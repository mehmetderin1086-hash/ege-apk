"""Şema v12: okuma listeleri ve okuma yarışması pedagojik katmanı."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from kitapkatalog.config import AppPaths
from kitapkatalog.database import SCHEMA_VERSION, Database, _unicode_nocase
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


def _v11_database(path: Path) -> None:
    connection = sqlite3.connect(path)
    try:
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        for version in range(1, 12):
            getattr(Database, f"_migrate_v{version}")(connection)
        connection.commit()
    finally:
        connection.close()


def test_new_database_has_v12_tables(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    assert SCHEMA_VERSION >= 12
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        list_columns = {
            row[1] for row in connection.execute("PRAGMA table_info(reading_list)").fetchall()
        }
        assert {
            "id", "name", "description", "is_opac_visible", "position",
            "created_at", "updated_at",
        } <= list_columns
        item_columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(reading_list_item)").fetchall()
        }
        assert {"id", "list_id", "edition_id", "position"} <= item_columns
        assignment_columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(reading_assignment)").fetchall()
        }
        assert {"id", "list_id", "member_id", "assigned_at", "note"} <= assignment_columns
        challenge_columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(reading_challenge)").fetchall()
        }
        assert {
            "id", "name", "start_date", "end_date", "target_books", "scope",
            "class_name", "status", "created_at",
        } <= challenge_columns
        certificate_columns = {
            row[1]
            for row in connection.execute("PRAGMA table_info(challenge_certificate)").fetchall()
        }
        assert {"id", "challenge_id", "member_id", "rank", "printed_at"} <= certificate_columns
        versions = {
            row[0] for row in connection.execute("SELECT version FROM schema_migration").fetchall()
        }
        assert 12 in versions
    assert database.integrity_check() == "ok"


def test_reading_challenge_check_constraints(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with pytest.raises(sqlite3.IntegrityError), database.transaction() as connection:
        connection.execute(
            "INSERT INTO reading_challenge(name, start_date, end_date, target_books, "
            "created_at) VALUES ('Yarışma', '2026-01-01', '2026-06-01', 0, '2026-01-01')"
        )
    with pytest.raises(sqlite3.IntegrityError), database.transaction() as connection:
        connection.execute(
            "INSERT INTO reading_challenge(name, start_date, end_date, target_books, "
            "scope, created_at) VALUES ('Yarışma', '2026-01-01', '2026-06-01', 5, "
            "'bilinmeyen', '2026-01-01')"
        )


def _remove_v12(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        DROP TABLE reading_list_item;
        DROP TABLE reading_assignment;
        DROP TABLE challenge_certificate;
        DROP TABLE reading_challenge;
        DROP TABLE reading_list;
        DELETE FROM schema_migration WHERE version = 12;
        PRAGMA user_version = 11;
        """
    )


def test_v11_database_reenters_v12_migration_safely(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    with database.connection() as connection:
        _remove_v12(connection)

    reopened = Database(path)
    with reopened.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        for table in (
            "reading_list", "reading_list_item", "reading_assignment",
            "reading_challenge", "challenge_certificate",
        ):
            assert connection.execute(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                (table,),
            ).fetchone()[0] == 1
    assert reopened.integrity_check() == "ok"


def test_upgrade_chain_reaches_v12_from_v11(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _v11_database(paths.database)

    result = open_database_safely(paths)
    try:
        assert result.from_version == 11
        assert result.to_version == SCHEMA_VERSION
        assert result.database.fetchone("PRAGMA user_version")[0] == SCHEMA_VERSION
    finally:
        result.database.close()
