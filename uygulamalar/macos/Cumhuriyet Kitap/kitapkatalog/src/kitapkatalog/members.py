"""Üye (öğrenci + personel) servisi: CRUD, arama, e-Okul içe aktarımı, yıl sonu."""

from __future__ import annotations

import re
import sqlite3
import unicodedata
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from kitapkatalog.database import Database, StateConflictError

MEMBER_TYPES = ("student", "staff")

# e-Okul başlık eşleme listeleri (normalize: küçük, ı→i, alfasayısal).
# SIRALI: en özgül ad önce gelir — "No" ve "Okul No" aynı dosyadaysa kimlik
# sütunu her zaman "Okul No" seçilir (set olsaydı sıra rastgele olurdu).
_NUMBER_HEADERS = ("okulno", "okulnumarasi", "ogrencino", "ogrno", "numara", "no")
_FIRST_HEADERS = ("adi", "ad")
_LAST_HEADERS = ("soyadi", "soyad")
_FULL_HEADERS = ("adisoyadi", "adsoyad", "ogrencininadisoyadi")
_CLASS_HEADERS = ("sinifisubesi", "sinifsube", "sinifi", "sinif")
_SECTION_HEADERS = ("subesi", "sube")


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds")


def _fold(value: str) -> str:
    """Türkçe farkındalıklı küçük harfe indirme (İ→i, I→ı)."""

    return value.translate({ord("İ"): "i", ord("I"): "ı"}).casefold()


def _header_key(value: Any) -> str:
    text = _fold(str(value or ""))
    text = unicodedata.normalize("NFKD", text)
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.replace("ı", "i")
    return re.sub(r"[^a-z0-9]", "", text)


def _cell(row: tuple[Any, ...], columns: dict[str, int], name: str) -> str:
    position = columns.get(name)
    if position is None or position >= len(row):
        return ""
    value = row[position]
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    return str(value).strip()


def _clean_class(value: Any) -> str | None:
    text = str(value or "").strip()
    if not text:
        return None
    # "9/A", "9 A", "9-A" → "9-A"
    return re.sub(r"[\s/]+", "-", text).upper()


@dataclass(frozen=True, slots=True)
class MemberRecord:
    id: int
    member_type: str
    school_number: str | None
    first_name: str
    last_name: str
    class_name: str | None
    is_active: bool
    notes: str | None

    @property
    def full_name(self) -> str:
        return f"{self.first_name} {self.last_name}".strip()

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "member_type": self.member_type,
            "school_number": self.school_number,
            "first_name": self.first_name,
            "last_name": self.last_name,
            "full_name": self.full_name,
            "class_name": self.class_name,
            "is_active": self.is_active,
            "notes": self.notes,
        }


@dataclass(slots=True)
class ImportReport:
    imported: int = 0
    updated: int = 0
    skipped: int = 0
    deactivated: int = 0
    needs_resolution: list[dict[str, Any]] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "imported": self.imported,
            "updated": self.updated,
            "skipped": self.skipped,
            "deactivated": self.deactivated,
            "needs_resolution": self.needs_resolution,
            "errors": self.errors,
        }


@dataclass(frozen=True, slots=True)
class _ParsedStudent:
    school_number: str
    first_name: str
    last_name: str
    class_name: str | None


class Members:
    def __init__(self, database: Database) -> None:
        self.db = database

    # ── CRUD ────────────────────────────────────────────────────────

    def add(
        self,
        *,
        member_type: str,
        first_name: str,
        last_name: str,
        school_number: str | None = None,
        class_name: str | None = None,
        notes: str | None = None,
    ) -> MemberRecord:
        if member_type not in MEMBER_TYPES:
            raise ValueError(f"Geçersiz üye tipi: {member_type}")
        first_name = (first_name or "").strip()
        last_name = (last_name or "").strip()
        if not first_name or not last_name:
            raise ValueError("Ad ve soyad zorunludur")
        school_number = (school_number or "").strip() or None
        if member_type == "student" and not school_number:
            raise ValueError("Öğrenci için okul numarası zorunludur")
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            try:
                cursor = connection.execute(
                    """
                    INSERT INTO member(member_type, school_number, first_name, last_name,
                                       class_name, notes, created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        member_type,
                        school_number,
                        first_name,
                        last_name,
                        _clean_class(class_name),
                        notes,
                        now,
                        now,
                    ),
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError(
                    f"{school_number} numaralı üye zaten kayıtlı"
                ) from exc
            member_id = int(cursor.lastrowid)
        record = self.get(member_id)
        assert record is not None
        return record

    def get(self, member_id: int) -> MemberRecord | None:
        row = self.db.fetchone("SELECT * FROM member WHERE id = ?", (member_id,))
        return self._record(row) if row is not None else None

    def get_by_number(self, school_number: str) -> MemberRecord | None:
        row = self.db.fetchone(
            "SELECT * FROM member WHERE school_number = ?", (school_number.strip(),)
        )
        return self._record(row) if row is not None else None

    def update(self, member_id: int, **fields: Any) -> MemberRecord:
        # member_type de düzenlenebilir (öğrenci↔personel geçişi meşru bir
        # ihtiyaç; üye formu bu alanı her kayıtta gönderir).
        allowed = {
            "member_type", "school_number", "first_name", "last_name",
            "class_name", "notes", "is_active",
        }
        unknown = set(fields) - allowed
        if unknown:
            raise ValueError(f"Bilinmeyen alan: {', '.join(sorted(unknown))}")
        if not fields:
            record = self.get(member_id)
            if record is None:
                raise KeyError("Üye bulunamadı")
            return record
        current = self.get(member_id)
        if current is None:
            raise KeyError("Üye bulunamadı")
        # add() ile aynı kural: öğrencinin okul numarası boş kalamaz.
        new_type = str(fields.get("member_type", current.member_type) or "")
        if "member_type" in fields and new_type not in MEMBER_TYPES:
            raise ValueError(f"Geçersiz üye tipi: {new_type}")
        raw_number = fields.get("school_number", current.school_number)
        new_number = (str(raw_number).strip() or None) if raw_number is not None else None
        if new_type == "student" and not new_number:
            raise ValueError("Öğrenci için okul numarası zorunludur")
        sets: list[str] = []
        values: list[Any] = []
        for key, value in fields.items():
            if key == "is_active":
                value = 1 if value else 0
            elif key == "class_name":
                value = _clean_class(value)
            elif key == "school_number":
                value = new_number
            sets.append(f"{key} = ?")
            values.append(value)
        sets.append("updated_at = ?")
        values.append(_now())
        values.append(member_id)
        with self.db.transaction(immediate=True) as connection:
            try:
                cursor = connection.execute(
                    f"UPDATE member SET {', '.join(sets)} WHERE id = ?", values
                )
            except sqlite3.IntegrityError as exc:
                raise StateConflictError("Bu okul numarası başka üyede kayıtlı") from exc
            if cursor.rowcount == 0:
                raise KeyError("Üye bulunamadı")
        record = self.get(member_id)
        assert record is not None
        return record

    def delete(self, member_id: int) -> None:
        """Üyeyi kalıcı siler; ödünç izi olan üye korunur (pasifleştirilir).

        loan.member_id ON DELETE RESTRICT son emniyettir; buradaki denetimler
        kullanıcıya anlamlı mesaj vermek içindir.
        """

        with self.db.transaction(immediate=True) as connection:
            exists = connection.execute(
                "SELECT 1 FROM member WHERE id = ?", (member_id,)
            ).fetchone()
            if exists is None:
                raise KeyError("Üye bulunamadı")
            open_count = connection.execute(
                "SELECT COUNT(*) FROM loan WHERE member_id = ? AND returned_at IS NULL",
                (member_id,),
            ).fetchone()[0]
            if int(open_count) > 0:
                raise StateConflictError("Üyenin üzerinde kitap var; önce iade alın")
            total = connection.execute(
                "SELECT COUNT(*) FROM loan WHERE member_id = ?", (member_id,)
            ).fetchone()[0]
            if int(total) > 0:
                raise StateConflictError(
                    "Üyenin ödünç geçmişi var; kayıtlar korunur — üyeyi pasifleştirin"
                )
            connection.execute("DELETE FROM member WHERE id = ?", (member_id,))

    # ── Arama ───────────────────────────────────────────────────────

    def search(
        self,
        q: str = "",
        *,
        class_name: str | None = None,
        member_type: str | None = None,
        active: bool | None = True,
        limit: int = 50,
        offset: int = 0,
    ) -> tuple[list[MemberRecord], int]:
        where: list[str] = []
        parameters: list[Any] = []
        if class_name:
            where.append("class_name = ?")
            parameters.append(_clean_class(class_name))
        if member_type:
            where.append("member_type = ?")
            parameters.append(member_type)
        if active is not None:
            where.append("is_active = ?")
            parameters.append(1 if active else 0)
        clause = f"WHERE {' AND '.join(where)}" if where else ""
        limit = max(1, min(int(limit), 500))
        offset = max(0, int(offset))
        query = _fold(q.strip()) if q else ""
        if not query:
            # Normal listeleme yolunda bütün okulu Python'a taşımadan SQL'de
            # sayfala. Aramalı yol Türkçe I/İ/ı/i katlamasını korumak için
            # aşağıdaki kesin Python filtresini kullanmaya devam eder.
            with self.db.connection(readonly=True) as connection:
                total = int(
                    connection.execute(
                        f"SELECT COUNT(*) FROM member {clause}", parameters
                    ).fetchone()[0]
                )
                rows = connection.execute(
                    f"""
                    SELECT * FROM member {clause}
                    ORDER BY class_name, last_name COLLATE UNICODE_NOCASE, first_name
                    LIMIT ? OFFSET ?
                    """,
                    (*parameters, limit, offset),
                ).fetchall()
            return [self._record(row) for row in rows], total
        rows = self.db.fetchall(
            f"""
            SELECT * FROM member {clause}
            ORDER BY class_name, last_name COLLATE UNICODE_NOCASE, first_name
            """,
            parameters,
        )
        records = [self._record(row) for row in rows]
        # Türkçe büyük/küçük katlaması SQL LIKE ile güvenilmez; süzme burada
        # yapılır fakat yalnız gerçekten arama terimi gönderildiğinde.
        records = [
            record
            for record in records
            if query
            in _fold(f"{record.first_name} {record.last_name} {record.school_number or ''}")
        ]
        total = len(records)
        return records[offset : offset + limit], total

    def list_classes(self) -> list[str]:
        rows = self.db.fetchall(
            """
            SELECT DISTINCT class_name FROM member
            WHERE class_name IS NOT NULL AND class_name <> '' AND is_active = 1
            ORDER BY class_name
            """
        )

        def natural(value: str) -> tuple[int, str]:
            match = re.match(r"(\d+)", value)
            return (int(match.group(1)) if match else 999, value)

        return sorted((str(row[0]) for row in rows), key=natural)

    # ── e-Okul içe aktarımı ─────────────────────────────────────────

    def import_eokul_xlsx(self, path: Path | str) -> ImportReport:
        students, report = self._parse_eokul(Path(path))
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            for student in students:
                self._upsert_student(connection, student, now, report)
        return report

    def promote_preview(self, path: Path | str) -> dict[str, Any]:
        """Yıl sonu önizlemesi — hiçbir kaydı DEĞİŞTİRMEZ."""

        students, report = self._parse_eokul(Path(path))
        by_number = {student.school_number: student for student in students}
        existing = {
            str(row["school_number"]): row
            for row in self.db.fetchall(
                "SELECT * FROM member WHERE member_type = 'student' AND is_active = 1"
            )
        }
        active_loan_counts = {
            int(row["member_id"]): int(row["active_loan_count"])
            for row in self.db.fetchall(
                """
                SELECT member_id, COUNT(*) AS active_loan_count
                FROM loan WHERE returned_at IS NULL GROUP BY member_id
                """
            )
        }
        plan: dict[str, Any] = {
            "update": [],
            "add": [],
            "deactivate": [],
            "needs_resolution": [],
            "errors": report.errors,
        }
        for number, student in by_number.items():
            row = existing.get(number)
            if row is None:
                plan["add"].append(
                    {
                        "school_number": number,
                        "full_name": f"{student.first_name} {student.last_name}",
                        "class_name": student.class_name,
                    }
                )
            elif (
                row["class_name"] != student.class_name
                or row["first_name"] != student.first_name
                or row["last_name"] != student.last_name
            ):
                plan["update"].append(
                    {
                        "school_number": number,
                        "full_name": f"{student.first_name} {student.last_name}",
                        "old_class": row["class_name"],
                        "new_class": student.class_name,
                    }
                )
        for number, row in existing.items():
            if number not in by_number:
                item = {
                    "school_number": number,
                    "full_name": f"{row['first_name']} {row['last_name']}",
                    "class_name": row["class_name"],
                }
                active_loan_count = active_loan_counts.get(int(row["id"]), 0)
                if active_loan_count:
                    item["active_loan_count"] = active_loan_count
                    plan["needs_resolution"].append(item)
                else:
                    plan["deactivate"].append(item)
        return plan

    def promote_apply(self, path: Path | str) -> ImportReport:
        """Yıl sonu uygulaması: eşleşen güncellenir, listede olmayan pasife alınır.

        Emniyet: boş/bozuk ayrıştırma ya da aktif öğrencilerin yarısından
        fazlasını pasifleştirecek bir liste, tüm okulun yanlışlıkla
        pasifleşmesine yol açmasın diye REDDEDİLİR.
        """

        students, report = self._parse_eokul(Path(path))
        if not students:
            raise ValueError(
                "Dosyadan hiç öğrenci okunamadı; yıl sonu atlatma uygulanmadı. "
                "Dosyanın e-Okul sınıf listesi olduğundan emin olun."
            )
        numbers = {student.school_number for student in students}
        now = _now()
        with self.db.transaction(immediate=True) as connection:
            placeholders = ",".join("?" for _ in numbers) or "''"
            active_count = int(
                connection.execute(
                    "SELECT COUNT(*) FROM member "
                    "WHERE member_type = 'student' AND is_active = 1"
                ).fetchone()[0]
            )
            would_deactivate = int(
                connection.execute(
                    f"""
                    SELECT COUNT(*) FROM member
                    WHERE member_type = 'student' AND is_active = 1
                      AND (school_number IS NULL
                           OR school_number NOT IN ({placeholders}))
                      AND NOT EXISTS (
                          SELECT 1 FROM loan
                          WHERE loan.member_id = member.id
                            AND loan.returned_at IS NULL
                      )
                    """,
                    tuple(numbers),
                ).fetchone()[0]
            )
            if active_count >= 20 and would_deactivate > active_count // 2:
                raise StateConflictError(
                    f"Liste, aktif öğrencilerin yarısından fazlasını "
                    f"({would_deactivate}/{active_count}) pasifleştirecek; dosya "
                    "eksik görünüyor. Listeyi kontrol edin — yıl sonu atlatma "
                    "uygulanmadı."
                )
            for student in students:
                self._upsert_student(connection, student, now, report)
            resolution_rows = connection.execute(
                f"""
                SELECT m.school_number, m.first_name, m.last_name, m.class_name,
                       COUNT(l.id) AS active_loan_count
                FROM member AS m
                JOIN loan AS l ON l.member_id = m.id AND l.returned_at IS NULL
                WHERE m.member_type = 'student' AND m.is_active = 1
                  AND (m.school_number IS NULL
                       OR m.school_number NOT IN ({placeholders}))
                GROUP BY m.id
                ORDER BY m.school_number, m.id
                """,
                tuple(numbers),
            ).fetchall()
            report.needs_resolution.extend(
                {
                    "school_number": row["school_number"],
                    "full_name": f"{row['first_name']} {row['last_name']}",
                    "class_name": row["class_name"],
                    "active_loan_count": int(row["active_loan_count"]),
                }
                for row in resolution_rows
            )
            cursor = connection.execute(
                f"""
                UPDATE member SET is_active = 0, updated_at = ?
                WHERE member_type = 'student' AND is_active = 1
                  AND (school_number IS NULL OR school_number NOT IN ({placeholders}))
                  AND NOT EXISTS (
                      SELECT 1 FROM loan
                      WHERE loan.member_id = member.id AND loan.returned_at IS NULL
                  )
                """,
                (now, *numbers),
            )
            report.deactivated = cursor.rowcount
        return report

    @staticmethod
    def _upsert_student(
        connection: sqlite3.Connection,
        student: _ParsedStudent,
        now: str,
        report: ImportReport,
    ) -> None:
        row = connection.execute(
            "SELECT id, member_type FROM member WHERE school_number = ?",
            (student.school_number,),
        ).fetchone()
        if row is None:
            connection.execute(
                """
                INSERT INTO member(member_type, school_number, first_name, last_name,
                                   class_name, created_at, updated_at)
                VALUES ('student', ?, ?, ?, ?, ?, ?)
                """,
                (
                    student.school_number,
                    student.first_name,
                    student.last_name,
                    student.class_name,
                    now,
                    now,
                ),
            )
            report.imported += 1
        elif row["member_type"] != "student":
            report.errors.append(
                f"{student.school_number}: bu numara personel üyede kayıtlı, atlandı"
            )
            report.skipped += 1
        else:
            # class_name COALESCE: sınıf sütunu olmayan liste mevcut sınıfı
            # NULL ile ezmesin (sessiz veri kaybı).
            connection.execute(
                """
                UPDATE member SET first_name = ?, last_name = ?,
                                  class_name = COALESCE(?, class_name),
                                  is_active = 1, updated_at = ?
                WHERE id = ?
                """,
                (
                    student.first_name,
                    student.last_name,
                    student.class_name,
                    now,
                    int(row["id"]),
                ),
            )
            report.updated += 1

    @staticmethod
    def _parse_eokul(path: Path) -> tuple[list[_ParsedStudent], ImportReport]:
        if path.suffix.lower() != ".xlsx":
            raise ValueError(
                "Yalnız .xlsx desteklenir; dosyayı e-Okul'dan Excel (.xlsx) olarak kaydedin"
            )
        if not path.is_file():
            raise ValueError(f"Dosya bulunamadı: {path}")
        from openpyxl import load_workbook

        workbook = load_workbook(path, read_only=True, data_only=True)
        try:
            sheet = workbook.active
            rows = list(sheet.iter_rows(values_only=True))
        finally:
            workbook.close()

        columns: dict[str, int] = {}
        header_index = -1
        for index, row in enumerate(rows[:10]):
            keys = {_header_key(cell): position for position, cell in enumerate(row)}
            found: dict[str, int] = {}
            for name, aliases in (
                ("number", _NUMBER_HEADERS),
                ("first", _FIRST_HEADERS),
                ("last", _LAST_HEADERS),
                ("full", _FULL_HEADERS),
                ("class", _CLASS_HEADERS),
                ("section", _SECTION_HEADERS),
            ):
                for alias in aliases:
                    if alias in keys:
                        found[name] = keys[alias]
                        break
            if "number" in found and ("full" in found or ("first" in found and "last" in found)):
                columns = found
                header_index = index
                break
        if header_index < 0:
            raise ValueError(
                "Beklenen sütunlar bulunamadı (Okul No, Adı, Soyadı, Sınıfı); "
                "dosyanın e-Okul sınıf listesi olduğundan emin olun"
            )

        report = ImportReport()
        students: list[_ParsedStudent] = []
        seen: set[str] = set()
        for row_number, row in enumerate(rows[header_index + 1 :], start=header_index + 2):
            number = _cell(row, columns, "number")
            if "full" in columns and "first" not in columns:
                full = _cell(row, columns, "full")
                first, _, last = full.rpartition(" ")
                if not first:
                    first, last = full, ""
            else:
                first = _cell(row, columns, "first")
                last = _cell(row, columns, "last")
            if not number and not first and not last:
                continue  # tamamen boş satır
            if not number:
                report.errors.append(f"Satır {row_number}: okul numarası boş, atlandı")
                report.skipped += 1
                continue
            if not first:
                report.errors.append(f"Satır {row_number}: ad boş, atlandı")
                report.skipped += 1
                continue
            if number in seen:
                report.errors.append(
                    f"Satır {row_number}: {number} numarası dosyada tekrar ediyor, atlandı"
                )
                report.skipped += 1
                continue
            seen.add(number)
            class_name = _clean_class(_cell(row, columns, "class"))
            section = _cell(row, columns, "section")
            if section and class_name and "-" not in class_name:
                class_name = f"{class_name}-{section.upper()}"
            students.append(
                _ParsedStudent(
                    school_number=number,
                    first_name=first,
                    last_name=last,
                    class_name=class_name,
                )
            )
        return students, report

    @staticmethod
    def _record(row: sqlite3.Row) -> MemberRecord:
        return MemberRecord(
            id=int(row["id"]),
            member_type=row["member_type"],
            school_number=row["school_number"],
            first_name=row["first_name"],
            last_name=row["last_name"],
            class_name=row["class_name"],
            is_active=bool(row["is_active"]),
            notes=row["notes"],
        )
