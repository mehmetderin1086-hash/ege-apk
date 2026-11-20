from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, Literal

from pydantic import BaseModel, Field


class PrivacyMode(StrEnum):
    LOCAL_ONLY = "local_only"
    LOCAL_FIRST = "local_first"
    CLOUD_ALLOWED = "cloud_allowed"


class AnswerMode(StrEnum):
    STRICT = "strict"
    HYBRID = "hybrid"
    # Accepted by the API and MCP surfaces for compatibility, but there is
    # no research branch anywhere: it behaves exactly like STRICT. The UI
    # button was removed so the mode stops promising connector-backed
    # search it never performed. Wiring it is a separate feature.
    RESEARCH = "research"
    RAW = "raw"


class JobStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    NEEDS_REVIEW = "needs_review"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class SourceStatus(StrEnum):
    QUEUED = "queued"
    PROCESSING = "processing"
    READY = "ready"
    NEEDS_REVIEW = "needs_review"
    QUARANTINED = "quarantined"
    FAILED = "failed"


class AnchorType(StrEnum):
    TEXT = "text"
    PAGE = "page"
    SLIDE = "slide"
    TIME = "time"
    TABLE = "table"
    SEQUENCE = "sequence"


class CitationAnchor(BaseModel):
    id: str
    source_id: str
    source_sha256: str
    chunk_id: str
    anchor_type: AnchorType = AnchorType.TEXT
    page: int | None = None
    slide: int | None = None
    bbox: tuple[float, float, float, float] | None = None
    timestamp_start: float | None = None
    timestamp_end: float | None = None
    sequence_start: int | None = None
    sequence_end: int | None = None
    section: str | None = None
    quote: str
    source_title: str
    source_uri: str | None = None


class Evidence(BaseModel):
    label: str
    text: str
    score: float
    anchor: CitationAnchor
    retrieval_channels: list[str] = Field(default_factory=list)


class Claim(BaseModel):
    text: str
    citation_labels: list[str] = Field(default_factory=list)
    supported: bool = True


class AnswerEnvelope(BaseModel):
    answer_markdown: str
    claims: list[Claim] = Field(default_factory=list)
    citations: list[CitationAnchor] = Field(default_factory=list)
    evidence_status: Literal["supported", "partial", "insufficient", "raw"]
    provider: str
    model: str
    trace_id: str
    usage: dict[str, int] = Field(default_factory=dict)
    audio_job_id: str | None = None
    # Seçilen sağlayıcı (örn. yerel LLM) o an kullanılamadı; yanıt deterministik
    # kanıt özetine düştü. İkinci bir sağlayıcı asla denenmez.
    degraded: bool = False
    # Düşüşün nedeni: "yerel model kullanılamadı" mesajı tek başına ne
    # kullanıcıya ne geliştiriciye sorunu gösteriyordu.
    degraded_reason: str | None = None


class ProviderCapabilities(BaseModel):
    name: str
    available: bool
    models: list[str] = Field(default_factory=list)
    chat: bool = False
    responses: bool = False
    streaming: bool = False
    tools: bool = False
    json_schema: bool = False
    embeddings: bool = False
    transcription: bool = False
    speech: bool = False
    details: dict[str, Any] = Field(default_factory=dict)


class TrainingManifest(BaseModel):
    id: str
    name: str
    status: str = "draft"
    dataset_hash: str
    base_model: str
    base_revision: str | None = None
    method: str = "qlora"
    parameters: dict[str, Any] = Field(default_factory=dict)
    licenses: list[str] = Field(default_factory=list)
    source_ids: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))


class EvalReport(BaseModel):
    id: str
    model_id: str
    metrics: dict[str, float]
    passed: bool
    failures: list[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
