from __future__ import annotations

import asyncio
import errno
import hashlib
import os
import secrets
import socket
from collections.abc import Awaitable, Callable
from contextlib import suppress
from pathlib import Path
from typing import Any

import httpx

from ..config import AppSettings
from ..models import DownloadJob
from ..runtime import RuntimeRegistry
from ..security import unique_path

ProgressCallback = Callable[[dict[str, Any]], Awaitable[None]]


class DownloadEngineError(RuntimeError):
    def __init__(self, code: str, message: str, retryable: bool = True):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


class Aria2Supervisor:
    """Owns a loopback-only aria2 RPC child process and never exposes it to the UI."""

    def __init__(self, settings: AppSettings, runtime: RuntimeRegistry):
        self.settings = settings
        self.runtime = runtime
        self.process: asyncio.subprocess.Process | None = None
        self.port: int | None = None
        self.secret = secrets.token_urlsafe(32)
        self.client: httpx.AsyncClient | None = None
        self.available = False

    async def start(self) -> bool:
        binary = self.runtime.aria2()
        if not binary:
            return False
        self.port = self._free_loopback_port()
        session_file = self.settings.data_dir / "aria2.session"
        session_file.touch(exist_ok=True)
        args = [
            binary,
            "--enable-rpc=true",
            "--rpc-listen-all=false",
            f"--rpc-listen-port={self.port}",
            f"--rpc-secret={self.secret}",
            "--rpc-allow-origin-all=false",
            "--continue=true",
            "--auto-file-renaming=true",
            "--allow-overwrite=false",
            f"--max-concurrent-downloads={self.settings.max_concurrent_jobs}",
            f"--max-overall-download-limit={self.settings.global_speed_limit}",
            f"--save-session={session_file}",
            f"--input-file={session_file}",
            "--save-session-interval=15",
            "--disk-cache=32M",
            "--file-allocation=none",
            "--log-level=warn",
            "--console-log-level=warn",
        ]
        self.process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.PIPE,
        )
        self.client = httpx.AsyncClient(timeout=10)
        for _ in range(30):
            if self.process.returncode is not None:
                return False
            try:
                await self.rpc("aria2.getVersion")
                self.available = True
                return True
            except Exception:
                await asyncio.sleep(0.1)
        await self.stop()
        return False

    async def stop(self) -> None:
        if self.available:
            try:
                await self.rpc("aria2.saveSession")
                await self.rpc("aria2.shutdown")
            except Exception:
                pass
        if self.process and self.process.returncode is None:
            try:
                await asyncio.wait_for(self.process.wait(), timeout=3)
            except TimeoutError:
                self.process.terminate()
                await self.process.wait()
        if self.client:
            await self.client.aclose()
        self.available = False

    async def rpc(self, method: str, *params: Any) -> Any:
        if not self.client or not self.port:
            raise RuntimeError("aria2 RPC çalışmıyor")
        body = {
            "jsonrpc": "2.0",
            "id": secrets.token_hex(6),
            "method": method,
            "params": [f"token:{self.secret}", *params],
        }
        response = await self.client.post(f"http://127.0.0.1:{self.port}/jsonrpc", json=body)
        response.raise_for_status()
        data = response.json()
        if "error" in data:
            raise RuntimeError(data["error"].get("message", "aria2 RPC hatası"))
        return data.get("result")

    @staticmethod
    def _free_loopback_port() -> int:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])


class DirectDownloadEngine:
    def __init__(
        self,
        settings: AppSettings,
        supervisor: Aria2Supervisor,
    ):
        self.settings = settings
        self.supervisor = supervisor
        self._fallback_controls: dict[str, tuple[asyncio.Event, asyncio.Event]] = {}
        self._job_gids: dict[str, str] = {}
        self._desired_states: dict[str, str] = {}
        self._allocation_lock = asyncio.Lock()

    async def download(self, job: DownloadJob, progress: ProgressCallback) -> str:
        if self.supervisor.available:
            return await self._download_aria2(job, progress)
        return await self._download_fallback(job, progress)

    async def pause(self, job_id: str) -> None:
        self._desired_states[job_id] = "paused"
        gid = self._job_gids.get(job_id)
        if gid and self.supervisor.available:
            with suppress(RuntimeError):
                await self.supervisor.rpc("aria2.pause", gid)
        control = self._fallback_controls.get(job_id)
        if control:
            control[0].clear()

    async def resume(self, job_id: str) -> None:
        if self._desired_states.get(job_id) == "paused":
            self._desired_states.pop(job_id, None)
        gid = self._job_gids.get(job_id)
        if gid and self.supervisor.available:
            with suppress(RuntimeError):
                await self.supervisor.rpc("aria2.unpause", gid)
        control = self._fallback_controls.get(job_id)
        if control:
            control[0].set()

    async def cancel(self, job_id: str) -> None:
        self._desired_states[job_id] = "cancelled"
        gid = self._job_gids.get(job_id)
        if gid and self.supervisor.available:
            with suppress(RuntimeError):
                await self.supervisor.rpc("aria2.forceRemove", gid)
        control = self._fallback_controls.get(job_id)
        if control:
            control[1].set()
            control[0].set()

    def reset_control(self, job_id: str) -> None:
        self._desired_states.pop(job_id, None)

    async def _download_aria2(self, job: DownloadJob, progress: ProgressCallback) -> str:
        if self._desired_states.get(job.id) == "cancelled":
            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
        options = {
            "dir": str(Path(job.output_path or self.settings.download_dir).parent),
            "out": Path(job.output_path or job.title).name,
            "continue": "true",
            "split": str(self.settings.split_count),
            "max-connection-per-server": str(min(self.settings.split_count, 16)),
            "min-split-size": "1M",
            "allow-overwrite": "false",
            "auto-file-renaming": "true",
        }
        if self.settings.safe_proxy_url:
            options["all-proxy"] = self.settings.safe_proxy_url
        speed_limit = (job.options or {}).get("speed_limit")
        if speed_limit:
            options["max-download-limit"] = speed_limit
        checksum = (job.options or {}).get("sha256")
        if checksum:
            options["checksum"] = f"sha-256={checksum}"
        gid = job.aria2_gid
        if gid:
            try:
                await self.supervisor.rpc("aria2.tellStatus", gid, ["status"])
            except RuntimeError:
                gid = None
        if not gid:
            gid = await self.supervisor.rpc("aria2.addUri", [job.final_url or job.source_url], options)
        self._job_gids[job.id] = gid
        desired_state = self._desired_states.get(job.id)
        if desired_state == "cancelled":
            with suppress(RuntimeError):
                await self.supervisor.rpc("aria2.forceRemove", gid)
            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
        if desired_state == "paused":
            with suppress(RuntimeError):
                await self.supervisor.rpc("aria2.pause", gid)
        await self._rebalance_connections()
        await progress({"aria2_gid": gid})
        try:
            while True:
                state = await self.supervisor.rpc(
                    "aria2.tellStatus",
                    gid,
                    [
                        "status",
                        "totalLength",
                        "completedLength",
                        "downloadSpeed",
                        "errorCode",
                        "errorMessage",
                        "files",
                    ],
                )
                status = state["status"]
                total = int(state.get("totalLength") or 0)
                downloaded = int(state.get("completedLength") or 0)
                speed = int(state.get("downloadSpeed") or 0)
                eta = int((total - downloaded) / speed) if speed and total > downloaded else None
                await progress(
                    {
                        "downloaded_bytes": downloaded,
                        "total_bytes": total or None,
                        "speed_bytes": speed,
                        "eta_seconds": eta,
                        "progress": downloaded / total * 100 if total else 0,
                    }
                )
                if status == "complete":
                    files = state.get("files") or []
                    return files[0]["path"] if files else str(job.output_path)
                if status in {"error", "removed"}:
                    code = state.get("errorCode") or "ARIA2_ERROR"
                    message = state.get("errorMessage") or "aria2 indirmeyi tamamlayamadı"
                    raise DownloadEngineError(f"ARIA2_{code}", message, retryable=code not in {"3", "24"})
                await asyncio.sleep(0.5)
        finally:
            self._job_gids.pop(job.id, None)
            self._desired_states.pop(job.id, None)
            await self._rebalance_connections()

    async def _rebalance_connections(self) -> None:
        if not self.supervisor.available:
            return
        async with self._allocation_lock:
            active = max(1, len(self._job_gids))
            allocated = max(
                1,
                min(self.settings.split_count, self.settings.max_total_connections // active),
            )
            options = {
                "split": str(allocated),
                "max-connection-per-server": str(allocated),
            }
            for gid in tuple(self._job_gids.values()):
                with suppress(RuntimeError):
                    await self.supervisor.rpc("aria2.changeOption", gid, options)

    async def _download_fallback(self, job: DownloadJob, progress: ProgressCallback) -> str:
        """Single-stream recovery path used until the verified aria2 runtime is installed."""

        if self._desired_states.get(job.id) == "cancelled":
            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
        output = Path(job.output_path or self.settings.download_dir / job.category / job.title)
        output.parent.mkdir(parents=True, exist_ok=True)
        partial = output.with_name(output.name + ".downloadhub-part")
        resume_at = partial.stat().st_size if partial.exists() else 0
        pause_event = asyncio.Event()
        pause_event.set()
        cancel_event = asyncio.Event()
        self._fallback_controls[job.id] = (pause_event, cancel_event)
        desired_state = self._desired_states.get(job.id)
        if desired_state == "paused":
            pause_event.clear()
        elif desired_state == "cancelled":
            cancel_event.set()
        headers = {"User-Agent": "DownloadHub/0.1"}
        if resume_at:
            headers["Range"] = f"bytes={resume_at}-"
        started = asyncio.get_running_loop().time()
        last_time, last_downloaded = started, resume_at
        try:
            timeout = httpx.Timeout(None, connect=20, read=60)
            async with (
                httpx.AsyncClient(
                    timeout=timeout,
                    follow_redirects=False,
                    proxy=self.settings.safe_proxy_url,
                    trust_env=False,
                ) as client,
                client.stream("GET", job.final_url or job.source_url, headers=headers) as response,
            ):
                if response.is_redirect:
                    raise DownloadEngineError(
                        "SOURCE_REDIRECT_CHANGED",
                        "Kaynağın yönlendirmesi incelemeden sonra değişti; yeniden inceleyin.",
                        False,
                    )
                if response.status_code in {401, 403, 404, 429}:
                    code = f"HTTP_{response.status_code}"
                    retryable = response.status_code not in {401, 403, 404, 429}
                    raise DownloadEngineError(code, f"Kaynak {response.status_code} yanıtı verdi", retryable)
                response.raise_for_status()
                if resume_at:
                    response_etag = response.headers.get("etag")
                    response_modified = response.headers.get("last-modified")
                    if job.etag and response_etag and job.etag != response_etag:
                        raise DownloadEngineError(
                            "SOURCE_CHANGED",
                            "Kaynağın ETag değeri değişti; parçalar otomatik birleştirilmedi.",
                            False,
                        )
                    if job.last_modified and response_modified and job.last_modified != response_modified:
                        raise DownloadEngineError(
                            "SOURCE_CHANGED",
                            "Kaynağın son değişiklik tarihi değişti; parçalar otomatik birleştirilmedi.",
                            False,
                        )
                if resume_at and response.status_code != 206:
                    resume_at = 0
                    partial.unlink(missing_ok=True)
                content_length = int(response.headers.get("content-length") or 0)
                total = resume_at + content_length if content_length else job.total_bytes
                mode = "ab" if resume_at else "wb"
                downloaded = resume_at
                with partial.open(mode) as handle:
                    async for chunk in response.aiter_bytes(256 * 1024):
                        await pause_event.wait()
                        if cancel_event.is_set():
                            raise DownloadEngineError("CANCELLED", "İndirme iptal edildi", False)
                        handle.write(chunk)
                        downloaded += len(chunk)
                        now = asyncio.get_running_loop().time()
                        if now - last_time >= 0.5:
                            speed = int((downloaded - last_downloaded) / (now - last_time))
                            eta = int((total - downloaded) / speed) if speed and total else None
                            await progress(
                                {
                                    "downloaded_bytes": downloaded,
                                    "total_bytes": total,
                                    "speed_bytes": speed,
                                    "eta_seconds": eta,
                                    "progress": downloaded / total * 100 if total else 0,
                                }
                            )
                            last_time, last_downloaded = now, downloaded
                    handle.flush()
                    os.fsync(handle.fileno())
            expected_hash = (job.options or {}).get("sha256")
            if expected_hash:
                actual_hash = await asyncio.to_thread(self._sha256, partial)
                if actual_hash != expected_hash:
                    raise DownloadEngineError("CHECKSUM_MISMATCH", "SHA-256 doğrulaması başarısız", False)
            final_output = unique_path(output) if output.exists() else output
            os.replace(partial, final_output)
            await progress(
                {
                    "downloaded_bytes": final_output.stat().st_size,
                    "total_bytes": final_output.stat().st_size,
                    "speed_bytes": 0,
                    "eta_seconds": 0,
                    "progress": 100,
                    "fallback": True,
                }
            )
            return str(final_output)
        except httpx.HTTPStatusError as exc:
            status = exc.response.status_code
            raise DownloadEngineError(
                f"HTTP_{status}",
                f"Kaynak {status} yanıtı verdi",
                status >= 500,
            ) from exc
        except httpx.TimeoutException as exc:
            raise DownloadEngineError("NETWORK_TIMEOUT", "Kaynak zaman aşımına uğradı", True) from exc
        except httpx.RequestError as exc:
            raise DownloadEngineError("NETWORK_ERROR", "Kaynağa bağlanılamadı", True) from exc
        except OSError as exc:
            if exc.errno == errno.ENOSPC:
                raise DownloadEngineError("DISK_FULL", "Diskte yeterli boş alan yok", False) from exc
            if exc.errno in {errno.EACCES, errno.EPERM}:
                raise DownloadEngineError(
                    "PERMISSION_DENIED", "İndirme klasörüne yazılamıyor", False
                ) from exc
            raise DownloadEngineError("FILESYSTEM_ERROR", str(exc), False) from exc
        finally:
            self._fallback_controls.pop(job.id, None)
            self._desired_states.pop(job.id, None)

    @staticmethod
    def _sha256(path: Path) -> str:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
