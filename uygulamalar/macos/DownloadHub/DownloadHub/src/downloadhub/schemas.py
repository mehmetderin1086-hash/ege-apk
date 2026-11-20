from __future__ import annotations

import re
from datetime import datetime
from enum import StrEnum
from typing import Any

from pydantic import AliasChoices, BaseModel, ConfigDict, Field, HttpUrl, field_validator


class JobEngine(StrEnum):
    DIRECT = "direct"
    MEDIA = "media"


class JobStatus(StrEnum):
    INSPECTING = "inspecting"
    QUEUED = "queued"
    SCHEDULED = "scheduled"
    DOWNLOADING = "downloading"
    POSTPROCESSING = "postprocessing"
    PAUSED = "paused"
    RETRY_WAIT = "retry_wait"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    INTERRUPTED = "interrupted"


class MediaPreset(StrEnum):
    BEST = "best"
    MP4 = "mp4"
    P1080 = "1080p"
    P720 = "720p"
    M4A = "m4a"
    MP3 = "mp3"
    ARCHIVE = "archive"


class BrowserName(StrEnum):
    CHROME = "chrome"
    CHROMIUM = "chromium"
    BRAVE = "brave"
    EDGE = "edge"


class InspectRequest(BaseModel):
    url: HttpUrl
    use_browser_cookies: bool = False
    browser_name: BrowserName = BrowserName.CHROME
    browser_profile: str | None = None

    @field_validator("browser_profile")
    @classmethod
    def validate_browser_profile(cls, value: str | None) -> str | None:
        return _validate_browser_profile(value)


class FormatInfo(BaseModel):
    format_id: str
    label: str
    extension: str | None = None
    resolution: str | None = None
    video_codec: str | None = None
    audio_codec: str | None = None
    filesize: int | None = None


class PlaylistItem(BaseModel):
    id: str
    title: str
    url: str | None = None
    duration: int | None = None
    thumbnail: str | None = None
    selected: bool = True


class InspectResponse(BaseModel):
    inspection_id: str
    source_type: str
    engine: JobEngine
    url: str
    title: str
    thumbnail: str | None = None
    uploader: str | None = None
    duration: int | None = None
    filesize: int | None = None
    mime_type: str | None = None
    formats: list[FormatInfo] = Field(default_factory=list)
    subtitles: list[str] = Field(default_factory=list)
    items: list[PlaylistItem] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class JobCreate(BaseModel):
    url: HttpUrl
    engine: JobEngine | None = None
    inspection_id: str | None = None
    title: str | None = None
    category: str | None = None
    preset: MediaPreset = MediaPreset.BEST
    format_id: str | None = None
    subtitle_languages: list[str] = Field(default_factory=list)
    write_thumbnail: bool = False
    write_metadata: bool = False
    selected_item_ids: list[str] = Field(default_factory=list)
    scheduled_at: datetime | None = None
    speed_limit: str | None = None
    priority: int = Field(default=0, ge=-100, le=100)
    sha256: str | None = None
    use_browser_cookies: bool = False
    browser_name: BrowserName = BrowserName.CHROME
    browser_profile: str | None = None

    @field_validator("sha256")
    @classmethod
    def validate_sha256(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.lower().strip()
        if len(normalized) != 64 or any(c not in "0123456789abcdef" for c in normalized):
            raise ValueError("SHA-256 64 hexadecimal karakter olmalıdır")
        return normalized

    @field_validator("category")
    @classmethod
    def validate_category(cls, value: str | None) -> str | None:
        allowed = {"Videolar", "Müzik", "Resimler", "Belgeler", "Arşivler", "Diğer"}
        if value is not None and value not in allowed:
            raise ValueError("Geçersiz indirme kategorisi")
        return value

    @field_validator("speed_limit")
    @classmethod
    def validate_speed_limit(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().upper()
        if not re.fullmatch(r"0|[1-9]\d*(?:\.\d+)?[KMG]?", normalized):
            raise ValueError("Hız sınırı 0, 500K, 2M gibi olmalıdır")
        return normalized

    @field_validator("browser_profile")
    @classmethod
    def validate_browser_profile(cls, value: str | None) -> str | None:
        return _validate_browser_profile(value)


class JobRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    source_url: str
    engine: JobEngine
    status: JobStatus
    title: str
    category: str
    priority: int
    progress: float
    downloaded_bytes: int
    total_bytes: int | None
    speed_bytes: int
    eta_seconds: int | None
    scheduled_at: datetime | None
    created_at: datetime
    updated_at: datetime
    error_code: str | None
    error_message: str | None
    output_path: str | None
    options: dict[str, Any]


class CancelRequest(BaseModel):
    keep_partial: bool = True


class PriorityUpdate(BaseModel):
    priority: int = Field(ge=-100, le=100)


class JobsPage(BaseModel):
    items: list[JobRead]
    total: int
    page: int
    page_size: int


class SettingsRead(BaseModel):
    download_dir: str
    max_concurrent_jobs: int
    max_total_connections: int
    split_count: int
    global_speed_limit: str
    timezone: str
    allow_private_networks: bool
    theme: str
    browser_name: str
    browser_profile: str
    daily_window_start: str | None
    daily_window_end: str | None


class SettingsUpdate(BaseModel):
    download_dir: str | None = None
    max_concurrent_jobs: int | None = Field(default=None, ge=1, le=10)
    max_total_connections: int | None = Field(default=None, ge=1, le=64)
    split_count: int | None = Field(default=None, ge=1, le=16)
    global_speed_limit: str | None = None
    timezone: str | None = None
    allow_private_networks: bool | None = None
    theme: str | None = None
    browser_name: BrowserName | None = None
    browser_profile: str | None = None
    daily_window_start: str | None = None
    daily_window_end: str | None = None

    @field_validator("browser_profile")
    @classmethod
    def validate_browser_profile(cls, value: str | None) -> str | None:
        return _validate_browser_profile(value)

    @field_validator("daily_window_start", "daily_window_end")
    @classmethod
    def validate_daily_time(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        normalized = value.strip()
        match = re.fullmatch(r"(\d{2}):(\d{2})", normalized)
        if not match or int(match.group(1)) > 23 or int(match.group(2)) > 59:
            raise ValueError("Saat HH:MM biçiminde olmalıdır")
        return normalized


def _validate_browser_profile(value: str | None) -> str | None:
    if value is None:
        return None
    normalized = value.strip()
    if not normalized or len(normalized) > 128 or not re.fullmatch(r"[\w .()-]+", normalized):
        raise ValueError("Geçersiz Chromium profil adı")
    return normalized


class PairStartResponse(BaseModel):
    code: str
    expires_at: datetime


class PairCompleteRequest(BaseModel):
    code: str
    client_name: str = Field(default="Chromium", validation_alias=AliasChoices("client_name", "name"))


class PairCompleteResponse(BaseModel):
    token: str
    client_id: str


class PairedClientRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    origin: str
    created_at: datetime
    last_seen_at: datetime | None


class RuntimeComponent(BaseModel):
    name: str
    available: bool
    path: str | None = None
    version: str | None = None
    required: bool = True


class HealthResponse(BaseModel):
    status: str
    version: str
    components: list[RuntimeComponent]
