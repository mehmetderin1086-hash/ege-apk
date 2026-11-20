"""Düşüm defteri: statü geçişi, korumalar, sayım köprüsü, tutanak Excel'i."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.discards import Discards
from kitapkatalog.domain import BookInput, CopyInput, IdentifierInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings
from kitapkatalog.stocktake import Stocktake
from kitapkatalog.webapp.serialize import book_to_dict

NOW = datetime(2026, 6, 1, 10, 0, tzinfo=UTC)
ISBN = "9789750718533"


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    discards = Discards(database)
    book = catalog.save_book(
        BookInput(
            title="Eskiyen Kitap",
            identifiers=(IdentifierInput(scheme="isbn13", value=ISBN),),
            copy=CopyInput(inventory_code="2026-000001", location="Raf A"),
        )
    )
    catalog.add_copy(book.edition_id, CopyInput(inventory_code="2026-000002", location="Raf A"))
    book = catalog.get_book(book.edition_id)
    return database, catalog, discards, book


class TestDiscard:
    def test_discard_and_effects(self, env) -> None:
        database, catalog, discards, book = env
        record = discards.discard_copy(book.copies[0].id, reason="yipranma", note="Sırtı dağılmış")
        assert record.inventory_code_snapshot == "2026-000001"
        refreshed = catalog.get_book(book.edition_id)
        statuses = {copy.id: copy.status for copy in refreshed.copies}
        assert statuses[book.copies[0].id] == "discarded"
        # İstatistik yalnız aktif nüshayı sayar.
        assert catalog.stats()["copies"] == 1
        # Düşülen nüsha ödünç verilemez.
        members = Members(database)
        loans = Loans(database, AppSettings(database))
        student = members.add(
            member_type="student", school_number="1", first_name="A", last_name="B"
        )
        with pytest.raises(StateConflictError):
            loans.checkout(student.id, copy_id=book.copies[0].id, now=NOW)
        # Sayım beklentisine girmez.
        stocktake = Stocktake(database)
        session = stocktake.open_session("Kontrol")
        report = stocktake.report(session.id)
        assert report["lines"][0]["expected"] == 1

    def test_double_discard_conflict(self, env) -> None:
        *_, discards, book = env
        discards.discard_copy(book.copies[0].id, reason="kayip")
        with pytest.raises(StateConflictError, match="zaten"):
            discards.discard_copy(book.copies[0].id, reason="kayip")

    def test_discard_loaned_copy_rejected(self, env) -> None:
        database, _, discards, book = env
        members = Members(database)
        loans = Loans(database, AppSettings(database))
        student = members.add(
            member_type="student", school_number="9", first_name="C", last_name="D"
        )
        loans.checkout(student.id, copy_id=book.copies[0].id, now=NOW)
        with pytest.raises(StateConflictError, match="ödünçte"):
            discards.discard_copy(book.copies[0].id, reason="kayip")

    def test_restore(self, env) -> None:
        _, catalog, discards, book = env
        record = discards.discard_copy(book.copies[0].id, reason="diger")
        assert discards.restore(record.id) is True
        refreshed = catalog.get_book(book.edition_id)
        assert all(copy.status == "active" for copy in refreshed.copies)
        _, total = discards.list_discards()
        assert total == 0

    def test_copy_count_adjustment_preserves_discard_audit_rows(self, env) -> None:
        _database, catalog, discards, book = env
        discarded_id = book.copies[0].id
        discards.discard_copy(discarded_id, reason="yipranma")

        with pytest.raises(StateConflictError, match="Düşülmüş"):
            catalog.delete_copy(discarded_id)
        audit_rows, audit_total = discards.list_discards()
        assert audit_total == 1
        assert audit_rows[0].copy_id == discarded_id

        after_discard = catalog.get_book(book.edition_id)
        payload = book_to_dict(after_discard)
        assert payload["copy_count"] == 1
        assert payload["active_copies"] == 1
        assert payload["discarded_copies"] == 1
        assert payload["total_copy_records"] == 2

        # Hedef yalnız aktif nüshaları ifade eder. Azaltma/artırma hiçbir
        # durumda düşüm defterinin bağlı olduğu fiziksel kaydı silmez.
        assert catalog.set_copy_count(book.edition_id, 1) == 1
        unchanged = catalog.get_book(book.edition_id)
        assert any(copy.id == discarded_id and copy.status == "discarded" for copy in unchanged.copies)

        assert catalog.set_copy_count(book.edition_id, 3) == 3
        grown = catalog.get_book(book.edition_id)
        assert sum(copy.status == "active" for copy in grown.copies) == 3
        assert sum(copy.status == "discarded" for copy in grown.copies) == 1
        assert any(copy.id == discarded_id for copy in grown.copies)

    def test_edition_inventory_assignment_skips_discarded_copies(self, env) -> None:
        _database, catalog, discards, _book = env
        record = catalog.save_book(BookInput(title="Numarasız Düşüm"))
        catalog.add_copy(record.edition_id)
        before = catalog.get_book(record.edition_id)
        assert before is not None
        discarded = before.copies[0]
        active = before.copies[1]
        discards.discard_copy(discarded.id, reason="yipranma")

        assigned = catalog.assign_missing_inventory_codes(record.edition_id, year=2026)
        refreshed = catalog.get_book(record.edition_id)

        assert assigned.keys() == {active.id}
        assert refreshed is not None
        codes = {copy.id: copy.inventory_code for copy in refreshed.copies}
        assert codes[discarded.id] is None
        assert codes[active.id] == assigned[active.id]

    def test_invalid_reason(self, env) -> None:
        *_, discards, book = env
        with pytest.raises(ValueError, match="gerekçe"):
            discards.discard_copy(book.copies[0].id, reason="canim-istedi")


class TestStocktakeBridge:
    def test_bulk_requires_closed_session(self, env) -> None:
        # Codex bulgusu: açık oturumda rapor bayatlar; düşüm yalnız kapalı
        # oturum üzerinden yapılmalı.
        database, _, discards, _book = env
        stocktake = Stocktake(database)
        session = stocktake.open_session("Açık")
        with pytest.raises(StateConflictError, match="kapat"):
            discards.bulk_from_stocktake(session.id)

    def test_bulk_recomputes_missing_live(self, env) -> None:
        # Rapor ile düşüm arasında eksik nüsha ödünce çıkarsa düşüm YAPILMAZ
        # (canlı yeniden hesap).
        database, _, discards, book = env
        stocktake = Stocktake(database)
        session = stocktake.open_session("Bayat Rapor")
        stocktake.record_scan(session.id, ISBN)  # 2 nüsha, 1 okutma → 1 eksik
        stocktake.close_session(session.id)
        # "Kayıp" sanılan nüsha aslında bir öğrencideymiş: şimdi ödünç verildi.
        members = Members(database)
        loans = Loans(database, AppSettings(database))
        student = members.add(
            member_type="student", school_number="77", first_name="E", last_name="F"
        )
        loans.checkout(student.id, copy_id=book.copies[1].id, now=NOW)
        result = discards.bulk_from_stocktake(session.id)
        assert result["discarded"] == 0

    def test_bulk_from_stocktake_missing(self, env) -> None:
        database, _, discards, _book = env
        stocktake = Stocktake(database)
        session = stocktake.open_session("Kayıp Sayımı")
        stocktake.record_scan(session.id, ISBN)  # 2 nüsha, 1 okutma → 1 eksik
        stocktake.close_session(session.id)
        result = discards.bulk_from_stocktake(session.id)
        assert result["discarded"] == 1
        items, total = discards.list_discards()
        assert total == 1
        assert items[0].reason == "kayip"
        assert items[0].stocktake_session_id == session.id
        # Demirbaş okutması yapılan nüsha değil, okutulmayan düşülür.
        scanned_first = stocktake.report(session.id)
        assert scanned_first["totals"]["missing"] == 0  # eksik artık düşüldü

    def test_bulk_prefers_unscanned_copies(self, env) -> None:
        database, _, discards, _book = env
        stocktake = Stocktake(database)
        session = stocktake.open_session("Demirbaşlı")
        stocktake.record_scan(session.id, "2026-000002")  # nüsha 2 rafta görüldü
        stocktake.close_session(session.id)
        result = discards.bulk_from_stocktake(session.id)
        assert result["discarded"] == 1
        items, _ = discards.list_discards()
        assert items[0].inventory_code_snapshot == "2026-000001"


class TestTutanak:
    def test_export_tutanak_xlsx(self, env, tmp_path: Path) -> None:
        *_, discards, book = env
        discards.discard_copy(book.copies[0].id, reason="yipranma", note="Su almış")
        destination = tmp_path / "tutanak.xlsx"
        discards.export_tutanak_xlsx(destination)

        from openpyxl import load_workbook

        sheet = load_workbook(destination).active
        rows = list(sheet.iter_rows(values_only=True))
        assert any("2026-000001" in str(row) and "Yıpranma" in str(row) for row in rows)
