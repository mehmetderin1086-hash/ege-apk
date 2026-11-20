from __future__ import annotations

import wave
from array import array
from datetime import UTC, datetime, timedelta
from pathlib import Path
from threading import Event

import pytest

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.config import AppPaths
from kitapkatalog.database import Database, LeaseLostError
from kitapkatalog.domain import (
    ImportJobStatus,
    TranscriptSegment,
    VoiceItemStage,
)
from kitapkatalog.voice_scheduler import (
    CHUNK_SECONDS,
    VoiceRunSummary,
    VoiceScheduler,
)


def _paths(root: Path) -> AppPaths:
    paths = AppPaths(
        root=root,
        database=root / "catalog.sqlite3",
        assets=root / "assets",
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=root / "models",
        exports=root / "exports",
        logs=root / "logs",
    )
    paths.ensure()
    return paths


def _silent_wav(path: Path, seconds: float) -> Path:
    frames = int(seconds * WAV_SAMPLE_RATE)
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(WAV_SAMPLE_RATE)
        chunk = array("h", [0]) * WAV_SAMPLE_RATE
        for _ in range(frames // WAV_SAMPLE_RATE):
            writer.writeframes(chunk.tobytes())
        writer.writeframes((array("h", [0]) * (frames % WAV_SAMPLE_RATE)).tobytes())
    return path


def _segment(text: str, start: float, end: float) -> TranscriptSegment:
    return TranscriptSegment(start_seconds=start, end_seconds=end, text=text, avg_logprob=-0.1)


class FakeWhisper:
    """Programlanabilir sahte whisper istemcisi (bağlam yöneticisi)."""

    model_path = "sahte-model"

    def __init__(self, script: list, *, language: str = "tr") -> None:
        self.script = script
        self.language = language
        self.calls: list[Path] = []
        self.call_kwargs: list[dict] = []

    def __enter__(self) -> FakeWhisper:
        return self

    def __exit__(self, *exc_info: object) -> None:
        return None

    def transcribe(self, wav_path: Path, **kwargs):
        self.calls.append(Path(wav_path))
        self.call_kwargs.append(kwargs)
        behavior = self.script.pop(0)
        if isinstance(behavior, Exception):
            raise behavior
        return behavior


_TWO_BOOKS = (
    _segment(
        "ISBN dokuz yedi sekiz dokuz yedi beş sıfır yedi bir sekiz beş üç üç "
        "başlık Kar yazar Orhan Pamuk yayınevi İletişim kategori roman üç adet",
        0.0,
        16.0,
    ),
    _segment("yeni kitap", 16.0, 17.0),
    _segment(
        "Başlık Beyaz Kale yazar Orhan Pamuk sayfa yüz doksan iki adet",
        17.0,
        29.0,
    ),
)


def _scheduler(
    tmp_path: Path, script: list, **kwargs
) -> tuple[VoiceScheduler, Database, FakeWhisper]:
    paths = _paths(tmp_path / "veri")
    database = Database(paths.database)
    fake = FakeWhisper(script)
    scheduler = VoiceScheduler(
        database,
        paths,
        whisper_client_factory=lambda: fake,
        worker_id="test-worker",
        **kwargs,
    )
    return scheduler, database, fake


class TestEndToEnd:
    def test_external_stop_event_prevents_new_work(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "dur.wav", 1.0)
        stop = Event()
        stop.set()
        scheduler, database, fake = _scheduler(tmp_path, [[]], stop_event=stop)
        job = scheduler.enqueue(source)

        summary = scheduler.run_job(job.id)

        assert summary.processed_items == 0
        assert fake.calls == []
        persisted = database.get_voice_job(job.id)
        assert persisted is not None
        assert persisted.status.value == "running"

    def test_two_books_land_in_catalog(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 30.0)
        scheduler, database, _fake = _scheduler(tmp_path, [_TWO_BOOKS])
        job = scheduler.enqueue(source)
        summary = scheduler.run_job(job.id)

        assert isinstance(summary, VoiceRunSummary)
        items = database.list_voice_items(job.id)
        assert len(items) == 2
        assert {item.stage for item in items} == {VoiceItemStage.COMPLETED}

        first = scheduler.catalog.get_book(items[0].edition_id)
        second = scheduler.catalog.get_book(items[1].edition_id)
        assert first is not None and second is not None
        assert first.title == "Kar"
        assert first.category == "roman"
        assert any(identifier.value == "9789750718533" for identifier in first.identifiers)
        assert len(first.copies) == 3
        assert second.title == "Beyaz Kale"
        assert second.page_count == 190
        assert len(second.copies) == 2
        refreshed = database.get_voice_job(job.id)
        assert refreshed is not None
        assert refreshed.status == ImportJobStatus.COMPLETED
        assert refreshed.successful_items == 2

    def test_rerun_is_idempotent(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 30.0)
        scheduler, database, _fake = _scheduler(tmp_path, [_TWO_BOOKS])
        job = scheduler.enqueue(source)
        scheduler.run_job(job.id)

        # Aynı dosya ikinci kez enqueue -> aynı iş; run tekrar -> çift yok.
        again = scheduler.enqueue(source)
        assert again.id == job.id
        scheduler.run_job(job.id)

        items = database.list_voice_items(job.id)
        assert len(items) == 2
        first = scheduler.catalog.get_book(items[0].edition_id)
        assert first is not None
        assert len(first.copies) == 3  # nüsha çiftlenmedi
        editions = database.fetchone("SELECT COUNT(*) AS c FROM edition")
        assert int(editions["c"]) == 2

    def test_invalid_isbn_goes_to_review(self, tmp_path: Path) -> None:
        bad = (_segment("ISBN 978 975 07 1853 4 başlık Kar yazar Orhan Pamuk", 0.0, 9.0),)
        source = _silent_wav(tmp_path / "kayit.wav", 10.0)
        scheduler, database, _fake = _scheduler(tmp_path, [bad])
        job = scheduler.enqueue(source)
        scheduler.run_job(job.id)
        items = database.list_voice_items(job.id)
        assert len(items) == 1
        assert items[0].stage == VoiceItemStage.REVIEW
        assert "sağlaması geçmedi" in (items[0].review_reasons_json or "")
        book = scheduler.catalog.get_book(items[0].edition_id)
        assert book is not None
        assert book.identifiers == ()  # geçersiz ISBN asla yazılmaz

    def test_single_book_mode_skips_separators(self, tmp_path: Path) -> None:
        segments = (
            _segment("Başlık Kar yazar Orhan Pamuk", 0.0, 5.0),
            _segment("yeni kitap gibi geçen bir cümle değil", 5.0, 8.0),
        )
        source = _silent_wav(tmp_path / "tek.wav", 9.0)
        scheduler, database, _fake = _scheduler(tmp_path, [segments])
        job = scheduler.enqueue(source, single_book=True)
        scheduler.run_job(job.id)
        assert len(database.list_voice_items(job.id)) == 1


class TestCrashResume:
    def test_chunk_checkpoint_survives_crash(self, tmp_path: Path) -> None:
        seconds = CHUNK_SECONDS + 120  # iki parça
        source = _silent_wav(tmp_path / "uzun.wav", seconds)
        chunk0 = (_segment("Başlık Kar yazar Orhan Pamuk kategori roman", 1.0, 12.0),)
        # İkinci parça: mutlak zaman = parça ofseti + göreli zaman
        chunk1 = (
            _segment("yeni kitap", 8.0, 9.0),
            _segment("Başlık Beyaz Kale yazar Orhan Pamuk", 9.5, 16.0),
        )
        scheduler, database, fake = _scheduler(tmp_path, [chunk0, RuntimeError("whisper çöktü")])
        job = scheduler.enqueue(source)
        with pytest.raises(RuntimeError, match="whisper çöktü"):
            scheduler.run_job(job.id)
        assert {int(r["chunk_index"]) for r in database.list_voice_chunks(job.id)} == {0}
        assert len(fake.calls) == 2

        # Yeniden koşum: yalnız eksik parça çözülür, iş tamamlanır.
        fake.script.extend([chunk1])
        scheduler.run_job(job.id)
        assert len(fake.calls) == 3  # parça 0 yeniden ÇÖZÜLMEDİ
        items = database.list_voice_items(job.id)
        assert len(items) == 2
        titles = set()
        for item in items:
            book = scheduler.catalog.get_book(item.edition_id)
            assert book is not None
            titles.add(book.title)
        assert titles == {"Kar", "Beyaz Kale"}

    def test_pause_stops_processing_quietly(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 10.0)
        scheduler, _database, fake = _scheduler(tmp_path, [])
        job = scheduler.enqueue(source)
        scheduler.pause(job.id)
        summary = scheduler.run_job(job.id)
        assert summary.processed_items == 0
        assert fake.calls == []


class TestLeaseSemantics:
    def _seeded_item(self, tmp_path: Path) -> tuple[Database, int, str]:
        paths = _paths(tmp_path / "veri")
        database = Database(paths.database)
        job = database.create_voice_job(
            name="test", source_audio_path="/tmp/a.wav", source_sha256="abc"
        )
        database.insert_voice_items(
            job.id,
            [
                {
                    "item_key": "v1:00000",
                    "ordinal": 0,
                    "start_sample": 0,
                    "end_sample": 16000,
                    "transcript_json": "[]",
                }
            ],
        )
        return database, database.list_voice_items(job.id)[0].id, job.id

    def test_expired_lease_can_be_stolen(self, tmp_path: Path) -> None:
        database, item_id, _ = self._seeded_item(tmp_path)
        first = database.claim_next_voice_item("isci-a", lease_seconds=60)
        assert first is not None and first.lease_owner == "isci-a"
        # Süre dolmadan ikinci işçi alamaz.
        assert database.claim_next_voice_item("isci-b", lease_seconds=60) is None
        # Süre dolunca çalabilir.
        future = datetime.now(UTC) + timedelta(seconds=120)
        stolen = database.claim_next_voice_item("isci-b", lease_seconds=60, now=future)
        assert stolen is not None and stolen.lease_owner == "isci-b"
        # Eski işçinin heartbeat'i artık reddedilir.
        assert not database.heartbeat_voice_item(item_id, "isci-a")

    def test_advance_requires_valid_lease_and_transition(self, tmp_path: Path) -> None:
        database, item_id, _ = self._seeded_item(tmp_path)
        claimed = database.claim_next_voice_item("isci-a", lease_seconds=60)
        assert claimed is not None
        with pytest.raises(LeaseLostError):
            database.advance_voice_item(item_id, "isci-b", VoiceItemStage.PARSED)
        advanced = database.advance_voice_item(
            item_id, "isci-a", VoiceItemStage.PARSED, release=False
        )
        assert advanced.stage == VoiceItemStage.PARSED
        from kitapkatalog.database import StateConflictError

        with pytest.raises(StateConflictError):
            database.advance_voice_item(
                item_id, "isci-a", VoiceItemStage.COMPLETED
            )  # PARSED -> COMPLETED geçişi yasak (EXTRACTED atlanamaz)

    def test_fail_retry_cycle(self, tmp_path: Path) -> None:
        database, item_id, job_id = self._seeded_item(tmp_path)
        for attempt in (1, 2, 3):
            claimed = database.claim_next_voice_item("isci-a", lease_seconds=60)
            assert claimed is not None, f"deneme {attempt} claim edilemedi"
            item = database.fail_voice_item(item_id, "isci-a", "sahte hata", max_retries=2)
        assert item.stage == VoiceItemStage.FAILED
        assert item.retry_count == 3
        job = database.get_voice_job(job_id)
        assert job is not None and job.failed_items == 1
        # Kullanıcı yeniden denetir -> SEGMENTED'e döner, iş yeniden koşar.
        retried = database.retry_failed_voice_item(item_id)
        assert retried.stage == VoiceItemStage.SEGMENTED
        assert retried.retry_count == 0


class TestCodexFixes:
    def test_job_lease_blocks_second_runner(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 10.0)
        scheduler, database, _fake = _scheduler(tmp_path, [])
        job = scheduler.enqueue(source)
        assert database.claim_voice_job(job.id, "yabanci-isci", lease_seconds=60)
        with pytest.raises(Exception, match="başka bir işçi"):
            scheduler.run_job(job.id)
        # Yabancı lease süresi dolunca iş devralınabilir.
        future = datetime.now(UTC) + timedelta(seconds=120)
        assert database.claim_voice_job(job.id, "test-worker", lease_seconds=60, now=future)

    def test_empty_transcript_finalizes_job(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "sessiz.wav", 5.0)
        scheduler, database, _fake = _scheduler(tmp_path, [()])
        job = scheduler.enqueue(source)
        summary = scheduler.run_job(job.id)
        assert summary.processed_items == 0
        refreshed = database.get_voice_job(job.id)
        assert refreshed is not None
        assert refreshed.status == ImportJobStatus.COMPLETED_WITH_ERRORS
        assert refreshed.finished_at is not None
        assert "söylemi bulunamadı" in (refreshed.last_error or "")

    def test_next_voice_wake_seconds_reports_retry_delay(self, tmp_path: Path) -> None:
        paths = _paths(tmp_path / "veri")
        database = Database(paths.database)
        job = database.create_voice_job(
            name="t", source_audio_path="/tmp/a.wav", source_sha256="fff"
        )
        database.insert_voice_items(
            job.id,
            [
                {
                    "item_key": "v1:00000",
                    "ordinal": 0,
                    "start_sample": 0,
                    "end_sample": 16000,
                    "transcript_json": "[]",
                }
            ],
        )
        assert database.next_voice_wake_seconds(job.id) is None
        item = database.claim_next_voice_item("isci", lease_seconds=60)
        assert item is not None
        database.fail_voice_item(item.id, "isci", "hata", max_retries=3, retry_delay_seconds=30)
        wake = database.next_voice_wake_seconds(job.id)
        assert wake is not None and 0 < wake <= 31


class TestLocationPersistence:
    def test_persist_parse_result_applies_location_to_all_copies(self, tmp_path: Path) -> None:
        from kitapkatalog.catalog import Catalog
        from kitapkatalog.voice_extractor import FieldClaim, VoiceParseResult
        from kitapkatalog.voice_scheduler import persist_parse_result

        paths = _paths(tmp_path / "veri")
        database = Database(paths.database)
        catalog = Catalog(database)
        result = VoiceParseResult(copy_count=3)
        for field_path, value in (("title", "Kar"), ("location", "A Dolabı")):
            result.claims.append(
                FieldClaim(
                    field_path=field_path,
                    value=value,
                    raw_text=value,
                    start_char=0,
                    end_char=0,
                    source="form",
                )
            )
        edition_id = persist_parse_result(catalog, result, fingerprint_base="voice:location-test")
        book = catalog.get_book(edition_id)
        assert book is not None
        assert len(book.copies) == 3
        assert {copy.location for copy in book.copies} == {"A Dolabı"}

    def test_form_result_carries_location_claim(self) -> None:
        from kitapkatalog.voice_controller import VoiceSession

        result = VoiceSession.form_result({"title": "Kar", "location": "B Dolabı"}, copy_count=1)
        assert result.value_of("location") == "B Dolabı"


class TestLanguageAndPromptChain:
    def test_chunk_transcription_passes_prompt_kwarg(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 5.0)
        scheduler, database, fake = _scheduler(tmp_path, [_TWO_BOOKS])
        from kitapkatalog.settings import AppSettings

        AppSettings(database).update({"voice_prompt_bias": "0"})
        job = scheduler.enqueue(source)
        scheduler.run_job(job.id)
        assert fake.call_kwargs, "whisper.transcribe hiç çağrılmadı"
        # Bias kapalıyken prompt None geçmeli; anahtar hâlâ verilir.
        assert all(call.get("prompt") is None for call in fake.call_kwargs)

    def test_chunk_transcription_includes_prompt_when_bias_enabled(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 5.0)
        scheduler, _database, fake = _scheduler(tmp_path, [_TWO_BOOKS])
        # voice_prompt_bias varsayılan olarak açık.
        job = scheduler.enqueue(source)
        scheduler.run_job(job.id)
        assert fake.call_kwargs
        assert all(call.get("prompt") for call in fake.call_kwargs)
        assert all("Başlık" in call["prompt"] for call in fake.call_kwargs)

    def test_whisper_factory_uses_configured_voice_language(self, tmp_path: Path) -> None:
        from kitapkatalog.database import Database as _Database
        from kitapkatalog.settings import AppSettings
        from kitapkatalog.voice_scheduler import build_voice_scheduler

        paths = _paths(tmp_path / "veri")
        database = _Database(paths.database)
        AppSettings(database).update({"voice_language": "auto"})
        scheduler = build_voice_scheduler(database, paths)
        client = scheduler.whisper_client_factory()
        assert client.language == "auto"

    def test_job_language_overrides_default_and_reaches_whisper(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 5.0)
        scheduler, _database, fake = _scheduler(tmp_path, [_TWO_BOOKS])
        job = scheduler.enqueue(source, language="en")
        assert job.language == "en"

        scheduler.run_job(job.id)

        assert fake.call_kwargs
        assert all(call.get("language") == "en" for call in fake.call_kwargs)

    def test_missing_job_language_defers_to_whisper_client_default(self, tmp_path: Path) -> None:
        source = _silent_wav(tmp_path / "kayit.wav", 5.0)
        scheduler, _database, fake = _scheduler(tmp_path, [_TWO_BOOKS])
        job = scheduler.enqueue(source)
        assert job.language is None

        scheduler.run_job(job.id)

        assert fake.call_kwargs
        assert all(call.get("language") is None for call in fake.call_kwargs)
