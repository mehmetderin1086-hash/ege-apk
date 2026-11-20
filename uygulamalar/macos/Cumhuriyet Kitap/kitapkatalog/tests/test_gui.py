from __future__ import annotations

import os
from pathlib import Path
from types import SimpleNamespace

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

pytest.importorskip("PySide6")

from PySide6.QtCore import Qt
from PySide6.QtGui import QCloseEvent
from PySide6.QtWidgets import QApplication, QFileDialog, QMenu, QMessageBox

from kitapkatalog.calibration import ConfidenceCalibrationProfile
from kitapkatalog.capacity import CapacityEstimate
from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import (
    BookInput,
    ContributorInput,
    CoverRole,
    IdentifierInput,
    ImagePair,
    JobItemStage,
    OcrEngine,
)
from kitapkatalog.gui import MainWindow


@pytest.fixture(scope="module")
def application() -> QApplication:
    return QApplication.instance() or QApplication([])


def _close(window: object, application: QApplication) -> None:
    # Test cleanup is intentionally non-interactive. Individual close-guard
    # tests exercise the real dirty state before reaching this helper.
    window._library_loaded_state = None
    window.pool.waitForDone(5_000)
    window.close()
    application.processEvents()


def test_gui_pair_review_storage_default_isbn_and_turkish_status(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    front = tmp_path / "IMG_0001.JPG"
    back = tmp_path / "IMG_0002.JPG"
    front.write_bytes(b"front")
    back.write_bytes(b"back")
    job = database.create_import_job(
        "Belirsiz",
        [
            ImagePair(
                front,
                back,
                confidence=0.61,
                basis="exif_sequence",
                needs_review=True,
            )
        ],
    )
    book = Catalog(database).save_book(
        BookInput(
            title="Deneme",
            contributors=(ContributorInput("Ünal Akkemik", "editor"),),
            identifiers=(
                IdentifierInput("ISBN10", "0140449132"),
                IdentifierInput("ISBN13", "9780140449136"),
            ),
        )
    )

    window = MainWindow(database_path)
    window.pool.waitForDone(5_000)
    application.processEvents()
    window.refresh_all()
    window.pool.waitForDone(5_000)
    application.processEvents()

    assert window.storage_mode.currentData() == "managed_copy"
    assert window.pair_review_table.rowCount() == 1
    assert window.jobs_table.item(0, 2).text() == "Sırada"
    assert window._identifier(book) == "9780140449136"
    assert window._authors(book) == "Ünal Akkemik (editör)"
    window.jobs_table.selectRow(0)
    application.processEvents()
    assert "Hız:" in window.job_progress_label.text()
    assert "Kalan:" in window.job_progress_label.text()

    window.pair_review_table.selectRow(0)
    application.processEvents()
    window.approve_selected_pair()
    assert database.list_pending_pair_reviews(job_id=job.id) == []
    _close(window, application)


def test_gui_retry_preserves_success_and_resets_failed_engine(
    tmp_path: Path,
    application: QApplication,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    database = Database(database_path)
    job = database.create_import_job(
        "Hatalı kitap",
        [
            ImagePair(
                tmp_path / "book_front.jpg",
                tmp_path / "book_back.jpg",
                pair_key="book",
            )
        ],
    )
    item = database.claim_next_item("worker", job_id=job.id)
    assert item is not None
    database.advance_item(item.id, "worker", JobItemStage.PREPROCESSED)
    database.record_engine_success(
        item.id,
        CoverRole.FRONT,
        OcrEngine.RAPIDOCR,
        cache_key="keep-me",
        text="kalıcı",
        worker_id="worker",
    )
    for attempt in range(3):
        database.record_engine_failure(
            item.id,
            CoverRole.FRONT,
            OcrEngine.TESSERACT,
            f"hata {attempt}",
            worker_id="worker",
        )

    window = MainWindow(database_path)
    window.pool.waitForDone(5_000)
    application.processEvents()
    window.refresh_jobs()
    window.jobs_table.selectRow(0)
    application.processEvents()
    assert window.errors_table.rowCount() == 1
    window.errors_table.selectRow(0)
    window.retry_selected_item()

    rows = {
        row["engine_name"]: row
        for row in database.fetchall(
            """
            SELECT engine_name, status, attempt_count, cache_key, text, error
            FROM job_item_engine WHERE item_id = ?
            """,
            (item.id,),
        )
    }
    completed = rows[OcrEngine.RAPIDOCR.value]
    assert completed["status"] == "completed"
    assert completed["attempt_count"] == 1
    assert completed["cache_key"] == "keep-me"
    assert completed["text"] == "kalıcı"
    failed = rows[OcrEngine.TESSERACT.value]
    assert failed["status"] == "pending"
    assert failed["attempt_count"] == 0
    assert failed["cache_key"] is None
    assert failed["text"] is None
    assert failed["error"] is None
    assert window.errors_table.rowCount() == 0
    _close(window, application)


def test_gui_shows_all_four_surfaces_in_pair_review(
    tmp_path: Path,
    application: QApplication,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    paths = {
        role: tmp_path / f"book_{role}.jpg"
        for role in ("front", "front_inside", "back_inside", "back")
    }
    for path in paths.values():
        path.write_bytes(b"preview")
    database = Database(database_path)
    database.create_import_job(
        "Dört yüz",
        [
            ImagePair(
                front=paths["front"],
                front_inside=paths["front_inside"],
                back_inside=paths["back_inside"],
                back=paths["back"],
                needs_review=True,
                confidence=0.55,
                basis="four_document_sequence",
            )
        ],
    )

    window = MainWindow(database_path)
    window.pool.waitForDone(5_000)
    application.processEvents()
    window.refresh_pair_reviews()
    window.pair_review_table.selectRow(0)
    application.processEvents()

    assert window.pair_review_table.columnCount() == 9
    assert window.pair_review_table.item(0, 6).text() == "book_front_inside.jpg"
    assert window.pair_review_table.item(0, 7).text() == "book_back_inside.jpg"
    assert "Ön iç:" in window.pair_review_detail.text()
    assert "Arka iç:" in window.pair_review_detail.text()
    assert window.pair_front_inside_preview is not None
    assert window.pair_back_inside_preview is not None
    _close(window, application)


def test_gui_capacity_failure_is_fail_closed_before_enqueue(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    photos = tmp_path / "photos"
    photos.mkdir()
    (photos / "a_front.jpg").write_bytes(b"front")
    (photos / "a_back.jpg").write_bytes(b"back")
    database_path = tmp_path / "catalog.sqlite3"
    window = MainWindow(database_path)
    window.pool.waitForDone(5_000)
    application.processEvents()
    insufficient = CapacityEstimate(
        image_count=2,
        source_bytes=9,
        managed_copy_bytes=9,
        derivative_bytes=27,
        ocr_evidence_bytes=100,
        database_bytes=100,
        model_bytes=100,
        reserve_bytes=100,
        required_additional_bytes=436,
        free_bytes=10,
    )
    errors: list[str] = []
    monkeypatch.setattr(
        "kitapkatalog.gui.estimate_import_capacity",
        lambda *_args, **_kwargs: insufficient,
    )
    monkeypatch.setattr(
        QFileDialog,
        "getExistingDirectory",
        lambda *_args, **_kwargs: str(photos),
    )
    monkeypatch.setattr(
        QMessageBox,
        "critical",
        lambda _parent, _title, message: errors.append(message),
    )

    window.choose_import_folder()
    window.pool.waitForDone(5_000)
    application.processEvents()

    assert errors and "Yetersiz disk alanı" in errors[0]
    assert Database(database_path).list_import_jobs() == []
    _close(window, application)


def _seed_library(database_path: Path) -> tuple[Catalog, int, int]:
    catalog = Catalog(Database(database_path))
    first = catalog.save_book(
        BookInput(title="Tutunamayanlar", publisher="İletişim", language="Türkçe"),
        source_fingerprint="test:1",
    )
    second = catalog.save_book(
        BookInput(title="Kürk Mantolu Madonna", language="Türkçe"),
        source_fingerprint="test:2",
    )
    catalog.update_book(second.edition_id, {"review_status": "completed"}, user_edit=False)
    return catalog, first.edition_id, second.edition_id


def _library_row_of(table: object, edition_id: int) -> int:
    from PySide6.QtCore import Qt

    for row in range(table.rowCount()):
        item = table.item(row, 0)
        if item and item.data(Qt.ItemDataRole.UserRole) == edition_id:
            return row
    raise AssertionError(f"Baskı {edition_id} kütüphane tablosunda yok")


def _library_window(database_path: Path, application: QApplication) -> MainWindow:
    window = MainWindow(database_path)
    window.pool.waitForDone(5_000)
    application.processEvents()
    window.refresh_all()
    window.pool.waitForDone(5_000)
    application.processEvents()
    return window


def test_gui_library_detail_fills_on_selection(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    assert not window.library_save_button.isEnabled()
    window.library_table.selectRow(_library_row_of(window.library_table, first_id))
    application.processEvents()

    assert window.library_title.text() == "Tutunamayanlar"
    assert window.library_publisher.text() == "İletişim"
    assert window.library_language.text() == "Türkçe"
    assert window.library_copy_label.text() == "Adet: 1"
    assert window.library_save_button.isEnabled()
    assert window.library_delete_button.isEnabled()
    assert window.library_copy_add.isEnabled()
    assert not window.library_copy_remove.isEnabled()
    _close(window, application)


def test_gui_library_edit_saves_without_touching_review_status(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.library_table.selectRow(_library_row_of(window.library_table, first_id))
    application.processEvents()
    window.library_subtitle.setText("Bir Oğuz Atay Romanı")
    window.library_pages.setValue(724)
    window.save_library_edit()
    application.processEvents()

    book = catalog.get_book(first_id)
    assert book is not None
    assert book.subtitle == "Bir Oğuz Atay Romanı"
    assert book.page_count == 724
    assert book.review_status == "review"
    _close(window, application)


def test_gui_library_copy_add_and_remove(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.library_table.selectRow(_library_row_of(window.library_table, first_id))
    application.processEvents()
    window.add_library_copy()
    application.processEvents()

    assert window.library_copy_label.text() == "Adet: 2"
    assert window.library_copy_remove.isEnabled()
    book = catalog.get_book(first_id)
    assert book is not None and len(book.copies) == 2
    row = _library_row_of(window.library_table, first_id)
    assert window.library_table.item(row, 11).text() == "2"

    window.remove_library_copy()
    application.processEvents()
    assert window.library_copy_label.text() == "Adet: 1"
    assert not window.library_copy_remove.isEnabled()
    book = catalog.get_book(first_id)
    assert book is not None and len(book.copies) == 1
    _close(window, application)


def test_gui_library_delete_removes_book_after_confirmation(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, _first_id, second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *_args, **_kwargs: QMessageBox.StandardButton.Yes,
    )
    window.library_table.selectRow(_library_row_of(window.library_table, second_id))
    application.processEvents()
    window.delete_library_book()
    application.processEvents()

    assert catalog.get_book(second_id) is None
    with pytest.raises(AssertionError):
        _library_row_of(window.library_table, second_id)
    assert not window.library_save_button.isEnabled()
    assert window._selected_library_id is None
    _close(window, application)


def test_gui_library_status_filter_narrows_results(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _catalog, _first_id, second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    assert window.library_table.rowCount() == 2
    index = window.library_status_filter.findData("completed")
    assert index >= 0
    window.library_status_filter.setCurrentIndex(index)
    window.refresh_library()
    application.processEvents()

    assert window.library_table.rowCount() == 1
    assert _library_row_of(window.library_table, second_id) == 0
    assert window.library_table.item(0, 13).text() == "Tamamlandı"
    _close(window, application)


def _write_test_image(path: Path) -> Path:
    from PySide6.QtGui import QImage

    image = QImage(20, 28, QImage.Format.Format_RGB32)
    image.fill(0xFF3366AA)
    assert image.save(str(path), "PNG")
    return path


def test_gui_library_columns_and_numeric_sort(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(Database(database_path))
    small = catalog.save_book(
        BookInput(title="İnce Kitap", page_count=9, language="Türkçe"),
        source_fingerprint="test:small",
    )
    big = catalog.save_book(
        BookInput(title="Kalın Kitap", page_count=100, language="Türkçe"),
        source_fingerprint="test:big",
    )
    catalog.set_isbn(big.edition_id, "9789754700114")
    window = _library_window(database_path, application)

    headers = [
        window.library_table.horizontalHeaderItem(i).text()
        for i in range(window.library_table.columnCount())
    ]
    assert headers == [
        "Ön Kapak",
        "Arka Kapak",
        "No",
        "ISBN",
        "Başlık",
        "Yazar / Katkıda Bulunan",
        "Yayınevi",
        "Basım Tarihi",
        "Sayfa",
        "Dil",
        "Kategori",
        "Adet",
        "Dolap",
        "Durum",
    ]
    big_row = _library_row_of(window.library_table, big.edition_id)
    assert window.library_table.item(big_row, 3).text() == "9789754700114"
    assert window.library_table.item(big_row, 8).text() == "100"

    from PySide6.QtCore import Qt

    window.library_table.sortItems(8, Qt.SortOrder.AscendingOrder)
    assert _library_row_of(window.library_table, small.edition_id) == 0
    assert _library_row_of(window.library_table, big.edition_id) == 1
    _close(window, application)


def test_gui_library_missing_filter(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _catalog, first_id, second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    index = window.library_missing_filter.findData("publisher")
    assert index >= 0
    window.library_missing_filter.setCurrentIndex(index)
    window.refresh_library()
    application.processEvents()

    assert window.library_table.rowCount() == 1
    assert _library_row_of(window.library_table, second_id) == 0
    assert first_id not in {
        window.library_table.item(row, 0).data(0x0100)
        for row in range(window.library_table.rowCount())
    }
    _close(window, application)


def test_gui_library_detail_edits_isbn_and_authors(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.library_table.selectRow(_library_row_of(window.library_table, first_id))
    application.processEvents()
    window.library_isbn.setText("978-975-470-011-4")
    window.library_authors.setText("Oğuz Atay; Vüs'at O. Bener")
    window.library_series.setText("Modern Klasikler")
    window.save_library_edit()
    application.processEvents()

    book = catalog.get_book(first_id)
    assert book is not None
    assert {i.scheme for i in book.identifiers} == {"ISBN10", "ISBN13"}
    authors = [c.name for c in book.contributors if str(c.role) == "author"]
    assert authors == ["Oğuz Atay", "Vüs'at O. Bener"]
    assert book.series == "Modern Klasikler"
    _close(window, application)


def test_gui_library_thumbnails_and_cover_assign(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    cover = _write_test_image(tmp_path / "kapak.png")
    catalog.set_cover_paths(first_id, front_path=cover)
    window = _library_window(database_path, application)

    front_cache, _back_cache = window._thumb_cache_paths(first_id)
    assert front_cache.is_file()
    row = _library_row_of(window.library_table, first_id)
    assert not window.library_table.item(row, 0).icon().isNull()

    new_cover = _write_test_image(tmp_path / "yeni-kapak.png")
    monkeypatch.setattr(
        QFileDialog,
        "getOpenFileName",
        lambda *_args, **_kwargs: (str(new_cover), ""),
    )
    window.library_table.selectRow(row)
    application.processEvents()
    window.assign_library_cover("front")
    window.pool.waitForDone(5_000)
    application.processEvents()

    book = catalog.get_book(first_id)
    assert book is not None
    assert book.front_path == str(new_cover)
    _close(window, application)


def test_gui_new_book_from_values_and_isbn_merge(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(Database(database_path))
    window = _library_window(database_path, application)

    values = {
        "isbn": "9789754700114",
        "title": "Yeni Roman",
        "authors": ["Adalet Ağaoğlu"],
        "publisher": "YKY",
        "publication_date": "1973",
        "page_count": 300,
        "language": "Türkçe",
        "category": "Roman",
        "copies": 2,
        "front": None,
        "back": None,
    }
    window._create_book_from_values(values)
    application.processEvents()

    book = catalog.get_by_identifier("ISBN", "9789754700114")
    assert book is not None
    assert book.title == "Yeni Roman"
    assert book.review_status == "completed"
    assert len(book.copies) == 2
    authors = [c.name for c in book.contributors if str(c.role) == "author"]
    assert authors == ["Adalet Ağaoğlu"]

    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *_args, **_kwargs: QMessageBox.StandardButton.Yes,
    )
    window._create_book_from_values({**values, "copies": 1})
    application.processEvents()
    book = catalog.get_by_identifier("ISBN", "9789754700114")
    assert book is not None and len(book.copies) == 3
    _close(window, application)


def test_gui_bulk_approve_and_delete(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.library_table.selectAll()
    application.processEvents()
    window.approve_selected_books()
    window.pool.waitForDone(5_000)
    application.processEvents()
    for edition_id in (first_id, second_id):
        book = catalog.get_book(edition_id)
        assert book is not None and book.review_status == "completed"

    window.library_table.selectAll()
    application.processEvents()
    monkeypatch.setattr(
        QMessageBox,
        "question",
        lambda *_args, **_kwargs: QMessageBox.StandardButton.Yes,
    )
    window.delete_selected_books()
    window.pool.waitForDone(5_000)
    application.processEvents()
    assert window.library_table.rowCount() == 0
    assert catalog.get_book(first_id) is None
    assert catalog.get_book(second_id) is None
    _close(window, application)


def test_gui_stats_tab_contents(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _seed_library(database_path)
    window = _library_window(database_path, application)

    assert "2 baskı" in window.stats_summary.text()
    language_table = window.stats_tables["language"]
    values = {
        language_table.item(row, 0).text(): language_table.item(row, 1).text()
        for row in range(language_table.rowCount())
    }
    assert values == {"Türkçe": "2"}
    status_table = window.stats_tables["review_status"]
    labels = {status_table.item(row, 0).text() for row in range(status_table.rowCount())}
    assert "İnceleme gerekli" in labels or "Tamamlandı" in labels
    _close(window, application)


def test_gui_library_location_and_copy_count_single(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.library_table.selectRow(_library_row_of(window.library_table, first_id))
    application.processEvents()
    window.library_location.setText("A Dolabı")
    window.save_library_edit()
    application.processEvents()

    book = catalog.get_book(first_id)
    assert book is not None
    assert [c.location for c in book.copies] == ["A Dolabı"]
    row = _library_row_of(window.library_table, first_id)
    assert window.library_table.item(row, 12).text() == "A Dolabı"

    window.library_copy_spin.setValue(3)
    window.apply_library_copy_count()
    application.processEvents()
    book = catalog.get_book(first_id)
    assert book is not None
    assert len(book.copies) == 3
    assert {c.location for c in book.copies} == {"A Dolabı"}
    assert window.library_copy_label.text() == "Adet: 3"
    _close(window, application)


def test_gui_bulk_location_and_copy_count(
    tmp_path: Path,
    application: QApplication,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from PySide6.QtWidgets import QInputDialog

    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    monkeypatch.setattr(
        QInputDialog,
        "getItem",
        lambda *_args, **_kwargs: ("Depo Rafı", True),
    )
    window.library_table.selectAll()
    application.processEvents()
    window.assign_location_to_selected()
    window.pool.waitForDone(5_000)
    application.processEvents()
    for edition_id in (first_id, second_id):
        book = catalog.get_book(edition_id)
        assert book is not None
        assert {c.location for c in book.copies} == {"Depo Rafı"}

    monkeypatch.setattr(
        QInputDialog,
        "getInt",
        lambda *_args, **_kwargs: (2, True),
    )
    window.library_table.selectAll()
    application.processEvents()
    window.assign_copy_count_to_selected()
    window.pool.waitForDone(5_000)
    application.processEvents()
    for edition_id in (first_id, second_id):
        book = catalog.get_book(edition_id)
        assert book is not None
        assert len(book.copies) == 2
        assert {c.location for c in book.copies} == {"Depo Rafı"}  # devralındı
    _close(window, application)


def test_gui_new_book_with_location(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(Database(database_path))
    window = _library_window(database_path, application)

    window._create_book_from_values(
        {
            "isbn": "",
            "title": "Dolaplı Kitap",
            "authors": [],
            "publisher": None,
            "publication_date": None,
            "page_count": None,
            "language": None,
            "category": None,
            "copies": 2,
            "location": "C Dolabı",
            "front": None,
            "back": None,
        }
    )
    application.processEvents()

    page = catalog.search("Dolaplı Kitap")
    assert page.total == 1
    book = page.items[0]
    assert len(book.copies) == 2
    assert {c.location for c in book.copies} == {"C Dolabı"}
    _close(window, application)


def test_gui_voice_location_sticky_and_in_form_values(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    window = _library_window(database_path, application)

    window.voice_location.setCurrentText("A Dolabı")
    window.voice_title.setText("Kar")
    window._voice_clear(after_save=True)

    assert window.voice_title.text() == ""  # form temizlendi
    assert window.voice_location.currentText() == "A Dolabı"  # dolap yapışkan
    assert window._voice_form_values()["location"] == "A Dolabı"
    _close(window, application)


def test_gui_voice_recent_list_and_focus(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window._voice_recent_add(first_id, "Tutunamayanlar", approved=True)
    assert window.voice_recent_list.count() == 1
    assert "Tutunamayanlar" in window.voice_recent_list.item(0).text()
    for extra in range(12):
        window._voice_recent_add(900 + extra, f"Kitap {extra}", approved=False)
    assert window.voice_recent_list.count() == 10  # üst sınır

    window.tabs.setCurrentIndex(2)
    window._focus_library_book(first_id)
    application.processEvents()
    assert window.tabs.currentIndex() == 0
    assert window._selected_library_id == first_id
    assert window.library_title.text() == "Tutunamayanlar"
    _close(window, application)


def test_gui_voice_enqueue_files_used_by_drop_and_dialog(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    window = _library_window(database_path, application)

    class FakeScheduler:
        def __init__(self) -> None:
            self.enqueued: list[Path] = []

        def enqueue(self, path: Path) -> None:
            self.enqueued.append(Path(path))

    fake = FakeScheduler()
    window._voice_batch_scheduler = fake
    files = [str(tmp_path / "raf1.m4a"), str(tmp_path / "raf2.mp3")]
    window._enqueue_voice_files(files)
    window.pool.waitForDone(5_000)
    application.processEvents()
    assert [p.name for p in fake.enqueued] == ["raf1.m4a", "raf2.mp3"]
    _close(window, application)


def test_gui_review_location_saved(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog, first_id, _second_id = _seed_library(database_path)
    window = _library_window(database_path, application)

    window.review_table.selectRow(0)
    application.processEvents()
    assert window._selected_review_id == first_id
    window.review_location.setText("İnceleme Dolabı")
    window.save_review()
    application.processEvents()

    book = catalog.get_book(first_id)
    assert book is not None
    assert {c.location for c in book.copies} == {"İnceleme Dolabı"}
    assert book.review_status == "completed"
    _close(window, application)


def _reviewed_fields(database: Database, *, books: int) -> None:
    """Propose a value for each book, then have the user confirm or replace it."""

    catalog = Catalog(database)
    now = "2026-01-01T00:00:00+00:00"
    for index in range(books):
        edition = catalog.save_book(BookInput(title=f"Kitap {index}", publisher="Yayınevi"))
        with database.transaction() as connection:
            for field_path, value, confidence in (
                ("edition.title", f"Kitap {index}", 0.97),
                ("edition.publisher", "Yayinevi", 0.55),
            ):
                connection.execute(
                    """
                    INSERT INTO field_observation (
                        edition_id, field_path, raw_value, normalized_value,
                        confidence, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (edition.edition_id, field_path, value, value, confidence, now),
                )
        catalog.update_book(
            edition.edition_id,
            {"title": f"Kitap {index}", "publisher": "Yayınevi"},
            user_edit=True,
        )


def test_review_tab_reports_the_distance_to_automatic_acceptance(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _reviewed_fields(Database(database_path), books=3)
    window = MainWindow(database_path)
    try:
        window.refresh_calibration_status()

        assert window.calibration_progress.value() == 6
        assert window.calibration_progress.maximum() == 200
        message = window.calibration_status.text()
        assert "Otomatik kabul kapalı" in message
        assert "194 örnek daha" in message
        # Fitting a profile from six samples would not be trusted anyway.
        assert not window.calibration_button.isEnabled()
    finally:
        _close(window, application)


def test_review_tab_offers_to_build_the_profile_once_enough_fields_are_reviewed(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    data_root = tmp_path / "veri"
    data_root.mkdir()
    monkeypatch.setenv("KITAPKATALOG_DATA_DIR", str(data_root))
    database_path = data_root / "catalog.sqlite3"
    _reviewed_fields(Database(database_path), books=120)
    window = MainWindow(database_path)
    try:
        window.refresh_calibration_status()
        assert window.calibration_button.isEnabled()

        window.build_calibration_profile()
        window.pool.waitForDone(20_000)
        application.processEvents()

        profile_path = data_root / "calibration" / "ensemble.json"
        assert profile_path.is_file()
        # The switch itself: a trusted profile is what lets consensus accept.
        profile = ConfidenceCalibrationProfile.load(profile_path)
        assert profile.trusted
        assert profile.total_samples == 240
    finally:
        _close(window, application)


def _review_queue(database: Database, *, books: int) -> None:
    catalog = Catalog(database)
    for index in range(books):
        record = catalog.save_book(BookInput(title=f"İnceleme {index}"))
        catalog.update_book(record.edition_id, {"review_status": "review"})


def test_menu_bar_exposes_global_shortcuts(tmp_path: Path, application: QApplication) -> None:
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        titles = [menu.title() for menu in window.menuBar().findChildren(QMenu)]
        assert {"&Dosya", "&Düzen", "&Görünüm"} <= set(titles)
        bound = {
            action.shortcut().toString()
            for action in window.actions()
            if not action.shortcut().isEmpty()
        }
        # Until now the only shortcuts in the whole app were on the voice tab.
        assert "Ctrl+F" in bound
        assert "Ctrl+S" in bound
        assert "Ctrl+1" in bound
        assert f"Ctrl+{window.tabs.count()}" in bound
    finally:
        _close(window, application)


def test_find_shortcut_moves_focus_to_the_search_box(
    tmp_path: Path, application: QApplication
) -> None:
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        window.tabs.setCurrentIndex(3)

        window.focus_search()

        assert window.tabs.currentIndex() == 0
        # hasFocus() needs an active window, which an offscreen test has not got;
        # focusWidget() reports the same intent without one.
        assert window.focusWidget() is window.search_edit
    finally:
        _close(window, application)


def test_review_save_advances_to_the_next_pending_record(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    _review_queue(Database(database_path), books=3)
    window = MainWindow(database_path)
    try:
        window.refresh_review()
        assert window.review_table.rowCount() == 3
        window.review_table.selectRow(0)
        first = window._selected_review_id

        window.save_review_and_advance()

        assert window.review_table.rowCount() == 2
        # Reviewing hundreds of records must not mean returning to the table
        # with the mouse after every single one.
        assert window._selected_review_id is not None
        assert window._selected_review_id != first
    finally:
        _close(window, application)


def test_switching_rows_with_unsaved_edits_asks_first(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(Database(database_path))
    catalog.save_book(BookInput(title="Birinci"))
    catalog.save_book(BookInput(title="İkinci"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()
        window.library_table.selectRow(0)
        original = window._selected_library_id
        window.library_title.setText("Elle düzenlenmiş başlık")

        asked: list[str] = []
        monkeypatch.setattr(
            QMessageBox,
            "question",
            lambda *args, **kwargs: (
                asked.append(args[2]),
                QMessageBox.StandardButton.Cancel,
            )[1],
        )
        window.library_table.selectRow(1)

        assert asked, "kaydedilmemiş düzenleme sessizce atılmamalı"
        # Cancelling keeps the edited record on screen instead of losing the work.
        assert window._selected_library_id == original
        assert window.library_title.text() == "Elle düzenlenmiş başlık"
    finally:
        _close(window, application)


def test_switching_tabs_with_unsaved_library_edits_can_cancel_or_discard(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    Catalog(Database(database_path)).save_book(BookInput(title="Korunacak Başlık"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()
        window.library_table.selectRow(0)
        application.processEvents()
        window.library_title.setText("Henüz kaydedilmedi")

        answers = [
            QMessageBox.StandardButton.Cancel,
            QMessageBox.StandardButton.Discard,
        ]
        prompts: list[str] = []
        monkeypatch.setattr(
            QMessageBox,
            "question",
            lambda *args, **kwargs: (prompts.append(args[2]), answers.pop(0))[1],
        )

        window.tabs.setCurrentIndex(1)
        application.processEvents()

        assert window.tabs.currentIndex() == 0
        assert window.library_title.text() == "Henüz kaydedilmedi"
        assert window._library_detail_is_dirty() is True

        window.tabs.setCurrentIndex(1)
        application.processEvents()

        assert window.tabs.currentIndex() == 1
        assert window.library_title.text() == "Korunacak Başlık"
        assert window._library_detail_is_dirty() is False
        assert len(prompts) == 2
    finally:
        _close(window, application)


def test_cancelled_close_keeps_context_timer_and_unsaved_edit(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    Catalog(Database(database_path)).save_book(BookInput(title="Açık Kalacak"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()
        window.library_table.selectRow(0)
        application.processEvents()
        window.library_title.setText("Kaydedilmemiş")
        monkeypatch.setattr(
            QMessageBox,
            "question",
            lambda *args, **kwargs: QMessageBox.StandardButton.Cancel,
        )
        event = QCloseEvent()

        window.closeEvent(event)

        assert event.isAccepted() is False
        assert window.library_title.text() == "Kaydedilmemiş"
        assert window.refresh_timer.isActive() is True
        assert window._application_context.app_lock is not None
    finally:
        _close(window, application)


def test_large_bulk_edits_are_confirmed_but_small_ones_are_not(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        prompts: list[str] = []
        monkeypatch.setattr(
            QMessageBox,
            "question",
            lambda *args, **kwargs: (
                prompts.append(args[2]),
                QMessageBox.StandardButton.Yes,
            )[1],
        )

        assert window._confirm_bulk_change(3, "kategori “Roman”") is True
        assert prompts == []

        assert window._confirm_bulk_change(40, "kategori “Roman”") is True
        assert len(prompts) == 1
        assert "geri alınamaz" in prompts[0]
    finally:
        _close(window, application)


def test_window_geometry_and_column_widths_survive_a_restart(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    window = MainWindow(database_path)
    window.resize(1100, 700)
    window.library_table.horizontalHeader().resizeSection(1, 321)
    window._save_window_state()
    _close(window, application)

    reopened = MainWindow(database_path)
    try:
        # Nothing about the window used to persist: every launch reset to a
        # fixed size and default column widths.
        assert reopened.library_table.horizontalHeader().sectionSize(1) == 321
    finally:
        _close(reopened, application)


def test_empty_tables_say_what_to_do_next(tmp_path: Path, application: QApplication) -> None:
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        window.refresh_all()

        hint = window._empty_hints[id(window.library_table)]
        assert hint.isVisibleTo(window.library_table.viewport())
        assert "İçe Aktarma" in hint.text()
        # A placeholder row would make an empty catalogue look like one record,
        # and paging, selection and "save and move on" all read rowCount().
        assert window.library_table.rowCount() == 0
    finally:
        _close(window, application)


def test_the_hint_disappears_once_there_is_something_to_show(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    Catalog(Database(database_path)).save_book(BookInput(title="Tutunamayanlar"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()

        assert window.library_table.rowCount() == 1
        assert window._empty_hints[id(window.library_table)].isHidden()
    finally:
        _close(window, application)


def test_every_toolbar_control_explains_itself(tmp_path: Path, application: QApplication) -> None:
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        # The window had no tooltips and no accessible names at all: each
        # control was a bare label with no way to learn what it does.
        for widget in (
            window.search_edit,
            window.library_status_filter,
            window.library_missing_filter,
            window.process_button,
            window.retry_button,
        ):
            assert widget.toolTip(), widget
            assert widget.accessibleName(), widget
    finally:
        _close(window, application)


def test_a_dropped_folder_is_queued_for_import(
    tmp_path: Path, application: QApplication, monkeypatch: pytest.MonkeyPatch
) -> None:
    from PySide6.QtCore import QMimeData, QUrl

    folder = tmp_path / "kapaklar"
    folder.mkdir()
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        queued: list[Path] = []
        monkeypatch.setattr(type(window), "import_folder", lambda _self, path: queued.append(path))
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(str(folder))])

        assert window._dropped_folders(SimpleNamespace(mimeData=lambda: mime)) == [folder]
        window.dropEvent(
            SimpleNamespace(
                mimeData=lambda: mime,
                acceptProposedAction=lambda: None,
            )
        )

        assert queued == [folder]
        # Dropping is the natural gesture for this application, and it lands on
        # the tab that shows what happened.
        assert window.tabs.currentIndex() == 1
    finally:
        _close(window, application)


def test_a_dropped_photograph_stands_for_its_folder(
    tmp_path: Path, application: QApplication
) -> None:
    from PySide6.QtCore import QMimeData, QUrl

    folder = tmp_path / "kapaklar"
    folder.mkdir()
    photo = folder / "IMG_0001.JPG"
    photo.write_bytes(b"x")
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(str(photo))])

        assert window._dropped_folders(SimpleNamespace(mimeData=lambda: mime)) == [folder]
    finally:
        _close(window, application)


def test_unrelated_files_are_not_accepted_as_a_drop(
    tmp_path: Path, application: QApplication
) -> None:
    from PySide6.QtCore import QMimeData, QUrl

    other = tmp_path / "notlar.txt"
    other.write_text("x", encoding="utf-8")
    window = MainWindow(tmp_path / "catalog.sqlite3")
    try:
        mime = QMimeData()
        mime.setUrls([QUrl.fromLocalFile(str(other))])

        assert window._dropped_folders(SimpleNamespace(mimeData=lambda: mime)) == []
    finally:
        _close(window, application)


def test_free_text_fields_suggest_values_already_in_the_catalogue(
    tmp_path: Path, application: QApplication
) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    catalog = Catalog(Database(database_path))
    catalog.save_book(BookInput(title="Bir", publisher="Yapı Kredi Yayınları", language="tr"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()

        completer = window.library_publisher.completer()
        assert completer is not None
        model = completer.model()
        values = [model.index(row, 0).data() for row in range(model.rowCount())]
        # Retyping a publisher per book is how one imprint ends up spelled
        # three different ways.
        assert "Yapı Kredi Yayınları" in values
    finally:
        _close(window, application)


def test_tables_offer_copy_on_right_click(tmp_path: Path, application: QApplication) -> None:
    database_path = tmp_path / "catalog.sqlite3"
    Catalog(Database(database_path)).save_book(BookInput(title="Kürk Mantolu Madonna"))
    window = MainWindow(database_path)
    try:
        window.refresh_library()

        # The tables are read-only, so without this a title could only be
        # copied out of the catalogue by retyping it.
        assert window.library_table.contextMenuPolicy() == Qt.ContextMenuPolicy.CustomContextMenu
        assert window.review_table.contextMenuPolicy() == Qt.ContextMenuPolicy.CustomContextMenu
    finally:
        _close(window, application)
