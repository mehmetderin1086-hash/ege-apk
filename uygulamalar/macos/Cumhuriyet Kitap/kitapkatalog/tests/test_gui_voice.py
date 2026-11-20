from __future__ import annotations

import os
import wave
from array import array
from pathlib import Path

import pytest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

pytest.importorskip("PySide6")

from PySide6.QtCore import QObject, Signal
from PySide6.QtWidgets import QApplication
from test_voice_scheduler import FakeWhisper

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.domain import TranscriptSegment
from kitapkatalog.gui import MainWindow
from kitapkatalog.voice_controller import VoiceSession


@pytest.fixture(scope="module")
def application() -> QApplication:
    return QApplication.instance() or QApplication([])


class FakeCapture(QObject):
    levelChanged = Signal(float)
    finished = Signal(str)
    errorOccurred = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.recording = False
        self.auto_stop_enabled = False
        self.next_wav: str | None = None

    @staticmethod
    def input_devices() -> list[tuple[int, str]]:
        return [(0, "Sahte Mikrofon")]

    @staticmethod
    def permission_status() -> str:
        return "verildi"

    def start(self, device_index: int = -1) -> None:
        self.recording = True

    def stop(self) -> None:
        self.recording = False
        if self.next_wav:
            self.finished.emit(self.next_wav)

    def cancel(self) -> None:
        self.recording = False


def _wav(path: Path, seconds: float = 1.0) -> Path:
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(WAV_SAMPLE_RATE)
        writer.writeframes((array("h", [64]) * int(seconds * WAV_SAMPLE_RATE)).tobytes())
    return path


_SEGMENTS = (
    TranscriptSegment(
        start_seconds=0.0,
        end_seconds=12.0,
        text=(
            "ISBN dokuz yedi sekiz dokuz yedi beş sıfır yedi bir sekiz beş üç üç "
            "başlık Kar yazar Orhan Pamuk yayınevi İletişim kategori roman "
            "yıl iki bin iki üç adet"
        ),
        avg_logprob=-0.1,
    ),
)


@pytest.fixture()
def window(tmp_path: Path, application: QApplication):
    holder: dict[str, object] = {}
    capture = FakeCapture()

    def session_factory() -> VoiceSession:
        return VoiceSession(
            holder["database"],
            holder["paths"],
            whisper_client_factory=lambda: FakeWhisper([_SEGMENTS]),
        )

    built = MainWindow(
        str(tmp_path / "veri" / "catalog.sqlite3"),
        voice_session_factory=session_factory,
        voice_capture_factory=lambda: capture,
    )
    holder["database"] = built.database
    holder["paths"] = built.paths
    built._test_capture = capture
    yield built
    built.pool.waitForDone(5_000)
    built.close()
    application.processEvents()


def test_voice_tab_exists_with_form_and_batch_table(window) -> None:
    labels = [window.tabs.tabText(i) for i in range(window.tabs.count())]
    assert "Sesli Kayıt" in labels
    assert window.voice_jobs_table.columnCount() == 8
    assert window.voice_copies.value() == 1


def test_capture_analyze_fills_form(window, qtbot, tmp_path: Path) -> None:
    capture = window._test_capture
    capture.next_wav = str(_wav(tmp_path / "soylem.wav"))

    window.toggle_voice_recording()
    assert capture.recording
    window.toggle_voice_recording()  # durdur -> finished sinyali -> analiz

    qtbot.waitUntil(lambda: window.voice_title.text() == "Kar", timeout=5000)
    assert window.voice_author.text() == "Orhan Pamuk"
    assert window.voice_publisher.text() == "İletişim"
    assert window.voice_isbn.text() == "9789750718533"
    assert window.voice_year.text() == "2002"
    assert window.voice_category.currentText() == "roman"
    assert window.voice_copies.value() == 3
    assert "Kar" in window.voice_transcript.toPlainText()


def test_save_writes_edition_with_copies_and_approves(window, qtbot, tmp_path: Path) -> None:
    capture = window._test_capture
    capture.next_wav = str(_wav(tmp_path / "soylem.wav"))
    window.toggle_voice_recording()
    window.toggle_voice_recording()
    qtbot.waitUntil(lambda: window.voice_title.text() == "Kar", timeout=5000)

    window.save_voice_current()
    qtbot.waitUntil(
        lambda: window.database.fetchone("SELECT COUNT(*) AS c FROM edition")["c"] == 1,
        timeout=5000,
    )
    qtbot.waitUntil(lambda: window._voice_pending is None, timeout=5000)
    row = window.database.fetchone("SELECT id, review_status FROM edition")
    book = window.catalog.get_book(int(row["id"]))
    assert book is not None
    assert book.title == "Kar"
    assert book.category == "roman"
    assert len(book.copies) == 3
    assert book.review_status == "completed"  # Enter/Kaydet bilinçli onaydır
    # Söylem WAV'ı kanıt olarak taşındı, yanında sidecar json var.
    utterances = list((window.paths.voice_assets / "utterances").glob("*.wav"))
    assert len(utterances) == 1
    assert utterances[0].with_suffix(".json").is_file()


def test_fast_mode_auto_saves_but_keeps_review_status(window, qtbot, tmp_path: Path) -> None:
    window.voice_fast_mode.setChecked(True)
    capture = window._test_capture
    capture.next_wav = str(_wav(tmp_path / "soylem.wav"))
    window.toggle_voice_recording()
    window.toggle_voice_recording()

    qtbot.waitUntil(
        lambda: window.database.fetchone("SELECT COUNT(*) AS c FROM edition")["c"] == 1,
        timeout=5000,
    )
    row = window.database.fetchone("SELECT review_status FROM edition")
    assert row["review_status"] == "review"  # güvenlik ağı: incelemede kalır


def test_save_without_pending_shows_guard_message(window) -> None:
    window.voice_title.setText("Elle yazılmış")
    window.save_voice_current()  # ses kanıtı yok -> kayıt yazılmaz
    row = window.database.fetchone("SELECT COUNT(*) AS c FROM edition")
    assert row["c"] == 0


def test_batch_enqueue_and_process_with_fake_whisper(window, qtbot, tmp_path: Path) -> None:
    from kitapkatalog.voice_scheduler import VoiceScheduler

    source = _wav(tmp_path / "raf.wav", seconds=2.0)
    window._voice_batch_scheduler = VoiceScheduler(
        window.database,
        window.paths,
        whisper_client_factory=lambda: FakeWhisper([_SEGMENTS]),
        worker_id="gui-test",
    )
    window._voice_batch_scheduler.enqueue(source)
    window.process_voice_queue()
    qtbot.waitUntil(lambda: not window._voice_batch_running, timeout=10_000)
    window.refresh_voice_jobs()
    assert window.voice_jobs_table.rowCount() == 1
    jobs = window.database.list_voice_jobs()
    assert jobs[0].successful_items == 1

    # Değerlendirme sekmesi: toplu kayıt "Ses" kaynağıyla listelenir.
    window.refresh_review()
    sources = {
        window.review_table.item(row, 4).text() for row in range(window.review_table.rowCount())
    }
    assert sources == {"Ses"}
