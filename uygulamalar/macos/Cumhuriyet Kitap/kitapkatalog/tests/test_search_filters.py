"""Katalog araması: yeni filtreler (konum/müsaitlik/yıl) ve sıralama beyaz listesi."""

from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, CopyInput, SearchFilters
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    loans = Loans(database, AppSettings(database))

    def add(title: str, *, location: str | None = None, date: str | None = None) -> int:
        record = catalog.save_book(
            BookInput(
                title=title,
                publication_date=date,
                copy=CopyInput(location=location),
            )
        )
        return record.edition_id

    return database, catalog, members, loans, add


def _titles(page) -> list[str]:
    return [record.title for record in page.items]


class TestLocationFilter:
    def test_location_exact_match(self, env) -> None:
        _database, catalog, _members, _loans, add = env
        add("Rafta A", location="Dolap A")
        add("Rafta B", location="Dolap B")
        add("Konumsuz")
        page = catalog.search(filters=SearchFilters(location="Dolap A"))
        assert _titles(page) == ["Rafta A"]

    def test_discarded_copy_not_matched(self, env) -> None:
        database, catalog, _, _, add = env
        edition_id = add("Düşülmüş", location="Dolap A")
        with database.transaction() as connection:
            connection.execute(
                "UPDATE copy SET status = 'discarded' WHERE edition_id = ?", (edition_id,)
            )
        page = catalog.search(filters=SearchFilters(location="Dolap A"))
        assert page.total == 0


class TestAvailabilityFilter:
    def test_available_and_unavailable_are_disjoint(self, env) -> None:
        _database, catalog, members, loans, add = env
        loaned = add("Tamamı Ödünçte", location="X")
        add("Rafta Duran", location="X")
        student = members.add(
            member_type="student", school_number="1", first_name="A", last_name="B"
        )
        loans.checkout(student.id, edition_id=loaned)

        available = catalog.search(filters=SearchFilters(availability="available"))
        unavailable = catalog.search(filters=SearchFilters(availability="unavailable"))
        assert _titles(available) == ["Rafta Duran"]
        assert _titles(unavailable) == ["Tamamı Ödünçte"]

    def test_partial_loan_counts_as_available_only(self, env) -> None:
        # Bir nüshası rafta, biri ödünçte olan baskı YALNIZ "available" sayılır
        # (Codex bulgusu: iki filtreye birden girmemeli).
        _database, catalog, members, loans, add = env
        edition_id = add("Yarısı Ödünçte")
        catalog.add_copy(edition_id, CopyInput())
        student = members.add(
            member_type="student", school_number="2", first_name="C", last_name="D"
        )
        loans.checkout(student.id, edition_id=edition_id)
        assert catalog.search(filters=SearchFilters(availability="available")).total == 1
        assert catalog.search(filters=SearchFilters(availability="unavailable")).total == 0

    def test_availability_scoped_to_location(self, env) -> None:
        # Codex bulgusu: "Dolap A + rafta" filtresi, başka dolaptaki müsait
        # nüshayla sağlanmamalı — iki koşul aynı nüsha kümesinde değerlenir.
        _database, catalog, members, loans, add = env
        edition_id = add("İki Dolaplı", location="Dolap A")
        copy_b = catalog.add_copy(edition_id, CopyInput(location="Dolap B"))
        student = members.add(
            member_type="student", school_number="9", first_name="I", last_name="J"
        )
        # Dolap A'daki nüsha ödünçte (küçük id önce seçilir), B'deki rafta.
        loan = loans.checkout(student.id, edition_id=edition_id)
        assert loan.copy_id != copy_b
        in_a = SearchFilters(location="Dolap A", availability="available")
        in_b = SearchFilters(location="Dolap B", availability="available")
        out_a = SearchFilters(location="Dolap A", availability="unavailable")
        assert catalog.search(filters=in_a).total == 0
        assert catalog.search(filters=in_b).total == 1
        assert catalog.search(filters=out_a).total == 1

    def test_unknown_availability_rejected(self, env) -> None:
        _database, catalog, *_rest = env
        with pytest.raises(ValueError, match="müsaitlik"):
            catalog.search(filters=SearchFilters(availability="belki"))


class TestYearFilter:
    def test_year_range_inclusive(self, env) -> None:
        _database, catalog, _members, _loans, add = env
        add("Eski", date="1999")
        add("Orta", date="2010-05")
        add("Yeni", date="2024")
        add("Bozuk Tarih", date="birinci baskı")
        add("Tarihsiz")
        page = catalog.search(
            filters=SearchFilters(year_from=2000, year_to=2020), sort="title"
        )
        assert _titles(page) == ["Orta"]

    def test_open_ended_ranges(self, env) -> None:
        _database, catalog, _members, _loans, add = env
        add("Eski", date="1999")
        add("Yeni", date="2024")
        assert catalog.search(filters=SearchFilters(year_from=2000)).total == 1
        assert catalog.search(filters=SearchFilters(year_to=2000)).total == 1


class TestSorting:
    def test_title_and_year_sort(self, env) -> None:
        _database, catalog, _members, _loans, add = env
        add("Çilek", date="2020")
        add("Armut", date="2005")
        add("Üzüm", date="2015")
        add("Bozuk", date="birinci baskı")  # yıl sıralamasında sona düşmeli
        assert _titles(catalog.search(sort="title")) == ["Armut", "Bozuk", "Çilek", "Üzüm"]
        assert _titles(catalog.search(sort="year")) == ["Çilek", "Üzüm", "Armut", "Bozuk"]

    def test_popular_sort_counts_all_loans(self, env) -> None:
        _database, catalog, members, loans, add = env
        quiet = add("Sessiz")
        star = add("Gözde")
        student = members.add(
            member_type="student", school_number="3", first_name="E", last_name="F"
        )
        loan = loans.checkout(student.id, edition_id=star)
        loans.return_loan(loan.id)
        loans.checkout(student.id, edition_id=star)
        page = catalog.search(sort="popular")
        assert _titles(page)[0] == "Gözde"
        assert quiet is not None

    def test_unknown_sort_rejected(self, env) -> None:
        _database, catalog, *_rest = env
        with pytest.raises(ValueError, match="sıralama"):
            catalog.search(sort="fiyat; DROP TABLE edition")

    def test_query_keeps_relevance_default(self, env) -> None:
        _database, catalog, _members, _loans, add = env
        add("Deneme Kitabı")
        page = catalog.search("deneme")
        assert page.total == 1  # bm25 yolu sort paramı olmadan da çalışır


class TestCombined:
    def test_filters_compose(self, env) -> None:
        _database, catalog, members, loans, add = env
        hit = add("Hedef", location="Dolap A", date="2018")
        add("Yanlış Dolap", location="Dolap B", date="2018")
        add("Yanlış Yıl", location="Dolap A", date="1980")
        loaned = add("Ödünçte", location="Dolap A", date="2018")
        student = members.add(
            member_type="student", school_number="4", first_name="G", last_name="H"
        )
        loans.checkout(student.id, edition_id=loaned)
        page = catalog.search(
            filters=SearchFilters(
                location="Dolap A", availability="available", year_from=2000
            ),
        )
        assert [record.edition_id for record in page.items] == [hit]
        assert page.total == 1
