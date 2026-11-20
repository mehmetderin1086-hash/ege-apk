"""Üye servisi: CRUD, Türkçe katlamalı arama, e-Okul içe aktarımı, yıl sonu sihirbazı."""

from __future__ import annotations

from pathlib import Path

import pytest
from openpyxl import Workbook

from kitapkatalog.database import Database
from kitapkatalog.members import Members


@pytest.fixture()
def members(tmp_path: Path) -> Members:
    return Members(Database(tmp_path / "catalog.sqlite3"))


def _eokul_file(tmp_path: Path, rows: list[list[object]], header_row: int = 3) -> Path:
    """Başlığı istenen satırda olan sahte e-Okul listesi üretir."""

    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["T.C. MEB Örnek Okulu"])
    for _ in range(header_row - 2):
        sheet.append([])
    sheet.append(["Okul No", "Adı", "Soyadı", "Sınıfı"])
    for row in rows:
        sheet.append(row)
    path = tmp_path / "eokul.xlsx"
    workbook.save(path)
    return path


class TestCrud:
    def test_add_and_get(self, members: Members) -> None:
        record = members.add(
            member_type="student",
            school_number="123",
            first_name="Ada",
            last_name="Yılmaz",
            class_name="9-A",
        )
        assert record.id > 0
        fetched = members.get(record.id)
        assert fetched is not None
        assert fetched.school_number == "123"
        assert fetched.is_active is True

    def test_student_requires_school_number(self, members: Members) -> None:
        with pytest.raises(ValueError, match="numara"):
            members.add(member_type="student", school_number="", first_name="A", last_name="B")

    def test_staff_without_number_is_fine(self, members: Members) -> None:
        record = members.add(
            member_type="staff", school_number=None, first_name="Ali", last_name="Öğretmen"
        )
        assert record.member_type == "staff"

    def test_update_and_deactivate(self, members: Members) -> None:
        record = members.add(
            member_type="student", school_number="7", first_name="Can", last_name="Demir"
        )
        updated = members.update(record.id, class_name="10-B", is_active=False)
        assert updated.class_name == "10-B"
        assert updated.is_active is False

    def test_duplicate_school_number_conflict(self, members: Members) -> None:
        members.add(member_type="student", school_number="55", first_name="A", last_name="B")
        with pytest.raises(Exception, match="55"):
            members.add(member_type="student", school_number="55", first_name="C", last_name="D")


class TestSearch:
    def test_turkish_case_folding(self, members: Members) -> None:
        members.add(
            member_type="student", school_number="1", first_name="IŞIL", last_name="YILMAZ",
            class_name="9-A",
        )
        members.add(
            member_type="student", school_number="2", first_name="İsmail", last_name="Çelik",
            class_name="9-B",
        )
        items, total = members.search(q="yılmaz")
        assert total == 1 and items[0].school_number == "1"
        items, total = members.search(q="ışıl")
        assert total == 1
        items, total = members.search(q="ismail")
        assert total == 1 and items[0].school_number == "2"

    def test_filters_and_pagination(self, members: Members) -> None:
        for index in range(30):
            members.add(
                member_type="student",
                school_number=str(100 + index),
                first_name=f"Öğrenci{index}",
                last_name="Test",
                class_name="9-A" if index % 2 == 0 else "9-B",
            )
        members.add(member_type="staff", school_number=None, first_name="P", last_name="Personel")
        items, total = members.search(class_name="9-A", limit=10)
        assert total == 15 and len(items) == 10
        items, total = members.search(member_type="staff")
        assert total == 1
        items, total = members.search(q="10")  # okul numarası araması
        assert total >= 1

    def test_list_classes_natural_order(self, members: Members) -> None:
        for class_name in ("10-A", "9-B", "9-A", "11-C"):
            members.add(
                member_type="student",
                school_number=class_name,
                first_name="X",
                last_name="Y",
                class_name=class_name,
            )
        assert members.list_classes() == ["9-A", "9-B", "10-A", "11-C"]


class TestEokulImport:
    def test_import_with_offset_header_and_blank_rows(
        self, members: Members, tmp_path: Path
    ) -> None:
        path = _eokul_file(
            tmp_path,
            [
                ["101", "IŞIL", "YILMAZ", "9/A"],
                [],
                ["102", "Can", "Demir", "9/A"],
                ["101", "Tekrar", "Kayıt", "9/B"],  # dosya içi tekrar → hata
                ["", "Numarasız", "Kayıt", "9/C"],  # numarasız → hata
            ],
        )
        report = members.import_eokul_xlsx(path)
        assert report.imported == 2
        assert report.updated == 0
        assert len(report.errors) == 2
        _, total = members.search()
        assert total == 2

    def test_reimport_updates_existing(self, members: Members, tmp_path: Path) -> None:
        first = _eokul_file(tmp_path, [["101", "Işıl", "Yılmaz", "9/A"]])
        members.import_eokul_xlsx(first)
        second = _eokul_file(tmp_path, [["101", "Işıl", "Yılmaz", "10/A"]])
        report = members.import_eokul_xlsx(second)
        assert report.updated == 1 and report.imported == 0
        items, _ = members.search(q="101")
        assert items[0].class_name == "10-A"

    def test_missing_column_gives_turkish_error(self, members: Members, tmp_path: Path) -> None:
        workbook = Workbook()
        sheet = workbook.active
        sheet.append(["Numara", "İsim"])  # soyad/sınıf yok
        sheet.append(["1", "Ali"])
        path = tmp_path / "eksik.xlsx"
        workbook.save(path)
        with pytest.raises(ValueError, match="sütun"):
            members.import_eokul_xlsx(path)

    def test_xls_extension_rejected(self, members: Members, tmp_path: Path) -> None:
        path = tmp_path / "eski.xls"
        path.write_bytes(b"eski bicim")
        with pytest.raises(ValueError, match="xlsx"):
            members.import_eokul_xlsx(path)


class TestParsingSafety:
    def test_class_column_absent_preserves_existing_class(
        self, members: Members, tmp_path: Path
    ) -> None:
        # Codex bulgusu: sınıf sütunu olmayan liste mevcut sınıfı NULL ile ezmemeli.
        members.add(
            member_type="student", school_number="101", first_name="Işıl",
            last_name="Yılmaz", class_name="9-A",
        )
        workbook_path = tmp_path / "sinifsiz.xlsx"
        from openpyxl import Workbook

        workbook = Workbook()
        sheet = workbook.active
        sheet.append(["Okul No", "Adı", "Soyadı"])
        sheet.append(["101", "Işıl", "Yılmaz"])
        workbook.save(workbook_path)
        members.import_eokul_xlsx(workbook_path)
        items, _ = members.search(q="101")
        assert items[0].class_name == "9-A"  # korunur

    def test_number_column_priority_is_deterministic(
        self, members: Members, tmp_path: Path
    ) -> None:
        # "No" ve "Okul No" birlikteyse kimlik sütunu her zaman "Okul No" olmalı.
        from openpyxl import Workbook

        workbook = Workbook()
        sheet = workbook.active
        sheet.append(["No", "Okul No", "Adı", "Soyadı", "Sınıfı"])
        sheet.append(["1", "901", "Sıra", "Değil", "9/A"])
        path = tmp_path / "cift-no.xlsx"
        workbook.save(path)
        report = members.import_eokul_xlsx(path)
        assert report.imported == 1
        items, _ = members.search(q="Sıra")
        assert items[0].school_number == "901"


class TestPromotion:
    def _seed(self, members: Members) -> None:
        members.add(
            member_type="student", school_number="101", first_name="Işıl", last_name="Yılmaz",
            class_name="9-A",
        )
        members.add(
            member_type="student", school_number="102", first_name="Can", last_name="Demir",
            class_name="12-A",
        )
        members.add(member_type="staff", school_number=None, first_name="Ali", last_name="Hoca")

    def test_preview_does_not_mutate(self, members: Members, tmp_path: Path) -> None:
        self._seed(members)
        path = _eokul_file(
            tmp_path,
            [["101", "Işıl", "Yılmaz", "10/A"], ["201", "Yeni", "Öğrenci", "9/A"]],
        )
        plan = members.promote_preview(path)
        assert len(plan["update"]) == 1
        assert len(plan["add"]) == 1
        assert len(plan["deactivate"]) == 1  # 102 listede yok
        # Önizleme hiçbir şeyi DEĞİŞTİRMEZ.
        items, _ = members.search(q="101")
        assert items[0].class_name == "9-A"
        items, total = members.search(member_type="student", active=True)
        assert total == 2

    def test_apply_refuses_empty_or_suspicious_file(
        self, members: Members, tmp_path: Path
    ) -> None:
        # Codex bulgusu: boş/bozuk ayrıştırma yıl sonunda TÜM okulu pasifleştirebilir.
        for index in range(30):
            members.add(
                member_type="student", school_number=str(200 + index),
                first_name=f"Ö{index}", last_name="K", class_name="9-A",
            )
        empty = _eokul_file(tmp_path, [])
        with pytest.raises(Exception, match=r"uygulanmadı|okunamadı"):
            members.promote_apply(empty)
        # Aktiflerin yarısından fazlasını pasifleştirecek liste de reddedilir.
        tiny = _eokul_file(tmp_path, [["200", "Ö0", "K", "10/A"]])
        with pytest.raises(Exception, match=r"yarısından fazlası|kontrol"):
            members.promote_apply(tiny)
        # Hiç kimse pasifleşmedi.
        _, total = members.search(member_type="student", active=True)
        assert total == 30

    def test_apply_updates_deactivates_and_adds(self, members: Members, tmp_path: Path) -> None:
        self._seed(members)
        path = _eokul_file(
            tmp_path,
            [["101", "Işıl", "Yılmaz", "10/A"], ["201", "Yeni", "Öğrenci", "9/A"]],
        )
        report = members.promote_apply(path)
        assert report.updated == 1 and report.imported == 1
        items, _ = members.search(q="101")
        assert items[0].class_name == "10-A"
        items, total = members.search(member_type="student", active=False)
        assert total == 1 and items[0].school_number == "102"
        # Personel dokunulmadan kalır.
        items, total = members.search(member_type="staff", active=True)
        assert total == 1

    def test_open_loan_member_is_kept_active_for_resolution(
        self, members: Members, tmp_path: Path
    ) -> None:
        from kitapkatalog.catalog import Catalog
        from kitapkatalog.domain import BookInput
        from kitapkatalog.loans import Loans
        from kitapkatalog.settings import AppSettings

        self._seed(members)
        missing = members.get_by_number("102")
        assert missing is not None
        book = Catalog(members.db).save_book(BookInput(title="Açık Ödünç"))
        Loans(members.db, AppSettings(members.db)).checkout(
            missing.id,
            edition_id=book.edition_id,
            request_id="year-end-open-loan-001",
        )
        path = _eokul_file(tmp_path, [["101", "Işıl", "Yılmaz", "10/A"]])

        preview = members.promote_preview(path)
        assert preview["deactivate"] == []
        assert preview["needs_resolution"] == [
            {
                "school_number": "102",
                "full_name": "Can Demir",
                "class_name": "12-A",
                "active_loan_count": 1,
            }
        ]

        report = members.promote_apply(path)
        assert report.deactivated == 0
        assert report.needs_resolution == preview["needs_resolution"]
        preserved = members.get(missing.id)
        assert preserved is not None and preserved.is_active is True


class TestDelete:
    def test_delete_clean_member(self, members: Members) -> None:
        record = members.add(
            member_type="student", school_number="700", first_name="Sil", last_name="Inecek"
        )
        members.delete(record.id)
        assert members.get(record.id) is None

    def test_delete_missing_raises(self, members: Members) -> None:
        with pytest.raises(KeyError):
            members.delete(999)

    def test_delete_guards(self, members: Members, tmp_path: Path) -> None:
        # Açık ödünç → "önce iade"; iade edilmiş geçmiş → "pasifleştirin".
        from kitapkatalog.catalog import Catalog
        from kitapkatalog.database import StateConflictError
        from kitapkatalog.domain import BookInput
        from kitapkatalog.loans import Loans
        from kitapkatalog.settings import AppSettings

        database = members.db
        catalog = Catalog(database)
        loans = Loans(database, AppSettings(database))
        record = members.add(
            member_type="student", school_number="701", first_name="Okur", last_name="Üye"
        )
        book = catalog.save_book(BookInput(title="Silinemez"))
        loan = loans.checkout(record.id, edition_id=book.edition_id)
        with pytest.raises(StateConflictError, match="önce iade"):
            members.delete(record.id)
        loans.return_loan(loan.id)
        with pytest.raises(StateConflictError, match="pasifleştirin"):
            members.delete(record.id)
        assert members.get(record.id) is not None
