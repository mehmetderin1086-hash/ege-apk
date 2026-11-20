"""Durable, resource-bounded integration of queue, OCR and catalogue layers.

Book pairs are processed by a bounded worker pool. SQLite leases, process-wide
semaphores and the inter-process heavy-model lock coordinate all jobs without
keeping a 250-book chunk in memory.
"""

from __future__ import annotations

import hashlib
import itertools
import json
import mimetypes
import os
import re
import shutil
import tempfile
import threading
import time
import unicodedata
from collections.abc import Callable, Iterable, Iterator, Mapping
from concurrent.futures import ThreadPoolExecutor
from contextlib import AbstractContextManager, contextmanager, nullcontext, suppress
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from kitapkatalog.catalog import Catalog
from kitapkatalog.config import RuntimeLimits
from kitapkatalog.consensus import ConsensusSpan as PipelineConsensusSpan
from kitapkatalog.database import Database, LeaseLostError, StateConflictError
from kitapkatalog.domain import (
    BOOK_SURFACE_ORDER,
    UNKNOWN_VALUE,
    BookInput,
    ContributorInput,
    ContributorRole,
    CopyInput,
    CoverRole,
    FieldObservation,
    FieldStatus,
    IdentifierInput,
    ImagePair,
    ImportJob,
    JobItem,
    JobItemStage,
    OcrEngine,
    PersistedConsensusSpan,
    StorageMode,
)
from kitapkatalog.extractor import (
    EvidenceBoundExtractor,
    EvidenceToken,
    ExtractedField,
    ExtractionResult,
)
from kitapkatalog.images import CoverPreprocessor, PreparedImage, sha256_file
from kitapkatalog.isbn import canonical_isbn, merge_isbn_evidence
from kitapkatalog.ocr.contracts import (
    CLASSIC_ENGINE_IDS,
    REQUIRED_ENGINE_IDS,
)
from kitapkatalog.pipeline import (
    CoverPipelineResult,
    EngineCheckpoint,
    FiveOcrPipeline,
    PairPipelineResult,
)
from kitapkatalog.resources import (
    HEAVY_ENGINE_IDS,
    MemoryAdmissionController,
    ResourceLimitError,
    model_admission,
)


class SchedulerError(RuntimeError):
    """An item could not be safely completed."""


class RawCheckpointError(SchedulerError):
    """A DB checkpoint referred to a missing/non-durable OCR result."""


class HeartbeatLostError(LeaseLostError):
    """The background lease heartbeat was rejected."""


# These process-wide limits apply across jobs and scheduler instances.
_PREPROCESSOR_SEMAPHORE = threading.BoundedSemaphore(2)
_ENGINE_CAPACITIES: dict[str, int] = {
    "rapidocr_ppocrv6": 1,
    "tesseract": 2,
    "easyocr": 1,
    "paddleocr_vl": 1,
    "surya": 1,
}
_ENGINE_SEMAPHORES: dict[str, threading.BoundedSemaphore] = {
    engine_id: threading.BoundedSemaphore(capacity)
    for engine_id, capacity in _ENGINE_CAPACITIES.items()
}

_BOOK_STRING_FIELDS: tuple[str, ...] = (
    "title",
    "subtitle",
    "original_title",
    "publisher",
    "imprint",
    "series",
    "volume",
    "language",
    "publication_place",
    "publication_date",
    "edition_statement",
    "printing_number",
    "printer",
    "binding",
    "dimensions",
    "price_amount",
    "currency",
    "blurb",
    "awards",
    "quotations",
)

_FIELD_TO_COLUMN: dict[str, str] = {
    "title": "title",
    "subtitle": "subtitle",
    "original_title": "original_title",
    "publisher": "publisher",
    "imprint": "imprint",
    "series": "series",
    "volume": "volume",
    "language": "language",
    "publication_place": "publication_place",
    "publication_date": "publication_date",
    "edition_statement": "edition_statement",
    "printing_number": "printing_number",
    "printer": "printer",
    "binding": "binding",
    "page_count": "page_count",
    "dimensions": "dimensions",
    "printed_price": "price_amount",
    "price_amount": "price_amount",
    "currency": "currency",
    "synopsis": "blurb",
    "blurb": "blurb",
    "awards": "awards",
    "quotations": "quotations",
}

_CONTRIBUTOR_ROLES: dict[str, ContributorRole] = {
    "author": ContributorRole.AUTHOR,
    "translator": ContributorRole.TRANSLATOR,
    "editor": ContributorRole.EDITOR,
    "compiler": ContributorRole.COMPILER,
    "illustrator": ContributorRole.ILLUSTRATOR,
    "foreword": ContributorRole.FOREWORD,
    "other": ContributorRole.OTHER,
}


def _nfc(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip()


def _normalized_field_value(field_name: str, value: str) -> str | None:
    normalized = _nfc(value)
    if field_name != "page_count":
        return normalized or None
    match = re.fullmatch(
        r"(?i)\s*(?:sayfa\s*[:\-]?\s*)?(\d{1,5})"
        r"(?:\s*(?:sayfa|pages?|pp\.?))?\s*",
        normalized,
    )
    if match is None:
        return None
    return str(int(match.group(1)))


def _batched(values: Iterator[ImagePair], size: int) -> Iterator[tuple[ImagePair, ...]]:
    while batch := tuple(itertools.islice(values, size)):
        yield batch


def _acquire(
    semaphore: threading.BoundedSemaphore,
    *,
    timeout: float | None,
    description: str,
    cancel: threading.Event | None = None,
) -> None:
    if cancel is None:
        acquired = semaphore.acquire() if timeout is None else semaphore.acquire(timeout=timeout)
        if not acquired:
            raise ResourceLimitError(f"{description} çalışma yuvası bekleme süresi doldu")
        return
    started = time.monotonic()
    while not cancel.is_set():
        remaining = None if timeout is None else timeout - (time.monotonic() - started)
        if remaining is not None and remaining <= 0:
            break
        if semaphore.acquire(timeout=min(0.2, remaining) if remaining is not None else 0.2):
            return
    if cancel.is_set():
        raise ResourceLimitError(f"{description} çalışma yuvası beklemesi iptal edildi")
    raise ResourceLimitError(f"{description} çalışma yuvası bekleme süresi doldu")


@dataclass(slots=True)
class SchedulerResources:
    """Shared admission policy for preprocessing, OCR and Qwen extraction."""

    controller: MemoryAdmissionController
    heavy_lock_path: Path
    admission_timeout_seconds: float | None = None
    cancel: threading.Event | None = None

    @classmethod
    def create(
        cls,
        *,
        lock_root: str | Path,
        limits: RuntimeLimits | None = None,
        admission_timeout_seconds: float | None = None,
        cancel: threading.Event | None = None,
    ) -> SchedulerResources:
        return cls(
            controller=MemoryAdmissionController(limits),
            heavy_lock_path=Path(lock_root) / "heavy-model.lock",
            admission_timeout_seconds=admission_timeout_seconds,
            cancel=cancel,
        )

    @contextmanager
    def preprocess_admission(self) -> Iterator[None]:
        _acquire(
            _PREPROCESSOR_SEMAPHORE,
            timeout=self.admission_timeout_seconds,
            description="Ön işleme",
            cancel=self.cancel,
        )
        try:
            self.controller.wait_for_capacity(
                timeout=self.admission_timeout_seconds,
                cancel=self.cancel,
            )
            yield
        finally:
            _PREPROCESSOR_SEMAPHORE.release()

    @contextmanager
    def engine_admission(self, engine_id: str) -> Iterator[Any]:
        """Limit one cache-miss inference; cached results never enter here."""

        if engine_id not in REQUIRED_ENGINE_IDS:
            raise SchedulerError(f"Bilinmeyen OCR motoru için kaynak isteği: {engine_id}")
        semaphore = _ENGINE_SEMAPHORES[engine_id]
        _acquire(
            semaphore,
            timeout=self.admission_timeout_seconds,
            description=engine_id,
            cancel=self.cancel,
        )
        try:
            with model_admission(
                engine_id,
                controller=self.controller,
                lock_path=self.heavy_lock_path,
                timeout=self.admission_timeout_seconds,
                cancel=self.cancel,
            ) as snapshot:
                yield snapshot
        finally:
            semaphore.release()

    def extraction_admission(self, *, enabled: bool) -> AbstractContextManager[Any]:
        if not enabled:
            return nullcontext()
        return model_admission(
            "qwen3_field_extractor",
            controller=self.controller,
            lock_path=self.heavy_lock_path,
            timeout=self.admission_timeout_seconds,
            cancel=self.cancel,
        )

    @contextmanager
    def extraction_phase(
        self,
        *,
        registry: Any,
        enabled: bool,
    ) -> Iterator[Any]:
        """Drain every OCR slot before releasing heavy models and loading Qwen.

        Every slot is drained so no OCR call is in flight while Qwen holds the
        heavy-model admission.  Only the heavy engines are unloaded, though:
        the light in-process engines hold no headroom worth reclaiming, and
        dropping them would make every book pay to load them again.
        """

        acquired: list[threading.BoundedSemaphore] = []
        try:
            for engine_id in REQUIRED_ENGINE_IDS:
                semaphore = _ENGINE_SEMAPHORES[engine_id]
                for _slot in range(_ENGINE_CAPACITIES[engine_id]):
                    _acquire(
                        semaphore,
                        timeout=self.admission_timeout_seconds,
                        description=f"{engine_id} Qwen bariyeri",
                    )
                    acquired.append(semaphore)
            registry.release_all(only=HEAVY_ENGINE_IDS)
            try:
                with self.extraction_admission(enabled=enabled) as snapshot:
                    yield snapshot
            except ResourceLimitError:
                # Releasing only the heavy engines usually leaves ample room,
                # but it removes the guarantee the full release used to give.
                # If Qwen still cannot be admitted, drop everything and retry
                # once rather than failing this book and every one after it.
                registry.release_all()
                with self.extraction_admission(enabled=enabled) as snapshot:
                    yield snapshot
        finally:
            for semaphore in reversed(acquired):
                semaphore.release()

    def configure_pipeline(self, pipeline: FiveOcrPipeline) -> None:
        if not isinstance(pipeline.preprocessor, ResourceAwarePreprocessor):
            pipeline.preprocessor = ResourceAwarePreprocessor(pipeline.preprocessor, self)
        pipeline.engine_admission = self.engine_admission


class ResourceAwarePreprocessor:
    """Two-slot wrapper around the deterministic canonical-cover preprocessor."""

    def __init__(
        self,
        delegate: CoverPreprocessor,
        resources: SchedulerResources,
    ) -> None:
        self.delegate = delegate
        self.resources = resources
        self._primed: dict[Path, list[PreparedImage]] = {}
        self._lock = threading.Lock()

    def prepare(self, source_path: str | Path) -> PreparedImage:
        key = Path(source_path).expanduser().resolve()
        with self._lock:
            prepared_items = self._primed.get(key)
            if prepared_items:
                prepared = prepared_items.pop(0)
                if not prepared_items:
                    self._primed.pop(key, None)
                return prepared
        with self.resources.preprocess_admission():
            return self.delegate.prepare(key)

    def prepare_and_prime(self, source_path: str | Path) -> PreparedImage:
        """Prepare once for DB metadata, then hand the same object to the pipeline."""

        key = Path(source_path).expanduser().resolve()
        with self.resources.preprocess_admission():
            prepared = self.delegate.prepare(key)
        with self._lock:
            self._primed.setdefault(key, []).append(prepared)
        return prepared

    def __getattr__(self, name: str) -> Any:
        return getattr(self.delegate, name)


class LeaseHeartbeat:
    """Extend an item lease while a long OCR/model call is in progress."""

    def __init__(
        self,
        database: Database,
        item_id: int,
        worker_id: str,
        *,
        lease_seconds: int,
        heartbeat: Callable[..., bool] | None = None,
    ) -> None:
        self.database = database
        self.item_id = item_id
        self.worker_id = worker_id
        # Varsayılan görüntü kuyruğudur; ses kuyruğu heartbeat_voice_item verir.
        self._heartbeat = heartbeat if heartbeat is not None else database.heartbeat_item
        self.lease_seconds = max(1, int(lease_seconds))
        self.interval = min(30.0, max(0.25, self.lease_seconds / 3))
        self._stop = threading.Event()
        self._lost = threading.Event()
        self._error: BaseException | None = None
        self._thread = threading.Thread(
            target=self._run,
            name=f"kitapkatalog-heartbeat-{item_id}",
            daemon=True,
        )

    def start(self) -> None:
        self._thread.start()

    def _run(self) -> None:
        while not self._stop.wait(self.interval):
            try:
                if not self._heartbeat(
                    self.item_id,
                    self.worker_id,
                    lease_seconds=self.lease_seconds,
                ):
                    self._lost.set()
                    return
            except BaseException as exc:  # stored and raised on the owning worker
                self._error = exc
                self._lost.set()
                return

    def raise_if_lost(self) -> None:
        if self._lost.is_set():
            detail = f": {self._error}" if self._error is not None else ""
            raise HeartbeatLostError(f"Öğe lease heartbeat'i kaybedildi{detail}")

    def stop(self, *, check: bool = False) -> None:
        self._stop.set()
        if self._thread.is_alive():
            self._thread.join(timeout=max(1.0, self.interval * 2))
        if check:
            self.raise_if_lost()


@dataclass(frozen=True, slots=True)
class ScheduledItemResult:
    item_id: int
    job_id: str
    stage: JobItemStage
    edition_id: int | None
    cache_hits: int
    error: str | None = None

    @property
    def terminal(self) -> bool:
        return self.stage.terminal


@dataclass(frozen=True, slots=True)
class SchedulerRunSummary:
    job: ImportJob
    claims: int
    cache_hits: int


@dataclass(frozen=True, slots=True)
class SchedulerBatchSummary:
    claims: int
    cache_hits: int


@dataclass(frozen=True, slots=True)
class _FieldEvidence:
    role: CoverRole
    spans: tuple[PipelineConsensusSpan, ...]
    confidence: float
    polygon: tuple[tuple[float, float], ...] | None
    source_polygon: tuple[tuple[float, float], ...] | None
    source_token_ids: tuple[str, ...]
    engines: tuple[OcrEngine, ...]


@dataclass(frozen=True, slots=True)
class _FieldResolutionCandidate:
    field: ExtractedField
    path: str
    value: str
    evidence: _FieldEvidence
    status: FieldStatus
    observation_id: int | None = None


class DurableScheduler:
    """Run leased book pairs through strict five-OCR and grounded extraction."""

    def __init__(
        self,
        *,
        database: Database,
        pipeline: FiveOcrPipeline,
        extractor: EvidenceBoundExtractor,
        asset_root: str | Path,
        resources: SchedulerResources,
        limits: RuntimeLimits | None = None,
        require_raw_checkpoints: bool = True,
        retry_delay_seconds: int = 0,
    ) -> None:
        self.database = database
        self.catalog = Catalog(database)
        self.pipeline = pipeline
        self.extractor = extractor
        self.asset_root = Path(asset_root)
        self.resources = resources
        self.limits = limits or RuntimeLimits()
        self.require_raw_checkpoints = require_raw_checkpoints
        self.retry_delay_seconds = max(0, int(retry_delay_seconds))
        self.asset_root.mkdir(parents=True, exist_ok=True)
        self.resources.configure_pipeline(self.pipeline)

    def enqueue(
        self,
        name: str,
        pairs: Iterable[ImagePair],
        *,
        storage_mode: StorageMode | str = StorageMode.MANAGED_COPY,
        idempotency_key: str | None = None,
        config_hash: str | None = None,
        chunk_size: int | None = None,
        location: str | None = None,
        locations: Mapping[str, str] | None = None,
    ) -> ImportJob:
        """Persist an arbitrary-size iterator in independent <=250 item chunks.

        ``location`` bütün partinin dolabıdır; ``locations`` tek tek kitapların
        (eşleştirme anahtarına göre) dolabını belirler ve partiyi ezer.
        """

        if idempotency_key:
            row = self.database.fetchone(
                "SELECT id FROM import_job WHERE idempotency_key = ?",
                (idempotency_key,),
            )
            if row is not None:
                existing = self.database.get_import_job(str(row["id"]))
                assert existing is not None
                return existing

        size = min(250, max(1, int(chunk_size or self.limits.chunk_books)))
        iterator = iter(pairs)
        first = tuple(itertools.islice(iterator, size))
        job = self.database.create_import_job(
            name,
            first,
            storage_mode=storage_mode,
            idempotency_key=idempotency_key,
            config_hash=config_hash or self.pipeline.config.digest(),
            location=location,
            locations=locations,
        )
        for chunk in _batched(iterator, size):
            self.database.append_job_items(job.id, chunk, locations=locations)
        refreshed = self.database.get_import_job(job.id)
        assert refreshed is not None
        return refreshed

    def run_next(
        self,
        worker_id: str,
        *,
        job_id: str | None = None,
    ) -> ScheduledItemResult | None:
        item = self.database.claim_next_item(
            worker_id,
            job_id=job_id,
            lease_seconds=self.limits.lease_seconds,
        )
        if item is None:
            return None
        return self.process_claimed_item(item, worker_id)

    def run_job(self, job_id: str, *, worker_id: str) -> SchedulerRunSummary:
        totals = self._run_worker_pool(job_id=job_id, worker_prefix=worker_id)
        job = self.database.get_import_job(job_id)
        if job is None:
            raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
        return SchedulerRunSummary(
            job=job,
            claims=totals.claims,
            cache_hits=totals.cache_hits,
        )

    def run_all(self, *, worker_id: str) -> SchedulerBatchSummary:
        """Consume all currently runnable jobs with bounded book parallelism."""

        return self._run_worker_pool(job_id=None, worker_prefix=worker_id)

    def _run_worker_pool(
        self,
        *,
        job_id: str | None,
        worker_prefix: str,
    ) -> SchedulerBatchSummary:
        workers = max(
            1,
            min(
                int(self.limits.book_workers),
                int(self.limits.microbatch_pairs),
            ),
        )

        def consume(worker_number: int) -> tuple[int, int]:
            worker_id = f"{worker_prefix}-{worker_number + 1}"
            claims = 0
            cache_hits = 0
            while result := self.run_next(worker_id, job_id=job_id):
                claims += 1
                cache_hits += result.cache_hits
            return claims, cache_hits

        if workers == 1:
            claims, cache_hits = consume(0)
            return SchedulerBatchSummary(claims=claims, cache_hits=cache_hits)
        with ThreadPoolExecutor(
            max_workers=workers,
            thread_name_prefix="kitapkatalog-book",
        ) as executor:
            totals = tuple(executor.map(consume, range(workers)))
        return SchedulerBatchSummary(
            claims=sum(item[0] for item in totals),
            cache_hits=sum(item[1] for item in totals),
        )

    def process_claimed_item(
        self,
        item: JobItem,
        worker_id: str,
    ) -> ScheduledItemResult:
        if item.lease_owner != worker_id:
            raise LeaseLostError("İş öğesi bu worker tarafından claim edilmemiş")

        heartbeat = LeaseHeartbeat(
            self.database,
            item.id,
            worker_id,
            lease_seconds=self.limits.lease_seconds,
        )
        heartbeat.start()
        cache_hits = 0
        heartbeat_stopped = False
        try:
            result = self._process_item(item, worker_id, heartbeat)
            cache_hits = result.front.cache_hits + result.back.cache_hits
            latest = self.database.get_job_item(item.id)
            if latest is None:
                raise SchedulerError(f"İş öğesi kayboldu: {item.id}")
            if latest.stage != JobItemStage.EXTRACTED:
                raise SchedulerError(f"Terminal geçiş öncesi beklenmeyen aşama: {latest.stage}")
            review = self._needs_review(result, latest.edition_id)
            heartbeat.stop(check=True)
            heartbeat_stopped = True
            target = JobItemStage.REVIEW if review else JobItemStage.COMPLETED
            completed = self.database.advance_item(
                item.id,
                worker_id,
                target,
                expected_stage=JobItemStage.EXTRACTED,
                release=True,
            )
            return ScheduledItemResult(
                item_id=item.id,
                job_id=item.job_id,
                stage=completed.stage,
                edition_id=completed.edition_id,
                cache_hits=cache_hits,
            )
        except Exception as exc:
            if not heartbeat_stopped:
                heartbeat.stop(check=False)
            failed = self._checkpoint_item_error(item.id, worker_id, exc)
            return ScheduledItemResult(
                item_id=item.id,
                job_id=item.job_id,
                stage=failed.stage,
                edition_id=failed.edition_id,
                cache_hits=cache_hits,
                error=str(exc),
            )
        finally:
            if not heartbeat_stopped:
                heartbeat.stop(check=False)

    def _process_item(
        self,
        claimed: JobItem,
        worker_id: str,
        heartbeat: LeaseHeartbeat,
    ) -> PairPipelineResult:
        job = self.database.get_import_job(claimed.job_id)
        if job is None:
            raise SchedulerError(f"İçe aktarma işi kayboldu: {claimed.job_id}")
        latest = self.database.get_job_item(claimed.id)
        if latest is None:
            raise SchedulerError(f"İş öğesi kayboldu: {claimed.id}")
        if latest.stage == JobItemStage.DISCOVERED:
            latest = self.database.advance_item(
                latest.id,
                worker_id,
                JobItemStage.PAIRED,
                expected_stage=JobItemStage.DISCOVERED,
            )

        source_paths = self._item_source_paths(latest)
        inputs = {
            role: self._materialize(source, mode=job.storage_mode)
            for role, source in source_paths.items()
        }
        heartbeat.raise_if_lost()

        prepared = {role: self._prepare_and_prime(path) for role, path in inputs.items()}
        assets = {
            role: self._register_asset(
                latest,
                role,
                prepared[role],
                source_path=source_paths[role],
                managed_path=(
                    inputs[role] if job.storage_mode == StorageMode.MANAGED_COPY else None
                ),
            )
            for role in source_paths
        }
        if latest.stage == JobItemStage.PAIRED:
            latest = self.database.advance_item(
                latest.id,
                worker_id,
                JobItemStage.PREPROCESSED,
                expected_stage=JobItemStage.PAIRED,
            )
        elif latest.stage not in {
            JobItemStage.PREPROCESSED,
            JobItemStage.OCR_COMPLETE,
            JobItemStage.RECONCILED,
            JobItemStage.EXTRACTED,
        }:
            raise SchedulerError(f"İşlenemeyen resume aşaması: {latest.stage}")

        previous_result_handler = self.pipeline.result_handler
        previous_event_handler = self.pipeline.event_handler

        def checkpoint_handler(checkpoint: EngineCheckpoint) -> None:
            if checkpoint.cover_role not in {role.value for role in source_paths}:
                raise SchedulerError("OCR checkpointinin kapak rolü bilinmiyor")
            role = CoverRole(checkpoint.cover_role)
            heartbeat.raise_if_lost()
            self._record_engine_checkpoint(
                latest.id,
                worker_id,
                role,
                checkpoint,
            )
            if previous_result_handler is not None:
                previous_result_handler(checkpoint)

        def event_handler(event: Any) -> None:
            role = (
                CoverRole(event.cover_role)
                if event.cover_role in {value.value for value in source_paths}
                else None
            )
            if role is not None and event.stage == "engine_retry" and event.engine_id is not None:
                current = self.database.get_job_item(latest.id)
                if current is not None and current.stage in {
                    JobItemStage.PREPROCESSED,
                    JobItemStage.OCR_COMPLETE,
                }:
                    self.database.record_engine_failure(
                        latest.id,
                        role,
                        OcrEngine(event.engine_id),
                        event.message or "OCR motoru başarısız",
                        max_retries=self.pipeline.config.max_retries,
                        worker_id=worker_id,
                    )
            if previous_event_handler is not None:
                previous_event_handler(event)

        with (
            self.pipeline.callbacks(
                result_handler=checkpoint_handler,
                event_handler=event_handler,
            ),
            # One model load per batch-capable engine for the whole book instead
            # of one per surface; the per-surface loop below is unchanged.
            self.pipeline.warm_covers(list(inputs.values())),
        ):
            results = {
                role: self.pipeline.process_cover(path, cover_role=role.value)
                for role, path in inputs.items()
            }

        if any(
            results[role].prepared.source_sha256 != prepared[role].source_sha256
            for role in source_paths
        ):
            raise SchedulerError("Kapak kaynağı ön işleme ile OCR arasında değişti")
        if job.storage_mode == StorageMode.REFERENCE and any(
            sha256_file(inputs[role]) != results[role].prepared.source_sha256
            for role in source_paths
        ):
            raise SchedulerError("Başvurulan kapak OCR sırasında değiştirildi")

        pair = self._pair_result(results)
        if any(not cover.five_ocr_complete for cover in results.values()):
            raise SchedulerError("Kitabın bütün yüzlerinde beş OCR sonucu tamamlanmadı")
        latest = self.database.get_job_item(latest.id)
        if latest is None or latest.stage not in {
            JobItemStage.OCR_COMPLETE,
            JobItemStage.RECONCILED,
            JobItemStage.EXTRACTED,
        }:
            raise SchedulerError("Veritabanı bütün kitap yüzleri × beş motor kapısını doğrulamadı")

        for role, result in results.items():
            self._store_consensus(assets[role], result)
        if latest.stage == JobItemStage.OCR_COMPLETE:
            latest = self.database.advance_item(
                latest.id,
                worker_id,
                JobItemStage.RECONCILED,
                expected_stage=JobItemStage.OCR_COMPLETE,
            )

        heartbeat.raise_if_lost()
        evidence_tokens, evidence_map = self._evidence_tokens(pair)
        # No OCR inference/model may overlap the Qwen extraction phase.
        with self.resources.extraction_phase(
            registry=self.pipeline.registry,
            enabled=self.extractor.model_client is not None,
        ):
            extraction = self.extractor.extract(evidence_tokens)

        fingerprint = self._source_fingerprint(tuple(prepared[role] for role in source_paths))
        # Öğe dolabı (klasörden türetilen) işin parti dolabını ezer. İşin
        # dolabı OCR sürerken değişmiş olabileceği için tazesi okunur; öğe
        # alındığında okunan `job` nesnesi dakikalarca bayat kalabilir.
        current_job = self.database.get_import_job(job.id) or job
        book = self._book_input(
            extraction,
            pair,
            fingerprint,
            evidence_map,
            location=latest.location or current_job.location,
        )
        record = self.catalog.save_book(
            book,
            source_fingerprint=fingerprint,
            add_copy=True,
            overwrite=False,
        )
        heartbeat.raise_if_lost()
        latest = self.database.link_item_edition(
            latest.id,
            worker_id,
            record.edition_id,
            expected_stage=latest.stage,
        )
        self.catalog.set_cover_paths(
            record.edition_id,
            front_path=inputs[CoverRole.FRONT],
            front_inside_path=inputs.get(CoverRole.FRONT_INSIDE),
            back_inside_path=inputs.get(CoverRole.BACK_INSIDE),
            back_path=inputs[CoverRole.BACK],
        )
        self.catalog.set_raw_ocr_text(
            record.edition_id,
            "\n".join(
                results[role].consensus.raw_text
                for role in source_paths
                if results[role].consensus.raw_text
            ).strip(),
        )
        self._persist_fields(
            item_id=latest.id,
            edition_id=record.edition_id,
            extraction=extraction,
            pair=pair,
            evidence_map=evidence_map,
        )
        review = self._extraction_needs_review(extraction, pair, evidence_map)
        self.catalog.update_book(
            record.edition_id,
            {"review_status": "review" if review else "completed"},
            user_edit=False,
        )
        for role in source_paths:
            self._register_asset(
                latest,
                role,
                results[role].prepared,
                source_path=source_paths[role],
                managed_path=(
                    inputs[role] if job.storage_mode == StorageMode.MANAGED_COPY else None
                ),
                edition_id=record.edition_id,
            )

        latest = self.database.get_job_item(latest.id)
        assert latest is not None
        if latest.stage == JobItemStage.RECONCILED:
            self.database.advance_item(
                latest.id,
                worker_id,
                JobItemStage.EXTRACTED,
                expected_stage=JobItemStage.RECONCILED,
                edition_id=record.edition_id,
            )
        elif latest.stage == JobItemStage.EXTRACTED:
            if latest.edition_id not in {None, record.edition_id}:
                raise SchedulerError("Resume sırasında baskı kimliği değişti")
        else:
            raise SchedulerError(f"Alan çıkarımı sonrası beklenmeyen aşama: {latest.stage}")
        return pair

    @staticmethod
    def _item_source_paths(item: JobItem) -> dict[CoverRole, Path]:
        candidates = {
            CoverRole.FRONT: item.front_path,
            CoverRole.FRONT_INSIDE: item.front_inside_path,
            CoverRole.BACK_INSIDE: item.back_inside_path,
            CoverRole.BACK: item.back_path,
        }
        return {role: path for role in BOOK_SURFACE_ORDER if (path := candidates[role]) is not None}

    def _prepare_and_prime(self, source_path: Path) -> PreparedImage:
        preprocessor = self.pipeline.preprocessor
        if isinstance(preprocessor, ResourceAwarePreprocessor):
            return preprocessor.prepare_and_prime(source_path)
        return preprocessor.prepare(source_path)

    def _record_engine_checkpoint(
        self,
        item_id: int,
        worker_id: str,
        role: CoverRole,
        checkpoint: EngineCheckpoint,
    ) -> None:
        current = self.database.get_job_item(item_id)
        if current is None:
            raise SchedulerError(f"İş öğesi kayboldu: {item_id}")
        # On reconciliation/extraction resume, the existing DB checkpoint is
        # already authoritative; loading its content cache must not rewrite it.
        if current.stage not in {
            JobItemStage.PREPROCESSED,
            JobItemStage.OCR_COMPLETE,
        }:
            return
        raw_path = checkpoint.raw_result_path
        if self.require_raw_checkpoints:
            if raw_path is None:
                raise RawCheckpointError(
                    f"{checkpoint.result.engine_id} için kalıcı .json.zst yolu yok"
                )
            if raw_path.suffixes[-2:] != [".json", ".zst"] or not raw_path.is_file():
                raise RawCheckpointError(
                    f"{checkpoint.result.engine_id} ham checkpointi eksik: {raw_path}"
                )
        self.database.record_engine_success(
            item_id,
            role,
            OcrEngine(checkpoint.result.engine_id),
            cache_key=checkpoint.cache_key,
            text=checkpoint.result.raw_text,
            raw_result_path=raw_path,
            duration_ms=checkpoint.result.duration_ms,
            worker_id=worker_id,
            model_digest=checkpoint.model_digest,
            config_hash=checkpoint.config_hash,
            preprocessing_version=checkpoint.prepared.preprocessing_version,
            normalized_text=_nfc(checkpoint.result.raw_text),
        )

    def _register_asset(
        self,
        item: JobItem,
        role: CoverRole,
        prepared: PreparedImage,
        *,
        source_path: Path,
        managed_path: Path | None,
        edition_id: int | None = None,
    ) -> int:
        mime_type = mimetypes.guess_type(prepared.source_path.name)[0] or "application/octet-stream"
        return self.database.register_image_asset(
            item.id,
            role,
            source_path=source_path,
            managed_path=managed_path,
            source_sha256=prepared.source_sha256,
            crop_sha256=prepared.crop_sha256,
            mime_type=mime_type,
            width=prepared.width,
            height=prepared.height,
            preprocessing_version=prepared.preprocessing_version,
            homography=prepared.homography_to_source,
            edition_id=edition_id,
        )

    def _materialize(self, source_path: Path, *, mode: StorageMode) -> Path:
        source = Path(source_path).expanduser().resolve()
        if not source.is_file():
            raise SchedulerError(f"Kaynak kapak bulunamadı: {source}")
        if mode == StorageMode.REFERENCE:
            return source
        digest = sha256_file(source)
        suffix = source.suffix.lower() or ".bin"
        target = self.asset_root / digest[:2] / f"{digest}{suffix}"
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            if sha256_file(target) != digest:
                raise SchedulerError(f"Yönetilen kopyanın hash'i bozuk: {target}")
            return target
        temporary: Path | None = None
        try:
            with (
                source.open("rb") as source_handle,
                tempfile.NamedTemporaryFile(
                    mode="wb",
                    dir=target.parent,
                    prefix=f".{target.name}.",
                    suffix=".part",
                    delete=False,
                ) as output,
            ):
                temporary = Path(output.name)
                shutil.copyfileobj(source_handle, output, length=1024 * 1024)
                output.flush()
                os.fsync(output.fileno())
            if sha256_file(temporary) != digest:
                raise SchedulerError("Kaynak dosya kopyalama sırasında değişti")
            temporary.replace(target)
            return target
        except BaseException:
            if temporary is not None:
                with suppress(OSError):
                    temporary.unlink(missing_ok=True)
            raise

    @staticmethod
    def _pair_result(
        results: dict[CoverRole, CoverPipelineResult],
    ) -> PairPipelineResult:
        covers = tuple(results[role] for role in BOOK_SURFACE_ORDER if role in results)
        isbns, pair_conflict = merge_isbn_evidence(
            tuple(candidate for cover in covers for candidate in cover.isbn_candidates),
            tuple(barcode for cover in covers for barcode in cover.barcodes),
        )
        conflict = any(cover.isbn_conflict for cover in covers) or pair_conflict
        return PairPipelineResult(
            front=results[CoverRole.FRONT],
            front_inside=results.get(CoverRole.FRONT_INSIDE),
            back_inside=results.get(CoverRole.BACK_INSIDE),
            back=results[CoverRole.BACK],
            isbns=isbns,
            isbn_conflict=conflict,
            stage="review" if conflict else "completed",
        )

    def _store_consensus(
        self,
        image_asset_id: int,
        cover: CoverPipelineResult,
    ) -> None:
        spans = (
            PersistedConsensusSpan(
                text=span.text,
                normalized_text=_nfc(span.text),
                confidence=span.confidence,
                source_token_ids=span.source_token_ids,
                polygon=span.polygon,
                source_polygon=span.source_polygon,
                engine_support=tuple(OcrEngine(value) for value in span.supporting_engines),
            )
            for span in cover.consensus.spans
        )
        self.database.replace_consensus_spans(image_asset_id, spans)

    @staticmethod
    def _source_fingerprint(images: tuple[PreparedImage, ...]) -> str:
        if not images:
            raise SchedulerError("Kaynak parmak izi için görüntü yok")
        payload = "\0".join(
            f"{image.source_sha256}:{image.preprocessing_version}" for image in images
        ).encode()
        return hashlib.sha256(payload).hexdigest()

    @staticmethod
    def _evidence_tokens(
        pair: PairPipelineResult,
    ) -> tuple[list[EvidenceToken], dict[str, tuple[CoverRole, PipelineConsensusSpan]]]:
        tokens: list[EvidenceToken] = []
        mapping: dict[str, tuple[CoverRole, PipelineConsensusSpan]] = {}
        for role, cover in pair.by_role.items():
            for index, span in enumerate(cover.consensus.spans):
                # Preserve every span in SQLite/raw evidence, but do not feed
                # low-confidence one-engine debris (cover art strokes, leaves,
                # texture) to the field model.  It cannot satisfy the
                # independent-engine acceptance gate and, on real covers, can
                # inflate a four-surface prompt beyond the local context.
                if len(span.supporting_engines) < 2 and span.confidence < 0.90:
                    continue
                token_id = f"{role.value}:{span.span_id}"
                mapping[token_id] = (role, span)
                tokens.append(
                    EvidenceToken(
                        token_id=token_id,
                        text=span.text,
                        cover=role.value,
                        polygon=span.polygon or (),
                        confidence=span.confidence,
                        line_index=index,
                    )
                )
        return tokens, mapping

    @staticmethod
    def _field_evidence(
        field: ExtractedField,
        mapping: dict[str, tuple[CoverRole, PipelineConsensusSpan]],
    ) -> _FieldEvidence | None:
        located = [
            mapping[token_id] for token_id in field.evidence_token_ids if token_id in mapping
        ]
        if not located or len(located) != len(field.evidence_token_ids):
            return None
        role = located[0][0]
        if any(located_role != role for located_role, _span in located):
            return None
        spans = tuple(span for _, span in located)
        polygons = [span.polygon for span in spans if span.polygon]
        polygon = _union_polygons(polygons)
        source_polygons = [span.source_polygon for span in spans if span.source_polygon]
        source_polygon = _union_polygons(source_polygons)
        source_ids = tuple(
            dict.fromkeys(source_id for span in spans for source_id in span.source_token_ids)
        )
        engines = tuple(
            dict.fromkeys(OcrEngine(engine) for span in spans for engine in span.supporting_engines)
        )
        confidence = min(field.confidence, *(span.confidence for span in spans))
        return _FieldEvidence(
            role=role,
            spans=spans,
            confidence=confidence,
            polygon=polygon,
            source_polygon=source_polygon,
            source_token_ids=source_ids,
            engines=engines,
        )

    def _book_input(
        self,
        extraction: ExtractionResult,
        pair: PairPipelineResult,
        fingerprint: str,
        mapping: dict[str, tuple[CoverRole, PipelineConsensusSpan]],
        location: str | None = None,
    ) -> BookInput:
        values: dict[str, Any] = {
            **{name: UNKNOWN_VALUE for name in _BOOK_STRING_FIELDS},
            "page_count": None,
        }
        chosen: dict[str, tuple[float, str]] = {}
        contributors: list[ContributorInput] = []
        contributor_seen: set[tuple[str, str]] = set()
        for field in extraction.fields:
            evidence = self._field_evidence(field, mapping)
            if evidence is None or evidence.confidence < 0.80:
                continue
            normalized_value = _normalized_field_value(field.field_name, field.value)
            if normalized_value is None:
                continue
            column = _FIELD_TO_COLUMN.get(field.field_name)
            if column is not None:
                current = chosen.get(column)
                if current is None or evidence.confidence > current[0]:
                    chosen[column] = (evidence.confidence, normalized_value)
                continue
            role_name = (
                field.field_name.removeprefix("contributor.")
                if field.field_name.startswith("contributor.")
                else field.field_name
            )
            role = _CONTRIBUTOR_ROLES.get(role_name)
            if role is not None:
                name = _nfc(field.value)
                key = (name.casefold(), role.value)
                if name and key not in contributor_seen:
                    contributor_seen.add(key)
                    contributors.append(
                        ContributorInput(
                            name=name,
                            role=role,
                            sort_order=len(contributors),
                        )
                    )
        for column, (_confidence, value) in chosen.items():
            values[column] = value
        barcode_isbns = {
            canonical
            for cover in pair.covers
            for observation in cover.barcodes
            if observation.isbn
            if (canonical := canonical_isbn(observation.isbn)) is not None
        }
        identifiers_list: list[IdentifierInput] = []
        for isbn in pair.isbns:
            source = "barcode"
            if isbn not in barcode_isbns:
                matching_evidence = next(
                    (
                        evidence
                        for field in extraction.fields
                        if field.field_name == "isbn_candidate"
                        if canonical_isbn(field.value) == isbn
                        if (evidence := self._field_evidence(field, mapping)) is not None
                        if _field_status(evidence) == FieldStatus.AUTO
                    ),
                    None,
                )
                if matching_evidence is None:
                    # The ISBN remains visible in OCR/review evidence, but a
                    # raw-text vote without positioned consensus provenance is
                    # not an automatic catalogue identifier.
                    continue
                source = "ocr_corroborated"
            identifiers_list.append(
                IdentifierInput(
                    scheme="ISBN13" if len(isbn) == 13 else "ISBN10",
                    value=isbn,
                    source=source,
                    confidence=0.99 if not pair.isbn_conflict else 0.80,
                )
            )
        identifiers = tuple(identifiers_list)
        return BookInput(
            **values,
            contributors=tuple(contributors),
            identifiers=identifiers,
            copy=CopyInput(source_fingerprint=fingerprint, location=location),
        )

    def _persist_fields(
        self,
        *,
        item_id: int,
        edition_id: int,
        extraction: ExtractionResult,
        pair: PairPipelineResult,
        evidence_map: dict[str, tuple[CoverRole, PipelineConsensusSpan]],
    ) -> None:
        candidates_by_path: dict[str, list[_FieldResolutionCandidate]] = {}
        resolved_paths: set[str] = set()
        for candidate in self._resolution_candidates(extraction, evidence_map):
            observation = FieldObservation(
                field_path=candidate.path,
                raw_value=candidate.field.value,
                normalized_value=candidate.value,
                cover_role=candidate.evidence.role,
                confidence=candidate.evidence.confidence,
                source_token_ids=candidate.evidence.source_token_ids,
                engine_evidence=candidate.evidence.engines,
                polygon=candidate.evidence.polygon,
                source_polygon=candidate.evidence.source_polygon,
            )
            observation_id = self._add_observation_idempotent(
                observation,
                edition_id=edition_id,
                item_id=item_id,
            )
            candidates_by_path.setdefault(candidate.path, []).append(
                _FieldResolutionCandidate(
                    field=candidate.field,
                    path=candidate.path,
                    value=candidate.value,
                    evidence=candidate.evidence,
                    status=candidate.status,
                    observation_id=observation_id,
                )
            )

        for path, candidates in candidates_by_path.items():
            winner = _choose_field_candidate(path, candidates)
            self.catalog.resolve_field(
                edition_id,
                path,
                winner.value,
                status=winner.status,
                observation_id=winner.observation_id,
                resolver_version="five-ocr-qwen-v2",
            )
            resolved_paths.add(path)

        for isbn in pair.isbns:
            path = f"identifier.{'isbn13' if len(isbn) == 13 else 'isbn10'}"
            matching = next(
                (
                    field
                    for field in extraction.fields
                    if field.field_name == "isbn_candidate"
                    and "".join(
                        character for character in field.value if character.isalnum()
                    ).upper()
                    == isbn
                ),
                None,
            )
            evidence = (
                self._field_evidence(matching, evidence_map) if matching is not None else None
            )
            if evidence is not None:
                observation_id = self._add_observation_idempotent(
                    FieldObservation(
                        field_path=path,
                        raw_value=isbn,
                        normalized_value=isbn,
                        cover_role=evidence.role,
                        confidence=evidence.confidence,
                        source_token_ids=evidence.source_token_ids,
                        engine_evidence=evidence.engines,
                        polygon=evidence.polygon,
                        source_polygon=evidence.source_polygon,
                    ),
                    edition_id=edition_id,
                    item_id=item_id,
                )
                status = _field_status(evidence)
                self.catalog.resolve_field(
                    edition_id,
                    path,
                    isbn,
                    status=status,
                    observation_id=observation_id,
                    resolver_version="isbn-checksum-v1",
                )
                resolved_paths.add(path)

        for column in _BOOK_STRING_FIELDS:
            path = f"edition.{column}"
            if path not in resolved_paths:
                self.catalog.resolve_field(
                    edition_id,
                    path,
                    UNKNOWN_VALUE,
                    status=FieldStatus.UNRESOLVED,
                    resolver_version="absent-on-cover-v1",
                )

    def _resolution_candidates(
        self,
        extraction: ExtractionResult,
        evidence_map: dict[str, tuple[CoverRole, PipelineConsensusSpan]],
    ) -> list[_FieldResolutionCandidate]:
        candidates: list[_FieldResolutionCandidate] = []
        for field in extraction.fields:
            evidence = self._field_evidence(field, evidence_map)
            if evidence is None:
                continue
            value = _normalized_field_value(field.field_name, field.value)
            if value is None:
                continue
            candidates.append(
                _FieldResolutionCandidate(
                    field=field,
                    path=_canonical_field_path(field.field_name),
                    value=value,
                    evidence=evidence,
                    status=_field_status(evidence),
                )
            )
        return candidates

    def _add_observation_idempotent(
        self,
        observation: FieldObservation,
        *,
        edition_id: int,
        item_id: int,
    ) -> int:
        """Reuse evidence when the same source pair is replayed from cache.

        Token IDs alone are not globally unique: a new photograph of the same
        edition may legitimately produce the same adapter-local IDs.  Pair
        paths are therefore included in the replay identity.
        """

        source_ids = json.dumps(
            list(observation.source_token_ids),
            separators=(",", ":"),
        )
        engines = json.dumps(
            [engine.value for engine in observation.engine_evidence],
            separators=(",", ":"),
        )
        row = self.database.fetchone(
            """
            SELECT fo.id
            FROM field_observation AS fo
            JOIN job_item AS previous_item ON previous_item.id = fo.item_id
            JOIN job_item AS current_item ON current_item.id = ?
            WHERE fo.edition_id = ?
              AND fo.field_path = ?
              AND fo.normalized_value = ?
              AND fo.cover_role = ?
              AND fo.source_token_ids_json = ?
              AND fo.engine_evidence_json = ?
              AND previous_item.front_path = current_item.front_path
              AND previous_item.front_inside_path IS current_item.front_inside_path
              AND previous_item.back_inside_path IS current_item.back_inside_path
              AND previous_item.back_path = current_item.back_path
            ORDER BY fo.id
            LIMIT 1
            """,
            (
                item_id,
                edition_id,
                observation.field_path,
                observation.normalized_value,
                observation.cover_role.value,
                source_ids,
                engines,
            ),
        )
        if row is not None:
            return int(row["id"])
        return self.catalog.add_observation(
            observation,
            edition_id=edition_id,
            item_id=item_id,
        )

    def _extraction_needs_review(
        self,
        extraction: ExtractionResult,
        pair: PairPipelineResult,
        evidence_map: dict[str, tuple[CoverRole, PipelineConsensusSpan]],
    ) -> bool:
        if pair.isbn_conflict or extraction.rejected_model_fields:
            return True
        candidates = self._resolution_candidates(extraction, evidence_map)
        if len(candidates) != len(extraction.fields):
            return True
        by_path: dict[str, list[_FieldResolutionCandidate]] = {}
        for candidate in candidates:
            by_path.setdefault(candidate.path, []).append(candidate)
        winners = {path: _choose_field_candidate(path, values) for path, values in by_path.items()}
        title = winners.get("edition.title")
        if title is None or title.status == FieldStatus.UNRESOLVED:
            return True
        return any(winner.status != FieldStatus.AUTO for winner in winners.values())

    def _needs_review(
        self,
        pair: PairPipelineResult,
        edition_id: int | None,
    ) -> bool:
        if pair.isbn_conflict or edition_id is None:
            return True
        row = self.database.fetchone(
            "SELECT review_status FROM edition WHERE id = ?",
            (edition_id,),
        )
        return row is None or row["review_status"] != "completed"

    def _checkpoint_item_error(
        self,
        item_id: int,
        worker_id: str,
        error: BaseException,
    ) -> JobItem:
        latest = self.database.get_job_item(item_id)
        if latest is None:
            raise SchedulerError(f"Hata kaydı sırasında öğe kayboldu: {item_id}") from error
        if latest.stage.terminal:
            return latest
        if latest.lease_owner != worker_id:
            # Never overwrite another worker's state after losing the lease.
            return latest
        try:
            return self.database.fail_item(
                item_id,
                worker_id,
                f"{type(error).__name__}: {error}",
                max_retries=self.limits.max_retries,
                retry_delay_seconds=self.retry_delay_seconds,
            )
        except (LeaseLostError, StateConflictError):
            current = self.database.get_job_item(item_id)
            if current is None:
                raise
            return current


def _canonical_field_path(field_name: str) -> str:
    column = _FIELD_TO_COLUMN.get(field_name)
    if column is not None:
        return f"edition.{column}"
    if field_name == "isbn_candidate":
        return "identifier.isbn_candidate"
    if field_name.startswith("contributor."):
        return f"contributors.{field_name.removeprefix('contributor.')}"
    if field_name == "author":
        return "contributors.author"
    return f"claims.{field_name}"


def _field_status(evidence: _FieldEvidence) -> FieldStatus:
    engine_ids = {engine.value for engine in evidence.engines}
    classic_visual = bool(engine_ids.intersection(CLASSIC_ENGINE_IDS) and evidence.polygon)
    if (
        evidence.confidence >= 0.98
        and len(engine_ids) >= 2
        and classic_visual
        and evidence.source_token_ids
    ):
        return FieldStatus.AUTO
    if evidence.confidence >= 0.80:
        return FieldStatus.REVIEW
    return FieldStatus.UNRESOLVED


_FIELD_STATUS_RANK = {
    FieldStatus.UNRESOLVED: 0,
    FieldStatus.REVIEW: 1,
    FieldStatus.AUTO: 2,
    FieldStatus.CONFIRMED: 3,
}


def _candidate_rank(
    candidate: _FieldResolutionCandidate,
) -> tuple[int, float, int, int]:
    return (
        _FIELD_STATUS_RANK[candidate.status],
        candidate.evidence.confidence,
        len(candidate.evidence.engines),
        len(candidate.value),
    )


def _publisher_name_key(value: str) -> str:
    return "".join(
        "i" if character == "ı" else character
        for character in unicodedata.normalize("NFC", value).casefold()
        if character.isalnum()
    )


def _safe_publisher_name(candidate: _FieldResolutionCandidate) -> bool:
    value = candidate.value
    folded = value.casefold()
    return (
        candidate.status != FieldStatus.UNRESOLVED
        and candidate.evidence.confidence >= 0.90
        and len(candidate.evidence.engines) >= 2
        and not any(character.isdigit() for character in value)
        and not value.lstrip().startswith(("©", "®"))
        and not any(
            marker in folded
            for marker in (
                "tüm yayın hak",
                "copyright",
                "http",
                "www.",
                "tel.",
                "telefon",
                "cadde",
                "sokak",
            )
        )
    )


def _leading_integer(value: str) -> int | None:
    match = re.search(r"\b(\d{1,4})\b", value)
    return int(match.group(1)) if match else None


def _choose_field_candidate(
    path: str,
    candidates: Iterable[_FieldResolutionCandidate],
) -> _FieldResolutionCandidate:
    values = tuple(candidates)
    if not values:
        raise ValueError("Alan çözümlemesi için aday bulunamadı")
    winner = max(values, key=_candidate_rank)

    if path == "edition.title":
        winner = max(
            values,
            key=lambda candidate: (
                _FIELD_STATUS_RANK[candidate.status],
                candidate.evidence.confidence,
                len(candidate.evidence.engines),
                candidate.evidence.role == CoverRole.FRONT,
                len(candidate.value),
            ),
        )

    if path == "edition.publisher":
        safe_publishers = [candidate for candidate in values if _safe_publisher_name(candidate)]
        if safe_publishers:
            winner = max(safe_publishers, key=_candidate_rank)
        winner_key = _publisher_name_key(winner.value)
        expansions = [
            candidate
            for candidate in safe_publishers
            if winner_key and winner_key in _publisher_name_key(candidate.value)
        ]
        if expansions:
            winner = max(
                expansions,
                key=lambda candidate: (
                    len(_publisher_name_key(candidate.value)),
                    _candidate_rank(candidate),
                ),
            )

    if path in {
        "edition.publication_date",
        "edition.edition_statement",
        "edition.printing_number",
    }:
        top_status = max(_FIELD_STATUS_RANK[item.status] for item in values)
        numbered = [
            (number, candidate)
            for candidate in values
            if _FIELD_STATUS_RANK[candidate.status] == top_status
            if (number := _leading_integer(candidate.value)) is not None
        ]
        if numbered:
            winner = max(
                numbered,
                key=lambda item: (item[0], _candidate_rank(item[1])),
            )[1]
    return winner


def _union_polygons(
    polygons: Iterable[tuple[tuple[float, float], ...]],
) -> tuple[tuple[float, float], ...] | None:
    points = [point for polygon in polygons for point in polygon]
    if not points:
        return None
    left = min(point[0] for point in points)
    top = min(point[1] for point in points)
    right = max(point[0] for point in points)
    bottom = max(point[1] for point in points)
    return ((left, top), (right, top), (right, bottom), (left, bottom))
