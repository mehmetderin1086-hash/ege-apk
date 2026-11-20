"""Serbest barkod girdisinin katalogda çözümlenmesi.

Öncelik kuralı tektir ve buradan yönetilir: önce demirbaş numarası TAM
eşleşmesi, sonra ISBN. Yıl+sıra demirbaş kodları (örn. "2026-000001")
rakam ayıklanınca 10 haneye düşüp kayıtlı bir ISBN ile çakışabilir;
tam eşleşme her zaman kazanır.
"""

from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass

_NON_ISBN_CHARS = re.compile(r"[^0-9Xx]")


def compact_code(code: str) -> str:
    """Rakam ve X dışını ayıkla (identifier.normalized_value biçimi)."""
    return _NON_ISBN_CHARS.sub("", code or "").upper()


def isbn_candidate(code: str) -> str | None:
    """Kompakt hâli 10/13 hane ise ISBN adayı, değilse None."""
    compact = compact_code(code)
    if len(compact) in (10, 13):
        return compact
    return None


@dataclass(frozen=True)
class ResolvedCode:
    kind: str  # "inventory" | "isbn" | "unresolved"
    copy_id: int | None
    edition_id: int | None


def resolve_catalog_code(connection: sqlite3.Connection, code: str) -> ResolvedCode:
    code = (code or "").strip()
    if code:
        row = connection.execute(
            "SELECT id, edition_id FROM copy WHERE inventory_code = ?", (code,)
        ).fetchone()
        if row is not None:
            return ResolvedCode("inventory", int(row["id"]), int(row["edition_id"]))
        compact = isbn_candidate(code)
        if compact is not None:
            identifier = connection.execute(
                "SELECT edition_id FROM identifier WHERE normalized_value = ?",
                (compact,),
            ).fetchone()
            if identifier is not None:
                return ResolvedCode("isbn", None, int(identifier["edition_id"]))
    return ResolvedCode("unresolved", None, None)
