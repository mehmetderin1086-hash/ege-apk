"""High-level catalogue CRUD, de-duplication and full-text search."""

from __future__ import annotations

import json
import re
import sqlite3
import unicodedata
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, ClassVar

from kitapkatalog.database import Database, DatabaseError, StateConflictError
from kitapkatalog.domain import (
    UNKNOWN_VALUE,
    BookInput,
    BookRecord,
    ContributorInput,
    ContributorRole,
    CopyInput,
    CopyRecord,
    FieldObservation,
    FieldStatus,
    IdentifierInput,
    SearchFilters,
    SearchPage,
)
from kitapkatalog.isbn import (
    is_valid_isbn10,
    is_valid_isbn13,
    isbn10_check_digit,
    isbn10_to_isbn13,
)

# SearchFilters.missing değerleri → SQL koşulu (İstenen alanı boş olan baskılar).
_MISSING_FILTERS = {
    "isbn": (
        """
        NOT EXISTS(
            SELECT 1 FROM identifier AS mi
            WHERE mi.edition_id = e.id AND mi.scheme IN ('ISBN10', 'ISBN13')
        )
        """
    ),
    "cover": (
        "(e.front_path IS NULL OR e.front_path = '' OR e.back_path IS NULL OR e.back_path = '')"
    ),
    "category": "(e.category IS NULL OR e.category = '')",
    "language": "(e.language IS NULL OR e.language = '')",
    "publisher": "(e.publisher IS NULL OR e.publisher = '')",
    "publication_date": "(e.publication_date IS NULL OR e.publication_date = '')",
    "page_count": "(e.page_count IS NULL OR e.page_count = 0)",
}

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
)
_EDITABLE_FIELDS = frozenset(
    (
        *_EDITION_FIELDS,
        "review_status",
        "front_path",
        "front_inside_path",
        "back_inside_path",
        "back_path",
    )
)
# Liste ve arama sonuçları BookRecord'ın bütün kullanıcı alanlarını korur;
# ayrıntı ekranına özgü büyük OCR gövdesini ve iç kimlik sütunlarını taşımaz.
# ``NULL AS raw_ocr_text`` aynı assembler'ı güvenle yeniden kullanmamızı sağlar
# ve SQLite'ın gerçek ``edition.raw_ocr_text`` sayfalarına dokunmasını önler.
_LIST_EDITION_COLUMNS = """
    e.id,
    e.work_id,
    e.title,
    e.subtitle,
    e.original_title,
    e.publisher,
    e.imprint,
    e.series,
    e.volume,
    e.language,
    e.publication_place,
    e.publication_date,
    e.edition_statement,
    e.printing_number,
    e.printer,
    e.binding,
    e.page_count,
    e.dimensions,
    e.price_amount,
    e.currency,
    e.blurb,
    e.awards,
    e.quotations,
    e.review_status,
    e.category,
    e.front_path,
    e.front_inside_path,
    e.back_inside_path,
    e.back_path,
    NULL AS raw_ocr_text,
    e.created_at,
    e.updated_at
"""
_ISBN_SCHEMES = frozenset({"ISBN", "ISBN10", "ISBN13"})
_FTS_TERM = re.compile(r"\w+", re.UNICODE)
_FIELD_STATUS_STRENGTH = {
    FieldStatus.UNRESOLVED: 0,
    FieldStatus.REVIEW: 1,
    FieldStatus.AUTO: 2,
    FieldStatus.CONFIRMED: 3,
}


def _canonical_resolved_field_path(field_path: str) -> str:
    """Use one taxonomy while accepting rows written by older releases."""

    normalized = str(field_path).strip()
    if normalized.startswith("edition."):
        column = normalized.removeprefix("edition.")
        return f"edition.{column}" if column in _EDITABLE_FIELDS else normalized
    if normalized in _EDITABLE_FIELDS:
        return f"edition.{normalized}"
    return normalized


def _resolved_field_aliases(field_path: str) -> tuple[str, ...]:
    canonical = _canonical_resolved_field_path(field_path)
    if canonical.startswith("edition."):
        column = canonical.removeprefix("edition.")
        if column in _EDITABLE_FIELDS:
            return canonical, column
    return (canonical,)


class IdentifierConflictError(DatabaseError):
    """Identifiers from one input point at multiple existing editions."""


class LockedFieldError(DatabaseError):
    """A machine update attempted to replace a user-confirmed value."""


class InsufficientEvidenceError(DatabaseError):
    """An automatic value did not meet the fail-closed evidence gate."""


class Catalog:
    def __init__(self, database: Database | str | Path) -> None:
        self.db = database if isinstance(database, Database) else Database(database)

    def save_book(
        self,
        book: BookInput,
        *,
        source_fingerprint: str | None = None,
        add_copy: bool = True,
        overwrite: bool = False,
    ) -> BookRecord:
        """Create or idempotently merge an edition.

        A valid ISBN identifies an edition, while each distinct source
        fingerprint/inventory code identifies a physical copy.  Thus two cover
        pairs with the same ISBN create one edition and two copies.
        """

        identifiers = _prepare_identifiers(book.identifiers)
        source_fingerprint = source_fingerprint or (
            book.copy.source_fingerprint if book.copy is not None else None
        )
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            edition_id = self._locate_edition(connection, identifiers, source_fingerprint)
            if edition_id is None:
                title = _clean_value(book.title) or UNKNOWN_VALUE
                work_id = int(
                    connection.execute(
                        """
                        INSERT INTO work(
                            canonical_title, original_title, created_at, updated_at
                        ) VALUES (?, ?, ?, ?)
                        """,
                        (title, _clean_value(book.original_title), now, now),
                    ).lastrowid
                )
                values = [
                    (title if name == "title" else _normalise_field(name, getattr(book, name)))
                    for name in _EDITION_FIELDS
                ]
                placeholders = ", ".join("?" for _ in values)
                edition_id = int(
                    connection.execute(
                        f"""
                        INSERT INTO edition(
                            work_id, {", ".join(_EDITION_FIELDS)},
                            source_fingerprint, created_at, updated_at
                        ) VALUES (?, {placeholders}, ?, ?, ?)
                        """,
                        (work_id, *values, source_fingerprint, now, now),
                    ).lastrowid
                )
            else:
                self._merge_edition(connection, edition_id, book, overwrite=overwrite, now=now)

            self._save_contributors(
                connection,
                edition_id,
                book.contributors,
                replace=(
                    overwrite and not self._field_is_locked(connection, edition_id, "contributors")
                ),
                skip=self._field_is_locked(connection, edition_id, "contributors"),
            )
            if not self._field_is_locked(connection, edition_id, "identifiers"):
                self._save_identifiers(connection, edition_id, identifiers, now)

            if add_copy:
                copy_input = book.copy or CopyInput(source_fingerprint=source_fingerprint)
                self._add_copy(connection, edition_id, copy_input, now)

            self._refresh_search_document(connection, edition_id)

        record = self.get_book(edition_id)
        assert record is not None
        return record

    # Common names used by integrations.
    create_book = save_book
    upsert_book = save_book

    @staticmethod
    def _locate_edition(
        connection: sqlite3.Connection,
        identifiers: Sequence[tuple[IdentifierInput, str, str]],
        source_fingerprint: str | None,
    ) -> int | None:
        ids: set[int] = set()
        for _identifier, scheme, normalized in identifiers:
            if scheme not in _ISBN_SCHEMES:
                continue
            row = connection.execute(
                """
                SELECT edition_id FROM identifier
                WHERE scheme = ? AND normalized_value = ?
                """,
                (scheme, normalized),
            ).fetchone()
            if row is not None:
                ids.add(int(row["edition_id"]))
        if source_fingerprint:
            row = connection.execute(
                """
                SELECT id AS edition_id FROM edition WHERE source_fingerprint = ?
                UNION
                SELECT edition_id FROM copy WHERE source_fingerprint = ?
                """,
                (source_fingerprint, source_fingerprint),
            ).fetchone()
            if row is not None:
                ids.add(int(row["edition_id"]))
        if len(ids) > 1:
            raise IdentifierConflictError(
                "Aynı kayıt içindeki ISBN/kapak kimlikleri farklı baskılara bağlı"
            )
        return next(iter(ids), None)

    @staticmethod
    def _merge_edition(
        connection: sqlite3.Connection,
        edition_id: int,
        book: BookInput,
        *,
        overwrite: bool,
        now: str,
    ) -> None:
        existing = connection.execute(
            "SELECT * FROM edition WHERE id = ?", (edition_id,)
        ).fetchone()
        if existing is None:
            raise KeyError(f"Baskı bulunamadı: {edition_id}")
        locked = {
            row["field_path"].removeprefix("edition.")
            for row in connection.execute(
                """
                SELECT field_path FROM resolved_field
                WHERE edition_id = ? AND user_locked = 1
                """,
                (edition_id,),
            )
        }
        updates: dict[str, Any] = {}
        for field_name in _EDITION_FIELDS:
            incoming = _normalise_field(field_name, getattr(book, field_name))
            if incoming in (None, "") or field_name in locked:
                continue
            current = existing[field_name]
            if overwrite or current in (None, "", UNKNOWN_VALUE):
                updates[field_name] = incoming
        if updates:
            assignments = ", ".join(f"{name} = ?" for name in updates)
            connection.execute(
                f"UPDATE edition SET {assignments}, updated_at = ? WHERE id = ?",
                (*updates.values(), now, edition_id),
            )
            if "title" in updates or "original_title" in updates:
                connection.execute(
                    """
                    UPDATE work SET
                        canonical_title = CASE WHEN ? IS NULL THEN canonical_title ELSE ? END,
                        original_title = CASE WHEN ? IS NULL THEN original_title ELSE ? END,
                        updated_at = ?
                    WHERE id = (SELECT work_id FROM edition WHERE id = ?)
                    """,
                    (
                        updates.get("title"),
                        updates.get("title"),
                        updates.get("original_title"),
                        updates.get("original_title"),
                        now,
                        edition_id,
                    ),
                )

    @staticmethod
    def _save_contributors(
        connection: sqlite3.Connection,
        edition_id: int,
        contributors: Sequence[ContributorInput],
        *,
        replace: bool,
        skip: bool = False,
    ) -> None:
        if skip:
            return
        if replace and contributors:
            connection.execute(
                "DELETE FROM edition_contributor WHERE edition_id = ?", (edition_id,)
            )
        for position, contributor in enumerate(contributors):
            display_name = _clean_value(contributor.name)
            if not display_name:
                continue
            normalized_name = unicodedata.normalize("NFC", display_name).casefold()
            connection.execute(
                """
                INSERT INTO contributor(display_name, normalized_name)
                VALUES (?, ?)
                ON CONFLICT(normalized_name) DO UPDATE SET
                    display_name = CASE
                        WHEN length(excluded.display_name) > length(contributor.display_name)
                        THEN excluded.display_name ELSE contributor.display_name
                    END
                """,
                (display_name, normalized_name),
            )
            row = connection.execute(
                "SELECT id FROM contributor WHERE normalized_name = ?",
                (normalized_name,),
            ).fetchone()
            assert row is not None
            role = (
                contributor.role.value
                if isinstance(contributor.role, ContributorRole)
                else str(contributor.role).strip().casefold() or ContributorRole.OTHER.value
            )
            connection.execute(
                """
                INSERT INTO edition_contributor(
                    edition_id, contributor_id, role, sort_order
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(edition_id, contributor_id, role) DO UPDATE SET
                    sort_order = excluded.sort_order
                """,
                (
                    edition_id,
                    row["id"],
                    role,
                    contributor.sort_order if contributor.sort_order else position,
                ),
            )

    @staticmethod
    def _field_is_locked(connection: sqlite3.Connection, edition_id: int, field_path: str) -> bool:
        aliases = _resolved_field_aliases(field_path)
        canonical_path = aliases[0]
        legacy_path = aliases[-1]
        return (
            connection.execute(
                """
                SELECT 1 FROM resolved_field
                WHERE edition_id = ? AND user_locked = 1
                  AND field_path IN (?, ?)
                """,
                (edition_id, canonical_path, legacy_path),
            ).fetchone()
            is not None
        )

    @staticmethod
    def _save_identifiers(
        connection: sqlite3.Connection,
        edition_id: int,
        identifiers: Sequence[tuple[IdentifierInput, str, str]],
        now: str,
    ) -> None:
        for identifier, scheme, normalized in identifiers:
            existing = connection.execute(
                """
                SELECT edition_id FROM identifier
                WHERE scheme = ? AND normalized_value = ?
                """,
                (scheme, normalized),
            ).fetchone()
            if existing is not None and int(existing["edition_id"]) != edition_id:
                raise IdentifierConflictError(f"{scheme} {normalized} başka bir baskıya kayıtlı")
            connection.execute(
                """
                INSERT INTO identifier(
                    edition_id, scheme, value, normalized_value, source,
                    confidence, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(scheme, normalized_value) DO UPDATE SET
                    value = excluded.value,
                    source = excluded.source,
                    confidence = CASE
                        WHEN identifier.confidence IS NULL THEN excluded.confidence
                        WHEN excluded.confidence IS NULL THEN identifier.confidence
                        ELSE MAX(identifier.confidence, excluded.confidence)
                    END
                """,
                (
                    edition_id,
                    scheme,
                    identifier.value.strip(),
                    normalized,
                    identifier.source,
                    identifier.confidence,
                    now,
                ),
            )

    @staticmethod
    def _add_copy(
        connection: sqlite3.Connection,
        edition_id: int,
        copy_input: CopyInput,
        now: str,
    ) -> int:
        inventory_code = _clean_value(copy_input.inventory_code)
        fingerprint = _clean_value(copy_input.source_fingerprint)
        if inventory_code:
            existing = connection.execute(
                "SELECT id, edition_id FROM copy WHERE inventory_code = ?",
                (inventory_code,),
            ).fetchone()
        elif fingerprint:
            existing = connection.execute(
                "SELECT id, edition_id FROM copy WHERE source_fingerprint = ?",
                (fingerprint,),
            ).fetchone()
        else:
            existing = None
        if existing is not None:
            if int(existing["edition_id"]) != edition_id:
                raise IdentifierConflictError("Nüsha kimliği başka bir baskıya bağlı")
            connection.execute(
                """
                UPDATE copy SET
                    location = COALESCE(?, location),
                    notes = COALESCE(?, notes),
                    acquisition_method = COALESCE(?, acquisition_method),
                    acquisition_date = COALESCE(?, acquisition_date),
                    acquisition_price = COALESCE(?, acquisition_price),
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    _clean_value(copy_input.location),
                    _clean_value(copy_input.notes),
                    _clean_value(copy_input.acquisition_method),
                    _clean_value(copy_input.acquisition_date),
                    _clean_value(copy_input.acquisition_price),
                    now,
                    existing["id"],
                ),
            )
            return int(existing["id"])
        return int(
            connection.execute(
                """
                INSERT INTO copy(
                    edition_id, inventory_code, source_fingerprint, location,
                    notes, acquisition_method, acquisition_date, acquisition_price,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    edition_id,
                    inventory_code,
                    fingerprint,
                    _clean_value(copy_input.location),
                    _clean_value(copy_input.notes),
                    _clean_value(copy_input.acquisition_method),
                    _clean_value(copy_input.acquisition_date),
                    _clean_value(copy_input.acquisition_price),
                    now,
                    now,
                ),
            ).lastrowid
        )

    def add_copy(self, edition_id: int, copy_input: CopyInput | None = None) -> int:
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            return self._add_copy(connection, edition_id, copy_input or CopyInput(), now)

    def get_book(self, edition_id: int) -> BookRecord | None:
        with self.db.connection(readonly=True) as connection:
            row = connection.execute("SELECT * FROM edition WHERE id = ?", (edition_id,)).fetchone()
            if row is None:
                return None
            return self._record_from_row(connection, row)

    def get_by_identifier(self, scheme: str, value: str) -> BookRecord | None:
        normalized_scheme, normalized_value = normalise_identifier(scheme, value)
        row = self.db.fetchone(
            """
            SELECT edition_id FROM identifier
            WHERE scheme = ? AND normalized_value = ?
            """,
            (normalized_scheme, normalized_value),
        )
        return self.get_book(int(row["edition_id"])) if row is not None else None

    def list_books(
        self,
        *,
        limit: int = 100,
        offset: int = 0,
        review_status: str | None = None,
    ) -> list[BookRecord]:
        where = ""
        parameters: list[Any] = []
        if review_status:
            where = "WHERE review_status = ?"
            parameters.append(review_status)
        parameters.extend((max(1, min(int(limit), 10_000)), max(0, int(offset))))
        with self.db.connection(readonly=True) as connection:
            id_rows = connection.execute(
                f"""
                SELECT id FROM edition {where}
                ORDER BY title COLLATE NOCASE, id LIMIT ? OFFSET ?
                """,
                parameters,
            ).fetchall()
            return self._records_for_list_ids(
                connection, [int(row["id"]) for row in id_rows]
            )

    def list_distinct_values(self, column: str) -> list[str]:
        """Form önerileri için ayrık değerler (kategori/dil/yayınevi/dolap)."""

        if column == "location":
            rows = self.db.fetchall(
                """
                SELECT DISTINCT location AS value FROM copy
                WHERE status = 'active' AND location IS NOT NULL AND location <> ''
                ORDER BY value COLLATE NOCASE
                """
            )
            return [str(row["value"]) for row in rows]
        if column == "author":
            rows = self.db.fetchall(
                """
                SELECT DISTINCT c.display_name AS value
                FROM edition_contributor AS ec
                JOIN contributor AS c ON c.id = ec.contributor_id
                WHERE ec.role = 'author'
                ORDER BY value COLLATE NOCASE
                """
            )
            return [str(row["value"]) for row in rows]
        # Publisher joins the list because retyping it per book is how a
        # catalogue ends up with three spellings of the same imprint.
        if column not in {"category", "language", "publisher"}:
            raise ValueError(f"Desteklenmeyen sütun: {column}")
        rows = self.db.fetchall(
            f"""
            SELECT DISTINCT {column} AS value FROM edition
            WHERE {column} IS NOT NULL AND {column} <> ''
            ORDER BY value COLLATE NOCASE
            """
        )
        return [str(row["value"]) for row in rows]

    def top_contributors(self, *, role: str = "author", limit: int = 40) -> list[str]:
        """Katalogda en sık geçen katkı sağlayanlar (ses istemi biasing için)."""

        rows = self.db.fetchall(
            """
            SELECT c.display_name AS value, COUNT(*) AS occurrences
            FROM edition_contributor AS ec
            JOIN contributor AS c ON c.id = ec.contributor_id
            WHERE ec.role = ?
            GROUP BY c.id
            ORDER BY occurrences DESC, value COLLATE NOCASE
            LIMIT ?
            """,
            (role, max(1, min(int(limit), 500))),
        )
        return [str(row["value"]) for row in rows]

    # Sıralama beyaz listesi: ORDER BY'a yalnız buradaki sabitler girer.
    # "relevance" = mevcut varsayılan (sorgu varsa bm25, yoksa başlık).
    _SORTS: ClassVar[dict[str, str | None]] = {
        "relevance": None,
        "title": "e.title COLLATE NOCASE, e.id",
        # Bozuk/serbest metin tarihler ("birinci baskı") sona atılır; yalnız
        # YYYY ile başlayanlar yıla göre sıralanır.
        "year": (
            "CASE WHEN e.publication_date GLOB '[0-9][0-9][0-9][0-9]*' "
            "THEN 0 ELSE 1 END, substr(e.publication_date, 1, 4) DESC, e.id"
        ),
        "created": "e.created_at DESC, e.id",
        "popular": (
            "(SELECT COUNT(*) FROM loan WHERE loan.edition_id = e.id) DESC, "
            "e.title COLLATE NOCASE, e.id"
        ),
    }

    @staticmethod
    def _available_sql(location_scoped: bool) -> str:
        """Ödünçte olmayan aktif nüsha VAR; konum filtresiyle birlikte
        kullanılınca aynı nüsha kümesi üzerinden değerlendirilir (aksi hâlde
        'Dolap A + rafta' filtresi, başka dolaptaki müsait nüshayla sağlanırdı)."""

        scope = " AND ac.location = ?" if location_scoped else ""
        return f"""
        EXISTS(
            SELECT 1 FROM copy AS ac
            WHERE ac.edition_id = e.id AND ac.status = 'active'{scope} AND NOT EXISTS(
                SELECT 1 FROM loan
                WHERE loan.copy_id = ac.id AND loan.returned_at IS NULL
            )
        )
        """

    def search(
        self,
        query: str = "",
        *,
        filters: SearchFilters | None = None,
        limit: int = 50,
        offset: int = 0,
        sort: str = "relevance",
    ) -> SearchPage:
        filters = filters or SearchFilters()
        if sort not in self._SORTS:
            raise ValueError(f"Desteklenmeyen sıralama: {sort}")
        limit = max(1, min(int(limit), 1000))
        offset = max(0, int(offset))
        fts_query = _make_fts_query(query)
        where: list[str] = []
        parameters: list[Any] = []
        if fts_query:
            source = "edition AS e JOIN edition_fts AS f ON f.rowid = e.id"
            where.append("edition_fts MATCH ?")
            parameters.append(fts_query)
        else:
            source = "edition AS e"
        if filters.publisher:
            where.append("e.publisher = ? COLLATE UNICODE_NOCASE")
            parameters.append(filters.publisher)
        if filters.language:
            where.append("e.language = ? COLLATE UNICODE_NOCASE")
            parameters.append(filters.language)
        if filters.review_status:
            where.append("e.review_status = ?")
            parameters.append(filters.review_status)
        if filters.category:
            where.append("e.category = ? COLLATE UNICODE_NOCASE")
            parameters.append(filters.category)
        if filters.missing:
            condition = _MISSING_FILTERS.get(filters.missing)
            if condition is None:
                raise ValueError(f"Desteklenmeyen eksik-alan filtresi: {filters.missing}")
            where.append(condition)
        if filters.identifier:
            identifier = re.sub(r"[^0-9Xx]", "", filters.identifier).upper()
            where.append(
                """
                EXISTS(
                    SELECT 1 FROM identifier AS i
                    WHERE i.edition_id = e.id AND i.normalized_value = ?
                )
                """
            )
            parameters.append(identifier)
        location_scoped = bool(filters.location)
        if filters.location and not filters.availability:
            where.append(
                """
                EXISTS(
                    SELECT 1 FROM copy AS lc
                    WHERE lc.edition_id = e.id AND lc.status = 'active'
                      AND lc.location = ?
                )
                """
            )
            parameters.append(filters.location)
        if filters.availability:
            # "available": ödünçte olmayan aktif nüsha VAR.
            # "unavailable": aktif nüsha var ama hepsi ödünçte (nüshasız
            # baskılar iki filtreye de girmez; OPAC ile aynı tanım).
            # Konum filtresi varsa iki koşul da AYNI dolabın nüshalarıyla
            # değerlendirilir.
            scope = " AND ec.location = ?" if location_scoped else ""
            if filters.availability == "available":
                where.append(self._available_sql(location_scoped))
                if location_scoped:
                    parameters.append(filters.location)
            elif filters.availability == "unavailable":
                where.append(
                    "EXISTS(SELECT 1 FROM copy AS ec "
                    f"WHERE ec.edition_id = e.id AND ec.status = 'active'{scope}) "
                    f"AND NOT {self._available_sql(location_scoped)}"
                )
                if location_scoped:
                    parameters.extend([filters.location, filters.location])
            else:
                raise ValueError(f"Desteklenmeyen müsaitlik filtresi: {filters.availability}")
        if filters.year_from is not None or filters.year_to is not None:
            where.append(
                "e.publication_date GLOB '[0-9][0-9][0-9][0-9]*' AND "
                "CAST(substr(e.publication_date, 1, 4) AS INTEGER) BETWEEN ? AND ?"
            )
            parameters.append(int(filters.year_from) if filters.year_from is not None else 0)
            parameters.append(int(filters.year_to) if filters.year_to is not None else 9999)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        order = self._SORTS[sort]
        if order is None:
            order = "bm25(edition_fts), e.id" if fts_query else "e.title COLLATE NOCASE, e.id"
        with self.db.connection(readonly=True) as connection:
            total = int(
                connection.execute(
                    f"SELECT COUNT(*) FROM {source} {clause}", parameters
                ).fetchone()[0]
            )
            id_rows = connection.execute(
                f"""
                SELECT e.id FROM {source} {clause}
                ORDER BY {order} LIMIT ? OFFSET ?
                """,
                (*parameters, limit, offset),
            ).fetchall()
            items = tuple(
                self._records_for_list_ids(
                    connection, [int(row["id"]) for row in id_rows]
                )
            )
        return SearchPage(items=items, total=total, limit=limit, offset=offset)

    def update_book(
        self,
        edition_id: int,
        changes: Mapping[str, Any] | None = None,
        *,
        user_edit: bool = True,
        **field_changes: Any,
    ) -> BookRecord:
        updates = dict(changes or {})
        updates.update(field_changes)
        unknown = set(updates) - _EDITABLE_FIELDS
        if unknown:
            raise ValueError(f"Desteklenmeyen alanlar: {', '.join(sorted(unknown))}")
        if not updates:
            record = self.get_book(edition_id)
            if record is None:
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            return record
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            for field_name, raw_value in updates.items():
                value = _normalise_field(field_name, raw_value)
                canonical_path, legacy_path = _resolved_field_aliases(field_name)
                locked = connection.execute(
                    """
                    SELECT 1 FROM resolved_field
                    WHERE edition_id = ? AND field_path IN (?, ?)
                      AND user_locked = 1
                    """,
                    (edition_id, canonical_path, legacy_path),
                ).fetchone()
                if locked is not None and not user_edit:
                    raise LockedFieldError(f"{field_name} kullanıcı tarafından kilitli")
                connection.execute(
                    f"UPDATE edition SET {field_name} = ?, updated_at = ? WHERE id = ?",
                    (value, now, edition_id),
                )
                if user_edit:
                    text_value = "" if value is None else str(value)
                    connection.execute(
                        """
                        INSERT INTO resolved_field(
                            edition_id, field_path, value, status, user_locked,
                            resolver_version, updated_at
                        ) VALUES (?, ?, ?, ?, 1, 'user', ?)
                        ON CONFLICT(edition_id, field_path) DO UPDATE SET
                            observation_id = NULL,
                            value = excluded.value,
                            status = excluded.status,
                            user_locked = 1,
                            resolver_version = 'user',
                            updated_at = excluded.updated_at
                        """,
                        (
                            edition_id,
                            canonical_path,
                            text_value,
                            FieldStatus.CONFIRMED.value,
                            now,
                        ),
                    )
                    if legacy_path != canonical_path:
                        connection.execute(
                            """
                            DELETE FROM resolved_field
                            WHERE edition_id = ? AND field_path = ?
                            """,
                            (edition_id, legacy_path),
                        )
            self._refresh_search_document(connection, edition_id)
        record = self.get_book(edition_id)
        assert record is not None
        return record

    def add_observation(
        self,
        observation: FieldObservation,
        *,
        edition_id: int | None = None,
        item_id: int | None = None,
    ) -> int:
        if edition_id is None and item_id is None:
            raise ValueError("edition_id veya item_id verilmelidir")
        if not 0.0 <= observation.confidence <= 1.0:
            raise ValueError("Gözlem güveni 0 ile 1 arasında olmalıdır")
        now = _now()
        polygon = (
            json.dumps(observation.polygon, separators=(",", ":"))
            if observation.polygon is not None
            else None
        )
        source_polygon = (
            json.dumps(observation.source_polygon, separators=(",", ":"))
            if observation.source_polygon is not None
            else None
        )
        with self.db.transaction(immediate=True) as connection:
            return int(
                connection.execute(
                    """
                    INSERT INTO field_observation(
                        edition_id, item_id, field_path, raw_value,
                        normalized_value, cover_role, polygon_json,
                        source_polygon_json,
                        engine_evidence_json, source_token_ids_json, confidence,
                        created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        edition_id,
                        item_id,
                        observation.field_path,
                        observation.raw_value,
                        observation.normalized_value,
                        observation.cover_role.value,
                        polygon,
                        source_polygon,
                        json.dumps(
                            [engine.value for engine in observation.engine_evidence],
                            separators=(",", ":"),
                        ),
                        json.dumps(list(observation.source_token_ids), separators=(",", ":")),
                        observation.confidence,
                        now,
                    ),
                ).lastrowid
            )

    def resolve_field(
        self,
        edition_id: int,
        field_path: str,
        value: str,
        *,
        status: FieldStatus | str,
        observation_id: int | None = None,
        user_locked: bool = False,
        resolver_version: str = "",
        force: bool = False,
    ) -> bool:
        """Resolve one field without letting later OCR degrade stronger evidence."""

        status = FieldStatus(status)
        canonical_path = _canonical_resolved_field_path(field_path)
        aliases = _resolved_field_aliases(canonical_path)
        legacy_path = aliases[-1]
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            existing = connection.execute(
                """
                SELECT rf.*, fo.confidence AS observation_confidence
                FROM resolved_field AS rf
                LEFT JOIN field_observation AS fo ON fo.id = rf.observation_id
                WHERE rf.edition_id = ? AND rf.field_path IN (?, ?)
                ORDER BY rf.user_locked DESC, rf.field_path = ? DESC
                LIMIT 1
                """,
                (edition_id, canonical_path, legacy_path, canonical_path),
            ).fetchone()
            if existing is not None and not force:
                if bool(existing["user_locked"]):
                    return False
                existing_status = FieldStatus(existing["status"])
                if existing_status == FieldStatus.CONFIRMED:
                    return False
                existing_known = str(existing["value"]).strip().casefold() not in {
                    "",
                    UNKNOWN_VALUE.casefold(),
                }
                incoming_known = str(value).strip().casefold() not in {
                    "",
                    UNKNOWN_VALUE.casefold(),
                }
                if existing_known and (not incoming_known or status == FieldStatus.UNRESOLVED):
                    return False
                existing_strength = _FIELD_STATUS_STRENGTH[existing_status]
                incoming_strength = _FIELD_STATUS_STRENGTH[status]
                if incoming_strength < existing_strength:
                    return False
                if incoming_strength == existing_strength:
                    incoming_confidence: float | None = None
                    if observation_id is not None:
                        row = connection.execute(
                            "SELECT confidence FROM field_observation WHERE id = ?",
                            (observation_id,),
                        ).fetchone()
                        if row is not None:
                            incoming_confidence = float(row["confidence"])
                    existing_confidence = (
                        float(existing["observation_confidence"])
                        if existing["observation_confidence"] is not None
                        else None
                    )
                    if existing_confidence is not None and (
                        incoming_confidence is None or incoming_confidence <= existing_confidence
                    ):
                        return False
            if status == FieldStatus.AUTO:
                self._require_auto_evidence(
                    connection, edition_id, canonical_path, value, observation_id
                )
            connection.execute(
                """
                INSERT INTO resolved_field(
                    edition_id, field_path, observation_id, value, status,
                    user_locked, resolver_version, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(edition_id, field_path) DO UPDATE SET
                    observation_id = excluded.observation_id,
                    value = excluded.value,
                    status = excluded.status,
                    user_locked = excluded.user_locked,
                    resolver_version = excluded.resolver_version,
                    updated_at = excluded.updated_at
                """,
                (
                    edition_id,
                    canonical_path,
                    observation_id,
                    value,
                    status.value,
                    int(user_locked),
                    resolver_version,
                    now,
                ),
            )
            if legacy_path != canonical_path:
                connection.execute(
                    """
                    DELETE FROM resolved_field
                    WHERE edition_id = ? AND field_path = ?
                    """,
                    (edition_id, legacy_path),
                )
            column = canonical_path.removeprefix("edition.")
            if column in _EDITABLE_FIELDS:
                connection.execute(
                    f"UPDATE edition SET {column} = ?, updated_at = ? WHERE id = ?",
                    (_normalise_field(column, value), now, edition_id),
                )
                if column in {"title", "original_title"}:
                    work_column = "canonical_title" if column == "title" else "original_title"
                    connection.execute(
                        f"""
                        UPDATE work SET {work_column} = ?, updated_at = ?
                        WHERE id = (SELECT work_id FROM edition WHERE id = ?)
                        """,
                        (_normalise_field(column, value), now, edition_id),
                    )
                self._refresh_search_document(connection, edition_id)
            return True

    @staticmethod
    def _require_auto_evidence(
        connection: sqlite3.Connection,
        edition_id: int,
        field_path: str,
        value: str,
        observation_id: int | None,
    ) -> None:
        if observation_id is None:
            raise InsufficientEvidenceError(
                "Otomatik alan görsel kanıt gözlemi olmadan kaydedilemez"
            )
        row = connection.execute(
            """
            SELECT fo.*, ji.edition_id AS item_edition_id
            FROM field_observation AS fo
            LEFT JOIN job_item AS ji ON ji.id = fo.item_id
            WHERE fo.id = ?
            """,
            (observation_id,),
        ).fetchone()
        if row is None:
            raise InsufficientEvidenceError("Alan gözlemi bulunamadı")
        evidence_edition = row["edition_id"] or row["item_edition_id"]
        if evidence_edition is not None and int(evidence_edition) != edition_id:
            raise InsufficientEvidenceError("Alan gözlemi farklı bir baskıya ait")
        if row["field_path"].removeprefix("edition.") != field_path.removeprefix("edition."):
            raise InsufficientEvidenceError("Alan gözlemi farklı bir alanı kanıtlıyor")
        if _clean_value(row["normalized_value"]) != _clean_value(value):
            raise InsufficientEvidenceError(
                "Otomatik değer, bağlı OCR gözlemiyle birebir uyuşmuyor"
            )
        engines = set(json.loads(row["engine_evidence_json"]))
        classic = {"rapidocr_ppocrv6", "tesseract", "easyocr"}
        token_ids = json.loads(row["source_token_ids_json"])
        if (
            float(row["confidence"]) < 0.98
            or len(engines) < 2
            or not engines.intersection(classic)
            or not row["polygon_json"]
            or not token_ids
        ):
            raise InsufficientEvidenceError(
                "Otomatik kabul için güven ≥0,98, iki motor, klasik OCR kutusu "
                "ve token kanıtı gerekir"
            )

    def set_cover_paths(
        self,
        edition_id: int,
        *,
        front_path: str | Path | None = None,
        front_inside_path: str | Path | None = None,
        back_inside_path: str | Path | None = None,
        back_path: str | Path | None = None,
    ) -> None:
        changes: dict[str, str] = {}
        if front_path is not None:
            changes["front_path"] = str(front_path)
        if front_inside_path is not None:
            changes["front_inside_path"] = str(front_inside_path)
        if back_inside_path is not None:
            changes["back_inside_path"] = str(back_inside_path)
        if back_path is not None:
            changes["back_path"] = str(back_path)
        if changes:
            self.update_book(edition_id, changes, user_edit=False)

    def set_raw_ocr_text(self, edition_id: int, text: str) -> None:
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE edition SET raw_ocr_text = ?, updated_at = ? WHERE id = ?
                """,
                (unicodedata.normalize("NFC", text), now, edition_id),
            )
            if cursor.rowcount != 1:
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            self._refresh_search_document(connection, edition_id)

    def delete_copy(self, copy_id: int) -> bool:
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                """
                SELECT c.status,
                       EXISTS(SELECT 1 FROM discard_record AS d WHERE d.copy_id = c.id)
                           AS has_discard_audit
                FROM copy AS c WHERE c.id = ?
                """,
                (copy_id,),
            ).fetchone()
            if row is None:
                return False
            if row["status"] != "active" or bool(row["has_discard_audit"]):
                raise StateConflictError(
                    "Düşülmüş nüsha fiziksel olarak silinemez; düşüm defteri kaydı korunmalıdır"
                )
            try:
                cursor = connection.execute(
                    "DELETE FROM copy WHERE id = ? AND status = 'active'", (copy_id,)
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError(str(exc)) from exc
            return cursor.rowcount == 1

    def delete_book(self, edition_id: int) -> bool:
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT work_id FROM edition WHERE id = ?", (edition_id,)
            ).fetchone()
            if row is None:
                return False
            try:
                connection.execute("DELETE FROM edition WHERE id = ?", (edition_id,))
            except sqlite3.IntegrityError as exc:
                raise StateConflictError(str(exc)) from exc
            connection.execute(
                """
                DELETE FROM work
                WHERE id = ? AND NOT EXISTS(
                    SELECT 1 FROM edition WHERE work_id = work.id
                )
                """,
                (row["work_id"],),
            )
            return True

    @classmethod
    def _record_from_row(cls, connection: sqlite3.Connection, row: sqlite3.Row) -> BookRecord:
        return cls._records_from_rows(connection, [row])[0]

    @classmethod
    def _records_for_list_ids(
        cls, connection: sqlite3.Connection, edition_ids: Sequence[int]
    ) -> list[BookRecord]:
        """Load a page's explicit lightweight edition columns in page order."""

        if not edition_ids:
            return []
        by_id: dict[int, sqlite3.Row] = {}
        # list_books permits 10k rows; stay below conservative SQLite variable
        # limits while still using one bounded query per 500 records.
        for start in range(0, len(edition_ids), 500):
            chunk = edition_ids[start : start + 500]
            marks = ",".join("?" for _ in chunk)
            rows = connection.execute(
                f"""
                SELECT {_LIST_EDITION_COLUMNS}
                FROM edition AS e
                WHERE e.id IN ({marks})
                """,
                chunk,
            )
            by_id.update((int(row["id"]), row) for row in rows)
        ordered = [by_id[edition_id] for edition_id in edition_ids if edition_id in by_id]
        return cls._records_from_rows(connection, ordered)

    @classmethod
    def _records_from_rows(
        cls, connection: sqlite3.Connection, rows: Sequence[sqlite3.Row]
    ) -> list[BookRecord]:
        """Bir sayfa baskıyı üç toplu sorguyla hidratlar (kayıt başına sorgu yok)."""

        if not rows:
            return []
        edition_ids = [int(row["id"]) for row in rows]
        contributors: dict[int, list[ContributorInput]] = {eid: [] for eid in edition_ids}
        identifiers: dict[int, list[IdentifierInput]] = {eid: [] for eid in edition_ids}
        copies: dict[int, list[CopyRecord]] = {eid: [] for eid in edition_ids}
        # SQLite parametre sınırına (999) takılmamak için 500'lük parçalar.
        for start in range(0, len(edition_ids), 500):
            chunk = edition_ids[start : start + 500]
            marks = ",".join("?" for _ in chunk)
            for item in connection.execute(
                f"""
                SELECT ec.edition_id, c.display_name, ec.role, ec.sort_order
                FROM edition_contributor AS ec
                JOIN contributor AS c ON c.id = ec.contributor_id
                WHERE ec.edition_id IN ({marks})
                ORDER BY ec.sort_order, c.display_name
                """,
                chunk,
            ):
                contributors[int(item["edition_id"])].append(
                    ContributorInput(
                        name=item["display_name"],
                        role=item["role"],
                        sort_order=int(item["sort_order"]),
                    )
                )
            for item in connection.execute(
                f"""
                SELECT edition_id, scheme, value, source, confidence
                FROM identifier WHERE edition_id IN ({marks})
                ORDER BY scheme, value
                """,
                chunk,
            ):
                identifiers[int(item["edition_id"])].append(
                    IdentifierInput(
                        scheme=item["scheme"],
                        value=item["value"],
                        source=item["source"],
                        confidence=item["confidence"],
                    )
                )
            for item in connection.execute(
                f"SELECT * FROM copy WHERE edition_id IN ({marks}) ORDER BY id",
                chunk,
            ):
                copies[int(item["edition_id"])].append(
                    CopyRecord(
                        id=int(item["id"]),
                        edition_id=int(item["edition_id"]),
                        inventory_code=item["inventory_code"],
                        source_fingerprint=item["source_fingerprint"],
                        location=item["location"],
                        notes=item["notes"],
                        status=item["status"],
                        acquisition_method=item["acquisition_method"],
                        acquisition_date=item["acquisition_date"],
                        acquisition_price=item["acquisition_price"],
                    )
                )
        return [
            cls._assemble_record(
                row,
                tuple(contributors[int(row["id"])]),
                tuple(identifiers[int(row["id"])]),
                tuple(copies[int(row["id"])]),
            )
            for row in rows
        ]

    @staticmethod
    def _assemble_record(
        row: sqlite3.Row,
        contributors: tuple[ContributorInput, ...],
        identifiers: tuple[IdentifierInput, ...],
        copies: tuple[CopyRecord, ...],
    ) -> BookRecord:
        return BookRecord(
            edition_id=int(row["id"]),
            work_id=int(row["work_id"]),
            title=row["title"],
            subtitle=row["subtitle"],
            original_title=row["original_title"],
            publisher=row["publisher"],
            imprint=row["imprint"],
            series=row["series"],
            volume=row["volume"],
            language=row["language"],
            publication_place=row["publication_place"],
            publication_date=row["publication_date"],
            edition_statement=row["edition_statement"],
            printing_number=row["printing_number"],
            printer=row["printer"],
            binding=row["binding"],
            page_count=row["page_count"],
            dimensions=row["dimensions"],
            price_amount=row["price_amount"],
            currency=row["currency"],
            blurb=row["blurb"],
            awards=row["awards"],
            quotations=row["quotations"],
            review_status=row["review_status"],
            category=row["category"],
            contributors=contributors,
            identifiers=identifiers,
            copies=copies,
            front_path=row["front_path"],
            front_inside_path=row["front_inside_path"],
            back_inside_path=row["back_inside_path"],
            back_path=row["back_path"],
            raw_ocr_text=row["raw_ocr_text"],
            created_at=_parse_time(row["created_at"]),
            updated_at=_parse_time(row["updated_at"]),
        )

    @staticmethod
    def _refresh_search_document(connection: sqlite3.Connection, edition_id: int) -> None:
        row = connection.execute("SELECT * FROM edition WHERE id = ?", (edition_id,)).fetchone()
        if row is None:
            return
        contributors = " ".join(
            item[0]
            for item in connection.execute(
                """
                SELECT c.display_name
                FROM edition_contributor AS ec
                JOIN contributor AS c ON c.id = ec.contributor_id
                WHERE ec.edition_id = ? ORDER BY ec.sort_order, c.display_name
                """,
                (edition_id,),
            )
        )
        identifiers = " ".join(
            f"{item['scheme']} {item['value']} {item['normalized_value']}"
            for item in connection.execute(
                """
                SELECT scheme, value, normalized_value
                FROM identifier WHERE edition_id = ? ORDER BY scheme, value
                """,
                (edition_id,),
            )
        )
        connection.execute(
            """
            INSERT INTO edition_search_document(
                edition_id, title, subtitle, original_title, contributors,
                publisher, identifiers, blurb, raw_ocr
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(edition_id) DO UPDATE SET
                title = excluded.title,
                subtitle = excluded.subtitle,
                original_title = excluded.original_title,
                contributors = excluded.contributors,
                publisher = excluded.publisher,
                identifiers = excluded.identifiers,
                blurb = excluded.blurb,
                raw_ocr = excluded.raw_ocr
            """,
            (
                edition_id,
                _searchable_text(row["title"]),
                _searchable_text(row["subtitle"]),
                _searchable_text(row["original_title"]),
                _searchable_text(contributors),
                _searchable_text(row["publisher"]),
                _searchable_text(identifiers),
                _searchable_text(row["blurb"]),
                _searchable_text(row["raw_ocr_text"]),
            ),
        )

    def set_location(self, edition_id: int, location: str | None) -> int:
        """Baskının tüm kopyalarının dolap/konum bilgisini günceller."""

        cleaned = (location or "").strip() or None
        with self.db.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            cursor = connection.execute(
                "UPDATE copy SET location = ? WHERE edition_id = ? AND status = 'active'",
                (cleaned, edition_id),
            )
            return cursor.rowcount

    def set_copy_location(self, copy_id: int, location: str | None) -> None:
        """Tek nüshanın konumunu günceller (set_location tüm nüshaları ezer)."""

        cleaned = (location or "").strip() or None
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                "UPDATE copy SET location = ? WHERE id = ?",
                (cleaned, copy_id),
            )
            if cursor.rowcount == 0:
                raise KeyError(f"Nüsha bulunamadı: {copy_id}")

    def update_copy_fields(
        self,
        copy_id: int,
        *,
        location: str | None = None,
        notes: str | None = None,
        acquisition_method: str | None = None,
        acquisition_date: str | None = None,
        acquisition_price: str | None = None,
    ) -> None:
        """Yalnız çağıranın verdiği alanları günceller.

        Bir alan için ``None`` geçilmesi "dokunma" anlamına gelir (kwarg hiç
        verilmemiş gibi); alanı NULL'a çekmek için boş string geçilmelidir.
        """

        fields = {
            name: _clean_value(value)
            for name, value in (
                ("location", location),
                ("notes", notes),
                ("acquisition_method", acquisition_method),
                ("acquisition_date", acquisition_date),
                ("acquisition_price", acquisition_price),
            )
            if value is not None
        }
        if not fields:
            with self.db.connection(readonly=True) as connection:
                if connection.execute(
                    "SELECT 1 FROM copy WHERE id = ?", (copy_id,)
                ).fetchone() is None:
                    raise KeyError(f"Nüsha bulunamadı: {copy_id}")
            return
        assignments = ", ".join(f"{name} = ?" for name in fields)
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                f"UPDATE copy SET {assignments}, updated_at = ? WHERE id = ?",
                (*fields.values(), _now(), copy_id),
            )
            if cursor.rowcount == 0:
                raise KeyError(f"Nüsha bulunamadı: {copy_id}")

    def set_copy_count(
        self,
        edition_id: int,
        count: int,
        *,
        location: str | None = None,
    ) -> int:
        """Aktif kopya sayısını hedefe getirir; düşüm denetim izi korunur.

        Azaltırken aktif ödünçteki nüshalar SİLİNMEZ; hedefin altına
        inilemiyorsa ulaşılabilen sayı döner (DB trigger'ı son emniyettir).
        """

        target = max(1, int(count))
        book = self.get_book(edition_id)
        if book is None:
            raise KeyError(f"Baskı bulunamadı: {edition_id}")
        cleaned = (location or "").strip() or None
        active_copies = [copy for copy in book.copies if copy.status == "active"]
        if cleaned is None:
            inheritance_source = active_copies or list(book.copies)
            if inheritance_source:
                cleaned = inheritance_source[-1].location
        current = len(active_copies)
        if target > current:
            for _ in range(target - current):
                self.add_copy(
                    edition_id,
                    CopyInput(location=cleaned) if cleaned else None,
                )
            return target
        if target < current:
            loaned = {
                int(row["copy_id"])
                for row in self.db.fetchall(
                    """
                    SELECT copy_id FROM loan
                    WHERE edition_id = ? AND returned_at IS NULL AND copy_id IS NOT NULL
                    """,
                    (edition_id,),
                )
            }
            # Düşülmüş nüsha Discards tablosunun ve MEB tutanağının bağlı
            # denetim kaydıdır; adet azaltımı onu asla fiziksel olarak silmez.
            deletable = [copy for copy in active_copies if copy.id not in loaned]
            for copy in reversed(deletable[-(current - target) :]):
                self.delete_copy(copy.id)
            removable = min(current - target, len(deletable))
            return current - removable
        return target

    def set_authors(self, edition_id: int, names: Sequence[str]) -> None:
        """Yazar rolündeki katkıda bulunanları yeniden yazar; diğer roller korunur."""

        contributors = tuple(
            ContributorInput(name=name.strip(), role=ContributorRole.AUTHOR)
            for name in names
            if name and name.strip()
        )
        with self.db.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            connection.execute(
                "DELETE FROM edition_contributor WHERE edition_id = ? AND role = ?",
                (edition_id, ContributorRole.AUTHOR.value),
            )
            self._save_contributors(connection, edition_id, contributors, replace=False)
            self._refresh_search_document(connection, edition_id)

    def set_isbn(self, edition_id: int, value: str | None) -> None:
        """ISBN'i değiştirir; boş değer mevcut ISBN kayıtlarını siler.

        Geçersiz ISBN ``ValueError``, başka baskıya kayıtlı ISBN
        ``IdentifierConflictError`` üretir; iki durumda da kayıt değişmez.
        """

        cleaned = re.sub(r"[^0-9Xx]", "", value or "").upper()
        prepared: tuple[tuple[IdentifierInput, str, str], ...] = ()
        if cleaned:
            prepared = _prepare_identifiers(
                (IdentifierInput(scheme="ISBN", value=cleaned, source="user"),)
            )
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            connection.execute(
                """
                DELETE FROM identifier
                WHERE edition_id = ? AND scheme IN ('ISBN10', 'ISBN13')
                """,
                (edition_id,),
            )
            if prepared:
                self._save_identifiers(connection, edition_id, prepared, now)
            self._refresh_search_document(connection, edition_id)

    def distribution(self, column: str) -> list[tuple[str, int]]:
        """İstatistik görünümü için sütun dağılımı (boş değerler '—' altında)."""

        if column not in {"category", "language", "publisher", "review_status"}:
            raise ValueError(f"Desteklenmeyen sütun: {column}")
        rows = self.db.fetchall(
            f"""
            SELECT COALESCE(NULLIF({column}, ''), '—') AS value, COUNT(*) AS count
            FROM edition
            GROUP BY value
            ORDER BY count DESC, value COLLATE NOCASE
            """
        )
        return [(str(row["value"]), int(row["count"])) for row in rows]

    def allocate_inventory_codes(self, count: int, *, year: int | None = None) -> list[str]:
        """Yıl+sıra biçiminde (örn. 2026-000001) demirbaş numarası ayırır.

        BEGIN IMMEDIATE tek yazarı garanti eder; elle girilmiş (işgal edilmiş)
        numaralar atlanır. Çökme arası kaybolan numaralar sorun değildir
        (seri boşluklu olabilir).
        """

        count = max(1, int(count))
        year = int(year) if year else datetime.now(UTC).year
        codes: list[str] = []
        with self.db.transaction(immediate=True) as connection:
            codes = self._allocate_codes_in_tx(connection, count, year)
        return codes

    @staticmethod
    def _allocate_codes_in_tx(
        connection: sqlite3.Connection, count: int, year: int
    ) -> list[str]:
        connection.execute(
            "INSERT OR IGNORE INTO inventory_sequence(year, next_value) VALUES (?, 1)",
            (year,),
        )
        row = connection.execute(
            "SELECT next_value FROM inventory_sequence WHERE year = ?", (year,)
        ).fetchone()
        sequence = int(row[0])
        codes: list[str] = []
        while len(codes) < count:
            candidate = f"{year}-{sequence:06d}"
            sequence += 1
            occupied = connection.execute(
                "SELECT 1 FROM copy WHERE inventory_code = ?", (candidate,)
            ).fetchone()
            if occupied is None:
                codes.append(candidate)
        connection.execute(
            "UPDATE inventory_sequence SET next_value = ? WHERE year = ?",
            (sequence, year),
        )
        return codes

    def assign_missing_inventory_codes(
        self, edition_id: int, *, year: int | None = None
    ) -> dict[int, str]:
        """Baskının numarasız nüshalarına sıradaki demirbaş numaralarını basar."""

        year = int(year) if year else datetime.now(UTC).year
        assigned: dict[int, str] = {}
        with self.db.transaction(immediate=True) as connection:
            rows = connection.execute(
                """
                SELECT id FROM copy
                WHERE edition_id = ? AND status = 'active'
                  AND (inventory_code IS NULL OR inventory_code = '')
                ORDER BY id
                """,
                (edition_id,),
            ).fetchall()
            if not rows:
                return {}
            codes = self._allocate_codes_in_tx(connection, len(rows), year)
            for row, code in zip(rows, codes, strict=True):
                connection.execute(
                    "UPDATE copy SET inventory_code = ? WHERE id = ?",
                    (code, int(row["id"])),
                )
                assigned[int(row["id"])] = code
        return assigned

    def assign_missing_codes_bulk(
        self, *, location: str | None = None, year: int | None = None
    ) -> dict[int, str]:
        """Kapsamdaki (tümü ya da tek dolap) numarasız aktif nüshalara kod basar."""

        year = int(year) if year else datetime.now(UTC).year
        clause = "AND location = ?" if location else ""
        parameters: list[Any] = [location] if location else []
        assigned: dict[int, str] = {}
        with self.db.transaction(immediate=True) as connection:
            rows = connection.execute(
                f"""
                SELECT id FROM copy
                WHERE (inventory_code IS NULL OR inventory_code = '')
                  AND status = 'active' {clause}
                ORDER BY id
                """,
                parameters,
            ).fetchall()
            if not rows:
                return {}
            codes = self._allocate_codes_in_tx(connection, len(rows), year)
            for row, code in zip(rows, codes, strict=True):
                connection.execute(
                    "UPDATE copy SET inventory_code = ? WHERE id = ?",
                    (code, int(row["id"])),
                )
                assigned[int(row["id"])] = code
        return assigned

    def peek_next_inventory_code(self, *, year: int | None = None) -> str:
        year = int(year) if year else datetime.now(UTC).year
        row = self.db.fetchone(
            "SELECT next_value FROM inventory_sequence WHERE year = ?", (year,)
        )
        sequence = int(row[0]) if row is not None else 1
        return f"{year}-{sequence:06d}"

    def stats(self) -> dict[str, int]:
        row = self.db.fetchone(
            """
            SELECT
                (SELECT COUNT(*) FROM work) AS works,
                (SELECT COUNT(*) FROM edition) AS editions,
                (SELECT COUNT(*) FROM copy WHERE status = 'active') AS copies,
                (SELECT COUNT(*) FROM edition WHERE review_status = 'review') AS review
            """
        )
        assert row is not None
        return {key: int(row[key]) for key in ("works", "editions", "copies", "review")}


CatalogRepository = Catalog


def normalise_identifier(scheme: str, value: str) -> tuple[str, str]:
    scheme = re.sub(r"[^A-Za-z0-9]", "", scheme).upper()
    compact = re.sub(r"[^0-9Xx]", "", value).upper()
    if scheme in _ISBN_SCHEMES:
        if scheme == "ISBN":
            scheme = "ISBN10" if len(compact) == 10 else "ISBN13"
        if scheme == "ISBN10" and not _valid_isbn10(compact):
            raise ValueError(f"Geçersiz ISBN-10: {value}")
        if scheme == "ISBN13" and not _valid_isbn13(compact):
            raise ValueError(f"Geçersiz ISBN-13: {value}")
    else:
        if not scheme:
            raise ValueError("Tanımlayıcı türü boş olamaz")
        compact = unicodedata.normalize("NFC", value).strip().casefold()
    if not compact:
        raise ValueError("Tanımlayıcı değeri boş olamaz")
    return scheme, compact


def _prepare_identifiers(
    identifiers: Sequence[IdentifierInput],
) -> tuple[tuple[IdentifierInput, str, str], ...]:
    prepared: list[tuple[IdentifierInput, str, str]] = []
    seen: set[tuple[str, str]] = set()
    for identifier in identifiers:
        scheme, normalized = normalise_identifier(identifier.scheme, identifier.value)
        key = (scheme, normalized)
        if key not in seen:
            prepared.append((identifier, scheme, normalized))
            seen.add(key)
        equivalent: tuple[str, str] | None = None
        if scheme == "ISBN10":
            equivalent = ("ISBN13", _isbn10_to_isbn13(normalized))
        elif scheme == "ISBN13" and normalized.startswith("978"):
            equivalent = ("ISBN10", _isbn13_to_isbn10(normalized))
        if equivalent is not None and equivalent not in seen:
            derived_scheme, derived_value = equivalent
            prepared.append(
                (
                    IdentifierInput(
                        scheme=derived_scheme,
                        value=derived_value,
                        source=f"derived:{identifier.source}",
                        confidence=identifier.confidence,
                    ),
                    derived_scheme,
                    derived_value,
                )
            )
            seen.add(equivalent)
    return tuple(prepared)


# Check-digit arithmetic lives in `isbn`. A second copy here drifted from it
# once already: this one accepted any thirteen digits, while `isbn` required the
# 978/979 book prefix that makes a number an ISBN rather than some other EAN.
def _isbn10_to_isbn13(value: str) -> str:
    return isbn10_to_isbn13(value)


def _isbn13_to_isbn10(value: str) -> str:
    body = value[3:12]
    return f"{body}{isbn10_check_digit(body)}"


def _valid_isbn10(value: str) -> bool:
    return is_valid_isbn10(value)


def _valid_isbn13(value: str) -> bool:
    return is_valid_isbn13(value)


def _normalise_field(name: str, value: Any) -> Any:
    if value is None:
        return None
    if name == "page_count":
        page_count = int(value)
        if page_count < 0:
            raise ValueError("page_count negatif olamaz")
        return page_count
    if isinstance(value, str):
        return _clean_value(value)
    return value


def _clean_value(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = unicodedata.normalize("NFC", str(value))
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized or None


def _make_fts_query(query: str) -> str:
    # Quoting every term prevents operators supplied by a filename/ISBN from
    # becoming FTS syntax. Prefix matching is convenient for catalogue search.
    terms = _FTS_TERM.findall(unicodedata.normalize("NFC", query))
    return " AND ".join(f'"{term.replace(chr(34), chr(34) * 2)}"*' for term in terms)


def _searchable_text(value: str | None) -> str:
    original = unicodedata.normalize("NFC", value or "")
    decomposed = unicodedata.normalize("NFKD", original).translate(
        str.maketrans({"ı": "i", "İ": "I"})
    )
    folded = "".join(
        character for character in decomposed if unicodedata.category(character) != "Mn"
    ).casefold()
    return original if folded == original.casefold() else f"{original} {folded}"


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


def _parse_time(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None
