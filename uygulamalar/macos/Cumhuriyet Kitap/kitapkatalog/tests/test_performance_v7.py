"""v7 performance contracts: indexes, narrow lists and O(1) job counters."""

from __future__ import annotations

import sqlite3
import time
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import SCHEMA_VERSION, Database
from kitapkatalog.domain import (
    BookInput,
    CopyInput,
    ImagePair,
    ImportJobStatus,
    JobItemStage,
    SearchFilters,
    VoiceItemStage,
)

V7_INDEXES = {
    "idx_edition_title_nocase",
    "idx_edition_created_id",
    "idx_edition_publisher_unicode_title",
    "idx_edition_language_unicode_title",
    "idx_edition_category_unicode_title",
    "idx_edition_review_title",
    "idx_edition_publication_year",
    "idx_copy_edition_status_location",
    "idx_job_item_pair_review",
    "idx_loan_loaned_at",
    "idx_loan_returned_at",
}


def _pair(index: int, *, needs_review: bool = False) -> ImagePair:
    return ImagePair(
        front=Path(f"/tmp/v7-{index}-front.jpg"),
        back=Path(f"/tmp/v7-{index}-back.jpg"),
        pair_key=f"v7-{index}",
        needs_review=needs_review,
    )


def _voice_items(count: int) -> list[dict[str, object]]:
    return [
        {
            "item_key": f"v1:{index:05d}",
            "ordinal": index,
            "start_sample": index * 16_000,
            "end_sample": (index + 1) * 16_000,
            "transcript_json": "[]",
        }
        for index in range(count)
    ]


def _lease_at_stage(
    database: Database,
    table: str,
    item_id: int,
    stage: str,
    *,
    worker: str = "v7-worker",
) -> None:
    assert table in {"job_item", "voice_item"}
    with database.transaction(immediate=True) as connection:
        connection.execute(
            f"""
            UPDATE {table}
            SET stage = ?, lease_owner = ?, lease_until = '9999-12-31T23:59:59Z'
            WHERE id = ?
            """,
            (stage, worker, item_id),
        )


def _capture_sql(database: Database, monkeypatch: pytest.MonkeyPatch) -> list[str]:
    statements: list[str] = []
    original = database._new_connection

    def traced(*, readonly: bool = False):
        connection = original(readonly=readonly)
        connection.set_trace_callback(statements.append)
        return connection

    monkeypatch.setattr(database, "_new_connection", traced)
    return statements


def _assert_no_counter_scan(statements: list[str], table: str) -> None:
    normalized = [" ".join(statement.upper().split()) for statement in statements]
    assert not any(
        statement.startswith("SELECT")
        and ("SUM(CASE" in statement or "COUNT(*)" in statement)
        and f"FROM {table.upper()} WHERE JOB_ID" in statement
        for statement in normalized
    )


def test_v7_schema_has_exact_indexes_and_expected_query_plans(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    catalog.save_book(
        BookInput(
            title="Plan Kitabı",
            publisher="Deneme",
            copy=CopyInput(location="Dolap A"),
        )
    )

    with database.connection(readonly=True) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert SCHEMA_VERSION >= 7
        indexes = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'index'"
            )
        }
        assert indexes >= V7_INDEXES
        assert connection.execute(
            "SELECT 1 FROM schema_migration WHERE version = 7"
        ).fetchone()

        title_plan = " ".join(
            row["detail"]
            for row in connection.execute(
                """
                EXPLAIN QUERY PLAN
                SELECT e.id FROM edition AS e
                ORDER BY e.title COLLATE NOCASE, e.id LIMIT 50 OFFSET 9950
                """
            )
        )
        assert "idx_edition_title_nocase" in title_plan
        assert "TEMP B-TREE FOR ORDER BY" not in title_plan

        availability_plan = " ".join(
            row["detail"]
            for row in connection.execute(
                """
                EXPLAIN QUERY PLAN
                SELECT e.id FROM edition AS e
                WHERE EXISTS(
                    SELECT 1 FROM copy AS ac
                    WHERE ac.edition_id = e.id AND ac.status = 'active'
                      AND ac.location = 'Dolap A' AND NOT EXISTS(
                          SELECT 1 FROM loan
                          WHERE loan.copy_id = ac.id AND loan.returned_at IS NULL
                      )
                )
                ORDER BY e.title COLLATE NOCASE, e.id LIMIT 50
                """
            )
        )
        assert "idx_copy_edition_status_location" in availability_plan


def test_search_and_list_do_not_read_raw_ocr_but_detail_does(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    saved = catalog.save_book(BookInput(title="OCR Kitabı", copy=CopyInput(location="A")))
    raw_text = "çok büyük ham ocr " * 10_000
    catalog.set_raw_ocr_text(saved.edition_id, raw_text)

    reads: list[tuple[str | None, str | None]] = []
    original = database._new_connection

    def watched(*, readonly: bool = False):
        connection = original(readonly=readonly)

        def authorizer(
            action: int,
            arg1: str | None,
            arg2: str | None,
            _database_name: str | None,
            _trigger_name: str | None,
        ) -> int:
            if action == sqlite3.SQLITE_READ:
                reads.append((arg1, arg2))
            return sqlite3.SQLITE_OK

        connection.set_authorizer(authorizer)
        return connection

    monkeypatch.setattr(database, "_new_connection", watched)

    page = catalog.search(limit=10)
    assert page.items[0].raw_ocr_text is None
    assert ("edition", "raw_ocr_text") not in reads

    reads.clear()
    listed = catalog.list_books(limit=10)
    assert listed[0].raw_ocr_text is None
    assert ("edition", "raw_ocr_text") not in reads

    reads.clear()
    detail = catalog.get_book(saved.edition_id)
    assert detail is not None and detail.raw_ocr_text == raw_text
    assert ("edition", "raw_ocr_text") in reads


def test_import_terminal_counters_use_deltas_for_review_retry_and_cancel(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Delta", [_pair(index) for index in range(4)])
    database.set_job_status(job.id, ImportJobStatus.RUNNING)
    item_ids = [item.id for item in database.list_job_items(job.id)]
    statements = _capture_sql(database, monkeypatch)

    _lease_at_stage(database, "job_item", item_ids[0], JobItemStage.EXTRACTED.value)
    database.advance_item(item_ids[0], "v7-worker", JobItemStage.COMPLETED)

    _lease_at_stage(database, "job_item", item_ids[1], JobItemStage.EXTRACTED.value)
    database.advance_item(item_ids[1], "v7-worker", JobItemStage.REVIEW)
    _lease_at_stage(database, "job_item", item_ids[1], JobItemStage.REVIEW.value)
    database.advance_item(item_ids[1], "v7-worker", JobItemStage.COMPLETED)

    _lease_at_stage(database, "job_item", item_ids[2], JobItemStage.PAIRED.value)
    database.fail_item(item_ids[2], "v7-worker", "hata", max_retries=0)
    failed = database.get_import_job(job.id)
    assert failed is not None
    assert (failed.successful_items, failed.failed_items, failed.review_items) == (2, 1, 0)

    database.retry_failed_item(item_ids[2])
    retried = database.get_import_job(job.id)
    assert retried is not None
    assert (retried.successful_items, retried.failed_items, retried.review_items) == (2, 0, 0)

    _lease_at_stage(database, "job_item", item_ids[2], JobItemStage.PAIRED.value)
    database.fail_item(item_ids[2], "v7-worker", "yine hata", max_retries=0)
    cancelled = database.cancel_job(job.id)
    assert cancelled.status == ImportJobStatus.CANCELLED
    assert cancelled.total_items == 4
    assert (cancelled.successful_items, cancelled.failed_items, cancelled.review_items) == (
        2,
        2,
        0,
    )
    _assert_no_counter_scan(statements, "job_item")


def test_pair_rejection_updates_counter_without_reconcile(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Eşleştirme", [_pair(1, needs_review=True)])
    statements = _capture_sql(database, monkeypatch)

    item = database.list_job_items(job.id)[0]
    rejected = database.approve_pair(item.id, approved=False)
    assert rejected.stage == JobItemStage.FAILED
    finished = database.get_import_job(job.id)
    assert finished is not None
    assert finished.status == ImportJobStatus.COMPLETED_WITH_ERRORS
    assert finished.failed_items == 1
    _assert_no_counter_scan(statements, "job_item")


def test_voice_terminal_counters_use_deltas_for_review_retry_and_cancel(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_voice_job(name="Ses Delta", source_audio_path="/tmp/ses.wav")
    database.insert_voice_items(job.id, _voice_items(4))
    database.set_voice_job_status(job.id, ImportJobStatus.RUNNING)
    item_ids = [item.id for item in database.list_voice_items(job.id)]
    statements = _capture_sql(database, monkeypatch)

    _lease_at_stage(database, "voice_item", item_ids[0], VoiceItemStage.EXTRACTED.value)
    database.advance_voice_item(item_ids[0], "v7-worker", VoiceItemStage.COMPLETED)

    _lease_at_stage(database, "voice_item", item_ids[1], VoiceItemStage.EXTRACTED.value)
    database.advance_voice_item(item_ids[1], "v7-worker", VoiceItemStage.REVIEW)
    _lease_at_stage(database, "voice_item", item_ids[1], VoiceItemStage.REVIEW.value)
    database.advance_voice_item(item_ids[1], "v7-worker", VoiceItemStage.COMPLETED)

    _lease_at_stage(database, "voice_item", item_ids[2], VoiceItemStage.SEGMENTED.value)
    database.fail_voice_item(item_ids[2], "v7-worker", "hata", max_retries=0)
    failed = database.get_voice_job(job.id)
    assert failed is not None
    assert (failed.successful_items, failed.failed_items, failed.review_items) == (2, 1, 0)

    database.retry_failed_voice_item(item_ids[2])
    retried = database.get_voice_job(job.id)
    assert retried is not None
    assert (retried.successful_items, retried.failed_items, retried.review_items) == (2, 0, 0)

    _lease_at_stage(database, "voice_item", item_ids[2], VoiceItemStage.SEGMENTED.value)
    database.fail_voice_item(item_ids[2], "v7-worker", "yine hata", max_retries=0)
    cancelled = database.cancel_voice_job(job.id)
    assert cancelled.status == ImportJobStatus.CANCELLED
    assert cancelled.total_items == 4
    assert (cancelled.successful_items, cancelled.failed_items, cancelled.review_items) == (
        2,
        2,
        0,
    )
    _assert_no_counter_scan(statements, "voice_item")


def test_explicit_reconcile_repairs_corrupt_import_and_voice_counters(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    import_job = database.create_import_job("Onarım", [_pair(1), _pair(2)])
    voice_job = database.create_voice_job(name="Ses Onarım", source_audio_path="/tmp/ses.wav")
    database.insert_voice_items(voice_job.id, _voice_items(2))

    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET stage = 'completed' WHERE job_id = ? AND id = "
            "(SELECT MIN(id) FROM job_item WHERE job_id = ?)",
            (import_job.id, import_job.id),
        )
        connection.execute(
            "UPDATE import_job SET total_items = 99, successful_items = 0 WHERE id = ?",
            (import_job.id,),
        )
        connection.execute(
            "UPDATE voice_item SET stage = 'review' WHERE job_id = ? AND id = "
            "(SELECT MIN(id) FROM voice_item WHERE job_id = ?)",
            (voice_job.id, voice_job.id),
        )
        connection.execute(
            "UPDATE voice_job SET total_items = 99, review_items = 0 WHERE id = ?",
            (voice_job.id,),
        )

    repaired_import = database.reconcile_job_counts(import_job.id)
    repaired_voice = database.reconcile_voice_job_counts(voice_job.id)
    assert (repaired_import.total_items, repaired_import.successful_items) == (2, 1)
    assert (repaired_voice.total_items, repaired_voice.review_items) == (2, 1)


def test_v6_upgrade_reconciles_existing_counters_before_delta_mode(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    import_job = database.create_import_job("Eski", [_pair(1), _pair(2)])
    voice_job = database.create_voice_job(name="Eski Ses", source_audio_path="/tmp/ses.wav")
    database.insert_voice_items(voice_job.id, _voice_items(2))

    with database.transaction(immediate=True) as connection:
        import_ids = [
            row[0]
            for row in connection.execute(
                "SELECT id FROM job_item WHERE job_id = ? ORDER BY id", (import_job.id,)
            )
        ]
        voice_ids = [
            row[0]
            for row in connection.execute(
                "SELECT id FROM voice_item WHERE job_id = ? ORDER BY id", (voice_job.id,)
            )
        ]
        connection.execute("UPDATE job_item SET stage = 'completed' WHERE id = ?", (import_ids[0],))
        connection.execute("UPDATE job_item SET stage = 'cancelled' WHERE id = ?", (import_ids[1],))
        connection.execute(
            "UPDATE voice_item SET stage = 'completed' WHERE id = ?", (voice_ids[0],)
        )
        connection.execute("UPDATE voice_item SET stage = 'review' WHERE id = ?", (voice_ids[1],))
        connection.execute(
            """
            UPDATE import_job
            SET total_items = 88, successful_items = 0, failed_items = 0, review_items = 0
            WHERE id = ?
            """,
            (import_job.id,),
        )
        connection.execute(
            """
            UPDATE voice_job
            SET total_items = 77, successful_items = 0, failed_items = 0, review_items = 0
            WHERE id = ?
            """,
            (voice_job.id,),
        )
        connection.executescript(
            """
            DROP TRIGGER circulation_event_no_update;
            DROP TRIGGER circulation_event_no_delete;
            DROP TABLE circulation_event;
            DROP TRIGGER loan_snapshot_required;
            DROP TRIGGER loan_snapshot_immutable;
            DROP TRIGGER loan_one_active_edition_insert;
            DROP TRIGGER loan_one_active_edition_update;
            DROP INDEX idx_loan_active_member_edition;
            DROP INDEX IF EXISTS idx_edition_title_nocase;
            DROP INDEX IF EXISTS idx_edition_created_id;
            DROP INDEX IF EXISTS idx_edition_publisher_unicode_title;
            DROP INDEX IF EXISTS idx_edition_language_unicode_title;
            DROP INDEX IF EXISTS idx_edition_category_unicode_title;
            DROP INDEX IF EXISTS idx_edition_review_title;
            DROP INDEX IF EXISTS idx_edition_publication_year;
            DROP INDEX IF EXISTS idx_copy_edition_status_location;
            DROP INDEX IF EXISTS idx_job_item_pair_review;
            DROP INDEX IF EXISTS idx_loan_loaned_at;
            DROP INDEX IF EXISTS idx_loan_returned_at;
            ALTER TABLE loan DROP COLUMN snapshot_source;
            ALTER TABLE loan DROP COLUMN academic_period_snapshot;
            ALTER TABLE loan DROP COLUMN member_type_snapshot;
            ALTER TABLE loan DROP COLUMN member_class_snapshot;
            ALTER TABLE loan DROP COLUMN member_number_snapshot;
            ALTER TABLE loan DROP COLUMN member_name_snapshot;
            DELETE FROM schema_migration WHERE version >= 7;
            """
        )
        connection.execute("PRAGMA user_version = 6")

    upgraded = Database(path)
    repaired_import = upgraded.get_import_job(import_job.id)
    repaired_voice = upgraded.get_voice_job(voice_job.id)
    assert repaired_import is not None and repaired_voice is not None
    assert (
        repaired_import.total_items,
        repaired_import.successful_items,
        repaired_import.failed_items,
        repaired_import.review_items,
    ) == (2, 1, 1, 0)
    assert (
        repaired_voice.total_items,
        repaired_voice.successful_items,
        repaired_voice.failed_items,
        repaired_voice.review_items,
    ) == (2, 1, 0, 1)


def test_10k_location_availability_gate_is_bounded(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    raw_ocr = "x" * 4096
    now = "2026-08-08T00:00:00Z"
    with database.transaction(immediate=True) as connection:
        connection.execute(
            """
            INSERT INTO work(id, canonical_title, created_at, updated_at)
            VALUES (1, 'Performans', ?, ?)
            """,
            (now, now),
        )
        connection.executemany(
            """
            INSERT INTO edition(
                id, work_id, title, publisher, language, category,
                review_status, raw_ocr_text, created_at, updated_at
            ) VALUES (?, 1, ?, 'Yayınevi', 'Türkçe', 'Roman', 'completed', ?, ?, ?)
            """,
            ((index, f"Kitap {index:05d}", raw_ocr, now, now) for index in range(1, 10_001)),
        )
        connection.executemany(
            """
            INSERT INTO copy(edition_id, location, status, created_at, updated_at)
            VALUES (?, 'Dolap A', 'active', ?, ?)
            """,
            ((index, now, now) for index in range(1, 10_001)),
        )

    started = time.perf_counter()
    page = Catalog(database).search(
        filters=SearchFilters(location="Dolap A", availability="available"),
        limit=50,
    )
    elapsed = time.perf_counter() - started
    assert page.total == 10_000
    assert len(page.items) == 50
    assert all(item.raw_ocr_text is None for item in page.items)
    # Deliberately loose CI wall-clock gate; query-plan tests above carry the
    # deterministic regression signal while this catches catastrophic scans.
    assert elapsed < 2.0, f"10k konum+müsaitlik araması {elapsed:.3f} saniye sürdü"
