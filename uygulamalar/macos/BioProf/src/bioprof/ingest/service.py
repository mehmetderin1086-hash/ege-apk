from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import tempfile
from contextlib import suppress
from pathlib import Path
from typing import Any

from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from bioprof.config import Settings
from bioprof.db.models import ChunkRecord, NotebookRecord, SourceRecord
from bioprof.domain.models import SourceStatus
from bioprof.ingest.chunking import chunk_blocks
from bioprof.ingest.models import (
    IngestionResult,
    PIIFinding,
    UnsafeSourceError,
    VectorIndexer,
)
from bioprof.ingest.parsers import ParserRegistry, detect_mime_type
from bioprof.ingest.security import SensitiveDataScanner

_SAFE_SUFFIX = re.compile(r"^\.[A-Za-z0-9]{1,10}$")


def _safe_display_name(name: str) -> str:
    value = Path(name).name.replace("\x00", "").strip()
    return (value or "source")[:500]


def _safe_title(title: str | None, fallback: str) -> str:
    value = " ".join((title or Path(fallback).stem or "Kaynak").split())
    return value[:500]


class IngestionService:
    """Transactional, local-only source ingestion and index maintenance."""

    def __init__(
        self,
        settings: Settings,
        session: Session,
        *,
        registry: ParserRegistry | None = None,
        scanner: SensitiveDataScanner | None = None,
        vector_indexer: VectorIndexer | None = None,
    ) -> None:
        self.settings = settings
        self.session = session
        self.registry = registry or ParserRegistry()
        self.scanner = scanner or SensitiveDataScanner()
        self.vector_indexer = vector_indexer
        self.settings.ensure_directories()

    def ingest_file(
        self,
        notebook_id: str,
        path: str | Path,
        *,
        filename: str | None = None,
        title: str | None = None,
        mime_type: str | None = None,
        source_uri: str | None = None,
        license: str | None = None,
        language: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> IngestionResult:
        source_path = Path(path)
        if source_path.is_symlink():
            raise UnsafeSourceError("Sembolik bağlantılar kaynak olarak kabul edilmez.")
        try:
            path_stat = source_path.stat()
        except OSError as exc:
            raise UnsafeSourceError("Kaynak dosya okunamıyor.") from exc
        if not stat.S_ISREG(path_stat.st_mode):
            raise UnsafeSourceError("Kaynak normal bir dosya olmalıdır.")
        if path_stat.st_size > self.settings.max_upload_mb * 1024 * 1024:
            raise UnsafeSourceError(
                f"Dosya {self.settings.max_upload_mb} MB yükleme sınırını aşıyor."
            )
        display_name = _safe_display_name(filename or source_path.name)
        display_suffix = Path(display_name).suffix
        suffix = display_suffix if _SAFE_SUFFIX.fullmatch(display_suffix) else ""
        staged_path, digest = self._copy_to_stage(source_path, suffix=suffix)
        try:
            return self._ingest_staged(
                notebook_id,
                staged_path,
                digest=digest,
                original_name=display_name,
                title=title,
                mime_type=detect_mime_type(Path(display_name), mime_type),
                source_uri=source_uri,
                license=license,
                language=language,
                metadata=metadata,
            )
        finally:
            staged_path.unlink(missing_ok=True)

    def ingest_bytes(
        self,
        notebook_id: str,
        data: bytes,
        *,
        filename: str,
        title: str | None = None,
        mime_type: str | None = None,
        source_uri: str | None = None,
        license: str | None = None,
        language: str | None = None,
        metadata: dict[str, Any] | None = None,
    ) -> IngestionResult:
        if len(data) > self.settings.max_upload_mb * 1024 * 1024:
            raise UnsafeSourceError(
                f"Dosya {self.settings.max_upload_mb} MB yükleme sınırını aşıyor."
            )
        display_name = _safe_display_name(filename)
        original_suffix = Path(display_name).suffix
        suffix = original_suffix if _SAFE_SUFFIX.fullmatch(original_suffix) else ""
        staged_path = self._new_stage(suffix=suffix)
        try:
            with staged_path.open("wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            digest = hashlib.sha256(data).hexdigest()
            return self._ingest_staged(
                notebook_id,
                staged_path,
                digest=digest,
                original_name=display_name,
                title=title,
                mime_type=detect_mime_type(Path(display_name), mime_type),
                source_uri=source_uri,
                license=license,
                language=language,
                metadata=metadata,
            )
        finally:
            staged_path.unlink(missing_ok=True)

    def _new_stage(self, *, suffix: str) -> Path:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=".ingest-", suffix=suffix, dir=self.settings.data_dir, delete=False
        ) as handle:
            path = Path(handle.name)
        os.chmod(path, 0o600)
        return path

    def _copy_to_stage(self, source_path: Path, *, suffix: str) -> tuple[Path, str]:
        staged_path = self._new_stage(suffix=suffix)
        digest = hashlib.sha256()
        flags = os.O_RDONLY
        if hasattr(os, "O_NOFOLLOW"):
            flags |= os.O_NOFOLLOW
        try:
            descriptor = os.open(source_path, flags)
            try:
                with (
                    os.fdopen(descriptor, "rb", closefd=True) as source,
                    staged_path.open("wb") as target,
                ):
                    copied = 0
                    while block := source.read(1024 * 1024):
                        copied += len(block)
                        if copied > self.settings.max_upload_mb * 1024 * 1024:
                            raise UnsafeSourceError(
                                f"Dosya {self.settings.max_upload_mb} MB yükleme sınırını aşıyor."
                            )
                        digest.update(block)
                        target.write(block)
                    target.flush()
                    os.fsync(target.fileno())
            except Exception:
                # fdopen owns descriptor once constructed; on construction errors
                # close explicitly without masking the ingestion exception.
                with suppress(OSError):
                    os.close(descriptor)
                raise
        except Exception:
            staged_path.unlink(missing_ok=True)
            raise
        return staged_path, digest.hexdigest()

    def _existing(self, notebook_id: str, digest: str) -> SourceRecord | None:
        return self.session.scalar(
            select(SourceRecord).where(
                SourceRecord.notebook_id == notebook_id,
                SourceRecord.sha256 == digest,
            )
        )

    def _duplicate_result(self, source: SourceRecord) -> IngestionResult:
        chunk_count = (
            self.session.scalar(
                select(func.count(ChunkRecord.id)).where(ChunkRecord.source_id == source.id)
            )
            or 0
        )
        try:
            source_status = SourceStatus(source.status)
        except ValueError:
            source_status = SourceStatus.FAILED
        return IngestionResult(
            source_id=source.id,
            status=source_status,
            sha256=source.sha256,
            title=source.title,
            mime_type=source.mime_type,
            parser=source.parser,
            chunk_count=int(chunk_count),
            deduplicated=True,
            error=source.error,
        )

    def _ingest_staged(
        self,
        notebook_id: str,
        staged_path: Path,
        *,
        digest: str,
        original_name: str,
        title: str | None,
        mime_type: str,
        source_uri: str | None,
        license: str | None,
        language: str | None,
        metadata: dict[str, Any] | None,
    ) -> IngestionResult:
        if self.session.get(NotebookRecord, notebook_id) is None:
            raise ValueError(f"Notebook bulunamadı: {notebook_id}")
        existing = self._existing(notebook_id, digest)
        if existing is not None:
            return self._duplicate_result(existing)

        safe_title = _safe_title(title, original_name)
        parser = None
        try:
            parser = self.registry.resolve(Path(original_name), mime_type)
            parsed = parser.parse(staged_path, title=safe_title)
            if not parsed.blocks or not any(block.text.strip() for block in parsed.blocks):
                raise ValueError("Ayrıştırıcı indekslenebilir içerik üretmedi.")
        except Exception as exc:
            from bioprof.ingest.models import UnsupportedFormatError

            if not isinstance(exc, (UnsupportedFormatError, UnsafeSourceError, ValueError)):
                exc = UnsupportedFormatError(f"Ayrıştırma başarısız: {type(exc).__name__}")
            quarantine_path = self._place_blob(staged_path, digest, quarantine=True)
            source = SourceRecord(
                notebook_id=notebook_id,
                title=safe_title,
                original_name=original_name,
                source_uri=source_uri,
                object_path=str(quarantine_path),
                sha256=digest,
                mime_type=mime_type,
                language=language or "und",
                license=license,
                status=SourceStatus.NEEDS_REVIEW.value,
                parser=parser.name if parser is not None else None,
                parser_version=parser.version if parser is not None else None,
                metadata_json=json.dumps(
                    {"quarantine_reason": "parser", "suffix": Path(original_name).suffix},
                    ensure_ascii=False,
                ),
                error=str(exc)[:2000],
            )
            self.session.add(source)
            self.session.commit()
            return IngestionResult(
                source_id=source.id,
                status=SourceStatus.NEEDS_REVIEW,
                sha256=digest,
                title=source.title,
                mime_type=mime_type,
                parser=parser.name if parser is not None else None,
                chunk_count=0,
                warnings=["Kaynak karantinaya alındı; manuel inceleme gerekiyor."],
                error=source.error,
            )

        context_text = "\n".join(
            [
                original_name,
                safe_title,
                json.dumps(parsed.metadata, ensure_ascii=False, default=str),
                json.dumps(metadata or {}, ensure_ascii=False, default=str),
            ]
        )
        findings = self._scan_blocks(parsed.blocks, context_text=context_text)
        if self.scanner.should_quarantine(findings):
            quarantine_path = self._place_blob(staged_path, digest, quarantine=True)
            metadata_value = dict(metadata or {})
            metadata_value.update(parsed.metadata)
            metadata_value.update(
                {
                    "quarantine_reason": "sensitive_data",
                    "finding_kinds": sorted({finding.kind for finding in findings}),
                    "suffix": Path(original_name).suffix,
                }
            )
            source = SourceRecord(
                notebook_id=notebook_id,
                title=parsed.title[:500],
                original_name=original_name,
                source_uri=source_uri,
                object_path=str(quarantine_path),
                sha256=digest,
                mime_type=mime_type,
                language=language or parsed.language,
                license=license,
                status=SourceStatus.QUARANTINED.value,
                parser=parsed.parser,
                parser_version=parsed.parser_version,
                metadata_json=json.dumps(metadata_value, ensure_ascii=False, default=str),
                error="Doğrudan tanımlayıcı kişisel/sağlık verisi tespit edildi.",
            )
            self.session.add(source)
            self.session.commit()
            return IngestionResult(
                source_id=source.id,
                status=SourceStatus.QUARANTINED,
                sha256=digest,
                title=source.title,
                mime_type=mime_type,
                parser=parsed.parser,
                chunk_count=0,
                findings=findings,
                warnings=["Kaynak indekslenmedi ve karantinaya alındı."],
                error=source.error,
            )

        prepared_chunks = chunk_blocks(
            parsed.blocks,
            target_chars=self.settings.chunk_target_chars,
            overlap_chars=self.settings.chunk_overlap_chars,
        )
        if not prepared_chunks:
            raise ValueError("Ayrıştırılmış kaynak boş.")
        object_path = self._place_blob(staged_path, digest, quarantine=False)
        metadata_value = dict(metadata or {})
        metadata_value.update(parsed.metadata)
        metadata_value["suffix"] = Path(original_name).suffix
        source = SourceRecord(
            notebook_id=notebook_id,
            title=parsed.title[:500],
            original_name=original_name,
            source_uri=source_uri,
            object_path=str(object_path),
            sha256=digest,
            mime_type=mime_type,
            language=language or parsed.language,
            license=license,
            status=SourceStatus.PROCESSING.value,
            parser=parsed.parser,
            parser_version=parsed.parser_version,
            metadata_json=json.dumps(metadata_value, ensure_ascii=False, default=str),
        )
        self.session.add(source)
        self.session.flush()
        chunk_records: list[ChunkRecord] = []
        for chunk in prepared_chunks:
            record = ChunkRecord(
                source_id=source.id,
                ordinal=chunk.ordinal,
                text=chunk.text,
                section=chunk.section,
                page=chunk.page,
                slide=chunk.slide,
                bbox_json=json.dumps(chunk.bbox) if chunk.bbox else None,
                timestamp_start=chunk.timestamp_start,
                timestamp_end=chunk.timestamp_end,
                sequence_start=chunk.sequence_start,
                sequence_end=chunk.sequence_end,
                token_count=chunk.token_count,
            )
            self.session.add(record)
            chunk_records.append(record)
        self.session.flush()
        self.session.execute(
            text(
                """
                INSERT INTO chunk_fts(chunk_id, source_id, notebook_id, title, section, text)
                VALUES (:chunk_id, :source_id, :notebook_id, :title, :section, :text)
                """
            ),
            [
                {
                    "chunk_id": chunk.id,
                    "source_id": source.id,
                    "notebook_id": notebook_id,
                    "title": source.title,
                    "section": chunk.section or "",
                    "text": chunk.text,
                }
                for chunk in chunk_records
            ],
        )
        source.status = SourceStatus.READY.value
        try:
            self.session.commit()
        except IntegrityError:
            self.session.rollback()
            existing = self._existing(notebook_id, digest)
            if existing is not None:
                return self._duplicate_result(existing)
            raise

        warnings: list[str] = []
        if findings:
            warnings.append(
                "Kaynakta kişisel tanımlayıcı olabilecek düşük/orta riskli alanlar tespit edildi."
            )
        if self.vector_indexer is not None:
            try:
                self.vector_indexer.upsert_chunks(chunk_records, notebook_id=notebook_id)
            except Exception as exc:  # optional acceleration must not corrupt FTS ingestion
                warnings.append(
                    "Vektör indeksi güncellenemedi; FTS/deterministik arama kullanılacak "
                    f"({type(exc).__name__})."
                )
        return IngestionResult(
            source_id=source.id,
            status=SourceStatus.READY,
            sha256=digest,
            title=source.title,
            mime_type=mime_type,
            parser=parsed.parser,
            chunk_count=len(chunk_records),
            findings=findings,
            warnings=warnings,
        )

    def _scan_blocks(
        self,
        blocks: list[Any],
        *,
        context_text: str = "",
    ) -> list[PIIFinding]:
        findings: list[PIIFinding] = []
        seen: set[tuple[str, str]] = set()
        values = [block.text for block in blocks]
        if context_text:
            values.append(context_text)
        for value in values:
            for finding in self.scanner.scan(value):
                key = (finding.kind, finding.excerpt)
                if key not in seen:
                    findings.append(finding)
                    seen.add(key)
                if len(findings) >= 100:
                    return findings
        return findings

    def _place_blob(self, staged_path: Path, digest: str, *, quarantine: bool) -> Path:
        root = self.settings.quarantine_dir if quarantine else self.settings.objects_dir
        directory = root / digest[:2]
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = directory / digest
        if target.exists():
            return target
        temporary = directory / f".{digest}.{os.getpid()}.tmp"
        shutil.copyfile(staged_path, temporary)
        os.chmod(temporary, 0o600)
        try:
            os.replace(temporary, target)
        finally:
            temporary.unlink(missing_ok=True)
        return target

    def delete_source(self, source_id: str) -> bool:
        source = self.session.get(SourceRecord, source_id)
        if source is None:
            return False
        if self.vector_indexer is not None:
            try:
                # Delete the acceleration index first. If this fails the source
                # remains authoritative in DB/FTS and deletion can be retried.
                self.vector_indexer.delete_source(source_id)
            except Exception as exc:
                raise ValueError(
                    f"Vektör türevi silinemedi: {type(exc).__name__}"
                ) from exc
        digest = source.sha256
        object_path = Path(source.object_path)
        self.session.execute(
            text("DELETE FROM chunk_fts WHERE source_id = :source_id"), {"source_id": source_id}
        )
        self.session.execute(delete(ChunkRecord).where(ChunkRecord.source_id == source_id))
        self.session.delete(source)
        self.session.commit()
        references = (
            self.session.scalar(
                select(func.count(SourceRecord.id)).where(SourceRecord.sha256 == digest)
            )
            or 0
        )
        if not references:
            resolved = object_path.resolve()
            roots = (self.settings.objects_dir.resolve(), self.settings.quarantine_dir.resolve())
            if any(resolved.is_relative_to(root) for root in roots):
                resolved.unlink(missing_ok=True)
        return True
