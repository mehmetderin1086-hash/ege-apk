from __future__ import annotations

import asyncio
import signal
from pathlib import Path

import pytest

from downloadhub.engines.aria2 import DownloadEngineError
from downloadhub.engines.media import MediaDownloadEngine
from downloadhub.models import DownloadJob, JobItem
from downloadhub.queue import QueueManager


class FakeRuntime:
    def yt_dlp_command(self):
        return ["yt-dlp"]

    def ffmpeg(self):
        return "/runtime/bin/ffmpeg"

    def deno(self):
        return "/runtime/bin/deno"


def test_media_command_uses_typed_options_without_shell(app_settings) -> None:
    engine = MediaDownloadEngine(app_settings, FakeRuntime())
    job = DownloadJob(
        id="a" * 32,
        source_url="https://www.youtube.com/watch?v=allowed",
        engine="media",
        status="queued",
        title="Test",
        category="Videolar",
        output_path=str(Path(app_settings.download_dir) / "Videolar"),
        options={
            "preset": "1080p",
            "subtitle_languages": ["tr", "en"],
            "write_thumbnail": True,
            "write_metadata": True,
            "selected_positions": [1, 3],
            "use_browser_cookies": True,
            "browser_name": "brave",
            "browser_profile": "Profile 1",
        },
    )
    args = engine._build_args(["yt-dlp"], job)
    assert args[0] == "yt-dlp"
    assert "bv*[height<=1080]+ba/b[height<=1080]" in args
    assert "1,3" in args
    assert "brave:Profile 1" in args
    assert "--write-thumbnail" in args
    assert args[args.index("--ffmpeg-location") + 1] == "/runtime/bin/ffmpeg"
    assert ";" not in " ".join(args)


def test_progress_parser_handles_unknown_values() -> None:
    parsed = MediaDownloadEngine._parse_progress(" 42.5%|1024|2048|512|2")
    assert parsed == {
        "progress": 42.5,
        "downloaded_bytes": 1024,
        "total_bytes": 2048,
        "speed_bytes": 512,
        "eta_seconds": 2,
    }
    unknown = MediaDownloadEngine._parse_progress("NA|NA|NA|NA|NA")
    assert unknown["total_bytes"] is None


def test_media_sidecars_with_brackets_are_collected(app_settings) -> None:
    output_dir = app_settings.download_dir / "Videolar"
    output_dir.mkdir(parents=True, exist_ok=True)
    primary = output_dir / "Başlık [video-id].webm"
    subtitle = output_dir / "Başlık [video-id].tr.vtt"
    metadata = output_dir / "Başlık [video-id].info.json"
    for target in (primary, subtitle, metadata):
        target.write_bytes(b"test")
    manager = QueueManager(app_settings, None, None, None, None, {})  # type: ignore[arg-type]
    job = DownloadJob(
        id="b" * 32,
        source_url="https://www.youtube.com/watch?v=video-id",
        engine="media",
        status="completed",
        title="Başlık",
        category="Videolar",
        output_path=str(output_dir),
        options={},
    )
    collected = manager._collect_artifact_paths(job, [str(primary)])
    assert set(collected) == {primary.resolve(), subtitle.resolve(), metadata.resolve()}


def test_playlist_item_outcomes_are_derived_from_output_ids(app_settings) -> None:
    manager = QueueManager(app_settings, None, None, None, None, {})  # type: ignore[arg-type]
    job = DownloadJob(
        id="c" * 32,
        source_url="https://www.youtube.com/playlist?list=test",
        engine="media",
        status="completed",
        title="Liste",
        category="Videolar",
        output_path=str(app_settings.download_dir / "Videolar"),
        options={},
    )
    job.items = [
        JobItem(source_id="ok-id", title="Başarılı", position=1, selected=True),
        JobItem(source_id="missing-id", title="Başarısız", position=2, selected=True),
    ]
    artifact = app_settings.download_dir / "Videolar" / "Başlık [ok-id].webm"
    assert manager._successful_item_ids(job, [artifact]) == {"ok-id"}


@pytest.mark.asyncio
async def test_media_accepts_successful_playlist_outputs_when_yt_dlp_reports_partial_failure(
    app_settings,
    monkeypatch,
) -> None:
    class FakeStdout:
        def __init__(self) -> None:
            self.lines = iter([b"__DH_FILE__/tmp/Basarili [ok-id].webm\n", b"ERROR: bir oge basarisiz\n"])

        def __aiter__(self):
            return self

        async def __anext__(self) -> bytes:
            try:
                return next(self.lines)
            except StopIteration as exc:
                raise StopAsyncIteration from exc

    class FakeProcess:
        def __init__(self) -> None:
            self.stdout = FakeStdout()
            self.returncode = None

        async def wait(self) -> int:
            self.returncode = 1
            return 1

    async def fake_subprocess(*_args, **_kwargs):
        return FakeProcess()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", fake_subprocess)
    engine = MediaDownloadEngine(app_settings, FakeRuntime())
    job = DownloadJob(
        id="d" * 32,
        source_url="https://www.youtube.com/playlist?list=test",
        engine="media",
        status="downloading",
        title="Liste",
        category="Videolar",
        output_path=str(app_settings.download_dir / "Videolar"),
        options={"selected_positions": [1, 2]},
    )

    async def progress(_values):
        return None

    async def stage(_value):
        return None

    assert await engine.download(job, progress, stage) == ["/tmp/Basarili [ok-id].webm"]


@pytest.mark.asyncio
async def test_media_applies_pause_requested_while_process_is_starting(
    app_settings,
    monkeypatch,
) -> None:
    spawn_started = asyncio.Event()
    allow_spawn = asyncio.Event()
    signals: list[tuple[int, int]] = []

    class EmptyStdout:
        def __aiter__(self):
            return self

        async def __anext__(self) -> bytes:
            raise StopAsyncIteration

    class FakeProcess:
        pid = 4321
        stdout = EmptyStdout()
        returncode = None

        async def wait(self) -> int:
            self.returncode = 1
            return 1

    async def delayed_subprocess(*_args, **_kwargs):
        spawn_started.set()
        await allow_spawn.wait()
        return FakeProcess()

    monkeypatch.setattr(asyncio, "create_subprocess_exec", delayed_subprocess)
    monkeypatch.setattr(
        "downloadhub.engines.media.os.killpg",
        lambda pid, sent_signal: signals.append((pid, sent_signal)),
    )
    engine = MediaDownloadEngine(app_settings, FakeRuntime())
    job = DownloadJob(
        id="e" * 32,
        source_url="https://www.youtube.com/watch?v=test",
        engine="media",
        status="downloading",
        title="Video",
        category="Videolar",
        output_path=str(app_settings.download_dir / "Videolar"),
        options={},
    )

    async def progress(_values):
        return None

    async def stage(_value):
        return None

    task = asyncio.create_task(engine.download(job, progress, stage))
    await spawn_started.wait()
    await engine.pause(job.id)
    allow_spawn.set()
    with pytest.raises(DownloadEngineError, match="yt-dlp 1 koduyla sonlandı"):
        await task
    assert (FakeProcess.pid, signal.SIGSTOP) in signals
