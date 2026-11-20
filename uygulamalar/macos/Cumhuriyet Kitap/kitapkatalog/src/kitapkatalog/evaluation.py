"""Reproducible quality metrics and acceptance gates for the labelled corpus."""

from __future__ import annotations

import hashlib
import unicodedata
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from enum import StrEnum

TURKISH_DISTINCT = frozenset("çÇğĞıİöÖşŞüÜ")


class DatasetSplit(StrEnum):
    TRAIN = "train"
    CALIBRATION = "calibration"
    BLIND_TEST = "blind_test"


@dataclass(frozen=True, slots=True)
class CalibrationPoint:
    confidence: float
    correct: bool


@dataclass(frozen=True, slots=True)
class FieldEvaluation:
    predicted: str
    expected: str
    confidence: float
    auto_accepted: bool
    has_visual_provenance: bool
    engine_support: tuple[str, ...]
    # A single overall precision hides that, say, ISBN is solved while title is
    # not. Callers that do not care can leave the default.
    field_name: str = "genel"

    @property
    def correct(self) -> bool:
        return _field_key(self.predicted) == _field_key(self.expected)


@dataclass(frozen=True, slots=True)
class FieldMetrics:
    """Per-field view of what automatic acceptance actually delivered."""

    candidates: int
    automatic_count: int
    precision: float
    recall: float
    f1: float

    @classmethod
    def of(cls, fields: Sequence[FieldEvaluation]) -> FieldMetrics:
        auto = [item for item in fields if item.auto_accepted]
        true_positives = sum(item.correct for item in auto)
        # Recall is against every field that could have been accepted, so a
        # pipeline that reaches high precision by accepting almost nothing is
        # visible instead of flattering.
        answerable = sum(item.correct for item in fields)
        precision = true_positives / len(auto) if auto else 0.0
        recall = true_positives / answerable if answerable else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        return cls(
            candidates=len(fields),
            automatic_count=len(auto),
            precision=precision,
            recall=recall,
            f1=f1,
        )


@dataclass(frozen=True, slots=True)
class AcceptanceMetrics:
    automatic_precision: float
    automatic_count: int
    provenance_coverage: float
    ece: float
    ece_all_candidates: float
    automatic_recall: float
    automatic_f1: float
    by_field: Mapping[str, FieldMetrics]
    ensemble_cer: float
    best_single_engine_cer: float
    relative_cer_improvement: float
    turkish_character_errors: int
    barcode_recall: float
    barcode_false_positives: int


@dataclass(frozen=True, slots=True)
class AcceptanceReport:
    passed: bool
    metrics: AcceptanceMetrics
    violations: tuple[str, ...]


def deterministic_split(group_key: str) -> DatasetSplit:
    """Keep the same work/edition/photo-session group in exactly one split."""

    bucket = int.from_bytes(hashlib.sha256(group_key.encode("utf-8")).digest()[:8], "big") % 100
    if bucket < 60:
        return DatasetSplit.TRAIN
    if bucket < 80:
        return DatasetSplit.CALIBRATION
    return DatasetSplit.BLIND_TEST


def edit_distance(left: str, right: str) -> int:
    left = unicodedata.normalize("NFC", left)
    right = unicodedata.normalize("NFC", right)
    previous = list(range(len(right) + 1))
    for left_index, left_character in enumerate(left, 1):
        current = [left_index]
        for right_index, right_character in enumerate(right, 1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[right_index] + 1,
                    previous[right_index - 1] + int(left_character != right_character),
                )
            )
        previous = current
    return previous[-1]


def character_error_rate(expected: str, predicted: str) -> float:
    return edit_distance(expected, predicted) / max(1, len(unicodedata.normalize("NFC", expected)))


def expected_calibration_error(
    points: Iterable[CalibrationPoint],
    *,
    bins: int = 15,
) -> float:
    values = tuple(points)
    if not values:
        return 0.0
    if bins < 1:
        raise ValueError("bins en az 1 olmalıdır")
    total_error = 0.0
    for index in range(bins):
        low, high = index / bins, (index + 1) / bins
        bucket = [
            point
            for point in values
            if low <= point.confidence <= 1.0 and (point.confidence < high or index == bins - 1)
        ]
        if not bucket:
            continue
        accuracy = sum(point.correct for point in bucket) / len(bucket)
        average_confidence = sum(point.confidence for point in bucket) / len(bucket)
        total_error += len(bucket) / len(values) * abs(accuracy - average_confidence)
    return total_error


def _field_key(value: str) -> str:
    return " ".join(unicodedata.normalize("NFC", value).casefold().split())


def aligned_characters(expected: str, predicted: str) -> list[tuple[str, str]]:
    """Align two strings by edit distance, returning per-position pairs.

    A missing side is the empty string.  Comparing by raw index instead would
    make one inserted character mark every following character as wrong, which
    inflates any per-character metric built on top.
    """

    left = unicodedata.normalize("NFC", expected)
    right = unicodedata.normalize("NFC", predicted)
    rows, columns = len(left) + 1, len(right) + 1
    costs = [[0] * columns for _ in range(rows)]
    for row in range(rows):
        costs[row][0] = row
    for column in range(columns):
        costs[0][column] = column
    for row in range(1, rows):
        for column in range(1, columns):
            costs[row][column] = min(
                costs[row - 1][column] + 1,
                costs[row][column - 1] + 1,
                costs[row - 1][column - 1] + int(left[row - 1] != right[column - 1]),
            )
    pairs: list[tuple[str, str]] = []
    row, column = len(left), len(right)
    while row > 0 or column > 0:
        if (
            row > 0
            and column > 0
            and costs[row][column]
            == costs[row - 1][column - 1] + int(left[row - 1] != right[column - 1])
        ):
            pairs.append((left[row - 1], right[column - 1]))
            row -= 1
            column -= 1
        elif row > 0 and costs[row][column] == costs[row - 1][column] + 1:
            pairs.append((left[row - 1], ""))
            row -= 1
        else:
            pairs.append(("", right[column - 1]))
            column -= 1
    pairs.reverse()
    return pairs


def _turkish_error_count(expected: str, predicted: str) -> int:
    """Count distinct-letter substitutions/deletions without folding diacritics."""

    return sum(
        1
        for expected_character, predicted_character in aligned_characters(expected, predicted)
        if expected_character != predicted_character
        and (expected_character in TURKISH_DISTINCT or predicted_character in TURKISH_DISTINCT)
    )


def evaluate_acceptance(
    fields: Iterable[FieldEvaluation],
    *,
    expected_ocr_texts: Iterable[str],
    ensemble_ocr_texts: Iterable[str],
    single_engine_ocr_texts: dict[str, Iterable[str]],
    readable_barcodes: Iterable[str] = (),
    predicted_barcodes: Iterable[str] = (),
) -> AcceptanceReport:
    fields_tuple = tuple(fields)
    auto = tuple(item for item in fields_tuple if item.auto_accepted)
    precision = sum(item.correct for item in auto) / max(1, len(auto))
    provenance = sum(item.has_visual_provenance for item in auto) / max(1, len(auto))
    calibration = expected_calibration_error(
        CalibrationPoint(item.confidence, item.correct) for item in auto
    )
    # Measuring only the accepted subset never sees the low-confidence half of
    # the curve, which is exactly the region a calibration profile has to fix.
    calibration_all = expected_calibration_error(
        CalibrationPoint(item.confidence, item.correct) for item in fields_tuple
    )
    overall = FieldMetrics.of(fields_tuple)
    by_field: dict[str, FieldMetrics] = {}
    for name in sorted({item.field_name for item in fields_tuple}):
        by_field[name] = FieldMetrics.of([item for item in fields_tuple if item.field_name == name])

    expected_texts = tuple(expected_ocr_texts)
    ensemble_texts = tuple(ensemble_ocr_texts)
    if len(expected_texts) != len(ensemble_texts):
        raise ValueError("Beklenen ve ensemble OCR belge sayıları eşit olmalıdır")
    ensemble_cer = sum(
        character_error_rate(expected, predicted)
        for expected, predicted in zip(expected_texts, ensemble_texts, strict=True)
    ) / max(1, len(expected_texts))
    engine_cers: dict[str, float] = {}
    for engine, predictions_iterable in single_engine_ocr_texts.items():
        predictions = tuple(predictions_iterable)
        if len(predictions) != len(expected_texts):
            raise ValueError(f"{engine} OCR belge sayısı eşleşmiyor")
        engine_cers[engine] = sum(
            character_error_rate(expected, predicted)
            for expected, predicted in zip(expected_texts, predictions, strict=True)
        ) / max(1, len(expected_texts))
    best_single = min(engine_cers.values(), default=0.0)
    improvement = (best_single - ensemble_cer) / best_single if best_single > 0 else 0.0
    turkish_errors = sum(
        _turkish_error_count(expected, predicted)
        for expected, predicted in zip(expected_texts, ensemble_texts, strict=True)
    )

    readable = tuple(dict.fromkeys(readable_barcodes))
    predictions = tuple(predicted_barcodes)
    readable_set, predicted_set = set(readable), set(predictions)
    barcode_recall = len(readable_set & predicted_set) / max(1, len(readable_set))
    barcode_false_positives = sum(
        count for value, count in Counter(predictions).items() if value not in readable_set
    )

    metrics = AcceptanceMetrics(
        automatic_precision=precision,
        automatic_count=len(auto),
        provenance_coverage=provenance,
        ece=calibration,
        ece_all_candidates=calibration_all,
        automatic_recall=overall.recall,
        automatic_f1=overall.f1,
        by_field=by_field,
        ensemble_cer=ensemble_cer,
        best_single_engine_cer=best_single,
        relative_cer_improvement=improvement,
        turkish_character_errors=turkish_errors,
        barcode_recall=barcode_recall,
        barcode_false_positives=barcode_false_positives,
    )
    violations: list[str] = []
    if precision < 0.99:
        violations.append(f"Otomatik temel alan precision %{precision * 100:.2f} < %99")
    if provenance < 1.0:
        violations.append(f"Görsel provenance kapsamı %{provenance * 100:.2f} < %100")
    if calibration > 0.03:
        violations.append(f"ECE {calibration:.4f} > 0.03")
    if best_single > 0 and improvement < 0.15:
        violations.append(f"Ensemble göreli CER iyileşmesi %{improvement * 100:.2f} < %15")
    if readable and barcode_recall < 0.99:
        violations.append(f"Okunabilir barkod ISBN recall %{barcode_recall * 100:.2f} < %99")
    if barcode_false_positives:
        violations.append(f"Otomatik ISBN yanlış pozitif: {barcode_false_positives}")
    if not auto:
        violations.append("Otomatik kabul edilmiş alan yok; precision kapısı ölçülemedi")
    return AcceptanceReport(not violations, metrics, tuple(violations))
