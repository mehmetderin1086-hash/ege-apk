"""Core domain contracts shared by the catalogue and OCR pipeline.

The objects in this module deliberately contain no Qt or database code.  They
can therefore be passed between worker processes and used by the command-line
and desktop front ends alike.
"""

from __future__ import annotations

import hashlib
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path

UNKNOWN_VALUE = "bilinmiyor"


def utc_now() -> datetime:
    """Return an aware UTC timestamp."""

    return datetime.now(UTC)


class CoverRole(StrEnum):
    FRONT = "front"
    FRONT_INSIDE = "front_inside"
    BACK_INSIDE = "back_inside"
    BACK = "back"


BOOK_SURFACE_ORDER: tuple[CoverRole, ...] = (
    CoverRole.FRONT,
    CoverRole.FRONT_INSIDE,
    CoverRole.BACK_INSIDE,
    CoverRole.BACK,
)


class StorageMode(StrEnum):
    MANAGED_COPY = "managed_copy"
    REFERENCE = "reference"


class OcrEngine(StrEnum):
    RAPIDOCR = "rapidocr_ppocrv6"
    TESSERACT = "tesseract"
    EASYOCR = "easyocr"
    PADDLEOCR_VL = "paddleocr_vl"
    SURYA = "surya"


REQUIRED_OCR_ENGINES: tuple[OcrEngine, ...] = tuple(OcrEngine)


class RunStatus(StrEnum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class ImportJobStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    COMPLETED_WITH_ERRORS = "completed_with_errors"
    CANCELLED = "cancelled"


class JobItemStage(StrEnum):
    DISCOVERED = "discovered"
    PAIRED = "paired"
    PREPROCESSED = "preprocessed"
    OCR_COMPLETE = "5_ocr_complete"
    RECONCILED = "reconciled"
    EXTRACTED = "extracted"
    REVIEW = "review"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

    @property
    def terminal(self) -> bool:
        return self in {
            JobItemStage.REVIEW,
            JobItemStage.COMPLETED,
            JobItemStage.FAILED,
            JobItemStage.CANCELLED,
        }


ALLOWED_STAGE_TRANSITIONS: Mapping[JobItemStage, frozenset[JobItemStage]] = {
    JobItemStage.DISCOVERED: frozenset({JobItemStage.PAIRED}),
    JobItemStage.PAIRED: frozenset({JobItemStage.PREPROCESSED}),
    JobItemStage.PREPROCESSED: frozenset({JobItemStage.OCR_COMPLETE}),
    JobItemStage.OCR_COMPLETE: frozenset({JobItemStage.RECONCILED}),
    JobItemStage.RECONCILED: frozenset({JobItemStage.EXTRACTED}),
    JobItemStage.EXTRACTED: frozenset({JobItemStage.REVIEW, JobItemStage.COMPLETED}),
    JobItemStage.REVIEW: frozenset({JobItemStage.COMPLETED}),
    JobItemStage.COMPLETED: frozenset(),
    JobItemStage.FAILED: frozenset(),
    JobItemStage.CANCELLED: frozenset(),
}


@dataclass(frozen=True, slots=True)
class TranscriptSegment:
    """Whisper çıktısındaki tek zaman-damgalı konuşma parçası (saniye cinsinden)."""

    start_seconds: float
    end_seconds: float
    text: str
    avg_logprob: float | None = None
    no_speech_prob: float | None = None


class VoiceJobPhase(StrEnum):
    INGESTED = "ingested"
    CONVERTED = "converted"
    TRANSCRIBED = "transcribed"
    SEGMENTED = "segmented"
    ITEMS = "items"
    DONE = "done"


class VoiceItemStage(StrEnum):
    SEGMENTED = "segmented"
    PARSED = "parsed"
    EXTRACTED = "extracted"
    REVIEW = "review"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"

    @property
    def terminal(self) -> bool:
        return self in {
            VoiceItemStage.REVIEW,
            VoiceItemStage.COMPLETED,
            VoiceItemStage.FAILED,
            VoiceItemStage.CANCELLED,
        }


ALLOWED_VOICE_STAGE_TRANSITIONS: Mapping[VoiceItemStage, frozenset[VoiceItemStage]] = {
    VoiceItemStage.SEGMENTED: frozenset({VoiceItemStage.PARSED}),
    VoiceItemStage.PARSED: frozenset({VoiceItemStage.EXTRACTED}),
    VoiceItemStage.EXTRACTED: frozenset({VoiceItemStage.REVIEW, VoiceItemStage.COMPLETED}),
    VoiceItemStage.REVIEW: frozenset({VoiceItemStage.COMPLETED}),
    VoiceItemStage.COMPLETED: frozenset(),
    VoiceItemStage.FAILED: frozenset(),
    VoiceItemStage.CANCELLED: frozenset(),
}


class FieldStatus(StrEnum):
    AUTO = "auto"
    REVIEW = "review"
    CONFIRMED = "confirmed"
    UNRESOLVED = "unresolved"


class ContributorRole(StrEnum):
    AUTHOR = "author"
    TRANSLATOR = "translator"
    EDITOR = "editor"
    COMPILER = "compiler"
    ILLUSTRATOR = "illustrator"
    FOREWORD = "foreword"
    OTHER = "other"


@dataclass(frozen=True, slots=True)
class ImagePair:
    """A proposed two- or four-surface book scan set.

    ``pair_key`` is stable within an import and makes re-submitting the same
    discovery result idempotent.  Pairing does not read the image bytes, so the
    definitive source SHA-256 values are stored later by preprocessing.

    ``front_inside`` and ``back_inside`` are optional only for backward
    compatibility with existing two-cover catalogues.  New four-surface
    single/bulk imports require both.
    """

    front: Path
    back: Path
    front_inside: Path | None = None
    back_inside: Path | None = None
    pair_key: str = ""
    confidence: float = 1.0
    basis: str = "filename"
    needs_review: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "front", Path(self.front))
        object.__setattr__(self, "back", Path(self.back))
        object.__setattr__(
            self,
            "front_inside",
            Path(self.front_inside) if self.front_inside is not None else None,
        )
        object.__setattr__(
            self,
            "back_inside",
            Path(self.back_inside) if self.back_inside is not None else None,
        )
        if not self.pair_key.strip():
            material = "\0".join(
                str(path.absolute()) if path is not None else ""
                for path in (
                    self.front,
                    self.front_inside,
                    self.back_inside,
                    self.back,
                )
            ).encode()
            object.__setattr__(
                self, "pair_key", f"pair-{hashlib.sha256(material).hexdigest()[:20]}"
            )
        if not 0.0 <= self.confidence <= 1.0:
            raise ValueError("confidence 0 ile 1 arasında olmalıdır")
        paths = tuple(path for path in self.paths_by_role.values() if path is not None)
        if len(paths) != len(set(paths)):
            raise ValueError("Bir belge aynı kitapta birden fazla yüz olarak kullanılamaz")

    @property
    def complete_four_surface(self) -> bool:
        return self.front_inside is not None and self.back_inside is not None

    @property
    def paths_by_role(self) -> Mapping[CoverRole, Path | None]:
        return {
            CoverRole.FRONT: self.front,
            CoverRole.FRONT_INSIDE: self.front_inside,
            CoverRole.BACK_INSIDE: self.back_inside,
            CoverRole.BACK: self.back,
        }

    @property
    def active_roles(self) -> tuple[CoverRole, ...]:
        return tuple(role for role in BOOK_SURFACE_ORDER if self.paths_by_role[role] is not None)


Point = tuple[float, float]
Polygon = tuple[Point, ...]


@dataclass(frozen=True, slots=True)
class PersistedConsensusSpan:
    """Database DTO; OCR voting uses ``kitapkatalog.consensus.ConsensusSpan``."""

    text: str
    normalized_text: str
    confidence: float
    source_token_ids: tuple[str, ...]
    polygon: Polygon | None = None
    source_polygon: Polygon | None = None
    engine_support: tuple[OcrEngine, ...] = ()


@dataclass(frozen=True, slots=True)
class FieldObservation:
    field_path: str
    raw_value: str
    normalized_value: str
    cover_role: CoverRole
    confidence: float
    source_token_ids: tuple[str, ...] = ()
    engine_evidence: tuple[OcrEngine, ...] = ()
    polygon: Polygon | None = None
    source_polygon: Polygon | None = None


@dataclass(frozen=True, slots=True)
class ResolvedField:
    field_path: str
    value: str
    status: FieldStatus
    observation_id: int | None = None
    user_locked: bool = False
    resolver_version: str = ""
    updated_at: datetime | None = None


@dataclass(frozen=True, slots=True)
class ContributorInput:
    name: str
    role: ContributorRole | str = ContributorRole.AUTHOR
    sort_order: int = 0


@dataclass(frozen=True, slots=True)
class IdentifierInput:
    scheme: str
    value: str
    source: str = "cover"
    confidence: float | None = None


@dataclass(frozen=True, slots=True)
class CopyInput:
    inventory_code: str | None = None
    source_fingerprint: str | None = None
    location: str | None = None
    notes: str | None = None
    acquisition_method: str | None = None
    acquisition_date: str | None = None
    acquisition_price: str | None = None


@dataclass(frozen=True, slots=True)
class BookInput:
    title: str = UNKNOWN_VALUE
    subtitle: str | None = None
    original_title: str | None = None
    publisher: str | None = None
    imprint: str | None = None
    series: str | None = None
    volume: str | None = None
    language: str | None = None
    publication_place: str | None = None
    publication_date: str | None = None
    edition_statement: str | None = None
    printing_number: str | None = None
    printer: str | None = None
    binding: str | None = None
    page_count: int | None = None
    dimensions: str | None = None
    price_amount: str | None = None
    currency: str | None = None
    blurb: str | None = None
    awards: str | None = None
    quotations: str | None = None
    category: str | None = None
    contributors: tuple[ContributorInput, ...] = ()
    identifiers: tuple[IdentifierInput, ...] = ()
    copy: CopyInput | None = None


@dataclass(frozen=True, slots=True)
class CopyRecord:
    id: int
    edition_id: int
    inventory_code: str | None
    source_fingerprint: str | None
    location: str | None
    notes: str | None
    status: str = "active"
    acquisition_method: str | None = None
    acquisition_date: str | None = None
    acquisition_price: str | None = None


@dataclass(frozen=True, slots=True)
class BookRecord:
    edition_id: int
    work_id: int
    title: str
    subtitle: str | None
    original_title: str | None
    publisher: str | None
    imprint: str | None
    series: str | None
    volume: str | None
    language: str | None
    publication_place: str | None
    publication_date: str | None
    edition_statement: str | None
    printing_number: str | None
    printer: str | None
    binding: str | None
    page_count: int | None
    dimensions: str | None
    price_amount: str | None
    currency: str | None
    blurb: str | None
    awards: str | None
    quotations: str | None
    review_status: str
    category: str | None = None
    contributors: tuple[ContributorInput, ...] = ()
    identifiers: tuple[IdentifierInput, ...] = ()
    copies: tuple[CopyRecord, ...] = ()
    front_path: str | None = None
    front_inside_path: str | None = None
    back_inside_path: str | None = None
    back_path: str | None = None
    raw_ocr_text: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


@dataclass(frozen=True, slots=True)
class ImportJob:
    id: str
    name: str
    status: ImportJobStatus
    storage_mode: StorageMode
    total_items: int
    successful_items: int
    failed_items: int
    review_items: int
    idempotency_key: str | None = None
    config_hash: str = ""
    location: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None

    @property
    def terminal_items(self) -> int:
        return self.successful_items + self.failed_items + self.review_items


@dataclass(frozen=True, slots=True)
class JobItem:
    id: int
    job_id: str
    pair_key: str
    front_path: Path
    back_path: Path
    pairing_confidence: float
    pairing_basis: str
    needs_pair_review: bool
    stage: JobItemStage
    retry_count: int
    front_inside_path: Path | None = None
    back_inside_path: Path | None = None
    lease_owner: str | None = None
    lease_until: datetime | None = None
    heartbeat_at: datetime | None = None
    last_error: str | None = None
    edition_id: int | None = None
    location: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


@dataclass(frozen=True, slots=True)
class VoiceJob:
    id: str
    name: str
    status: ImportJobStatus
    phase: VoiceJobPhase
    source_audio_path: Path
    source_sha256: str | None
    canonical_wav_path: Path | None
    segmentation_version: int
    single_book: bool
    total_items: int
    successful_items: int
    failed_items: int
    review_items: int
    idempotency_key: str | None = None
    config_hash: str = ""
    lease_owner: str | None = None
    lease_until: datetime | None = None
    heartbeat_at: datetime | None = None
    last_error: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    language: str | None = None  # NULL = ayar varsayılanı (AppSettings.voice_language)

    @property
    def terminal_items(self) -> int:
        return self.successful_items + self.failed_items + self.review_items


@dataclass(frozen=True, slots=True)
class VoiceItem:
    id: int
    job_id: str
    item_key: str
    ordinal: int
    start_sample: int
    end_sample: int
    transcript_json: str
    stage: VoiceItemStage
    retry_count: int
    claims_json: str | None = None
    lease_owner: str | None = None
    lease_until: datetime | None = None
    heartbeat_at: datetime | None = None
    last_error: str | None = None
    edition_id: int | None = None
    review_reasons_json: str | None = None
    created_at: datetime | None = None
    updated_at: datetime | None = None


@dataclass(frozen=True, slots=True)
class VoiceAlias:
    """Sesli düzeltme sözlüğü kaydı: duyulan (katlanmış) metin -> kanonik değer."""

    id: int
    heard: str
    canonical: str
    field_scope: str  # "any" | "title" | "author" | "publisher"
    created_at: datetime | None = None


@dataclass(frozen=True, slots=True)
class SearchFilters:
    publisher: str | None = None
    language: str | None = None
    review_status: str | None = None
    identifier: str | None = None
    category: str | None = None
    missing: str | None = None
    location: str | None = None
    availability: str | None = None  # "available" | "unavailable"
    year_from: int | None = None
    year_to: int | None = None


@dataclass(frozen=True, slots=True)
class SearchPage:
    items: tuple[BookRecord, ...]
    total: int
    limit: int
    offset: int


def ensure_engine_set(engines: Sequence[OcrEngine | str]) -> frozenset[OcrEngine]:
    return frozenset(OcrEngine(engine) for engine in engines)
