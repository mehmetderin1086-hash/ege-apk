"""Süreç-içi arka plan işleri: tür başına tek yuva, işbirlikçi durdurma.

Kalıcı gerçeklik kaynağı SQLite'taki iş tablolarıdır (OCR/ses kuyrukları
checkpoint'lidir); bu kayıt defteri yalnız "şu an bu süreçte koşan thread"in
canlı görünümüdür. Sunucu yeniden başlarsa koşular kaybolur ama kuyruklar
kaldıkları yerden devam ettirilebilir.
"""

from __future__ import annotations

import threading
import traceback
import uuid
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any


class JobSlotBusyError(RuntimeError):
    """Aynı türde bir iş zaten çalışıyor."""


@dataclass
class WebJob:
    id: str
    kind: str
    title: str
    status: str = "running"  # running | succeeded | failed | stopped
    message: str = ""
    progress_done: int | None = None
    progress_total: int | None = None
    result: Any = None
    error: str | None = None
    started_at: str = ""
    finished_at: str | None = None
    stop_event: threading.Event = field(default_factory=threading.Event)

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "title": self.title,
            "status": self.status,
            "message": self.message,
            "progress_done": self.progress_done,
            "progress_total": self.progress_total,
            "result": self.result,
            "error": self.error,
            "started_at": self.started_at,
            "finished_at": self.finished_at,
        }


class JobRegistry:
    """Tür başına tek eşzamanlı iş; bitmiş son iş sonucu sorgulanabilir kalır."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._jobs: dict[str, WebJob] = {}
        self._threads: dict[str, threading.Thread] = {}

    def start(
        self,
        kind: str,
        title: str,
        target: Callable[[WebJob], Any],
    ) -> WebJob:
        """`target(job)` fonksiyonunu arka plan thread'inde çalıştır.

        `target` uzun döngülerinde `job.stop_event`'i kontrol etmeli ve
        ilerlemeyi `job.message`/`job.progress_*` alanlarına yazmalıdır.
        Dönüş değeri `job.result`'a konur.
        """

        with self._lock:
            current = self._jobs.get(kind)
            if current is not None and current.status == "running":
                raise JobSlotBusyError(f"Bu türde bir iş zaten çalışıyor: {current.title}")
            job = WebJob(
                id=uuid.uuid4().hex[:12],
                kind=kind,
                title=title,
                started_at=datetime.now(UTC).isoformat(),
            )
            self._jobs[kind] = job

        def _run() -> None:
            try:
                job.result = target(job)
                job.status = "stopped" if job.stop_event.is_set() else "succeeded"
            except Exception as exc:  # İş hatası kullanıcıya raporlanır.
                job.status = "failed"
                job.error = f"{type(exc).__name__}: {exc}"
                job.message = str(exc)
                traceback.print_exc()
            finally:
                job.finished_at = datetime.now(UTC).isoformat()

        thread = threading.Thread(target=_run, name=f"webjob-{kind}", daemon=True)
        with self._lock:
            self._threads[kind] = thread
        thread.start()
        return job

    def get(self, kind: str) -> WebJob | None:
        with self._lock:
            return self._jobs.get(kind)

    def request_stop(self, kind: str) -> WebJob | None:
        with self._lock:
            job = self._jobs.get(kind)
        if job is not None and job.status == "running":
            job.stop_event.set()
            job.message = "Durdurma istendi; mevcut öğe bitince duracak."
        return job

    def snapshot(self) -> dict[str, dict[str, Any]]:
        with self._lock:
            return {kind: job.to_dict() for kind, job in self._jobs.items()}

    def shutdown(self, timeout_seconds: float = 10.0) -> None:
        """Tüm koşulara durdurma gönder ve TOPLAM en fazla timeout kadar bekle."""

        import time

        with self._lock:
            jobs = list(self._jobs.values())
            threads = list(self._threads.values())
        for job in jobs:
            if job.status == "running":
                job.stop_event.set()
        deadline = time.monotonic() + timeout_seconds
        for thread in threads:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            if thread.is_alive():
                thread.join(timeout=remaining)
