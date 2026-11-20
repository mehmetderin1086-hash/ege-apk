from __future__ import annotations

import asyncio
import os
import platform
import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass


@dataclass(slots=True)
class ResourceLease:
    kind: str
    acquired_at: float


class ResourceManager:
    """Serialises memory-heavy Apple Silicon workloads."""

    def __init__(self, concurrency: int = 1) -> None:
        self._semaphore = asyncio.Semaphore(max(1, concurrency))
        self._active: dict[str, ResourceLease] = {}
        self._lock = asyncio.Lock()

    @asynccontextmanager
    async def lease(self, kind: str) -> AsyncIterator[ResourceLease]:
        await self._semaphore.acquire()
        lease = ResourceLease(kind=kind, acquired_at=time.monotonic())
        async with self._lock:
            self._active[kind] = lease
        try:
            yield lease
        finally:
            async with self._lock:
                self._active.pop(kind, None)
            self._semaphore.release()

    async def snapshot(self) -> dict[str, object]:
        async with self._lock:
            active = [
                {"kind": lease.kind, "seconds": round(time.monotonic() - lease.acquired_at, 2)}
                for lease in self._active.values()
            ]
        return {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "logical_cpus": os.cpu_count(),
            "active_heavy_tasks": active,
            "concurrency": self._semaphore._value + len(active),  # noqa: SLF001
        }

