"""Yıl sonu raporu (Reports.annual + /api/reports/annual) testleri."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, CopyInput, IdentifierInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.reports import Reports
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 3, 10, 12, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    return database, catalog, members, loans


def _book(catalog: Catalog, *, title: str, isbn: str, year: str, category: str) -> object:
    return catalog.save_book(
        BookInput(
            title=title,
            publication_date=year,
            category=category,
            identifiers=(IdentifierInput(scheme="isbn13", value=isbn),),
            copy=CopyInput(inventory_code=f"D-{isbn[-6:]}"),
        )
    )


def test_annual_report_aggregates_collection_and_circulation(env) -> None:
    database, catalog, members, loans = env
    student = members.add(
        member_type="student",
        school_number="501",
        first_name="Rapor",
        last_name="Öğrencisi",
        class_name="8-A",
    )
    new_book = _book(
        catalog, title="Yeni Roman", isbn="9789750718533", year="2025", category="Roman"
    )
    _book(catalog, title="Eski Ansiklopedi", isbn="9789750500930", year="1995", category="Başvuru")
    loan = loans.checkout(student.id, edition_id=new_book.edition_id, now=NOW)
    loans.return_loan(loan.id, now=NOW)

    report = Reports(database).annual(start="2025-09-01", end="2026-06-30")

    assert report["collection"]["editions"] == 2
    assert report["collection"]["copies"] == 2
    assert report["circulation"]["loans"] == 1
    assert report["circulation"]["returns"] == 1
    assert report["circulation"]["readers"] == 1
    assert report["monthly"] == [{"month": "2026-03", "loans": 1}]
    categories = {row["category"]: row["n"] for row in report["categories"]}
    assert categories == {"Roman": 1, "Başvuru": 1}
    # Yaş analizi: 2025 yayını 0-4 kovasında, 1995 yayını 20+ kovasında.
    assert report["age_analysis"]["buckets"]["0-4"] == 1
    assert report["age_analysis"]["buckets"]["20+"] == 1
    assert report["age_analysis"]["unknown"] == 0
    assert report["top_books"][0]["title"] == "Yeni Roman"
    assert report["top_readers"][0]["member_name"] == "Rapor Öğrencisi"


def test_annual_report_period_filters_loans(env) -> None:
    database, catalog, members, loans = env
    student = members.add(
        member_type="student", school_number="502", first_name="Dönem", last_name="Dışı"
    )
    book = _book(
        catalog, title="Tek Kitap", isbn="9789750718533", year="2020", category="Roman"
    )
    early = loans.checkout(
        student.id, edition_id=book.edition_id, now=datetime(2024, 1, 5, tzinfo=UTC)
    )
    loans.return_loan(early.id, now=datetime(2024, 1, 20, tzinfo=UTC))

    report = Reports(database).annual(start="2025-09-01", end="2026-06-30")
    assert report["circulation"]["loans"] == 0
    assert report["monthly"] == []
    # Koleksiyon sayıları dönemden bağımsızdır.
    assert report["collection"]["editions"] == 1


def test_annual_endpoint_defaults_to_school_year(tmp_path: Path) -> None:
    fastapi = pytest.importorskip("fastapi")  # noqa: F841
    from fastapi.testclient import TestClient

    from kitapkatalog.application import open_application
    from kitapkatalog.config import AppPaths
    from kitapkatalog.webapp.app import create_app

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
    context = open_application(paths, enforce_offline=False)
    app = create_app(context)
    with TestClient(app, base_url="http://127.0.0.1") as client:
        client.get(f"/?token={app.state.web.token}", follow_redirects=False)
        payload = client.get("/api/reports/annual").json()
        assert payload["period"]["start"].endswith("-09-01")
        assert payload["collection"]["editions"] == 0
        explicit = client.get(
            "/api/reports/annual?start=2025-09-01&end=2026-06-30"
        ).json()
        assert explicit["period"] == {"start": "2025-09-01", "end": "2026-06-30"}
