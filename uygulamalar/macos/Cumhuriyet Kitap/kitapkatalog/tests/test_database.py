from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog, InsufficientEvidenceError
from kitapkatalog.database import SCHEMA_VERSION, Database, LeaseLostError
from kitapkatalog.domain import (
    BookInput,
    ContributorInput,
    CopyInput,
    CoverRole,
    FieldObservation,
    FieldStatus,
    IdentifierInput,
    ImagePair,
    ImportJobStatus,
    JobItemStage,
    OcrEngine,
)


def _pair(number: int) -> ImagePair:
    return ImagePair(
        front=Path(f"/photos/{number:05d}_front.jpg"),
        back=Path(f"/photos/{number:05d}_back.jpg"),
        pair_key=f"book-{number:05d}",
    )


def _four_surface_pair(number: int) -> ImagePair:
    return ImagePair(
        front=Path(f"/photos/{number:05d}_front.jpg"),
        front_inside=Path(f"/photos/{number:05d}_front_inside.jpg"),
        back_inside=Path(f"/photos/{number:05d}_back_inside.jpg"),
        back=Path(f"/photos/{number:05d}_back.jpg"),
        pair_key=f"four-book-{number:05d}",
    )


def test_schema_uses_wal_foreign_keys_and_fts(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")

    with database.connection() as connection:
        assert connection.execute("PRAGMA journal_mode").fetchone()[0] == "wal"
        assert connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        tables = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
            )
        }

    assert database.integrity_check() == "ok"
    assert {
        "work",
        "edition",
        "copy",
        "import_job",
        "job_item",
        "ocr_engine_run",
        "resolved_field",
        "edition_fts",
        "voice_job",
        "voice_transcript_chunk",
        "voice_item",
    } <= tables


def test_nested_service_transactions_share_one_atomic_unit_of_work(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)

    with pytest.raises(RuntimeError, match="son adım"), database.transaction(immediate=True):
        record = catalog.save_book(BookInput(title="Geri Alınacak"))
        catalog.update_book(record.edition_id, {"publisher": "Geçici"})
        catalog.add_copy(record.edition_id)
        # get_book's readonly helper sees the same uncommitted connection.
        assert catalog.get_book(record.edition_id).publisher == "Geçici"
        raise RuntimeError("son adım başarısız")

    assert catalog.search("Geri Alınacak").total == 0

    # A nested failure rolled back to its savepoint can be handled by the
    # outer transaction without poisoning the connection.
    with database.transaction(immediate=True):
        kept = catalog.save_book(BookInput(title="Kalıcı"))
        with pytest.raises(ValueError), database.transaction():
            catalog.update_book(kept.edition_id, {"bilinmeyen_alan": "x"})
        catalog.update_book(kept.edition_id, {"publisher": "Güvenli"})
    assert catalog.get_book(kept.edition_id).publisher == "Güvenli"


def test_job_is_idempotent_and_requires_all_ten_engine_runs(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job(
        "Toplu raf",
        (_pair(index) for index in range(3)),
        idempotency_key="camera-roll-1",
    )
    duplicate = database.create_import_job("Tekrar", (_pair(99),), idempotency_key="camera-roll-1")

    assert duplicate.id == job.id
    assert duplicate.total_items == 3

    item = database.claim_next_item("worker-a", job_id=job.id)
    assert item is not None
    item = database.advance_item(
        item.id,
        "worker-a",
        JobItemStage.PREPROCESSED,
        expected_stage=JobItemStage.PAIRED,
    )

    completed = 0
    for role in (CoverRole.FRONT, CoverRole.BACK):
        for engine in OcrEngine:
            completed += 1
            item = database.record_engine_success(
                item.id,
                role,
                engine,
                cache_key=f"{item.id}-{role}-{engine}",
                text=f"{role} {engine}",
                worker_id="worker-a",
            )
            if completed < 10:
                assert item.stage == JobItemStage.PREPROCESSED
    assert item.stage == JobItemStage.OCR_COMPLETE
    statuses = database.get_engine_statuses(item.id)
    assert len(statuses) == 10


def test_four_surface_item_requires_all_twenty_engine_runs(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Dört yüz", [_four_surface_pair(1)])
    item = database.claim_next_item("worker-a", job_id=job.id)
    assert item is not None
    item = database.advance_item(
        item.id,
        "worker-a",
        JobItemStage.PREPROCESSED,
        expected_stage=JobItemStage.PAIRED,
    )

    completed = 0
    for role in CoverRole:
        for engine in OcrEngine:
            completed += 1
            item = database.record_engine_success(
                item.id,
                role,
                engine,
                cache_key=f"{role.value}-{engine.value}",
                worker_id="worker-a",
            )
            if completed < 20:
                assert item.stage == JobItemStage.PREPROCESSED

    assert item.stage == JobItemStage.OCR_COMPLETE
    assert len(database.get_engine_statuses(item.id)) == 20


def test_expired_lease_is_reclaimed_without_duplicate_item(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Raf", [_pair(1)])
    instant = datetime(2026, 7, 26, 10, 0, tzinfo=UTC)

    first = database.claim_next_item("dead-worker", job_id=job.id, lease_seconds=10, now=instant)
    assert first is not None
    assert (
        database.claim_next_item("new-worker", job_id=job.id, lease_seconds=10, now=instant) is None
    )
    reclaimed = database.claim_next_item(
        "new-worker",
        job_id=job.id,
        lease_seconds=10,
        now=instant + timedelta(seconds=11),
    )
    assert reclaimed is not None
    assert reclaimed.id == first.id
    with pytest.raises(LeaseLostError):
        database.advance_item(first.id, "dead-worker", JobItemStage.PREPROCESSED)


def test_engine_failure_retries_twice_then_fails_book(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Raf", [_pair(1)])
    item = database.claim_next_item("worker", job_id=job.id)
    assert item is not None
    item = database.advance_item(item.id, "worker", JobItemStage.PREPROCESSED)

    assert database.record_engine_failure(
        item.id, CoverRole.FRONT, OcrEngine.TESSERACT, "hata 1", worker_id="worker"
    )
    assert database.record_engine_failure(
        item.id, CoverRole.FRONT, OcrEngine.TESSERACT, "hata 2", worker_id="worker"
    )
    assert not database.record_engine_failure(
        item.id, CoverRole.FRONT, OcrEngine.TESSERACT, "hata 3", worker_id="worker"
    )
    failed = database.get_job_item(item.id)
    assert failed is not None and failed.stage == JobItemStage.FAILED
    finished = database.get_import_job(job.id)
    assert finished is not None
    assert finished.status == ImportJobStatus.COMPLETED_WITH_ERRORS
    assert finished.failed_items == 1


def test_user_retry_preserves_completed_engine_and_resets_failed_attempt_cycle(
    tmp_path: Path,
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Yeniden deneme", [_pair(1)])
    item = database.claim_next_item("worker-a", job_id=job.id)
    assert item is not None
    item = database.advance_item(item.id, "worker-a", JobItemStage.PREPROCESSED)
    database.record_engine_success(
        item.id,
        CoverRole.FRONT,
        OcrEngine.RAPIDOCR,
        cache_key="rapid-cache",
        text="tamamlandı",
        raw_result_path="/cache/rapid.json.zst",
        duration_ms=123,
        worker_id="worker-a",
    )
    for attempt in range(1, 4):
        retry_remains = database.record_engine_failure(
            item.id,
            CoverRole.FRONT,
            OcrEngine.TESSERACT,
            f"hata {attempt}",
            worker_id="worker-a",
        )
        assert retry_remains is (attempt < 3)

    retried = database.retry_failed_item(item.id)
    assert retried.stage == JobItemStage.PAIRED
    rows = {
        (row["cover_role"], row["engine_name"]): row
        for row in database.fetchall(
            """
            SELECT cover_role, engine_name, status, attempt_count, cache_key,
                   raw_result_path, text, error, duration_ms
            FROM job_item_engine WHERE item_id = ?
            """,
            (item.id,),
        )
    }
    completed = rows[(CoverRole.FRONT.value, OcrEngine.RAPIDOCR.value)]
    assert completed["status"] == "completed"
    assert completed["attempt_count"] == 1
    assert completed["cache_key"] == "rapid-cache"
    assert completed["raw_result_path"] == "/cache/rapid.json.zst"
    assert completed["text"] == "tamamlandı"
    assert completed["duration_ms"] == 123
    failed = rows[(CoverRole.FRONT.value, OcrEngine.TESSERACT.value)]
    assert failed["status"] == "pending"
    assert failed["attempt_count"] == 0
    assert all(
        failed[name] is None
        for name in ("cache_key", "raw_result_path", "text", "error", "duration_ms")
    )

    claimed = database.claim_next_item("worker-b", job_id=job.id)
    assert claimed is not None
    database.advance_item(claimed.id, "worker-b", JobItemStage.PREPROCESSED)
    assert database.record_engine_failure(
        claimed.id,
        CoverRole.FRONT,
        OcrEngine.TESSERACT,
        "yeni hata 1",
        worker_id="worker-b",
    )
    assert database.record_engine_failure(
        claimed.id,
        CoverRole.FRONT,
        OcrEngine.TESSERACT,
        "yeni hata 2",
        worker_id="worker-b",
    )
    assert not database.record_engine_failure(
        claimed.id,
        CoverRole.FRONT,
        OcrEngine.TESSERACT,
        "yeni hata 3",
        worker_id="worker-b",
    )


def test_same_isbn_is_one_edition_with_multiple_idempotent_copies(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    identity = IdentifierInput("ISBN-13", "978-0-14-044913-6")
    first = catalog.save_book(
        BookInput(
            title="İnce Memed",
            publisher="Yapı Kredi Yayınları",
            identifiers=(identity,),
            contributors=(ContributorInput("Yaşar Kemal"),),
            copy=CopyInput(source_fingerprint="photo-pair-a"),
        )
    )
    second = catalog.save_book(
        BookInput(
            title="İnce Memed",
            identifiers=(identity,),
            copy=CopyInput(source_fingerprint="photo-pair-b"),
        )
    )
    repeated = catalog.save_book(
        BookInput(
            title="İnce Memed",
            identifiers=(identity,),
            copy=CopyInput(source_fingerprint="photo-pair-b"),
        )
    )

    assert first.edition_id == second.edition_id == repeated.edition_id
    assert len(repeated.copies) == 2
    assert catalog.search("İnce").total == 1
    assert catalog.search("ince").total == 1
    assert catalog.search("Yaşar").total == 1
    assert catalog.search("yasar").total == 1
    assert catalog.search("978014").total == 1
    assert catalog.stats() == {
        "works": 1,
        "editions": 1,
        "copies": 2,
        "review": 1,
    }


def test_user_lock_survives_machine_reprocessing(tmp_path: Path) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    identity = IdentifierInput("ISBN13", "9780140449136")
    record = catalog.save_book(BookInput(title="Kitap", publisher="Eski", identifiers=(identity,)))
    catalog.update_book(record.edition_id, {"publisher": "Kullanıcı Değeri"})

    rerun = catalog.save_book(
        BookInput(
            title="Kitap",
            publisher="Yeni OCR Değeri",
            identifiers=(identity,),
        ),
        overwrite=True,
    )

    assert rerun.publisher == "Kullanıcı Değeri"


def test_user_lock_uses_canonical_path_and_blocks_legacy_or_canonical_ocr(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    record = catalog.save_book(BookInput(title="Kitap", publisher="İlk OCR"))
    catalog.update_book(record.edition_id, {"publisher": "Kullanıcı Değeri"})
    stored = catalog.db.fetchall(
        """
        SELECT field_path, value, user_locked
        FROM resolved_field WHERE edition_id = ?
        """,
        (record.edition_id,),
    )
    assert [tuple(row) for row in stored] == [("edition.publisher", "Kullanıcı Değeri", 1)]

    observation = catalog.add_observation(
        FieldObservation(
            field_path="edition.publisher",
            raw_value="Yeni OCR",
            normalized_value="Yeni OCR",
            cover_role=CoverRole.BACK,
            confidence=0.99,
            source_token_ids=("tess:1", "easy:1"),
            engine_evidence=(OcrEngine.TESSERACT, OcrEngine.EASYOCR),
            polygon=((0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (0.0, 1.0)),
            source_polygon=((10.0, 10.0), (12.0, 10.0), (12.0, 11.0), (10.0, 11.0)),
        ),
        edition_id=record.edition_id,
    )
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Yeni OCR",
        status=FieldStatus.AUTO,
        observation_id=observation,
    )
    assert catalog.get_book(record.edition_id).publisher == "Kullanıcı Değeri"

    # Simulate a database written by the earlier short-path taxonomy.
    with catalog.db.transaction(immediate=True) as connection:
        connection.execute(
            """
            UPDATE resolved_field SET field_path = 'publisher'
            WHERE edition_id = ? AND field_path = 'edition.publisher'
            """,
            (record.edition_id,),
        )
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Yeni OCR",
        status=FieldStatus.AUTO,
        observation_id=observation,
    )
    assert catalog.get_book(record.edition_id).publisher == "Kullanıcı Değeri"

    # Touching a legacy user value migrates it back to the canonical path.
    catalog.update_book(record.edition_id, {"publisher": "Son Kullanıcı Değeri"})
    stored = catalog.db.fetchall(
        """
        SELECT field_path, value, user_locked
        FROM resolved_field WHERE edition_id = ?
        """,
        (record.edition_id,),
    )
    assert [tuple(row) for row in stored] == [("edition.publisher", "Son Kullanıcı Değeri", 1)]


def test_equivalent_isbn10_and_isbn13_do_not_split_an_edition(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    isbn10 = catalog.save_book(
        BookInput(
            title="The Odyssey",
            identifiers=(IdentifierInput("ISBN10", "0140449132"),),
            copy=CopyInput(source_fingerprint="copy-10"),
        )
    )
    isbn13 = catalog.save_book(
        BookInput(
            title="The Odyssey",
            identifiers=(IdentifierInput("ISBN13", "9780140449136"),),
            copy=CopyInput(source_fingerprint="copy-13"),
        )
    )

    assert isbn10.edition_id == isbn13.edition_id
    assert len(isbn13.identifiers) == 2
    assert len(isbn13.copies) == 2


def test_automatic_field_requires_two_engines_and_positioned_evidence(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    record = catalog.save_book(BookInput(title="Taslak"))
    weak = catalog.add_observation(
        FieldObservation(
            field_path="title",
            raw_value="Kanıtsız",
            normalized_value="Kanıtsız",
            cover_role=CoverRole.FRONT,
            confidence=0.999,
            source_token_ids=("vl:1",),
            engine_evidence=(OcrEngine.PADDLEOCR_VL, OcrEngine.SURYA),
            polygon=None,
        ),
        edition_id=record.edition_id,
    )
    with pytest.raises(InsufficientEvidenceError):
        catalog.resolve_field(
            record.edition_id,
            "title",
            "Kanıtsız",
            status=FieldStatus.AUTO,
            observation_id=weak,
        )

    grounded = catalog.add_observation(
        FieldObservation(
            field_path="title",
            raw_value="Kanıtlı",
            normalized_value="Kanıtlı",
            cover_role=CoverRole.FRONT,
            confidence=0.99,
            source_token_ids=("tess:1", "vl:1"),
            engine_evidence=(OcrEngine.TESSERACT, OcrEngine.PADDLEOCR_VL),
            polygon=((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)),
            source_polygon=((10.0, 20.0), (30.0, 20.0), (30.0, 40.0), (10.0, 40.0)),
        ),
        edition_id=record.edition_id,
    )
    assert catalog.resolve_field(
        record.edition_id,
        "title",
        "Kanıtlı",
        status=FieldStatus.AUTO,
        observation_id=grounded,
    )
    assert catalog.get_book(record.edition_id).title == "Kanıtlı"
    assert (
        catalog.db.fetchone(
            """
            SELECT w.canonical_title
            FROM work AS w JOIN edition AS e ON e.work_id = w.id
            WHERE e.id = ?
            """,
            (record.edition_id,),
        )[0]
        == "Kanıtlı"
    )
    stored = catalog.db.fetchone(
        "SELECT polygon_json, source_polygon_json FROM field_observation WHERE id = ?",
        (grounded,),
    )
    assert stored is not None
    assert stored["polygon_json"] != stored["source_polygon_json"]


def test_machine_field_resolution_never_downgrades_existing_evidence(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    record = catalog.save_book(BookInput(title="Kitap"))

    def observation(value: str, confidence: float) -> int:
        return catalog.add_observation(
            FieldObservation(
                field_path="edition.publisher",
                raw_value=value,
                normalized_value=value,
                cover_role=CoverRole.FRONT,
                confidence=confidence,
                source_token_ids=(f"tess:{confidence}", f"easy:{confidence}"),
                engine_evidence=(OcrEngine.TESSERACT, OcrEngine.EASYOCR),
                polygon=((0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (0.0, 1.0)),
                source_polygon=(
                    (10.0, 10.0),
                    (12.0, 10.0),
                    (12.0, 11.0),
                    (10.0, 11.0),
                ),
            ),
            edition_id=record.edition_id,
        )

    strong_review = observation("Doğru Yayınları", 0.96)
    assert catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Doğru Yayınları",
        status=FieldStatus.REVIEW,
        observation_id=strong_review,
    )
    weak_review = observation("Eksik Yayınları", 0.85)
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Eksik Yayınları",
        status=FieldStatus.REVIEW,
        observation_id=weak_review,
    )
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "bilinmiyor",
        status=FieldStatus.UNRESOLVED,
    )
    assert catalog.get_book(record.edition_id).publisher == "Doğru Yayınları"

    automatic = observation("Kanıtlı Yayınları", 0.99)
    assert catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Kanıtlı Yayınları",
        status=FieldStatus.AUTO,
        observation_id=automatic,
    )
    later_review = observation("Daha Sonraki Yayınları", 0.999)
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Daha Sonraki Yayınları",
        status=FieldStatus.REVIEW,
        observation_id=later_review,
    )
    assert catalog.get_book(record.edition_id).publisher == "Kanıtlı Yayınları"


def test_confirmed_field_is_stable_and_force_explicitly_bypasses_monotonic_guard(
    tmp_path: Path,
) -> None:
    catalog = Catalog(tmp_path / "catalog.sqlite3")
    record = catalog.save_book(BookInput(title="Kitap"))
    assert catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Onaylı Yayınları",
        status=FieldStatus.CONFIRMED,
    )
    observation = catalog.add_observation(
        FieldObservation(
            field_path="edition.publisher",
            raw_value="Yeni Yayınları",
            normalized_value="Yeni Yayınları",
            cover_role=CoverRole.FRONT,
            confidence=0.99,
            source_token_ids=("tess:new", "easy:new"),
            engine_evidence=(OcrEngine.TESSERACT, OcrEngine.EASYOCR),
            polygon=((0.0, 0.0), (2.0, 0.0), (2.0, 1.0), (0.0, 1.0)),
            source_polygon=((10.0, 10.0), (12.0, 10.0), (12.0, 11.0), (10.0, 11.0)),
        ),
        edition_id=record.edition_id,
    )
    assert not catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Yeni Yayınları",
        status=FieldStatus.AUTO,
        observation_id=observation,
    )
    assert catalog.get_book(record.edition_id).publisher == "Onaylı Yayınları"
    assert catalog.resolve_field(
        record.edition_id,
        "edition.publisher",
        "Yeni Yayınları",
        status=FieldStatus.AUTO,
        observation_id=observation,
        force=True,
    )
    assert catalog.get_book(record.edition_id).publisher == "Yeni Yayınları"


def test_item_edition_link_is_lease_safe_and_does_not_advance_stage(
    tmp_path: Path,
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    job = database.create_import_job("Bağlantı", [_pair(5)])
    item = database.claim_next_item("worker-a", job_id=job.id)
    assert item is not None
    item = database.advance_item(
        item.id,
        "worker-a",
        JobItemStage.PREPROCESSED,
        expected_stage=JobItemStage.PAIRED,
    )
    for role in (CoverRole.FRONT, CoverRole.BACK):
        for engine in OcrEngine:
            item = database.record_engine_success(
                item.id,
                role,
                engine,
                cache_key=f"{role.value}-{engine.value}",
                worker_id="worker-a",
            )
    item = database.advance_item(
        item.id,
        "worker-a",
        JobItemStage.RECONCILED,
        expected_stage=JobItemStage.OCR_COMPLETE,
    )
    record = catalog.save_book(BookInput(title="Henüz tamamlanmadı"))

    with pytest.raises(LeaseLostError):
        database.link_item_edition(item.id, "worker-b", record.edition_id)
    linked = database.link_item_edition(item.id, "worker-a", record.edition_id)
    assert linked.edition_id == record.edition_id
    assert linked.stage == JobItemStage.RECONCILED
