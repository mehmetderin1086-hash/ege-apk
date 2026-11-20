"""Optional PySide6 desktop interface.

PySide6 is imported lazily so the headless CLI and exporters remain usable
without the ``ui`` extra.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Callable, Sequence
from contextlib import suppress
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

from kitapkatalog.archive import create_archive
from kitapkatalog.calibration import (
    ConfidenceCalibrationProfile,
    ReviewLabel,
    fit_isotonic_profile,
    samples_from_reviews,
)
from kitapkatalog.capacity import estimate_import_capacity, require_capacity
from kitapkatalog.catalog import IdentifierConflictError
from kitapkatalog.config import AppPaths
from kitapkatalog.documents import (
    build_single_book_scan,
    expand_bulk_documents,
    pdf_page_count,
)
from kitapkatalog.domain import (
    BookInput,
    BookRecord,
    ContributorInput,
    CopyInput,
    IdentifierInput,
    SearchFilters,
    StorageMode,
)
from kitapkatalog.exporters import ExportFormat, export_catalog
from kitapkatalog.offline import install_network_guard
from kitapkatalog.pairing import discover_documents, pair_cover_files
from kitapkatalog.qtenv import ensure_qt_plugins_visible


class QtUnavailableError(RuntimeError):
    """The optional desktop dependency is not installed."""


_MAIN_WINDOW_CLASS: type[Any] | None = None

_STATUS_TR = {
    "queued": "Sırada",
    "running": "Çalışıyor",
    "paused": "Duraklatıldı",
    "completed": "Tamamlandı",
    "completed_with_errors": "Hatalarla tamamlandı",
    "cancelled": "İptal edildi",
    "pending": "Bekliyor",
    "failed": "Başarısız",
    "review": "İnceleme gerekli",
    "unresolved": "Çözümlenmedi",
    "confirmed": "Kullanıcı onaylı",
    "auto": "Otomatik kabul",
}

_ENGINE_NAMES = {
    "rapidocr_ppocrv6": "RapidOCR + PP-OCRv6",
    "tesseract": "Tesseract 5",
    "easyocr": "EasyOCR",
    "paddleocr_vl": "PaddleOCR-VL",
    "surya": "Surya OCR 2",
    "qwen3": "Qwen3 alan çıkarıcı",
}


def _paths_for_database(path: str | Path | None) -> AppPaths:
    defaults = AppPaths.default()
    if path is None:
        return defaults
    database = Path(path).expanduser()
    if database.resolve() == defaults.database.resolve():
        return defaults
    root = database.parent
    return AppPaths(
        root=root,
        database=database,
        assets=root / "assets",
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=defaults.models,
        exports=root / "exports",
        logs=root / "logs",
        owns_data_root=False,
    )


def _build_main_window_class() -> type[Any]:
    global _MAIN_WINDOW_CLASS
    if _MAIN_WINDOW_CLASS is not None:
        return _MAIN_WINDOW_CLASS
    try:
        from PySide6.QtCore import (
            QObject,
            QRunnable,
            QSettings,
            QSize,
            Qt,
            QThreadPool,
            QTimer,
            Signal,
        )
        from PySide6.QtGui import (
            QAction,
            QIcon,
            QImage,
            QKeySequence,
            QPalette,
            QPixmap,
            QShortcut,
        )
        from PySide6.QtWidgets import (
            QAbstractItemView,
            QApplication,
            QCheckBox,
            QComboBox,
            QCompleter,
            QDialog,
            QDialogButtonBox,
            QFileDialog,
            QFormLayout,
            QGridLayout,
            QGroupBox,
            QHBoxLayout,
            QHeaderView,
            QInputDialog,
            QLabel,
            QLineEdit,
            QListWidget,
            QMainWindow,
            QMenu,
            QMessageBox,
            QPlainTextEdit,
            QProgressBar,
            QPushButton,
            QSpinBox,
            QSplitter,
            QStatusBar,
            QTableWidget,
            QTableWidgetItem,
            QTabWidget,
            QVBoxLayout,
            QWidget,
        )
    except ModuleNotFoundError as exc:
        raise QtUnavailableError(
            "Masaüstü arayüzü için PySide6 kurulu değil. "
            "Uygulamayı `pip install 'kitapkatalog[ui]'` ile kurun."
        ) from exc

    class WorkerSignals(QObject):
        succeeded = Signal(object)
        failed = Signal(str)
        finished = Signal()

    class Worker(QRunnable):
        def __init__(self, function: Callable[[], Any]) -> None:
            super().__init__()
            self.function = function
            self.signals = WorkerSignals()

        def run(self) -> None:
            try:
                result = self.function()
            except BaseException as exc:
                with suppress(RuntimeError):
                    self.signals.failed.emit(f"{type(exc).__name__}: {exc}")
            else:
                with suppress(RuntimeError):
                    self.signals.succeeded.emit(result)
            finally:
                with suppress(RuntimeError):
                    self.signals.finished.emit()

    class ClickableLabel(QLabel):
        clicked = Signal()

        def mousePressEvent(self, event: Any) -> None:
            self.clicked.emit()
            super().mousePressEvent(event)

    class AudioDropGroupBox(QGroupBox):
        """Ses dosyalarını sürükle-bırakla kabul eden grup kutusu."""

        filesDropped = Signal(list)
        _EXTENSIONS = (".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg")

        def __init__(self, title: str) -> None:
            super().__init__(title)
            self.setAcceptDrops(True)

        def _audio_paths(self, event: Any) -> list[str]:
            mime = event.mimeData()
            if not mime.hasUrls():
                return []
            return [
                url.toLocalFile()
                for url in mime.urls()
                if url.isLocalFile() and url.toLocalFile().casefold().endswith(self._EXTENSIONS)
            ]

        def dragEnterEvent(self, event: Any) -> None:
            if self._audio_paths(event):
                event.acceptProposedAction()

        def dropEvent(self, event: Any) -> None:
            paths = self._audio_paths(event)
            if paths:
                event.acceptProposedAction()
                self.filesDropped.emit(paths)

    class NewBookDialog(QDialog):
        """Elle (fotoğrafsız/sessiz) hızlı kitap girişi."""

        def __init__(
            self,
            parent: Any,
            *,
            categories: list[str],
            languages: list[str],
            locations: list[str] | None = None,
        ) -> None:
            super().__init__(parent)
            self.setWindowTitle("Yeni Kitap")
            self.front_path: str | None = None
            self.back_path: str | None = None
            form = QFormLayout(self)
            self.isbn = QLineEdit()
            self.isbn.setPlaceholderText("İsteğe bağlı; 10 veya 13 hane")
            self.title = QLineEdit()
            self.authors = QLineEdit()
            self.authors.setPlaceholderText("Birden fazlaysa ; ile ayırın")
            self.publisher = QLineEdit()
            self.publication_date = QLineEdit()
            self.pages = QSpinBox()
            self.pages.setRange(0, 99_999)
            self.pages.setSpecialValueText("—")
            self.language = QComboBox()
            self.language.setEditable(True)
            self.language.addItem("")
            for value in languages:
                self.language.addItem(value)
            self.category = QComboBox()
            self.category.setEditable(True)
            self.category.addItem("")
            for value in categories:
                self.category.addItem(value)
            self.copies = QSpinBox()
            self.copies.setRange(1, 99)
            self.location = QComboBox()
            self.location.setEditable(True)
            self.location.addItem("")
            for value in locations or []:
                self.location.addItem(value)
            self.front_button = QPushButton("Ön kapak görseli seç…")
            self.front_button.clicked.connect(lambda: self._choose_cover("front"))
            self.back_button = QPushButton("Arka kapak görseli seç…")
            self.back_button.clicked.connect(lambda: self._choose_cover("back"))
            form.addRow("ISBN", self.isbn)
            form.addRow("Başlık *", self.title)
            form.addRow("Yazar(lar)", self.authors)
            form.addRow("Yayınevi", self.publisher)
            form.addRow("Basım tarihi", self.publication_date)
            form.addRow("Sayfa", self.pages)
            form.addRow("Dil", self.language)
            form.addRow("Kategori", self.category)
            form.addRow("Adet", self.copies)
            form.addRow("Dolap", self.location)
            form.addRow("Ön kapak", self.front_button)
            form.addRow("Arka kapak", self.back_button)
            buttons = QDialogButtonBox(
                QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel
            )
            buttons.button(QDialogButtonBox.StandardButton.Ok).setText("Kaydet")
            buttons.button(QDialogButtonBox.StandardButton.Cancel).setText("Vazgeç")
            buttons.accepted.connect(self._validate_and_accept)
            buttons.rejected.connect(self.reject)
            form.addRow("", buttons)

        def _choose_cover(self, role: str) -> None:
            path, _filter = QFileDialog.getOpenFileName(
                self,
                "Kapak görselini seçin",
                "",
                "Görseller (*.jpg *.jpeg *.png *.heic *.heif *.webp *.tif *.tiff *.bmp)",
            )
            if not path:
                return
            name = Path(path).name
            if role == "front":
                self.front_path = path
                self.front_button.setText(name)
            else:
                self.back_path = path
                self.back_button.setText(name)

        def _validate_and_accept(self) -> None:
            from kitapkatalog.voice_protocol import isbn_candidates_from_span

            if not self.title.text().strip():
                QMessageBox.warning(self, "Yeni Kitap", "Başlık boş olamaz.")
                return
            isbn = self.isbn.text().strip()
            if isbn and len(isbn_candidates_from_span(isbn)) != 1:
                QMessageBox.warning(
                    self, "Yeni Kitap", "ISBN geçersiz görünüyor; düzeltin veya silin."
                )
                return
            self.accept()

        def values(self) -> dict[str, Any]:
            return {
                "isbn": self.isbn.text().strip(),
                "title": self.title.text().strip(),
                "authors": [
                    part.strip() for part in self.authors.text().split(";") if part.strip()
                ],
                "publisher": self.publisher.text().strip() or None,
                "publication_date": self.publication_date.text().strip() or None,
                "page_count": self.pages.value() or None,
                "language": self.language.currentText().strip() or None,
                "category": self.category.currentText().strip() or None,
                "copies": self.copies.value(),
                "location": self.location.currentText().strip() or None,
                "front": self.front_path,
                "back": self.back_path,
            }

    class KitapKatalogMainWindow(QMainWindow):
        def __init__(
            self,
            database_path: str | Path | None = None,
            *,
            voice_session_factory: Callable[[], Any] | None = None,
            voice_capture_factory: Callable[[], Any] | None = None,
        ) -> None:
            super().__init__()
            paths = _paths_for_database(database_path)
            # Use the same fail-closed lifecycle as web/CLI. In particular, an
            # older live catalogue is never auto-migrated before a verified
            # portable backup exists and an exclusive application lock is held.
            from kitapkatalog.application import open_application

            self._application_context = open_application(paths, enforce_offline=False)
            self.database = self._application_context.database
            self.catalog = self._application_context.catalog
            self.paths = paths
            self.pool = QThreadPool.globalInstance()
            self._workers: set[Worker] = set()
            self._selected_job_id: str | None = None
            self._selected_pair_review_id: int | None = None
            self._selected_review_id: int | None = None
            self._selected_library_id: int | None = None
            self._library_offset = 0
            self._library_total = 0
            self._thumb_worker_running = False
            self._library_cover_paths: dict[str, str | None] = {}
            self._library_loaded_isbn = ""
            self._library_loaded_authors: list[str] = []
            self._library_loaded_location = ""
            self._empty_hints: dict[int, Any] = {}
            # Baseline for the unsaved-changes guard; None until a record loads.
            self._library_loaded_state: tuple[Any, ...] | None = None
            self._review_loaded_location = ""
            self._voice_session_factory = voice_session_factory
            self._voice_capture_factory = voice_capture_factory
            self._voice_session: Any | None = None
            self._voice_capture: Any | None = None
            self._voice_pending: Any | None = None
            self._voice_batch_scheduler: Any | None = None
            self._voice_batch_running = False
            self.setWindowTitle("KitapKatalog — 5 OCR Çevrimdışı Katalog")
            self.settings = QSettings("MehmetDerin", "KitapKatalog")
            self.setStatusBar(QStatusBar(self))
            self.tabs = QTabWidget()
            self.setCentralWidget(self.tabs)
            self._build_library_tab()
            self._build_import_tab()
            self._build_voice_tab()
            self._build_pair_review_tab()
            self._build_review_tab()
            self._build_export_tab()
            self._build_engine_tab()
            self._build_stats_tab()
            self._build_menus()
            # ``currentChanged`` arrives after QTabWidget has already selected
            # the destination. Keep the last accepted index so a cancelled
            # unsaved-edits prompt can restore the source tab without losing
            # focus or recursively prompting.
            self._accepted_tab_index = self.tabs.currentIndex()
            self._restoring_tab_index = False
            self.tabs.currentChanged.connect(self._tab_changed)
            # Dropping the folder of photographs onto the window is the gesture
            # this application is for; until now only the audio box accepted one.
            self.setAcceptDrops(True)
            self._restore_window_state()
            self.refresh_all()
            self.refresh_timer = QTimer(self)
            self.refresh_timer.setInterval(2000)
            self.refresh_timer.timeout.connect(self.refresh_runtime)
            self.refresh_timer.start()

        # --------------------------------------------------------------
        # Menus, shortcuts and persisted window state

        def _build_menus(self) -> None:
            """Give the window a menu bar and the usual global shortcuts.

            Reviewing thousands of books is keyboard work.  Until now the only
            shortcuts lived on the voice tab, and macOS had no File/Edit menu at
            all, so even Cmd+W and Cmd+Q were missing.
            """

            menubar = self.menuBar()
            file_menu = menubar.addMenu("&Dosya")
            self._add_action(
                file_menu,
                "Klasör İçe Aktar…",
                QKeySequence.StandardKey.Open,
                self.choose_import_folder,
            )
            self._add_action(
                file_menu,
                "Dışa Aktar…",
                QKeySequence("Ctrl+E"),
                self.choose_export_path,
            )
            file_menu.addSeparator()
            self._add_action(
                file_menu,
                "Yenile",
                QKeySequence.StandardKey.Refresh,
                self.refresh_all,
            )
            file_menu.addSeparator()
            self._add_action(
                file_menu,
                "Pencereyi Kapat",
                QKeySequence.StandardKey.Close,
                self.close,
            )
            self._add_action(
                file_menu,
                "Çıkış",
                QKeySequence.StandardKey.Quit,
                self.close,
            )

            edit_menu = menubar.addMenu("&Düzen")
            self._add_action(
                edit_menu,
                "Aramaya Git",
                QKeySequence.StandardKey.Find,
                self.focus_search,
            )
            self._add_action(
                edit_menu,
                "Kaydet",
                QKeySequence.StandardKey.Save,
                self.save_current_tab,
            )
            self._add_action(
                edit_menu,
                "Kaydet ve Sıradakine Geç",
                QKeySequence("Ctrl+Return"),
                self.save_review_and_advance,
            )

            view_menu = menubar.addMenu("&Görünüm")
            for index in range(self.tabs.count()):
                self._add_action(
                    view_menu,
                    self.tabs.tabText(index),
                    QKeySequence(f"Ctrl+{index + 1}"),
                    lambda _checked=False, target=index: self.tabs.setCurrentIndex(target),
                )

        def _add_action(
            self,
            menu: Any,
            title: str,
            shortcut: Any,
            slot: Callable[..., Any],
        ) -> Any:
            action = QAction(title, self)
            action.setShortcut(shortcut)
            # Menu actions stay live no matter which widget holds focus.
            action.setShortcutContext(Qt.ShortcutContext.WindowShortcut)
            action.triggered.connect(slot)
            menu.addAction(action)
            self.addAction(action)
            return action

        def focus_search(self) -> None:
            self.tabs.setCurrentIndex(0)
            self.search_edit.setFocus()
            self.search_edit.selectAll()

        def save_current_tab(self) -> None:
            """Route the save shortcut to whatever the visible tab saves."""

            savers: dict[int, Callable[[], None]] = {
                0: self.save_library_edit,
                4: self.save_review,
            }
            saver = savers.get(self.tabs.currentIndex())
            if saver is None:
                self.statusBar().showMessage("Bu sekmede kaydedilecek bir düzenleme yok", 4000)
                return
            saver()

        def _restore_window_state(self) -> None:
            """Reopen where the user left off, including table column widths."""

            geometry = self.settings.value("window/geometry")
            if geometry is not None:
                self.restoreGeometry(geometry)
            else:
                self.resize(1320, 820)
            for name, table in self._persisted_tables().items():
                state = self.settings.value(f"columns/{name}")
                if state is not None:
                    table.horizontalHeader().restoreState(state)

        def _save_window_state(self) -> None:
            self.settings.setValue("window/geometry", self.saveGeometry())
            for name, table in self._persisted_tables().items():
                self.settings.setValue(f"columns/{name}", table.horizontalHeader().saveState())

        def _persisted_tables(self) -> dict[str, Any]:
            return {
                "library": self.library_table,
                "review": self.review_table,
                "jobs": self.jobs_table,
            }

        # --------------------------------------------------------------
        # Shared helpers

        def _background(
            self,
            function: Callable[[], Any],
            success: Callable[[Any], None],
            *,
            message: str,
        ) -> Worker:
            worker = Worker(function)
            self._workers.add(worker)
            worker.signals.succeeded.connect(success)
            worker.signals.failed.connect(self._show_error)
            worker.signals.finished.connect(lambda: self._workers.discard(worker))
            self.statusBar().showMessage(message)
            self.pool.start(worker)
            return worker

        def _show_error(self, message: str) -> None:
            self.statusBar().showMessage("İşlem başarısız", 5000)
            QMessageBox.critical(self, "KitapKatalog", message)

        #: Folders and photographs the window accepts by drag and drop.
        DROPPABLE_SUFFIXES = (".jpg", ".jpeg", ".png", ".heic", ".heif", ".tif", ".tiff", ".pdf")

        def _dropped_folders(self, event: Any) -> list[Path]:
            mime = event.mimeData()
            if not mime.hasUrls():
                return []
            folders: list[Path] = []
            for url in mime.urls():
                if not url.isLocalFile():
                    continue
                path = Path(url.toLocalFile())
                if path.is_dir():
                    folders.append(path)
                elif path.suffix.casefold() in self.DROPPABLE_SUFFIXES:
                    # A dropped photograph stands for the folder holding it.
                    folders.append(path.parent)
            return list(dict.fromkeys(folders))

        def dragEnterEvent(self, event: Any) -> None:
            if self._dropped_folders(event):
                event.acceptProposedAction()

        def dropEvent(self, event: Any) -> None:
            folders = self._dropped_folders(event)
            if not folders:
                return
            event.acceptProposedAction()
            if len(folders) > 1:
                self.statusBar().showMessage(
                    "Aynı anda tek klasör bırakın; ilki kullanılıyor.", 6000
                )
            self.tabs.setCurrentIndex(1)
            self.import_folder(folders[0])

        @staticmethod
        def _describe(*controls: tuple[Any, str, str]) -> None:
            """Give each control a hover explanation and a screen-reader name.

            The window had neither: every button and filter was a bare Turkish
            label with no way to find out what it actually does, and nothing at
            all for assistive technology.
            """

            for widget, name, explanation in controls:
                widget.setToolTip(explanation)
                widget.setAccessibleName(name)
                widget.setAccessibleDescription(explanation)

        @staticmethod
        def _hint_colour(widget: Any) -> str:
            """A muted foreground taken from the running theme.

            Hard-coded hex works in one appearance and fails in the other; on
            macOS the same window is routinely opened in both.  ``Shadow`` is a
            mid tone in both, unlike ``PlaceholderText``, which some styles
            leave equal to the full-strength text colour.
            """

            return widget.palette().color(QPalette.ColorRole.Shadow).name()

        @staticmethod
        def _border_colour(widget: Any) -> str:
            """The theme's own separator tone, so borders never go pure black."""

            return widget.palette().color(QPalette.ColorRole.Mid).name()

        def _set_empty_hint(self, table: QTableWidget, message: str) -> None:
            """Say what to do next instead of showing an empty grid.

            A first launch is nothing but empty tables, and a blank grid gives a
            new user no way to tell "nothing here yet" from "something failed".

            The hint is a label over the viewport rather than a placeholder row:
            a row would make ``rowCount()`` report one record where there are
            none, and paging, selection and "save and move on" all read it.
            """

            label: QLabel | None = self._empty_hints.get(id(table))
            if label is None:
                label = QLabel(table.viewport())
                label.setWordWrap(True)
                label.setAlignment(Qt.AlignmentFlag.AlignCenter)
                label.setStyleSheet(f"color: {self._hint_colour(table)}; padding: 24px;")
                self._empty_hints[id(table)] = label
            label.setText(message)
            self._update_empty_hint(table)

        def _enable_row_menu(self, table: QTableWidget) -> None:
            """Offer the obvious per-row actions on right click.

            Copying a title or an ISBN out of the catalogue previously meant
            retyping it: the tables are read-only and had no context menu.
            """

            table.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
            table.customContextMenuRequested.connect(
                lambda point, target=table: self._show_row_menu(target, point)
            )

        def _show_row_menu(self, table: QTableWidget, point: Any) -> None:
            item = table.itemAt(point)
            if item is None:
                return
            row = item.row()
            menu = QMenu(table)
            cell = menu.addAction("Hücreyi Kopyala")
            menu.addAction("Satırı Kopyala")
            chosen = menu.exec(table.viewport().mapToGlobal(point))
            if chosen is None:
                return
            if chosen is cell:
                text = item.text()
            else:
                text = "\t".join(
                    (table.item(row, column).text() if table.item(row, column) else "")
                    for column in range(table.columnCount())
                )
            QApplication.clipboard().setText(text)
            self.statusBar().showMessage("Panoya kopyalandı", 3000)

        @staticmethod
        def _suggest(widget: Any, values: Sequence[str]) -> None:
            """Complete a free-text field from what the catalogue already holds.

            These fields are editable on purpose, but retyping "Yapı Kredi
            Yayınları" for the hundredth book is how inconsistent spellings get
            into a catalogue.
            """

            completer = QCompleter(list(dict.fromkeys(values)))
            completer.setCaseSensitivity(Qt.CaseSensitivity.CaseInsensitive)
            completer.setFilterMode(Qt.MatchFlag.MatchContains)
            completer.setCompletionMode(QCompleter.CompletionMode.PopupCompletion)
            widget.setCompleter(completer)

        def _update_empty_hint(self, table: QTableWidget) -> None:
            label = self._empty_hints.get(id(table))
            if label is None:
                return
            if table.rowCount():
                label.hide()
                return
            label.setGeometry(table.viewport().rect())
            label.show()

        def _fill_table(
            self,
            table: QTableWidget,
            rows: list[list[Any]],
            *,
            first_column_data: list[Any] | None = None,
        ) -> None:
            table.setSortingEnabled(False)
            table.clearSpans()
            table.setRowCount(len(rows))
            for row_index, values in enumerate(rows):
                for column_index, value in enumerate(values):
                    item = QTableWidgetItem()
                    if value is None:
                        item.setText("")
                    elif isinstance(value, (int, float)) and not isinstance(value, bool):
                        # Sayısal DisplayRole: No/Sayfa/Adet sütunları doğru sıralanır.
                        item.setData(Qt.ItemDataRole.DisplayRole, value)
                    else:
                        item.setText(str(value))
                    if (
                        first_column_data is not None
                        and column_index == 0
                        and row_index < len(first_column_data)
                    ):
                        item.setData(Qt.ItemDataRole.UserRole, first_column_data[row_index])
                    table.setItem(row_index, column_index, item)
            table.setSortingEnabled(True)
            table.resizeRowsToContents()
            self._update_empty_hint(table)

        @staticmethod
        def _identifier(book: BookRecord) -> str:
            for scheme in ("ISBN13", "ISBN10"):
                match = next(
                    (
                        item.value
                        for item in book.identifiers
                        if item.scheme.replace("-", "").replace("_", "").replace(" ", "").upper()
                        == scheme
                    ),
                    None,
                )
                if match:
                    return match
            return ""

        @staticmethod
        def _authors(book: BookRecord) -> str:
            authors = [item.name for item in book.contributors if str(item.role) == "author"]
            if authors:
                return ", ".join(authors)
            role_labels = {
                "editor": "editör",
                "compiler": "hazırlayan",
                "translator": "çevirmen",
                "illustrator": "çizer",
                "foreword": "önsöz",
                "other": "katkı",
            }
            return ", ".join(
                f"{item.name} ({role_labels.get(str(item.role), str(item.role))})"
                for item in book.contributors
            )

        @staticmethod
        def _status(value: Any) -> str:
            raw = getattr(value, "value", value)
            return _STATUS_TR.get(str(raw), str(raw))

        @staticmethod
        def _book_locations(book: BookRecord) -> str:
            values = sorted({copy.location for copy in book.copies if copy.location})
            return ", ".join(values)

        @staticmethod
        def _format_bytes(value: int) -> str:
            size = float(value)
            for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
                if size < 1024 or unit == "TiB":
                    return f"{size:,.1f} {unit}"
                size /= 1024
            return f"{size:,.1f} TiB"

        @staticmethod
        def _format_duration(seconds: float) -> str:
            total = max(0, round(seconds))
            days, remainder = divmod(total, 86_400)
            hours, remainder = divmod(remainder, 3_600)
            minutes, _seconds = divmod(remainder, 60)
            parts: list[str] = []
            if days:
                parts.append(f"{days} gün")
            if hours:
                parts.append(f"{hours} sa")
            if minutes or not parts:
                parts.append(f"{minutes} dk")
            return " ".join(parts[:2])

        def _managed_cover_paths(self) -> tuple[Path, ...]:
            from kitapkatalog.restore import collect_cover_paths

            return tuple(collect_cover_paths(self.database.path, self.paths.assets))

        # --------------------------------------------------------------
        # Library

        def _build_library_tab(self) -> None:
            page = QWidget()
            layout = QVBoxLayout(page)
            controls = QHBoxLayout()
            self.search_edit = QLineEdit()
            self.search_edit.setPlaceholderText(
                "Başlık, yazar, yayınevi, ISBN veya kapak metninde ara…"
            )
            self.search_edit.setClearButtonEnabled(True)
            self.library_status_filter = QComboBox()
            self.library_status_filter.addItem("Tüm durumlar", "")
            for value in ("review", "completed"):
                self.library_status_filter.addItem(_STATUS_TR[value], value)
            self.library_language_filter = QComboBox()
            self.library_language_filter.addItem("Tüm diller", "")
            self.library_category_filter = QComboBox()
            self.library_category_filter.addItem("Tüm kategoriler", "")
            self.library_missing_filter = QComboBox()
            for label, value in (
                ("Eksik alan: —", ""),
                ("ISBN'siz", "isbn"),
                ("Kapaksız", "cover"),
                ("Kategorisiz", "category"),
                ("Dilsiz", "language"),
                ("Yayınevisiz", "publisher"),
                ("Basım tarihisiz", "publication_date"),
                ("Sayfa sayısız", "page_count"),
            ):
                self.library_missing_filter.addItem(label, value)
            refresh = QPushButton("Yenile")
            refresh.clicked.connect(self.refresh_library)
            self._describe(
                (
                    self.search_edit,
                    "Arama (Ctrl+F)",
                    "Başlık, alt başlık, katkıda bulunanlar, yayınevi, ISBN ve ham "
                    "kapak metninde arar. Türkçe harfler aynen eşleşir.",
                ),
                (
                    self.library_status_filter,
                    "Durum süzgeci",
                    "İncelemeyi bekleyen kayıtlarla tamamlananları ayırır.",
                ),
                (self.library_language_filter, "Dil süzgeci", "Katalogdaki dillere göre süzer."),
                (
                    self.library_category_filter,
                    "Kategori süzgeci",
                    "Katalogda kullanılmış kategorilere göre süzer.",
                ),
                (
                    self.library_missing_filter,
                    "Eksik alan süzgeci",
                    "Seçilen alanı boş olan kayıtları listeler; tamamlanacak "
                    "kitapları bulmanın en hızlı yolu.",
                ),
                (refresh, "Yenile (F5)", "Tabloyu veritabanından yeniden okur."),
            )
            controls.addWidget(self.search_edit, 1)
            controls.addWidget(self.library_status_filter)
            controls.addWidget(self.library_language_filter)
            controls.addWidget(self.library_category_filter)
            controls.addWidget(self.library_missing_filter)
            controls.addWidget(refresh)
            layout.addLayout(controls)

            toolbar = QHBoxLayout()
            new_book = QPushButton("Yeni Kitap")
            new_book.clicked.connect(self.create_book_manually)
            approve_selected = QPushButton("Seçilileri Onayla")
            approve_selected.clicked.connect(self.approve_selected_books)
            assign_category = QPushButton("Kategori Ata…")
            assign_category.clicked.connect(self.assign_category_to_selected)
            assign_location = QPushButton("Dolap Ata…")
            assign_location.clicked.connect(self.assign_location_to_selected)
            assign_copies = QPushButton("Adet Ata…")
            assign_copies.clicked.connect(self.assign_copy_count_to_selected)
            delete_selected = QPushButton("Seçilileri Sil")
            delete_selected.clicked.connect(self.delete_selected_books)
            self._describe(
                (
                    new_book,
                    "Yeni kitap",
                    "Fotoğrafsız, elle kitap kaydı ekler. Aynı ISBN varsa adet "
                    "artırmayı teklif eder.",
                ),
                (
                    approve_selected,
                    "Seçilileri onayla",
                    "Seçili kayıtları incelenmiş sayar; alanları kullanıcı değeri "
                    "olarak kilitlenir ve sonraki OCR bunları değiştiremez.",
                ),
                (
                    assign_category,
                    "Kategori ata",
                    "Seçili kayıtların hepsine aynı kategoriyi yazar.",
                ),
                (
                    assign_location,
                    "Dolap ata",
                    "Seçili kayıtların bütün nüshalarına aynı raf konumunu yazar.",
                ),
                (
                    assign_copies,
                    "Adet ata",
                    "Seçili kayıtların her birinin nüsha adedini ayarlar.",
                ),
                (
                    delete_selected,
                    "Seçilileri sil",
                    "Kayıtları kapak kanıtı ve OCR gözlemleriyle birlikte siler. "
                    "Geri alınamaz; önce .kitaparsiv yedeği almayı düşünün.",
                ),
            )
            for button in (
                new_book,
                approve_selected,
                assign_category,
                assign_location,
                assign_copies,
                delete_selected,
            ):
                toolbar.addWidget(button)
            toolbar.addStretch(1)
            self.library_prev_button = QPushButton("◀ Önceki")
            self.library_prev_button.clicked.connect(self._library_prev_page)
            self.library_page_label = QLabel("")
            self.library_next_button = QPushButton("Sonraki ▶")
            self.library_next_button.clicked.connect(self._library_next_page)
            for widget in (
                self.library_prev_button,
                self.library_page_label,
                self.library_next_button,
            ):
                toolbar.addWidget(widget)
                widget.setVisible(False)
            layout.addLayout(toolbar)

            splitter = QSplitter(Qt.Orientation.Horizontal)
            table_holder = QWidget()
            table_layout = QVBoxLayout(table_holder)
            table_layout.setContentsMargins(0, 0, 0, 0)
            self.library_table = QTableWidget(0, 14)
            self.library_table.setHorizontalHeaderLabels(
                (
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
                )
            )
            self.library_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.library_table.setSelectionMode(QAbstractItemView.SelectionMode.ExtendedSelection)
            self.library_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.library_table.setIconSize(QSize(48, 64))
            self.library_table.setColumnWidth(0, 60)
            self.library_table.setColumnWidth(1, 60)
            self.library_table.setColumnWidth(2, 46)
            self.library_table.setColumnWidth(3, 120)
            self.library_table.horizontalHeader().setSectionResizeMode(
                4, QHeaderView.ResizeMode.Stretch
            )
            self.library_table.itemSelectionChanged.connect(self._library_selected)
            table_layout.addWidget(self.library_table)
            self.library_count = QLabel()
            table_layout.addWidget(self.library_count)
            splitter.addWidget(table_holder)
            splitter.addWidget(self._build_library_detail())
            splitter.setStretchFactor(0, 3)
            splitter.setStretchFactor(1, 2)
            layout.addWidget(splitter)
            self.search_delay = QTimer(self)
            self.search_delay.setSingleShot(True)
            self.search_delay.setInterval(250)
            self.search_delay.timeout.connect(self.refresh_library)
            self.search_edit.textChanged.connect(lambda _value: self._library_filter_changed())
            for combo in (
                self.library_status_filter,
                self.library_language_filter,
                self.library_category_filter,
                self.library_missing_filter,
            ):
                combo.currentIndexChanged.connect(lambda _index: self._library_filter_changed())
            self._enable_row_menu(self.library_table)
            self._set_empty_hint(
                self.library_table,
                "Katalog boş. Başlamak için “İçe Aktarma ve Kuyruk” sekmesinden "
                "kitap fotoğrafı ekleyin ya da “Sesli Kayıt” ile sesle girin.",
            )
            self.tabs.addTab(page, "Kütüphane")

        def _library_filter_changed(self) -> None:
            self._library_offset = 0
            self.search_delay.start()

        def _build_library_detail(self) -> QWidget:
            panel = QWidget()
            layout = QVBoxLayout(panel)
            previews = QGridLayout()
            self.library_front_preview = ClickableLabel("Ön kapak")
            self.library_front_inside_preview = ClickableLabel("Ön iç kapak")
            self.library_back_inside_preview = ClickableLabel("Arka iç kapak")
            self.library_back_preview = ClickableLabel("Arka kapak")
            library_previews = (
                ("front", self.library_front_preview),
                ("front_inside", self.library_front_inside_preview),
                ("back_inside", self.library_back_inside_preview),
                ("back", self.library_back_preview),
            )
            for index, (role, preview) in enumerate(library_previews):
                preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
                preview.setMinimumSize(150, 180)
                preview.setStyleSheet(f"border: 1px solid {self._border_colour(preview)};")
                preview.clicked.connect(lambda role=role: self._zoom_library_cover(role))
                previews.addWidget(preview, index // 2, index % 2)
            layout.addLayout(previews)
            cover_buttons = QHBoxLayout()
            self.library_front_cover_button = QPushButton("Ön Kapak Seç…")
            self.library_front_cover_button.clicked.connect(
                lambda: self.assign_library_cover("front")
            )
            self.library_back_cover_button = QPushButton("Arka Kapak Seç…")
            self.library_back_cover_button.clicked.connect(
                lambda: self.assign_library_cover("back")
            )
            cover_buttons.addWidget(self.library_front_cover_button)
            cover_buttons.addWidget(self.library_back_cover_button)
            cover_buttons.addStretch(1)
            layout.addLayout(cover_buttons)

            detail_tabs = QTabWidget()
            basic = QWidget()
            form = QFormLayout(basic)
            self.library_isbn = QLineEdit()
            self.library_isbn.textChanged.connect(self._library_isbn_changed)
            self.library_title = QLineEdit()
            self.library_subtitle = QLineEdit()
            self.library_authors = QLineEdit()
            self.library_authors.setPlaceholderText("Birden fazlaysa ; ile ayırın")
            self.library_publisher = QLineEdit()
            self.library_category = QComboBox()
            self.library_category.setEditable(True)
            self.library_year = QLineEdit()
            self.library_pages = QSpinBox()
            self.library_pages.setRange(0, 99_999)
            self.library_pages.setSpecialValueText("—")
            self.library_language = QLineEdit()
            self.library_blurb = QPlainTextEdit()
            form.addRow("ISBN", self.library_isbn)
            form.addRow("Başlık", self.library_title)
            form.addRow("Alt başlık", self.library_subtitle)
            form.addRow("Yazar(lar) (;)", self.library_authors)
            form.addRow("Yayınevi", self.library_publisher)
            form.addRow("Kategori", self.library_category)
            form.addRow("Basım tarihi", self.library_year)
            form.addRow("Sayfa", self.library_pages)
            form.addRow("Dil", self.library_language)
            self.library_location = QLineEdit()
            self.library_location.setPlaceholderText("Örn. A Dolabı / Raf 3")
            form.addRow("Dolap", self.library_location)
            form.addRow("Tanıtım", self.library_blurb)
            detail_tabs.addTab(basic, "Temel")

            advanced = QWidget()
            advanced_form = QFormLayout(advanced)
            self.library_original_title = QLineEdit()
            self.library_series = QLineEdit()
            self.library_volume = QLineEdit()
            self.library_place = QLineEdit()
            self.library_edition_statement = QLineEdit()
            self.library_printing_number = QLineEdit()
            self.library_printer = QLineEdit()
            self.library_binding = QLineEdit()
            self.library_dimensions = QLineEdit()
            self.library_price = QLineEdit()
            self.library_currency = QLineEdit()
            self.library_awards = QPlainTextEdit()
            self.library_quotations = QPlainTextEdit()
            advanced_form.addRow("Orijinal başlık", self.library_original_title)
            advanced_form.addRow("Seri", self.library_series)
            advanced_form.addRow("Cilt", self.library_volume)
            advanced_form.addRow("Basım yeri", self.library_place)
            advanced_form.addRow("Baskı ifadesi", self.library_edition_statement)
            advanced_form.addRow("Baskı no", self.library_printing_number)
            advanced_form.addRow("Matbaa", self.library_printer)
            advanced_form.addRow("Cilt tipi", self.library_binding)
            advanced_form.addRow("Boyutlar", self.library_dimensions)
            advanced_form.addRow("Fiyat", self.library_price)
            advanced_form.addRow("Para birimi", self.library_currency)
            advanced_form.addRow("Ödüller", self.library_awards)
            advanced_form.addRow("Alıntılar", self.library_quotations)
            detail_tabs.addTab(advanced, "Ayrıntı")
            layout.addWidget(detail_tabs, 1)
            copies_row = QHBoxLayout()
            self.library_copy_label = QLabel("Adet: —")
            self.library_copy_add = QPushButton("Adet +1")
            self.library_copy_add.clicked.connect(self.add_library_copy)
            self.library_copy_remove = QPushButton("Adet −1")
            self.library_copy_remove.clicked.connect(self.remove_library_copy)
            self.library_copy_spin = QSpinBox()
            self.library_copy_spin.setRange(1, 999)
            self.library_copy_apply = QPushButton("Adet Uygula")
            self.library_copy_apply.clicked.connect(self.apply_library_copy_count)
            copies_row.addWidget(self.library_copy_label)
            copies_row.addWidget(self.library_copy_add)
            copies_row.addWidget(self.library_copy_remove)
            copies_row.addWidget(self.library_copy_spin)
            copies_row.addWidget(self.library_copy_apply)
            copies_row.addStretch(1)
            layout.addLayout(copies_row)
            actions = QHBoxLayout()
            self.library_save_button = QPushButton("Değişiklikleri Kaydet")
            self.library_save_button.clicked.connect(self.save_library_edit)
            self.library_delete_button = QPushButton("Kaydı Sil")
            self.library_delete_button.clicked.connect(self.delete_library_book)
            actions.addWidget(self.library_save_button)
            actions.addWidget(self.library_delete_button)
            layout.addLayout(actions)
            layout.addStretch(1)
            self._library_clear_detail()
            return panel

        def _library_filters(self) -> SearchFilters:
            status = str(self.library_status_filter.currentData() or "")
            language = str(self.library_language_filter.currentData() or "")
            category = str(self.library_category_filter.currentData() or "")
            missing = str(self.library_missing_filter.currentData() or "")
            return SearchFilters(
                review_status=status or None,
                language=language or None,
                category=category or None,
                missing=missing or None,
            )

        def _library_refresh_filter_combos(self) -> None:
            for combo, column, empty_label in (
                (self.library_language_filter, "language", "Tüm diller"),
                (self.library_category_filter, "category", "Tüm kategoriler"),
            ):
                current = str(combo.currentData() or "")
                combo.blockSignals(True)
                combo.clear()
                combo.addItem(empty_label, "")
                for value in self.catalog.list_distinct_values(column):
                    combo.addItem(value, value)
                index = combo.findData(current)
                combo.setCurrentIndex(index if index >= 0 else 0)
                combo.blockSignals(False)
            self._refresh_suggestions()

        def _refresh_suggestions(self) -> None:
            """Feed the free-text fields with values already in the catalogue."""

            publishers = self.catalog.list_distinct_values("publisher")
            languages = self.catalog.list_distinct_values("language")
            locations = self.catalog.list_distinct_values("location")
            categories = self.catalog.list_distinct_values("category")
            for widget, values in (
                (self.library_publisher, publishers),
                (self.library_language, languages),
                (self.library_location, locations),
                (self.review_publisher, publishers),
                (self.review_language, languages),
                (self.review_location, locations),
            ):
                self._suggest(widget, values)
            for combo, values in (
                (self.library_category, categories),
                (self.review_category, categories),
            ):
                self._suggest(combo.lineEdit(), values)

        def refresh_library(self) -> None:
            page = self.catalog.search(
                self.search_edit.text(),
                filters=self._library_filters(),
                limit=1000,
                offset=self._library_offset,
            )
            if page.total and self._library_offset >= page.total:
                self._library_offset = 0
                page = self.catalog.search(
                    self.search_edit.text(),
                    filters=self._library_filters(),
                    limit=1000,
                )
            self._library_total = page.total
            books = list(page.items)
            rows = [
                [
                    None,
                    None,
                    book.edition_id,
                    self._identifier(book),
                    book.title,
                    self._authors(book),
                    book.publisher,
                    book.publication_date,
                    book.page_count,
                    book.language,
                    book.category,
                    len(book.copies),
                    self._book_locations(book),
                    self._status(book.review_status),
                ]
                for book in books
            ]
            selected = self._selected_library_id
            self._fill_table(
                self.library_table,
                rows,
                first_column_data=[book.edition_id for book in books],
            )
            stats = self.catalog.stats()
            self.library_count.setText(
                f"{page.total:,} kayıttan {len(books):,} tanesi gösteriliyor • "
                f"{stats['works']:,} eser, {stats['editions']:,} baskı, "
                f"{stats['copies']:,} kopya, {stats['review']:,} incelemede"
            )
            self._library_update_pager()
            self._library_refresh_filter_combos()
            current_category = self.library_category.currentText()
            self.library_category.blockSignals(True)
            self.library_category.clear()
            self.library_category.addItem("")
            for value in self.catalog.list_distinct_values("category"):
                self.library_category.addItem(value)
            self.library_category.setCurrentText(current_category)
            self.library_category.blockSignals(False)
            self._library_apply_thumbnails(books)
            if selected is not None:
                row = self._library_find_row(selected)
                if row is not None:
                    self.library_table.selectRow(row)
                else:
                    self._library_clear_detail()
                    self.library_table.clearSelection()

        def _library_find_row(self, edition_id: int) -> int | None:
            for row in range(self.library_table.rowCount()):
                item = self.library_table.item(row, 0)
                if item and item.data(Qt.ItemDataRole.UserRole) == edition_id:
                    return row
            return None

        # Sayfalama

        def _library_update_pager(self) -> None:
            total = self._library_total
            offset = self._library_offset
            visible = total > 1000 or offset > 0
            for widget in (
                self.library_prev_button,
                self.library_page_label,
                self.library_next_button,
            ):
                widget.setVisible(visible)
            if not visible:
                return
            shown = self.library_table.rowCount()
            first = offset + 1 if shown else 0
            last = offset + shown
            self.library_page_label.setText(f"{first:,}–{last:,} / {total:,}")
            self.library_prev_button.setEnabled(offset > 0)
            self.library_next_button.setEnabled(offset + 1000 < total)

        def _library_prev_page(self) -> None:
            self._library_offset = max(0, self._library_offset - 1000)
            self.refresh_library()

        def _library_next_page(self) -> None:
            if self._library_offset + 1000 < self._library_total:
                self._library_offset += 1000
                self.refresh_library()

        # Kapak küçük resimleri

        def _thumb_cache_dir(self) -> Path:
            return self.paths.derivatives / "cover-thumbs"

        def _thumb_cache_paths(self, edition_id: int) -> tuple[Path, Path]:
            cache = self._thumb_cache_dir()
            return (cache / f"{edition_id}-front.png", cache / f"{edition_id}-back.png")

        @staticmethod
        def _thumb_fresh(source: Path, cache: Path) -> bool:
            try:
                return cache.is_file() and cache.stat().st_mtime >= source.stat().st_mtime
            except OSError:
                return False

        def _library_apply_thumbnails(self, books: list[BookRecord]) -> None:
            pending: list[tuple[int, str, str, str]] = []
            for row, book in enumerate(books):
                front_cache, back_cache = self._thumb_cache_paths(book.edition_id)
                for column, role, source, cache in (
                    (0, "front", book.front_path, front_cache),
                    (1, "back", book.back_path, back_cache),
                ):
                    if not source:
                        continue
                    source_path = Path(source)
                    if not source_path.is_file():
                        continue
                    if self._thumb_fresh(source_path, cache):
                        item = self.library_table.item(row, column)
                        if item is not None:
                            item.setIcon(QIcon(str(cache)))
                    else:
                        pending.append((book.edition_id, role, source, str(cache)))
            self.library_table.resizeRowsToContents()
            if pending and not self._thumb_worker_running:
                self._thumb_worker_running = True

                def work() -> list[tuple[int, str, str]]:
                    produced: list[tuple[int, str, str]] = []
                    for edition_id, role, source, cache in pending:
                        # QImage iş parçacığında güvenlidir; QPixmap DEĞİLDİR.
                        image = QImage(source)
                        if image.isNull():
                            continue
                        target = Path(cache)
                        target.parent.mkdir(parents=True, exist_ok=True)
                        scaled = image.scaledToHeight(
                            64, Qt.TransformationMode.SmoothTransformation
                        )
                        if scaled.save(str(target), "PNG"):
                            produced.append((edition_id, role, cache))
                    return produced

                worker = self._background(
                    work,
                    self._library_thumbs_ready,
                    message="Kapak küçük resimleri hazırlanıyor…",
                )
                worker.signals.failed.connect(
                    lambda _msg: setattr(self, "_thumb_worker_running", False)
                )

        def _library_thumbs_ready(self, produced: object) -> None:
            self._thumb_worker_running = False
            applied = False
            for edition_id, role, cache in produced:
                row = self._library_find_row(int(edition_id))
                if row is None:
                    continue
                column = 0 if role == "front" else 1
                item = self.library_table.item(row, column)
                if item is not None:
                    item.setIcon(QIcon(str(cache)))
                    applied = True
            if applied:
                self.library_table.resizeRowsToContents()
                self.statusBar().showMessage("Kapak küçük resimleri güncellendi", 2000)

        def _library_selected(self) -> None:
            items = self.library_table.selectedItems()
            if not items:
                return
            edition_id = int(
                self.library_table.item(items[0].row(), 0).data(Qt.ItemDataRole.UserRole)
            )
            if edition_id != self._selected_library_id and not (
                self._confirm_discarding_library_edits()
            ):
                # Put the selection back so the pending edits stay on screen.
                self._reselect_library_row(self._selected_library_id)
                return
            book = self.catalog.get_book(edition_id)
            if book is None:
                return
            self._selected_library_id = edition_id
            self._library_fill_detail(book)

        def _confirm_discarding_library_edits(self) -> bool:
            """Ask before losing detail-panel edits by moving to another row.

            The panel writes only when its save button is pressed, so switching
            rows used to drop whatever had been typed without a word.
            """

            if not self._library_detail_is_dirty():
                return True
            answer = QMessageBox.question(
                self,
                "Kaydedilmemiş değişiklik",
                "Bu kayıttaki düzenlemeler kaydedilmedi. Yine de başka kayda geçilsin mi?",
                QMessageBox.StandardButton.Discard | QMessageBox.StandardButton.Cancel,
                QMessageBox.StandardButton.Cancel,
            )
            return answer == QMessageBox.StandardButton.Discard

        def _library_form_state(self) -> tuple[Any, ...]:
            """Snapshot every editable value the detail panel can write.

            Listing the fields by hand here would drift from ``save_library_edit``
            the moment one is added, and a guard that misses a field is worse
            than none: it teaches the user their edits are safe.
            """

            return (
                self.library_isbn.text().strip(),
                self.library_location.text().strip(),
                tuple(self._library_author_values()),
                self.library_title.text(),
                self.library_subtitle.text(),
                self.library_publisher.text(),
                self.library_category.currentText(),
                self.library_year.text(),
                self.library_pages.value(),
                self.library_language.text(),
                self.library_blurb.toPlainText(),
                self.library_original_title.text(),
                self.library_series.text(),
                self.library_volume.text(),
                self.library_place.text(),
                self.library_edition_statement.text(),
                self.library_printing_number.text(),
                self.library_printer.text(),
                self.library_binding.text(),
                self.library_dimensions.text(),
                self.library_price.text(),
                self.library_currency.text(),
                self.library_awards.toPlainText(),
                self.library_quotations.toPlainText(),
            )

        def _library_detail_is_dirty(self) -> bool:
            if self._selected_library_id is None or self._library_loaded_state is None:
                return False
            return self._library_form_state() != self._library_loaded_state

        def _discard_library_detail_edits(self) -> None:
            """Restore the selected record after an explicit Discard choice."""

            if self._selected_library_id is None:
                return
            book = self.catalog.get_book(self._selected_library_id)
            if book is None:
                self._library_clear_detail()
                return
            self._library_fill_detail(book)

        def _reselect_library_row(self, edition_id: int | None) -> None:
            if edition_id is None:
                return
            self.library_table.blockSignals(True)
            try:
                for row in range(self.library_table.rowCount()):
                    item = self.library_table.item(row, 0)
                    if item is not None and item.data(Qt.ItemDataRole.UserRole) == edition_id:
                        self.library_table.selectRow(row)
                        break
            finally:
                self.library_table.blockSignals(False)

        def _library_isbn_changed(self, text: str) -> None:
            from kitapkatalog.voice_protocol import isbn_candidates_from_span

            if not text.strip():
                self.library_isbn.setStyleSheet("")
                return
            valid = len(isbn_candidates_from_span(text)) == 1
            self.library_isbn.setStyleSheet("" if valid else "border: 1px solid #c62828;")

        def _library_author_values(self) -> list[str]:
            return [part.strip() for part in self.library_authors.text().split(";") if part.strip()]

        def _library_fill_detail(self, book: BookRecord) -> None:
            self._library_loaded_isbn = self._identifier(book)
            self._library_loaded_authors = [
                item.name for item in book.contributors if str(item.role) == "author"
            ]
            self.library_isbn.setText(self._library_loaded_isbn)
            self.library_title.setText(book.title)
            self.library_subtitle.setText(book.subtitle or "")
            self.library_authors.setText("; ".join(self._library_loaded_authors))
            self.library_publisher.setText(book.publisher or "")
            self.library_category.setCurrentText(book.category or "")
            self.library_year.setText(book.publication_date or "")
            self.library_pages.setValue(book.page_count or 0)
            self.library_language.setText(book.language or "")
            self.library_blurb.setPlainText(book.blurb or "")
            self.library_original_title.setText(book.original_title or "")
            self.library_series.setText(book.series or "")
            self.library_volume.setText(book.volume or "")
            self.library_place.setText(book.publication_place or "")
            self.library_edition_statement.setText(book.edition_statement or "")
            self.library_printing_number.setText(book.printing_number or "")
            self.library_printer.setText(book.printer or "")
            self.library_binding.setText(book.binding or "")
            self.library_dimensions.setText(book.dimensions or "")
            self.library_price.setText(book.price_amount or "")
            self.library_currency.setText(book.currency or "")
            self.library_awards.setPlainText(book.awards or "")
            self.library_quotations.setPlainText(book.quotations or "")
            self._library_loaded_location = self._book_locations(book)
            self.library_location.setText(self._library_loaded_location)
            self.library_copy_label.setText(f"Adet: {len(book.copies)}")
            self.library_copy_spin.setValue(len(book.copies))
            self._library_cover_paths = {
                "front": book.front_path,
                "front_inside": book.front_inside_path,
                "back_inside": book.back_inside_path,
                "back": book.back_path,
            }
            self._set_preview(self.library_front_preview, book.front_path, "Ön kapak")
            self._set_preview(
                self.library_front_inside_preview,
                book.front_inside_path,
                "Ön iç kapak",
            )
            self._set_preview(
                self.library_back_inside_preview,
                book.back_inside_path,
                "Arka iç kapak",
            )
            self._set_preview(self.library_back_preview, book.back_path, "Arka kapak")
            for button in (
                self.library_save_button,
                self.library_delete_button,
                self.library_copy_add,
                self.library_copy_apply,
                self.library_copy_spin,
                self.library_front_cover_button,
                self.library_back_cover_button,
            ):
                button.setEnabled(True)
            self.library_copy_remove.setEnabled(len(book.copies) > 1)
            # Taken after every widget is populated: this is the baseline the
            # unsaved-changes guard compares against.
            self._library_loaded_state = self._library_form_state()

        def _library_clear_detail(self) -> None:
            self._selected_library_id = None
            self._library_loaded_isbn = ""
            self._library_loaded_authors = []
            self._library_loaded_location = ""
            self._library_loaded_state = None
            self._library_cover_paths = {}
            for edit in (
                self.library_isbn,
                self.library_title,
                self.library_subtitle,
                self.library_authors,
                self.library_publisher,
                self.library_year,
                self.library_language,
                self.library_original_title,
                self.library_series,
                self.library_volume,
                self.library_place,
                self.library_edition_statement,
                self.library_printing_number,
                self.library_printer,
                self.library_binding,
                self.library_dimensions,
                self.library_price,
                self.library_currency,
                self.library_location,
            ):
                edit.clear()
            self.library_category.setCurrentText("")
            self.library_pages.setValue(0)
            self.library_blurb.clear()
            self.library_awards.clear()
            self.library_quotations.clear()
            self.library_copy_label.setText("Adet: —")
            self.library_copy_spin.setValue(1)
            self._set_preview(self.library_front_preview, None, "Ön kapak")
            self._set_preview(self.library_front_inside_preview, None, "Ön iç kapak")
            self._set_preview(self.library_back_inside_preview, None, "Arka iç kapak")
            self._set_preview(self.library_back_preview, None, "Arka kapak")
            for button in (
                self.library_save_button,
                self.library_delete_button,
                self.library_copy_add,
                self.library_copy_remove,
                self.library_copy_apply,
                self.library_copy_spin,
                self.library_front_cover_button,
                self.library_back_cover_button,
            ):
                button.setEnabled(False)

        def _library_refresh_copies(self) -> None:
            if self._selected_library_id is None:
                return
            book = self.catalog.get_book(self._selected_library_id)
            if book is None:
                self._library_clear_detail()
                return
            self.library_copy_label.setText(f"Adet: {len(book.copies)}")
            self.library_copy_spin.setValue(len(book.copies))
            self.library_copy_remove.setEnabled(len(book.copies) > 1)

        def apply_library_copy_count(self) -> None:
            if self._selected_library_id is None:
                return
            location = self.library_location.text().strip() or None
            try:
                target = self.catalog.set_copy_count(
                    self._selected_library_id,
                    self.library_copy_spin.value(),
                    location=location,
                )
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._library_refresh_copies()
            self.refresh_library()
            self.statusBar().showMessage(f"Adet {target} olarak ayarlandı", 3000)

        def save_library_edit(self) -> None:
            if self._selected_library_id is None:
                return
            title = self.library_title.text().strip()
            if not title:
                self._show_error("Başlık boş olamaz")
                return
            isbn = self.library_isbn.text().strip()
            authors = [
                part.strip() for part in self.library_authors.text().split(";") if part.strip()
            ]
            try:
                self.catalog.update_book(
                    self._selected_library_id,
                    {
                        "title": title,
                        "subtitle": self.library_subtitle.text() or None,
                        "publisher": self.library_publisher.text() or None,
                        "category": self.library_category.currentText() or None,
                        "publication_date": self.library_year.text() or None,
                        "page_count": self.library_pages.value() or None,
                        "language": self.library_language.text() or None,
                        "blurb": self.library_blurb.toPlainText() or None,
                        "original_title": self.library_original_title.text() or None,
                        "series": self.library_series.text() or None,
                        "volume": self.library_volume.text() or None,
                        "publication_place": self.library_place.text() or None,
                        "edition_statement": (self.library_edition_statement.text() or None),
                        "printing_number": self.library_printing_number.text() or None,
                        "printer": self.library_printer.text() or None,
                        "binding": self.library_binding.text() or None,
                        "dimensions": self.library_dimensions.text() or None,
                        "price_amount": self.library_price.text() or None,
                        "currency": self.library_currency.text() or None,
                        "awards": self.library_awards.toPlainText() or None,
                        "quotations": self.library_quotations.toPlainText() or None,
                    },
                    user_edit=True,
                )
                if isbn != self._library_loaded_isbn:
                    self.catalog.set_isbn(self._selected_library_id, isbn or None)
                if authors != self._library_loaded_authors:
                    self.catalog.set_authors(self._selected_library_id, authors)
                location = self.library_location.text().strip()
                if location != self._library_loaded_location:
                    self.catalog.set_location(self._selected_library_id, location or None)
                    self._library_loaded_location = location
            except (
                KeyError,
                ValueError,
                RuntimeError,
                IdentifierConflictError,
            ) as exc:
                self._show_error(str(exc))
                return
            self._library_loaded_isbn = isbn
            self._library_loaded_authors = authors
            self.refresh_library()
            self.statusBar().showMessage("Değişiklikler kaydedildi", 3000)

        def add_library_copy(self) -> None:
            if self._selected_library_id is None:
                return
            try:
                self.catalog.add_copy(self._selected_library_id)
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._library_refresh_copies()
            self.refresh_library()

        def remove_library_copy(self) -> None:
            if self._selected_library_id is None:
                return
            book = self.catalog.get_book(self._selected_library_id)
            if book is None:
                return
            active_copies = [copy for copy in book.copies if copy.status == "active"]
            if len(active_copies) <= 1:
                return
            try:
                self.catalog.delete_copy(active_copies[-1].id)
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._library_refresh_copies()
            self.refresh_library()

        def delete_library_book(self) -> None:
            if self._selected_library_id is None:
                return
            book = self.catalog.get_book(self._selected_library_id)
            if book is None:
                return
            answer = QMessageBox.question(
                self,
                "Kaydı sil",
                f"#{book.edition_id} — {book.title} katalogdan tamamen silinecek. "
                "Devam edilsin mi?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer != QMessageBox.StandardButton.Yes:
                return
            try:
                self.catalog.delete_book(book.edition_id)
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._library_clear_detail()
            self.library_table.clearSelection()
            self.refresh_library()
            self.refresh_review()
            self.statusBar().showMessage("Kayıt silindi", 3000)

        # Kapak atama ve büyütme

        def _zoom_library_cover(self, role: str) -> None:
            path = self._library_cover_paths.get(role)
            if not path or not Path(path).is_file():
                return
            pixmap = QPixmap(path)
            if pixmap.isNull():
                return
            dialog = QDialog(self)
            dialog.setWindowTitle("Kapak önizleme")
            layout = QVBoxLayout(dialog)
            label = QLabel()
            screen = self.screen()
            if screen is not None:
                area = screen.availableGeometry()
                max_width = int(area.width() * 0.8)
                max_height = int(area.height() * 0.8)
            else:
                max_width, max_height = 1000, 800
            label.setPixmap(
                pixmap.scaled(
                    max_width,
                    max_height,
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
            )
            layout.addWidget(label)
            dialog.exec()

        def assign_library_cover(self, role: str) -> None:
            if self._selected_library_id is None:
                return
            path, _filter = QFileDialog.getOpenFileName(
                self,
                "Kapak görselini seçin",
                "",
                "Görseller (*.jpg *.jpeg *.png *.heic *.heif *.webp *.tif *.tiff *.bmp)",
            )
            if not path:
                return
            try:
                if role == "front":
                    self.catalog.set_cover_paths(self._selected_library_id, front_path=path)
                else:
                    self.catalog.set_cover_paths(self._selected_library_id, back_path=path)
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            for cache in self._thumb_cache_paths(self._selected_library_id):
                with suppress(OSError):
                    cache.unlink()
            book = self.catalog.get_book(self._selected_library_id)
            if book is not None:
                self._library_fill_detail(book)
            self.refresh_library()
            self.statusBar().showMessage("Kapak güncellendi", 3000)

        # Elle yeni kitap

        def create_book_manually(self) -> None:
            dialog = NewBookDialog(
                self,
                categories=self.catalog.list_distinct_values("category"),
                languages=self.catalog.list_distinct_values("language"),
                locations=self.catalog.list_distinct_values("location"),
            )
            if dialog.exec() != QDialog.DialogCode.Accepted:
                return
            self._create_book_from_values(dialog.values())

        def _create_book_from_values(self, values: dict[str, Any]) -> None:
            if values["isbn"]:
                try:
                    existing = self.catalog.get_by_identifier("ISBN", values["isbn"])
                except ValueError as exc:
                    self._show_error(str(exc))
                    return
                if existing is not None:
                    answer = QMessageBox.question(
                        self,
                        "ISBN zaten kayıtlı",
                        f"#{existing.edition_id} — {existing.title} bu ISBN ile "
                        f"katalogda var.\n{values['copies']} adet eklensin mi?",
                        QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                        QMessageBox.StandardButton.Yes,
                    )
                    if answer == QMessageBox.StandardButton.Yes:
                        merge_location = values.get("location")
                        for _ in range(values["copies"]):
                            self.catalog.add_copy(
                                existing.edition_id,
                                (CopyInput(location=merge_location) if merge_location else None),
                            )
                        self.refresh_library()
                        self.statusBar().showMessage(
                            f"#{existing.edition_id} kaydına {values['copies']} adet eklendi",
                            4000,
                        )
                    return
            try:
                book = self.catalog.save_book(
                    BookInput(
                        title=values["title"],
                        publisher=values["publisher"],
                        publication_date=values["publication_date"],
                        page_count=values["page_count"],
                        language=values["language"],
                        category=values["category"],
                        contributors=tuple(
                            ContributorInput(name, "author") for name in values["authors"]
                        ),
                        identifiers=(
                            (IdentifierInput("ISBN", values["isbn"], source="user"),)
                            if values["isbn"]
                            else ()
                        ),
                    ),
                    source_fingerprint=f"manual:{uuid4().hex}",
                )
                for _ in range(values["copies"] - 1):
                    self.catalog.add_copy(book.edition_id)
                if values.get("location"):
                    self.catalog.set_location(book.edition_id, values["location"])
                if values["front"] or values["back"]:
                    self.catalog.set_cover_paths(
                        book.edition_id,
                        front_path=values["front"],
                        back_path=values["back"],
                    )
                self.catalog.update_book(
                    book.edition_id, {"review_status": "completed"}, user_edit=True
                )
            except (
                KeyError,
                ValueError,
                RuntimeError,
                IdentifierConflictError,
            ) as exc:
                self._show_error(str(exc))
                return
            self._selected_library_id = book.edition_id
            self.refresh_library()
            self.statusBar().showMessage(f"Yeni kitap #{book.edition_id} eklendi", 4000)

        # Toplu işlemler

        def _selected_library_ids(self) -> list[int]:
            rows = self.library_table.selectionModel().selectedRows()
            ids: list[int] = []
            for index in rows:
                item = self.library_table.item(index.row(), 0)
                if item is not None:
                    ids.append(int(item.data(Qt.ItemDataRole.UserRole)))
            return ids

        def approve_selected_books(self) -> None:
            ids = self._selected_library_ids()
            if not ids:
                self.statusBar().showMessage("Önce tabloda satır seçin", 4000)
                return

            def work() -> int:
                for edition_id in ids:
                    self.catalog.update_book(
                        edition_id, {"review_status": "completed"}, user_edit=True
                    )
                return len(ids)

            def done(count: object) -> None:
                self.refresh_library()
                self.refresh_review()
                self.statusBar().showMessage(f"{count} kayıt onaylandı", 4000)

            self._background(work, done, message="Kayıtlar onaylanıyor…")

        def assign_category_to_selected(self) -> None:
            ids = self._selected_library_ids()
            if not ids:
                self.statusBar().showMessage("Önce tabloda satır seçin", 4000)
                return
            category, accepted = QInputDialog.getItem(
                self,
                "Kategori Ata",
                f"{len(ids)} kayda uygulanacak kategori:",
                self.catalog.list_distinct_values("category"),
                0,
                True,
            )
            if not accepted:
                return
            category = category.strip()
            if not self._confirm_bulk_change(
                len(ids),
                f"kategori “{category or 'boş'}”",
            ):
                return

            def work() -> int:
                for edition_id in ids:
                    self.catalog.update_book(
                        edition_id, {"category": category or None}, user_edit=True
                    )
                return len(ids)

            def done(count: object) -> None:
                self.refresh_library()
                self.statusBar().showMessage(f"{count} kayda kategori uygulandı", 4000)

            self._background(work, done, message="Kategori uygulanıyor…")

        def assign_location_to_selected(self) -> None:
            ids = self._selected_library_ids()
            if not ids:
                self.statusBar().showMessage("Önce tabloda satır seçin", 4000)
                return
            location, accepted = QInputDialog.getItem(
                self,
                "Dolap Ata",
                f"{len(ids)} kaydın tüm kopyalarına uygulanacak dolap/konum:",
                self.catalog.list_distinct_values("location"),
                0,
                True,
            )
            if not accepted:
                return
            location = location.strip()
            if not self._confirm_bulk_change(
                len(ids),
                f"dolap “{location or 'boş'}”",
            ):
                return

            def work() -> int:
                for edition_id in ids:
                    self.catalog.set_location(edition_id, location or None)
                return len(ids)

            def done(count: object) -> None:
                self.refresh_library()
                self.statusBar().showMessage(f"{count} kayda dolap bilgisi uygulandı", 4000)

            self._background(work, done, message="Dolap bilgisi uygulanıyor…")

        def assign_copy_count_to_selected(self) -> None:
            ids = self._selected_library_ids()
            if not ids:
                self.statusBar().showMessage("Önce tabloda satır seçin", 4000)
                return
            count, accepted = QInputDialog.getInt(
                self,
                "Adet Ata",
                f"{len(ids)} kaydın her biri için kopya adedi:",
                1,
                1,
                999,
            )
            if not accepted:
                return
            if not self._confirm_bulk_change(len(ids), f"{count} adet"):
                return

            def work() -> int:
                for edition_id in ids:
                    self.catalog.set_copy_count(edition_id, count)
                return len(ids)

            def done(total: object) -> None:
                self._library_refresh_copies()
                self.refresh_library()
                self.statusBar().showMessage(f"{total} kaydın adedi {count} olarak ayarlandı", 4000)

            self._background(work, done, message="Adetler ayarlanıyor…")

        #: Deleting more than this many records at once is worth a second look.
        BULK_CONFIRM_THRESHOLD = 5

        def _confirm_bulk_change(self, count: int, description: str) -> bool:
            """Confirm a bulk edit that touches more than a handful of records.

            These operations rewrite every selected record and cannot be undone,
            yet they used to run straight from the input dialog with nothing in
            between.  Small selections keep running unprompted so routine work
            stays quick.
            """

            if count <= self.BULK_CONFIRM_THRESHOLD:
                return True
            answer = QMessageBox.question(
                self,
                "Toplu değişikliği onayla",
                f"{count} kayda {description} uygulanacak. Bu işlem geri alınamaz. "
                "Devam edilsin mi?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            return answer == QMessageBox.StandardButton.Yes

        def delete_selected_books(self) -> None:
            ids = self._selected_library_ids()
            if not ids:
                self.statusBar().showMessage("Önce tabloda satır seçin", 4000)
                return
            answer = QMessageBox.question(
                self,
                "Seçilileri sil",
                f"{len(ids)} kayıt katalogdan tamamen silinecek: kapak kanıtı, "
                "OCR gözlemleri ve nüsha bilgisi dâhil. Bu işlem geri alınamaz — "
                "önce Dışa Aktarım sekmesinden .kitaparsiv yedeği alabilirsiniz. "
                "Devam edilsin mi?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer != QMessageBox.StandardButton.Yes:
                return

            def work() -> int:
                deleted = 0
                for edition_id in ids:
                    if self.catalog.delete_book(edition_id):
                        deleted += 1
                return deleted

            def done(count: object) -> None:
                self._library_clear_detail()
                self.library_table.clearSelection()
                self.refresh_library()
                self.refresh_review()
                self.statusBar().showMessage(f"{count} kayıt silindi", 4000)

            self._background(work, done, message="Kayıtlar siliniyor…")

        # --------------------------------------------------------------
        # Import queue and progress

        def _build_import_tab(self) -> None:
            page = QWidget()
            layout = QVBoxLayout(page)
            buttons = QHBoxLayout()
            import_single = QPushButton("Tek Kitap Ekle (4 Belge/PDF)")
            import_single.clicked.connect(self.choose_single_book_documents)
            import_folder = QPushButton("Toplu Kitap Klasörü Ekle")
            import_folder.clicked.connect(self.choose_import_folder)
            self.process_button = QPushButton("5 OCR İşlemeyi Başlat")
            self.process_button.clicked.connect(self.process_queue)
            self.pause_button = QPushButton("Duraklat")
            self.pause_button.clicked.connect(self.pause_selected_job)
            self.resume_button = QPushButton("Devam Et")
            self.resume_button.clicked.connect(self.resume_selected_job)
            self.retry_button = QPushButton("Seçili Hatayı Yeniden Dene")
            self.retry_button.clicked.connect(self.retry_selected_item)
            self._describe(
                (
                    import_single,
                    "Tek kitap ekle",
                    "Bir kitabın dört yüzünü sırayla seçin: ön kapak, ön iç kapak, "
                    "arka iç kapak, arka kapak. Dört sayfalı tek PDF de olur.",
                ),
                (
                    import_folder,
                    "Toplu kitap klasörü ekle",
                    "Klasördeki fotoğrafları dört yüzlü kitaplara eşleştirir. "
                    "Klasörü doğrudan pencereye de sürükleyebilirsiniz.",
                ),
                (
                    self.process_button,
                    "5 OCR işlemeyi başlat",
                    "Kuyruktaki kitapları beş OCR motoru ve alan çıkarıcıyla işler. "
                    "Kapatsanız da tamamlanan adımlar korunur.",
                ),
                (self.pause_button, "Duraklat", "Seçili işi güvenli bir noktada durdurur."),
                (
                    self.resume_button,
                    "Devam et",
                    "Duraklatılmış işi kaldığı yerden sürdürür; biten adımlar "
                    "yeniden çalıştırılmaz.",
                ),
                (
                    self.retry_button,
                    "Seçili hatayı yeniden dene",
                    "Yalnız hata veren motoru sıfırlar; o kitabın başarılı motor "
                    "sonuçları korunur.",
                ),
            )
            for button in (
                import_single,
                import_folder,
                self.process_button,
                self.pause_button,
                self.resume_button,
                self.retry_button,
            ):
                buttons.addWidget(button)
            buttons.addStretch(1)
            layout.addLayout(buttons)

            storage_row = QHBoxLayout()
            storage_row.addWidget(QLabel("Fotoğraf saklama:"))
            self.storage_mode = QComboBox()
            self.storage_mode.addItem("Yönetilen kopya (önerilen)", StorageMode.MANAGED_COPY.value)
            self.storage_mode.addItem("Yalnız kaynak dosyasına başvur", StorageMode.REFERENCE.value)
            storage_row.addWidget(self.storage_mode)
            self.capacity_label = QLabel(
                "Klasör seçildiğinde model, türev, OCR kanıtı ve yedek alanı "
                "iş başlamadan hesaplanır."
            )
            self.capacity_label.setWordWrap(True)
            storage_row.addWidget(self.capacity_label, 1)
            layout.addLayout(storage_row)

            splitter = QSplitter(Qt.Orientation.Vertical)
            jobs_group = QGroupBox("Toplu işler")
            jobs_layout = QVBoxLayout(jobs_group)
            self.jobs_table = QTableWidget(0, 7)
            self.jobs_table.setHorizontalHeaderLabels(
                ("İş", "Ad", "Durum", "Toplam", "Tamam", "İnceleme", "Hata")
            )
            self.jobs_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.jobs_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.jobs_table.horizontalHeader().setSectionResizeMode(
                1, QHeaderView.ResizeMode.Stretch
            )
            self.jobs_table.itemSelectionChanged.connect(self._job_selected)
            jobs_layout.addWidget(self.jobs_table)
            splitter.addWidget(jobs_group)

            detail = QWidget()
            detail_layout = QHBoxLayout(detail)
            progress_group = QGroupBox("Aşama ve motor ilerlemesi")
            progress_layout = QVBoxLayout(progress_group)
            self.job_progress = QProgressBar()
            self.job_progress.setRange(0, 100)
            self.job_progress_label = QLabel("Bir iş seçin")
            self.engine_progress_table = QTableWidget(0, 3)
            self.engine_progress_table.setHorizontalHeaderLabels(("Motor", "Durum", "Adet"))
            self.engine_progress_table.horizontalHeader().setSectionResizeMode(
                0, QHeaderView.ResizeMode.Stretch
            )
            self.engine_progress_table.setColumnWidth(1, 130)
            self.engine_progress_table.setColumnWidth(2, 90)
            progress_layout.addWidget(self.job_progress_label)
            progress_layout.addWidget(self.job_progress)
            progress_layout.addWidget(self.engine_progress_table)
            errors_group = QGroupBox("Hatalar")
            errors_layout = QVBoxLayout(errors_group)
            self.errors_table = QTableWidget(0, 3)
            self.errors_table.setHorizontalHeaderLabels(("Öğe", "Çift", "Hata"))
            self.errors_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.errors_table.horizontalHeader().setSectionResizeMode(
                2, QHeaderView.ResizeMode.Stretch
            )
            errors_layout.addWidget(self.errors_table)
            detail_layout.addWidget(progress_group, 1)
            detail_layout.addWidget(errors_group, 1)
            splitter.addWidget(detail)
            layout.addWidget(splitter)
            self._set_empty_hint(
                self.jobs_table,
                "Henüz iş yok. “Tek Kitap” ya da “Toplu Kitap” ile fotoğraf ekleyin; "
                "klasörü doğrudan bu pencereye de sürükleyebilirsiniz.",
            )
            self._set_empty_hint(self.errors_table, "Hatalı öğe yok.")
            self.tabs.addTab(page, "İçe Aktarma ve Kuyruk")

        def choose_import_folder(self) -> None:
            directory = QFileDialog.getExistingDirectory(
                self,
                "Ön, ön iç, arka iç ve arka belgelerini içeren toplu klasörü seçin",
            )
            if directory:
                self.import_folder(Path(directory))

        def import_folder(self, source: Path) -> None:
            """Queue a folder of covers, whether chosen in a dialog or dropped."""

            storage_mode = StorageMode(str(self.storage_mode.currentData()))

            def work() -> dict[str, Any]:
                documents = discover_documents(source)
                expanded = expand_bulk_documents(
                    documents,
                    self.paths.derivatives / "pdf-pages",
                )
                pairing = pair_cover_files(
                    expanded.images,
                    require_four_surfaces=True,
                )
                pairs = (*expanded.four_page_books, *pairing.pairs)
                pair_paths = tuple(
                    dict.fromkeys(
                        Path(path)
                        for pair in pairs
                        for path in pair.paths_by_role.values()
                        if path is not None
                    )
                )
                estimate = estimate_import_capacity(
                    pair_paths,
                    data_root=self.paths.root,
                    model_root=self.paths.models,
                    storage_mode=storage_mode,
                )
                # No job row is written unless the conservative estimate passes.
                require_capacity(estimate)
                first = pairs[:250]
                job = self.database.create_import_job(
                    f"Toplu • {source.name}",
                    first,
                    storage_mode=storage_mode,
                )
                for start in range(250, len(pairs), 250):
                    self.database.append_job_items(job.id, pairs[start : start + 250])
                job = self.database.get_import_job(job.id) or job
                return {
                    "job": job,
                    "documents": len(documents),
                    "images": len(expanded.images),
                    "pairs": len(pairs),
                    "review": pairing.needs_review_count,
                    "unpaired": len(pairing.unpaired),
                    "rejected": len(expanded.rejected),
                    "storage_mode": storage_mode,
                    "capacity": estimate,
                }

            def finished(result: dict[str, Any]) -> None:
                estimate = result["capacity"]
                mode_label = (
                    "yönetilen kopya"
                    if result["storage_mode"] is StorageMode.MANAGED_COPY
                    else "yalnız kaynağa başvuru"
                )
                self.capacity_label.setText(
                    f"Tahmin: {self._format_bytes(estimate.required_additional_bytes)} "
                    f"gerekli • {self._format_bytes(estimate.free_bytes)} boş • "
                    f"{mode_label}"
                )
                self.statusBar().showMessage(
                    f"{result['pairs']:,} dört-yüzlü kitap kuyruğa eklendi",
                    5000,
                )
                self.refresh_jobs()
                self.refresh_pair_reviews()
                if result["review"] or result["unpaired"]:
                    QMessageBox.information(
                        self,
                        "Eşleştirme özeti",
                        f"{result['documents']:,} belge, {result['pairs']:,} kitap.\n"
                        f"{result['review']:,} kitap onay bekliyor; "
                        f"{result['unpaired']:,} yüz eşleşmedi; "
                        f"{result['rejected']:,} PDF reddedildi.",
                    )

            self._background(work, finished, message="Dört yüzlü kitaplar eşleştiriliyor…")

        def choose_single_book_documents(self) -> None:
            first, _filter = QFileDialog.getOpenFileName(
                self,
                "Ön kapağı veya tek dört sayfalı PDF'yi seçin",
                "",
                "Kitap belgeleri (*.jpg *.jpeg *.png *.heic *.heif *.webp *.tif "
                "*.tiff *.bmp *.pdf)",
            )
            if not first:
                return
            selected = [first]
            first_path = Path(first)
            is_four_page_pdf = (
                first_path.suffix.casefold() == ".pdf" and pdf_page_count(first_path) == 4
            )
            if not is_four_page_pdf:
                prompts = (
                    "Ön iç kapağı seçin (ön kapaktan sonraki sayfa)",
                    "Arka iç kapağı seçin (arka kapaktan önceki sayfa)",
                    "Arka kapağı seçin",
                )
                for prompt in prompts:
                    document, _filter = QFileDialog.getOpenFileName(
                        self,
                        prompt,
                        str(first_path.parent),
                        "Kitap belgeleri (*.jpg *.jpeg *.png *.heic *.heif *.webp "
                        "*.tif *.tiff *.bmp *.pdf)",
                    )
                    if not document:
                        self.statusBar().showMessage(
                            "Tek kitap ekleme iptal edildi; dört yüzün tamamı gerekli.",
                            5000,
                        )
                        return
                    selected.append(document)
            storage_mode = StorageMode(str(self.storage_mode.currentData()))

            def work() -> dict[str, Any]:
                scan = build_single_book_scan(
                    selected,
                    self.paths.derivatives / "pdf-pages",
                )
                scan_paths = tuple(
                    Path(path) for path in scan.paths_by_role.values() if path is not None
                )
                estimate = estimate_import_capacity(
                    scan_paths,
                    data_root=self.paths.root,
                    model_root=self.paths.models,
                    storage_mode=storage_mode,
                )
                require_capacity(estimate)
                job = self.database.create_import_job(
                    f"Tek kitap • {Path(selected[0]).stem}",
                    (scan,),
                    storage_mode=storage_mode,
                )
                return {
                    "job": job,
                    "capacity": estimate,
                    "storage_mode": storage_mode,
                }

            def finished(result: dict[str, Any]) -> None:
                estimate = result["capacity"]
                self.capacity_label.setText(
                    f"Tek kitap: {self._format_bytes(estimate.required_additional_bytes)} "
                    f"gerekli • {self._format_bytes(estimate.free_bytes)} boş"
                )
                self.statusBar().showMessage(
                    "Tek kitap dört yüzüyle kuyruğa eklendi",
                    5000,
                )
                self.refresh_jobs()
                self.tabs.setCurrentIndex(1)

            self._background(
                work,
                finished,
                message="Tek kitabın dört belgesi hazırlanıyor…",
            )

        def process_queue(self) -> None:
            selected_job_id = self._selected_job_id
            self.process_button.setEnabled(False)

            def work() -> dict[str, int]:
                # This import constructs OCR adapters, so it stays behind the
                # already-installed process-wide network guard.
                from kitapkatalog.application import open_application

                context = open_application(self.paths)
                try:
                    scheduler = context.processing_scheduler()
                    if selected_job_id:
                        summary = scheduler.run_job(selected_job_id, worker_id="desktop-worker")
                        return {
                            "claims": summary.claims,
                            "cache_hits": summary.cache_hits,
                        }
                    summary = scheduler.run_all(worker_id="desktop-worker")
                    return {
                        "claims": summary.claims,
                        "cache_hits": summary.cache_hits,
                    }
                finally:
                    context.close()

            def finished(result: dict[str, int]) -> None:
                self.statusBar().showMessage(
                    f"{result['claims']:,} kitap işlendi; "
                    f"{result['cache_hits']:,} OCR önbellekten geldi",
                    8000,
                )
                self.refresh_all()

            worker = self._background(
                work,
                finished,
                message=(
                    "Seçili iş beş OCR ile işleniyor…"
                    if selected_job_id
                    else "Kuyruk beş OCR ile işleniyor…"
                ),
            )
            worker.signals.finished.connect(lambda: self.process_button.setEnabled(True))

        def refresh_jobs(self) -> None:
            jobs = self.database.list_import_jobs(limit=250)
            rows = [
                [
                    job.id[:8],
                    job.name,
                    self._status(job.status),
                    job.total_items,
                    job.successful_items,
                    job.review_items,
                    job.failed_items,
                ]
                for job in jobs
            ]
            selected = self._selected_job_id
            self._fill_table(self.jobs_table, rows, first_column_data=[job.id for job in jobs])
            if selected:
                for row in range(self.jobs_table.rowCount()):
                    item = self.jobs_table.item(row, 0)
                    if item and item.data(Qt.ItemDataRole.UserRole) == selected:
                        self.jobs_table.selectRow(row)
                        break
                self.refresh_job_detail()

        def _job_selected(self) -> None:
            items = self.jobs_table.selectedItems()
            if not items:
                return
            self._selected_job_id = str(
                self.jobs_table.item(items[0].row(), 0).data(Qt.ItemDataRole.UserRole)
            )
            self.refresh_job_detail()

        def refresh_job_detail(self) -> None:
            if not self._selected_job_id:
                return
            try:
                progress = self.database.job_progress(self._selected_job_id)
            except KeyError:
                self._selected_job_id = None
                return
            job = progress["job"]
            finished = job.terminal_items
            percentage = round(100 * finished / job.total_items) if job.total_items else 100
            self.job_progress.setValue(percentage)
            speed = 0.0
            elapsed_seconds = 0.0
            if job.started_at is not None:
                elapsed_seconds = max(
                    0.0,
                    (datetime.now(UTC) - job.started_at.astimezone(UTC)).total_seconds(),
                )
                if elapsed_seconds > 0:
                    speed = finished * 3600 / elapsed_seconds
            remaining = max(0, job.total_items - finished)
            if remaining == 0:
                speed_text = f"{speed:,.1f} kitap/saat" if speed else "ölçüm tamamlandı"
                eta_text = "tamamlandı"
            elif speed > 0:
                speed_text = f"{speed:,.1f} kitap/saat"
                eta_text = self._format_duration(remaining * 3600 / speed)
            else:
                speed_text = "ölçülüyor"
                eta_text = "—"
            self.job_progress_label.setText(
                f"{job.name}: {finished:,}/{job.total_items:,} — %{percentage} • "
                f"{self._status(job.status)} • Hız: {speed_text} • Kalan: {eta_text}"
            )
            engine_rows: list[list[Any]] = []
            for key, count in sorted(progress["engines"].items()):
                engine, status = key.rsplit(":", 1)
                engine_rows.append(
                    [
                        _ENGINE_NAMES.get(engine, engine),
                        self._status(status),
                        count,
                    ]
                )
            self._fill_table(self.engine_progress_table, engine_rows)
            failed = self.database.list_job_items(job.id, stage="failed", limit=10_000)
            self._fill_table(
                self.errors_table,
                [[item.id, item.pair_key, item.last_error] for item in failed],
                first_column_data=[item.id for item in failed],
            )

        def pause_selected_job(self) -> None:
            if self._selected_job_id:
                try:
                    self.database.pause_job(self._selected_job_id)
                    self.refresh_jobs()
                except (KeyError, ValueError, RuntimeError) as exc:
                    self._show_error(str(exc))

        def resume_selected_job(self) -> None:
            if self._selected_job_id:
                try:
                    self.database.resume_job(self._selected_job_id)
                    self.refresh_jobs()
                except (KeyError, ValueError, RuntimeError) as exc:
                    self._show_error(str(exc))

        def retry_selected_item(self) -> None:
            items = self.errors_table.selectedItems()
            if not items:
                return
            item_id = int(self.errors_table.item(items[0].row(), 0).data(Qt.ItemDataRole.UserRole))
            try:
                self.database.retry_failed_item(item_id)
                self.refresh_jobs()
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))

        # --------------------------------------------------------------
        # Ambiguous four-surface pairing review

        # --------------------------------------------------------------
        # Sesli Kayıt

        def _build_voice_tab(self) -> None:
            page = QWidget()
            outer = QVBoxLayout(page)
            splitter = QSplitter(Qt.Orientation.Vertical)

            live = QGroupBox("Canlı Mikrofon — kitap başına bas-konuş")
            live_layout = QVBoxLayout(live)
            controls = QHBoxLayout()
            controls.addWidget(QLabel("Aygıt:"))
            self.voice_device = QComboBox()
            self.voice_device.addItem("Varsayılan aygıt", -1)
            controls.addWidget(self.voice_device, 1)
            self.voice_record_button = QPushButton("● Kayıt (F2)")
            self.voice_record_button.clicked.connect(self.toggle_voice_recording)
            controls.addWidget(self.voice_record_button)
            self.voice_level = QProgressBar()
            self.voice_level.setRange(0, 100)
            self.voice_level.setTextVisible(False)
            self.voice_level.setFixedWidth(160)
            controls.addWidget(self.voice_level)
            self.voice_elapsed = QLabel("")
            controls.addWidget(self.voice_elapsed)
            self.voice_permission = QLabel("Mikrofon izni: bilinmiyor")
            controls.addWidget(self.voice_permission)
            live_layout.addLayout(controls)
            self._voice_elapsed_seconds = 0
            self.voice_elapsed_timer = QTimer(self)
            self.voice_elapsed_timer.setInterval(1000)
            self.voice_elapsed_timer.timeout.connect(self._voice_elapsed_tick)

            options = QHBoxLayout()
            self.voice_auto_stop = QCheckBox("1,5 sn sessizlikte otomatik durdur")
            self.voice_fast_mode = QCheckBox(
                "Hızlı mod: uygun kayıtları otomatik kaydet (incelemede kalır)"
            )
            options.addWidget(self.voice_auto_stop)
            options.addWidget(self.voice_fast_mode)
            options.addStretch(1)
            live_layout.addLayout(options)

            body = QHBoxLayout()
            left = QVBoxLayout()
            left.addWidget(QLabel("Transkript:"))
            self.voice_transcript = QPlainTextEdit()
            self.voice_transcript.setReadOnly(True)
            self.voice_transcript.setMaximumBlockCount(200)
            left.addWidget(self.voice_transcript, 1)
            self.voice_reasons = QLabel("")
            self.voice_reasons.setWordWrap(True)
            self.voice_reasons.setStyleSheet(f"color: {self._hint_colour(self.voice_reasons)};")
            left.addWidget(self.voice_reasons)
            left.addWidget(QLabel("Son kaydedilenler (çift tık: kütüphanede aç):"))
            self.voice_recent_list = QListWidget()
            self.voice_recent_list.setMaximumHeight(120)
            self.voice_recent_list.itemDoubleClicked.connect(
                lambda item: self._focus_library_book(int(item.data(Qt.ItemDataRole.UserRole)))
            )
            left.addWidget(self.voice_recent_list)
            body.addLayout(left, 1)

            form_holder = QWidget()
            form = QFormLayout(form_holder)
            self.voice_isbn = QLineEdit()
            self.voice_isbn.textChanged.connect(self._voice_isbn_changed)
            self.voice_title = QLineEdit()
            self.voice_author = QLineEdit()
            self.voice_publisher = QLineEdit()
            self.voice_year = QLineEdit()
            self.voice_pages = QSpinBox()
            self.voice_pages.setRange(0, 99_999)
            self.voice_pages.setSpecialValueText("—")
            self.voice_language = QComboBox()
            self.voice_language.setEditable(True)
            self.voice_category = QComboBox()
            self.voice_category.setEditable(True)
            self.voice_location = QComboBox()
            self.voice_location.setEditable(True)
            self.voice_location.lineEdit().setPlaceholderText(
                "Yapışkan: raf değişene dek kalır; sesle 'dolap A5'"
            )
            self.voice_copies = QSpinBox()
            self.voice_copies.setRange(1, 99)
            form.addRow("ISBN", self.voice_isbn)
            form.addRow("Başlık", self.voice_title)
            form.addRow("Yazar(lar) (;)", self.voice_author)
            form.addRow("Yayınevi", self.voice_publisher)
            form.addRow("Basım yılı", self.voice_year)
            form.addRow("Sayfa", self.voice_pages)
            form.addRow("Dil", self.voice_language)
            form.addRow("Kategori", self.voice_category)
            form.addRow("Dolap", self.voice_location)
            form.addRow("Adet", self.voice_copies)
            actions = QHBoxLayout()
            self.voice_save_button = QPushButton("Kaydet ve Sıradaki (Enter)")
            self.voice_save_button.clicked.connect(self.save_voice_current)
            redo = QPushButton("Yeniden Söyle (F4)")
            redo.clicked.connect(self.redo_voice_current)
            skip = QPushButton("Atla (F6)")
            skip.clicked.connect(self.skip_voice_current)
            actions.addWidget(self.voice_save_button)
            actions.addWidget(redo)
            actions.addWidget(skip)
            form.addRow("", actions)
            body.addWidget(form_holder, 1)
            live_layout.addLayout(body, 1)
            splitter.addWidget(live)

            batch = AudioDropGroupBox(
                "Toplu Ses Dosyaları — telefonda kaydedilen raflar "
                "(dosyaları buraya sürükleyebilirsiniz)"
            )
            batch.filesDropped.connect(self._enqueue_voice_files)
            batch_layout = QVBoxLayout(batch)
            batch_buttons = QHBoxLayout()
            add_files = QPushButton("Ses Dosyası Ekle…")
            add_files.clicked.connect(self.choose_voice_files)
            self.voice_process_button = QPushButton("Kuyruğu İşle")
            self.voice_process_button.clicked.connect(self.process_voice_queue)
            voice_pause = QPushButton("Duraklat")
            voice_pause.clicked.connect(self.pause_selected_voice_job)
            voice_resume = QPushButton("Devam Et")
            voice_resume.clicked.connect(self.resume_selected_voice_job)
            for button in (
                add_files,
                self.voice_process_button,
                voice_pause,
                voice_resume,
            ):
                batch_buttons.addWidget(button)
            batch_buttons.addStretch(1)
            batch_layout.addLayout(batch_buttons)
            self.voice_jobs_table = QTableWidget(0, 8)
            self.voice_jobs_table.setHorizontalHeaderLabels(
                ("İş", "Ad", "Durum", "Faz", "Toplam", "Tamam", "İnceleme", "Hata")
            )
            self.voice_jobs_table.setSelectionBehavior(
                QAbstractItemView.SelectionBehavior.SelectRows
            )
            self.voice_jobs_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.voice_jobs_table.horizontalHeader().setSectionResizeMode(
                1, QHeaderView.ResizeMode.Stretch
            )
            batch_layout.addWidget(self.voice_jobs_table)
            splitter.addWidget(batch)
            outer.addWidget(splitter)

            for key, slot in (
                ("F2", self.toggle_voice_recording),
                ("F4", self.redo_voice_current),
                ("F6", self.skip_voice_current),
            ):
                shortcut = QShortcut(QKeySequence(key), page)
                shortcut.setContext(Qt.ShortcutContext.WidgetWithChildrenShortcut)
                shortcut.activated.connect(slot)
            for key in ("Return", "Enter"):
                shortcut = QShortcut(QKeySequence(key), form_holder)
                shortcut.setContext(Qt.ShortcutContext.WidgetWithChildrenShortcut)
                shortcut.activated.connect(self.save_voice_current)

            self._voice_refresh_suggestions()
            self.tabs.addTab(page, "Sesli Kayıt")

        def _voice_refresh_suggestions(self) -> None:
            for combo, column in (
                (self.voice_language, "language"),
                (self.voice_category, "category"),
                (self.voice_location, "location"),
            ):
                current = combo.currentText()
                combo.blockSignals(True)
                combo.clear()
                combo.addItem("")
                for value in self.catalog.list_distinct_values(column):
                    combo.addItem(value)
                combo.setCurrentText(current)
                combo.blockSignals(False)

        def _voice_session_get(self) -> Any:
            if self._voice_session is None:
                if self._voice_session_factory is not None:
                    self._voice_session = self._voice_session_factory()
                else:
                    from kitapkatalog.voice_controller import VoiceSession
                    from kitapkatalog.voice_scheduler import resolve_qwen_factory

                    self._voice_session = VoiceSession(
                        self.database,
                        self.paths,
                        qwen_client_factory=resolve_qwen_factory(self.paths),
                    )
            return self._voice_session

        def _voice_capture_get(self) -> Any:
            if self._voice_capture is None:
                if self._voice_capture_factory is not None:
                    capture = self._voice_capture_factory()
                else:
                    from kitapkatalog.voice_controller import (
                        build_voice_capture_class,
                    )

                    capture_class = build_voice_capture_class()
                    capture = capture_class(self.paths.derivatives / "voice-live")
                capture.levelChanged.connect(self._voice_level_changed)
                capture.finished.connect(self._voice_captured)
                capture.errorOccurred.connect(self._voice_capture_error)
                self._voice_capture = capture
                with suppress(Exception):
                    self.voice_device.clear()
                    self.voice_device.addItem("Varsayılan aygıt", -1)
                    for index, label in capture.input_devices():
                        self.voice_device.addItem(label, index)
                with suppress(Exception):
                    self.voice_permission.setText(f"Mikrofon izni: {capture.permission_status()}")
            return self._voice_capture

        def toggle_voice_recording(self) -> None:
            try:
                capture = self._voice_capture_get()
            except Exception as exc:
                self._show_error(str(exc))
                return
            if getattr(capture, "recording", False):
                capture.stop()
                self.voice_record_button.setText("● Kayıt (F2)")
                self.voice_elapsed_timer.stop()
                return
            capture.auto_stop_enabled = self.voice_auto_stop.isChecked()
            device_data = self.voice_device.currentData()
            device_index = -1 if device_data is None else int(device_data)
            capture.start(device_index)
            if getattr(capture, "recording", False):
                self.voice_record_button.setText("■ Durdur (F2)")
                self._voice_elapsed_seconds = 0
                self.voice_elapsed.setText("● 00:00")
                self.voice_elapsed_timer.start()
                self.statusBar().showMessage("Kayıt: kitap bilgisini söyleyin…")

        def _voice_elapsed_tick(self) -> None:
            self._voice_elapsed_seconds += 1
            minutes, seconds = divmod(self._voice_elapsed_seconds, 60)
            self.voice_elapsed.setText(f"● {minutes:02d}:{seconds:02d}")

        def _voice_level_changed(self, level: float) -> None:
            self.voice_level.setValue(min(100, int(level * 300)))

        def _voice_capture_error(self, message: str) -> None:
            self.voice_record_button.setText("● Kayıt (F2)")
            self.voice_elapsed_timer.stop()
            self.statusBar().showMessage(message, 5000)

        def _voice_captured(self, wav_path: str) -> None:
            self.voice_record_button.setText("● Kayıt (F2)")
            self.voice_elapsed_timer.stop()
            self.voice_level.setValue(0)
            session = self._voice_session_get()
            self._background(
                lambda: session.analyze(Path(wav_path)),
                self._voice_analyzed,
                message="Söylem yazıya çevriliyor…",
            )

        def _voice_analyzed(self, pending: Any) -> None:
            self._voice_pending = pending
            result = pending.result
            self.voice_transcript.setPlainText(pending.transcript)
            self._voice_fill_form(result)
            reasons = list(result.review_reasons)
            self.voice_reasons.setText(" • ".join(reasons))
            if self.voice_fast_mode.isChecked():
                session = self._voice_session_get()
                similar = []
                if result.isbn is None:
                    similar = session.similar_books(
                        result.value_of("title") or "",
                        result.value_of("author") or "",
                    )
                if session.auto_save_allowed(result, similar):
                    self._voice_commit(result, approve=False)
                    return
            self.statusBar().showMessage("Alanları kontrol edin; Enter kaydeder", 5000)
            self.voice_title.setFocus()

        def _voice_fill_form(self, result: Any) -> None:
            self.voice_isbn.setText(result.isbn or "")
            self.voice_title.setText(result.value_of("title") or "")
            self.voice_author.setText(result.value_of("author") or "")
            self.voice_publisher.setText(result.value_of("publisher") or "")
            self.voice_year.setText(result.value_of("publication_date") or "")
            pages = result.value_of("page_count")
            self.voice_pages.setValue(int(pages) if pages else 0)
            self.voice_language.setCurrentText(result.value_of("language") or "")
            self.voice_category.setCurrentText(result.value_of("category") or "")
            location = result.value_of("location")
            if location:  # sesten gelmediyse yapışkan dolap değeri korunur
                self.voice_location.setCurrentText(location)
            self.voice_copies.setValue(result.copy_count)

        def _voice_isbn_changed(self, text: str) -> None:
            from kitapkatalog.voice_protocol import isbn_candidates_from_span

            if not text.strip():
                self.voice_isbn.setStyleSheet("")
                return
            valid = len(isbn_candidates_from_span(text)) == 1
            self.voice_isbn.setStyleSheet("" if valid else "border: 1px solid #c62828;")

        def _voice_form_values(self) -> dict[str, str]:
            return {
                "isbn": self.voice_isbn.text(),
                "title": self.voice_title.text(),
                "author": self.voice_author.text(),
                "publisher": self.voice_publisher.text(),
                "publication_date": self.voice_year.text(),
                "page_count": (
                    str(self.voice_pages.value()) if self.voice_pages.value() > 0 else ""
                ),
                "language": self.voice_language.currentText(),
                "category": self.voice_category.currentText(),
                "location": self.voice_location.currentText(),
            }

        def save_voice_current(self) -> None:
            if self._voice_pending is None:
                self.statusBar().showMessage(
                    "Önce kayıt yapın (F2) — ses kanıtı olmadan kayıt yazılmaz",
                    5000,
                )
                return
            session = self._voice_session_get()
            result = session.form_result(
                self._voice_form_values(),
                copy_count=self.voice_copies.value(),
            )
            if result.value_of("title") is None:
                self._show_error("Başlık boş olamaz")
                return
            merge_into: int | None = None
            if result.isbn is None:
                similar = session.similar_books(
                    result.value_of("title") or "",
                    result.value_of("author") or "",
                )
                if similar:
                    best = similar[0]
                    box = QMessageBox(self)
                    box.setWindowTitle("Benzer kayıt bulundu")
                    box.setText(
                        f"Katalogta çok benzer bir kayıt var:\n"
                        f"#{best.edition_id} — {best.title} ({best.authors})\n\n"
                        "Bu kitabın adedini mi artırmak istiyorsunuz?"
                    )
                    increase = box.addButton("Adet Artır", QMessageBox.ButtonRole.AcceptRole)
                    box.addButton("Yine de Yeni Kayıt", QMessageBox.ButtonRole.ActionRole)
                    cancel = box.addButton("Vazgeç", QMessageBox.ButtonRole.RejectRole)
                    box.exec()
                    if box.clickedButton() is cancel:
                        return
                    if box.clickedButton() is increase:
                        merge_into = best.edition_id
            self._voice_commit(result, approve=True, merge_into=merge_into)

        def _voice_commit(
            self,
            result: Any,
            *,
            approve: bool,
            merge_into: int | None = None,
        ) -> None:
            if getattr(self, "_voice_commit_running", False):
                return  # çift Enter tek kayıt yazsın
            pending = self._voice_pending
            if pending is None:
                return
            session = self._voice_session_get()
            self._voice_commit_running = True

            def done(edition_id: object) -> None:
                self._voice_commit_running = False
                self._voice_recent_add(
                    int(edition_id),  # type: ignore[arg-type]
                    result.value_of("title") or "(başlıksız)",
                    approved=approve,
                )
                # Kullanıcı bu arada YENİ bir söylem kaydettiyse onun formunu
                # silme; yalnız hâlâ bizim pending'imizse temizle.
                if self._voice_pending is pending:
                    self._voice_clear(after_save=True)
                self.refresh_review()
                self.refresh_library()
                note = "onaylandı" if approve else "otomatik (incelemede)"
                self.statusBar().showMessage(f"Kayıt #{edition_id} {note}", 4000)
                if (
                    self.voice_fast_mode.isChecked()
                    and self.voice_auto_stop.isChecked()
                    and self._voice_pending is None
                ):
                    self.toggle_voice_recording()  # eller-serbest zincir

            worker = self._background(
                lambda: session.save(
                    pending,
                    result,
                    approve=approve,
                    merge_into_edition=merge_into,
                ),
                done,
                message="Katalog kaydı yazılıyor…",
            )
            worker.signals.failed.connect(
                lambda _msg: setattr(self, "_voice_commit_running", False)
            )

        def _voice_clear(self, *, after_save: bool) -> None:
            self._voice_pending = None
            self.voice_transcript.clear()
            self.voice_reasons.clear()
            self.voice_isbn.clear()
            self.voice_title.clear()
            self.voice_author.clear()
            self.voice_publisher.clear()
            self.voice_year.clear()
            self.voice_pages.setValue(0)
            self.voice_language.setCurrentText("")
            self.voice_category.setCurrentText("")
            self.voice_copies.setValue(1)
            if after_save:
                self._voice_refresh_suggestions()

        def redo_voice_current(self) -> None:
            if self._voice_pending is not None:
                with suppress(OSError):
                    Path(self._voice_pending.wav_path).unlink()
            self._voice_clear(after_save=False)
            self.toggle_voice_recording()

        def skip_voice_current(self) -> None:
            self._voice_clear(after_save=False)
            self.statusBar().showMessage("Söylem atlandı", 3000)

        def _voice_recent_add(self, edition_id: int, title: str, *, approved: bool) -> None:
            from PySide6.QtWidgets import QListWidgetItem

            note = "onaylandı" if approved else "incelemede"
            item = QListWidgetItem(f"#{edition_id} — {title} • {note}")
            item.setData(Qt.ItemDataRole.UserRole, edition_id)
            self.voice_recent_list.insertItem(0, item)
            while self.voice_recent_list.count() > 10:
                self.voice_recent_list.takeItem(self.voice_recent_list.count() - 1)

        def _focus_library_book(self, edition_id: int) -> None:
            self._selected_library_id = edition_id
            self.tabs.setCurrentIndex(0)
            self.refresh_library()

        # Toplu ses dosyaları

        def _voice_batch_scheduler_get(self) -> Any:
            if self._voice_batch_scheduler is None:
                from kitapkatalog.voice_scheduler import build_voice_scheduler

                self._voice_batch_scheduler = build_voice_scheduler(self.database, self.paths)
            return self._voice_batch_scheduler

        def choose_voice_files(self) -> None:
            files, _ = QFileDialog.getOpenFileNames(
                self,
                "Toplu ses kayıtlarını seçin",
                "",
                "Ses dosyaları (*.m4a *.mp3 *.wav *.aac *.flac *.ogg)",
            )
            if files:
                self._enqueue_voice_files(files)

        def _enqueue_voice_files(self, files: list[str]) -> None:
            if not files:
                return
            scheduler = self._voice_batch_scheduler_get()

            def work() -> int:
                for item in files:
                    scheduler.enqueue(Path(item))
                return len(files)

            self._background(
                work,
                lambda count: (
                    self.refresh_voice_jobs(),
                    self.statusBar().showMessage(f"{count} ses dosyası kuyruğa alındı", 4000),
                ),
                message="Ses dosyaları kuyruğa alınıyor…",
            )

        def process_voice_queue(self) -> None:
            if self._voice_batch_running:
                self.statusBar().showMessage("Ses kuyruğu zaten işleniyor", 3000)
                return
            scheduler = self._voice_batch_scheduler_get()
            self._voice_batch_running = True
            self.voice_process_button.setEnabled(False)

            def work() -> int:
                processed = 0
                while scheduler.run_next() is not None:
                    processed += 1
                return processed

            def done(count: object) -> None:
                self._voice_batch_running = False
                self.voice_process_button.setEnabled(True)
                self.refresh_voice_jobs()
                self.refresh_review()
                self.refresh_library()
                self.statusBar().showMessage(f"Ses kuyruğu bitti ({count} iş)", 5000)

            worker = self._background(work, done, message="Ses kuyruğu işleniyor…")
            worker.signals.failed.connect(
                lambda _msg: (
                    setattr(self, "_voice_batch_running", False),
                    self.voice_process_button.setEnabled(True),
                )
            )

        def _selected_voice_job_id(self) -> str | None:
            items = self.voice_jobs_table.selectedItems()
            if not items:
                return None
            data = self.voice_jobs_table.item(items[0].row(), 0)
            return str(data.data(Qt.ItemDataRole.UserRole)) if data else None

        def pause_selected_voice_job(self) -> None:
            job_id = self._selected_voice_job_id()
            if job_id:
                self.database.pause_voice_job(job_id)
                self.refresh_voice_jobs()

        def resume_selected_voice_job(self) -> None:
            job_id = self._selected_voice_job_id()
            if job_id:
                self.database.resume_voice_job(job_id)
                self.refresh_voice_jobs()

        def refresh_voice_jobs(self) -> None:
            jobs = self.database.list_voice_jobs()
            self._fill_table(
                self.voice_jobs_table,
                [
                    [
                        job.id,
                        job.name,
                        _STATUS_TR.get(job.status.value, job.status.value),
                        job.phase.value,
                        job.total_items,
                        job.successful_items,
                        job.review_items,
                        job.failed_items,
                    ]
                    for job in jobs
                ],
                first_column_data=[job.id for job in jobs],
            )

        def _build_pair_review_tab(self) -> None:
            page = QWidget()
            layout = QHBoxLayout(page)
            self.pair_review_table = QTableWidget(0, 9)
            self.pair_review_table.setHorizontalHeaderLabels(
                (
                    "Öğe",
                    "İş",
                    "Kitap",
                    "Yöntem",
                    "Güven",
                    "Ön",
                    "Ön İç",
                    "Arka İç",
                    "Arka",
                )
            )
            self.pair_review_table.setSelectionBehavior(
                QAbstractItemView.SelectionBehavior.SelectRows
            )
            self.pair_review_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.pair_review_table.horizontalHeader().setSectionResizeMode(
                2, QHeaderView.ResizeMode.Stretch
            )
            self.pair_review_table.setColumnWidth(0, 75)
            self.pair_review_table.setColumnWidth(1, 90)
            self.pair_review_table.setColumnWidth(3, 150)
            self.pair_review_table.setColumnWidth(4, 80)
            self.pair_review_table.itemSelectionChanged.connect(self._pair_review_selected)
            layout.addWidget(self.pair_review_table, 3)

            decision = QWidget()
            decision_layout = QVBoxLayout(decision)
            notice = QLabel(
                "Belirsiz dört-yüzlü eşleştirmeler onaylanmadan OCR kuyruğuna alınmaz. "
                "Reddetmek öğeyi hata kuyruğuna taşır."
            )
            notice.setWordWrap(True)
            decision_layout.addWidget(notice)
            previews = QGridLayout()
            self.pair_front_preview = QLabel("Ön kapak")
            self.pair_front_inside_preview = QLabel("Ön iç kapak")
            self.pair_back_inside_preview = QLabel("Arka iç kapak")
            self.pair_back_preview = QLabel("Arka kapak")
            pair_previews = (
                self.pair_front_preview,
                self.pair_front_inside_preview,
                self.pair_back_inside_preview,
                self.pair_back_preview,
            )
            for index, preview in enumerate(pair_previews):
                preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
                preview.setMinimumSize(150, 190)
                preview.setStyleSheet(f"border: 1px solid {self._border_colour(preview)};")
                previews.addWidget(preview, index // 2, index % 2)
            decision_layout.addLayout(previews)
            self.pair_review_detail = QLabel("Bir eşleştirme seçin")
            self.pair_review_detail.setWordWrap(True)
            decision_layout.addWidget(self.pair_review_detail)
            actions = QHBoxLayout()
            approve = QPushButton("Eşleştirmeyi Onayla")
            approve.clicked.connect(self.approve_selected_pair)
            reject = QPushButton("Eşleştirmeyi Reddet")
            reject.clicked.connect(self.reject_selected_pair)
            actions.addWidget(approve)
            actions.addWidget(reject)
            decision_layout.addLayout(actions)
            decision_layout.addStretch(1)
            layout.addWidget(decision, 2)
            self._set_empty_hint(
                self.pair_review_table,
                "Onay bekleyen eşleştirme yok. Dört yüzü kendiliğinden eşleşemeyen "
                "kitaplar burada listelenir.",
            )
            self.tabs.addTab(page, "Eşleştirme Onayı")

        def refresh_pair_reviews(self) -> None:
            items = self.database.list_pending_pair_reviews(limit=10_000)
            rows = [
                [
                    item.id,
                    item.job_id[:8],
                    item.pair_key,
                    item.pairing_basis,
                    f"%{item.pairing_confidence * 100:.1f}",
                    item.front_path.name,
                    item.front_inside_path.name if item.front_inside_path else "",
                    item.back_inside_path.name if item.back_inside_path else "",
                    item.back_path.name,
                ]
                for item in items
            ]
            self._fill_table(
                self.pair_review_table,
                rows,
                first_column_data=[item.id for item in items],
            )
            if self._selected_pair_review_id is not None:
                selected_exists = False
                for row in range(self.pair_review_table.rowCount()):
                    cell = self.pair_review_table.item(row, 0)
                    if (
                        cell
                        and cell.data(Qt.ItemDataRole.UserRole) == self._selected_pair_review_id
                    ):
                        self.pair_review_table.selectRow(row)
                        selected_exists = True
                        break
                if not selected_exists:
                    self._selected_pair_review_id = None
                    self.pair_review_detail.setText("Bir eşleştirme seçin")
                    self._set_preview(self.pair_front_preview, None, "Ön kapak")
                    self._set_preview(self.pair_front_inside_preview, None, "Ön iç kapak")
                    self._set_preview(self.pair_back_inside_preview, None, "Arka iç kapak")
                    self._set_preview(self.pair_back_preview, None, "Arka kapak")

        def _pair_review_selected(self) -> None:
            rows = self.pair_review_table.selectionModel().selectedRows()
            if not rows:
                return
            item_id = int(
                self.pair_review_table.item(rows[0].row(), 0).data(Qt.ItemDataRole.UserRole)
            )
            item = self.database.get_job_item(item_id)
            if item is None:
                return
            self._selected_pair_review_id = item_id
            self._set_preview(self.pair_front_preview, str(item.front_path), "Ön kapak")
            self._set_preview(
                self.pair_front_inside_preview,
                str(item.front_inside_path) if item.front_inside_path else None,
                "Ön iç kapak",
            )
            self._set_preview(
                self.pair_back_inside_preview,
                str(item.back_inside_path) if item.back_inside_path else None,
                "Arka iç kapak",
            )
            self._set_preview(self.pair_back_preview, str(item.back_path), "Arka kapak")
            self.pair_review_detail.setText(
                f"Öğe #{item.id} • yöntem: {item.pairing_basis} • "
                f"güven: %{item.pairing_confidence * 100:.1f}\n"
                f"Ön: {item.front_path}\n"
                f"Ön iç: {item.front_inside_path or 'bilinmiyor'}\n"
                f"Arka iç: {item.back_inside_path or 'bilinmiyor'}\n"
                f"Arka: {item.back_path}"
            )

        def _decide_selected_pair(self, *, approved: bool) -> None:
            if self._selected_pair_review_id is None:
                return
            try:
                self.database.approve_pair(
                    self._selected_pair_review_id,
                    approved=approved,
                )
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._selected_pair_review_id = None
            self.refresh_pair_reviews()
            self.refresh_jobs()
            self.statusBar().showMessage(
                "Eşleştirme onaylandı"
                if approved
                else "Eşleştirme reddedildi ve hata kuyruğuna taşındı",
                4000,
            )

        def approve_selected_pair(self) -> None:
            self._decide_selected_pair(approved=True)

        def reject_selected_pair(self) -> None:
            if self._selected_pair_review_id is None:
                return
            answer = QMessageBox.question(
                self,
                "Eşleştirmeyi reddet",
                "Bu çift hata kuyruğuna taşınacak. Devam edilsin mi?",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer == QMessageBox.StandardButton.Yes:
                self._decide_selected_pair(approved=False)

        # --------------------------------------------------------------
        # Bibliographic review

        def _build_review_tab(self) -> None:
            page = QWidget()
            layout = QHBoxLayout(page)
            self.review_table = QTableWidget(0, 5)
            self.review_table.setHorizontalHeaderLabels(
                ("No", "Başlık", "Yazar / Katkıda Bulunan", "Yayınevi", "Kaynak")
            )
            self.review_table.setSelectionBehavior(QAbstractItemView.SelectionBehavior.SelectRows)
            self.review_table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
            self.review_table.horizontalHeader().setSectionResizeMode(
                1, QHeaderView.ResizeMode.Stretch
            )
            self.review_table.itemSelectionChanged.connect(self._review_selected)
            layout.addWidget(self.review_table, 1)

            editor = QWidget()
            editor_layout = QVBoxLayout(editor)
            previews = QGridLayout()
            self.front_preview = QLabel("Ön kapak")
            self.front_inside_preview = QLabel("Ön iç kapak")
            self.back_inside_preview = QLabel("Arka iç kapak")
            self.back_preview = QLabel("Arka kapak")
            book_previews = (
                self.front_preview,
                self.front_inside_preview,
                self.back_inside_preview,
                self.back_preview,
            )
            for index, preview in enumerate(book_previews):
                preview.setAlignment(Qt.AlignmentFlag.AlignCenter)
                preview.setMinimumSize(150, 180)
                preview.setStyleSheet(f"border: 1px solid {self._border_colour(preview)};")
                previews.addWidget(preview, index // 2, index % 2)
            editor_layout.addLayout(previews)
            self.review_transcript = QPlainTextEdit()
            self.review_transcript.setReadOnly(True)
            self.review_transcript.setPlaceholderText(
                "Sesli kayıtlarda söylem transkripti burada görünür"
            )
            self.review_transcript.setMaximumBlockCount(200)
            self.review_transcript.setVisible(False)
            editor_layout.addWidget(self.review_transcript)
            self.review_play_button = QPushButton("Sesi Çal")
            self.review_play_button.clicked.connect(self.play_review_audio)
            self.review_play_button.setVisible(False)
            editor_layout.addWidget(self.review_play_button)
            form = QFormLayout()
            self.review_title = QLineEdit()
            self.review_subtitle = QLineEdit()
            self.review_publisher = QLineEdit()
            self.review_category = QComboBox()
            self.review_category.setEditable(True)
            self.review_year = QLineEdit()
            self.review_pages = QSpinBox()
            self.review_pages.setRange(0, 99_999)
            self.review_pages.setSpecialValueText("—")
            self.review_language = QLineEdit()
            self.review_location = QLineEdit()
            self.review_location.setPlaceholderText("Örn. A Dolabı / Raf 3")
            self.review_blurb = QPlainTextEdit()
            form.addRow("Başlık", self.review_title)
            form.addRow("Alt başlık", self.review_subtitle)
            form.addRow("Yayınevi", self.review_publisher)
            form.addRow("Kategori", self.review_category)
            form.addRow("Basım yılı", self.review_year)
            form.addRow("Sayfa", self.review_pages)
            form.addRow("Dil", self.review_language)
            form.addRow("Dolap", self.review_location)
            form.addRow("Tanıtım", self.review_blurb)
            editor_layout.addLayout(form)
            save = QPushButton("Düzeltmeleri Kaydet ve Onayla")
            save.clicked.connect(self.save_review)
            editor_layout.addWidget(save)

            # Reviewing is what produces the labels a calibration profile needs,
            # and that profile is the only thing that turns automatic field
            # acceptance on. Showing the progress makes the trade visible.
            calibration_box = QGroupBox("Otomatik kabul için kalibrasyon")
            calibration_layout = QVBoxLayout(calibration_box)
            self.calibration_status = QLabel("Kalibrasyon durumu okunuyor…")
            self.calibration_status.setWordWrap(True)
            calibration_layout.addWidget(self.calibration_status)
            self.calibration_progress = QProgressBar()
            self.calibration_progress.setFormat("%v / %m örnek")
            calibration_layout.addWidget(self.calibration_progress)
            self.calibration_button = QPushButton("Profili Üret ve Otomatik Kabulü Aç")
            self.calibration_button.setEnabled(False)
            self.calibration_button.clicked.connect(self.build_calibration_profile)
            calibration_layout.addWidget(self.calibration_button)
            editor_layout.addWidget(calibration_box)

            layout.addWidget(editor, 1)
            self._enable_row_menu(self.review_table)
            self._set_empty_hint(
                self.review_table,
                "İncelenecek kayıt yok. OCR ya da sesli kayıt sonrası kanıtı zayıf "
                "kalan alanlar buraya düşer.",
            )
            self.tabs.addTab(page, "Kitap Bilgisi İncelemesi")

        @staticmethod
        def _book_source(book: BookRecord) -> str:
            if any((copy.source_fingerprint or "").startswith("voice:") for copy in book.copies):
                return "Ses"
            return "Foto"

        def refresh_review(self) -> None:
            books = self.catalog.list_books(review_status="review", limit=10_000)
            self._fill_table(
                self.review_table,
                [
                    [
                        book.edition_id,
                        book.title,
                        self._authors(book),
                        book.publisher,
                        self._book_source(book),
                    ]
                    for book in books
                ],
                first_column_data=[book.edition_id for book in books],
            )
            current_category = self.review_category.currentText()
            self.review_category.blockSignals(True)
            self.review_category.clear()
            self.review_category.addItem("")
            for value in self.catalog.list_distinct_values("category"):
                self.review_category.addItem(value)
            self.review_category.setCurrentText(current_category)
            self.review_category.blockSignals(False)
            self.refresh_calibration_status()

        def refresh_calibration_status(self) -> None:
            """Show how close the reviewed fields are to enabling auto-accept."""

            minimum = ConfidenceCalibrationProfile.__dataclass_fields__["minimum_samples"].default
            # Only the count is needed here, and this runs on the UI thread after
            # every saved review. Building label objects for a catalogue with
            # hundreds of thousands of observations would freeze the very
            # keyboard flow the review screen exists to make fast.
            total = self.database.review_label_count()
            self.calibration_progress.setRange(0, minimum)
            self.calibration_progress.setValue(min(total, minimum))
            profile = self._active_calibration_profile()
            if profile is not None and profile.trusted:
                self.calibration_status.setText(
                    f"Otomatik kabul açık. Profil “{profile.version}”, "
                    f"{profile.total_samples} örnekle üretildi."
                )
                self.calibration_button.setEnabled(total > profile.total_samples)
                self.calibration_button.setText("Profili Yeniden Üret")
                return
            remaining = max(0, minimum - total)
            self.calibration_status.setText(
                f"Otomatik kabul kapalı: her alan incelemeye düşüyor. "
                f"İncelenen alanlardan {total} kalibrasyon örneği çıktı; "
                f"profili üretmek için {remaining} örnek daha gerekiyor."
                if remaining
                else (
                    f"{total} örnek hazır. Profili üretince kanıtı güçlü alanlar "
                    "otomatik kabul edilmeye başlar."
                )
            )
            self.calibration_button.setEnabled(remaining == 0)
            self.calibration_button.setText("Profili Üret ve Otomatik Kabulü Aç")

        def _active_calibration_profile(self) -> ConfidenceCalibrationProfile | None:
            from kitapkatalog.model_manager import ModelManager

            with suppress(Exception):
                return ModelManager(self.paths).optional_calibration_profile()
            return None

        def build_calibration_profile(self) -> None:
            """Fit a profile from this catalogue's own review decisions."""

            from kitapkatalog.model_manager import ModelManager

            destination = ModelManager(self.paths).local_calibration_path

            def work() -> ConfidenceCalibrationProfile:
                labels = [ReviewLabel(**row) for row in self.database.review_labels()]
                profile = fit_isotonic_profile(
                    samples_from_reviews(labels),
                    version=f"inceleme-{len(labels)}",
                )
                profile.save(destination)
                return profile

            def done(profile: ConfidenceCalibrationProfile) -> None:
                self.statusBar().showMessage(
                    f"Kalibrasyon profili yazıldı: {profile.total_samples} örnek. "
                    "Otomatik kabul bir sonraki OCR koşumunda devreye girer.",
                    10_000,
                )
                self.refresh_calibration_status()

            self.calibration_button.setEnabled(False)
            self._background(work, done, message="Kalibrasyon profili üretiliyor…")

        def _review_selected(self) -> None:
            items = self.review_table.selectedItems()
            if not items:
                return
            edition_id = int(
                self.review_table.item(items[0].row(), 0).data(Qt.ItemDataRole.UserRole)
            )
            book = self.catalog.get_book(edition_id)
            if book is None:
                return
            self._selected_review_id = edition_id
            self.review_title.setText(book.title)
            self.review_subtitle.setText(book.subtitle or "")
            self.review_publisher.setText(book.publisher or "")
            self.review_category.setCurrentText(book.category or "")
            self.review_year.setText(book.publication_date or "")
            self.review_pages.setValue(book.page_count or 0)
            self.review_language.setText(book.language or "")
            self._review_loaded_location = self._book_locations(book)
            self.review_location.setText(self._review_loaded_location)
            self.review_blurb.setPlainText(book.blurb or "")
            self._show_voice_evidence(book)
            self._set_preview(self.front_preview, book.front_path, "Ön kapak")
            self._set_preview(self.front_inside_preview, book.front_inside_path, "Ön iç kapak")
            self._set_preview(self.back_inside_preview, book.back_inside_path, "Arka iç kapak")
            self._set_preview(self.back_preview, book.back_path, "Arka kapak")

        @staticmethod
        def _set_preview(label: QLabel, path: str | None, fallback: str) -> None:
            if not path or not Path(path).is_file():
                label.setPixmap(QPixmap())
                label.setText(fallback)
                return
            pixmap = QPixmap(path)
            if pixmap.isNull():
                label.setText(fallback)
                return
            label.setPixmap(
                pixmap.scaled(
                    label.size(),
                    Qt.AspectRatioMode.KeepAspectRatio,
                    Qt.TransformationMode.SmoothTransformation,
                )
            )

        def _show_voice_evidence(self, book: BookRecord) -> None:
            is_voice = self._book_source(book) == "Ses"
            self.review_transcript.setVisible(is_voice)
            self.review_play_button.setVisible(is_voice)
            if not is_voice:
                self.review_transcript.clear()
                return
            transcript = ""
            item = self.database.get_voice_item_by_edition(book.edition_id)
            if item is not None:
                with suppress(Exception):
                    import json as _json

                    transcript = " ".join(
                        str(entry.get("text", "")).strip()
                        for entry in _json.loads(item.transcript_json)
                    )
            if not transcript:
                sidecar = self._voice_sidecar_for(book)
                if sidecar is not None:
                    with suppress(Exception):
                        import json as _json

                        transcript = _json.loads(sidecar.read_text()).get("transcript", "")
            self.review_transcript.setPlainText(transcript or "Transkript bulunamadı")

        def _voice_sidecar_for(self, book: BookRecord) -> Path | None:
            for copy in book.copies:
                fingerprint = copy.source_fingerprint or ""
                parts = fingerprint.split(":")
                # Canlı mod parmak izi: voice:<wav_sha256>:cN
                if len(parts) == 3 and parts[0] == "voice":
                    candidate = self.paths.voice_assets / "utterances" / f"{parts[1]}.json"
                    if candidate.is_file():
                        return candidate
            return None

        def _voice_audio_for(self, book: BookRecord) -> Path | None:
            """Kanıt sesini çöz: canlı söylem WAV'ı ya da toplu kayıt kesiti."""

            for copy in book.copies:
                fingerprint = copy.source_fingerprint or ""
                parts = fingerprint.split(":")
                if len(parts) == 3 and parts[0] == "voice":
                    candidate = self.paths.voice_assets / "utterances" / f"{parts[1]}.wav"
                    if candidate.is_file():
                        return candidate
            item = self.database.get_voice_item_by_edition(book.edition_id)
            if item is None:
                return None
            job = self.database.get_voice_job(item.job_id)
            if job is None or not job.canonical_wav_path:
                return None
            wav = Path(job.canonical_wav_path)
            if not wav.is_file():
                return None
            from kitapkatalog.audio import slice_wav

            preview_dir = self.paths.derivatives / "voice-preview"
            safe_key = item.item_key.replace(":", "-")
            target = preview_dir / f"{item.job_id}-{safe_key}.wav"
            if not target.is_file():
                slice_wav(
                    wav,
                    target,
                    start_sample=item.start_sample,
                    end_sample=max(item.end_sample, item.start_sample + 1600),
                )
            return target

        def play_review_audio(self) -> None:
            if self._selected_review_id is None:
                return
            book = self.catalog.get_book(self._selected_review_id)
            if book is None:
                return
            try:
                audio_path = self._voice_audio_for(book)
            except Exception as exc:
                self._show_error(str(exc))
                return
            if audio_path is None:
                self.statusBar().showMessage("Kanıt sesi bulunamadı", 4000)
                return
            try:
                from PySide6.QtCore import QUrl
                from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
            except ImportError:
                self.statusBar().showMessage("Ses çalma için QtMultimedia gerekli", 4000)
                return
            if getattr(self, "_review_player", None) is None:
                self._review_audio_output = QAudioOutput(self)
                self._review_player = QMediaPlayer(self)
                self._review_player.setAudioOutput(self._review_audio_output)
            self._review_player.stop()
            self._review_player.setSource(QUrl.fromLocalFile(str(audio_path)))
            self._review_player.play()
            self.statusBar().showMessage("Kanıt sesi çalınıyor…", 3000)

        def save_review_and_advance(self) -> None:
            """Confirm this record and open the next one still awaiting review.

            Reviewing a large catalogue means hundreds of records in a row.
            Saving used to just clear the selection, so every record cost a trip
            back to the table with the mouse.
            """

            if self._selected_review_id is None:
                self.statusBar().showMessage("İncelenecek seçili kayıt yok", 4000)
                return
            row = self.review_table.currentRow()
            self.save_review()
            if self.review_table.rowCount() == 0:
                self.statusBar().showMessage("İnceleme kuyruğu boşaldı", 5000)
                return
            # The saved row leaves the queue, so the same index is now the next
            # record; at the end of the list, wrap back to the last remaining one.
            following = min(max(row, 0), self.review_table.rowCount() - 1)
            self.review_table.selectRow(following)
            self.review_title.setFocus()

        def save_review(self) -> None:
            if self._selected_review_id is None:
                return
            try:
                location = self.review_location.text().strip()
                if location != self._review_loaded_location:
                    self.catalog.set_location(self._selected_review_id, location or None)
                self.catalog.update_book(
                    self._selected_review_id,
                    {
                        "title": self.review_title.text(),
                        "subtitle": self.review_subtitle.text() or None,
                        "publisher": self.review_publisher.text() or None,
                        "category": self.review_category.currentText() or None,
                        "publication_date": self.review_year.text() or None,
                        "page_count": self.review_pages.value() or None,
                        "language": self.review_language.text() or None,
                        "blurb": self.review_blurb.toPlainText() or None,
                        "review_status": "completed",
                    },
                    user_edit=True,
                )
            except (KeyError, ValueError, RuntimeError) as exc:
                self._show_error(str(exc))
                return
            self._selected_review_id = None
            self.refresh_review()
            self.refresh_library()
            self.statusBar().showMessage("Kayıt onaylandı", 3000)

        # --------------------------------------------------------------
        # Export

        def _build_export_tab(self) -> None:
            page = QWidget()
            layout = QVBoxLayout(page)
            form = QFormLayout()
            self.export_format = QComboBox()
            for item in ExportFormat:
                self.export_format.addItem(item.value.upper(), item.value)
            self.export_path = QLineEdit()
            browse = QPushButton("Hedef Seç")
            browse.clicked.connect(self.choose_export_path)
            path_row = QHBoxLayout()
            path_row.addWidget(self.export_path, 1)
            path_row.addWidget(browse)
            self.completed_only = QCheckBox("Yalnız tamamlanan/incelemeye hazır kayıtlar")
            self.completed_only.setChecked(True)
            form.addRow("Biçim", self.export_format)
            form.addRow("Hedef", path_row)
            form.addRow("", self.completed_only)
            layout.addLayout(form)
            export_button = QPushButton("Dışa Aktar")
            export_button.clicked.connect(self.start_export)
            layout.addWidget(export_button)
            self.export_progress = QProgressBar()
            self.export_progress.setRange(0, 1)
            self.export_progress.setValue(0)
            layout.addWidget(self.export_progress)
            self.export_result = QLabel(
                "XLSX: 9 sayfalı ayrıntılı çalışma kitabı (Özet, Kitaplar, "
                "Katkıda Bulunanlar, Tanımlayıcılar, Nüshalar/Dolap, İstatistik, "
                "Ayrıntılı Alanlar, İnceleme, Hatalar). CSV/JSON/JSONL/Markdown "
                "çıktıları da dolap ve nüsha bilgisi dahil tüm alanları içerir."
            )
            self.export_result.setWordWrap(True)
            layout.addWidget(self.export_result)
            backup_group = QGroupBox("Taşınabilir yedek")
            backup_layout = QHBoxLayout(backup_group)
            self.backup_covers = QCheckBox("Yönetilen kapakları dahil et")
            backup_button = QPushButton(".kitaparsiv Yedeği Oluştur")
            backup_button.clicked.connect(self.start_backup)
            backup_layout.addWidget(self.backup_covers)
            backup_layout.addWidget(backup_button)
            backup_layout.addStretch(1)
            layout.addWidget(backup_group)
            layout.addStretch(1)
            self.tabs.addTab(page, "Dışa Aktarım")

        def choose_export_path(self) -> None:
            format_name = str(self.export_format.currentData())
            if format_name == ExportFormat.MARKDOWN.value:
                directory = QFileDialog.getExistingDirectory(self, "Markdown not klasörünü seçin")
                if directory:
                    self.export_path.setText(str(Path(directory) / "KitapKatalog-Notları"))
                return
            extensions = {
                "xlsx": "Excel (*.xlsx)",
                "csv": "CSV (*.csv)",
                "json": "JSON (*.json)",
                "jsonl": "JSON Lines (*.jsonl)",
            }
            path, _filter = QFileDialog.getSaveFileName(
                self, "Dışa aktar", str(self.paths.exports), extensions[format_name]
            )
            if path:
                suffix = f".{format_name}"
                if not path.casefold().endswith(suffix):
                    path += suffix
                self.export_path.setText(path)

        def start_export(self) -> None:
            destination = self.export_path.text().strip()
            if not destination:
                self.choose_export_path()
                destination = self.export_path.text().strip()
            if not destination:
                return
            selected = str(self.export_format.currentData())
            completed = self.completed_only.isChecked()
            self.export_progress.setRange(0, 0)

            def work() -> Any:
                return export_catalog(
                    self.database,
                    destination,
                    format=selected,
                    completed_only=completed,
                )

            def finished(result: Any) -> None:
                self.export_progress.setRange(0, 1)
                self.export_progress.setValue(1)
                self.export_result.setText(
                    f"{result.records:,} kitap dışa aktarıldı:\n{result.path}"
                )
                self.statusBar().showMessage("Dışa aktarım tamamlandı", 5000)

            self._background(work, finished, message="Dışa aktarılıyor…")

        def start_backup(self) -> None:
            destination, _filter = QFileDialog.getSaveFileName(
                self,
                "KitapKatalog yedeğini oluştur",
                str(self.paths.exports / "KitapKatalog.kitaparsiv"),
                "KitapKatalog Yedeği (*.kitaparsiv)",
            )
            if not destination:
                return
            if not destination.casefold().endswith(".kitaparsiv"):
                destination += ".kitaparsiv"
            include_covers = self.backup_covers.isChecked()

            def work() -> Any:
                return create_archive(
                    self.database.path,
                    Path(destination),
                    asset_root=self.paths.assets,
                    cover_paths=(self._managed_cover_paths() if include_covers else ()),
                    include_covers=include_covers,
                )

            def finished(result: Any) -> None:
                self.export_result.setText(
                    f"Yedek oluşturuldu: {result.path}\n"
                    f"Veritabanı: {self._format_bytes(result.database_size)} • "
                    f"Kapak: {result.cover_count:,}"
                )
                self.statusBar().showMessage("Yedek oluşturuldu", 5000)

            self._background(work, finished, message="Yedek oluşturuluyor…")

        # --------------------------------------------------------------
        # Engine/package status

        def _build_engine_tab(self) -> None:
            page = QWidget()
            layout = QVBoxLayout(page)
            label = QLabel(
                "Kitap işlenmeden önce beş OCR motorunun tamamı hazır olmalıdır. "
                "Denetim yalnız yerel dosya ve paketleri kontrol eder."
            )
            label.setWordWrap(True)
            layout.addWidget(label)
            refresh = QPushButton("Motor Durumunu Doğrula")
            refresh.clicked.connect(self.refresh_engines)
            layout.addWidget(refresh)
            self.engine_table = QTableWidget(0, 5)
            self.engine_table.setHorizontalHeaderLabels(
                ("Motor", "Sürüm", "Aile", "Hazır", "Açıklama")
            )
            self.engine_table.setColumnWidth(0, 220)
            self.engine_table.setColumnWidth(1, 130)
            self.engine_table.setColumnWidth(2, 150)
            self.engine_table.setColumnWidth(3, 90)
            self.engine_table.setColumnWidth(4, 500)
            self.engine_table.horizontalHeader().setSectionResizeMode(
                4, QHeaderView.ResizeMode.Stretch
            )
            layout.addWidget(self.engine_table)
            self.tabs.addTab(page, "5 OCR Durumu")

        def refresh_engines(self) -> None:
            def work() -> list[Any]:
                from kitapkatalog.model_manager import ModelManager

                manager = ModelManager(self.paths)
                return [*manager.engine_statuses(), manager.extractor_status()]

            def finished(statuses: list[Any]) -> None:
                self._fill_table(
                    self.engine_table,
                    [
                        [
                            _ENGINE_NAMES.get(status.engine_id, status.engine_id),
                            status.version,
                            status.family,
                            "Hazır" if status.available else "Eksik",
                            "; ".join(status.reasons),
                        ]
                        for status in statuses
                    ],
                )
                self.statusBar().showMessage("Yerel motor denetimi tamamlandı", 3000)

            self._background(work, finished, message="Motorlar doğrulanıyor…")

        # --------------------------------------------------------------
        # İstatistik

        def _build_stats_tab(self) -> None:
            page = QWidget()
            layout = QVBoxLayout(page)
            top = QHBoxLayout()
            self.stats_summary = QLabel("")
            refresh = QPushButton("Yenile")
            refresh.clicked.connect(self.refresh_stats)
            top.addWidget(self.stats_summary, 1)
            top.addWidget(refresh)
            layout.addLayout(top)
            grid = QGridLayout()
            self.stats_tables: dict[str, QTableWidget] = {}
            sections = (
                ("category", "Kategoriye göre"),
                ("language", "Dile göre"),
                ("publisher", "Yayınevine göre"),
                ("review_status", "Duruma göre"),
            )
            for index, (key, title) in enumerate(sections):
                group = QGroupBox(title)
                group_layout = QVBoxLayout(group)
                table = QTableWidget(0, 3)
                table.setHorizontalHeaderLabels(("Değer", "Adet", "%"))
                table.setEditTriggers(QAbstractItemView.EditTrigger.NoEditTriggers)
                table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.Stretch)
                table.setColumnWidth(1, 80)
                table.setColumnWidth(2, 80)
                group_layout.addWidget(table)
                self.stats_tables[key] = table
                grid.addWidget(group, index // 2, index % 2)
            layout.addLayout(grid, 1)
            self._stats_page = page
            self.tabs.addTab(page, "İstatistik")

        def refresh_stats(self) -> None:
            stats = self.catalog.stats()
            self.stats_summary.setText(
                f"{stats['works']:,} eser • {stats['editions']:,} baskı • "
                f"{stats['copies']:,} kopya • {stats['review']:,} incelemede"
            )
            for key, table in self.stats_tables.items():
                distribution = self.catalog.distribution(key)
                total = sum(count for _value, count in distribution) or 1
                rows = [
                    [
                        self._status(value) if key == "review_status" else value,
                        count,
                        f"%{100 * count / total:.1f}",
                    ]
                    for value, count in distribution
                ]
                self._fill_table(table, rows)

        def _tab_changed(self, index: int) -> None:
            if self._restoring_tab_index:
                return
            previous = self._accepted_tab_index
            if previous == 0 and index != previous and self._library_detail_is_dirty():
                if not self._confirm_discarding_library_edits():
                    self._restoring_tab_index = True
                    try:
                        self.tabs.setCurrentIndex(previous)
                    finally:
                        self._restoring_tab_index = False
                    return
                self._discard_library_detail_edits()
            self._accepted_tab_index = index
            if self.tabs.widget(index) is self._stats_page:
                self.refresh_stats()

        def refresh_all(self) -> None:
            self.refresh_library()
            self.refresh_jobs()
            self.refresh_voice_jobs()
            self.refresh_pair_reviews()
            self.refresh_review()
            self.refresh_engines()
            self.refresh_stats()

        def refresh_runtime(self) -> None:
            self.refresh_jobs()
            self.refresh_voice_jobs()
            self.refresh_pair_reviews()

        def closeEvent(self, event: Any) -> None:
            # Cancel means exactly that: keep the window, background timer and
            # process-lifetime application lock alive. Cleanup must only begin
            # after the user explicitly discards the pending edit.
            if not self._confirm_discarding_library_edits():
                event.ignore()
                return
            self._save_window_state()
            self.refresh_timer.stop()
            if self._voice_capture is not None:
                with suppress(Exception):
                    self._voice_capture.cancel()
            if self._voice_batch_scheduler is not None:
                # Toplu işleyici bir sonraki güvenli noktada (chunk/öğe
                # sınırında) dursun; whisper alt süreci onunla kapanır.
                with suppress(Exception):
                    self._voice_batch_scheduler.request_stop()
            if self._voice_session is not None:
                with suppress(Exception):
                    self._voice_session.close()
            self.pool.waitForDone(10_000)
            self._application_context.close()
            super().closeEvent(event)

    # Expose imported QApplication to ``main`` without importing Qt globally.
    KitapKatalogMainWindow._qapplication_class = QApplication
    KitapKatalogMainWindow._new_book_dialog_class = NewBookDialog
    _MAIN_WINDOW_CLASS = KitapKatalogMainWindow
    return KitapKatalogMainWindow


class MainWindow:
    """Lazy constructor compatible with ``MainWindow(database_path)`` callers."""

    def __new__(cls, *args: Any, **kwargs: Any) -> Any:
        return _build_main_window_class()(*args, **kwargs)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kitapkatalog-gui")
    parser.add_argument("--database", default=str(AppPaths.default().database))
    return parser


def main(argv: list[str] | None = None) -> int:
    # Install before PySide or a later model-related import can start a network call.
    install_network_guard()
    args = build_parser().parse_args(argv)
    ensure_qt_plugins_visible()
    try:
        window_class = _build_main_window_class()
    except QtUnavailableError as exc:
        print(f"Hata: {exc}", file=sys.stderr)
        return 2
    application_class = window_class._qapplication_class
    application = application_class.instance() or application_class(sys.argv[:1])
    window = window_class(args.database)
    window.show()
    return int(application.exec())


if __name__ == "__main__":
    raise SystemExit(main())


__all__ = ["MainWindow", "QtUnavailableError", "build_parser", "main"]
