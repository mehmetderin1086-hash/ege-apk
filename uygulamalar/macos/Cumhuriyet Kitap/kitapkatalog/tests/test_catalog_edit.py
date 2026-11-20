"""Kütüphane GUI'sinin kullandığı düzenleme/istatistik API'lerinin testleri."""

from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog, IdentifierConflictError
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, ContributorInput, SearchFilters


@pytest.fixture
def catalog(tmp_path: Path) -> Catalog:
    return Catalog(Database(tmp_path / "catalog.sqlite3"))


def _seed(catalog: Catalog) -> tuple[int, int]:
    first = catalog.save_book(
        BookInput(
            title="Tutunamayanlar",
            publisher="İletişim",
            language="Türkçe",
            category="Roman",
            page_count=724,
            contributors=(
                ContributorInput("Oğuz Atay", "author"),
                ContributorInput("Berna Moran", "foreword"),
            ),
        ),
        source_fingerprint="test:1",
    )
    second = catalog.save_book(
        BookInput(title="Sessiz Ev", language="Türkçe"),
        source_fingerprint="test:2",
    )
    return first.edition_id, second.edition_id


def test_set_authors_replaces_only_author_role(catalog: Catalog) -> None:
    first_id, _second_id = _seed(catalog)
    catalog.set_authors(first_id, ["Yeni Yazar", "İkinci Yazar"])
    book = catalog.get_book(first_id)
    assert book is not None
    authors = [c.name for c in book.contributors if str(c.role) == "author"]
    others = [(c.name, str(c.role)) for c in book.contributors if str(c.role) != "author"]
    assert authors == ["Yeni Yazar", "İkinci Yazar"]
    assert others == [("Berna Moran", "foreword")]


def test_set_authors_empty_clears_authors(catalog: Catalog) -> None:
    first_id, _second_id = _seed(catalog)
    catalog.set_authors(first_id, ["", "  "])
    book = catalog.get_book(first_id)
    assert book is not None
    assert [c.name for c in book.contributors if str(c.role) == "author"] == []


def test_set_isbn_derives_pair_and_clears(catalog: Catalog) -> None:
    first_id, _second_id = _seed(catalog)
    catalog.set_isbn(first_id, "978-975-470-011-4")
    book = catalog.get_book(first_id)
    assert book is not None
    schemes = {i.scheme: i.value for i in book.identifiers}
    assert schemes["ISBN13"] == "9789754700114"
    assert "ISBN10" in schemes  # 978 önekli ISBN-13'ten türetilir

    catalog.set_isbn(first_id, None)
    book = catalog.get_book(first_id)
    assert book is not None
    assert not [i for i in book.identifiers if i.scheme.startswith("ISBN")]


def test_set_isbn_invalid_and_conflict(catalog: Catalog) -> None:
    first_id, second_id = _seed(catalog)
    catalog.set_isbn(first_id, "9789754700114")
    with pytest.raises(ValueError):
        catalog.set_isbn(second_id, "1234567890120")  # geçersiz sağlama hanesi
    with pytest.raises(IdentifierConflictError):
        catalog.set_isbn(second_id, "9789754700114")
    book = catalog.get_book(second_id)
    assert book is not None
    assert not book.identifiers  # başarısız deneme kayıt bırakmaz


def test_search_category_and_missing_filters(catalog: Catalog) -> None:
    first_id, second_id = _seed(catalog)
    by_category = catalog.search(filters=SearchFilters(category="roman"))
    assert [b.edition_id for b in by_category.items] == [first_id]

    missing_category = catalog.search(filters=SearchFilters(missing="category"))
    assert [b.edition_id for b in missing_category.items] == [second_id]

    missing_isbn = catalog.search(filters=SearchFilters(missing="isbn"))
    assert {b.edition_id for b in missing_isbn.items} == {first_id, second_id}

    catalog.set_isbn(first_id, "9789754700114")
    missing_isbn = catalog.search(filters=SearchFilters(missing="isbn"))
    assert [b.edition_id for b in missing_isbn.items] == [second_id]

    missing_pages = catalog.search(filters=SearchFilters(missing="page_count"))
    assert [b.edition_id for b in missing_pages.items] == [second_id]

    with pytest.raises(ValueError):
        catalog.search(filters=SearchFilters(missing="bilinmeyen"))


def test_distribution_groups_and_orders(catalog: Catalog) -> None:
    _seed(catalog)
    languages = catalog.distribution("language")
    assert languages == [("Türkçe", 2)]
    categories = dict(catalog.distribution("category"))
    assert categories == {"Roman": 1, "—": 1}
    with pytest.raises(ValueError):
        catalog.distribution("title")


def test_set_location_updates_all_copies(catalog: Catalog) -> None:
    first_id, _second_id = _seed(catalog)
    catalog.add_copy(first_id)
    assert catalog.set_location(first_id, "  Dolap 3  ") == 2
    book = catalog.get_book(first_id)
    assert book is not None
    assert [c.location for c in book.copies] == ["Dolap 3", "Dolap 3"]

    catalog.set_location(first_id, None)
    book = catalog.get_book(first_id)
    assert book is not None
    assert [c.location for c in book.copies] == [None, None]

    with pytest.raises(KeyError):
        catalog.set_location(99_999, "D1")


def test_set_copy_count_grows_shrinks_and_inherits_location(
    catalog: Catalog,
) -> None:
    first_id, _second_id = _seed(catalog)
    catalog.set_location(first_id, "Dolap 1")
    catalog.set_copy_count(first_id, 4)
    book = catalog.get_book(first_id)
    assert book is not None
    assert len(book.copies) == 4
    assert {c.location for c in book.copies} == {"Dolap 1"}  # devralındı

    catalog.set_copy_count(first_id, 2, location="Dolap 2")
    book = catalog.get_book(first_id)
    assert book is not None
    assert len(book.copies) == 2

    catalog.set_copy_count(first_id, 0)  # en az 1 kopya korunur
    book = catalog.get_book(first_id)
    assert book is not None
    assert len(book.copies) == 1


def test_list_distinct_values_location(catalog: Catalog) -> None:
    first_id, second_id = _seed(catalog)
    catalog.set_location(first_id, "B Dolabı")
    catalog.set_location(second_id, "A Dolabı")
    assert catalog.list_distinct_values("location") == ["A Dolabı", "B Dolabı"]
