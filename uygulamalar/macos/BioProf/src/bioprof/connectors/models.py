from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, Field


class Provenance(BaseModel):
    provider: str
    canonical_url: str
    retrieved_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    record_id: str
    database: str
    license: str | None = None
    license_url: str | None = None
    rights_status: Literal["metadata_only", "open_access", "unknown", "restricted"] = (
        "metadata_only"
    )
    api_version: str | None = None


class RemoteRecord(BaseModel):
    id: str
    title: str
    text: str = ""
    url: str
    record_type: str
    authors: list[str] = Field(default_factory=list)
    published_at: str | None = None
    identifiers: dict[str, str] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)
    provenance: Provenance


class ConnectorPage(BaseModel):
    records: list[RemoteRecord]
    next_cursor: str | None = None
    total: int | None = None
    provider: str


class ConnectorError(RuntimeError):
    pass


class RateLimitError(ConnectorError):
    pass


class RightsError(ConnectorError):
    pass
