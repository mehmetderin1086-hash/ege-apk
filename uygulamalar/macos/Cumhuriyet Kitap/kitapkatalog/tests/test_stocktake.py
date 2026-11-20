"""Sayım modülü: adet mutabakatı, kapsam, olay logu, rapor ve Excel çıktısı."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput, CopyInput, IdentifierInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings
from kitapkatalog.stocktake import Stocktake

NOW = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)
ISBN = "9789750718533"


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    stocktake = Stocktake(database)
    book = catalog.save_book(
        BookInput(
            title="Beyaz Gemi",
            identifiers=(IdentifierInput(scheme="isbn13", value=ISBN),),
            copy=CopyInput(inventory_code="2026-000001", location="Raf A"),
        )
    )
    catalog.add_copy(book.edition_id, CopyInput(inventory_code="2026-000002", location="Raf A"))
    catalog.add_copy(book.edition_id, CopyInput(inventory_code="2026-000003", location="Raf B"))
    book = catalog.get_book(book.edition_id)  # kopya listesi tazelensin
    return database, catalog, stocktake, book


def _loan_first_copy(database: Database, book) -> None:
    members = Members(database)
    loans = Loans(database, AppSettings(database))
    student = members.add(
        member_type="student", school_number="1", first_name="A", last_name="B"
    )
    loans.checkout(student.id, copy_id=book.copies[0].id, now=NOW)


class TestReconciliation:
    def test_core_scenario_loaned_copy_not_missing(self, env) -> None:
        database, _, stocktake, book = env
        _loan_first_copy(database, book)
        session = stocktake.open_session("Dönem sonu")
        stocktake.record_scan(session.id, ISBN)
        stocktake.record_scan(session.id, ISBN)
        report = stocktake.report(session.id)
        line = report["lines"][0]
        assert line["expected"] == 3
        assert line["on_loan"] == 1
        assert line["scanned"] == 2
        assert line["missing"] == 0
        assert line["surplus"] == 0

    def test_missing_and_surplus(self, env) -> None:
        database, _, stocktake, book = env
        _loan_first_copy(database, book)
        session = stocktake.open_session("Eksik senaryosu")
        stocktake.record_scan(session.id, ISBN)
        report = stocktake.report(session.id)
        assert report["lines"][0]["missing"] == 1
        stocktake.record_scan(session.id, ISBN)
        stocktake.record_scan(session.id, ISBN)
        report = stocktake.report(session.id)
        assert report["lines"][0]["missing"] == 0
        assert report["lines"][0]["surplus"] == 1

    def test_scope_location_filters_expectations(self, env) -> None:
        _, _, stocktake, _book = env
        session = stocktake.open_session("Raf A sayımı", scope_location="Raf A")
        stocktake.record_scan(session.id, "2026-000001")
        report = stocktake.report(session.id)
        line = report["lines"][0]
        assert line["expected"] == 2  # Raf B'deki nüsha kapsam dışı
        assert line["scanned"] == 1
        assert line["missing"] == 1

    def test_inventory_scan_binds_copy(self, env) -> None:
        _, _, stocktake, book = env
        session = stocktake.open_session("Demirbaş")
        result = stocktake.record_scan(session.id, "2026-000002")
        assert result["code_type"] == "inventory"
        assert result["copy_id"] == book.copies[1].id
        assert result["edition_id"] == book.edition_id

    def test_duplicate_inventory_scan_not_double_counted(self, env) -> None:
        # Codex bulgusu: aynı demirbaş iki kez okutulursa nüsha çift sayılıp
        # gerçek kaybı maskeleyebilir. Nüsha düzeyinde tekilleştirilmeli.
        _, _, stocktake, _book = env
        session = stocktake.open_session("Tekrar")
        first = stocktake.record_scan(session.id, "2026-000001")
        assert first.get("duplicate") is not True
        second = stocktake.record_scan(session.id, "2026-000001")
        assert second["duplicate"] is True
        report = stocktake.report(session.id)
        assert report["lines"][0]["scanned"] == 1  # çift sayım yok

    def test_out_of_scope_inventory_scan_rejected(self, env) -> None:
        # Raf A oturumunda Raf B demirbaşı okutulursa Raf A'nın eksiğini
        # kapatmamalı; kayıt edilmez, kullanıcı uyarılır.
        _, _, stocktake, _book = env
        session = stocktake.open_session("Raf A", scope_location="Raf A")
        result = stocktake.record_scan(session.id, "2026-000003")  # Raf B'de
        assert result["out_of_scope"] is True
        report = stocktake.report(session.id)
        assert report["lines"][0]["scanned"] == 0

    def test_unresolved_code_is_kept_and_reported(self, env) -> None:
        _, _, stocktake, _ = env
        session = stocktake.open_session("Bilinmeyen")
        result = stocktake.record_scan(session.id, "9990000000000")
        assert result["code_type"] == "unresolved"
        report = stocktake.report(session.id)
        assert report["unresolved"][0]["raw_code"] == "9990000000000"

    def test_isbnless_unscanned_goes_to_manual_list(self, env) -> None:
        _, catalog, stocktake, _ = env
        catalog.save_book(BookInput(title="ISBN'siz Eski Kitap", copy=CopyInput(location="Raf A")))
        session = stocktake.open_session("Tam sayım")
        report = stocktake.report(session.id)
        manual = [line for line in report["manual_check"]]
        assert any(line["title"] == "ISBN'siz Eski Kitap" for line in manual)
        # Elle sayım listesindeki kitap 'eksik' toplamına girmez.
        assert all(line["title"] != "ISBN'siz Eski Kitap" for line in report["lines"] if line["missing"] > 0)

    def test_manual_mark_via_search(self, env) -> None:
        _, catalog, stocktake, _ = env
        record = catalog.save_book(BookInput(title="ISBN'siz Kitap", copy=CopyInput()))
        session = stocktake.open_session("Elle")
        result = stocktake.record_scan(session.id, "elle", manual_edition_id=record.edition_id)
        assert result["code_type"] == "manual"
        report = stocktake.report(session.id)
        line = next(item for item in report["lines"] if item["edition_id"] == record.edition_id)
        assert line["scanned"] == 1


class TestSessionLifecycle:
    def test_closed_session_rejects_scans(self, env) -> None:
        _, _, stocktake, _ = env
        session = stocktake.open_session("Kapanacak")
        stocktake.close_session(session.id)
        with pytest.raises(StateConflictError, match="kapalı"):
            stocktake.record_scan(session.id, ISBN)
        with pytest.raises(StateConflictError, match="zaten"):
            stocktake.close_session(session.id)

    def test_undo_scan(self, env) -> None:
        _, _, stocktake, _ = env
        session = stocktake.open_session("Geri al")
        result = stocktake.record_scan(session.id, ISBN)
        assert stocktake.undo_scan(result["scan_id"]) is True
        report = stocktake.report(session.id)
        assert report["lines"][0]["scanned"] == 0

    def test_progress(self, env) -> None:
        database, _, stocktake, book = env
        _loan_first_copy(database, book)
        session = stocktake.open_session("İlerleme")
        progress = stocktake.progress(session.id)
        assert progress["expected_on_shelf"] == 2
        assert progress["scanned"] == 0
        stocktake.record_scan(session.id, ISBN)
        progress = stocktake.progress(session.id)
        assert progress["scanned"] == 1
        assert progress["percent"] == 50


class TestExport:
    def test_excel_report_roundtrip(self, env, tmp_path: Path) -> None:
        database, _, stocktake, book = env
        _loan_first_copy(database, book)
        session = stocktake.open_session("Excel")
        stocktake.record_scan(session.id, ISBN)
        stocktake.record_scan(session.id, "TANIMSIZ-KOD-XYZ")
        destination = tmp_path / "rapor.xlsx"
        stocktake.export_report_xlsx(session.id, destination)

        from openpyxl import load_workbook

        workbook = load_workbook(destination)
        assert {"Özet", "Eksikler", "Ödünçte", "Eşleşmeyenler"} <= set(workbook.sheetnames)
        unresolved_rows = list(workbook["Eşleşmeyenler"].iter_rows(values_only=True))
        assert any("TANIMSIZ-KOD-XYZ" in str(row) for row in unresolved_rows)
