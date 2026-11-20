"""Sayım (stocktake) servisi.

Etiketsiz kütüphane için tasarım: okutmalar edition düzeyinde ADET olarak
sayılır (aynı ISBN'den kaç nüsha kayıtlı ↔ kaç kez okutuldu), demirbaş
numarası okutulursa nüsha da bağlanır. Her okutma değişmez bir olay olarak
loglanır; beklenen adetler rapor ANINDA canlı hesaplanır ve rapor üretim
zamanı damgası taşır.
"""

from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from kitapkatalog.codes import resolve_catalog_code
from kitapkatalog.database import Database, StateConflictError


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


@dataclass(frozen=True, slots=True)
class StocktakeSession:
    id: int
    name: str
    scope_location: str | None
    status: str
    started_at: str
    closed_at: str | None
    notes: str | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "scope_location": self.scope_location,
            "status": self.status,
            "started_at": self.started_at,
            "closed_at": self.closed_at,
            "notes": self.notes,
        }


class Stocktake:
    def __init__(self, database: Database) -> None:
        self.db = database

    # ── Oturum yaşam döngüsü ────────────────────────────────────────

    def open_session(self, name: str, *, scope_location: str | None = None) -> StocktakeSession:
        name = (name or "").strip() or f"Sayım {datetime.now(UTC).date().isoformat()}"
        scope = (scope_location or "").strip() or None
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                INSERT INTO stocktake_session(name, scope_location, started_at,
                                              created_at, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (name, scope, now, now, now),
            )
            session_id = int(cursor.lastrowid)
        session = self.get_session(session_id)
        assert session is not None
        return session

    def get_session(self, session_id: int) -> StocktakeSession | None:
        row = self.db.fetchone(
            "SELECT * FROM stocktake_session WHERE id = ?", (session_id,)
        )
        return self._session(row) if row is not None else None

    def list_sessions(self, *, limit: int = 50) -> list[StocktakeSession]:
        rows = self.db.fetchall(
            """
            SELECT * FROM stocktake_session
            ORDER BY CASE status WHEN 'open' THEN 0 ELSE 1 END, started_at DESC
            LIMIT ?
            """,
            (max(1, min(int(limit), 200)),),
        )
        return [self._session(row) for row in rows]

    def close_session(self, session_id: int) -> StocktakeSession:
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT status FROM stocktake_session WHERE id = ?", (session_id,)
            ).fetchone()
            if row is None:
                raise KeyError("Sayım oturumu bulunamadı")
            if row["status"] != "open":
                raise StateConflictError("Oturum zaten kapatılmış")
            connection.execute(
                """
                UPDATE stocktake_session
                SET status = 'closed', closed_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (now, now, session_id),
            )
        session = self.get_session(session_id)
        assert session is not None
        return session

    # ── Okutma ──────────────────────────────────────────────────────

    def record_scan(
        self,
        session_id: int,
        raw_code: str,
        *,
        manual_edition_id: int | None = None,
    ) -> dict[str, Any]:
        raw_code = (raw_code or "").strip()
        if not raw_code and manual_edition_id is None:
            raise ValueError("Kod boş olamaz")
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            session = connection.execute(
                "SELECT status, scope_location FROM stocktake_session WHERE id = ?",
                (session_id,),
            ).fetchone()
            if session is None:
                raise KeyError("Sayım oturumu bulunamadı")
            if session["status"] != "open":
                raise StateConflictError("Oturum kapalı; okutma kaydedilemez")

            code_type, edition_id, copy_id = self._resolve(connection, raw_code, manual_edition_id)

            if code_type == "inventory" and copy_id is not None:
                # Nüsha düzeyinde tekilleştirme: aynı demirbaşın ikinci okutması
                # adet sayacını şişirip gerçek kaybı maskeler — kaydedilmez.
                duplicate = connection.execute(
                    "SELECT 1 FROM stocktake_scan WHERE session_id = ? AND copy_id = ?",
                    (session_id, copy_id),
                ).fetchone()
                if duplicate is not None:
                    tally = self._edition_tally(
                        connection, session_id, edition_id, session["scope_location"]
                    )
                    return {
                        "scan_id": None,
                        "code_type": code_type,
                        "edition_id": edition_id,
                        "copy_id": copy_id,
                        "raw_code": raw_code,
                        "duplicate": True,
                        **tally,
                    }
                if session["scope_location"]:
                    # Kapsam dışı demirbaş bu oturumun eksiğini kapatmamalı.
                    location = connection.execute(
                        "SELECT location FROM copy WHERE id = ?", (copy_id,)
                    ).fetchone()
                    if location is not None and location["location"] != session["scope_location"]:
                        tally = self._edition_tally(
                            connection, session_id, edition_id, session["scope_location"]
                        )
                        return {
                            "scan_id": None,
                            "code_type": code_type,
                            "edition_id": edition_id,
                            "copy_id": copy_id,
                            "raw_code": raw_code,
                            "out_of_scope": True,
                            "copy_location": location["location"],
                            **tally,
                        }

            cursor = connection.execute(
                """
                INSERT INTO stocktake_scan(session_id, raw_code, code_type,
                                           edition_id, copy_id, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (session_id, raw_code or "(elle)", code_type, edition_id, copy_id, now),
            )
            scan_id = int(cursor.lastrowid)

            result: dict[str, Any] = {
                "scan_id": scan_id,
                "code_type": code_type,
                "edition_id": edition_id,
                "copy_id": copy_id,
                "raw_code": raw_code,
                "title": None,
            }
            if edition_id is not None:
                tally = self._edition_tally(
                    connection, session_id, edition_id, session["scope_location"]
                )
                result.update(tally)
        return result

    def undo_scan(self, scan_id: int) -> bool:
        with self.db.transaction(immediate=True) as connection:
            row = connection.execute(
                """
                SELECT s.status FROM stocktake_scan AS sc
                JOIN stocktake_session AS s ON s.id = sc.session_id
                WHERE sc.id = ?
                """,
                (scan_id,),
            ).fetchone()
            if row is None:
                return False
            if row["status"] != "open":
                raise StateConflictError("Oturum kapalı; okutma geri alınamaz")
            return (
                connection.execute(
                    "DELETE FROM stocktake_scan WHERE id = ?", (scan_id,)
                ).rowcount
                == 1
            )

    def recent_scans(self, session_id: int, *, limit: int = 20) -> list[dict[str, Any]]:
        rows = self.db.fetchall(
            """
            SELECT sc.id AS scan_id, sc.raw_code, sc.code_type, sc.edition_id,
                   sc.copy_id, sc.created_at, e.title
            FROM stocktake_scan AS sc
            LEFT JOIN edition AS e ON e.id = sc.edition_id
            WHERE sc.session_id = ?
            ORDER BY sc.id DESC LIMIT ?
            """,
            (session_id, max(1, min(int(limit), 100))),
        )
        return [dict(row) for row in rows]

    @staticmethod
    def _resolve(
        connection: sqlite3.Connection, raw_code: str, manual_edition_id: int | None
    ) -> tuple[str, int | None, int | None]:
        if manual_edition_id is not None:
            exists = connection.execute(
                "SELECT 1 FROM edition WHERE id = ?", (manual_edition_id,)
            ).fetchone()
            if exists is None:
                raise KeyError("İşaretlenecek kitap bulunamadı")
            return "manual", int(manual_edition_id), None
        resolved = resolve_catalog_code(connection, raw_code)
        return resolved.kind, resolved.edition_id, resolved.copy_id

    # ── Rapor ───────────────────────────────────────────────────────

    @staticmethod
    def _scope_filter(scope: str | None) -> tuple[str, list[Any]]:
        if scope:
            return "AND c.location = ?", [scope]
        return "", []

    def _edition_tally(
        self,
        connection: sqlite3.Connection,
        session_id: int,
        edition_id: int,
        scope: str | None,
    ) -> dict[str, Any]:
        clause, params = self._scope_filter(scope)
        row = connection.execute(
            f"""
            SELECT
                (SELECT title FROM edition WHERE id = :eid) AS title,
                (SELECT COUNT(*) FROM copy AS c
                 WHERE c.edition_id = :eid AND c.status = 'active' {clause.replace('?', ':scope')}) AS expected,
                (SELECT COUNT(*) FROM copy AS c
                 JOIN loan AS l ON l.copy_id = c.id AND l.returned_at IS NULL
                 WHERE c.edition_id = :eid AND c.status = 'active' {clause.replace('?', ':scope')}) AS on_loan,
                (SELECT COUNT(*) FROM stocktake_scan
                 WHERE session_id = :sid AND edition_id = :eid) AS scanned
            """,
            {"eid": edition_id, "sid": session_id, "scope": params[0] if params else None},
        ).fetchone()
        expected = int(row["expected"])
        on_loan = int(row["on_loan"])
        scanned = int(row["scanned"])
        shelf = max(0, expected - on_loan)
        return {
            "title": row["title"],
            "expected": expected,
            "on_loan": on_loan,
            "scanned": scanned,
            "missing": max(0, shelf - scanned),
            "surplus": max(0, scanned - shelf),
        }

    def report(self, session_id: int) -> dict[str, Any]:
        session = self.get_session(session_id)
        if session is None:
            raise KeyError("Sayım oturumu bulunamadı")
        scope = session.scope_location
        clause, params = self._scope_filter(scope)
        with self.db.connection(readonly=True) as connection:
            rows = connection.execute(
                f"""
                SELECT e.id AS edition_id, e.title,
                       COUNT(c.id) AS expected,
                       SUM(CASE WHEN l.id IS NOT NULL THEN 1 ELSE 0 END) AS on_loan,
                       EXISTS(SELECT 1 FROM identifier WHERE edition_id = e.id) AS has_isbn
                FROM edition AS e
                JOIN copy AS c ON c.edition_id = e.id AND c.status = 'active' {clause}
                LEFT JOIN loan AS l ON l.copy_id = c.id AND l.returned_at IS NULL
                GROUP BY e.id
                """,
                params,
            ).fetchall()
            scanned_rows = connection.execute(
                """
                SELECT edition_id, COUNT(*) AS scanned
                FROM stocktake_scan
                WHERE session_id = ? AND edition_id IS NOT NULL
                GROUP BY edition_id
                """,
                (session_id,),
            ).fetchall()
            scanned_by_edition = {
                int(row["edition_id"]): int(row["scanned"]) for row in scanned_rows
            }
            unresolved = connection.execute(
                """
                SELECT id AS scan_id, raw_code, created_at FROM stocktake_scan
                WHERE session_id = ? AND edition_id IS NULL
                ORDER BY id
                """,
                (session_id,),
            ).fetchall()
            loaned_detail = connection.execute(
                f"""
                SELECT e.title, c.inventory_code, l.due_at,
                       m.first_name || ' ' || m.last_name AS member_name,
                       m.class_name
                FROM copy AS c
                JOIN loan AS l ON l.copy_id = c.id AND l.returned_at IS NULL
                JOIN member AS m ON m.id = l.member_id
                JOIN edition AS e ON e.id = c.edition_id
                WHERE c.status = 'active' {clause}
                ORDER BY e.title COLLATE NOCASE
                """,
                params,
            ).fetchall()
            # Kapsamda hiç kaydı olmayan ama okutulmuş baskılar (beklenmedik).
            known = {int(row["edition_id"]) for row in rows}
            extra_ids = [eid for eid in scanned_by_edition if eid not in known]
            extra_titles: dict[int, str] = {}
            if extra_ids:
                marks = ",".join("?" for _ in extra_ids)
                for row in connection.execute(
                    f"SELECT id, title FROM edition WHERE id IN ({marks})", extra_ids
                ):
                    extra_titles[int(row["id"])] = row["title"]

        lines: list[dict[str, Any]] = []
        manual_check: list[dict[str, Any]] = []
        for row in rows:
            edition_id = int(row["edition_id"])
            expected = int(row["expected"])
            on_loan = int(row["on_loan"] or 0)
            scanned = scanned_by_edition.get(edition_id, 0)
            shelf = max(0, expected - on_loan)
            line = {
                "edition_id": edition_id,
                "title": row["title"],
                "expected": expected,
                "on_loan": on_loan,
                "scanned": scanned,
                "missing": max(0, shelf - scanned),
                "surplus": max(0, scanned - shelf),
            }
            if not row["has_isbn"] and scanned == 0:
                # ISBN'siz ve hiç okutulmamış: barkodla bulunması imkânsız;
                # sessizce "eksik" damgalamak yerine elle sayım listesine koy.
                manual_check.append(line)
            else:
                lines.append(line)
        for edition_id in extra_ids:
            scanned = scanned_by_edition[edition_id]
            lines.append(
                {
                    "edition_id": edition_id,
                    "title": extra_titles.get(edition_id, "bilinmiyor"),
                    "expected": 0,
                    "on_loan": 0,
                    "scanned": scanned,
                    "missing": 0,
                    "surplus": scanned,
                }
            )
        lines.sort(key=lambda item: (-item["missing"], -item["surplus"], item["title"] or ""))
        totals = {
            "expected": sum(line["expected"] for line in lines + manual_check),
            "on_loan": sum(line["on_loan"] for line in lines + manual_check),
            "scanned": sum(line["scanned"] for line in lines + manual_check),
            "missing": sum(line["missing"] for line in lines),
            "surplus": sum(line["surplus"] for line in lines),
            "manual_check": len(manual_check),
            "unresolved": len(unresolved),
        }
        return {
            "session": session.to_dict(),
            "generated_at": _now(),
            "totals": totals,
            "lines": lines,
            "manual_check": manual_check,
            "unresolved": [dict(row) for row in unresolved],
            "on_loan_detail": [dict(row) for row in loaned_detail],
        }

    def progress(self, session_id: int) -> dict[str, Any]:
        session = self.get_session(session_id)
        if session is None:
            raise KeyError("Sayım oturumu bulunamadı")
        clause, params = self._scope_filter(session.scope_location)
        row = self.db.fetchone(
            f"""
            SELECT
                (SELECT COUNT(*) FROM copy AS c
                 WHERE c.status = 'active' {clause}) AS expected,
                (SELECT COUNT(*) FROM copy AS c
                 JOIN loan AS l ON l.copy_id = c.id AND l.returned_at IS NULL
                 WHERE c.status = 'active' {clause}) AS on_loan
            """,
            params * 2 if params else [],
        )
        scanned_row = self.db.fetchone(
            "SELECT COUNT(*) FROM stocktake_scan WHERE session_id = ? AND edition_id IS NOT NULL",
            (session_id,),
        )
        expected = int(row["expected"]) if row else 0
        on_loan = int(row["on_loan"]) if row else 0
        shelf = max(0, expected - on_loan)
        scanned = int(scanned_row[0]) if scanned_row else 0
        return {
            "expected_on_shelf": shelf,
            "on_loan": on_loan,
            "scanned": scanned,
            "percent": min(100, round(scanned * 100 / shelf)) if shelf else 100,
        }

    # ── Excel ───────────────────────────────────────────────────────

    def export_report_xlsx(self, session_id: int, destination: Path | str) -> Path:
        from openpyxl import Workbook

        from kitapkatalog.exporters import protect_spreadsheet_value as safe

        report = self.report(session_id)
        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        workbook = Workbook(write_only=True)

        summary = workbook.create_sheet("Özet")
        session = report["session"]
        totals = report["totals"]
        summary.append(["Sayım", safe(session["name"])])
        summary.append(["Kapsam", safe(session["scope_location"] or "Tüm kütüphane")])
        summary.append(["Başlangıç", session["started_at"]])
        summary.append(["Rapor zamanı", report["generated_at"]])
        summary.append([])
        for label, key in (
            ("Beklenen nüsha", "expected"),
            ("Ödünçte", "on_loan"),
            ("Okutulan", "scanned"),
            ("Eksik", "missing"),
            ("Fazla", "surplus"),
            ("Elle sayım gerekir", "manual_check"),
            ("Eşleşmeyen okutma", "unresolved"),
        ):
            summary.append([label, totals[key]])

        missing_sheet = workbook.create_sheet("Eksikler")
        missing_sheet.append(["Kitap", "Beklenen", "Ödünçte", "Okutulan", "Eksik"])
        for line in report["lines"]:
            if line["missing"] > 0:
                missing_sheet.append(
                    [
                        safe(line["title"]),
                        line["expected"],
                        line["on_loan"],
                        line["scanned"],
                        line["missing"],
                    ]
                )

        surplus_sheet = workbook.create_sheet("Fazlalar")
        surplus_sheet.append(["Kitap", "Beklenen", "Okutulan", "Fazla"])
        for line in report["lines"]:
            if line["surplus"] > 0:
                surplus_sheet.append(
                    [safe(line["title"]), line["expected"], line["scanned"], line["surplus"]]
                )

        loan_sheet = workbook.create_sheet("Ödünçte")
        loan_sheet.append(["Kitap", "Demirbaş", "Üye", "Sınıf", "Son Gün"])
        for item in report["on_loan_detail"]:
            loan_sheet.append(
                [
                    safe(item["title"]),
                    safe(item["inventory_code"]),
                    safe(item["member_name"]),
                    safe(item["class_name"]),
                    item["due_at"],
                ]
            )

        manual_sheet = workbook.create_sheet("Elle Sayım")
        manual_sheet.append(["Kitap", "Beklenen", "Not"])
        for line in report["manual_check"]:
            manual_sheet.append(
                [safe(line["title"]), line["expected"], "ISBN'siz; rafta elle doğrulayın"]
            )

        unresolved_sheet = workbook.create_sheet("Eşleşmeyenler")
        unresolved_sheet.append(["Okutulan Kod", "Zaman"])
        for item in report["unresolved"]:
            unresolved_sheet.append([safe(item["raw_code"]), item["created_at"]])

        workbook.save(destination)
        return destination

    @staticmethod
    def _session(row: sqlite3.Row) -> StocktakeSession:
        return StocktakeSession(
            id=int(row["id"]),
            name=row["name"],
            scope_location=row["scope_location"],
            status=row["status"],
            started_at=row["started_at"],
            closed_at=row["closed_at"],
            notes=row["notes"],
        )
