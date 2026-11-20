"""Bildirim merkezi: hold hazır, gecikme, yedek hatası.

``enqueue`` bir bağlantı üzerinde çalışır (staticmethod) ki ``loans.py`` gibi
başka modüller kendi transaction'ları İÇİNDE bildirim yazabilsin (ör. iade
işleminin aynı atomik biriminde hold hazır bildirimi). ``dedupe_key`` UNIQUE
sütunu tekrar üretimi sessizce yutar (``ON CONFLICT ... DO NOTHING``); günlük
bakım aynı taramayı iki kez çalıştırsa bile bildirim çoğalmaz.
"""

from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from typing import Any

from kitapkatalog.database import Database


def _now_dt(now: datetime | None) -> datetime:
    return now if now is not None else datetime.now(UTC).astimezone()


def _stamp(now: datetime) -> str:
    return now.isoformat(timespec="microseconds")


class Notifications:
    def __init__(self, database: Database) -> None:
        self.db = database

    @staticmethod
    def enqueue(
        connection: sqlite3.Connection,
        *,
        kind: str,
        member_id: int | None,
        ref_kind: str | None,
        ref_id: int | None,
        title: str,
        body: str | None,
        dedupe_key: str | None,
        now: datetime | None = None,
    ) -> None:
        connection.execute(
            """
            INSERT INTO notification(
                kind, member_id, ref_kind, ref_id, title, body, created_at, dedupe_key
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(dedupe_key) DO NOTHING
            """,
            (kind, member_id, ref_kind, ref_id, title, body, _stamp(_now_dt(now)), dedupe_key),
        )

    def create(
        self,
        *,
        kind: str,
        member_id: int | None = None,
        ref_kind: str | None = None,
        ref_id: int | None = None,
        title: str,
        body: str | None = None,
        dedupe_key: str | None = None,
        now: datetime | None = None,
    ) -> None:
        with self.db.transaction(immediate=True) as connection:
            self.enqueue(
                connection,
                kind=kind,
                member_id=member_id,
                ref_kind=ref_kind,
                ref_id=ref_id,
                title=title,
                body=body,
                dedupe_key=dedupe_key,
                now=now,
            )

    def list(
        self, *, unread: bool = False, limit: int = 50, offset: int = 0
    ) -> tuple[list[dict[str, Any]], int]:
        clause = "WHERE dismissed_at IS NULL"
        if unread:
            clause += " AND read_at IS NULL"
        limit = max(1, min(int(limit), 200))
        offset = max(0, int(offset))
        with self.db.connection(readonly=True) as connection:
            total = int(
                connection.execute(f"SELECT COUNT(*) FROM notification {clause}").fetchone()[0]
            )
            rows = connection.execute(
                f"""
                SELECT * FROM notification {clause}
                ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?
                """,
                (limit, offset),
            ).fetchall()
        return [self._to_dict(row) for row in rows], total

    def unread_count(self) -> int:
        row = self.db.fetchone(
            "SELECT COUNT(*) FROM notification WHERE read_at IS NULL AND dismissed_at IS NULL"
        )
        return int(row[0]) if row is not None else 0

    def mark_read(self, notification_id: int, *, now: datetime | None = None) -> dict[str, Any]:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT * FROM notification WHERE id = ?", (notification_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Bildirim bulunamadı")
            if row["read_at"] is None:
                connection.execute(
                    "UPDATE notification SET read_at = ? WHERE id = ?", (stamp, notification_id)
                )
            updated = connection.execute(
                "SELECT * FROM notification WHERE id = ?", (notification_id,)
            ).fetchone()
        return self._to_dict(updated)

    def mark_all_read(self, *, now: datetime | None = None) -> int:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                "UPDATE notification SET read_at = ? WHERE read_at IS NULL AND dismissed_at IS NULL",
                (stamp,),
            )
            return int(cursor.rowcount)

    def dismiss(self, notification_id: int, *, now: datetime | None = None) -> None:
        stamp = _stamp(_now_dt(now))
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT id FROM notification WHERE id = ?", (notification_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Bildirim bulunamadı")
            connection.execute(
                "UPDATE notification SET dismissed_at = ? WHERE id = ?", (stamp, notification_id)
            )

    @staticmethod
    def _to_dict(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": int(row["id"]),
            "kind": row["kind"],
            "member_id": row["member_id"],
            "ref_kind": row["ref_kind"],
            "ref_id": row["ref_id"],
            "title": row["title"],
            "body": row["body"],
            "created_at": row["created_at"],
            "read_at": row["read_at"],
            "dismissed_at": row["dismissed_at"],
        }
