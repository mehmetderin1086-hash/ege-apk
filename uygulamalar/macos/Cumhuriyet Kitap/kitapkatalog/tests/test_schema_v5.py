from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import SCHEMA_VERSION, Database
from kitapkatalog.domain import BookInput

V5_TABLES = {
    "app_setting",
    "inventory_sequence",
    "member",
    "loan",
    "discard_record",
    "stocktake_session",
    "stocktake_scan",
}


def _tables(connection: sqlite3.Connection) -> set[str]:
    return {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
        )
    }


def _insert_member(connection: sqlite3.Connection, number: str = "101") -> int:
    cursor = connection.execute(
        """
        INSERT INTO member(member_type, school_number, first_name, last_name,
                           class_name, created_at, updated_at)
        VALUES ('student', ?, 'Ada', 'Yılmaz', '9-A', '2026-01-01', '2026-01-01')
        """,
        (number,),
    )
    return int(cursor.lastrowid)


def _insert_loan(connection: sqlite3.Connection, copy_id: int, member_id: int) -> int:
    cursor = connection.execute(
        """
        INSERT INTO loan(copy_id, member_id, edition_id, title_snapshot,
                         loaned_at, due_at, member_name_snapshot,
                         member_number_snapshot, member_class_snapshot,
                         member_type_snapshot, academic_period_snapshot,
                         snapshot_source, created_at, updated_at)
        SELECT ?, ?, edition_id, 'Test Kitabı', '2026-01-01', '2026-01-16',
               'Ada Yılmaz', '101', '9-A', 'student', '2025-2026',
               'test', '2026-01-01', '2026-01-01'
        FROM copy WHERE id = ?
        """,
        (copy_id, member_id, copy_id),
    )
    return int(cursor.lastrowid)


def _make_copy(database: Database) -> int:
    catalog = Catalog(database)
    record = catalog.save_book(BookInput(title="Sayım Deneme Kitabı"))
    return record.copies[0].id


def test_new_database_is_v5_with_new_tables(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert _tables(connection) >= V5_TABLES
    assert database.integrity_check() == "ok"


def test_copy_status_defaults_to_active(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    copy_id = _make_copy(database)
    row = database.fetchone("SELECT status FROM copy WHERE id = ?", (copy_id,))
    assert row is not None and row[0] == "active"
    with database.transaction() as connection, pytest.raises(sqlite3.IntegrityError):
        connection.execute("UPDATE copy SET status = 'bozuk' WHERE id = ?", (copy_id,))


def test_v4_database_upgrades_to_v5(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    copy_id = _make_copy(database)

    # v4 durumunu taklit et: v5 nesnelerini kaldır, sürümü geri çek.
    with database.connection() as connection:
        connection.executescript(
            """
            DROP TRIGGER IF EXISTS copy_no_delete_when_loaned;
            DROP TRIGGER IF EXISTS circulation_event_no_update;
            DROP TRIGGER IF EXISTS circulation_event_no_delete;
            DROP TABLE IF EXISTS circulation_event;
            DROP TABLE IF EXISTS stocktake_scan;
            DROP TABLE IF EXISTS stocktake_session;
            DROP TABLE IF EXISTS discard_record;
            DROP TABLE IF EXISTS loan;
            DROP TABLE IF EXISTS member;
            DROP TABLE IF EXISTS inventory_sequence;
            DROP TABLE IF EXISTS app_setting;
            DROP INDEX IF EXISTS idx_copy_edition_status_location;
            ALTER TABLE copy DROP COLUMN status;
            DELETE FROM schema_migration WHERE version >= 5;
            PRAGMA user_version = 4;
            """
        )

    upgraded = Database(path)
    with upgraded.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert _tables(connection) >= V5_TABLES
        status = connection.execute("SELECT status FROM copy WHERE id = ?", (copy_id,)).fetchone()
        assert status is not None and status[0] == "active"
    assert upgraded.integrity_check() == "ok"


def test_active_loan_blocks_copy_delete(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    copy_id = _make_copy(database)
    with database.transaction() as connection:
        member_id = _insert_member(connection)
        _insert_loan(connection, copy_id, member_id)
    with (
        database.transaction() as connection,
        pytest.raises(sqlite3.IntegrityError, match="ödünçte"),
    ):
        connection.execute("DELETE FROM copy WHERE id = ?", (copy_id,))
    # İade sonrası silme serbest.
    with database.transaction() as connection:
        connection.execute("UPDATE loan SET returned_at = '2026-01-10' WHERE copy_id = ?", (copy_id,))
        connection.execute("DELETE FROM copy WHERE id = ?", (copy_id,))
    row = database.fetchone("SELECT copy_id FROM loan WHERE member_id IS NOT NULL")
    assert row is not None and row[0] is None  # FK SET NULL: geçmiş kaydı yaşıyor


def test_partial_unique_index_forbids_double_active_loan(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    copy_id = _make_copy(database)
    with database.transaction() as connection:
        member_id = _insert_member(connection)
        other_member = _insert_member(connection, number="102")
        _insert_loan(connection, copy_id, member_id)
    with database.transaction() as connection, pytest.raises(sqlite3.IntegrityError):
        _insert_loan(connection, copy_id, other_member)
    # İade edilince aynı nüsha yeniden ödünç verilebilir.
    with database.transaction() as connection:
        connection.execute("UPDATE loan SET returned_at = '2026-01-05' WHERE copy_id = ?", (copy_id,))
        _insert_loan(connection, copy_id, other_member)


def test_member_school_number_unique_only_when_present(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.transaction() as connection:
        _insert_member(connection, number="500")
        with pytest.raises(sqlite3.IntegrityError):
            _insert_member(connection, number="500")
    with database.transaction() as connection:
        # Personelde numara olmayabilir; birden çok NULL serbest.
        for name in ("Ali", "Veli"):
            connection.execute(
                """
                INSERT INTO member(member_type, school_number, first_name, last_name,
                                   created_at, updated_at)
                VALUES ('staff', NULL, ?, 'Öğretmen', '2026-01-01', '2026-01-01')
                """,
                (name,),
            )
