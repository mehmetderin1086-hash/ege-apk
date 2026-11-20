"""Classic-engine cover-variant escalation ladder.

RapidOCR, Tesseract and EasyOCR all read the same three prepared derivatives
(``canonical``, ``gray_clahe``, ``binarized``). Each adapter starts on the
canonical cover and only pays for a second or third pass when the first one
looks weak — no text, or mostly low-confidence tokens. This module holds
that decision so it is deterministic and testable independent of any one
engine's SDK; the adapters only supply a ``recognize_at`` closure over their
own model state.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from kitapkatalog.images import PreparedImage
    from kitapkatalog.ocr.contracts import OcrToken

CLASSIC_VARIANT_LADDER: tuple[str, ...] = ("canonical", "gray_clahe", "binarized")
ALLOWED_CLASSIC_VARIANTS: frozenset[str] = frozenset(CLASSIC_VARIANT_LADDER)
ALLOWED_VISION_VARIANTS: frozenset[str] = frozenset({"canonical"})


def _median(values: Sequence[float]) -> float:
    ordered = sorted(values)
    count = len(ordered)
    middle = count // 2
    if count % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def needs_escalation(tokens: Sequence[OcrToken], *, threshold: float) -> bool:
    """A pass looks weak when it found nothing, or is mostly low-confidence."""

    if not tokens:
        return True
    return _median([token.confidence for token in tokens]) < threshold


def _score(tokens: Sequence[OcrToken], *, threshold: float) -> tuple[int, float]:
    above_threshold = sum(1 for token in tokens if token.confidence >= threshold)
    total_confidence = sum(token.confidence for token in tokens)
    return above_threshold, total_confidence


def select_best(
    results: dict[str, list[OcrToken]],
    *,
    threshold: float,
    ladder: Sequence[str] = CLASSIC_VARIANT_LADDER,
) -> tuple[str, list[OcrToken]]:
    """Pick the attempt with the most confident tokens.

    Ties break toward total confidence, then toward the earlier ladder rung,
    so the outcome never depends on dict iteration order.
    """

    if not results:
        raise ValueError("Seçilecek varyant sonucu yok")
    rank = {variant: index for index, variant in enumerate(ladder)}

    def key(item: tuple[str, list[OcrToken]]) -> tuple[int, float, int]:
        variant, tokens = item
        above_threshold, total_confidence = _score(tokens, threshold=threshold)
        return (above_threshold, total_confidence, -rank.get(variant, len(ladder)))

    variant, tokens = max(results.items(), key=key)
    return variant, tokens


def run_ladder(
    recognize_at: Callable[[Path], list[OcrToken]],
    image: PreparedImage,
    *,
    threshold: float,
    ladder: Sequence[str] = CLASSIC_VARIANT_LADDER,
) -> tuple[str, list[OcrToken], tuple[str, ...]]:
    """Climb ``ladder`` until a rung looks strong enough, then stop.

    ``recognize_at`` closes over whatever engine-specific state a call needs
    (a loaded model, a small/medium escalation of its own, ...); this
    function only decides which prepared derivative to hand it next and
    when the result is good enough to keep. A rung whose derivative was not
    prepared (no OpenCV at prepare-time, say) is skipped rather than failed.
    """

    results: dict[str, list[OcrToken]] = {}
    attempts: list[str] = []
    for variant in ladder:
        path = image.variant_paths.get(variant)
        if path is None:
            continue
        tokens = recognize_at(path)
        results[variant] = tokens
        attempts.append(variant)
        if not needs_escalation(tokens, threshold=threshold):
            return variant, tokens, tuple(attempts)
    if not results:
        raise ValueError("Merdivende denenecek hiçbir hazır varyant yok")
    variant, tokens = select_best(results, threshold=threshold, ladder=ladder)
    return variant, tokens, tuple(attempts)
