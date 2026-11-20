"""Okuma listeleri servisi: liste CRUD, kitap/üye atama, ilerleme türetme.

İlerleme ayrı bir tabloda TUTULMAZ: listedeki baskılardan üyenin İADE ETTİĞİ
(``returned_at NOT NULL``) farklı baskı sayısı / liste boyutu olarak her
çağrıda ``loan`` defterinden türetilir; aktif (henüz iade edilmemiş) ödünç
ilerlemeye sayılmaz. Böylece iki kaynağın birbirinden sapması mümkün olmaz.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from difflib import SequenceMatcher
from importlib.resources import files
from typing import Any

from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.voice_protocol import fold_text

_TEMPLATE_MATCH_THRESHOLD = 0.85
_TEMPLATE_RESOURCE = "yuz_temel_eser.txt"


def _now_dt(now: datetime | None) -> datetime:
    return now if now is not None else datetime.now(UTC).astimezone()


def _stamp(now: datetime) -> str:
    return now.isoformat(timespec="microseconds")


@dataclass(frozen=True, slots=True)
class ReadingListRecord:
    id: int
    name: str
    description: str | None
    is_opac_visible: bool
    position: int
    created_at: str
    updated_at: str
    item_count: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "is_opac_visible": self.is_opac_visible,
            "position": self.position,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "item_count": self.item_count,
        }


@dataclass(frozen=True, slots=True)
class ReadingListItemRecord:
    id: int
    list_id: int
    edition_id: int
    position: int
    title: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "list_id": self.list_id,
            "edition_id": self.edition_id,
            "position": self.position,
            "title": self.title,
        }


@dataclass(frozen=True, slots=True)
class ReadingAssignmentRecord:
    id: int
    list_id: int
    member_id: int
    assigned_at: str
    note: str | None
    member_name: str = ""
    school_number: str | None = None
    class_name: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "list_id": self.list_id,
            "member_id": self.member_id,
            "assigned_at": self.assigned_at,
            "note": self.note,
            "member_name": self.member_name,
            "school_number": self.school_number,
            "class_name": self.class_name,
        }


_LIST_SELECT = """
    SELECT rl.*, (SELECT COUNT(*) FROM reading_list_item WHERE list_id = rl.id) AS item_count
    FROM reading_list AS rl
"""

_ASSIGNMENT_SELECT = """
    SELECT ra.*, m.first_name, m.last_name, m.school_number, m.class_name
    FROM reading_assignment AS ra
    JOIN member AS m ON m.id = ra.member_id
"""


class ReadingLists:
    def __init__(self, database: Database) -> None:
        self.db = database

    # ── kayıt dönüştürme ─────────────────────────────

    @staticmethod
    def _list_record(row: sqlite3.Row) -> ReadingListRecord:
        return ReadingListRecord(
            id=int(row["id"]),
            name=row["name"],
            description=row["description"],
            is_opac_visible=bool(row["is_opac_visible"]),
            position=int(row["position"]),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            item_count=int(row["item_count"]),
        )

    @staticmethod
    def _item_record(row: sqlite3.Row) -> ReadingListItemRecord:
        keys = row.keys()
        return ReadingListItemRecord(
            id=int(row["id"]),
            list_id=int(row["list_id"]),
            edition_id=int(row["edition_id"]),
            position=int(row["position"]),
            title=row["title"] if "title" in keys else "",
        )

    @staticmethod
    def _assignment_record(row: sqlite3.Row) -> ReadingAssignmentRecord:
        return ReadingAssignmentRecord(
            id=int(row["id"]),
            list_id=int(row["list_id"]),
            member_id=int(row["member_id"]),
            assigned_at=row["assigned_at"],
            note=row["note"],
            member_name=f"{row['first_name']} {row['last_name']}".strip(),
            school_number=row["school_number"],
            class_name=row["class_name"],
        )

    def _get_in_connection(
        self, connection: sqlite3.Connection, list_id: int
    ) -> ReadingListRecord:
        row = connection.execute(_LIST_SELECT + " WHERE rl.id = ?", (list_id,)).fetchone()
        if row is None:
            raise KeyError("Liste bulunamadı")
        return self._list_record(row)

    # ── liste CRUD ───────────────────────────────────

    def get(self, list_id: int) -> ReadingListRecord:
        row = self.db.fetchone(_LIST_SELECT + " WHERE rl.id = ?", (list_id,))
        if row is None:
            raise KeyError("Liste bulunamadı")
        return self._list_record(row)

    def list_all(self) -> list[ReadingListRecord]:
        rows = self.db.fetchall(_LIST_SELECT + " ORDER BY rl.position, rl.id")
        return [self._list_record(row) for row in rows]

    def create(
        self,
        *,
        name: str,
        description: str | None = None,
        is_opac_visible: bool = False,
        now: datetime | None = None,
    ) -> ReadingListRecord:
        cleaned = (name or "").strip()
        if not cleaned:
            raise ValueError("Liste adı zorunludur")
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            next_position = connection.execute(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM reading_list"
            ).fetchone()[0]
            cursor = connection.execute(
                """
                INSERT INTO reading_list(
                    name, description, is_opac_visible, position, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    cleaned,
                    (description or "").strip() or None,
                    int(bool(is_opac_visible)),
                    int(next_position),
                    stamp,
                    stamp,
                ),
            )
            return self._get_in_connection(connection, int(cursor.lastrowid))

    def update(self, list_id: int, **fields: Any) -> ReadingListRecord:
        allowed = {"name", "description", "is_opac_visible", "position"}
        unknown = set(fields) - allowed
        if unknown:
            raise ValueError(f"Bilinmeyen alan: {', '.join(sorted(unknown))}")
        stamp = _stamp(_now_dt(None))
        with self.db.transaction(immediate=True) as connection:
            existing = connection.execute(
                "SELECT * FROM reading_list WHERE id = ?", (list_id,)
            ).fetchone()
            if existing is None:
                raise KeyError("Liste bulunamadı")
            name = fields.get("name", existing["name"])
            cleaned_name = str(name).strip()
            if not cleaned_name:
                raise ValueError("Liste adı boş olamaz")
            description = fields.get("description", existing["description"])
            is_opac_visible = fields.get("is_opac_visible", bool(existing["is_opac_visible"]))
            position = fields.get("position", existing["position"])
            connection.execute(
                """
                UPDATE reading_list
                SET name = ?, description = ?, is_opac_visible = ?, position = ?, updated_at = ?
                WHERE id = ?
                """,
                (
                    cleaned_name,
                    (str(description).strip() or None) if description else None,
                    int(bool(is_opac_visible)),
                    int(position),
                    stamp,
                    list_id,
                ),
            )
            return self._get_in_connection(connection, list_id)

    def delete(self, list_id: int) -> None:
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute("DELETE FROM reading_list WHERE id = ?", (list_id,))
            if cursor.rowcount == 0:
                raise KeyError("Liste bulunamadı")

    # ── kitap öğeleri ────────────────────────────────

    def list_items(self, list_id: int) -> list[ReadingListItemRecord]:
        rows = self.db.fetchall(
            """
            SELECT rli.*, e.title
            FROM reading_list_item AS rli
            JOIN edition AS e ON e.id = rli.edition_id
            WHERE rli.list_id = ?
            ORDER BY rli.position, rli.id
            """,
            (list_id,),
        )
        return [self._item_record(row) for row in rows]

    def add_item(self, list_id: int, edition_id: int) -> ReadingListItemRecord:
        with self.db.transaction(immediate=True) as connection:
            if connection.execute(
                "SELECT 1 FROM reading_list WHERE id = ?", (list_id,)
            ).fetchone() is None:
                raise KeyError("Liste bulunamadı")
            if connection.execute(
                "SELECT 1 FROM edition WHERE id = ?", (edition_id,)
            ).fetchone() is None:
                raise KeyError("Kitap bulunamadı")
            next_position = connection.execute(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM reading_list_item WHERE list_id = ?",
                (list_id,),
            ).fetchone()[0]
            try:
                cursor = connection.execute(
                    "INSERT INTO reading_list_item(list_id, edition_id, position) "
                    "VALUES (?, ?, ?)",
                    (list_id, edition_id, int(next_position)),
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError("Bu kitap zaten listede") from exc
            row = connection.execute(
                "SELECT rli.*, e.title FROM reading_list_item AS rli "
                "JOIN edition AS e ON e.id = rli.edition_id WHERE rli.id = ?",
                (int(cursor.lastrowid),),
            ).fetchone()
            assert row is not None
            return self._item_record(row)

    def remove_item(self, list_id: int, edition_id: int) -> None:
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                "DELETE FROM reading_list_item WHERE list_id = ? AND edition_id = ?",
                (list_id, edition_id),
            )
            if cursor.rowcount == 0:
                raise KeyError("Bu kitap listede değil")

    def reorder_items(self, list_id: int, edition_ids: list[int]) -> list[ReadingListItemRecord]:
        with self.db.transaction(immediate=True) as connection:
            if connection.execute(
                "SELECT 1 FROM reading_list WHERE id = ?", (list_id,)
            ).fetchone() is None:
                raise KeyError("Liste bulunamadı")
            current = {
                int(row["edition_id"])
                for row in connection.execute(
                    "SELECT edition_id FROM reading_list_item WHERE list_id = ?", (list_id,)
                ).fetchall()
            }
            if len(edition_ids) != len(set(edition_ids)) or set(edition_ids) != current:
                raise ValueError("Sıralama listesi mevcut kitaplarla birebir eşleşmeli")
            for position, edition_id in enumerate(edition_ids):
                connection.execute(
                    "UPDATE reading_list_item SET position = ? "
                    "WHERE list_id = ? AND edition_id = ?",
                    (position, list_id, edition_id),
                )
        return self.list_items(list_id)

    # ── üye atama ────────────────────────────────────

    def list_assignments(self, list_id: int) -> list[ReadingAssignmentRecord]:
        rows = self.db.fetchall(
            _ASSIGNMENT_SELECT + " WHERE ra.list_id = ? ORDER BY m.last_name, m.first_name",
            (list_id,),
        )
        return [self._assignment_record(row) for row in rows]

    def assign(
        self, list_id: int, member_id: int, *, note: str | None = None, now: datetime | None = None
    ) -> ReadingAssignmentRecord:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            if connection.execute(
                "SELECT 1 FROM reading_list WHERE id = ?", (list_id,)
            ).fetchone() is None:
                raise KeyError("Liste bulunamadı")
            if connection.execute(
                "SELECT 1 FROM member WHERE id = ?", (member_id,)
            ).fetchone() is None:
                raise KeyError("Üye bulunamadı")
            try:
                cursor = connection.execute(
                    "INSERT INTO reading_assignment(list_id, member_id, assigned_at, note) "
                    "VALUES (?, ?, ?, ?)",
                    (list_id, member_id, stamp, (note or "").strip() or None),
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError("Bu üye bu listeye zaten atanmış") from exc
            row = connection.execute(
                _ASSIGNMENT_SELECT + " WHERE ra.id = ?", (int(cursor.lastrowid),)
            ).fetchone()
            assert row is not None
            return self._assignment_record(row)

    def unassign(self, list_id: int, member_id: int) -> None:
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                "DELETE FROM reading_assignment WHERE list_id = ? AND member_id = ?",
                (list_id, member_id),
            )
            if cursor.rowcount == 0:
                raise KeyError("Bu üye bu listeye atanmamış")

    # ── ilerleme (türetilir, ayrı tablo yok) ──────────

    def progress(self, list_id: int, member_id: int) -> dict[str, Any]:
        # Açık BEGIN: bağlantılar autocommit (isolation_level=None) olduğu için
        # ardışık SELECT'ler kendiliğinden aynı anlık görüntüde DEĞİLDİR;
        # okuma transaction'ı olmadan araya giren bir yazma completed > total
        # gibi tutarsız bir çift üretebilir.
        with self.db.connection(readonly=True) as connection:
            own_txn = not connection.in_transaction
            if own_txn:
                connection.execute("BEGIN")
            total = int(
                connection.execute(
                    "SELECT COUNT(*) FROM reading_list_item WHERE list_id = ?", (list_id,)
                ).fetchone()[0]
            )
            try:
                completed_rows = connection.execute(
                    """
                    SELECT DISTINCT l.edition_id
                    FROM loan AS l
                    JOIN reading_list_item AS rli
                        ON rli.list_id = ? AND rli.edition_id = l.edition_id
                    WHERE l.member_id = ? AND l.returned_at IS NOT NULL
                    """,
                    (list_id, member_id),
                ).fetchall()
            finally:
                if own_txn:
                    connection.execute("COMMIT")
        completed = len(completed_rows)
        return {
            "list_id": list_id,
            "member_id": member_id,
            "total": total,
            "completed": completed,
            "fraction": (completed / total) if total > 0 else 0.0,
            "completed_edition_ids": [int(row["edition_id"]) for row in completed_rows],
        }

    def list_progress_bulk(self, list_id: int) -> list[dict[str, Any]]:
        """Listeye atanmış TÜM üyelerin ilerlemesi — tek bağlantı, tek sorgu.

        Üye başına ``progress()`` çağırmak her üye için yeni bir SQLite
        bağlantısı açar; 30 kişilik sınıf listesinde 60+ bağlantı döngüsü
        anlamına gelir. Burada toplam ve üye kırılımı aynı anlık görüntüden
        okunur.
        """

        with self.db.connection(readonly=True) as connection:
            # Açık BEGIN: toplam ile üye kırılımı aynı anlık görüntüden okunsun.
            own_txn = not connection.in_transaction
            if own_txn:
                connection.execute("BEGIN")
            total = int(
                connection.execute(
                    "SELECT COUNT(*) FROM reading_list_item WHERE list_id = ?", (list_id,)
                ).fetchone()[0]
            )
            rows = connection.execute(
                """
                SELECT ra.member_id,
                       m.first_name, m.last_name, m.school_number, m.class_name,
                       GROUP_CONCAT(DISTINCT l.edition_id) AS completed_ids
                FROM reading_assignment AS ra
                JOIN member AS m ON m.id = ra.member_id
                LEFT JOIN loan AS l
                    ON l.member_id = ra.member_id
                    AND l.returned_at IS NOT NULL
                    AND l.edition_id IN (
                        SELECT edition_id FROM reading_list_item
                        WHERE list_id = ra.list_id
                    )
                WHERE ra.list_id = ?
                GROUP BY ra.member_id
                ORDER BY m.last_name, m.first_name
                """,
                (list_id,),
            ).fetchall()
            if own_txn:
                connection.execute("COMMIT")
        entries = []
        for row in rows:
            completed_ids = sorted(
                int(value)
                for value in (row["completed_ids"] or "").split(",")
                if value
            )
            completed = len(completed_ids)
            entries.append(
                {
                    "list_id": list_id,
                    "member_id": int(row["member_id"]),
                    "member_name": f"{row['first_name']} {row['last_name']}".strip(),
                    "school_number": row["school_number"],
                    "class_name": row["class_name"],
                    "total": total,
                    "completed": completed,
                    "fraction": (completed / total) if total > 0 else 0.0,
                    "completed_edition_ids": completed_ids,
                }
            )
        return entries

    def member_progress(self, member_id: int) -> list[dict[str, Any]]:
        assignments = self.db.fetchall(
            "SELECT list_id FROM reading_assignment WHERE member_id = ? ORDER BY list_id",
            (member_id,),
        )
        results = []
        for row in assignments:
            list_id = int(row["list_id"])
            try:
                record = self.get(list_id)
            except KeyError:
                continue
            entry = self.progress(list_id, member_id)
            entry["list_name"] = record.name
            results.append(entry)
        return results

    # ── OPAC: üye verisi sızdırmadan yalnız katalog ───

    def opac_lists(self) -> list[dict[str, Any]]:
        lists = self.db.fetchall(
            _LIST_SELECT + " WHERE rl.is_opac_visible = 1 ORDER BY rl.position, rl.id"
        )
        out = []
        for row in lists:
            record = self._list_record(row)
            items = self.db.fetchall(
                """
                SELECT e.id AS edition_id, e.title, e.front_path
                FROM reading_list_item AS rli
                JOIN edition AS e ON e.id = rli.edition_id
                WHERE rli.list_id = ?
                ORDER BY rli.position, rli.id
                """,
                (record.id,),
            )
            out.append(
                {
                    "id": record.id,
                    "name": record.name,
                    "description": record.description,
                    "items": [
                        {
                            "edition_id": int(item["edition_id"]),
                            "title": item["title"],
                            "front_path": item["front_path"],
                        }
                        for item in items
                    ],
                }
            )
        return out

    # ── "100 Temel Eser" şablonu ───────────────────────

    def import_template(self, template: str, *, now: datetime | None = None) -> dict[str, Any]:
        if template != "100-temel-eser":
            raise KeyError("Bilinmeyen şablon")
        resource = files("kitapkatalog").joinpath(f"resources/{_TEMPLATE_RESOURCE}")
        titles = [
            line.strip() for line in resource.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        # ORDER BY id: eşit skorlu adaylar arasında en düşük edition_id kazanır
        # (deterministik tekrar-üretilebilirlik; SQLite satır sırası garanti değildir).
        editions = self.db.fetchall("SELECT id, title FROM edition ORDER BY id")
        folded_catalog = [(int(row["id"]), row["title"], fold_text(row["title"])) for row in editions]

        # Fuzzy eşleşme CPU işi: yazma kilidinin DIŞINDA hesaplanır. BEGIN
        # IMMEDIATE altında koşarsa 106 başlık × katalog taraması boyunca tüm
        # ödünç/iade işlemleri bloklanır (binlerce kitapta saniyeler sürer).
        proposals: list[tuple[str, int, str, float]] = []
        unmatched: list[str] = []
        for title in titles:
            folded_title = fold_text(title)
            best_score = 0.0
            best_edition: tuple[int, str] | None = None
            for edition_id, catalog_title, folded_catalog_title in folded_catalog:
                score = SequenceMatcher(None, folded_title, folded_catalog_title).ratio()
                if score > best_score:
                    best_score = score
                    best_edition = (edition_id, catalog_title)
            if best_edition is not None and best_score >= _TEMPLATE_MATCH_THRESHOLD:
                proposals.append((title, best_edition[0], best_edition[1], best_score))
            else:
                unmatched.append(title)

        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            existing = connection.execute(
                "SELECT id FROM reading_list WHERE name = ?", ("100 Temel Eser",)
            ).fetchone()
            if existing is not None:
                list_id = int(existing["id"])
            else:
                next_position = connection.execute(
                    "SELECT COALESCE(MAX(position), -1) + 1 FROM reading_list"
                ).fetchone()[0]
                cursor = connection.execute(
                    """
                    INSERT INTO reading_list(
                        name, description, is_opac_visible, position, created_at, updated_at
                    ) VALUES (?, ?, 0, ?, ?, ?)
                    """,
                    (
                        "100 Temel Eser",
                        "MEB tavsiyeli okuma listesinden katalogla eşleşen başlıklar.",
                        int(next_position),
                        stamp,
                        stamp,
                    ),
                )
                list_id = int(cursor.lastrowid)

            already_in_list = {
                int(row["edition_id"])
                for row in connection.execute(
                    "SELECT edition_id FROM reading_list_item WHERE list_id = ?", (list_id,)
                ).fetchall()
            }
            next_position = connection.execute(
                "SELECT COALESCE(MAX(position), -1) + 1 FROM reading_list_item WHERE list_id = ?",
                (list_id,),
            ).fetchone()[0]

            matched: list[dict[str, Any]] = []
            for title, edition_id, catalog_title, best_score in proposals:
                if edition_id not in already_in_list:
                    connection.execute(
                        "INSERT INTO reading_list_item(list_id, edition_id, position) "
                        "VALUES (?, ?, ?)",
                        (list_id, edition_id, int(next_position)),
                    )
                    next_position += 1
                    already_in_list.add(edition_id)
                matched.append(
                    {
                        "template_title": title,
                        "edition_id": edition_id,
                        "matched_title": catalog_title,
                        "score": round(best_score, 3),
                    }
                )

            record = self._get_in_connection(connection, list_id)
        return {"list": record.to_dict(), "matched": matched, "unmatched": unmatched}
