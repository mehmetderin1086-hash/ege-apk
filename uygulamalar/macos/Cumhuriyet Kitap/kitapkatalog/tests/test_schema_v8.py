"""Şema v8: dolaşım anlık görüntüleri, olay günlüğü ve dosya güvenliği."""

from __future__ import annotations

import os
import sqlite3
import stat
from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import SCHEMA_VERSION, Database
from kitapkatalog.domain import BookInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.reports import Reports
from kitapkatalog.settings import AppSettings


def _circulation(tmp_path: Path):
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    catalog = Catalog(database)
    members = Members(database)
    loans = Loans(database, AppSettings(database))
    member = members.add(
        member_type="student",
        school_number="101",
        first_name="Ada",
        last_name="Yılmaz",
        class_name="9-A",
    )
    book = catalog.save_book(BookInput(title="Tarih Kitabı"))
    loan = loans.checkout(
        member.id,
        edition_id=book.edition_id,
        now=datetime(2025, 10, 2, 9, tzinfo=UTC),
        request_id="checkout-history-001",
    )
    return path, database, members, loan


def _remove_v8(connection: sqlite3.Connection) -> None:
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
        ALTER TABLE loan DROP COLUMN snapshot_source;
        ALTER TABLE loan DROP COLUMN academic_period_snapshot;
        ALTER TABLE loan DROP COLUMN member_type_snapshot;
        ALTER TABLE loan DROP COLUMN member_class_snapshot;
        ALTER TABLE loan DROP COLUMN member_number_snapshot;
        ALTER TABLE loan DROP COLUMN member_name_snapshot;
        DELETE FROM schema_migration WHERE version = 8;
        PRAGMA user_version = 7;
        """
    )


def test_new_database_has_v8_circulation_objects(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert SCHEMA_VERSION >= 8
        columns = {
            row[1] for row in connection.execute("PRAGMA table_info(loan)").fetchall()
        }
        assert {
            "member_name_snapshot",
            "member_number_snapshot",
            "member_class_snapshot",
            "member_type_snapshot",
            "academic_period_snapshot",
            "snapshot_source",
        } <= columns
        objects = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'trigger', 'index')"
            )
        }
        assert {
            "circulation_event",
            "loan_snapshot_required",
            "loan_snapshot_immutable",
            "loan_one_active_edition_insert",
            "loan_one_active_edition_update",
            "circulation_event_no_update",
            "circulation_event_no_delete",
            "idx_loan_active_member_edition",
        } <= objects


def test_v7_upgrade_backfills_estimated_snapshot(tmp_path: Path) -> None:
    path, database, members, loan = _circulation(tmp_path)
    members.update(loan.member_id, first_name="Ada Nur", class_name="10-B")
    with database.connection() as connection:
        _remove_v8(connection)

    upgraded = Database(path)
    row = upgraded.fetchone("SELECT * FROM loan WHERE id = ?", (loan.id,))
    assert row is not None
    assert row["member_name_snapshot"] == "Ada Nur Yılmaz"
    assert row["member_class_snapshot"] == "10-B"
    assert row["academic_period_snapshot"] == "2025-2026"
    assert row["snapshot_source"] == "migration-estimate"
    assert Reports(upgraded).snapshot_quality() == {
        "total": 1,
        "exact": 0,
        "estimated": 1,
    }
    assert upgraded.integrity_check() == "ok"


def test_v8_migration_can_safely_reenter_complete_schema(tmp_path: Path) -> None:
    path, database, _, loan = _circulation(tmp_path)
    with database.transaction(immediate=True) as connection:
        connection.execute("DELETE FROM schema_migration WHERE version = 8")
        connection.execute("PRAGMA user_version = 7")

    reopened = Database(path)
    assert reopened.fetchone("SELECT COUNT(*) FROM loan")[0] == 1
    assert reopened.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 1
    replayed = Loans(reopened, AppSettings(reopened)).checkout(
        loan.member_id,
        edition_id=loan.edition_id,
        request_id="checkout-history-001",
    )
    assert replayed.id == loan.id


def test_snapshots_and_events_are_append_only(tmp_path: Path) -> None:
    _, database, _, loan = _circulation(tmp_path)
    with database.transaction(immediate=True) as connection:
        with pytest.raises(sqlite3.IntegrityError, match="değiştirilemez"):
            connection.execute(
                "UPDATE loan SET member_class_snapshot = '12-Z' WHERE id = ?",
                (loan.id,),
            )
        with pytest.raises(sqlite3.IntegrityError, match="değiştirilemez"):
            connection.execute("UPDATE circulation_event SET event_type = 'return'")
        with pytest.raises(sqlite3.IntegrityError, match="silinemez"):
            connection.execute("DELETE FROM circulation_event")


def test_database_and_wal_sidecars_are_mode_0600_under_umask_022(
    tmp_path: Path,
) -> None:
    path = tmp_path / "catalog.sqlite3"
    previous = os.umask(0o022)
    try:
        database = Database(path)
        with database.connection() as connection:
            connection.execute(
                "INSERT OR REPLACE INTO app_setting(key, value, updated_at) "
                "VALUES ('permission-test', '1', '2026-01-01')"
            )
            files = (path, Path(f"{path}-wal"), Path(f"{path}-shm"))
            assert all(candidate.exists() for candidate in files)
            assert all(
                stat.S_IMODE(candidate.stat().st_mode) == 0o600
                for candidate in files
            )
    finally:
        os.umask(previous)
