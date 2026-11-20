from __future__ import annotations

import secrets
from functools import lru_cache
from pathlib import Path

from platformdirs import user_cache_dir, user_data_dir, user_downloads_path, user_log_dir
from pydantic import Field, PrivateAttr
from pydantic_settings import BaseSettings, SettingsConfigDict


class AppSettings(BaseSettings):
    """Runtime configuration. Environment variables use the DOWNLOADHUB_ prefix."""

    model_config = SettingsConfigDict(
        env_prefix="DOWNLOADHUB_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    host: str = "127.0.0.1"
    port: int = 8765
    data_dir: Path = Field(default_factory=lambda: Path(user_data_dir("DownloadHub")))
    cache_dir: Path = Field(default_factory=lambda: Path(user_cache_dir("DownloadHub")))
    log_dir: Path = Field(default_factory=lambda: Path(user_log_dir("DownloadHub")))
    download_dir: Path = Field(default_factory=lambda: Path(user_downloads_path()) / "DownloadHub")
    database_url: str | None = None
    max_concurrent_jobs: int = 3
    max_total_connections: int = 16
    split_count: int = 8
    global_speed_limit: str = "0"
    timezone: str = "Europe/Istanbul"
    allow_private_networks: bool = False
    aria2_path: str = "aria2c"
    yt_dlp_path: str = "yt-dlp"
    ffmpeg_path: str = "ffmpeg"
    deno_path: str = "deno"
    app_secret: str | None = None
    retry_delays: tuple[int, ...] = (5, 30, 120)
    _safe_proxy_url: str | None = PrivateAttr(default=None)

    @property
    def safe_proxy_url(self) -> str | None:
        return self._safe_proxy_url

    @safe_proxy_url.setter
    def safe_proxy_url(self, value: str | None) -> None:
        self._safe_proxy_url = value

    @property
    def resolved_database_url(self) -> str:
        if self.database_url:
            return self.database_url
        return f"sqlite+aiosqlite:///{self.data_dir / 'downloadhub.db'}"

    @property
    def secret_file(self) -> Path:
        return self.data_dir / "app-secret"

    def prepare(self) -> None:
        for directory in (self.data_dir, self.cache_dir, self.log_dir, self.download_dir):
            directory.mkdir(parents=True, exist_ok=True)
        for category in ("Videolar", "Müzik", "Resimler", "Belgeler", "Arşivler", "Diğer"):
            (self.download_dir / category).mkdir(parents=True, exist_ok=True)
        if not self.app_secret:
            if self.secret_file.exists():
                self.app_secret = self.secret_file.read_text(encoding="utf-8").strip()
            else:
                self.app_secret = secrets.token_urlsafe(48)
                self.secret_file.write_text(self.app_secret, encoding="utf-8")
                self.secret_file.chmod(0o600)


@lru_cache
def get_settings() -> AppSettings:
    settings = AppSettings()
    settings.prepare()
    return settings
