from __future__ import annotations

import hashlib
import json
import re
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.orm import selectinload

from .config import AppSettings
from .db import Database
from .events import EventBroker
from .inspection import DIRECT_EXTENSIONS, MEDIA_HOST_PATTERNS, InspectionService
from .models import AppSetting, DownloadJob, JobItem
from .schemas import (
    JobCreate,
    JobEngine,
    JobRead,
    JobsPage,
    JobStatus,
    SettingsRead,
    SettingsUpdate,
)
from .security import (
    ensure_allowed_path,
    has_sensitive_query,
    redact_url,
    sanitize_filename,
    unique_path,
    validate_http_url,
)

CATEGORY_EXTENSIONS = {
    "Videolar": {".avi", ".mkv", ".mov", ".mp4", ".webm"},
    "Müzik": {".aac", ".flac", ".m4a", ".mp3", ".ogg", ".opus", ".wav"},
    "Resimler": {".avif", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp"},
    "Belgeler": {".csv", ".doc", ".docx", ".epub", ".pdf", ".ppt", ".pptx", ".txt", ".xls", ".xlsx"},
    "Arşivler": {".7z", ".dmg", ".gz", ".iso", ".pkg", ".rar", ".tar", ".tgz", ".zip"},
}


class DownloadService:
    def __init__(
        self,
        settings: AppSettings,
        database: Database,
        inspections: InspectionService,
        events: EventBroker,
        transient_urls: dict[str, tuple[str, str | None]],
    ):
        self.settings = settings
        self.database = database
        self.inspections = inspections
        self.events = events
        self.transient_urls = transient_urls

    async def apply_persisted_settings(self) -> None:
        """Apply the type-safe settings kept in SQLite before workers start."""

        async with self.database.sessions() as session:
            rows = (await session.scalars(select(AppSetting))).all()
        values = {row.key: row.value for row in rows}
        download_dir = values.get("download_dir")
        if isinstance(download_dir, str) and download_dir:
            path = Path(download_dir).expanduser().resolve()
            path.mkdir(parents=True, exist_ok=True)
            self.settings.download_dir = path
            self._prepare_categories(path)
        expected_types = {
            "max_concurrent_jobs": int,
            "max_total_connections": int,
            "split_count": int,
            "global_speed_limit": str,
            "timezone": str,
            "allow_private_networks": bool,
        }
        for key, expected_type in expected_types.items():
            value = values.get(key)
            if isinstance(value, expected_type):
                setattr(self.settings, key, value)

    async def create_job(
        self,
        request: JobCreate,
        *,
        idempotency_key: str | None = None,
    ) -> DownloadJob:
        raw_url = await validate_http_url(
            str(request.url), allow_private=self.settings.allow_private_networks
        )
        cached = self.inspections.get_cached(request.inspection_id)
        if cached and cached.response.url != raw_url:
            raise HTTPException(status_code=409, detail="İnceleme sonucu bu URL ile eşleşmiyor")
        engine = request.engine or (cached.response.engine if cached else self._guess_engine(raw_url))
        if request.format_id:
            if not cached:
                raise HTTPException(status_code=422, detail="Ayrıntılı format için geçerli inceleme gerekir")
            allowed_formats = {item.format_id for item in cached.response.formats}
            if request.format_id not in allowed_formats:
                raise HTTPException(status_code=422, detail="Seçilen format inceleme sonucunda bulunamadı")
        title = request.title or (cached.response.title if cached else self._title_from_url(raw_url))
        category = request.category or self._category(title, engine, request.preset.value)
        selected_positions: list[int] = []
        if cached and request.selected_item_ids:
            selected = set(request.selected_item_ids)
            selected_positions = [
                index for index, item in enumerate(cached.response.items, start=1) if item.id in selected
            ]
        options = {
            "preset": request.preset.value,
            "format_id": request.format_id,
            "subtitle_languages": request.subtitle_languages,
            "write_thumbnail": request.write_thumbnail,
            "write_metadata": request.write_metadata,
            "selected_item_ids": request.selected_item_ids,
            "selected_positions": selected_positions,
            "speed_limit": request.speed_limit,
            "sha256": request.sha256,
            "use_browser_cookies": request.use_browser_cookies,
            "browser_name": request.browser_name.value,
            "browser_profile": request.browser_profile,
            "requires_fresh_source": has_sensitive_query(raw_url),
        }
        stored_url = redact_url(raw_url) if options["requires_fresh_source"] else raw_url
        fingerprint = hashlib.sha256(
            json.dumps(
                {"url": stored_url, "engine": engine.value, "options": options},
                sort_keys=True,
                ensure_ascii=False,
            ).encode("utf-8")
        ).hexdigest()
        async with self.database.sessions() as session:
            if idempotency_key:
                existing = await session.scalar(
                    select(DownloadJob)
                    .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                    .where(DownloadJob.idempotency_key == idempotency_key[:128])
                )
                if existing:
                    return existing
            duplicate = await session.scalar(
                select(DownloadJob)
                .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                .where(
                    DownloadJob.source_fingerprint == fingerprint,
                    DownloadJob.status == JobStatus.COMPLETED.value,
                )
                .order_by(DownloadJob.completed_at.desc())
            )
            if duplicate:
                return duplicate

        now = datetime.now(UTC)
        scheduled_at = request.scheduled_at
        if scheduled_at and scheduled_at.tzinfo is None:
            scheduled_at = scheduled_at.replace(tzinfo=UTC)
        status = (
            JobStatus.SCHEDULED.value
            if scheduled_at and scheduled_at.astimezone(UTC) > now
            else JobStatus.QUEUED.value
        )
        probe = cached.raw if cached else {}
        if engine == JobEngine.DIRECT and not cached:
            probe = await self.inspections._probe_direct(raw_url)
            if request.title is None:
                title = self.inspections._filename(
                    probe.get("content_disposition", ""),
                    probe.get("final_url", raw_url),
                )
                category = request.category or self._category(title, engine, request.preset.value)
        category_dir = ensure_allowed_path(
            self.settings.download_dir / category,
            [self.settings.download_dir],
        )
        output_path: str
        if engine == JobEngine.DIRECT:
            output_path = str(unique_path(category_dir / sanitize_filename(title)))
        else:
            output_path = str(category_dir)

        raw_final_url = probe.get("final_url")
        final_is_sensitive = bool(raw_final_url and has_sensitive_query(raw_final_url))
        options["requires_fresh_source"] = options["requires_fresh_source"] or final_is_sensitive
        job = DownloadJob(
            source_url=stored_url,
            final_url=redact_url(raw_final_url) if final_is_sensitive else raw_final_url,
            source_fingerprint=fingerprint,
            engine=engine.value,
            status=status,
            title=sanitize_filename(title, "Adsız indirme"),
            category=category,
            priority=request.priority,
            total_bytes=cached.response.filesize if cached else probe.get("content_length"),
            scheduled_at=scheduled_at,
            output_path=output_path,
            etag=probe.get("etag"),
            last_modified=probe.get("last_modified"),
            content_type=cached.response.mime_type if cached else probe.get("content_type"),
            idempotency_key=idempotency_key[:128] if idempotency_key else None,
            options=options,
        )
        if cached:
            selected_ids = set(request.selected_item_ids)
            for position, item in enumerate(cached.response.items, start=1):
                job.items.append(
                    JobItem(
                        source_id=item.id,
                        title=item.title,
                        source_url=(
                            redact_url(item.url) if item.url and has_sensitive_query(item.url) else item.url
                        ),
                        position=position,
                        selected=not selected_ids or item.id in selected_ids,
                    )
                )
        async with self.database.sessions.begin() as session:
            session.add(job)
        if options["requires_fresh_source"] or final_is_sensitive:
            self.transient_urls[job.id] = (raw_url, raw_final_url)
        await self.events.publish(
            "job.created",
            {"job": JobRead.model_validate(job).model_dump(mode="json")},
            job.id,
        )
        return job

    async def get_job(self, job_id: str) -> DownloadJob:
        async with self.database.sessions() as session:
            job = await session.scalar(
                select(DownloadJob)
                .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                .where(DownloadJob.id == job_id)
            )
            if not job:
                raise HTTPException(status_code=404, detail="İndirme görevi bulunamadı")
            return job

    async def list_jobs(
        self,
        *,
        status: str | None = None,
        engine: str | None = None,
        category: str | None = None,
        query: str | None = None,
        page: int = 1,
        page_size: int = 50,
    ) -> JobsPage:
        filters = []
        if status:
            statuses = [part.strip() for part in status.split(",") if part.strip()]
            filters.append(DownloadJob.status.in_(statuses))
        if engine:
            filters.append(DownloadJob.engine == engine)
        if category:
            filters.append(DownloadJob.category == category)
        if query:
            term = f"%{query.strip()}%"
            filters.append(or_(DownloadJob.title.ilike(term), DownloadJob.source_url.ilike(term)))
        async with self.database.sessions() as session:
            total = await session.scalar(select(func.count(DownloadJob.id)).where(*filters))
            jobs = (
                await session.scalars(
                    select(DownloadJob)
                    .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                    .where(*filters)
                    .order_by(DownloadJob.created_at.desc())
                    .offset((page - 1) * page_size)
                    .limit(page_size)
                )
            ).all()
        return JobsPage(
            items=[JobRead.model_validate(job) for job in jobs],
            total=total or 0,
            page=page,
            page_size=page_size,
        )

    async def get_settings(self) -> SettingsRead:
        async with self.database.sessions() as session:
            rows = (await session.scalars(select(AppSetting))).all()
        stored = {row.key: row.value for row in rows}
        return SettingsRead(
            download_dir=str(self.settings.download_dir),
            max_concurrent_jobs=self.settings.max_concurrent_jobs,
            max_total_connections=self.settings.max_total_connections,
            split_count=self.settings.split_count,
            global_speed_limit=self.settings.global_speed_limit,
            timezone=self.settings.timezone,
            allow_private_networks=self.settings.allow_private_networks,
            theme=stored.get("theme", "system"),
            browser_name=stored.get("browser_name", "chrome"),
            browser_profile=stored.get("browser_profile") or "Default",
            daily_window_start=stored.get("daily_window_start"),
            daily_window_end=stored.get("daily_window_end"),
        )

    async def update_settings(self, update: SettingsUpdate) -> SettingsRead:
        values = update.model_dump(exclude_unset=True)
        runtime_keys = {
            "max_concurrent_jobs",
            "max_total_connections",
            "split_count",
            "global_speed_limit",
            "timezone",
            "allow_private_networks",
        }
        if "download_dir" in values and values["download_dir"]:
            path = Path(values.pop("download_dir")).expanduser().resolve()
            if path == Path(path.anchor):
                raise HTTPException(status_code=422, detail="Disk kökü indirme klasörü olarak kullanılamaz")
            path.mkdir(parents=True, exist_ok=True)
            if not path.is_dir():
                raise HTTPException(status_code=422, detail="İndirme yolu bir klasör olmalıdır")
            self.settings.download_dir = path
            self._prepare_categories(path)
            values["download_dir"] = str(path)
        if "global_speed_limit" in values and not self._valid_speed_limit(values["global_speed_limit"]):
            raise HTTPException(status_code=422, detail="Hız sınırı 0, 500K, 2M gibi olmalıdır")
        if "timezone" in values:
            try:
                ZoneInfo(values["timezone"])
            except (ZoneInfoNotFoundError, ValueError) as exc:
                raise HTTPException(status_code=422, detail="Geçersiz saat dilimi") from exc
        if "theme" in values and values["theme"] not in {"system", "light", "dark"}:
            raise HTTPException(status_code=422, detail="Geçersiz tema")
        if "browser_profile" in values and not values["browser_profile"]:
            values["browser_profile"] = "Default"
        for key in runtime_keys & values.keys():
            setattr(self.settings, key, values[key])
        async with self.database.sessions.begin() as session:
            if "download_dir" in values:
                roots = await session.get(AppSetting, "download_roots")
                known_roots = list(roots.value) if roots and isinstance(roots.value, list) else []
                if values["download_dir"] not in known_roots:
                    known_roots.append(values["download_dir"])
                if roots:
                    roots.value = known_roots
                else:
                    session.add(AppSetting(key="download_roots", value=known_roots))
            for key, value in values.items():
                row = await session.get(AppSetting, key)
                if row:
                    row.value = value
                else:
                    session.add(AppSetting(key=key, value=value))
        return await self.get_settings()

    async def allowed_download_roots(self) -> list[Path]:
        async with self.database.sessions() as session:
            row = await session.get(AppSetting, "download_roots")
        raw_roots = row.value if row and isinstance(row.value, list) else []
        roots = [Path(value) for value in raw_roots if isinstance(value, str) and value]
        current = self.settings.download_dir
        if current not in roots:
            roots.append(current)
        return roots

    @staticmethod
    def _valid_speed_limit(value: object) -> bool:
        return isinstance(value, str) and bool(
            re.fullmatch(r"0|[1-9]\d*(?:\.\d+)?[KMG]?", value.strip(), re.I)
        )

    @staticmethod
    def _prepare_categories(root: Path) -> None:
        for category in ("Videolar", "Müzik", "Resimler", "Belgeler", "Arşivler", "Diğer"):
            (root / category).mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _guess_engine(url: str) -> JobEngine:
        host = (urlsplit(url).hostname or "").lower()
        if any(host == pattern or host.endswith("." + pattern) for pattern in MEDIA_HOST_PATTERNS):
            return JobEngine.MEDIA
        suffix = Path(urlsplit(url).path).suffix.lower()
        return JobEngine.DIRECT if suffix in DIRECT_EXTENSIONS else JobEngine.MEDIA

    @staticmethod
    def _title_from_url(url: str) -> str:
        return sanitize_filename(Path(urlsplit(url).path).name or urlsplit(url).hostname or "indirme")

    @staticmethod
    def _category(title: str, engine: JobEngine, preset: str) -> str:
        if engine == JobEngine.MEDIA:
            return "Müzik" if preset in {"mp3", "m4a"} else "Videolar"
        suffix = Path(title).suffix.lower()
        for category, extensions in CATEGORY_EXTENSIONS.items():
            if suffix in extensions:
                return category
        return "Diğer"
