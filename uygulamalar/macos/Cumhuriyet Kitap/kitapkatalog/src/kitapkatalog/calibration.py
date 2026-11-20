"""Monotonic confidence calibration for the five-engine consensus.

The production pipeline must not interpret a heuristic OCR score as an
empirical probability.  A profile is fitted only on the edition/session-grouped
calibration split, serialized as JSON, and hash-addressed by the pipeline
configuration.  Without a trusted profile OCR can still be reviewed, but no
field is automatically accepted.
"""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
import unicodedata
from collections.abc import Iterable
from dataclasses import asdict, dataclass
from itertools import groupby
from pathlib import Path


class CalibrationError(ValueError):
    """A calibration profile is malformed or statistically insufficient."""


@dataclass(frozen=True, slots=True)
class CalibrationSample:
    raw_confidence: float
    correct: bool

    def __post_init__(self) -> None:
        if not 0.0 <= self.raw_confidence <= 1.0:
            raise CalibrationError("Ham güven 0 ile 1 arasında olmalıdır")


@dataclass(frozen=True, slots=True)
class ReviewLabel:
    """One reviewed field: what a model proposed and what the user settled on.

    This is the raw material of the closed loop.  Reviewing a book already
    produces the ground truth a calibration profile needs; nothing else has to
    be labelled by hand.
    """

    field_path: str
    raw_confidence: float
    observed_value: str
    confirmed_value: str
    #: Whether the proposal carried a box on the source photograph. The
    #: acceptance gate demands full coverage, so this must be measured rather
    #: than assumed.
    has_visual_provenance: bool = False
    engine_ids: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class CalibrationBin:
    upper_bound: float
    calibrated_probability: float
    sample_count: int


@dataclass(frozen=True, slots=True)
class ConfidenceCalibrationProfile:
    version: str
    bins: tuple[CalibrationBin, ...]
    total_samples: int
    minimum_samples: int = 200
    schema_version: int = 1

    def __post_init__(self) -> None:
        if self.schema_version != 1:
            raise CalibrationError(f"Desteklenmeyen kalibrasyon şeması: {self.schema_version}")
        if not self.version.strip():
            raise CalibrationError("Kalibrasyon sürümü boş olamaz")
        if not self.bins:
            raise CalibrationError("Kalibrasyon profili en az bir dilim içermelidir")
        previous_bound = -1.0
        previous_probability = -1.0
        counted = 0
        for item in self.bins:
            if not previous_bound < item.upper_bound <= 1.0:
                raise CalibrationError("Kalibrasyon dilim sınırları artan olmalıdır")
            if not previous_probability <= item.calibrated_probability <= 1.0:
                raise CalibrationError("Kalibre olasılıklar 0..1 aralığında ve monoton olmalıdır")
            if item.sample_count < 1:
                raise CalibrationError("Kalibrasyon dilimi örneksiz olamaz")
            previous_bound = item.upper_bound
            previous_probability = item.calibrated_probability
            counted += item.sample_count
        if self.bins[-1].upper_bound != 1.0:
            raise CalibrationError("Son kalibrasyon dilimi 1.0 değerini kapsamalıdır")
        if counted != self.total_samples:
            raise CalibrationError("Kalibrasyon örnek toplamı dilimlerle uyuşmuyor")
        if self.minimum_samples < 1:
            raise CalibrationError("minimum_samples pozitif olmalıdır")

    @property
    def trusted(self) -> bool:
        return self.total_samples >= self.minimum_samples

    def calibrate(self, raw_confidence: float) -> float:
        value = max(0.0, min(1.0, float(raw_confidence)))
        for item in self.bins:
            if value <= item.upper_bound:
                return item.calibrated_probability
        return self.bins[-1].calibrated_probability

    def to_dict(self) -> dict[str, object]:
        return {
            "schema_version": self.schema_version,
            "version": self.version,
            "total_samples": self.total_samples,
            "minimum_samples": self.minimum_samples,
            "bins": [asdict(item) for item in self.bins],
        }

    @classmethod
    def from_dict(cls, payload: dict[str, object]) -> ConfidenceCalibrationProfile:
        try:
            raw_bins = payload["bins"]
            if not isinstance(raw_bins, list):
                raise TypeError("bins liste olmalıdır")
            bins = tuple(
                CalibrationBin(
                    upper_bound=float(item["upper_bound"]),
                    calibrated_probability=float(item["calibrated_probability"]),
                    sample_count=int(item["sample_count"]),
                )
                for item in raw_bins
                if isinstance(item, dict)
            )
            if len(bins) != len(raw_bins):
                raise TypeError("bins öğeleri nesne olmalıdır")
            return cls(
                schema_version=int(payload.get("schema_version", 1)),
                version=str(payload["version"]),
                bins=bins,
                total_samples=int(payload["total_samples"]),
                minimum_samples=int(payload.get("minimum_samples", 200)),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise CalibrationError(f"Kalibrasyon profili bozuk: {exc}") from exc

    @classmethod
    def load(cls, path: str | Path) -> ConfidenceCalibrationProfile:
        source = Path(path)
        try:
            payload = json.loads(source.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise CalibrationError(f"Kalibrasyon profili okunamadı: {source}: {exc}") from exc
        if not isinstance(payload, dict):
            raise CalibrationError("Kalibrasyon profili JSON nesnesi olmalıdır")
        return cls.from_dict(payload)

    def digest(self) -> str:
        raw = json.dumps(
            self.to_dict(),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return hashlib.sha256(raw).hexdigest()

    def save(self, path: str | Path) -> Path:
        """Write the profile atomically so a partial file is never trusted."""

        destination = Path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w",
                encoding="utf-8",
                dir=destination.parent,
                prefix=f".{destination.name}.",
                suffix=".part",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                json.dump(
                    self.to_dict(),
                    handle,
                    ensure_ascii=False,
                    indent=2,
                )
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            temporary.replace(destination)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
        return destination


@dataclass(slots=True)
class _PavBlock:
    upper_bound: float
    correct: int
    count: int

    @property
    def probability(self) -> float:
        return self.correct / self.count


def _comparable(value: str) -> str:
    """Normalise for comparison without erasing what the project cares about.

    NFC and surrounding whitespace are noise.  Case is not: Turkish `I/İ/ı/i`
    is exactly the class of error this catalogue refuses to hide, so folding it
    away here would label a real mistake as a correct read.
    """

    return unicodedata.normalize("NFC", value).strip()


def samples_from_reviews(labels: Iterable[ReviewLabel]) -> list[CalibrationSample]:
    """Turn reviewed fields into calibration samples.

    A proposal counts as correct only when it matches the value the user left in
    place.  A proposal the user replaced — including one made where the user
    ended up recording nothing — is a negative sample, which is the half of the
    curve an accuracy-only view never sees.
    """

    samples: list[CalibrationSample] = []
    for label in labels:
        confidence = min(1.0, max(0.0, float(label.raw_confidence)))
        samples.append(
            CalibrationSample(
                raw_confidence=confidence,
                correct=_comparable(label.observed_value) == _comparable(label.confirmed_value),
            )
        )
    return samples


def fit_isotonic_profile(
    samples: list[CalibrationSample] | tuple[CalibrationSample, ...],
    *,
    version: str,
    minimum_samples: int = 200,
) -> ConfidenceCalibrationProfile:
    """Fit a deterministic pool-adjacent-violators calibration profile."""

    ordered = sorted(samples, key=lambda item: item.raw_confidence)
    if not ordered:
        raise CalibrationError("Kalibrasyon için örnek bulunamadı")
    blocks: list[_PavBlock] = []
    for raw_confidence, grouped in groupby(
        ordered,
        key=lambda item: item.raw_confidence,
    ):
        group = tuple(grouped)
        blocks.append(
            _PavBlock(
                upper_bound=raw_confidence,
                correct=sum(item.correct for item in group),
                count=len(group),
            )
        )
        while len(blocks) >= 2 and blocks[-2].probability > blocks[-1].probability:
            right = blocks.pop()
            left = blocks.pop()
            blocks.append(
                _PavBlock(
                    upper_bound=right.upper_bound,
                    correct=left.correct + right.correct,
                    count=left.count + right.count,
                )
            )
    # The final bin must cover future raw scores slightly above the calibration
    # sample maximum without extrapolating a new probability.
    blocks[-1].upper_bound = 1.0
    return ConfidenceCalibrationProfile(
        version=version,
        bins=tuple(
            CalibrationBin(
                upper_bound=block.upper_bound,
                calibrated_probability=block.probability,
                sample_count=block.count,
            )
            for block in blocks
        ),
        total_samples=len(ordered),
        minimum_samples=minimum_samples,
    )
