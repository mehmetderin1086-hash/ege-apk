"""Okuma raporları: en çok okuyanlar, sınıf bazlı, popüler kitaplar, aylık seri."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from kitapkatalog.database import Database


def _range_clause(start: str | None, end: str | None) -> tuple[str, list[Any]]:
    clauses: list[str] = []
    params: list[Any] = []
    if start:
        clauses.append("l.loaned_at >= ?")
        params.append(start)
    if end:
        clauses.append("l.loaned_at < ?")
        # Bitiş günü dahil olsun diye ertesi güne kadar say.
        params.append(f"{end}~")
    return (" AND " + " AND ".join(clauses)) if clauses else "", params


class Reports:
    def __init__(self, database: Database) -> None:
        self.db = database

    def top_readers(
        self, *, start: str | None = None, end: str | None = None, limit: int = 20
    ) -> list[dict[str, Any]]:
        clause, params = _range_clause(start, end)
        rows = self.db.fetchall(
            f"""
            WITH filtered AS (
                SELECT l.*,
                       ROW_NUMBER() OVER (
                           PARTITION BY l.member_id
                           ORDER BY l.loaned_at DESC, l.id DESC
                       ) AS latest_rank
                FROM loan AS l
                WHERE 1=1 {clause}
            ), totals AS (
                SELECT member_id, COUNT(*) AS loan_count
                FROM filtered GROUP BY member_id
            )
            SELECT f.member_name_snapshot AS member_name,
                   f.member_class_snapshot AS class_name,
                   f.member_number_snapshot AS school_number,
                   f.member_type_snapshot AS member_type,
                   t.loan_count
            FROM totals AS t
            JOIN filtered AS f
              ON f.member_id = t.member_id AND f.latest_rank = 1
            ORDER BY t.loan_count DESC, member_name
            LIMIT ?
            """,
            (*params, max(1, min(int(limit), 200))),
        )
        return [dict(row) for row in rows]

    def snapshot_quality(
        self, *, start: str | None = None, end: str | None = None
    ) -> dict[str, int]:
        """Count exact v8 checkout snapshots versus v7 migration estimates."""

        clause, params = _range_clause(start, end)
        row = self.db.fetchone(
            f"""
            SELECT COUNT(*) AS total,
                   SUM(CASE WHEN l.snapshot_source = 'migration-estimate'
                            THEN 1 ELSE 0 END) AS estimated
            FROM loan AS l
            WHERE 1=1 {clause}
            """,
            params,
        )
        total = int(row["total"] or 0) if row is not None else 0
        estimated = int(row["estimated"] or 0) if row is not None else 0
        return {"total": total, "exact": total - estimated, "estimated": estimated}

    def by_class(
        self, *, start: str | None = None, end: str | None = None
    ) -> list[dict[str, Any]]:
        clause, params = _range_clause(start, end)
        rows = self.db.fetchall(
            f"""
            SELECT CASE WHEN l.member_type_snapshot = 'staff' THEN 'Personel'
                        ELSE COALESCE(l.member_class_snapshot, 'Sınıfsız') END
                        AS class_name,
                   COUNT(*) AS loan_count,
                   COUNT(DISTINCT l.member_id) AS reader_count
            FROM loan AS l
            WHERE 1=1 {clause}
            GROUP BY 1
            ORDER BY loan_count DESC
            """,
            params,
        )
        return [dict(row) for row in rows]

    def popular_books(
        self, *, start: str | None = None, end: str | None = None, limit: int = 20
    ) -> list[dict[str, Any]]:
        clause, params = _range_clause(start, end)
        rows = self.db.fetchall(
            f"""
            SELECT l.title_snapshot AS title, COUNT(*) AS loan_count,
                   COUNT(DISTINCT l.member_id) AS reader_count
            FROM loan AS l
            WHERE 1=1 {clause}
            GROUP BY l.title_snapshot
            ORDER BY loan_count DESC, title
            LIMIT ?
            """,
            (*params, max(1, min(int(limit), 200))),
        )
        return [dict(row) for row in rows]

    def monthly(self, *, months: int = 12) -> list[dict[str, Any]]:
        rows = self.db.fetchall(
            """
            SELECT substr(loaned_at, 1, 7) AS month,
                   COUNT(*) AS loans,
                   SUM(CASE WHEN returned_at IS NOT NULL THEN 1 ELSE 0 END) AS returns
            FROM loan
            GROUP BY month ORDER BY month DESC LIMIT ?
            """,
            (max(1, min(int(months), 60)),),
        )
        return [dict(row) for row in reversed(rows)]

    def annual(self, *, start: str, end: str) -> dict[str, Any]:
        """Yıl sonu raporu: koleksiyon, dolaşım, liderler ve yaş analizi.

        ``start``/``end`` ISO tarihleridir (dönem: örn. eğitim-öğretim yılı).
        Tüm sayılar mevcut tablolardan türetilir; kopya veri tutulmaz.
        """

        clause, params = _range_clause(start, end)

        collection = self.db.fetchone(
            """
            SELECT (SELECT COUNT(*) FROM work) AS works,
                   (SELECT COUNT(*) FROM edition) AS editions,
                   (SELECT COUNT(*) FROM copy) AS copies
            """
        )
        copies_added = self.db.fetchone(
            "SELECT COUNT(*) AS n FROM copy WHERE created_at >= ? AND created_at < ?",
            (start, f"{end}~"),
        )
        discards = self.db.fetchall(
            """
            SELECT reason, COUNT(*) AS n FROM discard_record
            WHERE discarded_at >= ? AND discarded_at < ?
            GROUP BY reason ORDER BY n DESC
            """,
            (start, f"{end}~"),
        )
        circulation = self.db.fetchone(
            f"""
            SELECT COUNT(*) AS loans,
                   SUM(CASE WHEN l.returned_at IS NOT NULL THEN 1 ELSE 0 END) AS returns,
                   COUNT(DISTINCT l.member_id) AS readers
            FROM loan AS l WHERE 1=1 {clause}
            """,
            params,
        )
        monthly = self.db.fetchall(
            f"""
            SELECT substr(l.loaned_at, 1, 7) AS month, COUNT(*) AS loans
            FROM loan AS l WHERE 1=1 {clause}
            GROUP BY month ORDER BY month
            """,
            params,
        )
        categories = self.db.fetchall(
            """
            SELECT COALESCE(NULLIF(TRIM(category), ''), 'Kategorisiz') AS category,
                   COUNT(*) AS n
            FROM edition GROUP BY 1 ORDER BY n DESC LIMIT 12
            """
        )

        # Koleksiyon yaş analizi: yayın yılından (ilk 4 hane) kova bazlı dağılım.
        current_year = int((end or datetime.now(UTC).date().isoformat())[:4])
        year_rows = self.db.fetchall(
            """
            SELECT CAST(substr(TRIM(publication_date), 1, 4) AS INTEGER) AS year,
                   COUNT(*) AS n
            FROM edition
            WHERE TRIM(COALESCE(publication_date, '')) GLOB '[0-9][0-9][0-9][0-9]*'
            GROUP BY year
            """
        )
        buckets = {"0-4": 0, "5-9": 0, "10-19": 0, "20+": 0}
        known = 0
        for row in year_rows:
            year = int(row["year"] or 0)
            if not 1400 <= year <= current_year + 1:
                continue
            age = max(0, current_year - year)
            known += int(row["n"])
            if age < 5:
                buckets["0-4"] += int(row["n"])
            elif age < 10:
                buckets["5-9"] += int(row["n"])
            elif age < 20:
                buckets["10-19"] += int(row["n"])
            else:
                buckets["20+"] += int(row["n"])
        total_editions = int(collection["editions"] or 0) if collection else 0

        return {
            "period": {"start": start, "end": end},
            "collection": {
                "works": int(collection["works"] or 0) if collection else 0,
                "editions": total_editions,
                "copies": int(collection["copies"] or 0) if collection else 0,
                "copies_added": int(copies_added["n"] or 0) if copies_added else 0,
            },
            "discards": [dict(row) for row in discards],
            "circulation": {
                "loans": int(circulation["loans"] or 0) if circulation else 0,
                "returns": int(circulation["returns"] or 0) if circulation else 0,
                "readers": int(circulation["readers"] or 0) if circulation else 0,
            },
            "monthly": [dict(row) for row in monthly],
            "categories": [dict(row) for row in categories],
            "age_analysis": {
                "buckets": buckets,
                "known": known,
                "unknown": max(0, total_editions - known),
            },
            "top_books": self.popular_books(start=start, end=end, limit=10),
            "top_readers": self.top_readers(start=start, end=end, limit=10),
            "by_class": self.by_class(start=start, end=end),
        }

    def export_xlsx(
        self,
        destination: Path | str,
        *,
        start: str | None = None,
        end: str | None = None,
    ) -> Path:
        from openpyxl import Workbook

        from kitapkatalog.exporters import protect_spreadsheet_value as safe

        destination = Path(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        workbook = Workbook(write_only=True)

        info = workbook.create_sheet("Bilgi")
        info.append(["Okuma Raporu"])
        info.append(["Dönem", f"{start or 'başlangıç'} → {end or 'bugün'}"])
        info.append(["Üretim", datetime.now(UTC).isoformat(timespec="seconds")])
        quality = self.snapshot_quality(start=start, end=end)
        info.append(["Kesin v8 dolaşım kaydı", quality["exact"]])
        info.append(["v8 öncesi tahmini kayıt", quality["estimated"]])
        if quality["estimated"]:
            info.append(
                [
                    "Veri kalitesi uyarısı",
                    "v8 öncesi üye/sınıf alanları geçiş anındaki "
                    "güncel üye kaydından tahmin edilmiştir; tarihsel olarak kesin değildir.",
                ]
            )

        readers = workbook.create_sheet("En Çok Okuyanlar")
        readers.append(["Üye", "Sınıf", "Okul No", "Ödünç Sayısı"])
        for row in self.top_readers(start=start, end=end, limit=100):
            readers.append(
                [
                    safe(row["member_name"]),
                    safe(row["class_name"]),
                    safe(row["school_number"]),
                    row["loan_count"],
                ]
            )

        classes = workbook.create_sheet("Sınıf Bazında")
        classes.append(["Sınıf", "Ödünç Sayısı", "Okuyan Kişi"])
        for row in self.by_class(start=start, end=end):
            classes.append([safe(row["class_name"]), row["loan_count"], row["reader_count"]])

        books = workbook.create_sheet("Popüler Kitaplar")
        books.append(["Kitap", "Ödünç Sayısı", "Farklı Okur"])
        for row in self.popular_books(start=start, end=end, limit=100):
            books.append([safe(row["title"]), row["loan_count"], row["reader_count"]])

        monthly = workbook.create_sheet("Aylık")
        monthly.append(["Ay", "Verilen", "İade"])
        for row in self.monthly(months=24):
            monthly.append([row["month"], row["loans"], row["returns"]])

        workbook.save(destination)
        return destination
