from __future__ import annotations

import threading
from pathlib import Path

import pytest

from kitapkatalog.config import RuntimeLimits
from kitapkatalog.resources import (
    InterprocessModelLock,
    MemoryAdmissionController,
    ResourceLimitError,
    model_admission,
)


class _MemoryInfo:
    rss = 11


class _Process:
    def memory_info(self) -> _MemoryInfo:
        return _MemoryInfo()

    def children(self, *, recursive: bool) -> list:
        assert recursive
        return []


class _RestrictedProcess(_Process):
    def children(self, *, recursive: bool) -> list:
        assert recursive
        raise PermissionError("sandboxed sysctl")


def test_soft_limit_applies_backpressure() -> None:
    controller = MemoryAdmissionController(
        RuntimeLimits(soft_rss_bytes=10, hard_rss_bytes=12),
        process=_Process(),  # type: ignore[arg-type]
        minimum_system_available=0,
    )
    assert controller.can_admit() is False
    with pytest.raises(ResourceLimitError, match="bekleme süresi"):
        controller.wait_for_capacity(timeout=0)


def test_hard_limit_fails_immediately() -> None:
    controller = MemoryAdmissionController(
        RuntimeLimits(soft_rss_bytes=9, hard_rss_bytes=10),
        process=_Process(),  # type: ignore[arg-type]
        minimum_system_available=0,
    )
    with pytest.raises(ResourceLimitError, match="Sert bellek"):
        controller.wait_for_capacity(timeout=1)


def test_heavy_model_lock_is_not_reentrant(tmp_path: Path) -> None:
    first = InterprocessModelLock(tmp_path / "heavy.lock")
    second = InterprocessModelLock(tmp_path / "heavy.lock")
    first.acquire()
    try:
        with pytest.raises(ResourceLimitError, match="kilidi"):
            second.acquire(timeout=0)
    finally:
        first.release()


def test_heavy_model_lock_wait_honours_cancellation(tmp_path: Path) -> None:
    first = InterprocessModelLock(tmp_path / "heavy.lock")
    second = InterprocessModelLock(tmp_path / "heavy.lock")
    first.acquire()
    cancel = threading.Event()
    cancel.set()
    try:
        with pytest.raises(ResourceLimitError, match="iptal"):
            second.acquire(cancel=cancel)
    finally:
        first.release()


def test_light_engine_does_not_create_lock(tmp_path: Path) -> None:
    controller = MemoryAdmissionController(minimum_system_available=0)
    with model_admission(
        "tesseract",
        controller=controller,
        lock_path=tmp_path / "heavy.lock",
    ) as snapshot:
        assert snapshot.process_tree_rss > 0
    assert not (tmp_path / "heavy.lock").exists()


def test_process_list_permission_denial_keeps_own_rss_limit_active() -> None:
    controller = MemoryAdmissionController(
        process=_RestrictedProcess(),  # type: ignore[arg-type]
        minimum_system_available=0,
    )

    assert controller.snapshot().process_tree_rss == 11


def test_cancelled_wait_stops() -> None:
    controller = MemoryAdmissionController(
        RuntimeLimits(soft_rss_bytes=10, hard_rss_bytes=12),
        process=_Process(),  # type: ignore[arg-type]
        minimum_system_available=0,
    )
    cancel = threading.Event()
    cancel.set()
    with pytest.raises(ResourceLimitError, match="iptal"):
        controller.wait_for_capacity(cancel=cancel)
