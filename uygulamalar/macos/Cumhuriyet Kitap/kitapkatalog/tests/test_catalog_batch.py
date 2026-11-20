"""Toplu kayıt hidrasyonu: N+1 bekçisi ve tekil/toplu eşitlik testleri."""

from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, ContributorInput, CopyInput, IdentifierInput


def _isbn13(index: int) -> str:
    body = f"9780000{index:05d}"
    total = sum(int(digit) * (1 if pos % 2 == 0 else 3) for pos, digit in enumerate(body))
    return body + str((10 - total % 10) % 10)


def _seed(catalog: Catalog, count: int) -> list[int]:
    edition_ids = []
    for index in range(count):
        record = catalog.save_book(
            BookInput(
                title=f"Kitap {index:03d}",
                publisher=f"Yayınevi {index % 7}",
                contributors=(
                    ContributorInput(name=f"Yazar {index}", role="author"),
                    ContributorInput(name=f"Çevirmen {index}", role="translator", sort_order=1),
                ),
                identifiers=(IdentifierInput(scheme="isbn13", value=_isbn13(index)),),
                copy=CopyInput(source_fingerprint=f"fp-{index}", location=f"Raf {index % 5}"),
            )
        )
        catalog.add_copy(record.edition_id, CopyInput(source_fingerprint=f"fp-{index}-b"))
        edition_ids.append(record.edition_id)
    return edition_ids


@pytest.fixture()
def catalog(tmp_path: Path) -> Catalog:
    return Catalog(Database(tmp_path / "catalog.sqlite3"))


def test_search_page_runs_bounded_select_count(
    catalog: Catalog, monkeypatch: pytest.MonkeyPatch
) -> None:
    _seed(catalog, 60)
    database = catalog.db
    selects: list[str] = []
    original = database._new_connection

    def traced(*, readonly: bool = False):
        connection = original(readonly=readonly)
        connection.set_trace_callback(
            lambda statement: selects.append(statement)
            if statement.lstrip().upper().startswith("SELECT")
            else None
        )
        return connection

    monkeypatch.setattr(database, "_new_connection", traced)
    page = catalog.search(limit=50)
    assert len(page.items) == 50
    # COUNT + sayfa + 3 toplu hidrasyon sorgusu; kayıt başına sorgu YOK.
    assert len(selects) <= 6, f"{len(selects)} SELECT çalıştı:\n" + "\n".join(selects[:12])


def test_batch_hydration_matches_single_record(catalog: Catalog) -> None:
    edition_ids = _seed(catalog, 25)
    page = catalog.search(limit=25)
    by_id = {record.edition_id: record for record in page.items}
    assert set(by_id) == set(edition_ids)
    for edition_id in edition_ids:
        single = catalog.get_book(edition_id)
        assert single is not None
        batch = by_id[edition_id]
        assert batch == single
        assert len(batch.copies) == 2
        assert len(batch.contributors) == 2
        assert any(item.scheme == "ISBN13" for item in batch.identifiers)


def test_list_books_uses_batch_hydration(
    catalog: Catalog, monkeypatch: pytest.MonkeyPatch
) -> None:
    _seed(catalog, 30)
    database = catalog.db
    selects: list[str] = []
    original = database._new_connection

    def traced(*, readonly: bool = False):
        connection = original(readonly=readonly)
        connection.set_trace_callback(
            lambda statement: selects.append(statement)
            if statement.lstrip().upper().startswith("SELECT")
            else None
        )
        return connection

    monkeypatch.setattr(database, "_new_connection", traced)
    records = catalog.list_books(limit=30)
    assert len(records) == 30
    assert len(selects) <= 5, f"{len(selects)} SELECT çalıştı"
