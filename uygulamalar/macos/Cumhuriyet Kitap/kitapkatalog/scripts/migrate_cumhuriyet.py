#!/usr/bin/env python3
"""Cumhuriyet Kütüphanesi (Next.js + Prisma) verisini bu kataloğa göçürür.

Kaynak: cumhuriyet-kutuphanesi/prisma/dev.db (salt-okunur açılır).
Hedef: KITAPKATALOG_DATA_DIR (varsayılan kullanıcı veri kökü) altındaki katalog.

Yazma yalnız kitapkatalog'un kendi API'leriyle yapılır (FTS/parmak izi
tutarlılığı için ham SQL INSERT yok). Tekrar koşmak güvenlidir: baskılar
``cumhuriyet:book:<id>``, nüshalar ``cumhuriyet:copy:<id>`` parmak izi ve
envanter koduyla eşlenip birleştirilir.

Sözleşme: bu bir TEK SEFERLİK göçtür, senkronizasyon değil. Tekrar koşu yalnız
eksikleri tamamlar (``save_book`` overwrite=False): kaynakta sonradan değişen
başlık/yazar/kapak hedefte GÜNCELLENMEZ, değişen nüsha barkodu yeni nüsha
sanılabilir. Kaynak veri değiştiyse aradaki farkı elle aktarın.

Kullanım:
    PYTHONPATH=src .venv/bin/python scripts/migrate_cumhuriyet.py --dry-run
    PYTHONPATH=src .venv/bin/python scripts/migrate_cumhuriyet.py --limit 20
    PYTHONPATH=src .venv/bin/python scripts/migrate_cumhuriyet.py
"""

from __future__ import annotations

import argparse
import shutil
import sqlite3
import sys
from pathlib import Path

from kitapkatalog.catalog import Catalog, LockedFieldError, normalise_identifier
from kitapkatalog.config import AppPaths
from kitapkatalog.database import StateConflictError
from kitapkatalog.domain import BookInput, ContributorInput, CopyInput, IdentifierInput
from kitapkatalog.shelves import Shelves

DEFAULT_PRISMA_DB = (
    Path.home() / "Developer" / "cumhuriyet-kutuphanesi" / "prisma" / "dev.db"
)

LANGUAGES = {"tr": "Türkçe", "en": "İngilizce", "fr": "Fransızca"}


def _connect_readonly(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def _contributors(authors: str) -> tuple[ContributorInput, ...]:
    names = [name.strip() for name in (authors or "").split(",") if name.strip()]
    return tuple(
        ContributorInput(name=name, role="author", sort_order=index)
        for index, name in enumerate(names)
    )


def _identifiers(isbn: str | None) -> tuple[IdentifierInput, ...]:
    if not isbn:
        return ()
    digits = [ch for ch in isbn if ch.isdigit() or ch in "xX"]
    scheme = "ISBN10" if len(digits) == 10 else "ISBN13"
    try:
        normalise_identifier(scheme, isbn)
    except ValueError:
        # Bozuk ISBN tüm göçü durdurmasın: kitap ISBN'siz göçer, uyarı düşer.
        print(f"UYARI: geçersiz ISBN atlandı: {isbn!r}", file=sys.stderr)
        return ()
    return (IdentifierInput(scheme=scheme, value=isbn, source="cumhuriyet_import"),)


def _copy_notes(book: sqlite3.Row) -> str | None:
    parts = []
    if book["notes"]:
        parts.append(str(book["notes"]).strip())
    if book["dewey"]:
        parts.append(f"Dewey: {book['dewey']}")
    return " · ".join(parts) or None


def _copy_input(
    copy_row: sqlite3.Row, book: sqlite3.Row, shelf_code: str | None
) -> CopyInput:
    price = book["price"]
    return CopyInput(
        inventory_code=copy_row["barcode"],
        source_fingerprint=f"cumhuriyet:copy:{copy_row['id']}",
        location=shelf_code,
        notes=_copy_notes(book),
        acquisition_price=f"{price:g}" if price is not None else None,
    )


def _cover_source(uploads: Path, cover_url: str | None) -> Path | None:
    if not cover_url:
        return None
    source = uploads / Path(cover_url).name
    return source if source.is_file() else None


def migrate(prisma_db: Path, *, dry_run: bool, limit: int | None) -> int:
    if not prisma_db.is_file():
        print(f"HATA: Prisma veritabanı bulunamadı: {prisma_db}", file=sys.stderr)
        return 1
    uploads = prisma_db.parent / "uploads"
    paths = AppPaths.default()
    if not dry_run:
        paths.ensure()
    covers_dir = paths.assets / "web_covers"

    source = _connect_readonly(prisma_db)
    try:
        shelves_rows = source.execute(
            "SELECT id, code, name, location, capacity FROM Shelf ORDER BY sortOrder, code"
        ).fetchall()
        categories = {
            row["id"]: row["name"]
            for row in source.execute("SELECT id, name FROM Category")
        }
        book_sql = "SELECT * FROM Book ORDER BY createdAt, id"
        if limit is not None:
            book_sql += f" LIMIT {int(limit)}"
        books = source.execute(book_sql).fetchall()
        copies_by_book: dict[str, list[sqlite3.Row]] = {}
        for row in source.execute(
            "SELECT id, barcode, status, bookId FROM BookCopy ORDER BY barcode"
        ):
            copies_by_book.setdefault(row["bookId"], []).append(row)
    finally:
        source.close()

    shelf_codes = {row["id"]: row["code"] for row in shelves_rows}
    total_copies = sum(len(copies_by_book.get(row["id"], ())) for row in books)
    odd_status = [
        (copy_row["barcode"], copy_row["status"])
        for rows in copies_by_book.values()
        for copy_row in rows
        if copy_row["status"] != "AVAILABLE"
    ]
    print(
        f"Kaynak: {len(books)} kitap, {total_copies} nüsha, "
        f"{len(shelves_rows)} dolap, {len(categories)} kategori"
    )
    if odd_status:
        print(
            f"UYARI: {len(odd_status)} nüsha AVAILABLE değil (elle gözden geçirin): "
            f"{odd_status[:5]}"
        )
    if dry_run:
        with_cover = sum(
            1 for row in books if _cover_source(uploads, row["coverUrl"]) is not None
        )
        print(f"Kuru koşu: yazma yok. Kapak dosyası bulunan kitap: {with_cover}")
        return 0

    catalog = Catalog(paths.database)
    shelves = Shelves(catalog.db)
    created_shelves = 0
    for row in shelves_rows:
        notes = " · ".join(part for part in (row["name"], row["location"]) if part) or None
        capacity = row["capacity"]
        try:
            shelves.create(
                row["code"],
                capacity=capacity if capacity and capacity > 0 else None,
                notes=notes,
            )
            created_shelves += 1
        except StateConflictError:
            pass  # Aynı ad zaten var: tekrar koşu.

    covers_dir.mkdir(parents=True, exist_ok=True)
    editions = copies = covers = 0
    for index, book in enumerate(books, start=1):
        copy_rows = copies_by_book.get(book["id"], [])
        shelf_code = shelf_codes.get(book["shelfId"])
        first_copy = (
            _copy_input(copy_rows[0], book, shelf_code) if copy_rows else None
        )
        year = book["printYear"] or book["publishedYear"]
        book_input = BookInput(
            title=book["title"],
            subtitle=book["subtitle"],
            publisher=book["publisher"],
            publication_date=str(year) if year else None,
            edition_statement=book["edition"],
            binding=book["binding"],
            page_count=book["pageCount"],
            language=LANGUAGES.get(book["language"], book["language"]),
            blurb=book["description"],
            category=categories.get(book["categoryId"]),
            contributors=_contributors(book["authors"]),
            identifiers=_identifiers(book["isbn"]),
            copy=first_copy,
        )
        try:
            record = catalog.save_book(
                book_input,
                source_fingerprint=f"cumhuriyet:book:{book['id']}",
                add_copy=first_copy is not None,
            )
            editions += 1
            copies += len(copy_rows)
            for copy_row in copy_rows[1:]:
                catalog.add_copy(
                    record.edition_id, _copy_input(copy_row, book, shelf_code)
                )

            changes: dict[str, object] = {"review_status": "completed"}
            cover = _cover_source(uploads, book["coverUrl"])
            if cover is not None:
                target = covers_dir / f"cumhuriyet-{cover.name}"
                if not target.is_file():
                    # Yarım kopya kalıcılaşmasın: geçici ada yaz, atomik taşı.
                    temp = target.with_name(target.name + ".tmp")
                    shutil.copy2(cover, temp)
                    temp.replace(target)
                changes["front_path"] = str(target)
                covers += 1
            try:
                catalog.update_book(record.edition_id, changes, user_edit=False)
            except LockedFieldError:
                # Kullanıcı bu kitabın bir alanını UI'dan düzenlemiş; kilitli
                # alanı ez ME, kalan alanları tek tek dene.
                for field, value in changes.items():
                    try:
                        catalog.update_book(
                            record.edition_id, {field: value}, user_edit=False
                        )
                    except LockedFieldError:
                        print(
                            f"UYARI: kilitli alan atlandı: baskı "
                            f"{record.edition_id}, alan {field}",
                            file=sys.stderr,
                        )
        except Exception:
            # Kısmi göç kalıcıdır; kaldığı yeri bildir ki tekrar koşu ve elle
            # inceleme bu kayıttan başlayabilsin.
            print(
                f"HATA: {index}. kitapta durdu — kaynak Book.id={book['id']} "
                f"({book['title']!r})",
                file=sys.stderr,
            )
            raise
        if index % 250 == 0 or index == len(books):
            print(f"  {index}/{len(books)} kitap işlendi")

    print(
        f"Bitti: {editions} baskı, {copies} nüsha, {covers} kapak, "
        f"{created_shelves} yeni dolap."
    )
    print(f"Katalog durumu: {catalog.stats()}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prisma-db", type=Path, default=DEFAULT_PRISMA_DB)
    parser.add_argument("--dry-run", action="store_true", help="Yalnız oku ve raporla")
    parser.add_argument("--limit", type=int, default=None, help="İlk N kitapla sınırla")
    args = parser.parse_args()
    return migrate(args.prisma_db, dry_run=args.dry_run, limit=args.limit)


if __name__ == "__main__":
    raise SystemExit(main())
