"""İş kuyruğu — tek worker, SSE yayını.

Modeller thread-safe olmadığı ve 16 GB bütçe paralel inference'a izin
vermediği için TÜM üretimler tek asyncio worker'dan sırayla geçer.
Bloklayıcı inference `asyncio.to_thread` ile çalışır; olay döngüsü ve
SSE akışları serbest kalır.
"""
from __future__ import annotations

import asyncio
import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable

from app import db


@dataclass
class Job:
    id: str
    type: str
    status: str = "queued"       # queued | running | done | error | cancelled
    progress: float = 0.0
    message: str = ""
    payload: dict = field(default_factory=dict)
    result: dict | None = None
    created_at: float = field(default_factory=time.time)

    def public(self) -> dict:
        return {
            "id": self.id,
            "type": self.type,
            "status": self.status,
            "progress": round(self.progress, 4),
            "message": self.message,
            "result": self.result,
        }


JobRunner = Callable[[Job], Awaitable[dict | None]]


class JobQueue:
    def __init__(self) -> None:
        self.jobs: dict[str, Job] = {}
        self._queue: asyncio.Queue[tuple[Job, JobRunner]] = asyncio.Queue()
        self._conditions: dict[str, asyncio.Condition] = {}
        self._worker_task: asyncio.Task | None = None

    # -- yaşam döngüsü ---------------------------------------------------------

    def start(self) -> None:
        if self._worker_task is None:
            self._worker_task = asyncio.create_task(self._worker())

    async def stop(self) -> None:
        if self._worker_task:
            self._worker_task.cancel()
            self._worker_task = None

    # -- gönderim ----------------------------------------------------------------

    MAX_FINISHED_JOBS = 200  # bellekte tutulacak bitmiş iş sayısı

    def submit(self, type_: str, payload: dict, runner: JobRunner) -> Job:
        self._prune()
        job = Job(id=uuid.uuid4().hex[:12], type=type_, payload=payload)
        self.jobs[job.id] = job
        self._conditions[job.id] = asyncio.Condition()
        self._persist(job)
        self._queue.put_nowait((job, runner))
        return job

    def _prune(self) -> None:
        """Bitmiş işleri sınırla — STT sonuçları megabaytlarca olabilir."""
        finished = [
            j for j in self.jobs.values()
            if j.status in ("done", "error", "cancelled")
        ]
        if len(finished) <= self.MAX_FINISHED_JOBS:
            return
        finished.sort(key=lambda j: j.created_at)
        for j in finished[: len(finished) - self.MAX_FINISHED_JOBS]:
            self.jobs.pop(j.id, None)
            self._conditions.pop(j.id, None)

    async def submit_and_wait(
        self, type_: str, payload: dict, runner: JobRunner
    ) -> Job:
        """Kısa işler için: kuyruğa koy, bitmesini bekle (adil FIFO).

        Durum denetimi kilit ALTINDA yapılır; update() bildirimi de aynı
        kilidi aldığı için bildirim kaçırma yarışı oluşmaz.
        """
        job = self.submit(type_, payload, runner)
        cond = self._conditions[job.id]
        async with cond:
            while job.status not in ("done", "error", "cancelled"):
                await cond.wait()
        return job

    # -- worker ---------------------------------------------------------------------

    async def _worker(self) -> None:
        while True:
            job, runner = await self._queue.get()
            if job.status == "cancelled":
                continue
            await self.update(job, status="running")
            try:
                result = await runner(job)
                job.result = result
                await self.update(job, status="done", progress=1.0)
            except asyncio.CancelledError:
                await self.update(job, status="cancelled")
                raise
            except Exception as e:  # noqa: BLE001 — iş hatası kullanıcıya taşınır
                await self.update(job, status="error", message=str(e))

    # -- güncelleme + bildirim ----------------------------------------------------------

    async def update(
        self,
        job: Job,
        status: str | None = None,
        progress: float | None = None,
        message: str | None = None,
    ) -> None:
        if status is not None:
            job.status = status
        if progress is not None:
            job.progress = progress
        if message is not None:
            job.message = message
        self._persist(job)
        cond = self._conditions.get(job.id)
        if cond:
            async with cond:
                cond.notify_all()

    def _persist(self, job: Job) -> None:
        with db.connect() as conn:
            conn.execute(
                """INSERT INTO jobs (id, type, status, progress, message,
                                     payload, result, created_at, updated_at)
                   VALUES (?,?,?,?,?,?,?,?,?)
                   ON CONFLICT(id) DO UPDATE SET status=excluded.status,
                     progress=excluded.progress, message=excluded.message,
                     result=excluded.result, updated_at=excluded.updated_at""",
                (
                    job.id, job.type, job.status, job.progress, job.message,
                    json.dumps(job.payload, ensure_ascii=False, default=str),
                    json.dumps(job.result, ensure_ascii=False, default=str)
                    if job.result else None,
                    job.created_at, time.time(),
                ),
            )

    # -- SSE ---------------------------------------------------------------------------

    async def events(self, job_id: str):
        """SSE üreteci: her değişimde durum yayınlar, 15 sn'de bir kalp atışı."""
        job = self.jobs.get(job_id)
        if job is None:
            yield f"data: {json.dumps({'error': 'İş bulunamadı'})}\n\n"
            return
        cond = self._conditions[job_id]
        while True:
            yield f"data: {json.dumps(job.public(), ensure_ascii=False)}\n\n"
            if job.status in ("done", "error", "cancelled"):
                return
            try:
                async with cond:
                    await asyncio.wait_for(cond.wait(), timeout=15.0)
            except asyncio.TimeoutError:
                pass  # kalp atışı: mevcut durumu yeniden yayınla


queue = JobQueue()
