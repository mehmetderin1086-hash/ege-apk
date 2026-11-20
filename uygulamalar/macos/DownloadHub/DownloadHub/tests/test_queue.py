from __future__ import annotations

import pytest
from sqlalchemy import update

from downloadhub.db import Database
from downloadhub.events import EventBroker
from downloadhub.models import DownloadJob
from downloadhub.queue import QueueManager
from downloadhub.schemas import JobStatus


class NeverStartedEngine:
    def __init__(self) -> None:
        self.download_calls = 0

    async def download(self, *_args, **_kwargs):
        self.download_calls += 1
        raise AssertionError("Durumu değişmiş görev motor tarafından başlatılmamalı")

    async def pause(self, _job_id: str) -> None:
        return None

    async def resume(self, _job_id: str) -> None:
        return None

    async def cancel(self, _job_id: str) -> None:
        return None

    def reset_control(self, _job_id: str) -> None:
        return None


@pytest.mark.asyncio
@pytest.mark.parametrize("new_status", [JobStatus.PAUSED.value, JobStatus.CANCELLED.value])
async def test_due_job_is_not_started_after_concurrent_control(app_settings, new_status: str) -> None:
    database = Database(app_settings)
    await database.initialize()
    engine = NeverStartedEngine()
    manager = QueueManager(
        app_settings,
        database,
        EventBroker(database),
        engine,  # type: ignore[arg-type]
        engine,  # type: ignore[arg-type]
        {},
    )
    job = DownloadJob(
        source_url="https://example.com/file.bin",
        engine="direct",
        status=JobStatus.QUEUED.value,
        title="file.bin",
        category="Diğer",
        output_path=str(app_settings.download_dir / "Diğer" / "file.bin"),
        options={},
    )
    try:
        async with database.sessions.begin() as session:
            session.add(job)
            await session.flush()
            job_id = job.id

        due = await manager._due_jobs(1)
        assert [item.id for item in due] == [job_id]

        async with database.sessions.begin() as session:
            await session.execute(
                update(DownloadJob).where(DownloadJob.id == job_id).values(status=new_status)
            )

        await manager._run_job(job_id)
        current = await manager._get_job(job_id)
        assert current.status == new_status
        assert engine.download_calls == 0
    finally:
        await database.close()
