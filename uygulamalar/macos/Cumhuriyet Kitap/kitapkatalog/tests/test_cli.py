from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

from kitapkatalog.archive import inspect_archive
from kitapkatalog.capacity import CapacityEstimate
from kitapkatalog.catalog import Catalog
from kitapkatalog.cli import main
from kitapkatalog.database import SCHEMA_VERSION, Database, _unicode_nocase
from kitapkatalog.domain import (
    BookInput,
    CoverRole,
    ImagePair,
    ImportJobStatus,
    JobItemStage,
    OcrEngine,
)
from kitapkatalog.offline import _uninstall_for_tests, network_guard_installed


@pytest.fixture(autouse=True)
def restore_network_guard() -> None:
    _uninstall_for_tests()
    yield
    _uninstall_for_tests()


def test_init_installs_network_guard_and_creates_database(tmp_path: Path, capsys) -> None:
    database = tmp_path / "catalog.sqlite3"

    code = main(["--database", str(database), "--json", "init"])

    assert code == 0
    assert database.exists()
    assert network_guard_installed()
    payload = json.loads(capsys.readouterr().out)
    assert payload["integrity"] == "ok"


def test_init_upgrades_v7_only_after_verified_backup(tmp_path: Path, capsys) -> None:
    database = tmp_path / "catalog.sqlite3"
    with sqlite3.connect(database, isolation_level=None) as connection:
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        connection.execute("PRAGMA foreign_keys = ON")
        for version in range(1, 8):
            getattr(Database, f"_migrate_v{version}")(connection)

    code = main(["--database", str(database), "--json", "init"])

    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["integrity"] == "ok"
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
    backups = list(
        (tmp_path / "yedekler").glob(
            f"surum-yukseltme-oncesi-v7-v{SCHEMA_VERSION}-*.kitaparsiv"
        )
    )
    assert len(backups) == 1
    assert inspect_archive(backups[0]).database_size > 0


def test_import_pairs_images_and_persists_job(tmp_path: Path, capsys) -> None:
    photos = tmp_path / "photos"
    photos.mkdir()
    for name in ("a_front.jpg", "a_back.jpg", "b_on.png", "b_arka.png"):
        (photos / name).touch()
    database_path = tmp_path / "catalog.sqlite3"

    code = main(
        [
            "--database",
            str(database_path),
            "--json",
            "import",
            str(photos),
            "--no-sequence",
        ]
    )

    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["pairs"] == 2
    assert payload["storage_mode"] == "managed_copy"
    assert payload["capacity"]["sufficient"]
    jobs = Database(database_path).list_import_jobs()
    assert len(jobs) == 1
    assert jobs[0].total_items == 2


def test_import_expands_a_zip_source_and_keeps_extracted_files_for_later_processing(
    tmp_path: Path, capsys
) -> None:
    import zipfile

    zip_path = tmp_path / "arsiv.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        for name in ("a_front.jpg", "a_back.jpg", "b_on.png", "b_arka.png"):
            archive.writestr(name, b"")
    database_path = tmp_path / "catalog.sqlite3"

    code = main(
        [
            "--database",
            str(database_path),
            "--json",
            "import",
            str(zip_path),
            "--no-sequence",
        ]
    )

    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["pairs"] == 2
    assert payload["documents"] == 4

    jobs = Database(database_path).list_import_jobs()
    assert len(jobs) == 1
    items = Database(database_path).list_job_items(jobs[0].id, limit=10)
    assert len(items) == 2
    # MANAGED_COPY yalnızca kaynak yolunu kaydeder; asıl kopyalama ancak
    # sonraki bir `run` çağrısında olur. ZIP açılım dizini bu komuttan
    # hemen sonra silinseydi bu yollar artık var olmazdı.
    for item in items:
        assert Path(item.front_path).is_file()
        assert Path(item.back_path).is_file()


def test_import_refuses_a_zip_source_combined_with_reference_mode(
    tmp_path: Path, capsys
) -> None:
    import zipfile

    zip_path = tmp_path / "arsiv.zip"
    with zipfile.ZipFile(zip_path, "w") as archive:
        archive.writestr("a_front.jpg", b"")
    database_path = tmp_path / "catalog.sqlite3"

    with pytest.raises(SystemExit):
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "import",
                str(zip_path),
                "--reference",
            ]
        )


def test_single_and_bulk_four_surface_commands_are_separate(tmp_path: Path, capsys) -> None:
    single_documents: list[str] = []
    for role in ("front", "front_inside", "back_inside", "back"):
        path = tmp_path / f"single_{role}.jpg"
        path.touch()
        single_documents.append(str(path))
    database_path = tmp_path / "catalog.sqlite3"

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "import-single",
                *single_documents,
            ]
        )
        == 0
    )
    single = json.loads(capsys.readouterr().out)
    assert single["mode"] == "single"
    assert single["surfaces"] == 4

    bulk = tmp_path / "bulk"
    bulk.mkdir()
    for role in ("on", "on_ic", "arka_ic", "arka"):
        (bulk / f"book_{role}.jpg").touch()
    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "import-bulk",
                str(bulk),
                "--no-sequence",
            ]
        )
        == 0
    )
    bulk_result = json.loads(capsys.readouterr().out)
    assert bulk_result["mode"] == "bulk"
    assert bulk_result["books"] == 1
    assert bulk_result["surfaces"] == 4
    jobs = Database(database_path).list_import_jobs()
    assert sorted(job.total_items for job in jobs) == [1, 1]


def test_search_and_export_commands_work_headlessly(tmp_path: Path, capsys) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(database_path)
    catalog.save_book(BookInput(title="Saatleri Ayarlama Enstitüsü"))

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "search",
                "Saatleri",
            ]
        )
        == 0
    )
    payload = json.loads(capsys.readouterr().out)
    assert payload["total"] == 1
    assert payload["items"][0]["title"] == "Saatleri Ayarlama Enstitüsü"

    output = tmp_path / "catalog.jsonl"
    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "export",
                str(output),
            ]
        )
        == 0
    )
    result = json.loads(capsys.readouterr().out)
    assert result["records"] == 1
    assert output.exists()


def test_import_metadata_and_review_approval(tmp_path: Path, capsys) -> None:
    source = tmp_path / "metadata.json"
    source.write_text(
        json.dumps(
            {
                "books": [
                    {
                        "title": "Tutunamayanlar",
                        "publisher": "İletişim",
                        "contributors": [{"name": "Oğuz Atay", "role": "author"}],
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
    database_path = tmp_path / "catalog.sqlite3"
    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "import-metadata",
                str(source),
            ]
        )
        == 0
    )
    capsys.readouterr()
    book = Catalog(database_path).list_books()[0]

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "review",
                "--id",
                str(book.edition_id),
                "--set",
                "publisher=Yeni Yayınevi",
                "--approve",
            ]
        )
        == 0
    )
    payload = json.loads(capsys.readouterr().out)
    assert payload["publisher"] == "Yeni Yayınevi"
    assert payload["review_status"] == "completed"
    locked_paths = {
        row["field_path"]
        for row in Database(database_path).fetchall(
            """
            SELECT field_path FROM resolved_field
            WHERE edition_id = ? AND user_locked = 1
            """,
            (book.edition_id,),
        )
    }
    assert locked_paths == {"edition.publisher", "edition.review_status"}


def test_run_uses_application_scheduler_after_guard(tmp_path: Path, monkeypatch, capsys) -> None:
    calls: dict[str, object] = {}

    class Scheduler:
        def run_job(self, job_id: str, *, worker_id: str) -> object:
            calls["job_id"] = job_id
            calls["worker_id"] = worker_id
            calls["guard"] = network_guard_installed()
            return SimpleNamespace(job={"id": job_id}, claims=3, cache_hits=7)

    class Context:
        def processing_scheduler(self) -> Scheduler:
            return Scheduler()

        def close(self) -> None:
            calls["closed"] = True

    fake = SimpleNamespace(open_application=lambda _paths, **_kwargs: Context())
    monkeypatch.setitem(sys.modules, "kitapkatalog.application", fake)

    code = main(
        [
            "--database",
            str(tmp_path / "catalog.sqlite3"),
            "--json",
            "run",
            "job-1",
            "--worker-id",
            "test-worker",
        ]
    )

    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["claims"] == 3
    assert calls == {
        "job_id": "job-1",
        "worker_id": "test-worker",
        "guard": True,
        "closed": True,
    }


def test_import_capacity_failure_does_not_enqueue(tmp_path: Path, monkeypatch, capsys) -> None:
    photos = tmp_path / "photos"
    photos.mkdir()
    (photos / "a_front.jpg").write_bytes(b"front")
    (photos / "a_back.jpg").write_bytes(b"back")
    database_path = tmp_path / "catalog.sqlite3"
    insufficient = CapacityEstimate(
        image_count=2,
        source_bytes=9,
        managed_copy_bytes=9,
        derivative_bytes=27,
        ocr_evidence_bytes=100,
        database_bytes=100,
        model_bytes=100,
        reserve_bytes=100,
        required_additional_bytes=436,
        free_bytes=10,
    )
    monkeypatch.setattr(
        "kitapkatalog.cli.estimate_import_capacity",
        lambda *_args, **_kwargs: insufficient,
    )

    code = main(
        [
            "--database",
            str(database_path),
            "import",
            str(photos),
            "--no-sequence",
        ]
    )

    assert code == 2
    assert "Yetersiz disk alanı" in capsys.readouterr().err
    assert Database(database_path).list_import_jobs() == []


def test_pair_review_list_and_reject_updates_job_counts(tmp_path: Path, capsys) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    front = tmp_path / "IMG_0001.JPG"
    back = tmp_path / "IMG_0002.JPG"
    front.write_bytes(b"front")
    back.write_bytes(b"back")
    job = database.create_import_job(
        "Belirsiz çift",
        [
            ImagePair(
                front,
                back,
                confidence=0.62,
                basis="exif_sequence",
                needs_review=True,
            )
        ],
    )
    item = database.list_pending_pair_reviews(job_id=job.id)[0]

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "pair-reviews",
                "--job-id",
                job.id,
            ]
        )
        == 0
    )
    pending = json.loads(capsys.readouterr().out)
    assert pending[0]["id"] == item.id
    assert pending[0]["needs_pair_review"]

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "pair-review",
                str(item.id),
                "--reject",
            ]
        )
        == 0
    )
    rejected = json.loads(capsys.readouterr().out)
    assert rejected["stage"] == "failed"
    assert not rejected["needs_pair_review"]
    updated = database.get_import_job(job.id)
    assert updated is not None
    assert updated.failed_items == 1
    assert updated.status == ImportJobStatus.COMPLETED_WITH_ERRORS
    assert database.list_pending_pair_reviews(job_id=job.id) == []


def test_retry_command_keeps_completed_checkpoint_and_resets_failed_motor(
    tmp_path: Path,
    capsys,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    job = database.create_import_job(
        "Hatalı motor",
        [
            ImagePair(
                tmp_path / "book_front.jpg",
                tmp_path / "book_back.jpg",
                pair_key="book",
            )
        ],
    )
    item = database.claim_next_item("worker", job_id=job.id)
    assert item is not None
    database.advance_item(item.id, "worker", JobItemStage.PREPROCESSED)
    database.record_engine_success(
        item.id,
        CoverRole.FRONT,
        OcrEngine.RAPIDOCR,
        cache_key="keep-me",
        text="kalıcı",
        worker_id="worker",
    )
    for attempt in range(3):
        database.record_engine_failure(
            item.id,
            CoverRole.FRONT,
            OcrEngine.TESSERACT,
            f"hata {attempt}",
            worker_id="worker",
        )

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "retry",
                str(item.id),
            ]
        )
        == 0
    )
    payload = json.loads(capsys.readouterr().out)
    assert payload["stage"] == "paired"
    rows = {
        row["engine_name"]: row
        for row in database.fetchall(
            """
            SELECT engine_name, status, attempt_count, cache_key, text, error
            FROM job_item_engine WHERE item_id = ?
            """,
            (item.id,),
        )
    }
    assert dict(rows[OcrEngine.RAPIDOCR.value]) == {
        "engine_name": OcrEngine.RAPIDOCR.value,
        "status": "completed",
        "attempt_count": 1,
        "cache_key": "keep-me",
        "text": "kalıcı",
        "error": None,
    }
    assert dict(rows[OcrEngine.TESSERACT.value]) == {
        "engine_name": OcrEngine.TESSERACT.value,
        "status": "pending",
        "attempt_count": 0,
        "cache_key": None,
        "text": None,
        "error": None,
    }


def test_fit_calibration_writes_profile_without_opening_catalogue(
    tmp_path: Path,
    capsys,
) -> None:
    source = tmp_path / "samples.jsonl"
    destination = tmp_path / "models" / "calibration" / "ensemble.json"
    source.write_text(
        "\n".join(
            json.dumps(
                {
                    "raw_confidence": 0.90 + index / 1000,
                    "correct": index % 5 != 0,
                }
            )
            for index in range(20)
        ),
        encoding="utf-8",
    )

    code = main(
        [
            "--database",
            str(tmp_path / "must-not-exist.sqlite3"),
            "--json",
            "fit-calibration",
            str(source),
            str(destination),
            "--version",
            "labelled-v1",
            "--minimum-samples",
            "20",
        ]
    )

    assert code == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["trusted"] is True
    assert payload["samples"] == 20
    assert destination.is_file()
    assert not (tmp_path / "must-not-exist.sqlite3").exists()


def test_archive_create_inspect_and_extract_commands(tmp_path: Path, capsys) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    Catalog(database_path).save_book(BookInput(title="Arşiv Kitabı"))
    archive_path = tmp_path / "yedek.kitaparsiv"

    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "archive",
                "create",
                str(archive_path),
            ]
        )
        == 0
    )
    created = json.loads(capsys.readouterr().out)
    assert Path(created["path"]) == archive_path
    assert archive_path.is_file()

    untouched_database = tmp_path / "must-not-be-created.sqlite3"
    assert (
        main(
            [
                "--database",
                str(untouched_database),
                "--json",
                "archive",
                "inspect",
                str(archive_path),
            ]
        )
        == 0
    )
    inspected = json.loads(capsys.readouterr().out)
    assert inspected["database_sha256"] == created["database_sha256"]
    assert not untouched_database.exists()

    destination = tmp_path / "restored"
    assert (
        main(
            [
                "--database",
                str(database_path),
                "--json",
                "archive",
                "extract",
                str(archive_path),
                str(destination),
            ]
        )
        == 0
    )
    restored = Path(json.loads(capsys.readouterr().out))
    assert restored.is_file()
    assert Catalog(restored).search("Arşiv").total == 1


def test_archive_create_includes_cover_referenced_only_by_edition(tmp_path: Path, capsys) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    record = Catalog(database).save_book(BookInput(title="Edition Kapak"))
    asset_root = tmp_path / "ozel-kapaklar"
    cover = asset_root / "roman" / "on.jpg"
    cover.parent.mkdir(parents=True)
    cover.write_bytes(b"edition-only")
    with database.transaction() as connection:
        connection.execute(
            "UPDATE edition SET front_path = ? WHERE id = ?",
            (str(cover), record.edition_id),
        )
    database.close()
    archive_path = tmp_path / "edition-cover.kitaparsiv"

    code = main(
        [
            "--database",
            str(database_path),
            "--json",
            "archive",
            "create",
            str(archive_path),
            "--include-covers",
            "--asset-root",
            str(asset_root),
        ]
    )

    assert code == 0
    assert json.loads(capsys.readouterr().out)["cover_count"] == 1


def _record_engine_durations(
    database: Database,
    durations: dict[str, list[int]],
    *,
    tmp_path: Path,
) -> None:
    """Seed ocr_engine_run rows; only the recorded durations matter here."""

    job = database.create_import_job(
        "Ölçüm",
        [ImagePair(tmp_path / "front.jpg", tmp_path / "back.jpg", pair_key="book")],
    )
    item = database.claim_next_item("worker", job_id=job.id)
    assert item is not None
    surfaces = max(len(values) for values in durations.values())
    roles = [role.value for role in CoverRole][:surfaces]
    now = "2026-01-01T00:00:00+00:00"
    with database.transaction() as connection:
        for index, role in enumerate(roles, 1):
            connection.execute(
                """
                INSERT INTO image_asset (
                    id, item_id, cover_role, source_path, source_sha256,
                    crop_sha256, width, height, preprocessing_version,
                    homography_json, created_at, updated_at
                ) VALUES (?, ?, ?, '/x', 'a', 'c', 1, 1, 'v1', '[]', ?, ?)
                """,
                (index, item.id, role, now, now),
            )
        for engine_name, values in durations.items():
            for index, duration in enumerate(values, 1):
                connection.execute(
                    """
                    INSERT INTO ocr_engine_run (
                        image_asset_id, engine_name, model_digest, config_hash,
                        preprocessing_version, cache_key, status, attempt_count,
                        duration_ms, created_at, updated_at
                    ) VALUES (?, ?, 'd', 'c', 'v1', ?, 'completed', 1, ?, ?, ?)
                    """,
                    (index, engine_name, f"{engine_name}:{index}", duration, now, now),
                )


def test_perf_report_summarises_engine_durations_and_the_throughput_gate(
    tmp_path: Path,
    capsys,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    _record_engine_durations(
        database,
        {
            "surya": [20000, 20000, 20000, 28000],
            "paddleocr_vl": [7000, 7000, 7000, 9000],
            "tesseract": [800, 800, 800, 1300],
        },
        tmp_path=tmp_path,
    )

    assert main(["--database", str(database_path), "--json", "perf-report"]) == 0
    payload = json.loads(capsys.readouterr().out)

    assert payload["surfaces_measured"] == 4
    assert payload["engines"]["surya"]["runs"] == 4
    assert payload["engines"]["surya"]["median_ms"] == 20000
    assert payload["engines"]["surya"]["max_ms"] == 28000
    # Spread only: every one of these runs already paid a model load, so the
    # gap measures run-to-run variance, not the fixed cost.
    assert payload["engines"]["surya"]["spread_ms"] == 8000
    assert payload["bottleneck"] == "surya"
    # Heavy engines hold a process-wide lock, so they set the ceiling no matter
    # how many book workers are configured.
    assert payload["books_per_hour"] == payload["books_per_hour_heavy_ceiling"]
    assert payload["books_per_hour"] < payload["books_per_hour_worker_bound"]
    assert payload["gate_books_per_hour"] == 60
    assert payload["meets_gate"] is False


def test_perf_report_reports_no_heavy_ceiling_when_none_was_measured(
    tmp_path: Path,
    capsys,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    _record_engine_durations(database, {"tesseract": [800, 900]}, tmp_path=tmp_path)

    assert main(["--database", str(database_path), "--json", "perf-report"]) == 0
    payload = json.loads(capsys.readouterr().out)

    # No heavy-engine measurement means no heavy-engine constraint; a ceiling of
    # zero would read as "this catalogue cannot process anything".
    assert payload["books_per_hour_heavy_ceiling"] is None
    assert payload["books_per_hour"] == payload["books_per_hour_worker_bound"]
    assert payload["books_per_hour"] > 0


def test_perf_report_ignores_failed_runs_but_counts_them(
    tmp_path: Path,
    capsys,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    _record_engine_durations(database, {"tesseract": [1000, 1000]}, tmp_path=tmp_path)
    with database.transaction() as connection:
        connection.execute(
            """
            UPDATE ocr_engine_run SET status = 'failed', duration_ms = 999999
            WHERE cache_key = 'tesseract:1'
            """
        )

    assert main(["--database", str(database_path), "--json", "perf-report"]) == 0
    payload = json.loads(capsys.readouterr().out)

    summary = payload["engines"]["tesseract"]
    assert summary["runs"] == 1
    assert summary["failures"] == 1
    # A failed run's duration would otherwise poison the throughput estimate.
    assert summary["mean_ms"] == 1000
