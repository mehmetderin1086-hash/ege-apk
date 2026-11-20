from __future__ import annotations

import asyncio
import os
import re
import signal
from collections.abc import Awaitable, Callable
from contextlib import suppress
from pathlib import Path
from typing import Any

from ..config import AppSettings
from ..models import DownloadJob
from ..runtime import RuntimeRegistry
from .aria2 import DownloadEngineError, ProgressCallback


class MediaDownloadEngine:
    PROGRESS_PREFIX = "__DH_PROGRESS__"
    FILE_PREFIX = "__DH_FILE__"

    def __init__(self, settings: AppSettings, runtime: RuntimeRegistry):
        self.settings = settings
        self.runtime = runtime
        self._processes: dict[str, asyncio.subprocess.Process] = {}
        self._paused: set[str] = set()
        self._desired_states: dict[str, str] = {}

    async def download(
        self,
        job: DownloadJob,
        progress: ProgressCallback,
        stage: Callable[[str], Awaitable[None]],
    ) -> list[str]:
        if self._desired_states.get(job.id) == "cancelled":
            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
        command = self.runtime.yt_dlp_command()
        if not command:
            raise DownloadEngineError(
                "YTDLP_MISSING", "yt-dlp kurulmamış. Sistem Kontrolü ekranını açın.", False
            )
        args = self._build_args(command, job)
        process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            start_new_session=True,
        )
        self._processes[job.id] = process
        desired_state = self._desired_states.get(job.id)
        if desired_state == "cancelled":
            await self._terminate(process, job.id)
            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
        if desired_state == "paused" and process.returncode is None:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGSTOP)
                self._paused.add(job.id)
        output_paths: list[str] = []
        errors: list[str] = []
        try:
            assert process.stdout is not None
            async for raw_line in process.stdout:
                line = raw_line.decode("utf-8", "replace").strip()
                if line.startswith(self.PROGRESS_PREFIX):
                    update = self._parse_progress(line.removeprefix(self.PROGRESS_PREFIX))
                    if update:
                        await progress(update)
                elif line.startswith(self.FILE_PREFIX):
                    output_path = line.removeprefix(self.FILE_PREFIX).strip()
                    if output_path and output_path not in output_paths:
                        output_paths.append(output_path)
                elif any(marker in line for marker in ("[Merger]", "[ExtractAudio]", "[Metadata]")):
                    await stage("postprocessing")
                elif line.startswith("ERROR:"):
                    errors.append(self._redact_error(line))
            return_code = await process.wait()
            if return_code != 0 and not output_paths:
                message = errors[-1] if errors else f"yt-dlp {return_code} koduyla sonlandı"
                lower = message.lower()
                if "sign in" in lower or "cookie" in lower:
                    raise DownloadEngineError(
                        "AUTH_REQUIRED",
                        "Kaynak oturum doğrulaması istiyor. Tarayıcı oturumunu kullanmayı deneyin.",
                        False,
                    )
                if "429" in lower or "captcha" in lower:
                    raise DownloadEngineError(
                        "RATE_LIMITED", "Kaynak hız sınırı veya CAPTCHA uyguladı.", False
                    )
                raise DownloadEngineError("YTDLP_ERROR", message, True)
            if not output_paths:
                output_path = self._find_latest_output(job)
                if output_path:
                    output_paths.append(output_path)
            if not output_paths:
                raise DownloadEngineError(
                    "OUTPUT_NOT_FOUND", "İndirme bitti ancak çıktı dosyası bulunamadı", False
                )
            return output_paths
        finally:
            self._processes.pop(job.id, None)
            self._paused.discard(job.id)
            self._desired_states.pop(job.id, None)

    async def pause(self, job_id: str) -> None:
        self._desired_states[job_id] = "paused"
        process = self._processes.get(job_id)
        if process and process.returncode is None and job_id not in self._paused:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGSTOP)
                self._paused.add(job_id)

    async def resume(self, job_id: str) -> None:
        if self._desired_states.get(job_id) == "paused":
            self._desired_states.pop(job_id, None)
        process = self._processes.get(job_id)
        if process and process.returncode is None and job_id in self._paused:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGCONT)
            self._paused.discard(job_id)

    async def cancel(self, job_id: str) -> None:
        self._desired_states[job_id] = "cancelled"
        process = self._processes.get(job_id)
        if not process or process.returncode is not None:
            return
        await self._terminate(process, job_id)

    async def _terminate(self, process: asyncio.subprocess.Process, job_id: str) -> None:
        if job_id in self._paused:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGCONT)
            self._paused.discard(job_id)
        with suppress(ProcessLookupError):
            os.killpg(process.pid, signal.SIGTERM)
        try:
            await asyncio.wait_for(process.wait(), timeout=5)
        except TimeoutError:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            await process.wait()

    def reset_control(self, job_id: str) -> None:
        self._desired_states.pop(job_id, None)

    def _build_args(self, command: list[str], job: DownloadJob) -> list[str]:
        options = job.options or {}
        output_dir = Path(job.output_path or self.settings.download_dir / job.category)
        output_dir.mkdir(parents=True, exist_ok=True)
        template = str(
            output_dir
            / "%(uploader,channel|Bilinmeyen)s"
            / "%(upload_date|Tarih yok)s - %(title).180B [%(id)s].%(ext)s"
        )
        args = [
            *command,
            "--ignore-config",
            "--newline",
            "--no-color",
            "--continue",
            "--part",
            "--no-overwrites",
            "--ignore-errors",
            "--progress",
            "--progress-template",
            f"{self.PROGRESS_PREFIX}%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s",
            "--print",
            f"after_move:{self.FILE_PREFIX}%(filepath)s",
            "-o",
            template,
        ]
        deno = self.runtime.deno()
        if deno:
            args.extend(["--js-runtimes", f"deno:{deno}"])
        if self.settings.safe_proxy_url:
            args.extend(["--proxy", self.settings.safe_proxy_url])
        ffmpeg = self.runtime.ffmpeg()
        if ffmpeg:
            args.extend(["--ffmpeg-location", ffmpeg])
        preset = options.get("preset", "best")
        format_id = options.get("format_id")
        format_map = {
            "best": "bestvideo*+bestaudio/best",
            "mp4": "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4]/best",
            "1080p": "bv*[height<=1080]+ba/b[height<=1080]",
            "720p": "bv*[height<=720]+ba/b[height<=720]",
            "m4a": "bestaudio[ext=m4a]/bestaudio",
            "mp3": "bestaudio",
            "archive": "bestvideo+bestaudio/best",
        }
        args.extend(["-f", format_id or format_map.get(preset, format_map["best"])])
        if preset == "mp4":
            args.extend(["--merge-output-format", "mp4"])
        elif preset == "mp3":
            args.extend(["-x", "--audio-format", "mp3", "--audio-quality", "192K"])
        elif preset == "m4a":
            args.extend(["-x", "--audio-format", "m4a"])
        subtitle_languages = options.get("subtitle_languages") or []
        if subtitle_languages:
            args.extend(
                [
                    "--write-subs",
                    "--write-auto-subs",
                    "--sub-langs",
                    ",".join(subtitle_languages),
                ]
            )
        if options.get("write_thumbnail"):
            args.append("--write-thumbnail")
        if options.get("write_metadata"):
            args.extend(["--write-info-json", "--write-description"])
        positions = options.get("selected_positions") or []
        if positions:
            args.extend(["--playlist-items", ",".join(str(position) for position in positions)])
        if options.get("use_browser_cookies"):
            browser_name = options.get("browser_name") or "chrome"
            profile = options.get("browser_profile") or "Default"
            args.extend(["--cookies-from-browser", f"{browser_name}:{profile}"])
        speed_limit = options.get("speed_limit")
        if speed_limit and speed_limit != "0":
            args.extend(["--limit-rate", speed_limit])
        args.append(job.source_url)
        return args

    @staticmethod
    def _parse_progress(raw: str) -> dict[str, Any] | None:
        values = raw.split("|")
        if len(values) != 5:
            return None

        def number(value: str) -> int | None:
            value = value.strip()
            if value in {"", "NA", "None"}:
                return None
            try:
                return int(float(value))
            except ValueError:
                return None

        try:
            percent = float(values[0].replace("%", "").strip())
        except ValueError:
            percent = 0.0
        return {
            "progress": max(0.0, min(100.0, percent)),
            "downloaded_bytes": number(values[1]) or 0,
            "total_bytes": number(values[2]),
            "speed_bytes": number(values[3]) or 0,
            "eta_seconds": number(values[4]),
        }

    @staticmethod
    def _redact_error(value: str) -> str:
        value = re.sub(r"(?i)(cookie|token|authorization)=\S+", r"\1=[GİZLİ]", value)
        value = re.sub(r"https?://\S+\?\S+", "[GİZLİ URL]", value)
        return value[:1000]

    def _find_latest_output(self, job: DownloadJob) -> str | None:
        root = Path(job.output_path or self.settings.download_dir / job.category)
        if not root.exists():
            return None
        files = [
            path for path in root.rglob("*") if path.is_file() and not path.name.endswith((".part", ".ytdl"))
        ]
        return str(max(files, key=lambda path: path.stat().st_mtime)) if files else None
