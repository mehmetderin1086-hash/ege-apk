from __future__ import annotations

import asyncio
import json
import mimetypes
import re
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urljoin, urlsplit

import httpx
from fastapi import HTTPException

from .config import AppSettings
from .runtime import RuntimeRegistry
from .schemas import (
    FormatInfo,
    InspectRequest,
    InspectResponse,
    JobEngine,
    PlaylistItem,
)
from .security import sanitize_filename, validate_http_url

MEDIA_HOST_PATTERNS = (
    "youtube.com",
    "youtu.be",
    "vimeo.com",
    "dailymotion.com",
    "tiktok.com",
    "twitch.tv",
    "soundcloud.com",
    "instagram.com",
    "x.com",
    "twitter.com",
)
DIRECT_EXTENSIONS = {
    ".7z",
    ".apk",
    ".avi",
    ".csv",
    ".dmg",
    ".doc",
    ".docx",
    ".epub",
    ".gif",
    ".gz",
    ".iso",
    ".jpeg",
    ".jpg",
    ".json",
    ".m4a",
    ".mkv",
    ".mov",
    ".mp3",
    ".mp4",
    ".pdf",
    ".pkg",
    ".png",
    ".ppt",
    ".pptx",
    ".rar",
    ".tar",
    ".tgz",
    ".txt",
    ".wav",
    ".webm",
    ".webp",
    ".xls",
    ".xlsx",
    ".xml",
    ".zip",
}


@dataclass
class CachedInspection:
    response: InspectResponse
    raw: dict[str, Any]
    expires_at: float


class InspectionService:
    def __init__(self, settings: AppSettings, runtime: RuntimeRegistry):
        self.settings = settings
        self.runtime = runtime
        self.cache: dict[str, CachedInspection] = {}

    def get_cached(self, inspection_id: str | None) -> CachedInspection | None:
        if not inspection_id:
            return None
        cached = self.cache.get(inspection_id)
        if not cached or cached.expires_at < time.monotonic():
            self.cache.pop(inspection_id, None)
            return None
        return cached

    async def inspect(self, request: InspectRequest) -> InspectResponse:
        raw_url = await validate_http_url(
            str(request.url), allow_private=self.settings.allow_private_networks
        )
        host = (urlsplit(raw_url).hostname or "").lower()
        suffix = Path(urlsplit(raw_url).path).suffix.lower()
        if any(host == pattern or host.endswith("." + pattern) for pattern in MEDIA_HOST_PATTERNS):
            return await self._inspect_media(raw_url, request)
        if suffix in DIRECT_EXTENSIONS:
            return await self._inspect_direct(raw_url)

        direct = await self._probe_direct(raw_url)
        content_type = direct.get("content_type", "")
        disposition = direct.get("content_disposition", "")
        final_suffix = Path(urlsplit(direct.get("final_url", raw_url)).path).suffix.lower()
        if (
            "attachment" in disposition.lower()
            or final_suffix in DIRECT_EXTENSIONS
            or content_type.startswith("application/")
            or content_type.startswith("image/")
        ) and content_type not in {"application/vnd.apple.mpegurl", "application/x-mpegurl"}:
            return self._direct_response(raw_url, direct)
        return await self._inspect_media(raw_url, request, direct_probe=direct)

    async def _probe_direct(self, url: str) -> dict[str, Any]:
        timeout = httpx.Timeout(20, connect=10)
        headers = {"User-Agent": "DownloadHub/0.1"}
        try:
            async with httpx.AsyncClient(
                timeout=timeout,
                follow_redirects=False,
                proxy=self.settings.safe_proxy_url,
                trust_env=False,
            ) as client:
                current_url = url
                for _ in range(9):
                    await validate_http_url(current_url, allow_private=self.settings.allow_private_networks)
                    response = await client.head(current_url, headers=headers)
                    if response.status_code in {405, 501}:
                        response = await client.get(current_url, headers={**headers, "Range": "bytes=0-0"})
                    if response.is_redirect:
                        location = response.headers.get("location")
                        if not location:
                            raise HTTPException(status_code=422, detail="Geçersiz yönlendirme")
                        current_url = urljoin(current_url, location)
                        continue
                    response.raise_for_status()
                    return {
                        "final_url": str(response.url),
                        "content_type": response.headers.get("content-type", "").split(";", 1)[0],
                        "content_disposition": response.headers.get("content-disposition", ""),
                        "content_length": self._integer_header(response.headers.get("content-length")),
                        "etag": response.headers.get("etag"),
                        "last_modified": response.headers.get("last-modified"),
                    }
                raise HTTPException(status_code=422, detail="Çok fazla HTTP yönlendirmesi")
        except httpx.HTTPStatusError as exc:
            raise HTTPException(
                status_code=422,
                detail=f"Kaynak {exc.response.status_code} yanıtı verdi",
            ) from exc
        except httpx.HTTPError as exc:
            raise HTTPException(status_code=422, detail=f"Kaynak incelenemedi: {exc}") from exc

    async def _inspect_direct(self, url: str) -> InspectResponse:
        return self._direct_response(url, await self._probe_direct(url))

    def _direct_response(self, url: str, probe: dict[str, Any]) -> InspectResponse:
        final_url = probe.get("final_url", url)
        title = self._filename(probe.get("content_disposition", ""), final_url)
        response = InspectResponse(
            inspection_id=uuid.uuid4().hex,
            source_type="direct",
            engine=JobEngine.DIRECT,
            url=url,
            title=title,
            filesize=probe.get("content_length"),
            mime_type=probe.get("content_type"),
        )
        self.cache[response.inspection_id] = CachedInspection(
            response=response,
            raw=probe,
            expires_at=time.monotonic() + 900,
        )
        return response

    async def _inspect_media(
        self,
        url: str,
        request: InspectRequest,
        direct_probe: dict[str, Any] | None = None,
    ) -> InspectResponse:
        command = self.runtime.yt_dlp_command()
        if not command:
            title = sanitize_filename(Path(urlsplit(url).path).name or urlsplit(url).hostname or "Medya")
            response = InspectResponse(
                inspection_id=uuid.uuid4().hex,
                source_type="media",
                engine=JobEngine.MEDIA,
                url=url,
                title=title,
                warnings=["yt-dlp kurulmadığı için format bilgileri alınamadı."],
            )
            self.cache[response.inspection_id] = CachedInspection(
                response=response,
                raw=direct_probe or {},
                expires_at=time.monotonic() + 300,
            )
            return response

        args = [
            *command,
            "--ignore-config",
            "--dump-single-json",
            "--skip-download",
            "--no-warnings",
            "--playlist-end",
            "500",
        ]
        deno = self.runtime.deno()
        if deno:
            args.extend(["--js-runtimes", f"deno:{deno}"])
        if self.settings.safe_proxy_url:
            args.extend(["--proxy", self.settings.safe_proxy_url])
        if request.use_browser_cookies:
            profile = request.browser_profile or "Default"
            args.extend(["--cookies-from-browser", f"{request.browser_name.value}:{profile}"])
        args.append(url)
        process = await asyncio.create_subprocess_exec(
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=90)
        except TimeoutError as exc:
            process.kill()
            await process.wait()
            raise HTTPException(status_code=504, detail="Medya incelemesi zaman aşımına uğradı") from exc
        if process.returncode != 0:
            message = self._safe_error(stderr.decode("utf-8", "replace"))
            raise HTTPException(status_code=422, detail=message)
        try:
            info = json.loads(stdout)
        except json.JSONDecodeError as exc:
            raise HTTPException(status_code=502, detail="yt-dlp geçersiz inceleme sonucu döndürdü") from exc

        formats = []
        for item in info.get("formats") or []:
            format_id = str(item.get("format_id") or "")
            if not format_id:
                continue
            resolution = item.get("resolution") or (f"{item.get('height')}p" if item.get("height") else None)
            label_parts = [format_id, resolution, item.get("ext")]
            formats.append(
                FormatInfo(
                    format_id=format_id,
                    label=" · ".join(str(part) for part in label_parts if part),
                    extension=item.get("ext"),
                    resolution=resolution,
                    video_codec=item.get("vcodec"),
                    audio_codec=item.get("acodec"),
                    filesize=item.get("filesize") or item.get("filesize_approx"),
                )
            )
        entries = info.get("entries") or []
        playlist_items = [
            PlaylistItem(
                id=str(item.get("id") or index),
                title=item.get("title") or f"Öğe {index + 1}",
                url=item.get("webpage_url") or item.get("url"),
                duration=item.get("duration"),
                thumbnail=item.get("thumbnail"),
            )
            for index, item in enumerate(entries)
            if item
        ]
        subtitles = sorted(
            set((info.get("subtitles") or {}).keys()) | set((info.get("automatic_captions") or {}).keys())
        )
        source_type = "playlist" if entries else "media"
        if info.get("_type") in {"playlist", "multi_video"} and info.get("channel"):
            source_type = "channel"
        response = InspectResponse(
            inspection_id=uuid.uuid4().hex,
            source_type=source_type,
            engine=JobEngine.MEDIA,
            url=url,
            title=info.get("title") or "Adsız medya",
            thumbnail=info.get("thumbnail"),
            uploader=info.get("uploader") or info.get("channel"),
            duration=info.get("duration"),
            filesize=info.get("filesize") or info.get("filesize_approx"),
            formats=formats,
            subtitles=subtitles,
            items=playlist_items,
        )
        self.cache[response.inspection_id] = CachedInspection(
            response=response,
            raw=info,
            expires_at=time.monotonic() + 900,
        )
        return response

    @staticmethod
    def _filename(disposition: str, url: str) -> str:
        extended = re.search(r"filename\*=(?:UTF-8'')?([^;]+)", disposition, re.I)
        regular = re.search(r'filename="?([^";]+)', disposition, re.I)
        raw = extended.group(1) if extended else regular.group(1) if regular else ""
        if not raw:
            raw = unquote(Path(urlsplit(url).path).name)
        if not raw:
            extension = mimetypes.guess_extension("application/octet-stream") or ""
            raw = "indirme" + extension
        return sanitize_filename(raw.strip('"'))

    @staticmethod
    def _integer_header(value: str | None) -> int | None:
        try:
            return int(value) if value else None
        except ValueError:
            return None

    @staticmethod
    def _safe_error(message: str) -> str:
        lines = [line.strip() for line in message.splitlines() if line.strip()]
        result = lines[-1] if lines else "Medya kaynağı incelenemedi"
        result = re.sub(r"(?i)(cookie|token|authorization)=\S+", r"\1=[GİZLİ]", result)
        if "Sign in to confirm" in result or "cookies" in result.lower():
            return "Kaynak oturum doğrulaması istiyor. Tarayıcı oturumunu kullanmayı deneyin."
        return result[:800]
