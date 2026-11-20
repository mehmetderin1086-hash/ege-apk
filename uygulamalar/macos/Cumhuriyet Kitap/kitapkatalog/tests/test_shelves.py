"""Raf/dolap servisi: CRUD, ad senkronu, adopt, harita özeti."""

from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput, CopyInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings
from kitapkatalog.shelves import Shelves


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    return database, Catalog(database), Shelves(database)


def _book(catalog: Catalog, title: str, location: str | None) -> int:
    record = catalog.save_book(BookInput(title=title, copy=CopyInput(location=location)))
    return record.edition_id


class TestCrud:
    def test_create_and_get(self, env) -> None:
        *_, shelves = env
        record = shelves.create("Dolap A", grid_row=0, grid_col=1, capacity=40, color="#a3c2ff")
        assert record.name == "Dolap A"
        assert record.grid_row == 0 and record.grid_col == 1
        assert shelves.get(record.id) == record

    def test_name_trimmed_and_required(self, env) -> None:
        *_, shelves = env
        assert shelves.create("  Dolap B  ").name == "Dolap B"
        with pytest.raises(ValueError, match="boş"):
            shelves.create("   ")

    def test_cell_requires_both_coordinates(self, env) -> None:
        *_, shelves = env
        with pytest.raises(ValueError, match="birlikte"):
            shelves.create("Tek", grid_row=1)
        with pytest.raises(ValueError, match="negatif"):
            shelves.create("Eksi", grid_row=-1, grid_col=0)

    def test_duplicate_name_and_cell_conflict(self, env) -> None:
        *_, shelves = env
        shelves.create("Dolap A", grid_row=0, grid_col=0)
        with pytest.raises(StateConflictError):
            shelves.create("Dolap A")
        with pytest.raises(StateConflictError):
            shelves.create("Dolap B", grid_row=0, grid_col=0)

    def test_invalid_color_rejected(self, env) -> None:
        *_, shelves = env
        with pytest.raises(ValueError, match="renk"):
            shelves.create("Renkli", color="mavi")

    def test_delete_keeps_copy_locations(self, env) -> None:
        database, catalog, shelves = env
        record = shelves.create("Dolap A")
        _book(catalog, "Kitap", "Dolap A")
        shelves.delete(record.id)
        assert shelves.get(record.id) is None
        row = database.fetchone("SELECT location FROM copy WHERE location = 'Dolap A'")
        assert row is not None  # konum metni korunur

    def test_delete_missing_raises(self, env) -> None:
        *_, shelves = env
        with pytest.raises(KeyError):
            shelves.delete(999)


class TestRenameAndAdopt:
    def test_rename_moves_copy_locations(self, env) -> None:
        database, catalog, shelves = env
        record = shelves.create("Dolap A")
        _book(catalog, "Kitap 1", "Dolap A")
        _book(catalog, "Kitap 2", "Başka Yer")
        shelves.update(record.id, name="Dolap A1")
        locations = {
            row["location"]
            for row in database.fetchall("SELECT location FROM copy")
        }
        assert locations == {"Dolap A1", "Başka Yer"}

    def test_adopt_merges_variant(self, env) -> None:
        database, catalog, shelves = env
        record = shelves.create("Dolap A")
        _book(catalog, "Varyant", "dolap a ")  # yazım varyantı
        moved = shelves.adopt(record.id, "dolap a")
        assert moved == 1
        row = database.fetchone("SELECT location FROM copy WHERE location = 'Dolap A'")
        assert row is not None

    def test_adopt_empty_location_rejected(self, env) -> None:
        *_, shelves = env
        record = shelves.create("Dolap A")
        with pytest.raises(ValueError):
            shelves.adopt(record.id, "  ")

    def test_adopt_rejects_other_shelf_name(self, env) -> None:
        # Reviewer bulgusu: başka dolabın TAM adı "serbest konum" sayılırsa
        # o dolabın bütün nüshaları sessizce taşınırdı.
        _, catalog, shelves = env
        shelf_a = shelves.create("Dolap A")
        shelves.create("Dolap B")
        _book(catalog, "B'de Duran", "Dolap B")
        with pytest.raises(StateConflictError, match="başka bir dolabın adı"):
            shelves.adopt(shelf_a.id, "Dolap B")


class TestMapSummary:
    def test_counts_and_unmatched(self, env) -> None:
        database, catalog, shelves = env
        shelves.create("Dolap A", grid_row=0, grid_col=0, capacity=10)
        edition_id = _book(catalog, "Rafta", "Dolap A")
        catalog.add_copy(edition_id, CopyInput(location="Dolap A"))
        _book(catalog, "Serbest", "Kayıtsız Köşe")
        _book(catalog, "Konumsuz", None)

        members = Members(database)
        loans = Loans(database, AppSettings(database))
        student = members.add(
            member_type="student", school_number="1", first_name="A", last_name="B"
        )
        loans.checkout(student.id, edition_id=edition_id)

        summary = shelves.map_summary()
        shelf = next(item for item in summary["shelves"] if item["name"] == "Dolap A")
        assert shelf["copies"] == 2
        assert shelf["editions"] == 1
        assert shelf["on_loan"] == 1
        assert summary["unmatched"] == [
            {"name": "Kayıtsız Köşe", "copies": 1, "editions": 1}
        ]

    def test_discarded_copies_not_counted(self, env) -> None:
        database, catalog, shelves = env
        shelves.create("Dolap A")
        edition_id = _book(catalog, "Düşecek", "Dolap A")
        with database.transaction() as connection:
            connection.execute(
                "UPDATE copy SET status = 'discarded' WHERE edition_id = ?", (edition_id,)
            )
        summary = shelves.map_summary()
        shelf = next(item for item in summary["shelves"] if item["name"] == "Dolap A")
        assert shelf["copies"] == 0


class TestCopyLocation:
    def test_set_copy_location_single(self, env) -> None:
        database, catalog, _ = env
        edition_id = _book(catalog, "İki Nüsha", "Dolap A")
        second = catalog.add_copy(edition_id, CopyInput(location="Dolap A"))
        catalog.set_copy_location(second, "Dolap B")
        locations = sorted(
            row["location"]
            for row in database.fetchall(
                "SELECT location FROM copy WHERE edition_id = ?", (edition_id,)
            )
        )
        assert locations == ["Dolap A", "Dolap B"]
        with pytest.raises(KeyError):
            catalog.set_copy_location(9999, "X")
