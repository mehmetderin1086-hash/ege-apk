"""Şema v10: sesli düzeltme sözlüğü (voice_alias) ve iş başına ses dili."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from kitapkatalog.config import AppPaths
from kitapkatalog.database import SCHEMA_VERSION, Database, DatabaseError, _unicode_nocase
from kitapkatalog.upgrade import open_database_safely


def _paths(tmp_path: Path) -> AppPaths:
    paths = AppPaths(
        root=tmp_path,
        database=tmp_path / "catalog.sqlite3",
        assets=tmp_path / "assets",
        derivatives=tmp_path / "derivatives",
        ocr_raw=tmp_path / "ocr-raw",
        models=tmp_path / "models",
        exports=tmp_path / "exports",
        logs=tmp_path / "logs",
    )
    paths.ensure()
    return paths


def _v9_database(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        for version in range(1, 10):
            getattr(Database, f"_migrate_v{version}")(connection)
        connection.commit()
    finally:
        connection.close()


def test_new_database_has_v10_voice_alias_and_language_column(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    assert SCHEMA_VERSION >= 10
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        job_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(voice_job)").fetchall()
        }
        assert "language" in job_columns
        alias_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(voice_alias)").fetchall()
        }
        assert {"id", "heard", "canonical", "field_scope", "created_at"} <= alias_columns
        versions = {
            row[0] for row in connection.execute("SELECT version FROM schema_migration").fetchall()
        }
        assert 10 in versions
    assert database.integrity_check() == "ok"


def _remove_v10(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        DROP TABLE voice_alias;
        ALTER TABLE voice_job DROP COLUMN language;
        DELETE FROM schema_migration WHERE version = 10;
        PRAGMA user_version = 9;
        """
    )


def test_v9_database_reenters_v10_migration_safely(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    job = database.create_voice_job(name="test", source_audio_path="/tmp/a.m4a")
    with database.connection() as connection:
        _remove_v10(connection)

    reopened = Database(path)
    with reopened.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert connection.execute(
            "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'voice_alias'"
        ).fetchone()[0] == 1
    # v9'daki veri korunmuş olmalı.
    reloaded = reopened.get_voice_job(job.id)
    assert reloaded is not None
    assert reloaded.language is None
    assert reopened.integrity_check() == "ok"


def test_upgrade_chain_reaches_v10_from_v9(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _v9_database(paths.database)

    result = open_database_safely(paths)
    try:
        assert result.from_version == 9
        assert result.to_version == SCHEMA_VERSION
        assert result.database.fetchone("PRAGMA user_version")[0] == SCHEMA_VERSION
    finally:
        result.database.close()


def test_voice_job_language_round_trips(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    default_job = database.create_voice_job(name="varsayilan", source_audio_path="/tmp/a.m4a")
    assert default_job.language is None
    forced_job = database.create_voice_job(
        name="ingilizce", source_audio_path="/tmp/b.m4a", language="en"
    )
    assert forced_job.language == "en"
    assert database.get_voice_job(forced_job.id).language == "en"


class TestVoiceAliasCrud:
    def test_upsert_inserts_and_updates_canonical(self, tmp_path: Path) -> None:
        database = Database(tmp_path / "catalog.sqlite3")
        created = database.upsert_voice_alias("di greyt gatsbi", "The Great Gatsby", "title")
        assert created.heard == "di greyt gatsbi"
        assert created.canonical == "The Great Gatsby"
        assert created.field_scope == "title"

        updated = database.upsert_voice_alias("di greyt gatsbi", "The Great Gatsby (1925)", "title")
        assert updated.id == created.id
        assert updated.canonical == "The Great Gatsby (1925)"
        assert len(database.list_voice_aliases()) == 1

    def test_same_heard_different_scope_is_distinct(self, tmp_path: Path) -> None:
        database = Database(tmp_path / "catalog.sqlite3")
        database.upsert_voice_alias("kar", "Kar", "title")
        database.upsert_voice_alias("kar", "KAR Yayınları", "publisher")
        assert len(database.list_voice_aliases()) == 2

    def test_invalid_field_scope_is_rejected_by_check_constraint(self, tmp_path: Path) -> None:
        database = Database(tmp_path / "catalog.sqlite3")
        with pytest.raises(sqlite3.IntegrityError):
            database.upsert_voice_alias("x", "Y", "bilinmeyen")

    def test_delete_removes_and_missing_id_raises(self, tmp_path: Path) -> None:
        database = Database(tmp_path / "catalog.sqlite3")
        alias = database.upsert_voice_alias("orhan pamuk", "Orhan Pamuk", "author")
        database.delete_voice_alias(alias.id)
        assert database.list_voice_aliases() == []
        with pytest.raises(KeyError):
            database.delete_voice_alias(alias.id)

    def test_downgraded_database_rejects_opening(self, tmp_path: Path) -> None:
        path = tmp_path / "catalog.sqlite3"
        Database(path)
        with sqlite3.connect(path) as connection:
            connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION + 1}")
        with pytest.raises(DatabaseError, match="en yeni sürüm"):
            Database(path)
