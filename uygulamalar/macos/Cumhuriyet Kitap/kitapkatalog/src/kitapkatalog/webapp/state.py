"""Web uygulamasının paylaşılan süreç durumu."""

from __future__ import annotations

import secrets
import threading
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Any

from kitapkatalog.application import ApplicationContext
from kitapkatalog.webapp.instance import instance_id_for_root
from kitapkatalog.webapp.jobs import JobRegistry

if TYPE_CHECKING:
    from kitapkatalog.voice_controller import PendingUtterance, VoiceSession


@dataclass
class WebState:
    ctx: ApplicationContext
    registry: JobRegistry
    token: str
    instance_id: str = ""
    nonce: str = field(default_factory=lambda: secrets.token_hex(8))
    _voice_session: VoiceSession | None = None
    _voice_lock: threading.Lock = field(default_factory=threading.Lock)
    pending_utterances: dict[str, PendingUtterance] = field(default_factory=dict)
    pending_lock: threading.Lock = field(default_factory=threading.Lock)
    engine_cache: list[dict[str, Any]] | None = None
    _shutdown_callbacks: list[Callable[[], None]] = field(default_factory=list, repr=False)
    _close_lock: threading.Lock = field(default_factory=threading.Lock, repr=False)
    _closed: bool = field(default=False, init=False, repr=False)

    def __post_init__(self) -> None:
        if not self.instance_id:
            self.instance_id = instance_id_for_root(self.ctx.paths.root)

    @property
    def paths(self):
        return self.ctx.paths

    @property
    def database(self):
        return self.ctx.database

    @property
    def catalog(self):
        return self.ctx.catalog

    @property
    def settings(self):
        from kitapkatalog.settings import AppSettings

        return AppSettings(self.database)

    @property
    def members(self):
        from kitapkatalog.members import Members

        return Members(self.database)

    @property
    def loans(self):
        from kitapkatalog.loans import Loans

        return Loans(self.database, self.settings)

    @property
    def notifications(self):
        from kitapkatalog.notifications import Notifications

        return Notifications(self.database)

    @property
    def shelves(self):
        from kitapkatalog.shelves import Shelves

        return Shelves(self.database)

    @property
    def stocktake(self):
        from kitapkatalog.stocktake import Stocktake

        return Stocktake(self.database)

    @property
    def discards(self):
        from kitapkatalog.discards import Discards

        return Discards(self.database)

    @property
    def reports(self):
        from kitapkatalog.reports import Reports

        return Reports(self.database)

    @property
    def reading_lists(self):
        from kitapkatalog.reading_lists import ReadingLists

        return ReadingLists(self.database)

    @property
    def challenges(self):
        from kitapkatalog.challenges import Challenges

        return Challenges(self.database)

    @property
    def upload_root(self) -> Path:
        root = self.paths.root / "web_uploads"
        root.mkdir(parents=True, exist_ok=True)
        return root

    def voice_session(self) -> VoiceSession:
        from kitapkatalog.voice_controller import VoiceSession

        with self._voice_lock:
            if self._voice_session is None:
                self._voice_session = VoiceSession(self.database, self.paths)
            return self._voice_session

    def reset_voice_session(self) -> None:
        """Açık oturumu kapatıp at; sonraki ``voice_session()`` çağrısı yeni dil/istem
        ayarlarıyla kurulur (ör. ayarlar formundan dil değişince çağrılır)."""

        with self._voice_lock:
            if self._voice_session is not None:
                self._voice_session.close()
                self._voice_session = None

    def add_shutdown_callback(self, callback: Callable[[], None]) -> None:
        """Run server-owned cleanup before the application context closes."""

        with self._close_lock:
            if self._closed:
                raise RuntimeError("Kapanmış web durumuna callback eklenemez")
            self._shutdown_callbacks.append(callback)

    def close(self) -> None:
        with self._close_lock:
            if self._closed:
                return
            self._closed = True
            callbacks = tuple(self._shutdown_callbacks)
            self._shutdown_callbacks.clear()
        callback_error: BaseException | None = None
        for callback in callbacks:
            try:
                callback()
            except BaseException as exc:
                if callback_error is None:
                    callback_error = exc
        self.registry.shutdown()
        with self.pending_lock:
            pending = tuple(self.pending_utterances.values())
            self.pending_utterances.clear()
        for utterance in pending:
            # Onaylanan seslerde JSON sidecar denetim izi olarak tutulur;
            # formdan vazgeçilmiş ham kayıtlar süreç kapanışında silinir.
            if not utterance.wav_path.with_suffix(".json").exists():
                utterance.wav_path.unlink(missing_ok=True)
        with self._voice_lock:
            if self._voice_session is not None:
                self._voice_session.close()
                self._voice_session = None
        self.ctx.close()
        if callback_error is not None:
            raise callback_error
