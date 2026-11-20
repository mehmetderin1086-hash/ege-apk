"""Cross-job memory admission and mutually exclusive heavy-model loading."""

from __future__ import annotations

import os
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from threading import Event, Lock
from typing import BinaryIO

import psutil

from kitapkatalog.config import RuntimeLimits

HEAVY_ENGINE_IDS = frozenset({"paddleocr_vl", "surya", "qwen3_field_extractor"})


class ResourceLimitError(RuntimeError):
    """The configured hard memory limit or admission timeout was reached."""


@dataclass(frozen=True, slots=True)
class MemorySnapshot:
    process_tree_rss: int
    system_available: int
    soft_limit: int
    hard_limit: int

    @property
    def above_soft(self) -> bool:
        return self.process_tree_rss >= self.soft_limit

    @property
    def above_hard(self) -> bool:
        return self.process_tree_rss >= self.hard_limit


class MemoryAdmissionController:
    """Apply backpressure using the parent plus all live child process RSS."""

    def __init__(
        self,
        limits: RuntimeLimits | None = None,
        *,
        process: psutil.Process | None = None,
        minimum_system_available: int = 1024**3,
    ) -> None:
        self.limits = limits or RuntimeLimits()
        self.process = process or psutil.Process()
        self.minimum_system_available = max(0, int(minimum_system_available))

    def snapshot(self) -> MemorySnapshot:
        rss = self.process.memory_info().rss
        try:
            children = self.process.children(recursive=True)
        except (PermissionError, psutil.Error):
            children = []
        for child in children:
            try:
                rss += child.memory_info().rss
            except (PermissionError, psutil.Error):
                continue
        try:
            system_available = psutil.virtual_memory().available
        except (PermissionError, psutil.Error):
            # Sandboxed macOS processes can read their own RSS while the
            # system-wide sysctl is denied.  Keep the hard per-process limit
            # active and avoid turning a telemetry restriction into a failed
            # OCR job.
            system_available = self.minimum_system_available
        return MemorySnapshot(
            process_tree_rss=rss,
            system_available=system_available,
            soft_limit=self.limits.soft_rss_bytes,
            hard_limit=self.limits.hard_rss_bytes,
        )

    def can_admit(self) -> bool:
        snapshot = self.snapshot()
        return (
            not snapshot.above_soft and snapshot.system_available >= self.minimum_system_available
        )

    def wait_for_capacity(
        self,
        *,
        timeout: float | None = None,
        cancel: Event | None = None,
        poll_seconds: float = 0.25,
    ) -> MemorySnapshot:
        started = time.monotonic()
        while True:
            if cancel is not None and cancel.is_set():
                raise ResourceLimitError("Kaynak beklemesi iptal edildi")
            snapshot = self.snapshot()
            if snapshot.above_hard:
                raise ResourceLimitError(
                    "Sert bellek sınırı aşıldı: "
                    f"{snapshot.process_tree_rss / 1024**3:.2f} GiB / "
                    f"{snapshot.hard_limit / 1024**3:.2f} GiB"
                )
            if (
                not snapshot.above_soft
                and snapshot.system_available >= self.minimum_system_available
            ):
                return snapshot
            if timeout is not None and time.monotonic() - started >= timeout:
                raise ResourceLimitError("Bellek backpressure bekleme süresi doldu")
            if cancel is not None:
                cancel.wait(poll_seconds)
            else:
                time.sleep(poll_seconds)


class InterprocessModelLock:
    """Portable advisory file lock used by all jobs before loading a large model."""

    _thread_lock = Lock()

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._stream: BinaryIO | None = None

    def acquire(
        self,
        *,
        timeout: float | None = None,
        cancel: Event | None = None,
        poll_seconds: float = 0.1,
    ) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        started = time.monotonic()
        stream = self.path.open("a+b")
        if stream.tell() == 0:
            stream.write(b"\0")
            stream.flush()
        while True:
            if cancel is not None and cancel.is_set():
                stream.close()
                raise ResourceLimitError("Ağır model kilidi beklemesi iptal edildi")
            if self._try_lock(stream):
                self._stream = stream
                return
            if timeout is not None and time.monotonic() - started >= timeout:
                stream.close()
                raise ResourceLimitError("Ağır model kilidi bekleme süresi doldu")
            if cancel is not None:
                cancel.wait(poll_seconds)
            else:
                time.sleep(poll_seconds)

    @classmethod
    def _try_lock(cls, stream: BinaryIO) -> bool:
        # The in-process lock closes a Windows/POSIX edge where advisory file
        # locks may be process-scoped and two threads could otherwise re-enter.
        if not cls._thread_lock.acquire(blocking=False):
            return False
        try:
            if os.name == "nt":
                import msvcrt

                stream.seek(0)
                try:
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                except OSError:
                    cls._thread_lock.release()
                    return False
            else:
                import fcntl

                try:
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    cls._thread_lock.release()
                    return False
            return True
        except BaseException:
            cls._thread_lock.release()
            raise

    def release(self) -> None:
        if self._stream is None:
            return
        stream = self._stream
        self._stream = None
        try:
            if os.name == "nt":
                import msvcrt

                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
        finally:
            stream.close()
            self._thread_lock.release()

    def __enter__(self) -> InterprocessModelLock:
        self.acquire()
        return self

    def __exit__(self, _exc_type: object, _exc: object, _traceback: object) -> None:
        self.release()


@contextmanager
def model_admission(
    engine_id: str,
    *,
    controller: MemoryAdmissionController,
    lock_path: Path,
    timeout: float | None = None,
    cancel: Event | None = None,
) -> Iterator[MemorySnapshot]:
    """Wait for RSS capacity and serialize Paddle/Surya/Qwen across all jobs."""

    snapshot = controller.wait_for_capacity(timeout=timeout, cancel=cancel)
    if engine_id not in HEAVY_ENGINE_IDS:
        yield snapshot
        return
    lock = InterprocessModelLock(lock_path)
    lock.acquire(timeout=timeout, cancel=cancel)
    try:
        # Re-check after waiting: another model may have increased RSS.
        snapshot = controller.wait_for_capacity(timeout=timeout, cancel=cancel)
        yield snapshot
    finally:
        lock.release()
