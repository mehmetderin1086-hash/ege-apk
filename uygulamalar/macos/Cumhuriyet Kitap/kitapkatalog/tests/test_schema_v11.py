"""Şema v11: rezervasyon (hold), bildirim merkezi, üye yasağı, dış öneri tablosu."""

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


def _v10_database(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        for version in range(1, 11):
            getattr(Database, f"_migrate_v{version}")(connection)
        connection.commit()
    finally:
        connection.close()


def test_new_database_has_v11_tables(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    assert SCHEMA_VERSION >= 11
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        hold_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(hold)").fetchall()
        }
        assert {
            "id", "edition_id", "member_id", "status", "created_at", "ready_at",
            "ready_copy_id", "expires_at", "request_id",
        } <= hold_columns
        notification_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(notification)").fetchall()
        }
        assert {
            "id", "kind", "member_id", "ref_kind", "ref_id", "title", "body",
            "created_at", "read_at", "dismissed_at", "dedupe_key",
        } <= notification_columns
        block_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(member_block)").fetchall()
        }
        assert {
            "id", "member_id", "kind", "start_date", "end_date", "reason",
            "created_at", "lifted_at", "lift_reason",
        } <= block_columns
        suggestion_columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(external_suggestion)").fetchall()
        }
        assert {
            "id", "isbn13", "source", "payload_json", "fetched_at", "edition_id", "status",
        } <= suggestion_columns
        copy_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(copy)").fetchall()
        }
        assert {"acquisition_method", "acquisition_date", "acquisition_price"} <= copy_columns
        versions = {
            row[0] for row in connection.execute("SELECT version FROM schema_migration").fetchall()
        }
        assert 11 in versions
    assert database.integrity_check() == "ok"


def test_hold_status_check_constraint_rejects_unknown_value(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.transaction() as connection:
        connection.execute(
            "INSERT INTO member(member_type, first_name, last_name, created_at, updated_at) "
            "VALUES ('student', 'A', 'B', '2026-01-01', '2026-01-01')"
        )
        connection.execute(
            "INSERT INTO work(canonical_title, created_at, updated_at) "
            "VALUES ('bilinmiyor', '2026-01-01', '2026-01-01')"
        )
        work_id = connection.execute("SELECT id FROM work").fetchone()[0]
        connection.execute(
            "INSERT INTO edition(work_id, title, created_at, updated_at) "
            "VALUES (?, 'Kitap', '2026-01-01', '2026-01-01')",
            (work_id,),
        )
    with pytest.raises(sqlite3.IntegrityError), database.transaction() as connection:
        connection.execute(
            "INSERT INTO hold(edition_id, member_id, status, created_at) "
            "VALUES (1, 1, 'bilinmeyen', '2026-01-01')"
        )


def _remove_v11(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        DROP TABLE hold;
        DROP TABLE notification;
        DROP TABLE member_block;
        DROP TABLE external_suggestion;
        DELETE FROM schema_migration WHERE version = 11;
        PRAGMA user_version = 10;
        """
    )


def test_v10_database_reenters_v11_migration_safely(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    with database.connection() as connection:
        _remove_v11(connection)

    reopened = Database(path)
    with reopened.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        for table in ("hold", "notification", "member_block", "external_suggestion"):
            assert connection.execute(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                (table,),
            ).fetchone()[0] == 1
    assert reopened.integrity_check() == "ok"


def test_upgrade_chain_reaches_v11_from_v10(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _v10_database(paths.database)

    result = open_database_safely(paths)
    try:
        assert result.from_version == 10
        assert result.to_version == SCHEMA_VERSION
        assert result.database.fetchone("PRAGMA user_version")[0] == SCHEMA_VERSION
    finally:
        result.database.close()


def test_downgraded_database_rejects_opening(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    Database(path)
    with sqlite3.connect(path) as connection:
        connection.execute(f"PRAGMA user_version = {SCHEMA_VERSION + 1}")
    with pytest.raises(DatabaseError, match="en yeni sürüm"):
        Database(path)
