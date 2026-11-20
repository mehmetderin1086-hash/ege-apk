from __future__ import annotations

import asyncio
import importlib.util
import shutil
import sys
from pathlib import Path

from .config import AppSettings
from .schemas import RuntimeComponent


class RuntimeRegistry:
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.project_runtime = Path(__file__).resolve().parents[2] / "runtime" / "bin"

    def resolve(self, configured: str, *names: str) -> str | None:
        candidate = Path(configured).expanduser()
        if candidate.is_absolute() and candidate.is_file():
            return str(candidate)
        located = shutil.which(configured)
        if located:
            return located
        for name in names:
            bundled = self.project_runtime / name
            if bundled.is_file() and bundled.stat().st_mode & 0o111:
                return str(bundled)
        return None

    def aria2(self) -> str | None:
        return self.resolve(self.settings.aria2_path, "aria2c")

    def ffmpeg(self) -> str | None:
        binary = self.resolve(self.settings.ffmpeg_path, "ffmpeg")
        if binary:
            return binary
        try:
            import imageio_ffmpeg

            bundled = Path(imageio_ffmpeg.get_ffmpeg_exe())
            if bundled.is_file():
                return str(bundled)
        except (ImportError, RuntimeError):
            pass
        return None

    def deno(self) -> str | None:
        return self.resolve(self.settings.deno_path, "deno")

    def yt_dlp_command(self) -> list[str] | None:
        binary = self.resolve(self.settings.yt_dlp_path, "yt-dlp", "yt-dlp_macos")
        if binary:
            return [binary]
        if importlib.util.find_spec("yt_dlp"):
            return [sys.executable, "-m", "yt_dlp"]
        return None

    async def components(self) -> list[RuntimeComponent]:
        definitions: list[tuple[str, list[str] | None, list[str], bool]] = [
            ("aria2", [self.aria2()] if self.aria2() else None, ["--version"], False),
            ("yt-dlp", self.yt_dlp_command(), ["--version"], True),
            ("ffmpeg", [self.ffmpeg()] if self.ffmpeg() else None, ["-version"], True),
            ("Deno", [self.deno()] if self.deno() else None, ["--version"], True),
        ]
        return await asyncio.gather(
            *(self._component(name, command, args, required) for name, command, args, required in definitions)
        )

    async def _component(
        self, name: str, command: list[str] | None, args: list[str], required: bool
    ) -> RuntimeComponent:
        if not command or not command[0]:
            return RuntimeComponent(name=name, available=False, required=required)
        try:
            process = await asyncio.create_subprocess_exec(
                *command,
                *args,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            output, _ = await asyncio.wait_for(process.communicate(), timeout=5)
            first_line = output.decode("utf-8", "replace").splitlines()[0] if output else None
            return RuntimeComponent(
                name=name,
                available=process.returncode == 0,
                path=" ".join(command),
                version=first_line,
                required=required,
            )
        except (OSError, TimeoutError):
            return RuntimeComponent(name=name, available=False, path=command[0], required=required)
