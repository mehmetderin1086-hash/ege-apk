"""Sesli kitap kaydının dayanıklı iki fazlı zamanlayıcısı.

Faz 1 (iş düzeyi, tek işçi): kaynak ses → kanonik WAV → 300 sn'lik, 5 sn
bindirmeli parçalar hâlinde transkripsiyon. Her parça ``voice_transcript_chunk``
tablosuna checkpoint edilir; çökme sonrası yalnız eksik parçalar yeniden
çözülür. Faz 2 (öğe düzeyi): her kitap söylemi lease/heartbeat ile işlenir —
kural ayrıştırma → (gerekirse) Qwen → idempotent katalog yazımı.

İdempotenlik sözleşmesi: edition için ``voice:{sha}:{item_key}`` parmak izi,
n'inci nüsha için ``voice:{sha}:{item_key}:c{n}``; ``save_book`` ve
``_add_copy`` bu parmak izleriyle yeniden koşumda yeni satır üretmez. Terminal
aşamaya geçiş en son yapılır; aradaki her adım tekrarlanabilir olduğundan
yarım kalan öğe baştan güvenle işlenir.
"""

from __future__ import annotations

import json
import shutil
import threading
import time
from collections.abc import Callable
from contextlib import AbstractContextManager, suppress
from dataclasses import dataclass, replace
from pathlib import Path

from kitapkatalog.audio import (
    WAV_SAMPLE_RATE,
    audio_fingerprint,
    find_quietest_sample,
    slice_wav,
    transcode_to_wav16k,
    wav_sample_count,
)
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths, RuntimeLimits
from kitapkatalog.database import Database
from kitapkatalog.domain import (
    CopyInput,
    ImportJobStatus,
    TranscriptSegment,
    VoiceItem,
    VoiceItemStage,
    VoiceJob,
    VoiceJobPhase,
)
from kitapkatalog.scheduler import HeartbeatLostError, LeaseHeartbeat
from kitapkatalog.settings import AppSettings
from kitapkatalog.voice_extractor import (
    VoiceFieldExtractor,
    VoiceParseResult,
    build_book_input,
)
from kitapkatalog.voice_prompt import build_transcription_prompt
from kitapkatalog.voice_protocol import (
    BookUtterance,
    filter_hallucinations,
    segment_books,
)

CHUNK_SECONDS = 300
CHUNK_OVERLAP_SECONDS = 5
_BOUNDARY_SEARCH_SECONDS = 15.0


class VoiceSchedulerError(RuntimeError):
    pass


class VoiceJobInterrupted(VoiceSchedulerError):
    """İş duraklatıldı/iptal edildi; hata değil, sükûnetle çıkış sinyali."""


@dataclass(frozen=True, slots=True)
class VoiceRunSummary:
    job_id: str
    processed_items: int
    completed: int
    review: int
    failed: int


def _segments_to_json(segments: tuple[TranscriptSegment, ...]) -> str:
    return json.dumps(
        [
            {
                "start": segment.start_seconds,
                "end": segment.end_seconds,
                "text": segment.text,
                "avg_logprob": segment.avg_logprob,
                "no_speech_prob": segment.no_speech_prob,
            }
            for segment in segments
        ],
        ensure_ascii=False,
    )


def _segments_from_json(payload: str) -> tuple[TranscriptSegment, ...]:
    return tuple(
        TranscriptSegment(
            start_seconds=float(item["start"]),
            end_seconds=float(item["end"]),
            text=str(item["text"]),
            avg_logprob=item.get("avg_logprob"),
            no_speech_prob=item.get("no_speech_prob"),
        )
        for item in json.loads(payload)
    )


def persist_parse_result(
    catalog: Catalog, result: VoiceParseResult, *, fingerprint_base: str
) -> int:
    """İddia kümesini idempotent parmak izleriyle kataloğa yaz.

    Aynı parmak izleriyle yeniden çağrılmak yeni edition/nüsha üretmez; hem
    toplu kuyruk hem canlı mikrofon bu tek kapıdan yazar.
    """

    location = result.value_of("location")
    book = replace(
        build_book_input(result),
        copy=CopyInput(
            source_fingerprint=f"{fingerprint_base}:c1",
            location=location,
            notes="sesli kayıt",
        ),
    )
    with catalog.db.transaction(immediate=True):
        record = catalog.save_book(book, source_fingerprint=fingerprint_base)
        for copy_number in range(2, result.copy_count + 1):
            catalog.add_copy(
                record.edition_id,
                CopyInput(
                    source_fingerprint=f"{fingerprint_base}:c{copy_number}",
                    location=location,
                    notes="sesli kayıt",
                ),
            )
    return record.edition_id


def build_voice_scheduler(
    database: Database,
    paths: AppPaths,
    *,
    limits: RuntimeLimits | None = None,
    worker_id: str = "voice-worker-1",
    stop_event: threading.Event | None = None,
) -> VoiceScheduler:
    """Varsayılan whisper + (varsa) Qwen bağlamayla zamanlayıcı kur.

    Qwen paketi (llama-server + GGUF) yoksa hat kural-katmanıyla çalışır;
    anahtar kelimesiz serbest söylemler inceleme kuyruğuna düşer.
    """

    from kitapkatalog.whisper_runtime import (
        ManagedWhisperClient,
        default_model_path,
        default_server_executable,
    )

    def whisper_factory() -> ManagedWhisperClient:
        return ManagedWhisperClient(
            executable=default_server_executable(paths),
            model_path=default_model_path(paths),
            language=AppSettings(database).voice_language,
        )

    return VoiceScheduler(
        database,
        paths,
        limits,
        whisper_client_factory=whisper_factory,
        qwen_client_factory=resolve_qwen_factory(paths),
        worker_id=worker_id,
        stop_event=stop_event,
    )


def resolve_qwen_factory(paths: AppPaths) -> Callable[[], object] | None:
    """llama-server + Qwen GGUF varsa istemci fabrikası, yoksa None döndür.

    application._bundled_executable ile aynı çözümleme sırası; oradan import
    etmek OCR yığınını da yüklerdi.
    """

    import os as _os
    import shutil as _shutil

    from kitapkatalog.qwen_runtime import ManagedQwenClient

    llama: str | None = None
    if override := _os.environ.get("KITAPKATALOG_LLAMA_SERVER_BIN"):
        candidate = Path(override).expanduser()
        llama = str(candidate) if candidate.is_file() else None
    else:
        bundled_llama = paths.models / "bin" / "llama-server"
        llama = str(bundled_llama) if bundled_llama.is_file() else _shutil.which("llama-server")
    qwen_model = paths.models / "qwen3" / "Qwen3-4B-Q4_K_M.gguf"
    if llama is None or not qwen_model.is_file():
        return None
    resolved_llama = llama

    def factory() -> ManagedQwenClient:
        return ManagedQwenClient(executable=resolved_llama, model_path=qwen_model)

    return factory


class VoiceScheduler:
    def __init__(
        self,
        database: Database,
        paths: AppPaths,
        limits: RuntimeLimits | None = None,
        *,
        whisper_client_factory: Callable[[], AbstractContextManager],
        qwen_client_factory: Callable[[], object] | None = None,
        worker_id: str = "voice-worker-1",
        stop_event: threading.Event | None = None,
    ) -> None:
        self.database = database
        self.paths = paths
        self.limits = limits or RuntimeLimits()
        self.catalog = Catalog(database)
        self.whisper_client_factory = whisper_client_factory
        self.qwen_client_factory = qwen_client_factory
        self.worker_id = worker_id
        self._stop = stop_event or threading.Event()

    def request_stop(self) -> None:
        """Bir sonraki güvenli noktada (chunk/öğe sınırı) işlemeyi bırak.

        DB durumu değiştirilmez: iş RUNNING kalır ve bir sonraki ``run``
        kaldığı checkpoint'ten sürer. Pencere kapanışı bunu kullanır.
        """

        self._stop.set()

    # ------------------------------------------------------------- enqueue

    def enqueue(
        self,
        audio_path: str | Path,
        *,
        name: str | None = None,
        single_book: bool = False,
        idempotency_key: str | None = None,
        language: str | None = None,
    ) -> VoiceJob:
        source = Path(audio_path)
        if not source.is_file():
            raise VoiceSchedulerError(f"Ses dosyası bulunamadı: {source}")
        fingerprint = audio_fingerprint(source)
        originals = self.paths.voice_assets / "originals"
        originals.mkdir(parents=True, exist_ok=True)
        managed = originals / f"{fingerprint}{source.suffix.lower()}"
        if not managed.exists():
            shutil.copy2(source, managed)
        return self.database.create_voice_job(
            name=name or source.name,
            source_audio_path=managed,
            source_sha256=fingerprint,
            single_book=single_book,
            idempotency_key=idempotency_key or f"voice:{fingerprint}",
            language=language,
        )

    # ------------------------------------------------------------- run

    def run_job(self, job_id: str) -> VoiceRunSummary:
        job = self.database.get_voice_job(job_id)
        if job is None:
            raise VoiceSchedulerError(f"Ses işi bulunamadı: {job_id}")
        if job.status in {
            ImportJobStatus.CANCELLED,
            ImportJobStatus.PAUSED,
            ImportJobStatus.COMPLETED,
            ImportJobStatus.COMPLETED_WITH_ERRORS,
        }:
            return self._summary(job_id, 0)
        if not self.database.claim_voice_job(
            job_id, self.worker_id, lease_seconds=self._job_lease_seconds()
        ):
            raise VoiceSchedulerError(f"Ses işi {job_id} başka bir işçi tarafından çalıştırılıyor")
        self.database.update_voice_job_progress(job_id, mark_started=True)
        try:
            job = self._require_active(job_id)
            job = self._ensure_canonical_wav(job)
            job = self._ensure_transcribed(job)
            job = self._ensure_segmented(job)
        except VoiceJobInterrupted:
            return self._summary(job_id, 0)
        except Exception as error:
            self.database.update_voice_job_progress(job_id, error=str(error))
            raise
        finally:
            self.database.release_voice_job(job_id, self.worker_id)
        processed = self._process_items(job_id)
        return self._summary(job_id, processed)

    def _job_lease_seconds(self) -> int:
        # Faz-1'de tek chunk transkripsiyonu bile dakikalar sürebilir; lease
        # her chunk sonunda tazelenir (bkz. _ensure_transcribed).
        return max(600, self.limits.lease_seconds * 2)

    def run_next(self) -> VoiceRunSummary | None:
        for job in self.database.list_voice_jobs():
            if job.status in {ImportJobStatus.QUEUED, ImportJobStatus.RUNNING}:
                return self.run_job(job.id)
        return None

    # ------------------------------------------------------- faz 1: ses

    def _ensure_canonical_wav(self, job: VoiceJob) -> VoiceJob:
        if job.canonical_wav_path and Path(job.canonical_wav_path).is_file():
            return job
        canonical_dir = self.paths.voice_assets / "canonical"
        canonical_dir.mkdir(parents=True, exist_ok=True)
        target = canonical_dir / f"{job.id}.wav"
        transcode_to_wav16k(job.source_audio_path, target)
        return self.database.update_voice_job_progress(
            job.id,
            phase=VoiceJobPhase.CONVERTED,
            canonical_wav_path=target,
        )

    def _chunk_plan(self, wav_path: Path) -> list[tuple[int, int, int]]:
        """(chunk_index, start_sample, end_sample) listesi; sınırlar sessizliğe kaydırılır."""

        total = wav_sample_count(wav_path)
        chunk_samples = CHUNK_SECONDS * WAV_SAMPLE_RATE
        overlap = CHUNK_OVERLAP_SECONDS * WAV_SAMPLE_RATE
        if total <= chunk_samples:
            return [(0, 0, total)]
        boundaries = [0]
        position = chunk_samples
        while position < total:
            boundaries.append(
                find_quietest_sample(
                    wav_path,
                    around_sample=position,
                    span_seconds=_BOUNDARY_SEARCH_SECONDS,
                )
            )
            position += chunk_samples
        boundaries.append(total)
        plan: list[tuple[int, int, int]] = []
        for index in range(len(boundaries) - 1):
            start = max(0, boundaries[index] - (overlap if index else 0))
            end = min(total, boundaries[index + 1] + overlap)
            if index == len(boundaries) - 2:
                end = total
            plan.append((index, start, end))
        return plan

    def _ensure_transcribed(self, job: VoiceJob) -> VoiceJob:
        assert job.canonical_wav_path is not None
        wav_path = Path(job.canonical_wav_path)
        plan = self._chunk_plan(wav_path)
        existing = {int(row["chunk_index"]) for row in self.database.list_voice_chunks(job.id)}
        missing = [entry for entry in plan if entry[0] not in existing]
        if missing:
            scratch = self.paths.derivatives / "voice-chunks"
            scratch.mkdir(parents=True, exist_ok=True)
            settings = AppSettings(self.database)
            prompt = (
                build_transcription_prompt(self.database, extra=settings.voice_prompt_extra)
                if settings.voice_prompt_bias
                else None
            )
            with self.whisper_client_factory() as whisper:
                for chunk_index, start_sample, end_sample in missing:
                    job = self._require_active(job.id)
                    self.database.heartbeat_voice_job(
                        job.id,
                        self.worker_id,
                        lease_seconds=self._job_lease_seconds(),
                    )
                    piece = scratch / f"{job.id}-{chunk_index:04d}.wav"
                    try:
                        slice_wav(
                            wav_path,
                            piece,
                            start_sample=start_sample,
                            end_sample=end_sample,
                        )
                        # job.language ayar varsayılanını (whisper_client_factory'nin
                        # kurduğu dili) ezer; None ise istemcinin kendi varsayılanı geçer.
                        segments = whisper.transcribe(piece, prompt=prompt, language=job.language)
                    except BaseException:
                        piece.unlink(missing_ok=True)
                        raise
                    offset = start_sample / WAV_SAMPLE_RATE
                    absolute = tuple(
                        TranscriptSegment(
                            start_seconds=segment.start_seconds + offset,
                            end_seconds=segment.end_seconds + offset,
                            text=segment.text,
                            avg_logprob=segment.avg_logprob,
                            no_speech_prob=segment.no_speech_prob,
                        )
                        for segment in segments
                    )
                    self.database.upsert_voice_chunk(
                        job.id,
                        chunk_index,
                        start_sample=start_sample,
                        end_sample=end_sample,
                        segments_json=_segments_to_json(absolute),
                        model_id=str(getattr(whisper, "model_path", "")),
                    )
                    piece.unlink(missing_ok=True)
        return self.database.update_voice_job_progress(job.id, phase=VoiceJobPhase.TRANSCRIBED)

    # ------------------------------------------------- faz 1: bölütleme

    def _merged_segments(self, job: VoiceJob) -> tuple[TranscriptSegment, ...]:
        """Bindirmeli parçaları zaman-orta-noktası sahipliğiyle birleştir.

        Parça i>0 için transkripsiyon aralığı sınırdan ``overlap`` kadar önce
        başlar; sahiplik sınırı ise gerçek sınırdır (start + overlap). Bir
        segment, orta noktası hangi parçanın sahiplik aralığına düşüyorsa
        YALNIZ o parçadan alınır — metin benzerliği karşılaştırması yapılmaz.
        """

        rows = self.database.list_voice_chunks(job.id)
        if not rows:
            return ()
        ownership_starts: list[float] = []
        for index, row in enumerate(rows):
            start_seconds = int(row["start_sample"]) / WAV_SAMPLE_RATE
            ownership_starts.append(0.0 if index == 0 else start_seconds + CHUNK_OVERLAP_SECONDS)
        merged: list[TranscriptSegment] = []
        for index, row in enumerate(rows):
            own_start = ownership_starts[index]
            own_end = ownership_starts[index + 1] if index + 1 < len(rows) else float("inf")
            for segment in _segments_from_json(row["segments_json"]):
                midpoint = (segment.start_seconds + segment.end_seconds) / 2
                if own_start <= midpoint < own_end:
                    merged.append(segment)
        merged.sort(key=lambda segment: segment.start_seconds)
        return tuple(merged)

    def _ensure_segmented(self, job: VoiceJob) -> VoiceJob:
        segments = filter_hallucinations(self._merged_segments(job))
        if job.single_book:
            utterances: tuple[BookUtterance, ...] = (
                (
                    BookUtterance(
                        ordinal=0,
                        start_seconds=segments[0].start_seconds if segments else 0.0,
                        end_seconds=segments[-1].end_seconds if segments else 0.0,
                        segments=segments,
                    ),
                )
                if segments
                else ()
            )
        else:
            utterances = segment_books(segments)
        items = []
        for utterance in utterances:
            items.append(
                {
                    "item_key": (f"v{job.segmentation_version}:{utterance.ordinal:05d}"),
                    "ordinal": utterance.ordinal,
                    "start_sample": int(utterance.start_seconds * WAV_SAMPLE_RATE),
                    "end_sample": int(utterance.end_seconds * WAV_SAMPLE_RATE),
                    "transcript_json": _segments_to_json(utterance.segments),
                }
            )
        self.database.insert_voice_items(job.id, items)
        if not items and not self.database.list_voice_items(job.id):
            # Sessiz/boş kayıt: iş sonsuza dek 'running' kalmasın.
            self.database.update_voice_job_progress(
                job.id,
                phase=VoiceJobPhase.DONE,
                error="Kayıtta kitap söylemi bulunamadı",
                mark_finished=True,
            )
            self.database.set_voice_job_status(job.id, ImportJobStatus.COMPLETED_WITH_ERRORS)
            raise VoiceJobInterrupted("Kayıtta kitap söylemi bulunamadı")
        return self.database.update_voice_job_progress(job.id, phase=VoiceJobPhase.SEGMENTED)

    # --------------------------------------------------- faz 2: öğeler

    def _process_items(self, job_id: str) -> int:
        self.database.update_voice_job_progress(job_id, phase=VoiceJobPhase.ITEMS)
        processed = 0
        while True:
            if self._stop.is_set():
                break
            item = self.database.claim_next_voice_item(
                self.worker_id,
                job_id=job_id,
                lease_seconds=self.limits.lease_seconds,
            )
            if item is None:
                # Gecikmeli retry (not_before) veya yabancı lease bekliyor
                # olabilir; max_retries bu döngü İÇİNDE tüketilsin diye uyanma
                # zamanına kadar bekleyip yeniden dene.
                wake_seconds = self.database.next_voice_wake_seconds(job_id)
                if wake_seconds is None:
                    break
                current = self.database.get_voice_job(job_id)
                if current is None or current.status in {
                    ImportJobStatus.CANCELLED,
                    ImportJobStatus.PAUSED,
                }:
                    break
                time.sleep(min(wake_seconds + 0.05, 5.0))
                continue
            heartbeat = LeaseHeartbeat(
                self.database,
                item.id,
                self.worker_id,
                lease_seconds=self.limits.lease_seconds,
                heartbeat=self.database.heartbeat_voice_item,
            )
            heartbeat.start()
            try:
                self._process_one(item, heartbeat)
                processed += 1
            except HeartbeatLostError:
                continue  # başka işçi devraldı; öğe onun sorumluluğunda
            except Exception as error:
                # Lease de düştüyse öğe zaman aşımıyla kendiliğinden geri döner.
                with suppress(Exception):
                    self.database.fail_voice_item(
                        item.id,
                        self.worker_id,
                        f"{type(error).__name__}: {error}",
                        max_retries=self.limits.max_retries,
                        retry_delay_seconds=5,
                    )
            finally:
                heartbeat.stop()
        return processed

    def _process_one(self, item: VoiceItem, heartbeat: LeaseHeartbeat) -> None:
        job = self.database.get_voice_job(item.job_id)
        assert job is not None
        segments = _segments_from_json(item.transcript_json)
        utterance = BookUtterance(
            ordinal=item.ordinal,
            start_seconds=item.start_sample / WAV_SAMPLE_RATE,
            end_seconds=item.end_sample / WAV_SAMPLE_RATE,
            segments=segments,
        )
        stage = item.stage
        if stage == VoiceItemStage.SEGMENTED:
            rule_only = VoiceFieldExtractor().parse(utterance)
            heartbeat.raise_if_lost()
            item = self.database.advance_voice_item(
                item.id,
                self.worker_id,
                VoiceItemStage.PARSED,
                expected_stage=VoiceItemStage.SEGMENTED,
                claims_json=rule_only.to_json(),
                release=False,
            )
            stage = item.stage
        if stage == VoiceItemStage.PARSED:
            result = VoiceFieldExtractor(qwen_client_factory=self.qwen_client_factory).parse(
                utterance
            )
            heartbeat.raise_if_lost()
            item = self.database.advance_voice_item(
                item.id,
                self.worker_id,
                VoiceItemStage.EXTRACTED,
                expected_stage=VoiceItemStage.PARSED,
                claims_json=result.to_json(),
                release=False,
            )
            stage = item.stage
        if stage == VoiceItemStage.EXTRACTED:
            assert item.claims_json is not None
            result = VoiceParseResult.from_json(item.claims_json)
            edition_id = self._persist_book(job, item, result)
            heartbeat.raise_if_lost()
            target = VoiceItemStage.REVIEW if result.review_reasons else VoiceItemStage.COMPLETED
            self.database.advance_voice_item(
                item.id,
                self.worker_id,
                target,
                expected_stage=VoiceItemStage.EXTRACTED,
                edition_id=edition_id,
                review_reasons_json=json.dumps(result.review_reasons, ensure_ascii=False),
            )

    def _persist_book(self, job: VoiceJob, item: VoiceItem, result: VoiceParseResult) -> int:
        return persist_parse_result(
            self.catalog,
            result,
            fingerprint_base=f"voice:{job.source_sha256}:{item.item_key}",
        )

    # ------------------------------------------------------------ yardım

    def pause(self, job_id: str) -> VoiceJob:
        return self.database.pause_voice_job(job_id)

    def resume(self, job_id: str) -> VoiceJob:
        return self.database.resume_voice_job(job_id)

    def cancel(self, job_id: str) -> VoiceJob:
        return self.database.cancel_voice_job(job_id)

    def retry_item(self, item_id: int) -> VoiceItem:
        return self.database.retry_failed_voice_item(item_id)

    def _require_active(self, job_id: str) -> VoiceJob:
        if self._stop.is_set():
            raise VoiceJobInterrupted("Durdurma istendi; iş checkpoint'te kaldı")
        job = self.database.get_voice_job(job_id)
        if job is None:
            raise VoiceSchedulerError(f"Ses işi bulunamadı: {job_id}")
        if job.status in {ImportJobStatus.CANCELLED, ImportJobStatus.PAUSED}:
            raise VoiceJobInterrupted(f"Ses işi {job.status.value} durumunda; sürdürülemez")
        return job

    def _summary(self, job_id: str, processed: int) -> VoiceRunSummary:
        job = self.database.get_voice_job(job_id)
        assert job is not None
        return VoiceRunSummary(
            job_id=job_id,
            processed_items=processed,
            completed=job.successful_items,
            review=job.review_items,
            failed=job.failed_items,
        )
