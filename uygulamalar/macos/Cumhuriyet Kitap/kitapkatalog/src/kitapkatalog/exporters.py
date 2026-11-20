"""Streaming catalogue exports and local metadata imports.

The module deliberately depends only on the core catalogue and ``openpyxl``.
It never imports an OCR/model package, so exports stay usable on headless
machines and while workers are still processing another import job.
"""

from __future__ import annotations

import csv
import json
import os
import re
import shutil
import tempfile
import unicodedata
import xml.etree.ElementTree as ET
from collections.abc import Iterable, Iterator, Mapping
from contextlib import contextmanager, suppress
from dataclasses import dataclass
from datetime import UTC, date, datetime
from enum import StrEnum
from pathlib import Path
from typing import Any, TextIO

from openpyxl import Workbook
from openpyxl.cell import WriteOnlyCell
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import (
    UNKNOWN_VALUE,
    BookInput,
    ContributorInput,
    ContributorRole,
    CopyInput,
    IdentifierInput,
)


class ExportError(RuntimeError):
    """A catalogue export could not be completed atomically."""


class ImportFormatError(ValueError):
    """A local catalogue file does not contain supported records."""


class ExportFormat(StrEnum):
    XLSX = "xlsx"
    CSV = "csv"
    JSON = "json"
    JSONL = "jsonl"
    MARKDOWN = "markdown"


@dataclass(frozen=True, slots=True)
class ExportResult:
    path: Path
    format: ExportFormat
    records: int


@dataclass(frozen=True, slots=True)
class ImportResult:
    source: Path
    imported: int
    skipped: int
    errors: tuple[str, ...] = ()


BOOK_COLUMNS: tuple[tuple[str, str], ...] = (
    ("edition_id", "Kayıt No"),
    ("title", "Başlık"),
    ("subtitle", "Alt Başlık"),
    ("original_title", "Özgün Başlık"),
    ("authors", "Yazarlar"),
    ("other_contributors", "Diğer Katkıda Bulunanlar"),
    ("publisher", "Yayınevi"),
    ("imprint", "Marka"),
    ("series", "Seri"),
    ("volume", "Cilt"),
    ("language", "Dil"),
    ("category", "Kategori"),
    ("publication_place", "Basım Yeri"),
    ("publication_date", "Basım Tarihi"),
    ("edition_statement", "Baskı"),
    ("printing_number", "Basım Numarası"),
    ("printer", "Matbaa"),
    ("isbn13", "ISBN-13"),
    ("isbn10", "ISBN-10"),
    ("other_identifiers", "Diğer Tanımlayıcılar"),
    ("binding", "Cilt Türü"),
    ("page_count", "Sayfa Sayısı"),
    ("dimensions", "Boyutlar"),
    ("price_amount", "Fiyat"),
    ("currency", "Para Birimi"),
    ("blurb", "Tanıtım Yazısı"),
    ("awards", "Ödüller"),
    ("quotations", "Alıntılar"),
    ("review_status", "Durum"),
    ("copy_count", "Nüsha Sayısı"),
    ("locations", "Dolap"),
    ("inventory_codes", "Envanter Kodları"),
    ("front_path", "Ön Kapak"),
    ("front_inside_path", "Ön İç Kapak"),
    ("back_inside_path", "Arka İç Kapak"),
    ("back_path", "Arka Kapak"),
    ("created_at", "Oluşturulma"),
    ("updated_at", "Güncellenme"),
)

_EDITION_FIELDS = (
    "title",
    "subtitle",
    "original_title",
    "publisher",
    "imprint",
    "series",
    "volume",
    "language",
    "publication_place",
    "publication_date",
    "edition_statement",
    "printing_number",
    "printer",
    "binding",
    "page_count",
    "dimensions",
    "price_amount",
    "currency",
    "blurb",
    "awards",
    "quotations",
    "category",
    "review_status",
    "front_path",
    "front_inside_path",
    "back_inside_path",
    "back_path",
    "raw_ocr_text",
    "created_at",
    "updated_at",
)

# XLSX "Kitaplar" sayfası sütun genişlikleri (anahtar → karakter genişliği).
_XLSX_WIDTHS = {
    "edition_id": 9,
    "title": 36,
    "subtitle": 24,
    "original_title": 24,
    "authors": 28,
    "other_contributors": 24,
    "publisher": 20,
    "blurb": 48,
    "awards": 28,
    "quotations": 28,
    "isbn13": 15,
    "isbn10": 12,
    "other_identifiers": 20,
    "locations": 16,
    "inventory_codes": 20,
    "front_path": 32,
    "front_inside_path": 32,
    "back_inside_path": 32,
    "back_path": 32,
    "created_at": 19,
    "updated_at": 19,
}

_STATUS_LABELS = {
    "review": "İnceleme gerekli",
    "completed": "Tamamlandı",
}

_DANGEROUS_CELL_PREFIXES = ("=", "+", "-", "@", "\t", "\r", "\n")
_SAFE_FILE = re.compile(r"[^\w.-]+", re.UNICODE)


def protect_spreadsheet_value(value: Any) -> Any:
    """Neutralise formula injection while preserving typed non-string values."""

    if isinstance(value, str) and value.startswith(_DANGEROUS_CELL_PREFIXES):
        return f"'{value}"
    return value


# Friendly aliases used by callers and older integrations.
sanitize_spreadsheet_cell = protect_spreadsheet_value
formula_safe = protect_spreadsheet_value


def _json_default(value: object) -> str:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Path):
        return str(value)
    raise TypeError(f"{type(value).__name__} JSON'a dönüştürülemiyor")


def _part_path(target: Path) -> Path:
    return target.with_name(f"{target.name}.part")


@contextmanager
def _atomic_text(
    target: Path,
    *,
    encoding: str = "utf-8",
    newline: str | None = None,
) -> Iterator[TextIO]:
    target.parent.mkdir(parents=True, exist_ok=True)
    part = _part_path(target)
    part.unlink(missing_ok=True)
    handle: TextIO | None = None
    try:
        handle = part.open("w", encoding=encoding, newline=newline)
        yield handle
        handle.flush()
        os.fsync(handle.fileno())
        handle.close()
        handle = None
        part.replace(target)
    except BaseException:
        if handle is not None:
            handle.close()
        part.unlink(missing_ok=True)
        raise


def _as_database(value: Database | Catalog | str | Path) -> Database:
    if isinstance(value, Database):
        return value
    if isinstance(value, Catalog):
        return value.db
    return Database(value)


@contextmanager
def _snapshot_database(
    source: Database | Catalog | str | Path,
) -> Iterator[Database]:
    """Read a stable SQLite snapshot without blocking active workers."""

    database = _as_database(source)
    with tempfile.TemporaryDirectory(prefix="kitapkatalog-export-") as directory:
        snapshot_path = Path(directory) / "catalog.sqlite3"
        database.backup_to(snapshot_path)
        snapshot = Database(snapshot_path)
        try:
            yield snapshot
        finally:
            snapshot.close()


def _completed_clause(alias: str = "e") -> str:
    # Hand-entered records have no job item and are complete catalogue records.
    # Pipeline records are visible after reaching review/completed.
    return f"""
        (
            NOT EXISTS(SELECT 1 FROM job_item AS j0 WHERE j0.edition_id = {alias}.id)
            OR EXISTS(
                SELECT 1 FROM job_item AS j1
                WHERE j1.edition_id = {alias}.id
                  AND j1.stage IN ('review', 'completed')
            )
        )
    """


def _edition_rows(connection: Any, *, completed_only: bool) -> Iterator[Any]:
    where = f"WHERE {_completed_clause('e')}" if completed_only else ""
    cursor = connection.execute(
        f"""
        SELECT e.* FROM edition AS e
        {where}
        ORDER BY e.title COLLATE UNICODE_NOCASE, e.id
        """
    )
    while rows := cursor.fetchmany(250):
        yield from rows


def _related_rows(connection: Any, edition_id: int) -> dict[str, list[dict[str, Any]]]:
    contributors = [
        dict(row)
        for row in connection.execute(
            """
            SELECT c.display_name AS name, ec.role, ec.sort_order
            FROM edition_contributor AS ec
            JOIN contributor AS c ON c.id = ec.contributor_id
            WHERE ec.edition_id = ?
            ORDER BY ec.sort_order, c.display_name
            """,
            (edition_id,),
        )
    ]
    identifiers = [
        dict(row)
        for row in connection.execute(
            """
            SELECT scheme, value, normalized_value, source, confidence
            FROM identifier WHERE edition_id = ? ORDER BY scheme, value
            """,
            (edition_id,),
        )
    ]
    copies = [
        dict(row)
        for row in connection.execute(
            """
            SELECT id, inventory_code, source_fingerprint, location, notes, status
            FROM copy WHERE edition_id = ? ORDER BY id
            """,
            (edition_id,),
        )
    ]
    return {
        "contributors": contributors,
        "identifiers": identifiers,
        "copies": copies,
    }


def _book_document(connection: Any, row: Any) -> dict[str, Any]:
    document: dict[str, Any] = {
        "edition_id": int(row["id"]),
        "work_id": int(row["work_id"]),
    }
    document.update({name: row[name] for name in _EDITION_FIELDS})
    document.update(_related_rows(connection, int(row["id"])))
    return document


def _flat_book(document: Mapping[str, Any]) -> dict[str, Any]:
    contributors = list(document.get("contributors") or [])
    identifiers = list(document.get("identifiers") or [])
    authors = [
        str(item.get("name") or "")
        for item in contributors
        if str(item.get("role") or "") == ContributorRole.AUTHOR.value
    ]
    others = [
        f"{item.get('role')}: {item.get('name')}"
        for item in contributors
        if str(item.get("role") or "") != ContributorRole.AUTHOR.value
    ]

    def identifier(scheme: str) -> str:
        return next(
            (
                str(item.get("value") or "")
                for item in identifiers
                if str(item.get("scheme") or "").upper() == scheme
            ),
            "",
        )

    known = {"ISBN10", "ISBN13"}
    other_ids = [
        f"{item.get('scheme')}: {item.get('value')}"
        for item in identifiers
        if str(item.get("scheme") or "").upper() not in known
    ]
    copies = list(document.get("copies") or [])
    active_copies = [item for item in copies if item.get("status", "active") == "active"]
    locations = sorted(
        {str(item.get("location")) for item in active_copies if item.get("location")}
    )
    inventory_codes = [
        str(item.get("inventory_code"))
        for item in active_copies
        if item.get("inventory_code")
    ]
    return {
        **document,
        "authors": "; ".join(filter(None, authors)),
        "other_contributors": "; ".join(others),
        "isbn13": identifier("ISBN13"),
        "isbn10": identifier("ISBN10"),
        "other_identifiers": "; ".join(other_ids),
        "copy_count": len(active_copies),
        "locations": ", ".join(locations),
        "inventory_codes": "; ".join(inventory_codes),
    }


def _iter_documents(database: Database, *, completed_only: bool) -> Iterator[dict[str, Any]]:
    with database.read_connection(readonly=True) as connection:
        connection.execute("BEGIN")
        try:
            for row in _edition_rows(connection, completed_only=completed_only):
                yield _book_document(connection, row)
        finally:
            connection.rollback()


def _count_editions(database: Database, *, completed_only: bool) -> int:
    where = f"WHERE {_completed_clause('e')}" if completed_only else ""
    row = database.fetchone(f"SELECT COUNT(*) AS count FROM edition AS e {where}")
    return int(row["count"]) if row is not None else 0


def _write_header(sheet: Any, labels: Iterable[str]) -> None:
    cells: list[WriteOnlyCell] = []
    for label in labels:
        cell = WriteOnlyCell(sheet, value=label)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="24557A")
        cells.append(cell)
    sheet.append(cells)


class CatalogExporter:
    """Export a stable, completed-only catalogue snapshot."""

    def __init__(self, source: Database | Catalog | str | Path) -> None:
        self.database = _as_database(source)

    def export(
        self,
        destination: str | Path,
        *,
        format: ExportFormat | str | None = None,
        completed_only: bool = True,
    ) -> ExportResult:
        target = Path(destination).expanduser()
        selected = ExportFormat(format) if format else _format_from_path(target)
        method = {
            ExportFormat.XLSX: self.export_xlsx,
            ExportFormat.CSV: self.export_csv,
            ExportFormat.JSON: self.export_json,
            ExportFormat.JSONL: self.export_jsonl,
            ExportFormat.MARKDOWN: self.export_markdown,
        }[selected]
        return method(target, completed_only=completed_only)

    def export_csv(self, destination: str | Path, *, completed_only: bool = True) -> ExportResult:
        target = Path(destination)
        with _snapshot_database(self.database) as snapshot:
            records = _count_editions(snapshot, completed_only=completed_only)
            with _atomic_text(target, encoding="utf-8-sig", newline="") as handle:
                writer = csv.writer(handle, lineterminator="\n")
                writer.writerow(label for _, label in BOOK_COLUMNS)
                for document in _iter_documents(snapshot, completed_only=completed_only):
                    flat = _flat_book(document)
                    writer.writerow(
                        protect_spreadsheet_value(flat.get(key)) for key, _label in BOOK_COLUMNS
                    )
        return ExportResult(target, ExportFormat.CSV, records)

    def export_json(self, destination: str | Path, *, completed_only: bool = True) -> ExportResult:
        target = Path(destination)
        with _snapshot_database(self.database) as snapshot:
            records = _count_editions(snapshot, completed_only=completed_only)
            with _atomic_text(target) as handle:
                handle.write('{"schema_version":1,"exported_at":')
                json.dump(datetime.now(UTC).isoformat(), handle, ensure_ascii=False)
                handle.write(',"books":[')
                first = True
                for document in _iter_documents(snapshot, completed_only=completed_only):
                    if not first:
                        handle.write(",")
                    first = False
                    json.dump(
                        document,
                        handle,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        default=_json_default,
                    )
                handle.write("]}\n")
        return ExportResult(target, ExportFormat.JSON, records)

    def export_jsonl(self, destination: str | Path, *, completed_only: bool = True) -> ExportResult:
        target = Path(destination)
        with _snapshot_database(self.database) as snapshot:
            records = _count_editions(snapshot, completed_only=completed_only)
            with _atomic_text(target) as handle:
                for document in _iter_documents(snapshot, completed_only=completed_only):
                    json.dump(
                        document,
                        handle,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        default=_json_default,
                    )
                    handle.write("\n")
        return ExportResult(target, ExportFormat.JSONL, records)

    def export_xlsx(self, destination: str | Path, *, completed_only: bool = True) -> ExportResult:
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        part = _part_path(target)
        part.unlink(missing_ok=True)
        with _snapshot_database(self.database) as snapshot:
            records = _count_editions(snapshot, completed_only=completed_only)
            workbook = Workbook(write_only=True)
            try:
                self._populate_workbook(
                    workbook, snapshot, completed_only=completed_only, records=records
                )
                workbook.save(part)
                part.replace(target)
            except BaseException:
                for sheet in workbook.worksheets:
                    with suppress(OSError, ValueError):
                        sheet.close()
                part.unlink(missing_ok=True)
                raise
            finally:
                workbook.close()
        return ExportResult(target, ExportFormat.XLSX, records)

    @staticmethod
    def _populate_workbook(
        workbook: Workbook,
        database: Database,
        *,
        completed_only: bool,
        records: int,
    ) -> None:
        catalog = Catalog(database)
        summary = workbook.create_sheet("Özet")
        summary.column_dimensions["A"].width = 26
        summary.column_dimensions["B"].width = 24
        _write_header(summary, ("Alan", "Değer"))
        stats = catalog.stats()
        with database.read_connection(readonly=True) as connection:
            location_row = connection.execute(
                """
                SELECT COUNT(DISTINCT location) AS count FROM copy
                WHERE location IS NOT NULL AND location <> ''
                """
            ).fetchone()
            distinct_locations = int(location_row["count"]) if location_row else 0
        summary_rows = (
            ("Dışa aktarılan kitap", records),
            ("Toplam eser", stats["works"]),
            ("Toplam baskı", stats["editions"]),
            ("Toplam nüsha", stats["copies"]),
            ("İnceleme gereken", stats["review"]),
            ("Farklı kategori", len(catalog.distribution("category"))),
            ("Farklı dil", len(catalog.distribution("language"))),
            ("Farklı yayınevi", len(catalog.distribution("publisher"))),
            ("Farklı dolap", distinct_locations),
            ("Yalnız tamamlananlar", "Evet" if completed_only else "Hayır"),
            ("Dışa aktarım zamanı", datetime.now(UTC).replace(tzinfo=None)),
        )
        for row in summary_rows:
            summary.append([protect_spreadsheet_value(value) for value in row])

        books = workbook.create_sheet("Kitaplar")
        for index, (key, _label) in enumerate(BOOK_COLUMNS, start=1):
            books.column_dimensions[get_column_letter(index)].width = _XLSX_WIDTHS.get(key, 14)
        books.freeze_panes = "A2"
        books.auto_filter.ref = f"A1:{get_column_letter(len(BOOK_COLUMNS))}{records + 1}"
        _write_header(books, (label for _key, label in BOOK_COLUMNS))
        contributors = workbook.create_sheet("Katkıda Bulunanlar")
        contributors.freeze_panes = "A2"
        _write_header(contributors, ("Kayıt No", "Ad", "Rol", "Sıra"))
        identifiers = workbook.create_sheet("Tanımlayıcılar")
        identifiers.freeze_panes = "A2"
        _write_header(
            identifiers,
            ("Kayıt No", "Tür", "Değer", "Normalize Değer", "Kaynak", "Güven"),
        )
        copies_sheet = workbook.create_sheet("Nüshalar")
        copies_sheet.freeze_panes = "A2"
        for letter, width in (
            ("A", 9),
            ("B", 36),
            ("C", 9),
            ("D", 18),
            ("E", 16),
            ("F", 28),
            ("G", 34),
            ("H", 14),
        ):
            copies_sheet.column_dimensions[letter].width = width
        _write_header(
            copies_sheet,
            (
                "Kayıt No",
                "Başlık",
                "Nüsha No",
                "Envanter Kodu",
                "Dolap",
                "Not",
                "Kaynak Parmak İzi",
                "Nüsha Durumu",
            ),
        )

        with database.read_connection(readonly=True) as connection:
            connection.execute("BEGIN")
            try:
                for row in _edition_rows(connection, completed_only=completed_only):
                    document = _book_document(connection, row)
                    flat = _flat_book(document)
                    books.append(
                        [protect_spreadsheet_value(flat.get(key)) for key, _label in BOOK_COLUMNS]
                    )
                    edition_id = document["edition_id"]
                    for item in document["contributors"]:
                        contributors.append(
                            [
                                edition_id,
                                protect_spreadsheet_value(item.get("name")),
                                protect_spreadsheet_value(item.get("role")),
                                item.get("sort_order"),
                            ]
                        )
                    for item in document["identifiers"]:
                        identifiers.append(
                            [
                                edition_id,
                                protect_spreadsheet_value(item.get("scheme")),
                                protect_spreadsheet_value(item.get("value")),
                                protect_spreadsheet_value(item.get("normalized_value")),
                                protect_spreadsheet_value(item.get("source")),
                                item.get("confidence"),
                            ]
                        )
                    for copy_number, item in enumerate(document["copies"], start=1):
                        copies_sheet.append(
                            [
                                edition_id,
                                protect_spreadsheet_value(document.get("title")),
                                copy_number,
                                protect_spreadsheet_value(item.get("inventory_code")),
                                protect_spreadsheet_value(item.get("location")),
                                protect_spreadsheet_value(item.get("notes")),
                                protect_spreadsheet_value(item.get("source_fingerprint")),
                                "Aktif" if item.get("status", "active") == "active" else "Düşülmüş",
                            ]
                        )
            finally:
                connection.rollback()

        stats_sheet = workbook.create_sheet("İstatistik")
        stats_sheet.freeze_panes = "A2"
        for letter, width in (("A", 12), ("B", 28), ("C", 9), ("D", 9)):
            stats_sheet.column_dimensions[letter].width = width
        _write_header(stats_sheet, ("Grup", "Değer", "Adet", "%"))
        for column, group_label in (
            ("category", "Kategori"),
            ("language", "Dil"),
            ("publisher", "Yayınevi"),
            ("review_status", "Durum"),
        ):
            distribution = catalog.distribution(column)
            total = sum(count for _value, count in distribution) or 1
            for value, count in distribution:
                label = _STATUS_LABELS.get(value, value) if column == "review_status" else value
                stats_sheet.append(
                    [
                        group_label,
                        protect_spreadsheet_value(label),
                        count,
                        round(100 * count / total, 1),
                    ]
                )
        with database.read_connection(readonly=True) as connection:
            location_rows = connection.execute(
                """
                SELECT COALESCE(NULLIF(location, ''), '—') AS value,
                       COUNT(*) AS count
                FROM copy WHERE status = 'active' GROUP BY value
                ORDER BY count DESC, value COLLATE NOCASE
                """
            ).fetchall()
        location_total = sum(int(row["count"]) for row in location_rows) or 1
        for row in location_rows:
            stats_sheet.append(
                [
                    "Dolap",
                    protect_spreadsheet_value(row["value"]),
                    int(row["count"]),
                    round(100 * int(row["count"]) / location_total, 1),
                ]
            )

        details = workbook.create_sheet("Ayrıntılı Alanlar")
        _write_header(
            details,
            (
                "Kayıt No",
                "Alan",
                "Değer",
                "Durum",
                "Kullanıcı Kilidi",
                "Çözümleyici",
                "Güven",
                "Kapak",
                "Motor Kanıtı",
                "Güncellenme",
            ),
        )
        where = f"WHERE {_completed_clause('e')}" if completed_only else ""
        with database.read_connection(readonly=True) as connection:
            for row in connection.execute(
                f"""
                SELECT e.id AS edition_id, rf.field_path, rf.value, rf.status,
                       rf.user_locked, rf.resolver_version, rf.updated_at,
                       fo.confidence, fo.cover_role, fo.engine_evidence_json
                FROM resolved_field AS rf
                JOIN edition AS e ON e.id = rf.edition_id
                LEFT JOIN field_observation AS fo ON fo.id = rf.observation_id
                {where}
                ORDER BY e.id, rf.field_path
                """
            ):
                details.append(
                    [
                        row["edition_id"],
                        protect_spreadsheet_value(row["field_path"]),
                        protect_spreadsheet_value(row["value"]),
                        row["status"],
                        "Evet" if row["user_locked"] else "Hayır",
                        row["resolver_version"],
                        row["confidence"],
                        row["cover_role"],
                        row["engine_evidence_json"],
                        row["updated_at"],
                    ]
                )

        review = workbook.create_sheet("İnceleme Gerekenler")
        _write_header(
            review,
            (
                "Kayıt No",
                "Başlık",
                "Durum",
                "Ön Kapak",
                "Ön İç Kapak",
                "Arka İç Kapak",
                "Arka Kapak",
            ),
        )
        with database.read_connection(readonly=True) as connection:
            for row in connection.execute(
                f"""
                SELECT e.id, e.title, e.review_status,
                       e.front_path, e.front_inside_path,
                       e.back_inside_path, e.back_path
                FROM edition AS e
                WHERE e.review_status = 'review'
                  {"AND " + _completed_clause("e") if completed_only else ""}
                ORDER BY e.id
                """
            ):
                review.append(
                    [
                        row["id"],
                        protect_spreadsheet_value(row["title"]),
                        row["review_status"],
                        protect_spreadsheet_value(row["front_path"]),
                        protect_spreadsheet_value(row["front_inside_path"]),
                        protect_spreadsheet_value(row["back_inside_path"]),
                        protect_spreadsheet_value(row["back_path"]),
                    ]
                )

        errors = workbook.create_sheet("Hatalar")
        _write_header(
            errors,
            ("İş No", "Öğe No", "Çift Anahtarı", "Aşama", "Deneme", "Hata"),
        )
        with database.read_connection(readonly=True) as connection:
            for row in connection.execute(
                """
                SELECT job_id, id, pair_key, stage, retry_count, last_error
                FROM job_item
                WHERE stage IN ('failed', 'cancelled') OR last_error IS NOT NULL
                ORDER BY job_id, id
                """
            ):
                errors.append(
                    [
                        row["job_id"],
                        row["id"],
                        protect_spreadsheet_value(row["pair_key"]),
                        row["stage"],
                        row["retry_count"],
                        protect_spreadsheet_value(row["last_error"]),
                    ]
                )

    def export_markdown(
        self, destination: str | Path, *, completed_only: bool = True
    ) -> ExportResult:
        target = Path(destination)
        with _snapshot_database(self.database) as snapshot:
            records = _count_editions(snapshot, completed_only=completed_only)
            if target.suffix.casefold() in {".md", ".markdown"}:
                with _atomic_text(target) as handle:
                    for index, document in enumerate(
                        _iter_documents(snapshot, completed_only=completed_only)
                    ):
                        if index:
                            handle.write("\n---\n\n")
                        handle.write(_markdown_book(document))
                return ExportResult(target, ExportFormat.MARKDOWN, records)

            target.parent.mkdir(parents=True, exist_ok=True)
            staging = target.with_name(f"{target.name}.part")
            if staging.exists():
                shutil.rmtree(staging)
            staging.mkdir(parents=True)
            try:
                index_lines = ["# KitapKatalog\n\n"]
                for document in _iter_documents(snapshot, completed_only=completed_only):
                    filename = _markdown_filename(document)
                    note = staging / filename
                    note.write_text(_markdown_book(document), encoding="utf-8")
                    index_lines.append(
                        f"- [[{filename.removesuffix('.md')}|{document['title']}]]\n"
                    )
                (staging / "index.md").write_text("".join(index_lines), encoding="utf-8")
                if target.exists():
                    backup = target.with_name(f"{target.name}.old")
                    if backup.exists():
                        shutil.rmtree(backup)
                    target.replace(backup)
                    try:
                        staging.replace(target)
                    except BaseException:
                        backup.replace(target)
                        raise
                    else:
                        shutil.rmtree(backup)
                else:
                    staging.replace(target)
            except BaseException:
                if staging.exists():
                    shutil.rmtree(staging)
                raise
        return ExportResult(target, ExportFormat.MARKDOWN, records)


def _markdown_filename(document: Mapping[str, Any]) -> str:
    title = unicodedata.normalize("NFC", str(document.get("title") or UNKNOWN_VALUE))
    safe = _SAFE_FILE.sub("-", title).strip("-._")[:100] or "kitap"
    return f"{int(document['edition_id']):06d}-{safe}.md"


def _markdown_text(value: Any) -> str:
    if value in (None, ""):
        return UNKNOWN_VALUE
    return str(value).replace("\r\n", "\n").replace("\r", "\n").strip()


def _markdown_book(document: Mapping[str, Any]) -> str:
    flat = _flat_book(document)
    identifiers = ", ".join(
        f"{item.get('scheme')}: {item.get('value')}" for item in document.get("identifiers") or []
    )
    lines = [
        f"# {_markdown_text(document.get('title'))}\n\n",
        f"- **Alt başlık:** {_markdown_text(document.get('subtitle'))}\n",
        f"- **Yazar:** {_markdown_text(flat.get('authors'))}\n",
        f"- **Diğer katkıda bulunanlar:** {_markdown_text(flat.get('other_contributors'))}\n",
        f"- **Yayınevi:** {_markdown_text(document.get('publisher'))}\n",
        f"- **Seri / Cilt:** {_markdown_text(document.get('series'))} / "
        f"{_markdown_text(document.get('volume'))}\n",
        f"- **ISBN / Tanımlayıcı:** {_markdown_text(identifiers)}\n",
        f"- **Basım:** {_markdown_text(document.get('publication_place'))}, "
        f"{_markdown_text(document.get('publication_date'))}\n",
        f"- **Sayfa:** {_markdown_text(document.get('page_count'))}\n",
        f"- **Dil:** {_markdown_text(document.get('language'))}\n",
        f"- **Kategori:** {_markdown_text(document.get('category'))}\n",
        f"- **Baskı:** {_markdown_text(document.get('edition_statement'))}\n",
        f"- **Adet:** {_markdown_text(flat.get('copy_count'))}\n",
        f"- **Dolap:** {_markdown_text(flat.get('locations'))}\n",
        f"- **Durum:** {_markdown_text(document.get('review_status'))}\n",
        f"- **Ön kapak:** {_markdown_text(document.get('front_path'))}\n",
        f"- **Ön iç kapak:** {_markdown_text(document.get('front_inside_path'))}\n",
        f"- **Arka iç kapak:** {_markdown_text(document.get('back_inside_path'))}\n",
        f"- **Arka kapak:** {_markdown_text(document.get('back_path'))}\n",
    ]
    copies = list(document.get("copies") or [])
    if copies:
        lines.append("\n## Nüshalar\n\n")
        for copy_number, item in enumerate(copies, start=1):
            lines.append(
                f"{copy_number}. Dolap: {_markdown_text(item.get('location'))}"
                f" • Envanter: {_markdown_text(item.get('inventory_code'))}"
                f" • Durum: {'Aktif' if item.get('status', 'active') == 'active' else 'Düşülmüş'}"
                f" • Not: {_markdown_text(item.get('notes'))}\n"
            )
    if document.get("blurb"):
        lines.extend(("\n## Tanıtım yazısı\n\n", _markdown_text(document["blurb"]), "\n"))
    return "".join(lines)


def _format_from_path(path: Path) -> ExportFormat:
    suffix = path.suffix.casefold()
    mapping = {
        ".xlsx": ExportFormat.XLSX,
        ".csv": ExportFormat.CSV,
        ".json": ExportFormat.JSON,
        ".jsonl": ExportFormat.JSONL,
        ".ndjson": ExportFormat.JSONL,
        ".md": ExportFormat.MARKDOWN,
        ".markdown": ExportFormat.MARKDOWN,
    }
    if suffix not in mapping:
        raise ExportError("Çıktı biçimi uzantıdan anlaşılamadı; xlsx/csv/json/jsonl/md kullanın")
    return mapping[suffix]


def export_catalog(
    source: Database | Catalog | str | Path,
    destination: str | Path,
    *,
    format: ExportFormat | str | None = None,
    completed_only: bool = True,
) -> ExportResult:
    return CatalogExporter(source).export(destination, format=format, completed_only=completed_only)


_COLUMN_ALIASES: dict[str, tuple[str, ...]] = {
    "title": ("title", "başlık", "baslik", "kitap adı", "kitap adi"),
    "subtitle": ("subtitle", "alt başlık", "alt baslik"),
    "original_title": ("original_title", "özgün başlık", "ozgun baslik"),
    "publisher": ("publisher", "yayınevi", "yayinevi"),
    "imprint": ("imprint", "marka"),
    "series": ("series", "seri"),
    "volume": ("volume", "cilt"),
    "language": ("language", "dil"),
    "publication_place": ("publication_place", "basım yeri", "basim yeri"),
    "publication_date": ("publication_date", "basım tarihi", "basim tarihi"),
    "edition_statement": ("edition_statement", "baskı", "baski"),
    "printing_number": ("printing_number", "basım numarası", "basim numarasi"),
    "printer": ("printer", "matbaa"),
    "binding": ("binding", "cilt türü", "cilt turu"),
    "page_count": ("page_count", "sayfa sayısı", "sayfa sayisi"),
    "dimensions": ("dimensions", "boyutlar"),
    "price_amount": ("price_amount", "fiyat"),
    "currency": ("currency", "para birimi"),
    "blurb": ("blurb", "tanıtım yazısı", "tanitim yazisi"),
    "awards": ("awards", "ödüller", "oduller"),
    "quotations": ("quotations", "alıntılar", "alintilar"),
    "category": ("category", "kategori", "tür", "tur"),
    "authors": ("authors", "author", "yazar", "yazarlar"),
    "isbn13": ("isbn13", "isbn-13", "isbn 13"),
    "isbn10": ("isbn10", "isbn-10", "isbn 10"),
    "front_path": ("front_path", "ön kapak", "on kapak"),
    "front_inside_path": (
        "front_inside_path",
        "ön iç kapak",
        "on ic kapak",
        "ön kapağın içi",
    ),
    "back_inside_path": (
        "back_inside_path",
        "arka iç kapak",
        "arka ic kapak",
        "sondan bir önceki sayfa",
    ),
    "back_path": ("back_path", "arka kapak"),
}


def _normalise_key(value: str) -> str:
    return unicodedata.normalize("NFC", value).strip().casefold().replace("-", " ")


def _pick(row: Mapping[str, Any], field: str) -> Any:
    normalized = {_normalise_key(str(key)): value for key, value in row.items()}
    for alias in _COLUMN_ALIASES.get(field, (field,)):
        candidate = normalized.get(_normalise_key(alias))
        if candidate not in (None, ""):
            return _restore_formula_guard(candidate)
    return None


def _restore_formula_guard(value: Any) -> Any:
    if (
        isinstance(value, str)
        and len(value) > 1
        and value.startswith("'")
        and value[1:].startswith(_DANGEROUS_CELL_PREFIXES)
    ):
        return value[1:]
    return value


def _book_from_mapping(
    row: Mapping[str, Any],
) -> tuple[BookInput, str | None, str | None, str | None, str | None]:
    contributors: list[ContributorInput] = []
    nested = row.get("contributors")
    if isinstance(nested, list):
        for index, item in enumerate(nested):
            if isinstance(item, Mapping) and item.get("name"):
                contributors.append(
                    ContributorInput(
                        name=str(item["name"]),
                        role=str(item.get("role") or ContributorRole.AUTHOR.value),
                        sort_order=int(item.get("sort_order") or index),
                    )
                )
    else:
        authors = _pick(row, "authors")
        if authors:
            for index, name in enumerate(re.split(r"\s*[;|]\s*", str(authors))):
                if name:
                    contributors.append(ContributorInput(name=name, sort_order=index))

    identifiers: list[IdentifierInput] = []
    nested_ids = row.get("identifiers")
    if isinstance(nested_ids, list):
        for item in nested_ids:
            if isinstance(item, Mapping) and item.get("scheme") and item.get("value"):
                identifiers.append(
                    IdentifierInput(
                        scheme=str(item["scheme"]),
                        value=str(item["value"]),
                        source=str(item.get("source") or "local_import"),
                        confidence=(
                            float(item["confidence"])
                            if item.get("confidence") not in (None, "")
                            else None
                        ),
                    )
                )
    else:
        for field, scheme in (("isbn13", "ISBN13"), ("isbn10", "ISBN10")):
            if value := _pick(row, field):
                identifiers.append(
                    IdentifierInput(scheme=scheme, value=str(value), source="local_import")
                )

    values: dict[str, Any] = {}
    for field in _EDITION_FIELDS:
        if field in {
            "review_status",
            "front_path",
            "front_inside_path",
            "back_inside_path",
            "back_path",
            "raw_ocr_text",
            "created_at",
            "updated_at",
        }:
            continue
        value = row.get(field) if field in row else _pick(row, field)
        if value not in (None, ""):
            values[field] = value
    if "page_count" in values:
        values["page_count"] = int(values["page_count"])
    values["title"] = str(values.get("title") or UNKNOWN_VALUE)
    values["contributors"] = tuple(contributors)
    values["identifiers"] = tuple(identifiers)
    copy_data = row.get("copy")
    if isinstance(copy_data, Mapping):
        values["copy"] = CopyInput(
            inventory_code=_optional_text(copy_data.get("inventory_code")),
            source_fingerprint=_optional_text(copy_data.get("source_fingerprint")),
            location=_optional_text(copy_data.get("location")),
            notes=_optional_text(copy_data.get("notes")),
        )
    return (
        BookInput(**values),
        _optional_text(row.get("front_path") or _pick(row, "front_path")),
        _optional_text(row.get("front_inside_path") or _pick(row, "front_inside_path")),
        _optional_text(row.get("back_inside_path") or _pick(row, "back_inside_path")),
        _optional_text(row.get("back_path") or _pick(row, "back_path")),
    )


def _optional_text(value: Any) -> str | None:
    return str(value).strip() if value not in (None, "") else None


def _iter_import_rows(source: Path) -> Iterator[Mapping[str, Any]]:
    suffix = source.suffix.casefold()
    if suffix == ".csv":
        with source.open("r", encoding="utf-8-sig", newline="") as handle:
            yield from csv.DictReader(handle)
        return
    if suffix in {".jsonl", ".ndjson"}:
        with source.open("r", encoding="utf-8") as handle:
            for line_number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                value = json.loads(line)
                if not isinstance(value, Mapping):
                    raise ImportFormatError(f"JSONL satırı nesne değil: {line_number}")
                yield value
        return
    if suffix == ".json":
        with source.open("r", encoding="utf-8-sig") as handle:
            value = json.load(handle)
        if isinstance(value, Mapping):
            value = value.get("books", value.get("records"))
        if not isinstance(value, list):
            raise ImportFormatError("JSON kökünde books/records listesi bulunamadı")
        for index, item in enumerate(value, 1):
            if not isinstance(item, Mapping):
                raise ImportFormatError(f"JSON kaydı nesne değil: {index}")
            yield item
        return
    if suffix == ".xml":
        yield from _iter_onix_rows(source)
        return
    raise ImportFormatError(
        "Yerel içe aktarım yalnız CSV, JSON, JSONL ve güvenli ONIX XML destekler"
    )


def _reject_unsafe_xml(source: Path) -> None:
    """Reject DTD/entity declarations before ElementTree sees the document."""

    needles = (b"<!DOCTYPE", b"<!ENTITY")
    tail = b""
    with source.open("rb") as handle:
        while block := handle.read(64 * 1024):
            candidate = (tail + block).upper()
            if any(needle in candidate for needle in needles):
                raise ImportFormatError("ONIX XML güvenlik nedeniyle DOCTYPE/ENTITY içeremez")
            tail = candidate[-32:]


def _local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1].casefold()


def _descendants(element: ET.Element, name: str) -> Iterator[ET.Element]:
    wanted = name.casefold()
    for child in element.iter():
        if _local_name(child.tag) == wanted:
            yield child


def _first_text(element: ET.Element, *names: str) -> str | None:
    for name in names:
        for child in _descendants(element, name):
            if child.text and child.text.strip():
                return unicodedata.normalize("NFC", child.text).strip()
    return None


def _child_text(element: ET.Element, name: str) -> str | None:
    wanted = name.casefold()
    for child in element:
        if _local_name(child.tag) == wanted and child.text and child.text.strip():
            return unicodedata.normalize("NFC", child.text).strip()
    return None


def _onix_product(product: ET.Element) -> dict[str, Any]:
    title = _first_text(product, "TitleText", "titletext") or UNKNOWN_VALUE
    subtitle = _first_text(product, "Subtitle", "subtitle")
    publisher = _first_text(product, "PublisherName", "publishername")
    language = _first_text(product, "LanguageCode", "languagecode")
    publication_date = _first_text(product, "Date", "publicationdate")

    contributors: list[dict[str, Any]] = []
    role_map = {
        "A01": ContributorRole.AUTHOR.value,
        "A02": ContributorRole.AUTHOR.value,
        "A12": ContributorRole.ILLUSTRATOR.value,
        "B01": ContributorRole.EDITOR.value,
        "B06": ContributorRole.TRANSLATOR.value,
    }
    for index, contributor in enumerate(_descendants(product, "Contributor")):
        role_code = _first_text(contributor, "ContributorRole") or "A01"
        name = _first_text(contributor, "PersonName", "PersonNameInverted", "CorporateName")
        if not name:
            before = _first_text(contributor, "NamesBeforeKey") or ""
            key = _first_text(contributor, "KeyNames") or ""
            name = " ".join(part for part in (before, key) if part)
        if name:
            contributors.append(
                {
                    "name": name,
                    "role": role_map.get(role_code, ContributorRole.OTHER.value),
                    "sort_order": index,
                }
            )

    identifiers: list[dict[str, Any]] = []
    scheme_map = {"15": "ISBN13", "02": "ISBN10", "03": "GTIN13"}
    for identifier in _descendants(product, "ProductIdentifier"):
        scheme_code = _child_text(identifier, "ProductIDType")
        value = _child_text(identifier, "IDValue")
        if scheme_code and value:
            identifiers.append(
                {
                    "scheme": scheme_map.get(scheme_code, f"ONIX-{scheme_code}"),
                    "value": value,
                    "source": "onix_local",
                }
            )

    return {
        "title": title,
        "subtitle": subtitle,
        "publisher": publisher,
        "language": language,
        "publication_date": publication_date,
        "contributors": contributors,
        "identifiers": identifiers,
    }


def _iter_onix_rows(source: Path) -> Iterator[Mapping[str, Any]]:
    _reject_unsafe_xml(source)
    try:
        for _event, element in ET.iterparse(source, events=("end",)):
            if _local_name(element.tag) == "product":
                yield _onix_product(element)
                element.clear()
    except ET.ParseError as exc:
        raise ImportFormatError(f"ONIX XML ayrıştırılamadı: {exc}") from exc


def import_local_catalog(
    source: str | Path,
    catalog: Catalog | Database | str | Path,
    *,
    continue_on_error: bool = True,
) -> ImportResult:
    path = Path(source).expanduser()
    if not path.is_file():
        raise FileNotFoundError(path)
    destination = catalog if isinstance(catalog, Catalog) else Catalog(catalog)
    imported = 0
    skipped = 0
    errors: list[str] = []
    for index, row in enumerate(_iter_import_rows(path), 1):
        try:
            book, front, front_inside, back_inside, back = _book_from_mapping(row)
            record = destination.save_book(book, add_copy=book.copy is not None)
            if front or front_inside or back_inside or back:
                destination.set_cover_paths(
                    record.edition_id,
                    front_path=front,
                    front_inside_path=front_inside,
                    back_inside_path=back_inside,
                    back_path=back,
                )
            imported += 1
        except (TypeError, ValueError, KeyError) as exc:
            skipped += 1
            errors.append(f"Kayıt {index}: {exc}")
            if not continue_on_error:
                raise ImportFormatError(errors[-1]) from exc
    return ImportResult(path, imported, skipped, tuple(errors))


import_catalog = import_local_catalog


__all__ = [
    "BOOK_COLUMNS",
    "CatalogExporter",
    "ExportError",
    "ExportFormat",
    "ExportResult",
    "ImportFormatError",
    "ImportResult",
    "export_catalog",
    "formula_safe",
    "import_catalog",
    "import_local_catalog",
    "protect_spreadsheet_value",
    "sanitize_spreadsheet_cell",
]
