"""Okuma yarışması servisi: yarışma CRUD, sıralama (standings), sertifika sicili.

Sıralama ayrı bir puan tablosunda TUTULMAZ; dönem içinde (``start_date`` ≤
``loaned_at`` tarihi ≤ ``end_date``) verilip İADE EDİLMİŞ (``returned_at NOT
NULL``) ödünç sayısı ``loan`` defterinden her çağrıda türetilir.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import UTC, date, datetime
from typing import Any

from kitapkatalog.database import Database


def _now_dt(now: datetime | None) -> datetime:
    return now if now is not None else datetime.now(UTC).astimezone()


def _validate_date(value: str, field: str) -> str:
    text = str(value)
    try:
        date.fromisoformat(text)
    except ValueError as exc:
        raise ValueError(f"{field} 'YYYY-MM-DD' biçiminde geçerli bir tarih olmalı") from exc
    return text


def _stamp(now: datetime) -> str:
    return now.isoformat(timespec="microseconds")


@dataclass(frozen=True, slots=True)
class ChallengeRecord:
    id: int
    name: str
    start_date: str
    end_date: str
    target_books: int
    scope: str
    class_name: str | None
    status: str
    created_at: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "start_date": self.start_date,
            "end_date": self.end_date,
            "target_books": self.target_books,
            "scope": self.scope,
            "class_name": self.class_name,
            "status": self.status,
            "created_at": self.created_at,
        }


class Challenges:
    def __init__(self, database: Database) -> None:
        self.db = database

    @staticmethod
    def _record(row: sqlite3.Row) -> ChallengeRecord:
        return ChallengeRecord(
            id=int(row["id"]),
            name=row["name"],
            start_date=row["start_date"],
            end_date=row["end_date"],
            target_books=int(row["target_books"]),
            scope=row["scope"],
            class_name=row["class_name"],
            status=row["status"],
            created_at=row["created_at"],
        )

    def get(self, challenge_id: int) -> ChallengeRecord:
        row = self.db.fetchone("SELECT * FROM reading_challenge WHERE id = ?", (challenge_id,))
        if row is None:
            raise KeyError("Yarışma bulunamadı")
        return self._record(row)

    def list_all(self, *, status: str | None = None) -> list[ChallengeRecord]:
        if status is not None:
            rows = self.db.fetchall(
                "SELECT * FROM reading_challenge WHERE status = ? "
                "ORDER BY start_date DESC, id DESC",
                (status,),
            )
        else:
            rows = self.db.fetchall(
                "SELECT * FROM reading_challenge ORDER BY start_date DESC, id DESC"
            )
        return [self._record(row) for row in rows]

    def create(
        self,
        *,
        name: str,
        start_date: str,
        end_date: str,
        target_books: int,
        scope: str = "all",
        class_name: str | None = None,
        now: datetime | None = None,
    ) -> ChallengeRecord:
        cleaned = (name or "").strip()
        if not cleaned:
            raise ValueError("Yarışma adı zorunludur")
        if scope not in ("all", "class"):
            raise ValueError("scope 'all' veya 'class' olmalı")
        if scope == "class" and not (class_name or "").strip():
            raise ValueError("scope 'class' ise class_name zorunludur")
        if int(target_books) <= 0:
            raise ValueError("target_books pozitif olmalı")
        start_date = _validate_date(start_date, "start_date")
        end_date = _validate_date(end_date, "end_date")
        if start_date > end_date:
            raise ValueError("start_date, end_date'den sonra olamaz")
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                INSERT INTO reading_challenge(
                    name, start_date, end_date, target_books, scope, class_name,
                    status, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, 'active', ?)
                """,
                (
                    cleaned,
                    str(start_date),
                    str(end_date),
                    int(target_books),
                    scope,
                    (class_name or "").strip() or None if scope == "class" else None,
                    stamp,
                ),
            )
            challenge_id = int(cursor.lastrowid)
            row = connection.execute(
                "SELECT * FROM reading_challenge WHERE id = ?", (challenge_id,)
            ).fetchone()
            assert row is not None
            return self._record(row)

    def update(self, challenge_id: int, **fields: Any) -> ChallengeRecord:
        allowed = {
            "name", "start_date", "end_date", "target_books", "scope", "class_name", "status",
        }
        unknown = set(fields) - allowed
        if unknown:
            raise ValueError(f"Bilinmeyen alan: {', '.join(sorted(unknown))}")
        with self.db.transaction(immediate=True) as connection:
            existing = connection.execute(
                "SELECT * FROM reading_challenge WHERE id = ?", (challenge_id,)
            ).fetchone()
            if existing is None:
                raise KeyError("Yarışma bulunamadı")
            name = str(fields.get("name", existing["name"])).strip()
            if not name:
                raise ValueError("Yarışma adı boş olamaz")
            start_date = _validate_date(
                fields.get("start_date", existing["start_date"]), "start_date"
            )
            end_date = _validate_date(fields.get("end_date", existing["end_date"]), "end_date")
            if start_date > end_date:
                raise ValueError("start_date, end_date'den sonra olamaz")
            target_books = int(fields.get("target_books", existing["target_books"]))
            if target_books <= 0:
                raise ValueError("target_books pozitif olmalı")
            scope = fields.get("scope", existing["scope"])
            if scope not in ("all", "class"):
                raise ValueError("scope 'all' veya 'class' olmalı")
            class_name = fields.get("class_name", existing["class_name"])
            if scope == "class" and not (class_name or "").strip():
                raise ValueError("scope 'class' ise class_name zorunludur")
            if scope != "class":
                class_name = None
            status = fields.get("status", existing["status"])
            if status not in ("active", "archived"):
                raise ValueError("status 'active' veya 'archived' olmalı")
            connection.execute(
                """
                UPDATE reading_challenge
                SET name = ?, start_date = ?, end_date = ?, target_books = ?, scope = ?,
                    class_name = ?, status = ?
                WHERE id = ?
                """,
                (
                    name, start_date, end_date, target_books, scope,
                    (str(class_name).strip() or None) if class_name else None,
                    status, challenge_id,
                ),
            )
            row = connection.execute(
                "SELECT * FROM reading_challenge WHERE id = ?", (challenge_id,)
            ).fetchone()
            assert row is not None
            return self._record(row)

    def archive(self, challenge_id: int) -> ChallengeRecord:
        return self.update(challenge_id, status="archived")

    # ── sıralama (türetilir) ───────────────────────────

    def standings(self, challenge_id: int) -> dict[str, Any]:
        challenge = self.get(challenge_id)
        member_where = "WHERE is_active = 1"
        if challenge.scope == "class":
            member_where += " AND class_name = ?"
            params_members: list[Any] = [challenge.class_name]
        else:
            params_members = []
        # Üye listesi ve ödünç sayıları aynı anlık görüntüden okunur; aralarına
        # bir checkout/return girip sıralamayı tutarsız bir çift üretmesin diye.
        with self.db.connection(readonly=True) as connection:
            # Açık BEGIN: üye kümesi ile skorlar aynı anlık görüntüden okunsun
            # (autocommit bağlantıda ardışık SELECT'ler farklı snapshot görebilir).
            own_txn = not connection.in_transaction
            if own_txn:
                connection.execute("BEGIN")
            members = connection.execute(
                f"SELECT id, first_name, last_name, school_number, class_name FROM member "
                f"{member_where} ORDER BY last_name, first_name",
                params_members,
            ).fetchall()
            # DISTINCT edition: aynı kitabı beş kez alıp iade etmek beş puan
            # saymaz — yarışma FARKLI kitap okumayı ödüllendirir. Dönem
            # penceresi ödünç ALMA tarihine bakar; dönem içinde alınıp dönem
            # bittikten sonra iade edilen kitap da sayılır (bilinçli tercih:
            # dönem sonunda elindeki kitabı bitiren öğrenci cezalandırılmaz).
            counts_rows = connection.execute(
                """
                SELECT member_id, COUNT(DISTINCT edition_id) AS count
                FROM loan
                WHERE returned_at IS NOT NULL
                  AND substr(loaned_at, 1, 10) BETWEEN ? AND ?
                GROUP BY member_id
                """,
                (challenge.start_date, challenge.end_date),
            ).fetchall()
            if own_txn:
                connection.execute("COMMIT")
        counts = {int(row["member_id"]): int(row["count"]) for row in counts_rows}

        standings_list = []
        for member in members:
            member_id = int(member["id"])
            book_count = counts.get(member_id, 0)
            standings_list.append(
                {
                    "member_id": member_id,
                    "member_name": f"{member['first_name']} {member['last_name']}".strip(),
                    "school_number": member["school_number"],
                    "class_name": member["class_name"],
                    "book_count": book_count,
                    "reached_target": book_count >= challenge.target_books,
                }
            )
        standings_list.sort(key=lambda item: (-item["book_count"], item["member_name"]))

        class_totals: dict[str, dict[str, int]] = {}
        for entry in standings_list:
            label = entry["class_name"] or "Sınıfsız"
            bucket = class_totals.setdefault(label, {"total": 0, "member_count": 0})
            bucket["total"] += entry["book_count"]
            bucket["member_count"] += 1
        class_league = [
            {
                "class_name": label,
                "total_books": data["total"],
                "member_count": data["member_count"],
                "average": round(data["total"] / data["member_count"], 2)
                if data["member_count"] > 0 else 0.0,
            }
            for label, data in class_totals.items()
        ]
        class_league.sort(key=lambda item: -item["total_books"])

        return {
            "challenge": challenge.to_dict(),
            "standings": standings_list,
            "class_league": class_league,
        }

    # ── sertifika sicili ───────────────────────────────

    def record_certificate(
        self, challenge_id: int, member_id: int, *, rank: int | None = None,
        now: datetime | None = None,
    ) -> dict[str, Any]:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            if connection.execute(
                "SELECT 1 FROM reading_challenge WHERE id = ?", (challenge_id,)
            ).fetchone() is None:
                raise KeyError("Yarışma bulunamadı")
            if connection.execute(
                "SELECT 1 FROM member WHERE id = ?", (member_id,)
            ).fetchone() is None:
                raise KeyError("Üye bulunamadı")
            connection.execute(
                """
                INSERT INTO challenge_certificate(challenge_id, member_id, rank, printed_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(challenge_id, member_id)
                DO UPDATE SET rank = excluded.rank, printed_at = excluded.printed_at
                """,
                (challenge_id, member_id, rank, stamp),
            )
            row = connection.execute(
                "SELECT * FROM challenge_certificate WHERE challenge_id = ? AND member_id = ?",
                (challenge_id, member_id),
            ).fetchone()
            assert row is not None
            return {
                "id": int(row["id"]),
                "challenge_id": int(row["challenge_id"]),
                "member_id": int(row["member_id"]),
                "rank": row["rank"],
                "printed_at": row["printed_at"],
            }

    def list_certificates(self, challenge_id: int) -> list[dict[str, Any]]:
        rows = self.db.fetchall(
            "SELECT * FROM challenge_certificate WHERE challenge_id = ? ORDER BY rank",
            (challenge_id,),
        )
        return [
            {
                "id": int(row["id"]),
                "challenge_id": int(row["challenge_id"]),
                "member_id": int(row["member_id"]),
                "rank": row["rank"],
                "printed_at": row["printed_at"],
            }
            for row in rows
        ]
