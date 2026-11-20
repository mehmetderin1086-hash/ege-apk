"""Demirbaş numarası üretici: yıl+sıra biçimi, işgal atlama, thread ayrıklığı."""

from __future__ import annotations

import threading
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, CopyInput


@pytest.fixture()
def catalog(tmp_path: Path) -> Catalog:
    return Catalog(Database(tmp_path / "catalog.sqlite3"))


def test_sequential_format(catalog: Catalog) -> None:
    codes = catalog.allocate_inventory_codes(3, year=2026)
    assert codes == ["2026-000001", "2026-000002", "2026-000003"]
    more = catalog.allocate_inventory_codes(1, year=2026)
    assert more == ["2026-000004"]
    other_year = catalog.allocate_inventory_codes(1, year=2027)
    assert other_year == ["2027-000001"]


def test_occupied_codes_are_skipped(catalog: Catalog) -> None:
    catalog.save_book(
        BookInput(title="Elle Numaralı", copy=CopyInput(inventory_code="2026-000002"))
    )
    codes = catalog.allocate_inventory_codes(2, year=2026)
    assert codes == ["2026-000001", "2026-000003"]


def test_threads_get_disjoint_ranges(catalog: Catalog) -> None:
    barrier = threading.Barrier(2)
    results: list[list[str]] = []

    def worker() -> None:
        barrier.wait()
        results.append(catalog.allocate_inventory_codes(5, year=2026))

    threads = [threading.Thread(target=worker) for _ in range(2)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()
    flat = [code for chunk in results for code in chunk]
    assert len(flat) == 10
    assert len(set(flat)) == 10


def test_assign_missing_inventory_codes(catalog: Catalog) -> None:
    book = catalog.save_book(
        BookInput(title="Karışık", copy=CopyInput(inventory_code="ELLE-1"))
    )
    catalog.add_copy(book.edition_id)
    catalog.add_copy(book.edition_id)
    assigned = catalog.assign_missing_inventory_codes(book.edition_id, year=2026)
    assert len(assigned) == 2
    refreshed = catalog.get_book(book.edition_id)
    codes = sorted(copy.inventory_code for copy in refreshed.copies)
    assert codes == ["2026-000001", "2026-000002", "ELLE-1"]
    # İkinci çağrı boş döner (dolduracak nüsha kalmadı).
    assert catalog.assign_missing_inventory_codes(book.edition_id) == {}
