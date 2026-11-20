from __future__ import annotations

import asyncio
import shutil
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select, update
from sqlalchemy.orm import selectinload

from .config import AppSettings
from .db import Database
from .engines.aria2 import DirectDownloadEngine, DownloadEngineError
from .engines.media import MediaDownloadEngine
from .events import EventBroker
from .models import AppSetting, Artifact, DownloadJob, JobItem
from .schemas import JobStatus
from .security import redact_sensitive_text, unique_path


class QueueManager:
    def __init__(
        self,
        settings: AppSettings,
        database: Database,
        events: EventBroker,
        direct: DirectDownloadEngine,
        media: MediaDownloadEngine,
        transient_urls: dict[str, tuple[str, str | None]],
    ):
        self.settings = settings
        self.database = database
        self.events = events
        self.direct = direct
        self.media = media
        self.transient_urls = transient_urls
        self._scheduler: asyncio.Task[None] | None = None
        self._active: dict[str, asyncio.Task[None]] = {}
        self._stopping = False

    async def start(self) -> None:
        self._stopping = False
        self._scheduler = asyncio.create_task(self._run_scheduler(), name="downloadhub-scheduler")

    async def stop(self) -> None:
        self._stopping = True
        if self._scheduler:
            self._scheduler.cancel()
            await asyncio.gather(self._scheduler, return_exceptions=True)
        for job_id in tuple(self._active):
            await self._cancel_engine(job_id)
        await asyncio.gather(*self._active.values(), return_exceptions=True)
        await self.database.mark_active_interrupted()

    async def pause(self, job_id: str) -> DownloadJob:
        job = await self._get_job(job_id)
        if job.status == JobStatus.PAUSED.value:
            return job
        if job.status not in {
            JobStatus.DOWNLOADING.value,
            JobStatus.QUEUED.value,
            JobStatus.SCHEDULED.value,
            JobStatus.RETRY_WAIT.value,
            JobStatus.INTERRUPTED.value,
        }:
            raise DownloadEngineError("INVALID_STATE", "Bu görev duraklatılamaz", False)
        if job.engine == "direct":
            await self.direct.pause(job_id)
        else:
            await self.media.pause(job_id)
        await self._set_status(job_id, JobStatus.PAUSED.value)
        return await self._get_job(job_id)

    async def resume(self, job_id: str) -> DownloadJob:
        job = await self._get_job(job_id)
        if job.status == JobStatus.DOWNLOADING.value:
            return job
        if job.status != JobStatus.PAUSED.value:
            raise DownloadEngineError("INVALID_STATE", "Yalnız duraklatılmış görev sürdürülebilir", False)
        if job.engine == "direct":
            await self.direct.resume(job_id)
        else:
            await self.media.resume(job_id)
        active_task = self._active.get(job_id)
        if active_task and not active_task.done():
            await self._set_status(job_id, JobStatus.DOWNLOADING.value)
        else:
            await self._set_status(job_id, JobStatus.QUEUED.value)
        return await self._get_job(job_id)

    async def cancel(self, job_id: str, *, keep_partial: bool = True) -> DownloadJob:
        job = await self._get_job(job_id)
        if job.status == JobStatus.CANCELLED.value:
            return job
        if job.status in {JobStatus.COMPLETED.value, JobStatus.FAILED.value}:
            raise DownloadEngineError("INVALID_STATE", "Tamamlanmış görev iptal edilemez", False)
        discard_primary = False
        if job.engine == "direct" and job.output_path:
            output = Path(job.output_path)
            discard_primary = job.downloaded_bytes > 0 or output.with_name(output.name + ".aria2").is_file()
        await self._cancel_engine(job_id)
        await self._set_status(job_id, JobStatus.CANCELLED.value)
        if not keep_partial:
            moved = await asyncio.to_thread(
                self._move_partials_to_trash,
                job,
                discard_primary=discard_primary,
            )
            await self.events.publish(
                "job.partials_discarded",
                {"job_id": job_id, "moved": moved},
                job_id,
            )
        self.transient_urls.pop(job_id, None)
        return await self._get_job(job_id)

    async def set_priority(self, job_id: str, priority: int) -> DownloadJob:
        job = await self._get_job(job_id)
        if job.status in {JobStatus.COMPLETED.value, JobStatus.CANCELLED.value}:
            raise DownloadEngineError("INVALID_STATE", "Bu görevin önceliği değiştirilemez", False)
        async with self.database.sessions.begin() as session:
            await session.execute(
                update(DownloadJob).where(DownloadJob.id == job_id).values(priority=priority)
            )
        await self.events.publish(
            "job.priority",
            {"job_id": job_id, "priority": priority},
            job_id,
        )
        return await self._get_job(job_id)

    async def retry(self, job_id: str) -> DownloadJob:
        job = await self._get_job(job_id)
        if job.status not in {
            JobStatus.FAILED.value,
            JobStatus.CANCELLED.value,
            JobStatus.INTERRUPTED.value,
        }:
            raise DownloadEngineError("INVALID_STATE", "Bu görev yeniden denenemez", False)
        if job.engine == "direct":
            self.direct.reset_control(job_id)
        else:
            self.media.reset_control(job_id)
        async with self.database.sessions.begin() as session:
            await session.execute(
                update(DownloadJob)
                .where(DownloadJob.id == job_id)
                .values(
                    status=JobStatus.QUEUED.value,
                    error_code=None,
                    error_message=None,
                    scheduled_at=None,
                )
            )
        await self.events.publish("job.state", {"job_id": job_id, "status": "queued"}, job_id)
        return await self._get_job(job_id)

    async def _run_scheduler(self) -> None:
        while not self._stopping:
            try:
                for job_id, task in tuple(self._active.items()):
                    if task.done():
                        await asyncio.gather(task, return_exceptions=True)
                        self._active.pop(job_id, None)
                capacity = max(0, self.settings.max_concurrent_jobs - len(self._active))
                if capacity and await self._within_daily_window():
                    due = await self._due_jobs(capacity)
                    for job in due:
                        if job.id in self._active:
                            continue
                        task = asyncio.create_task(self._run_job(job.id), name=f"download-{job.id}")
                        self._active[job.id] = task
                await asyncio.sleep(0.5)
            except asyncio.CancelledError:
                raise
            except Exception:
                await asyncio.sleep(1)

    async def _due_jobs(self, limit: int) -> list[DownloadJob]:
        now = datetime.now(UTC)
        async with self.database.sessions() as session:
            return list(
                (
                    await session.scalars(
                        select(DownloadJob)
                        .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                        .where(
                            or_(
                                DownloadJob.status.in_(["queued", "interrupted"]),
                                (
                                    DownloadJob.status.in_(["scheduled", "retry_wait"])
                                    & (DownloadJob.scheduled_at <= now)
                                ),
                            )
                        )
                        .order_by(DownloadJob.priority.desc(), DownloadJob.created_at.asc())
                        .limit(limit)
                    )
                ).all()
            )

    async def _run_job(self, job_id: str) -> None:
        if not await self._claim_job(job_id):
            return
        job = await self._get_job(job_id)
        transient = self.transient_urls.get(job_id)
        if (job.options or {}).get("requires_fresh_source") and not transient:
            await self._fail(
                job_id,
                "SOURCE_CREDENTIAL_EXPIRED",
                "Gizli sorgu bilgisi kalıcı olarak saklanmadı; URL'yi yeniden inceleyip görev oluşturun.",
            )
            return
        if transient:
            job.source_url, job.final_url = transient
        await self._ensure_output_confined(job)
        last_saved = 0.0

        async def progress(values: dict) -> None:
            nonlocal last_saved
            now = asyncio.get_running_loop().time()
            force = values.get("progress") == 100 or "aria2_gid" in values
            if not force and now - last_saved < 1.0:
                return
            last_saved = now
            allowed = {
                key: value
                for key, value in values.items()
                if key
                in {
                    "progress",
                    "downloaded_bytes",
                    "total_bytes",
                    "speed_bytes",
                    "eta_seconds",
                    "aria2_gid",
                }
            }
            async with self.database.sessions.begin() as session:
                await session.execute(update(DownloadJob).where(DownloadJob.id == job_id).values(**allowed))
            await self.events.publish("job.progress", {"job_id": job_id, **allowed}, job_id)

        async def stage(value: str) -> None:
            if value == "postprocessing":
                await self._set_status(job_id, JobStatus.POSTPROCESSING.value)

        try:
            if job.engine == "direct":
                download_result: str | list[str] = await self.direct.download(job, progress)
            else:
                download_result = await self.media.download(job, progress, stage)
            primary_paths = [download_result] if isinstance(download_result, str) else download_result
            artifact_paths = self._collect_artifact_paths(job, primary_paths)
            if not artifact_paths:
                raise DownloadEngineError("OUTPUT_NOT_FOUND", "Çıktı dosyası bulunamadı", False)
            path = Path(primary_paths[-1]).expanduser().resolve()
            if path not in artifact_paths:
                raise DownloadEngineError("OUTPUT_NOT_FOUND", "Ana çıktı dosyası bulunamadı", False)
            async with self.database.sessions.begin() as session:
                current = await session.get(DownloadJob, job_id)
                if not current or current.status == JobStatus.CANCELLED.value:
                    return
                current.status = JobStatus.COMPLETED.value
                current.progress = 100.0
                current.speed_bytes = 0
                current.eta_seconds = 0
                current.output_path = str(path)
                current.completed_at = datetime.now(UTC)
                for artifact_path in artifact_paths:
                    session.add(
                        Artifact(
                            job_id=job_id,
                            kind=self._artifact_kind(artifact_path),
                            path=str(artifact_path),
                            size_bytes=artifact_path.stat().st_size,
                            sha256=(job.options or {}).get("sha256") if job.engine == "direct" else None,
                        )
                    )
                failed_item_ids: list[str] = []
                if job.items:
                    successful_ids = self._successful_item_ids(job, artifact_paths)
                    for item in job.items:
                        if not item.selected:
                            continue
                        stored_item = await session.get(JobItem, item.id)
                        if not stored_item:
                            continue
                        if item.source_id in successful_ids:
                            stored_item.status = JobStatus.COMPLETED.value
                            stored_item.error_message = None
                        else:
                            stored_item.status = JobStatus.FAILED.value
                            stored_item.error_message = "Bu oynatma listesi öğesi indirilemedi"
                            failed_item_ids.append(item.source_id)
            await self.events.publish("job.completed", {"job_id": job_id, "output_path": str(path)}, job_id)
            if failed_item_ids:
                await self.events.publish(
                    "job.items_failed",
                    {"job_id": job_id, "count": len(failed_item_ids), "item_ids": failed_item_ids[:100]},
                    job_id,
                )
            self.transient_urls.pop(job_id, None)
        except asyncio.CancelledError:
            raise
        except DownloadEngineError as exc:
            current = await self._get_job(job_id)
            if current.status == JobStatus.CANCELLED.value or exc.code == "CANCELLED":
                return
            safe_message = redact_sensitive_text(str(exc))[:1000]
            delays = self.settings.retry_delays
            if exc.retryable and current.retry_count < len(delays):
                delay = delays[current.retry_count]
                async with self.database.sessions.begin() as session:
                    await session.execute(
                        update(DownloadJob)
                        .where(DownloadJob.id == job_id)
                        .values(
                            status=JobStatus.RETRY_WAIT.value,
                            retry_count=current.retry_count + 1,
                            scheduled_at=datetime.now(UTC) + timedelta(seconds=delay),
                            error_code=exc.code,
                            error_message=safe_message,
                            speed_bytes=0,
                        )
                    )
                await self.events.publish(
                    "job.retry_wait",
                    {"job_id": job_id, "delay": delay, "error": safe_message},
                    job_id,
                )
            else:
                await self._fail(job_id, exc.code, safe_message)
        except Exception as exc:
            await self._fail(job_id, "INTERNAL_ERROR", str(exc))

    async def _fail(self, job_id: str, code: str, message: str) -> None:
        safe_message = redact_sensitive_text(message)[:1000]
        async with self.database.sessions.begin() as session:
            await session.execute(
                update(DownloadJob)
                .where(DownloadJob.id == job_id)
                .values(
                    status=JobStatus.FAILED.value,
                    error_code=code,
                    error_message=safe_message,
                    speed_bytes=0,
                    eta_seconds=None,
                )
            )
            await session.execute(
                update(JobItem)
                .where(JobItem.job_id == job_id, JobItem.selected.is_(True))
                .values(status=JobStatus.FAILED.value, error_message=safe_message)
            )
        await self.events.publish(
            "job.failed", {"job_id": job_id, "code": code, "message": safe_message}, job_id
        )

    async def _claim_job(self, job_id: str) -> bool:
        """Atomically move only a still-runnable due job into downloading."""

        now = datetime.now(UTC)
        async with self.database.sessions.begin() as session:
            result = await session.execute(
                update(DownloadJob)
                .where(
                    DownloadJob.id == job_id,
                    or_(
                        DownloadJob.status.in_([JobStatus.QUEUED.value, JobStatus.INTERRUPTED.value]),
                        (
                            DownloadJob.status.in_([JobStatus.SCHEDULED.value, JobStatus.RETRY_WAIT.value])
                            & (DownloadJob.scheduled_at <= now)
                        ),
                    ),
                )
                .values(
                    status=JobStatus.DOWNLOADING.value,
                    started_at=now,
                    error_code=None,
                    error_message=None,
                )
            )
            claimed = result.rowcount == 1
        if claimed:
            await self.events.publish(
                "job.state",
                {"job_id": job_id, "status": JobStatus.DOWNLOADING.value},
                job_id,
            )
        return claimed

    async def _get_job(self, job_id: str) -> DownloadJob:
        async with self.database.sessions() as session:
            job = await session.scalar(
                select(DownloadJob)
                .options(selectinload(DownloadJob.items), selectinload(DownloadJob.artifacts))
                .where(DownloadJob.id == job_id)
            )
            if not job:
                raise DownloadEngineError("NOT_FOUND", "İndirme görevi bulunamadı", False)
            return job

    async def _set_status(self, job_id: str, status: str, started: bool = False) -> None:
        async with self.database.sessions.begin() as session:
            job = await session.get(DownloadJob, job_id)
            if not job:
                return
            job.status = status
            if status != "downloading":
                job.speed_bytes = 0
            if started:
                job.started_at = datetime.now(UTC)
                job.error_code = None
                job.error_message = None
        await self.events.publish("job.state", {"job_id": job_id, "status": status}, job_id)

    async def _cancel_engine(self, job_id: str) -> None:
        job = await self._get_job(job_id)
        if job.engine == "direct":
            await self.direct.cancel(job_id)
        else:
            await self.media.cancel(job_id)

    async def _ensure_output_confined(self, job: DownloadJob) -> None:
        if not job.output_path:
            raise DownloadEngineError("OUTPUT_PATH_VIOLATION", "Görevin güvenli çıktı yolu yok", False)
        async with self.database.sessions() as session:
            row = await session.get(AppSetting, "download_roots")
        raw_roots = row.value if row and isinstance(row.value, list) else []
        roots = [Path(value).expanduser().absolute() for value in raw_roots if isinstance(value, str)]
        current_root = self.settings.download_dir.expanduser().absolute()
        if current_root not in roots:
            roots.append(current_root)
        resolved_output = Path(job.output_path).expanduser().resolve(strict=False)
        for root in roots:
            try:
                resolved_output.relative_to(root)
                return
            except ValueError:
                continue
        raise DownloadEngineError(
            "OUTPUT_PATH_VIOLATION",
            "Çıktı yolu izin verilen indirme kökünün dışına çıkıyor",
            False,
        )

    async def _within_daily_window(self) -> bool:
        async with self.database.sessions() as session:
            rows = (
                await session.scalars(
                    select(AppSetting).where(AppSetting.key.in_(["daily_window_start", "daily_window_end"]))
                )
            ).all()
        values = {row.key: row.value for row in rows}
        start, end = values.get("daily_window_start"), values.get("daily_window_end")
        if not start or not end:
            return True
        try:
            now = datetime.now(ZoneInfo(self.settings.timezone)).time()
            start_time = datetime.strptime(start, "%H:%M").time()
            end_time = datetime.strptime(end, "%H:%M").time()
        except (ValueError, KeyError):
            return True
        if start_time <= end_time:
            return start_time <= now <= end_time
        return now >= start_time or now <= end_time

    def _collect_artifact_paths(self, job: DownloadJob, primary_paths: list[str]) -> list[Path]:
        allowed_root = self.settings.download_dir.resolve()
        collected: dict[str, Path] = {}
        for raw_path in primary_paths:
            primary = Path(raw_path).expanduser().resolve()
            candidates = [primary]
            if job.engine == "media" and primary.parent.is_dir():
                prefix = f"{primary.stem}."
                candidates.extend(
                    candidate for candidate in primary.parent.iterdir() if candidate.name.startswith(prefix)
                )
            for candidate in candidates:
                resolved = candidate.resolve()
                try:
                    resolved.relative_to(allowed_root)
                except ValueError as exc:
                    raise DownloadEngineError(
                        "OUTPUT_PATH_VIOLATION",
                        "Motor izin verilen indirme klasörü dışında çıktı bildirdi",
                        False,
                    ) from exc
                if resolved.is_file() and not resolved.name.endswith((".part", ".ytdl")):
                    collected[str(resolved)] = resolved
        return list(collected.values())

    @staticmethod
    def _successful_item_ids(job: DownloadJob, artifact_paths: list[Path]) -> set[str]:
        return {
            item.source_id
            for item in job.items
            if item.selected
            and any(f"[{item.source_id}]" in artifact_path.name for artifact_path in artifact_paths)
        }

    def _move_partials_to_trash(self, job: DownloadJob, *, discard_primary: bool = False) -> int:
        candidates: set[Path] = set()
        if job.engine == "direct" and job.output_path:
            output = Path(job.output_path)
            candidates.update(
                {
                    output.with_name(output.name + ".aria2"),
                    output.with_name(output.name + ".downloadhub-part"),
                }
            )
            if discard_primary:
                candidates.add(output)
        elif job.engine == "media" and job.output_path:
            identifiers = set((job.options or {}).get("selected_item_ids") or [])
            video_id = parse_qs(urlsplit(job.source_url).query).get("v", [])
            identifiers.update(video_id)
            root = Path(job.output_path)
            if root.is_dir() and identifiers:
                for candidate in root.rglob("*"):
                    if candidate.name.endswith((".part", ".ytdl")) and any(
                        f"[{identifier}]" in candidate.name for identifier in identifiers
                    ):
                        candidates.add(candidate)

        trash = Path.home() / ".Trash"
        if not trash.is_dir():
            return 0
        allowed_root = self.settings.download_dir.resolve()
        moved = 0
        for candidate in candidates:
            try:
                resolved = candidate.resolve()
                resolved.relative_to(allowed_root)
            except (OSError, ValueError):
                continue
            if not resolved.is_file() or resolved.is_symlink():
                continue
            destination = unique_path(trash / resolved.name)
            try:
                shutil.move(str(resolved), str(destination))
            except OSError:
                continue
            moved += 1
        return moved

    @staticmethod
    def _artifact_kind(path: Path) -> str:
        name = path.name.lower()
        suffix = path.suffix.lower()
        if name.endswith(".info.json"):
            return "metadata"
        if suffix in {".vtt", ".srt", ".ass", ".lrc"}:
            return "subtitle"
        if suffix in {".jpg", ".jpeg", ".png", ".webp", ".avif"}:
            return "thumbnail"
        if suffix in {".mp3", ".m4a", ".aac", ".flac", ".ogg", ".opus", ".wav"}:
            return "audio"
        if suffix in {".mp4", ".mkv", ".mov", ".webm", ".avi"}:
            return "video"
        if suffix == ".description":
            return "description"
        return "file"
