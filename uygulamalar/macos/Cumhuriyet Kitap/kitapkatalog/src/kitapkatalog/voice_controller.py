"""Canlı mikrofonla kitap kaydı: oturum çekirdeği + Qt ses yakalama köprüsü.

İki katman vardır ve bilinçle ayrılmıştır:

* ``VoiceSession`` — Qt'ye hiç dokunmayan, testte sahte whisper ile sürülebilen
  çekirdek: söylem WAV'ı → transkript → alan iddiaları → (onayla/otomatik)
  idempotent katalog yazımı. Whisper sunucusu oturum boyunca AÇIK tutulur
  (model yüklemesi pahalıdır); ``close()`` süreci grup olarak kapatır.
* ``build_voice_capture_class()`` — yalnız GUI'de gereken QtMultimedia
  yakalayıcısını tembel kurar (gui.py'daki lazy-PySide6 deseni). Ham PCM
  doğrudan 16 kHz/mono/s16 istenir; codec bağımlılığı yoktur.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import threading
from collections.abc import Callable
from dataclasses import dataclass
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths
from kitapkatalog.database import Database
from kitapkatalog.domain import SearchFilters
from kitapkatalog.settings import AppSettings
from kitapkatalog.voice_extractor import (
    FieldClaim,
    VoiceFieldExtractor,
    VoiceParseResult,
)
from kitapkatalog.voice_protocol import (
    BookUtterance,
    extract_field_spans,
    filter_hallucinations,
    fold_text,
    isbn_candidates_from_span,
)
from kitapkatalog.voice_refine import FieldSuggestion, alias_suggestions
from kitapkatalog.voice_scheduler import persist_parse_result

_TITLE_SIMILARITY = 0.85
_AUTHOR_SIMILARITY = 0.70
_CATALOG_TITLE_MIN_SIMILARITY = 0.60
_CATALOG_TITLE_MAX_SIMILARITY = 0.85
_CATALOG_AUTHOR_MIN_SIMILARITY = 0.75
_CATALOG_CONTRIBUTOR_SCAN_LIMIT = 500
_MAX_SUGGESTIONS_PER_FIELD = 3
_MAX_AUTO_COPIES = 5
_MAX_FORM_COPIES = 1_000


def _top_suggestions_per_field(
    suggestions: list[FieldSuggestion], *, limit: int
) -> list[FieldSuggestion]:
    grouped: dict[str, list[FieldSuggestion]] = {}
    for item in suggestions:
        grouped.setdefault(item.field_path, []).append(item)
    capped: list[FieldSuggestion] = []
    for items in grouped.values():
        items.sort(key=lambda entry: entry.score, reverse=True)
        capped.extend(items[:limit])
    return capped


class VoiceCaptureError(RuntimeError):
    pass


@dataclass(frozen=True, slots=True)
class PendingUtterance:
    wav_path: Path
    wav_sha256: str
    transcript: str
    result_json: str

    @property
    def result(self) -> VoiceParseResult:
        return VoiceParseResult.from_json(self.result_json)


@dataclass(frozen=True, slots=True)
class SimilarBook:
    edition_id: int
    title: str
    authors: str
    title_score: float
    author_score: float


class VoiceSession:
    """Canlı modun Qt'suz çekirdeği; GUI bunu arka plan işçisinde çağırır."""

    def __init__(
        self,
        database: Database,
        paths: AppPaths,
        *,
        whisper_client_factory: Callable[[], Any] | None = None,
        qwen_client_factory: Callable[[], Any] | None = None,
    ) -> None:
        self.database = database
        self.paths = paths
        self.catalog = Catalog(database)
        self._whisper_factory = whisper_client_factory
        self._qwen_factory = qwen_client_factory
        self._whisper: Any | None = None
        self._whisper_lock = threading.Lock()

    # ------------------------------------------------------------- whisper

    def _ensure_whisper(self) -> Any:
        with self._whisper_lock:
            return self._ensure_whisper_locked()

    def _ensure_whisper_locked(self) -> Any:
        # Kilitsiz çift başlatma, uygulama kapansa da yaşayan (kendi süreç
        # grubunda) yetim whisper-server bırakırdı; model yüklemesi uzun
        # sürdüğü için ilk iki söylem pekâlâ yarışabilir.
        if self._whisper is None:
            if self._whisper_factory is None:
                from kitapkatalog.whisper_runtime import (
                    ManagedWhisperClient,
                    default_model_path,
                    default_server_executable,
                )

                language = AppSettings(self.database).voice_language
                self._whisper_factory = lambda: ManagedWhisperClient(
                    executable=default_server_executable(self.paths),
                    model_path=default_model_path(self.paths),
                    language=language,
                )
            client = self._whisper_factory()
            self._whisper = client.__enter__()
        return self._whisper

    def close(self) -> None:
        if self._whisper is not None:
            with_exit = self._whisper
            self._whisper = None
            with_exit.__exit__(None, None, None)

    # ------------------------------------------------------------- analiz

    def analyze(self, wav_path: str | Path) -> PendingUtterance:
        source = Path(wav_path)
        settings = AppSettings(self.database)
        whisper = self._ensure_whisper()
        prompt = self._transcription_prompt(settings)
        segments = filter_hallucinations(whisper.transcribe(source, prompt=prompt))
        utterance = BookUtterance(
            ordinal=0,
            start_seconds=segments[0].start_seconds if segments else 0.0,
            end_seconds=segments[-1].end_seconds if segments else 0.0,
            segments=segments,
        )
        result = VoiceFieldExtractor(qwen_client_factory=self._qwen_factory).parse(utterance)
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        stored = self._store_utterance(source, digest)
        if settings.voice_second_pass:
            self._refine(result, utterance, stored, settings, prompt)
        self._apply_offline_suggestions(result)
        return PendingUtterance(
            wav_path=stored,
            wav_sha256=digest,
            transcript=utterance.text,
            result_json=result.to_json(),
        )

    def _apply_offline_suggestions(self, result: VoiceParseResult) -> None:
        """Whisper gerektirmeyen öneri kaynakları: sözlük + katalog benzerliği.

        ``voice_second_pass`` kapalıyken de çalışır (ikinci bir whisper çağrısı
        gerekmez); iki geçiş de aynı ``suggestions`` listesine, alan başına en
        iyi ``_MAX_SUGGESTIONS_PER_FIELD`` öneriyle eklenir.
        """

        aliases = self.database.list_voice_aliases()
        extra = alias_suggestions(aliases, result)
        extra.extend(
            self.catalog_suggestions(
                result.value_of("title") or "", result.value_of("author") or ""
            )
        )
        if not extra:
            return
        capped = _top_suggestions_per_field(extra, limit=_MAX_SUGGESTIONS_PER_FIELD)
        result.suggestions.extend(dataclasses.asdict(item) for item in capped)

    def _transcription_prompt(self, settings: AppSettings) -> str | None:
        if not settings.voice_prompt_bias:
            return None
        from kitapkatalog.voice_prompt import build_transcription_prompt

        return build_transcription_prompt(self.database, extra=settings.voice_prompt_extra)

    def _refine(
        self,
        result: VoiceParseResult,
        utterance: BookUtterance,
        wav_path: Path,
        settings: AppSettings,
        prompt: str | None,
    ) -> None:
        """Öneri katmanı fail-open: whisper başarısız olursa kayıt akışı kesilmez."""

        from kitapkatalog.voice_refine import refine_foreign_fields, refine_missing_title

        language = settings.voice_second_pass_language
        scratch_dir = self.paths.derivatives / "voice-refine"
        suggestions = []
        try:
            whisper = self._ensure_whisper()
            suggestions = refine_foreign_fields(
                whisper,
                wav_path,
                utterance,
                result,
                language=language,
                scratch_dir=scratch_dir,
                prompt=prompt,
            )
        except Exception:
            pass
        if any("Başlık bulunamadı" in reason for reason in result.review_reasons):
            try:
                whole = refine_missing_title(
                    self._ensure_whisper(), wav_path, language=language, prompt=prompt
                )
            except Exception:
                whole = None
            if whole is not None:
                suggestions.append(whole)
        if suggestions:
            result.suggestions.extend(dataclasses.asdict(item) for item in suggestions)

    def transcribe_field(
        self, wav_path: str | Path, field: str, *, language: str, prompt: str | None = None
    ) -> tuple[str, str]:
        """Tek bir alanı hedefleyen kısa yeniden-söyleme kaydını çöz.

        Kayıt/pending durumuna hiç dokunmaz (kanıt sözleşmesi etkilenmez); dönen
        değer forma yalnız kullanıcı onayıyla yazılır. ``extract_field_spans``
        alan anahtar kelimesi bulursa o değeri, bulamazsa tüm transkripti verir
        (kısa kayıtta kullanıcı genelde anahtar kelimeyi söylemeden yanıtlar).
        Döner: ``(değer, tam_transkript)``.
        """

        whisper = self._ensure_whisper()
        segments = filter_hallucinations(
            whisper.transcribe(wav_path, language=language, prompt=prompt)
        )
        text = " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()
        spans = extract_field_spans(text)
        match = next((span for span in spans if span.field == field), None)
        return (match.raw_value if match is not None else text), text

    def _store_utterance(self, source: Path, digest: str) -> Path:
        utterances = self.paths.voice_assets / "utterances"
        utterances.mkdir(parents=True, exist_ok=True)
        target = utterances / f"{digest}.wav"
        if not target.exists():
            source.replace(target)
        elif source != target:
            source.unlink(missing_ok=True)
        return target

    # ---------------------------------------------------------- benzerlik

    def similar_books(self, title: str, authors: str) -> list[SimilarBook]:
        """ISBN'siz kayıtlar için başlık+yazar benzerlik adayları (FTS + oran)."""

        if not title.strip():
            return []
        candidates: dict[int, SimilarBook] = {}
        for query in (title, f"{title} {authors}".strip()):
            try:
                page = self.catalog.search(query, filters=SearchFilters(), limit=5)
            except Exception:
                continue
            for book in page.items:
                book_authors = "; ".join(
                    item.name for item in book.contributors if item.role == "author"
                )
                title_score = SequenceMatcher(None, fold_text(title), fold_text(book.title)).ratio()
                author_score = SequenceMatcher(
                    None, fold_text(authors), fold_text(book_authors)
                ).ratio()
                if title_score >= _TITLE_SIMILARITY and author_score >= _AUTHOR_SIMILARITY:
                    candidates[book.edition_id] = SimilarBook(
                        edition_id=book.edition_id,
                        title=book.title,
                        authors=book_authors,
                        title_score=title_score,
                        author_score=author_score,
                    )
        return sorted(
            candidates.values(),
            key=lambda item: (item.title_score, item.author_score),
            reverse=True,
        )

    def catalog_suggestions(self, title: str, authors: str) -> list[FieldSuggestion]:
        """Whisper'sız kanıt: mevcut katalogla fonetik yakınlık.

        Başlık: arama sonuçlarında ``[0.60, 0.85)`` bandına düşen adaylar (0.85+
        zaten ``similar_books``'ta mükerrer uyarısı/otomatik-kayıt engeli olarak
        ele alınır — burada tekrar önerilmez). Yazar: en sık geçen katkı
        sağlayanlar listesinde ``SequenceMatcher >= 0.75``.
        """

        suggestions: list[FieldSuggestion] = []
        title = title.strip()
        if title:
            try:
                page = self.catalog.search(title, filters=SearchFilters(), limit=5)
            except Exception:
                page = None
            for book in page.items if page is not None else ():
                score = SequenceMatcher(None, fold_text(title), fold_text(book.title)).ratio()
                if _CATALOG_TITLE_MIN_SIMILARITY <= score < _CATALOG_TITLE_MAX_SIMILARITY:
                    suggestions.append(
                        FieldSuggestion(
                            field_path="title",
                            value=book.title,
                            origin="catalog",
                            language="",
                            score=score,
                        )
                    )
        authors = authors.strip()
        if authors:
            for candidate in self.catalog.top_contributors(
                role="author", limit=_CATALOG_CONTRIBUTOR_SCAN_LIMIT
            ):
                score = SequenceMatcher(None, fold_text(authors), fold_text(candidate)).ratio()
                if score >= _CATALOG_AUTHOR_MIN_SIMILARITY:
                    suggestions.append(
                        FieldSuggestion(
                            field_path="author",
                            value=candidate,
                            origin="catalog",
                            language="",
                            score=score,
                        )
                    )
        return suggestions

    # ------------------------------------------------------------- kaydet

    @staticmethod
    def form_result(values: dict[str, str], *, copy_count: int) -> VoiceParseResult:
        """Formdaki (kullanıcı onaylı) değerlerden iddia kümesi kur.

        Form tek gerçek kaynaktır: kullanıcı ne görüyorsa o yazılır; ISBN yine
        de sağlamadan geçmek zorundadır (uydurma/yanlış aktarım yazılmaz).
        """

        parsed_copy_count = int(copy_count)
        if not 1 <= parsed_copy_count <= _MAX_FORM_COPIES:
            raise ValueError(f"Nüsha sayısı 1 ile {_MAX_FORM_COPIES} arasında olmalıdır")
        result = VoiceParseResult(copy_count=parsed_copy_count)
        isbn_raw = (values.get("isbn") or "").strip()
        if isbn_raw:
            candidates = isbn_candidates_from_span(isbn_raw)
            if len(candidates) == 1:
                result.isbn = candidates[0]
            else:
                result.review_reasons.append(f"ISBN sağlaması geçmedi: {isbn_raw!r}")
        for field_path in (
            "title",
            "author",
            "publisher",
            "publication_date",
            "page_count",
            "language",
            "category",
            "location",
        ):
            value = (values.get(field_path) or "").strip()
            if not value:
                continue
            result.claims.append(
                FieldClaim(
                    field_path=field_path,
                    value=value,
                    raw_text=value,
                    start_char=0,
                    end_char=0,
                    source="form",
                )
            )
        if result.value_of("title") is None:
            result.review_reasons.append("Başlık bulunamadı")
        return result

    def save(
        self,
        pending: PendingUtterance,
        result: VoiceParseResult,
        *,
        approve: bool,
        merge_into_edition: int | None = None,
    ) -> int:
        fingerprint_base = f"voice:{pending.wav_sha256}"
        with self.database.transaction(immediate=True):
            if merge_into_edition is not None:
                from kitapkatalog.domain import CopyInput

                location = result.value_of("location")
                for copy_number in range(1, result.copy_count + 1):
                    self.catalog.add_copy(
                        merge_into_edition,
                        CopyInput(
                            source_fingerprint=f"{fingerprint_base}:c{copy_number}",
                            location=location,
                            notes="sesli kayıt (adet artırma)",
                        ),
                    )
                edition_id = merge_into_edition
            else:
                edition_id = persist_parse_result(
                    self.catalog, result, fingerprint_base=fingerprint_base
                )
            if approve:
                self.catalog.update_book(
                    edition_id, {"review_status": "completed"}, user_edit=True
                )
        sidecar = pending.wav_path.with_suffix(".json")
        sidecar.write_text(
            json.dumps(
                {
                    "transcript": pending.transcript,
                    "result": json.loads(result.to_json()),
                    "edition_id": edition_id,
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return edition_id

    def auto_save_allowed(self, result: VoiceParseResult, similar: list[SimilarBook]) -> bool:
        """Deterministik otomatik-kayıt kapısı (sayısal 'güven' eşiği YOK).

        Şartlar: sağlaması geçen TEK ISBN, kural katmanından gelen başlık ve
        yazar, hiçbir inceleme nedeni ve benzerlik uyarısı yok, adet küçük.
        """

        if result.review_reasons or result.isbn is None or similar or result.suggestions:
            return False
        if result.copy_count > _MAX_AUTO_COPIES:
            return False
        for field_path in ("title", "author"):
            claim = next(
                (item for item in result.claims if item.field_path == field_path),
                None,
            )
            if claim is None or claim.source != "rule" or not claim.value.strip():
                return False
        return True


def build_voice_capture_class() -> type:
    """QtMultimedia tabanlı yakalayıcıyı tembel kur (yalnız GUI yolu).

    Ham PCM 16 kHz/mono/Int16 istenir ve doğrudan kanonik WAV yazılır; sistem
    codec'lerine bağımlılık yoktur. 1,5 sn sessizlik otomatik durdurması
    RMS üzerinden hesaplanır.
    """

    try:
        from PySide6.QtCore import QObject, Signal
        from PySide6.QtMultimedia import (
            QAudioFormat,
            QAudioSource,
            QMediaDevices,
        )
    except ImportError as error:  # pragma: no cover - ui extra yoksa
        raise VoiceCaptureError(
            "Mikrofon yakalama için PySide6 (kitapkatalog[ui]) gerekli"
        ) from error

    import uuid
    import wave

    class VoiceCapture(QObject):
        levelChanged = Signal(float)
        finished = Signal(str)  # geçici kanonik WAV yolu
        errorOccurred = Signal(str)

        MIN_UTTERANCE_SECONDS = 0.4

        def __init__(self, scratch_dir: Path, parent: QObject | None = None):
            super().__init__(parent)
            self.scratch_dir = Path(scratch_dir)
            self.auto_stop_enabled = False
            self.silence_threshold = 0.010
            self.auto_stop_ms = 1500.0
            self._source: QAudioSource | None = None
            self._io = None
            self._buffer = bytearray()
            self._silent_ms = 0.0
            self._speech_seen = False

        @staticmethod
        def input_devices() -> list[tuple[int, str]]:
            return [
                (index, device.description())
                for index, device in enumerate(QMediaDevices.audioInputs())
            ]

        @staticmethod
        def permission_status() -> str:
            try:
                from PySide6.QtCore import QMicrophonePermission
                from PySide6.QtWidgets import QApplication
            except ImportError:
                return "bilinmiyor"
            application = QApplication.instance()
            if application is None or not hasattr(application, "checkPermission"):
                return "bilinmiyor"
            from PySide6.QtCore import Qt

            status = application.checkPermission(QMicrophonePermission())
            return {
                Qt.PermissionStatus.Granted: "verildi",
                Qt.PermissionStatus.Denied: "reddedildi",
            }.get(status, "sorulmadı")

        @property
        def recording(self) -> bool:
            return self._source is not None

        def start(self, device_index: int = -1) -> None:
            if self._source is not None:
                return
            devices = QMediaDevices.audioInputs()
            if not devices:
                self.errorOccurred.emit("Ses giriş aygıtı bulunamadı")
                return
            device = (
                devices[device_index]
                if 0 <= device_index < len(devices)
                else QMediaDevices.defaultAudioInput()
            )
            audio_format = QAudioFormat()
            audio_format.setSampleRate(WAV_SAMPLE_RATE)
            audio_format.setChannelCount(1)
            audio_format.setSampleFormat(QAudioFormat.SampleFormat.Int16)
            if not device.isFormatSupported(audio_format):
                self.errorOccurred.emit("Aygıt 16 kHz/mono/16-bit yakalamayı desteklemiyor")
                return
            self._buffer.clear()
            self._silent_ms = 0.0
            self._speech_seen = False
            self._source = QAudioSource(device, audio_format, self)
            self._io = self._source.start()
            if self._io is None:
                self._source = None
                self.errorOccurred.emit("Mikrofon açılamadı (izin reddedilmiş olabilir)")
                return
            self._io.readyRead.connect(self._drain)

        def _drain(self) -> None:
            if self._io is None:
                return
            data = bytes(self._io.readAll().data())
            if not data:
                return
            self._buffer.extend(data)
            level = _RmsMeter.rms(data)
            self.levelChanged.emit(level)
            elapsed_ms = (len(data) / 2) / WAV_SAMPLE_RATE * 1000.0
            if level >= self.silence_threshold:
                self._speech_seen = True
                self._silent_ms = 0.0
            else:
                self._silent_ms += elapsed_ms
            if (
                self.auto_stop_enabled
                and self._speech_seen
                and self._silent_ms >= self.auto_stop_ms
            ):
                self.stop()

        def _teardown(self) -> None:
            if self._io is not None:
                from contextlib import suppress as _suppress

                with_io = self._io
                self._io = None
                with _suppress(RuntimeError, TypeError):
                    with_io.readyRead.disconnect(self._drain)
            if self._source is not None:
                source = self._source
                self._source = None
                source.stop()

        def stop(self) -> None:
            if self._source is None:
                return
            self._teardown()
            frame_count = len(self._buffer) // 2
            if frame_count < self.MIN_UTTERANCE_SECONDS * WAV_SAMPLE_RATE:
                self._buffer.clear()
                self.errorOccurred.emit("Kayıt çok kısa; kitap bilgisini söyleyip tekrar deneyin")
                return
            self.scratch_dir.mkdir(parents=True, exist_ok=True)
            target = self.scratch_dir / f"soylem-{uuid.uuid4().hex}.wav"
            with wave.open(str(target), "wb") as writer:
                writer.setnchannels(1)
                writer.setsampwidth(2)
                writer.setframerate(WAV_SAMPLE_RATE)
                writer.writeframes(bytes(self._buffer))
            self._buffer.clear()
            self.finished.emit(str(target))

        def cancel(self) -> None:
            self._teardown()
            self._buffer.clear()

    return VoiceCapture


class _RmsMeter:
    """Saf Python RMS ölçer; QtMultimedia geri çağrısında kullanılır."""

    @staticmethod
    def rms(chunk: bytes) -> float:
        if len(chunk) < 2:
            return 0.0
        total = 0
        count = len(chunk) // 2
        for index in range(0, count * 2, 2):
            sample = int.from_bytes(chunk[index : index + 2], "little", signed=True)
            total += sample * sample
        return (total / count) ** 0.5 / 32768.0
