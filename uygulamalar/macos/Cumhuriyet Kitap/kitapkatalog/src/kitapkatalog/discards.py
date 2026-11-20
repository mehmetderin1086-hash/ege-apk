"""Düşüm defteri: nüshayı demirbaştan düşme, geri alma, MEB tutanak çıktısı.

Düşülen nüshanın satırı SİLİNMEZ; ``copy.status`` 'discarded' olur ve defter
kaydı ``discard_record``'a yazılır. Böylece hem geçmiş korunur hem de yanlış
düşüm tek hamlede geri alınabilir.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from kitapkatalog.database import Database, StateConflictError

REASONS = {
    "yipranma": "Yıpranma",
    "kayip": "Kayıp",
    "guncelligini_yitirme": "Güncelliğini yitirme",
    "diger": "Diğer",
}


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


@dataclass(frozen=True, slots=True)
class DiscardRecord:
    id: int
    copy_id: int | None
    edition_id: int | None
    title_snapshot: str
    inventory_code_snapshot: str | None
    reason: str
    note: str | None
    stocktake_session_id: int | None
    discarded_at: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "copy_id": self.copy_id,
            "edition_id": self.edition_id,
            "title": self.title_snapshot,
            "inventory_code": self.inventory_code_snapshot,
            "reason": self.reason,
            "reason_label": REASONS.get(self.reason, self.reason),
            "note": self.note,
            "stocktake_session_id": self.stocktake_session_id,
            "discarded_at": self.discarded_at,
        }


class Discards:
    def __init__(self, database: Database) -> None:
        self.db = database

    def discard_copy(
        self,
        copy_id: int,
        *,
        reason: str,
        note: str | None = None,
        stocktake_session_id: int | None = None,
    ) -> DiscardRecord:
        if reason not in REASONS:
            raise ValueError(f"Geçersiz gerekçe: {reason}; beklenen: {', '.join(REASONS)}")
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            record_id = self._discard_in_tx(
                connection, copy_id, reason, note, stocktake_session_id, now
            )
        record = self.get(record_id)
        assert record is not None
        return record

    def _discard_in_tx(
        self,
        connection: sqlite3.Connection,
        copy_id: int,
        reason: str,
        note: str | None,
        stocktake_session_id: int | None,
        now: str,
    ) -> int:
        row = connection.execute(
            """
            SELECT c.id, c.status, c.inventory_code, c.edition_id, e.title
            FROM copy AS c JOIN edition AS e ON e.id = c.edition_id
            WHERE c.id = ?
            """,
            (copy_id,),
        ).fetchone()
        if row is None:
            raise KeyError("Nüsha bulunamadı")
        if row["status"] == "discarded":
            raise StateConflictError("Bu nüsha zaten düşülmüş")
        loaned = connection.execute(
            "SELECT 1 FROM loan WHERE copy_id = ? AND returned_at IS NULL", (copy_id,)
        ).fetchone()
        if loaned is not None:
            raise StateConflictError("Nüsha aktif ödünçte; düşmeden önce iade alın")
        connection.execute(
            "UPDATE copy SET status = 'discarded' WHERE id = ?", (copy_id,)
        )
        # Bu nüshaya ayrılmış "hazır" rezervasyon varsa sıraya geri düşür:
        # düşülmüş nüsha teslim edilemez (asılsız bildirim zinciri ve sessiz
        # kuyruk erimesi yaşanmasın).
        reverted = connection.execute(
            """
            UPDATE hold
            SET status = 'active', ready_at = NULL, ready_copy_id = NULL,
                expires_at = NULL
            WHERE ready_copy_id = ? AND status = 'ready'
            """,
            (copy_id,),
        )
        if reverted.rowcount > 0:
            # Aynı baskının rafta bekleyen, ayrılmamış başka bir nüshası varsa
            # sırayı hemen ona devret — yoksa üçüncü bir üye o nüshayı kapıp
            # sıradaki üyenin önüne geçebilirdi.
            replacement = connection.execute(
                """
                SELECT c.id FROM copy AS c
                WHERE c.edition_id = ? AND c.status = 'active' AND c.id != ?
                  AND NOT EXISTS (
                      SELECT 1 FROM loan WHERE copy_id = c.id AND returned_at IS NULL
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM hold WHERE ready_copy_id = c.id AND status = 'ready'
                  )
                ORDER BY c.id LIMIT 1
                """,
                (int(row["edition_id"]), copy_id),
            ).fetchone()
            if replacement is not None:
                from kitapkatalog.loans import Loans
                from kitapkatalog.settings import AppSettings

                Loans(self.db, AppSettings(self.db)).promote_next_hold_in_connection(
                    connection,
                    edition_id=int(row["edition_id"]),
                    copy_id=int(replacement["id"]),
                )
        cursor = connection.execute(
            """
            INSERT INTO discard_record(copy_id, edition_id, title_snapshot,
                                       inventory_code_snapshot, reason, note,
                                       stocktake_session_id, discarded_at, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                copy_id,
                int(row["edition_id"]),
                row["title"],
                row["inventory_code"],
                reason,
                note,
                stocktake_session_id,
                now,
                now,
            ),
        )
        return int(cursor.lastrowid)

    def restore(self, discard_id: int) -> bool:
        """Yanlış düşümü geri alır: nüsha aktifleşir, defter kaydı silinir."""

        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT copy_id FROM discard_record WHERE id = ?", (discard_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Düşüm kaydı bulunamadı")
            if row["copy_id"] is None:
                raise StateConflictError(
                    "Nüsha kalıcı olarak silinmiş; düşüm geri alınamaz"
                )
            connection.execute(
                "UPDATE copy SET status = 'active' WHERE id = ?", (int(row["copy_id"]),)
            )
            connection.execute("DELETE FROM discard_record WHERE id = ?", (discard_id,))
        return True

    def bulk_from_stocktake(self, session_id: int) -> dict[str, Any]:
        """Sayım raporundaki eksikleri toplu düşüme çevirir.

        Eksik sayısı edition düzeyinde bilinir; hangi nüshanın kayıp olduğu
        (etiket olmadığından) kesin değildir. Demirbaş okutmasıyla rafta
        görülen nüshalar korunur, kalanlardan okutulmayanlar düşülür.
        """

        from kitapkatalog.stocktake import Stocktake

        stocktake = Stocktake(self.db)
        session = stocktake.get_session(session_id)
        if session is None:
            raise KeyError("Sayım oturumu bulunamadı")
        if session.status != "closed":
            raise StateConflictError(
                "Toplu düşüm için önce sayım oturumunu kapatın; "
                "açık oturumda rapor değişmeye devam eder"
            )
        report = stocktake.report(session_id)
        now = _now()
        discarded = 0
        errors: list[str] = []
        note = f"'{session.name}' sayımında bulunamadı"
        with self.db.transaction(immediate=True) as connection:
            for line in report["lines"]:
                if line["missing"] <= 0:
                    continue
                # Rapor ile bu kilit arasında ödünç/iade değişmiş olabilir;
                # eksik sayısını aynı transaction içinde CANLI yeniden hesapla.
                live = stocktake._edition_tally(
                    connection, session_id, line["edition_id"], session.scope_location
                )
                if live["missing"] <= 0:
                    continue
                line = {**line, "missing": live["missing"]}
                seen_copy_ids = {
                    int(row["copy_id"])
                    for row in connection.execute(
                        """
                        SELECT copy_id FROM stocktake_scan
                        WHERE session_id = ? AND edition_id = ? AND copy_id IS NOT NULL
                        """,
                        (session_id, line["edition_id"]),
                    )
                }
                scope_clause = "AND c.location = ?" if session.scope_location else ""
                params: list[Any] = [line["edition_id"]]
                if session.scope_location:
                    params.append(session.scope_location)
                candidates = [
                    int(row["id"])
                    for row in connection.execute(
                        f"""
                        SELECT c.id FROM copy AS c
                        WHERE c.edition_id = ? AND c.status = 'active' {scope_clause}
                          AND NOT EXISTS(
                              SELECT 1 FROM loan
                              WHERE copy_id = c.id AND returned_at IS NULL
                          )
                        ORDER BY c.id DESC
                        """,
                        params,
                    )
                    if int(row["id"]) not in seen_copy_ids
                ]
                for copy_id in candidates[: line["missing"]]:
                    try:
                        self._discard_in_tx(connection, copy_id, "kayip", note, session_id, now)
                        discarded += 1
                    except StateConflictError as exc:
                        errors.append(f"{line['title']}: {exc}")
        return {"discarded": discarded, "errors": errors}

    def get(self, discard_id: int) -> DiscardRecord | None:
        row = self.db.fetchone("SELECT * FROM discard_record WHERE id = ?", (discard_id,))
        return self._record(row) if row is not None else None

    def list_discards(
        self, *, limit: int = 100, offset: int = 0
    ) -> tuple[list[DiscardRecord], int]:
        total_row = self.db.fetchone("SELECT COUNT(*) FROM discard_record")
        rows = self.db.fetchall(
            "SELECT * FROM discard_record ORDER BY discarded_at DESC, id DESC LIMIT ? OFFSET ?",
            (max(1, min(int(limit), 500)), max(0, int(offset))),
        )
        return [self._record(row) for row in rows], int(total_row[0]) if total_row else 0

    def export_tutanak_xlsx(self, destination: Path | str) -> Path:
        from openpyxl import Workbook

        from kitapkatalog.exporters import protect_spreadsheet_value as safe

        items, _ = self.list_discards(limit=500, offset=0)
        # Tutanak tüm kayıtları kapsar; 500'den fazlası için sayfalayarak çek.
        offset = 500
        while True:
            page, _total = self.list_discards(limit=500, offset=offset)
            if not page:
                break
            items.extend(page)
            offset += 500
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        workbook = Workbook(write_only=True)
        sheet = workbook.create_sheet("Düşüm Tutanağı")
        sheet.append(["Sıra", "Demirbaş No", "Eser Adı", "Gerekçe", "Açıklama", "Tarih"])
        for index, record in enumerate(items, start=1):
            sheet.append(
                [
                    index,
                    safe(record.inventory_code_snapshot),
                    safe(record.title_snapshot),
                    REASONS.get(record.reason, record.reason),
                    safe(record.note),
                    record.discarded_at[:10],
                ]
            )
        workbook.save(destination)
        return destination

    @staticmethod
    def _record(row: sqlite3.Row) -> DiscardRecord:
        return DiscardRecord(
            id=int(row["id"]),
            copy_id=int(row["copy_id"]) if row["copy_id"] is not None else None,
            edition_id=int(row["edition_id"]) if row["edition_id"] is not None else None,
            title_snapshot=row["title_snapshot"],
            inventory_code_snapshot=row["inventory_code_snapshot"],
            reason=row["reason"],
            note=row["note"],
            stocktake_session_id=(
                int(row["stocktake_session_id"])
                if row["stocktake_session_id"] is not None
                else None
            ),
            discarded_at=row["discarded_at"],
        )
