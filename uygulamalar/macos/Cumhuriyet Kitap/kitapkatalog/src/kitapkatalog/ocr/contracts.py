"""Stable contracts shared by all OCR engines.

The real engines deliberately live behind this small interface.  Importing
``kitapkatalog`` therefore never imports torch, onnxruntime, OpenCV, or a
sidecar runtime.  Those dependencies are checked only when an engine is
constructed or executed and failures always include an installation/remedy
hint.
"""

from __future__ import annotations

import hashlib
import json
import math
import unicodedata
from abc import ABC, abstractmethod
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, ClassVar, Literal

from kitapkatalog.images import PreparedImage

type Point = tuple[float, float]
type Polygon = tuple[Point, ...]
type EvidenceKind = Literal["classic", "vision"]

REQUIRED_ENGINE_IDS: tuple[str, ...] = (
    "rapidocr_ppocrv6",
    "tesseract",
    "easyocr",
    "paddleocr_vl",
    "surya",
)
CLASSIC_ENGINE_IDS: frozenset[str] = frozenset(REQUIRED_ENGINE_IDS[:3])
VISION_ENGINE_IDS: frozenset[str] = frozenset(REQUIRED_ENGINE_IDS[3:])


class OcrError(RuntimeError):
    """Base class for OCR failures that may be shown to the user."""


class EngineUnavailableError(OcrError):
    """A required executable, Python dependency, language pack, or model is absent."""


class OcrExecutionError(OcrError):
    """An installed OCR engine could not process an image."""


class InvalidEngineResultError(OcrError):
    """An engine returned malformed or unsafe output."""


@dataclass(frozen=True, slots=True)
class EngineAvailability:
    engine_id: str
    available: bool
    version: str
    problems: tuple[str, ...] = ()

    def require(self) -> None:
        if not self.available:
            detail = "; ".join(self.problems) or "bilinmeyen kullanılabilirlik hatası"
            raise EngineUnavailableError(f"{self.engine_id} kullanılamıyor: {detail}")


def _validate_polygon(polygon: Polygon | None) -> Polygon | None:
    if polygon is None:
        return None
    if len(polygon) < 4:
        raise ValueError("OCR polygonu en az dört nokta içermelidir")
    normalized = tuple((float(x), float(y)) for x, y in polygon)
    if any(not math.isfinite(value) for point in normalized for value in point):
        raise ValueError("OCR polygonu sonlu koordinatlar içermelidir")
    return normalized


@dataclass(frozen=True, slots=True)
class OcrToken:
    """One positioned OCR observation in canonical-image coordinates."""

    token_id: str
    text: str
    confidence: float
    polygon: Polygon | None
    line_id: str | None = None
    paragraph_id: str | None = None
    language: str | None = None

    def __post_init__(self) -> None:
        normalized = unicodedata.normalize("NFC", self.text)
        if not normalized.strip():
            raise ValueError("OCR token metni boş olamaz")
        if not 0.0 <= float(self.confidence) <= 1.0:
            raise ValueError("OCR güveni 0 ile 1 arasında olmalıdır")
        object.__setattr__(self, "text", normalized)
        object.__setattr__(self, "confidence", float(self.confidence))
        object.__setattr__(self, "polygon", _validate_polygon(self.polygon))

    @property
    def has_visual_evidence(self) -> bool:
        return self.polygon is not None


@dataclass(frozen=True, slots=True)
class EngineOcrResult:
    engine_id: str
    model_version: str
    image_sha256: str
    variant: str
    tokens: tuple[OcrToken, ...]
    raw_text: str
    duration_ms: int
    evidence_kind: EvidenceKind
    warnings: tuple[str, ...] = ()
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        if self.engine_id not in REQUIRED_ENGINE_IDS:
            raise ValueError(f"Bilinmeyen OCR motoru: {self.engine_id}")
        if self.evidence_kind not in ("classic", "vision"):
            raise ValueError(f"Geçersiz kanıt türü: {self.evidence_kind}")
        normalized = unicodedata.normalize("NFC", self.raw_text)
        object.__setattr__(self, "raw_text", normalized)
        object.__setattr__(self, "tokens", tuple(self.tokens))
        object.__setattr__(self, "duration_ms", max(0, int(self.duration_ms)))
        object.__setattr__(self, "warnings", tuple(self.warnings))

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> EngineOcrResult:
        tokens = tuple(
            OcrToken(
                token_id=str(item["token_id"]),
                text=str(item["text"]),
                confidence=float(item["confidence"]),
                polygon=(
                    tuple((float(p[0]), float(p[1])) for p in item["polygon"])
                    if item.get("polygon") is not None
                    else None
                ),
                line_id=item.get("line_id"),
                paragraph_id=item.get("paragraph_id"),
                language=item.get("language"),
            )
            for item in payload.get("tokens", ())
        )
        return cls(
            engine_id=str(payload["engine_id"]),
            model_version=str(payload["model_version"]),
            image_sha256=str(payload["image_sha256"]),
            variant=str(payload.get("variant", "canonical")),
            tokens=tokens,
            raw_text=str(payload.get("raw_text", "")),
            duration_ms=int(payload.get("duration_ms", 0)),
            evidence_kind=str(payload["evidence_kind"]),  # type: ignore[arg-type]
            warnings=tuple(str(value) for value in payload.get("warnings", ())),
            metadata=dict(payload.get("metadata", {})),
        )


class OcrEngineAdapter(ABC):
    """Required engine API.

    Adapters are intentionally synchronous: the durable scheduler decides
    process/thread placement and memory admission.  A single adapter instance
    must emit at most one result/vote for each call.
    """

    engine_id: ClassVar[str]
    evidence_kind: ClassVar[EvidenceKind]
    model_version: str

    #: Whether ``recognize_many`` amortises a fixed per-call cost across images.
    #: Only engines whose model is loaded per invocation gain from batching; the
    #: in-process engines keep their model resident and set this to ``False`` so
    #: callers do not pay for grouping that buys nothing.
    batches_model_load: ClassVar[bool] = False

    @abstractmethod
    def availability(self) -> EngineAvailability:
        """Inspect dependencies without running inference."""

    @abstractmethod
    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        """Process the canonical full cover exactly once."""

    def recognize_many(self, images: Sequence[PreparedImage]) -> tuple[EngineOcrResult, ...]:
        """Process several covers, one result per image, in the given order.

        The default keeps the single-image contract: one ``recognize`` call per
        image.  Adapters that load a large model per invocation override this so
        one model load serves the whole group, which is what makes a book's four
        surfaces cheap instead of four times the cost of one.
        """

        return tuple(self.recognize(image) for image in images)

    def require_available(self) -> None:
        self.availability().require()

    def release(self) -> None:
        """Drop resident model state before another large model is admitted."""

        return None

    def runtime_settings(self) -> dict[str, Any]:
        """Return deterministic inference settings that affect cached output.

        Model bytes are not the whole inference identity.  Thresholds, language
        selection, page segmentation and sidecar prompt protocols can all
        change OCR output while the model artifact stays unchanged.  Adapters
        expose those values here so a settings change cannot accidentally
        reuse an older cache entry.
        """

        return {}

    def model_digest(self) -> str:
        payload = json.dumps(
            {
                "engine_id": self.engine_id,
                "model_version": self.model_version,
                "evidence_kind": self.evidence_kind,
                "artifact_digest": getattr(self, "artifact_digest", None),
                "runtime_settings": self.runtime_settings(),
            },
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
        ).encode()
        return hashlib.sha256(payload).hexdigest()


def rectangular_polygon(left: float, top: float, right: float, bottom: float) -> Polygon:
    return (
        (float(left), float(top)),
        (float(right), float(top)),
        (float(right), float(bottom)),
        (float(left), float(bottom)),
    )


def path_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()
