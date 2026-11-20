"""Raf/dolap kayıtları: harita yerleşimi ve serbest konum metinlerinin evlatlığı.

`shelf.name`, `copy.location` serbest metniyle TAM eşleşir; otomatik
normalizasyon yapılmaz (yanlış birleştirme riski). Yazım varyantları harita
özetinde "eşleşmemiş" listesinde görünür ve `adopt` ile birleştirilir.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any

from kitapkatalog.database import Database, StateConflictError

_HEX_COLOR_CHARS = set("0123456789abcdefABCDEF")


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


def _clean_name(name: Any) -> str:
    cleaned = str(name or "").strip()
    if not cleaned:
        raise ValueError("Dolap adı boş olamaz")
    return cleaned


def _clean_color(color: Any) -> str | None:
    cleaned = str(color or "").strip()
    if not cleaned:
        return None
    if not (
        cleaned.startswith("#")
        and len(cleaned) in (4, 7)
        and set(cleaned[1:]) <= _HEX_COLOR_CHARS
    ):
        raise ValueError(f"Geçersiz renk (örn. #a3c2ff bekleniyor): {color}")
    return cleaned


def _clean_cell(grid_row: Any, grid_col: Any) -> tuple[int | None, int | None]:
    if (grid_row is None) != (grid_col is None):
        raise ValueError("Satır ve sütun birlikte verilmeli (ya ikisi ya hiçbiri)")
    if grid_row is None:
        return None, None
    row, col = int(grid_row), int(grid_col)
    if row < 0 or col < 0:
        raise ValueError("Satır ve sütun negatif olamaz")
    return row, col


@dataclass(frozen=True)
class ShelfRecord:
    id: int
    name: str
    grid_row: int | None
    grid_col: int | None
    capacity: int | None
    color: str | None
    notes: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "grid_row": self.grid_row,
            "grid_col": self.grid_col,
            "capacity": self.capacity,
            "color": self.color,
            "notes": self.notes,
        }


class Shelves:
    def __init__(self, database: Database) -> None:
        self.db = database

    @staticmethod
    def _record(row: sqlite3.Row) -> ShelfRecord:
        return ShelfRecord(
            id=int(row["id"]),
            name=row["name"],
            grid_row=row["grid_row"],
            grid_col=row["grid_col"],
            capacity=row["capacity"],
            color=row["color"],
            notes=row["notes"],
        )

    def get(self, shelf_id: int) -> ShelfRecord | None:
        row = self.db.fetchone("SELECT * FROM shelf WHERE id = ?", (shelf_id,))
        return self._record(row) if row is not None else None

    def list(self) -> list[ShelfRecord]:
        rows = self.db.fetchall("SELECT * FROM shelf ORDER BY name COLLATE NOCASE")
        return [self._record(row) for row in rows]

    def create(
        self,
        name: str,
        *,
        grid_row: int | None = None,
        grid_col: int | None = None,
        capacity: int | None = None,
        color: str | None = None,
        notes: str | None = None,
    ) -> ShelfRecord:
        cleaned = _clean_name(name)
        row, col = _clean_cell(grid_row, grid_col)
        if capacity is not None and int(capacity) <= 0:
            raise ValueError("Kapasite pozitif olmalı")
        stamp = _now()
        try:
            with self.db.transaction(immediate=True) as connection:
                cursor = connection.execute(
                    """
                    INSERT INTO shelf(name, grid_row, grid_col, capacity, color,
                                      notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        cleaned,
                        row,
                        col,
                        int(capacity) if capacity is not None else None,
                        _clean_color(color),
                        (str(notes).strip() or None) if notes else None,
                        stamp,
                        stamp,
                    ),
                )
                shelf_id = int(cursor.lastrowid)
        except sqlite3.IntegrityError as error:
            raise StateConflictError(self._conflict_message(cleaned, row, col)) from error
        record = self.get(shelf_id)
        assert record is not None
        return record

    def update(self, shelf_id: int, **fields: Any) -> ShelfRecord:
        allowed = {"name", "grid_row", "grid_col", "capacity", "color", "notes"}
        unknown = set(fields) - allowed
        if unknown:
            raise ValueError(f"Bilinmeyen alan: {', '.join(sorted(unknown))}")
        stamp = _now()
        try:
            with self.db.transaction(immediate=True) as connection:
                # Mevcut kayıt AYNI transaction'da okunur; eşzamanlı rename ile
                # copy.location senkronunun kopmaması için (Codex bulgusu).
                existing = connection.execute(
                    "SELECT * FROM shelf WHERE id = ?", (shelf_id,)
                ).fetchone()
                if existing is None:
                    raise KeyError("Dolap bulunamadı")
                current = self._record(existing)
                name = _clean_name(fields.get("name", current.name))
                row, col = _clean_cell(
                    fields.get("grid_row", current.grid_row),
                    fields.get("grid_col", current.grid_col),
                )
                capacity = fields.get("capacity", current.capacity)
                if capacity is not None and int(capacity) <= 0:
                    raise ValueError("Kapasite pozitif olmalı")
                color = _clean_color(fields.get("color", current.color))
                notes = fields.get("notes", current.notes)
                connection.execute(
                    """
                    UPDATE shelf SET name = ?, grid_row = ?, grid_col = ?,
                           capacity = ?, color = ?, notes = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        name,
                        row,
                        col,
                        int(capacity) if capacity is not None else None,
                        color,
                        (str(notes).strip() or None) if notes else None,
                        stamp,
                        shelf_id,
                    ),
                )
                if name != current.name:
                    # Harita-katalog eşleşmesi kopmasın: nüsha konumları aynı
                    # transaction'da yeni ada taşınır.
                    connection.execute(
                        "UPDATE copy SET location = ? WHERE location = ?",
                        (name, current.name),
                    )
        except sqlite3.IntegrityError as error:
            raise StateConflictError(self._conflict_message(name, row, col)) from error
        record = self.get(shelf_id)
        assert record is not None
        return record

    def delete(self, shelf_id: int) -> None:
        """Yalnız dolap kaydını siler; nüshalardaki konum metni korunur."""

        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute("DELETE FROM shelf WHERE id = ?", (shelf_id,))
            if cursor.rowcount == 0:
                raise KeyError("Dolap bulunamadı")

    def adopt(self, shelf_id: int, location: str) -> int:
        """Serbest konum metnindeki nüshaları bu dolabın adına taşır."""

        cleaned = str(location or "").strip()
        if not cleaned:
            raise ValueError("Taşınacak konum boş olamaz")
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT name FROM shelf WHERE id = ?", (shelf_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Dolap bulunamadı")
            # Başka bir dolabın TAM adı "serbest konum" değildir; kabul etmek
            # o dolabın bütün nüshalarını sessizce buraya taşırdı.
            other = connection.execute(
                "SELECT id FROM shelf WHERE name = ? AND id != ?",
                (cleaned, shelf_id),
            ).fetchone()
            if other is not None:
                raise StateConflictError(
                    f"'{cleaned}' başka bir dolabın adı; önce o dolabı silin ya da yeniden adlandırın"
                )
            cursor = connection.execute(
                "UPDATE copy SET location = ? WHERE location = ?",
                (row["name"], cleaned),
            )
            return cursor.rowcount

    def map_summary(self) -> dict[str, Any]:
        counts = {
            row["name"]: row
            for row in self.db.fetchall(
                """
                SELECT c.location AS name,
                       COUNT(*) AS copies,
                       COUNT(DISTINCT c.edition_id) AS editions,
                       SUM(CASE WHEN l.id IS NOT NULL THEN 1 ELSE 0 END) AS on_loan
                FROM copy AS c
                LEFT JOIN loan AS l
                       ON l.copy_id = c.id AND l.returned_at IS NULL
                WHERE c.location IS NOT NULL AND c.location <> ''
                  AND c.status = 'active'
                GROUP BY c.location
                """
            )
        }
        shelves: list[dict[str, Any]] = []
        for record in self.list():
            item = record.to_dict()
            tally = counts.pop(record.name, None)
            item["copies"] = int(tally["copies"]) if tally else 0
            item["editions"] = int(tally["editions"]) if tally else 0
            item["on_loan"] = int(tally["on_loan"]) if tally else 0
            shelves.append(item)
        unmatched = [
            {
                "name": name,
                "copies": int(tally["copies"]),
                "editions": int(tally["editions"]),
            }
            for name, tally in sorted(counts.items())
        ]
        return {"shelves": shelves, "unmatched": unmatched}

    @staticmethod
    def _conflict_message(name: str, row: int | None, col: int | None) -> str:
        if row is not None:
            return f"Bu ad ya da hücre kullanımda: {name} (satır {row}, sütun {col})"
        return f"Bu adla dolap zaten var: {name}"
