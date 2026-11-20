"""Şema v6: shelf tablosu, hücre/kısıt denetimleri, yeni indeksler."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from kitapkatalog.database import SCHEMA_VERSION, Database

V6_OBJECTS = {"shelf"}


def _names(connection: sqlite3.Connection, kind: str) -> set[str]:
    return {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = ?", (kind,)
        )
    }


def _insert_shelf(
    connection: sqlite3.Connection,
    name: str,
    *,
    row: int | None = None,
    col: int | None = None,
    capacity: int | None = None,
) -> int:
    cursor = connection.execute(
        """
        INSERT INTO shelf(name, grid_row, grid_col, capacity, created_at, updated_at)
        VALUES (?, ?, ?, ?, '2026-01-01', '2026-01-01')
        """,
        (name, row, col, capacity),
    )
    return int(cursor.lastrowid)


def test_new_database_is_v6_with_shelf(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert _names(connection, "table") >= V6_OBJECTS
        indexes = _names(connection, "index")
        assert {"idx_shelf_cell", "idx_copy_location", "idx_loan_edition"} <= indexes
    assert database.integrity_check() == "ok"


def test_v5_database_upgrades_to_v6(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    database = Database(path)
    # v5 durumunu taklit et: v6 nesnelerini kaldır, sürümü geri çek.
    with database.connection() as connection:
        connection.executescript(
            """
            DROP TABLE IF EXISTS shelf;
            DROP INDEX IF EXISTS idx_copy_location;
            DROP INDEX IF EXISTS idx_loan_edition;
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
            DELETE FROM schema_migration WHERE version >= 6;
            PRAGMA user_version = 5;
            """
        )

    upgraded = Database(path)
    with upgraded.connection() as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        assert _names(connection, "table") >= V6_OBJECTS
    assert upgraded.integrity_check() == "ok"


def test_shelf_cell_unique_when_placed(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.transaction() as connection:
        _insert_shelf(connection, "Dolap A", row=0, col=0)
        with pytest.raises(sqlite3.IntegrityError):
            _insert_shelf(connection, "Dolap B", row=0, col=0)
    with database.transaction() as connection:
        # Yerleşmemiş (NULL hücreli) dolaplar sınırsız olabilir.
        _insert_shelf(connection, "Dolap C")
        _insert_shelf(connection, "Dolap D")


def test_shelf_check_constraints(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    cases = [
        {"name": ""},  # boş ad
        {"name": " Dolap "},  # trim edilmemiş ad
        {"name": "Tek Satır", "row": 1},  # satır dolu, sütun NULL
        {"name": "Eksi", "row": -1, "col": 0},  # negatif koordinat
        {"name": "Sıfır Kapasite", "row": 0, "col": 1, "capacity": 0},
    ]
    for case in cases:
        with database.transaction() as connection, pytest.raises(sqlite3.IntegrityError):
            _insert_shelf(
                connection,
                case["name"],
                row=case.get("row"),
                col=case.get("col"),
                capacity=case.get("capacity"),
            )


def test_shelf_name_unique(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.transaction() as connection:
        _insert_shelf(connection, "Dolap A")
        with pytest.raises(sqlite3.IntegrityError):
            _insert_shelf(connection, "Dolap A")
