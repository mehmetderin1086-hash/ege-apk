from __future__ import annotations

import asyncio
import contextlib
import inspect
from collections import defaultdict
from collections.abc import Awaitable, Callable
from typing import Any

from bioprof.db.session import Database
from bioprof.services.repositories import Repository

JobCallable = Callable[[str, dict[str, Any]], Awaitable[dict[str, Any]] | dict[str, Any]]


class JobManager:
    """Persistent local background job runner with cancellable in-process workers."""

    def __init__(self, database: Database, concurrency: int = 1) -> None:
        self.database = database
        self._handlers: dict[str, JobCallable] = {}
        self._tasks: dict[str, asyncio.Task[None]] = {}
        self._events: dict[str, list[asyncio.Queue[dict[str, Any]]]] = defaultdict(list)
        self._semaphore = asyncio.Semaphore(max(1, concurrency))

    def register(self, kind: str, handler: JobCallable) -> None:
        self._handlers[kind] = handler

    def submit(self, kind: str, payload: dict[str, Any]) -> str:
        if kind not in self._handlers:
            raise ValueError(f"Bilinmeyen iş türü: {kind}")
        with self.database.session() as session:
            record = Repository(session).create_job(kind, payload)
            job_id = record.id
        task = asyncio.create_task(self._run(job_id, kind, payload), name=f"bioprof:{job_id}")
        self._tasks[job_id] = task
        return job_id

    async def _run(self, job_id: str, kind: str, payload: dict[str, Any]) -> None:
        try:
            async with self._semaphore:
                self._update(job_id, status="running", progress=0.01)
                await self.publish(job_id, {"status": "running", "progress": 0.01})
                result = self._handlers[kind](job_id, payload)
                if inspect.isawaitable(result):
                    result = await result
                self._update(job_id, status="completed", progress=1.0, result=result)
                await self.publish(
                    job_id, {"status": "completed", "progress": 1.0, "result": result}
                )
        except asyncio.CancelledError:
            self._update(job_id, status="cancelled")
            await self.publish(job_id, {"status": "cancelled"})
            raise
        except Exception as exc:  # noqa: BLE001 - persisted user-facing worker boundary
            self._update(job_id, status="failed", error=str(exc))
            await self.publish(job_id, {"status": "failed", "error": str(exc)})
        finally:
            self._tasks.pop(job_id, None)

    def _update(self, job_id: str, **values: Any) -> None:
        with self.database.session() as session:
            Repository(session).update_job(job_id, **values)

    def progress(
        self,
        job_id: str,
        value: float,
        message: str | None = None,
        *,
        checkpoint: dict[str, Any] | None = None,
    ) -> None:
        """İlerlemeyi kaydeder; mesaj ve ara sonuç iş kaydında da durur.

        Mesaj yalnız SSE'ye yayınlandığı sürece, akışı dinlemeyen bir istemci
        (ya da yeniden bağlanan biri) işin hangi aşamada olduğunu göremiyordu.
        Uzun podcast üretimlerinde bu, saatlerce "running" görmek demekti.
        """
        payload: dict[str, Any] = {}
        if message:
            payload["stage"] = message
        if checkpoint:
            payload["checkpoint"] = checkpoint
        self._update(job_id, progress=value, result=payload or None)
        with contextlib.suppress(RuntimeError):
            asyncio.get_running_loop().create_task(
                self.publish(job_id, {"status": "running", "progress": value, "message": message})
            )

    def cancel(self, job_id: str) -> bool:
        task = self._tasks.get(job_id)
        if task is None:
            return False
        task.cancel()
        return True

    async def publish(self, job_id: str, event: dict[str, Any]) -> None:
        for queue in list(self._events[job_id]):
            if queue.full():
                with contextlib.suppress(asyncio.QueueEmpty):
                    queue.get_nowait()
            with contextlib.suppress(asyncio.QueueFull):
                queue.put_nowait(event)

    async def stream(self, job_id: str):  # type: ignore[no-untyped-def]
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=100)
        self._events[job_id].append(queue)
        try:
            with self.database.session() as session:
                record = Repository(session).get_job(job_id)
                if record is None:
                    yield {"status": "failed", "error": "İş bulunamadı"}
                    return
                current = Repository.serialize_job(record)
            yield current
            if current["status"] in {"completed", "failed", "cancelled"}:
                return
            while True:
                event = await queue.get()
                yield event
                if event.get("status") in {"completed", "failed", "cancelled"}:
                    break
        finally:
            self._events[job_id].remove(queue)

    def recover_interrupted(self) -> int:
        """Mark work lost during a previous process exit without re-running unsafe jobs."""
        count = 0
        with self.database.session() as session:
            repository = Repository(session)
            for job in repository.list_jobs(limit=1000):
                if job.status in {"queued", "running"}:
                    repository.update_job(
                        job.id,
                        status="failed",
                        error=(
                            "Uygulama yeniden başlatıldığı için iş kesildi; "
                            "güvenle yeniden deneyin."
                        ),
                    )
                    count += 1
        return count
