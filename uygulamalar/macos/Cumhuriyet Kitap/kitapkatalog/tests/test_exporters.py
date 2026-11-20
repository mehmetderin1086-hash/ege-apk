from __future__ import annotations

import csv
import json
from pathlib import Path

import pytest
from openpyxl import load_workbook

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import (
    BookInput,
    ContributorInput,
    IdentifierInput,
    ImagePair,
)
from kitapkatalog.exporters import (
    CatalogExporter,
    ImportFormatError,
    export_catalog,
    import_local_catalog,
    protect_spreadsheet_value,
)


def _catalog(tmp_path: Path) -> tuple[Database, Catalog]:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    record = catalog.save_book(
        BookInput(
            title="İnce Memed",
            publisher="Yapı Kredi Yayınları",
            language="tr",
            blurb="Toroslar'da geçen bir roman.",
            contributors=(ContributorInput("Yaşar Kemal"),),
            identifiers=(IdentifierInput("ISBN13", "9780140449136"),),
        )
    )
    catalog.update_book(record.edition_id, {"review_status": "completed"}, user_edit=False)
    return database, catalog


def test_spreadsheet_formula_guard_preserves_non_strings() -> None:
    assert protect_spreadsheet_value('=HYPERLINK("x")') == '\'=HYPERLINK("x")'
    assert protect_spreadsheet_value("+2+3") == "'+2+3"
    assert protect_spreadsheet_value("@SUM(A1)") == "'@SUM(A1)"
    assert protect_spreadsheet_value("normal") == "normal"
    assert protect_spreadsheet_value(42) == 42


def test_csv_is_utf8_bom_streamed_and_formula_safe(tmp_path: Path) -> None:
    _database, catalog = _catalog(tmp_path)
    catalog.save_book(BookInput(title="=2+3", publisher="+Kötü"))

    target = tmp_path / "books.csv"
    result = CatalogExporter(catalog).export_csv(target, completed_only=False)

    assert result.records == 2
    assert target.read_bytes().startswith(b"\xef\xbb\xbf")
    with target.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    dangerous = next(row for row in rows if "2+3" in row["Başlık"])
    assert dangerous["Başlık"] == "'=2+3"
    assert dangerous["Yayınevi"] == "'+Kötü"
    assert not (tmp_path / "books.csv.part").exists()


def test_xlsx_has_required_write_only_sheets_and_safe_cells(tmp_path: Path) -> None:
    _database, catalog = _catalog(tmp_path)
    catalog.save_book(BookInput(title="@tehlike"))
    target = tmp_path / "books.xlsx"

    result = export_catalog(catalog, target, completed_only=False)
    workbook = load_workbook(target, read_only=True, data_only=False)

    assert result.records == 2
    assert workbook.sheetnames == [
        "Özet",
        "Kitaplar",
        "Katkıda Bulunanlar",
        "Tanımlayıcılar",
        "Nüshalar",
        "İstatistik",
        "Ayrıntılı Alanlar",
        "İnceleme Gerekenler",
        "Hatalar",
    ]
    rows = list(workbook["Kitaplar"].iter_rows(values_only=True))
    title_index = rows[0].index("Başlık")
    assert any(row[title_index] == "'@tehlike" for row in rows[1:])
    assert not (tmp_path / "books.xlsx.part").exists()
    workbook.close()


def test_json_jsonl_markdown_and_completed_snapshot(tmp_path: Path) -> None:
    database, catalog = _catalog(tmp_path)
    incomplete = catalog.save_book(BookInput(title="Henüz İşleniyor"))
    job = database.create_import_job(
        "Devam eden",
        [
            ImagePair(
                tmp_path / "x_front.jpg",
                tmp_path / "x_back.jpg",
                pair_key="x",
            )
        ],
    )
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET edition_id = ? WHERE job_id = ?",
            (incomplete.edition_id, job.id),
        )

    json_path = tmp_path / "books.json"
    jsonl_path = tmp_path / "books.jsonl"
    markdown_path = tmp_path / "notes"
    exporter = CatalogExporter(database)

    assert exporter.export_json(json_path).records == 1
    assert exporter.export_jsonl(jsonl_path).records == 1
    assert exporter.export_markdown(markdown_path).records == 1
    payload = json.loads(json_path.read_text(encoding="utf-8"))
    assert [item["title"] for item in payload["books"]] == ["İnce Memed"]
    assert len(jsonl_path.read_text(encoding="utf-8").splitlines()) == 1
    assert (markdown_path / "index.md").exists()
    assert len(list(markdown_path.glob("*.md"))) == 2


def test_exported_csv_and_json_can_be_imported_locally(tmp_path: Path) -> None:
    _database, source = _catalog(tmp_path)
    csv_path = tmp_path / "books.csv"
    json_path = tmp_path / "books.json"
    CatalogExporter(source).export_csv(csv_path)
    CatalogExporter(source).export_json(json_path)

    csv_catalog = Catalog(tmp_path / "csv.sqlite3")
    csv_result = import_local_catalog(csv_path, csv_catalog)
    assert csv_result.imported == 1
    assert csv_catalog.search("Yaşar").total == 1

    json_catalog = Catalog(tmp_path / "json.sqlite3")
    json_result = import_local_catalog(json_path, json_catalog)
    assert json_result.imported == 1
    book = json_catalog.list_books()[0]
    assert book.title == "İnce Memed"
    assert any(item.value == "9780140449136" for item in book.identifiers)


def test_four_surface_paths_round_trip_through_json_and_xlsx(tmp_path: Path) -> None:
    _database, source = _catalog(tmp_path)
    original = source.list_books()[0]
    source.set_cover_paths(
        original.edition_id,
        front_path="/books/front.jpg",
        front_inside_path="/books/front-inside.jpg",
        back_inside_path="/books/back-inside.jpg",
        back_path="/books/back.jpg",
    )
    json_path = tmp_path / "four.json"
    xlsx_path = tmp_path / "four.xlsx"

    CatalogExporter(source).export_json(json_path)
    CatalogExporter(source).export_xlsx(xlsx_path, completed_only=False)

    payload = json.loads(json_path.read_text(encoding="utf-8"))["books"][0]
    assert payload["front_inside_path"] == "/books/front-inside.jpg"
    assert payload["back_inside_path"] == "/books/back-inside.jpg"
    workbook = load_workbook(xlsx_path, read_only=True)
    headers = next(workbook["Kitaplar"].iter_rows(values_only=True))
    assert "Ön İç Kapak" in headers
    assert "Arka İç Kapak" in headers
    workbook.close()

    imported = Catalog(tmp_path / "roundtrip.sqlite3")
    assert import_local_catalog(json_path, imported).imported == 1
    restored = imported.list_books()[0]
    assert restored.front_inside_path == "/books/front-inside.jpg"
    assert restored.back_inside_path == "/books/back-inside.jpg"


def test_atomic_part_is_removed_when_xlsx_save_fails(tmp_path: Path, monkeypatch) -> None:
    _database, catalog = _catalog(tmp_path)
    target = tmp_path / "broken.xlsx"

    def fail(*_args, **_kwargs) -> None:
        raise OSError("disk full")

    monkeypatch.setattr("kitapkatalog.exporters.Workbook.save", fail)
    try:
        CatalogExporter(catalog).export_xlsx(target)
    except OSError:
        pass
    else:
        raise AssertionError("Beklenen yazma hatası oluşmadı")

    assert not target.exists()
    assert not (tmp_path / "broken.xlsx.part").exists()


def test_safe_onix_xml_import_and_doctype_rejection(tmp_path: Path) -> None:
    source = tmp_path / "catalog.xml"
    source.write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
        <ONIXMessage xmlns="http://ns.editeur.org/onix/3.0/reference">
          <Product>
            <DescriptiveDetail>
              <TitleDetail><TitleElement><TitleText>Dönüşüm</TitleText></TitleElement></TitleDetail>
              <Contributor><ContributorRole>A01</ContributorRole><PersonName>Franz Kafka</PersonName></Contributor>
              <Language><LanguageRole>01</LanguageRole><LanguageCode>tur</LanguageCode></Language>
            </DescriptiveDetail>
            <ProductIdentifier><ProductIDType>15</ProductIDType><IDValue>9780140449136</IDValue></ProductIdentifier>
            <PublishingDetail><Publisher><PublisherName>Yerel Yayın</PublisherName></Publisher></PublishingDetail>
          </Product>
        </ONIXMessage>
        """,
        encoding="utf-8",
    )
    catalog = Catalog(tmp_path / "onix.sqlite3")

    result = import_local_catalog(source, catalog)

    assert result.imported == 1
    book = catalog.list_books()[0]
    assert book.title == "Dönüşüm"
    assert book.publisher == "Yerel Yayın"
    assert book.contributors[0].name == "Franz Kafka"

    unsafe = tmp_path / "unsafe.xml"
    unsafe.write_text(
        '<!DOCTYPE x [<!ENTITY secret SYSTEM "file:///etc/passwd">]><ONIXMessage/>',
        encoding="utf-8",
    )
    with pytest.raises(ImportFormatError, match="DOCTYPE/ENTITY"):
        import_local_catalog(unsafe, catalog)


def test_xlsx_advanced_details_copies_and_stats(tmp_path: Path) -> None:
    _database, catalog = _catalog(tmp_path)
    book = catalog.save_book(
        BookInput(title="Dolaplı Kitap", category="Roman"),
    )
    catalog.set_location(book.edition_id, "A Dolabı")
    catalog.set_copy_count(book.edition_id, 2)
    target = tmp_path / "detay.xlsx"

    export_catalog(catalog, target, completed_only=False)

    workbook = load_workbook(target, read_only=True)
    kitaplar = list(workbook["Kitaplar"].iter_rows(values_only=True))
    header = list(kitaplar[0])
    assert "Dolap" in header and "Envanter Kodları" in header
    record_index = header.index("Kayıt No")
    row = next(r for r in kitaplar[1:] if r[record_index] == book.edition_id)
    assert row[header.index("Dolap")] == "A Dolabı"
    assert row[header.index("Nüsha Sayısı")] == 2

    nushalar = list(workbook["Nüshalar"].iter_rows(values_only=True))
    book_copies = [r for r in nushalar[1:] if r[0] == book.edition_id]
    assert len(book_copies) == 2
    assert {r[4] for r in book_copies} == {"A Dolabı"}

    stats = list(workbook["İstatistik"].iter_rows(values_only=True))
    assert any(r[0] == "Dolap" and r[1] == "A Dolabı" and r[2] == 2 for r in stats[1:])
    assert any(r[0] == "Kategori" and r[1] == "Roman" for r in stats[1:])

    ozet = list(workbook["Özet"].iter_rows(values_only=True))
    assert any(r[0] == "Farklı dolap" and r[1] == 1 for r in ozet[1:])
    workbook.close()

    formatted = load_workbook(target)
    assert formatted["Kitaplar"].freeze_panes == "A2"
    assert formatted["Kitaplar"].auto_filter.ref is not None
    assert formatted["Kitaplar"].column_dimensions["A"].width == 9
    formatted.close()


def test_csv_and_markdown_include_locations(tmp_path: Path) -> None:
    _database, catalog = _catalog(tmp_path)
    book = catalog.save_book(BookInput(title="Raftaki Kitap"))
    catalog.set_location(book.edition_id, "B Dolabı")

    csv_target = tmp_path / "dolap.csv"
    export_catalog(catalog, csv_target, completed_only=False)
    with csv_target.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    row = next(r for r in rows if r["Başlık"] == "Raftaki Kitap")
    assert row["Dolap"] == "B Dolabı"

    md_target = tmp_path / "notlar"
    export_catalog(catalog, md_target, format="markdown", completed_only=False)
    text = next(p for p in md_target.glob("*.md") if "Raftaki" in p.read_text()).read_text()
    assert "**Dolap:** B Dolabı" in text
    assert "## Nüshalar" in text
