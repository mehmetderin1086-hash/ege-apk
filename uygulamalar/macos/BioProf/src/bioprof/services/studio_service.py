"""Stüdyo iş ailesi: kanıt seçimi → artifact üretimi → LLM cilası → medya.

`application.py`'nin tanrı sınıfından çıkarıldı. Sağlayıcı/LLM yaşam döngüsüne
sahip DEĞİLDİR: model kurulumunu, ses sentezini ve bellek iadesini uygulamadan
enjekte edilen geri çağırımlarla kullanır. `JobRecord.kind == "studio"`
sözleşmesi değişmedi; crash-recovery aynı adla bu servise bağlanır.
"""

from __future__ import annotations

import mimetypes
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Any, Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session

from bioprof.config import Settings
from bioprof.db.models import ChunkRecord, SourceRecord
from bioprof.db.session import Database
from bioprof.domain.models import Evidence
from bioprof.rag.answering import HakemCallable
from bioprof.rag.citations import make_anchor
from bioprof.services.jobs import JobManager
from bioprof.services.repositories import Repository
from bioprof.studio.artifacts import (
    ArtifactExporter,
    MasteredAudio,
    StudioArtifact,
    StudioEngine,
    StudioEvidence,
    StudioMediaRenderer,
)
from bioprof.studio.llm_writer import StudioLLMWriter
from bioprof.studio.podcast import (
    VARSAYILAN_STIL,
    PodcastAyarlari,
    PodcastScriptBuilder,
    script_markdown,
    tahmini_sure,
)
from bioprof.voice.seslab import SesLabAdapter


class _Retriever(Protocol):
    def search(self, *args: Any, **kwargs: Any) -> list[Evidence]: ...


class StudioService:
    """`studio` işini uçtan uca yürütür; bağımlılıkları kurucudan alır."""

    def __init__(
        self,
        *,
        settings: Settings,
        database: Database,
        jobs: JobManager,
        engine: StudioEngine,
        exporter: ArtifactExporter,
        media_renderer: StudioMediaRenderer,
        voice: SesLabAdapter,
        retriever_fabrikasi: Callable[[Session], _Retriever],
        studio_writer: Callable[[Any], Awaitable[StudioLLMWriter | None]],
        synthesize: Callable[..., Awaitable[Any]],
        release_llm_for_audio: Callable[[], Awaitable[None]],
        require_notebook: Callable[[str], Awaitable[Any]],
        nli_hakem: Callable[[], HakemCallable | None],
        podcast_ayarlari: Callable[[], PodcastAyarlari],
    ) -> None:
        self.settings = settings
        self.database = database
        self.jobs = jobs
        self.engine = engine
        self.exporter = exporter
        self.media_renderer = media_renderer
        self.voice = voice
        self._retriever = retriever_fabrikasi
        self._studio_writer = studio_writer
        self._synthesize = synthesize
        self._release_llm_for_audio = release_llm_for_audio
        self._require_notebook = require_notebook
        self._nli_hakem = nli_hakem
        self._podcast_ayarlari = podcast_ayarlari

    async def _polish_artifact(
        self,
        job_id: str,
        artifact: StudioArtifact,
        records: list[StudioEvidence],
        notebook: Any = None,
    ) -> StudioArtifact:
        """Metni LLM ile akıcılaştırır; kanıt kapısı geçilmezse taslak kalır."""
        writer = await self._studio_writer(notebook)
        if writer is None or not writer.supports(artifact.kind):
            return artifact
        self.jobs.progress(job_id, 0.6, "Metin akıcılaştırılıyor")
        text, warnings = await writer.rewrite(
            artifact.kind, artifact.content_markdown, records, title=artifact.title
        )
        polished = text != artifact.content_markdown
        structured = dict(artifact.structured_data or {})
        structured["llm_polished"] = polished
        return artifact.model_copy(
            update={
                "content_markdown": text,
                "structured_data": structured,
                "warnings": [*artifact.warnings, *warnings],
            }
        )

    async def _write_podcast_script(
        self,
        job_id: str,
        artifact: StudioArtifact,
        records: list[StudioEvidence],
        length: str,
        notebook: Any = None,
        *,
        payload: dict[str, Any] | None = None,
    ) -> StudioArtifact:
        """Kalıp senaryoyu LLM diyaloğuyla değiştirir; başarısızlıkta kalıp kalır."""
        payload = payload or {}
        writer = await self._studio_writer(notebook)
        chat = writer.chat if writer is not None else None
        target_minutes = payload.get("target_minutes")
        style = str(payload.get("style") or VARSAYILAN_STIL)
        self.jobs.progress(job_id, 0.25, "Podcast senaryosu yazılıyor")

        notebook_id = str(payload.get("notebook_id") or artifact.notebook_id or "")
        source_ids = payload.get("source_ids")
        evidence_limit = int(payload.get("max_evidence") or self.settings.max_evidence)

        async def chapter_evidence(baslik: str) -> list[StudioEvidence]:
            """Bölüm başlığına göre kendi kanıtını getirir.

            Uzun bir bölümde tüm alt başlıkları aynı kanıt setiyle yazmak,
            aynı bilginin defalarca anlatılması demekti.
            """
            if not notebook_id:
                return []
            with self.database.session() as session:
                found = self._retriever(session).search(
                    notebook_id, baslik, source_ids=source_ids, limit=evidence_limit
                )
            return [
                StudioEvidence(
                    label=item.label,
                    text=item.text,
                    source_title=item.anchor.source_title,
                    citation_id=item.anchor.id,
                    section=item.anchor.section,
                    page=item.anchor.page,
                )
                for item in found
            ]

        async def chapter_progress(
            done: int, total: int, baslik: str, yazilanlar: list[dict[str, Any]]
        ) -> None:
            oran = 0.25 + 0.3 * (done / max(1, total))
            etiket = f"Bölüm {done + 1}/{total}: {baslik}" if baslik else "Senaryo tamam"
            # Ara kayıt: saatlerce süren bir üretim yarıda kesilirse yazılmış
            # bölümler iş kaydında durur, baştan üretmek gerekmez.
            self.jobs.progress(
                job_id,
                min(0.55, oran),
                etiket,
                checkpoint={
                    "chapters_done": done,
                    "chapters_total": total,
                    "segments": yazilanlar,
                },
            )

        segments, warnings, llm_wrote = await PodcastScriptBuilder(
            chat, hakem=self._nli_hakem(), ayarlar=self._podcast_ayarlari()
        ).build(
            artifact.title,
            records,
            length=length,
            target_minutes=float(target_minutes) if target_minutes else None,
            style=style,
            chapter_provider=chapter_evidence if notebook_id else None,
            progress=chapter_progress,
        )
        structured = dict(artifact.structured_data or {})
        structured.update(
            {
                "segments": segments,
                "llm_polished": llm_wrote,
                "length": length,
                "style": style,
                "target_minutes": target_minutes,
                # Karakter tabanlı tahmin: kısa soru ile uzun anlatım aynı
                # "1 replik" değildir.
                "estimated_seconds": round(
                    tahmini_sure(
                        segments, karakter_hizi=self.settings.podcast_karakter_hizi
                    )
                ),
            }
        )
        return artifact.model_copy(
            update={
                "content_markdown": script_markdown(artifact.title, segments)
                + self.engine._footer(records),  # noqa: SLF001
                "structured_data": structured,
                "warnings": [*artifact.warnings, *warnings],
            }
        )

    async def _mp3_kodla(self, media: Any) -> Any:
        """Doğrulanmış WAV'ı SesLab mastering zinciriyle MP3'e kodlar.

        Başarısızlıkta WAV + görünür uyarı: sessizce format düşürmek,
        arayüzdeki söz ile davranışı yeniden ayırırdı.
        """
        if media.status != "completed" or not media.files:
            return media
        wav_yolu = Path(media.files[0])
        try:
            payload = await self.voice.master(
                [wav_yolu.read_bytes()], response_format="mp3"
            )
        except Exception:  # noqa: BLE001 - kodlama iyileştirmedir, işi düşürmez
            payload = None
        if payload is None or not payload.data:
            return media.model_copy(
                update={
                    "warnings": [
                        *media.warnings,
                        "MP3 kodlanamadı (SesLab mastering ucu yok); WAV verildi.",
                    ]
                }
            )
        mp3_yolu = wav_yolu.with_suffix(".mp3")
        ArtifactExporter._atomic_bytes(mp3_yolu, payload.data)  # noqa: SLF001
        return media.model_copy(
            update={
                "files": [str(mp3_yolu), *media.files],
                "media_types": ["audio/mpeg", *media.media_types],
            }
        )

    async def _master_podcast(
        self, chunks: list[bytes], gap_ms: int, response_format: str = "wav"
    ) -> MasteredAudio | None:
        payload = await self.voice.master(
            chunks, gap_ms=gap_ms, response_format=response_format
        )
        if payload is None:
            return None
        return MasteredAudio(data=payload.data, metadata=dict(payload.metadata))

    async def job(self, job_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.jobs.progress(job_id, 0.1, "Kanıtlar seçiliyor")
        # Uzun bir podcast dar bir kanıt havuzuyla kısa kalır: replikler kanıt
        # kapısından geçemez. Havuzu istek başına genişletmek, kalıcı ayarı
        # (ve her işi) yavaşlatmadan bunu çözer.
        evidence_limit = int(payload.get("max_evidence") or self.settings.max_evidence)
        with self.database.session() as session:
            evidence = self._retriever(session).search(
                str(payload["notebook_id"]),
                str(payload.get("instructions") or payload["title"]),
                source_ids=payload.get("source_ids"),
                limit=evidence_limit,
            )
            if not evidence and payload.get("source_ids"):
                selected_rows = session.execute(
                    select(ChunkRecord, SourceRecord)
                    .join(SourceRecord, SourceRecord.id == ChunkRecord.source_id)
                    .where(
                        SourceRecord.id.in_(
                            [str(value) for value in payload["source_ids"]]
                        ),
                        SourceRecord.notebook_id == str(payload["notebook_id"]),
                        SourceRecord.status == "ready",
                    )
                    .order_by(SourceRecord.created_at.desc(), ChunkRecord.ordinal)
                    .limit(evidence_limit)
                ).all()
                evidence = [
                    Evidence(
                        label=f"S{index}",
                        text=chunk.text,
                        score=1.0,
                        anchor=make_anchor(chunk, source),
                        retrieval_channels=["selected_source_fallback"],
                    )
                    for index, (chunk, source) in enumerate(selected_rows, start=1)
                ]
        if not evidence:
            raise ValueError("Studio çıktısı için kaynaklı kanıt bulunamadı")
        studio_evidence = [
            StudioEvidence(
                label=item.label,
                text=item.text,
                source_title=item.anchor.source_title,
                citation_id=item.anchor.id,
                section=item.anchor.section,
                page=item.anchor.page,
                timestamp_start=item.anchor.timestamp_start,
                timestamp_end=item.anchor.timestamp_end,
            )
            for item in evidence
        ]
        kind = str(payload["kind"])
        # "slides" artık gerçek bir üreteç; study_guide alias'ı kalktı.
        normalized_kind = {
            "infographic": "mind_map",
            "audio_lecture": "audio_lesson",
        }.get(kind, kind)
        self.jobs.progress(job_id, 0.45, "Studio çıktısı hazırlanıyor")
        uretim_secenekleri = {
            anahtar: payload.get(anahtar)
            for anahtar in ("sinif", "sure_dakika", "kazanim_kodlari")
            if payload.get(anahtar) is not None
        }
        try:
            artifact = self.engine.generate(
                normalized_kind,  # type: ignore[arg-type]
                title=str(payload["title"]),
                evidence=studio_evidence,
                notebook_id=str(payload["notebook_id"]),
                options=uretim_secenekleri,
            )
        except ValueError:
            # Export-only aliases remain grounded in a study guide representation.
            artifact = self.engine.generate(
                "study_guide",
                title=str(payload["title"]),
                evidence=studio_evidence,
                notebook_id=str(payload["notebook_id"]),
            )
        notebook = await self._require_notebook(str(payload["notebook_id"]))
        if normalized_kind == "podcast":
            artifact = await self._write_podcast_script(
                job_id,
                artifact,
                studio_evidence,
                str(payload.get("length") or "orta"),
                notebook,
                payload=payload,
            )
        else:
            artifact = await self._polish_artifact(
                job_id, artifact, studio_evidence, notebook
            )
        format_name = payload.get("output_format") or {
            "audio_lesson": "wav",
            "audio_lecture": "wav",
            "video_overview": "mp4",
            "podcast": "podcast",
        }.get(normalized_kind, "markdown")
        format_alias = {"markdown": "md"}.get(str(format_name), str(format_name))
        destination = (
            self.settings.artifacts_dir / str(payload["notebook_id"]) / artifact.id
        )
        if format_alias in {"wav", "mp3", "mp4", "podcast"}:
            mp3_istendi = format_alias == "mp3" and normalized_kind != "podcast"
            if mp3_istendi:
                # Cümle bazlı üretici doğrulanmış PCM WAV ister; MP3 en sonda
                # SesLab mastering zinciriyle kodlanır. Eskiden istek sessizce
                # WAV'a düşürülüyordu — arayüzdeki "WAV/MP3" sözü boştu.
                format_alias = "wav"

            async def synthesize(
                text_value: str, voice: str, verify: bool
            ) -> tuple[bytes, str]:
                audio = await self._synthesize(
                    text_value,
                    voice=voice,
                    response_format="wav",
                    verify=verify,
                )
                return audio.data, audio.media_type

            if normalized_kind == "podcast":

                async def report(ratio: float, message: str) -> None:
                    self.jobs.progress(job_id, 0.6 + 0.35 * ratio, message)

                # Senaryo bitti; TTS başlamadan önce model belleği geri verilir
                # (9B + XTTS bu makinede birlikte sığmaz).
                await self._release_llm_for_audio()
                media = await self.media_renderer.render_podcast(
                    artifact,
                    destination,
                    synthesizer=synthesize,
                    mastering=self._master_podcast,
                    progress=report,
                )
            elif format_alias == "mp4":
                media = await self.media_renderer.render_video(
                    artifact,
                    destination,
                    synthesizer=synthesize,
                    strict_verification=bool(payload.get("verify")),
                )
            else:
                media = await self.media_renderer.render_audio(
                    artifact,
                    destination,
                    synthesizer=synthesize,
                    strict_verification=bool(payload.get("verify")),
                )
                if mp3_istendi:
                    media = await self._mp3_kodla(media)
            if not media.files:
                raise ValueError("SesLab/Murat servisi medya çıktısı için hazır değil")
            manifest = self.exporter.export(
                artifact, destination, format_name="manifest"
            )
            primary = Path(media.files[0])
            with self.database.session() as session:
                record = Repository(session).create_artifact(
                    str(payload["notebook_id"]),
                    kind,
                    str(payload["title"]),
                    str(primary),
                    media.media_types[0],
                    metadata={
                        **artifact.model_dump(mode="json"),
                        "files": [*media.files, str(manifest)],
                        "warnings": [*artifact.warnings, *media.warnings],
                        "render_status": media.status,
                        "voice": (
                            "Murat + Emel" if normalized_kind == "podcast" else "Murat"
                        ),
                        "synthetic": True,
                    },
                )
            return {
                "artifact_id": record.id,
                "kind": kind,
                "path": str(primary),
                "files": [*media.files, str(manifest)],
                "media_types": media.media_types,
                "render_status": media.status,
                # Senaryo kapısı uyarıları ("N replik çıkarıldı", "kalıp
                # senaryoya düşüldü") doğrudan güvenilirlikle ilgili; iş
                # sonucunda görünmezse kullanıcı yarısı atılmış bir podcast'i
                # bilmeden dinler.
                "warnings": [*artifact.warnings, *media.warnings],
                "provenance_complete": artifact.provenance_complete,
                "citations": [
                    item.model_dump(mode="json") for item in artifact.citations
                ],
            }
        exported = self.exporter.export(artifact, destination, format_name=format_alias)
        with self.database.session() as session:
            record = Repository(session).create_artifact(
                str(payload["notebook_id"]),
                kind,
                str(payload["title"]),
                str(exported),
                mimetypes.guess_type(exported.name)[0] or "application/octet-stream",
                metadata=artifact.model_dump(mode="json"),
            )
            artifact_id = record.id
        return {
            "artifact_id": artifact_id,
            "kind": kind,
            "path": str(exported),
            "provenance_complete": artifact.provenance_complete,
            "citations": [item.model_dump(mode="json") for item in artifact.citations],
        }
