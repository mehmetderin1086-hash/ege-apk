"""codes.py: serbest barkod çözümleme önceliği ve ISBN adayı ayıklama."""

from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.codes import isbn_candidate, resolve_catalog_code
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, CopyInput, IdentifierInput


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    return database, catalog


class TestIsbnCandidate:
    def test_ten_and_thirteen_digits(self) -> None:
        assert isbn_candidate("978-975-07-1853-3") == "9789750718533"
        assert isbn_candidate("975070185x") == "975070185X"

    def test_other_lengths_rejected(self) -> None:
        assert isbn_candidate("12345") is None
        assert isbn_candidate("") is None
        assert isbn_candidate("KOD-YOK") is None
        # 11 hane: ne ISBN10 ne ISBN13.
        assert isbn_candidate("12345678901") is None


class TestResolveCatalogCode:
    def test_inventory_exact_match_wins_over_isbn(self, env) -> None:
        # Barkod öncelik tuzağı: "2026-000001" rakam ayıklanınca 10 haneye
        # düşer; aynı değer bir ISBN olarak kayıtlı olsa bile demirbaş kazanır.
        database, catalog = env
        book = catalog.save_book(
            BookInput(title="Demirbaşlı", copy=CopyInput(inventory_code="2026-000001"))
        )
        other = catalog.save_book(BookInput(title="Tuzak ISBN"))
        # Kompakt "2026000001" başka baskının tanımlayıcısıymış gibi kaydedilsin
        # (checksum doğrulamasını aşmak için ham SQL).
        with database.transaction() as connection:
            connection.execute(
                """
                INSERT INTO identifier(edition_id, scheme, value, normalized_value,
                                       source, created_at)
                VALUES (?, 'ISBN10', '2026000001', '2026000001', 'user', '2026-01-01')
                """,
                (other.edition_id,),
            )
        with database.connection(readonly=True) as connection:
            resolved = resolve_catalog_code(connection, "2026-000001")
        assert resolved.kind == "inventory"
        assert resolved.copy_id == book.copies[0].id
        assert resolved.edition_id == book.edition_id

    def test_isbn_fallback(self, env) -> None:
        database, catalog = env
        book = catalog.save_book(
            BookInput(
                title="Beyaz Gemi",
                identifiers=(IdentifierInput(scheme="isbn13", value="9789750718533"),),
            )
        )
        with database.connection(readonly=True) as connection:
            resolved = resolve_catalog_code(connection, "978-975-07-1853-3")
        assert resolved.kind == "isbn"
        assert resolved.copy_id is None
        assert resolved.edition_id == book.edition_id

    def test_unresolved(self, env) -> None:
        database, catalog = env
        catalog.save_book(BookInput(title="Alakasız"))
        with database.connection(readonly=True) as connection:
            assert resolve_catalog_code(connection, "OLMAYAN-KOD").kind == "unresolved"
            assert resolve_catalog_code(connection, "").kind == "unresolved"
            assert resolve_catalog_code(connection, "   ").kind == "unresolved"
