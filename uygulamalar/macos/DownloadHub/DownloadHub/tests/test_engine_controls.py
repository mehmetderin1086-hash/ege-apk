from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from downloadhub.engines.aria2 import DirectDownloadEngine
from downloadhub.models import DownloadJob


class DelayedAria2Supervisor:
    available = True

    def __init__(self, output: Path) -> None:
        self.output = output
        self.add_started = asyncio.Event()
        self.allow_add = asyncio.Event()
        self.calls: list[str] = []

    async def rpc(self, method: str, *_params):
        self.calls.append(method)
        if method == "aria2.addUri":
            self.add_started.set()
            await self.allow_add.wait()
            return "test-gid"
        if method == "aria2.tellStatus":
            return {
                "status": "complete",
                "totalLength": "4",
                "completedLength": "4",
                "downloadSpeed": "0",
                "files": [{"path": str(self.output)}],
            }
        return "OK"


@pytest.mark.asyncio
async def test_aria2_applies_pause_requested_while_gid_is_allocating(app_settings) -> None:
    output = app_settings.download_dir / "Diğer" / "file.bin"
    supervisor = DelayedAria2Supervisor(output)
    engine = DirectDownloadEngine(app_settings, supervisor)  # type: ignore[arg-type]
    job = DownloadJob(
        id="f" * 32,
        source_url="https://example.com/file.bin",
        engine="direct",
        status="downloading",
        title="file.bin",
        category="Diğer",
        output_path=str(output),
        options={},
    )

    async def progress(_values):
        return None

    task = asyncio.create_task(engine.download(job, progress))
    await supervisor.add_started.wait()
    await engine.pause(job.id)
    supervisor.allow_add.set()

    assert await task == str(output)
    assert "aria2.pause" in supervisor.calls
