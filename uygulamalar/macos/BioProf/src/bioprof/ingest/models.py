from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Protocol

from bioprof.domain.models import AnchorType, SourceStatus


class IngestionError(RuntimeError):
    """Base class for failures that are safe to show to a local user."""


class UnsupportedFormatError(IngestionError):
    """Raised when no installed parser can safely process a source."""


class UnsafeSourceError(IngestionError):
    """Raised when an input violates an ingestion safety limit."""


@dataclass(slots=True)
class DocumentBlock:
    """A structure-preserving unit emitted by an input parser.

    Coordinates are deliberately expressed using the same fields as ChunkRecord so
    parsers do not leak library-specific objects into the rest of the application.
    Pages and slides are one-based; biological sequence offsets are one-based and
    inclusive; timestamps are seconds.
    """

    text: str
    section: str | None = None
    anchor_type: AnchorType = AnchorType.TEXT
    page: int | None = None
    slide: int | None = None
    bbox: tuple[float, float, float, float] | None = None
    timestamp_start: float | None = None
    timestamp_end: float | None = None
    sequence_start: int | None = None
    sequence_end: int | None = None
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class ParsedDocument:
    title: str
    blocks: list[DocumentBlock]
    parser: str
    parser_version: str = "1"
    language: str = "und"
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def text(self) -> str:
        return "\n\n".join(block.text for block in self.blocks if block.text.strip())


@dataclass(slots=True, frozen=True)
class PIIFinding:
    kind: str
    excerpt: str
    severity: str = "high"


@dataclass(slots=True)
class PreparedChunk:
    ordinal: int
    text: str
    section: str | None
    page: int | None
    slide: int | None
    bbox: tuple[float, float, float, float] | None
    timestamp_start: float | None
    timestamp_end: float | None
    sequence_start: int | None
    sequence_end: int | None
    token_count: int


@dataclass(slots=True)
class IngestionResult:
    source_id: str
    status: SourceStatus
    sha256: str
    title: str
    mime_type: str
    parser: str | None
    chunk_count: int
    deduplicated: bool = False
    findings: list[PIIFinding] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    error: str | None = None


class SourceParser(Protocol):
    name: str
    version: str

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument: ...


class MediaTranscriptionHook(Protocol):
    def __call__(self, path: Path, *, kind: str) -> list[DocumentBlock]:
        """Return timestamped blocks for an audio or video file."""


class VectorIndexer(Protocol):
    def upsert_chunks(self, chunks: list[Any], *, notebook_id: str) -> None: ...

    def delete_source(self, source_id: str) -> None: ...
