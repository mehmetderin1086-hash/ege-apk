from __future__ import annotations

from collections.abc import AsyncIterator

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine

from .config import AppSettings
from .models import AppSetting, Base, DownloadJob, Preset


class Database:
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.engine: AsyncEngine = create_async_engine(
            settings.resolved_database_url,
            echo=False,
            pool_pre_ping=True,
        )
        self.sessions = async_sessionmaker(self.engine, expire_on_commit=False)

    async def initialize(self) -> None:
        async with self.engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        await self._recover_interrupted_jobs()
        await self._seed_defaults()

    async def close(self) -> None:
        await self.engine.dispose()

    async def session(self) -> AsyncIterator[AsyncSession]:
        async with self.sessions() as session:
            yield session

    async def _recover_interrupted_jobs(self) -> None:
        async with self.sessions.begin() as session:
            await session.execute(
                update(DownloadJob)
                .where(DownloadJob.status.in_(["inspecting", "downloading", "postprocessing", "retry_wait"]))
                .values(status="interrupted", speed_bytes=0, eta_seconds=None)
            )

    async def mark_active_interrupted(self) -> None:
        await self._recover_interrupted_jobs()

    async def _seed_defaults(self) -> None:
        presets = {
            "best": ("En iyi kalite", {"format": "bestvideo*+bestaudio/best"}),
            "mp4": (
                "MP4 uyumlu",
                {"format": "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4]/best"},
            ),
            "1080p": ("1080p", {"format": "bv*[height<=1080]+ba/b[height<=1080]"}),
            "720p": ("720p", {"format": "bv*[height<=720]+ba/b[height<=720]"}),
            "m4a": ("Yalnız ses / M4A", {"format": "bestaudio[ext=m4a]/bestaudio"}),
            "mp3": ("MP3 192 kbps", {"format": "bestaudio", "audio_format": "mp3"}),
            "archive": ("Arşiv kalitesi", {"format": "bestvideo+bestaudio/best"}),
        }
        settings = {
            "download_dir": str(self.settings.download_dir),
            "download_roots": [str(self.settings.download_dir)],
            "max_concurrent_jobs": self.settings.max_concurrent_jobs,
            "max_total_connections": self.settings.max_total_connections,
            "split_count": self.settings.split_count,
            "global_speed_limit": self.settings.global_speed_limit,
            "timezone": self.settings.timezone,
            "allow_private_networks": self.settings.allow_private_networks,
            "theme": "system",
            "browser_name": "chrome",
            "browser_profile": "Default",
            "daily_window_start": None,
            "daily_window_end": None,
        }
        async with self.sessions.begin() as session:
            existing_presets = set((await session.scalars(select(Preset.key))).all())
            for key, (name, options) in presets.items():
                if key not in existing_presets:
                    session.add(
                        Preset(
                            key=key,
                            name=name,
                            engine="media",
                            options=options,
                            built_in=True,
                        )
                    )
            existing_settings = set((await session.scalars(select(AppSetting.key))).all())
            for key, value in settings.items():
                if key not in existing_settings:
                    session.add(AppSetting(key=key, value=value))
