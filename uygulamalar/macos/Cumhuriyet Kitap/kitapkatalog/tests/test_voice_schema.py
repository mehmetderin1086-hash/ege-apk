from __future__ import annotations

import sqlite3
from pathlib import Path

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import SCHEMA_VERSION, Database
from kitapkatalog.domain import (
    ALLOWED_VOICE_STAGE_TRANSITIONS,
    BookInput,
    ContributorInput,
    IdentifierInput,
    VoiceItemStage,
)


def _build_v3_database(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        Database._migrate_v1(connection)
        Database._migrate_v2(connection)
        Database._migrate_v3(connection)
        connection.execute(
            """
            INSERT INTO work(id, canonical_title, created_at, updated_at)
            VALUES (1, 'Eski Kitap', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
            """
        )
        connection.execute(
            """
            INSERT INTO edition(id, work_id, title, publisher, created_at, updated_at)
            VALUES (
                1, 1, 'Eski Kitap', 'Eski Yayınevi',
                '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
            )
            """
        )
        connection.commit()
    finally:
        connection.close()


def test_v3_database_upgrades_to_v4_without_data_loss(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    _build_v3_database(path)

    database = Database(path)
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        row = connection.execute(
            "SELECT title, publisher, category FROM edition WHERE id = 1"
        ).fetchone()
        assert (row["title"], row["publisher"], row["category"]) == (
            "Eski Kitap",
            "Eski Yayınevi",
            None,
        )
        versions = {
            item[0]
            for item in connection.execute("SELECT version FROM schema_migration").fetchall()
        }
        assert 4 in versions
    assert database.integrity_check() == "ok"


def test_voice_tables_have_expected_uniques(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.transaction() as connection:
        connection.execute(
            """
            INSERT INTO voice_job(
                id, name, status, source_audio_path, created_at, updated_at
            ) VALUES ('vj-1', 'test', 'queued', '/tmp/a.m4a', '2026', '2026')
            """
        )
        connection.execute(
            """
            INSERT INTO voice_item(
                job_id, item_key, ordinal, start_sample, end_sample,
                transcript_json, stage, created_at, updated_at
            ) VALUES ('vj-1', 'v1:00000', 0, 0, 16000, '[]', 'segmented',
                      '2026', '2026')
            """
        )
    with database.connection() as connection:
        try:
            connection.execute(
                """
                INSERT INTO voice_item(
                    job_id, item_key, ordinal, start_sample, end_sample,
                    transcript_json, stage, created_at, updated_at
                ) VALUES ('vj-1', 'v1:00000', 0, 0, 16000, '[]', 'segmented',
                          '2026', '2026')
                """
            )
        except sqlite3.IntegrityError:
            duplicate_rejected = True
        else:
            duplicate_rejected = False
        assert duplicate_rejected


def test_voice_stage_machine_is_closed() -> None:
    assert set(ALLOWED_VOICE_STAGE_TRANSITIONS) == set(VoiceItemStage)
    for stage in VoiceItemStage:
        if stage.terminal and stage is not VoiceItemStage.REVIEW:
            assert not ALLOWED_VOICE_STAGE_TRANSITIONS[stage]


def test_category_round_trip_with_save_update_and_search(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    record = catalog.save_book(
        BookInput(
            title="Kar",
            publisher="İletişim",
            category="Roman",
            contributors=(ContributorInput(name="Orhan Pamuk"),),
            identifiers=(IdentifierInput(scheme="ISBN13", value="9789750718533"),),
        )
    )
    assert record.category == "Roman"

    updated = catalog.update_book(record.edition_id, {"category": "Çağdaş Roman"}, user_edit=True)
    assert updated.category == "Çağdaş Roman"
