"""Unit tests for the classic-engine variant escalation ladder.

These exercise :mod:`kitapkatalog.ocr.variants` on its own, independent of
any engine SDK — the adapters only supply the ``recognize_at`` closure this
module calls.
"""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from kitapkatalog.ocr.contracts import OcrToken
from kitapkatalog.ocr.variants import needs_escalation, run_ladder, select_best


def _token(text: str, confidence: float) -> OcrToken:
    return OcrToken(token_id=f"t:{text}", text=text, confidence=confidence, polygon=None)


def _image(**variant_paths: Path) -> SimpleNamespace:
    return SimpleNamespace(variant_paths=variant_paths)


def test_needs_escalation_is_true_when_nothing_was_read() -> None:
    assert needs_escalation([], threshold=0.80) is True


def test_needs_escalation_looks_at_the_median_not_a_single_outlier() -> None:
    confident = [_token("a", 0.95), _token("b", 0.10), _token("c", 0.90)]
    assert needs_escalation(confident, threshold=0.80) is False  # median 0.90

    weak = [_token("a", 0.95), _token("b", 0.10), _token("c", 0.20)]
    assert needs_escalation(weak, threshold=0.80) is True  # median 0.20


def test_select_best_prefers_more_tokens_above_threshold() -> None:
    weak = [_token("a", 0.50)]
    strong = [_token("a", 0.95), _token("b", 0.91)]

    variant, tokens = select_best({"canonical": weak, "gray_clahe": strong}, threshold=0.80)

    assert variant == "gray_clahe"
    assert tokens == strong


def test_select_best_breaks_an_above_threshold_tie_toward_the_earlier_rung() -> None:
    tied = [_token("a", 0.90)]

    variant, _tokens = select_best(
        {"binarized": tied, "canonical": list(tied)}, threshold=0.80
    )

    assert variant == "canonical"


def test_select_best_breaks_a_zero_score_tie_by_total_confidence() -> None:
    # Neither attempt clears the threshold, so the tie-break falls to total
    # confidence before ladder order.
    weaker = [_token("a", 0.40)]
    stronger = [_token("a", 0.60)]

    variant, tokens = select_best({"canonical": weaker, "gray_clahe": stronger}, threshold=0.80)

    assert variant == "gray_clahe"
    assert tokens == stronger


def test_select_best_rejects_an_empty_result_set() -> None:
    with pytest.raises(ValueError, match="Seçilecek"):
        select_best({}, threshold=0.80)


def test_run_ladder_stops_at_the_first_rung_that_looks_good_enough(tmp_path: Path) -> None:
    calls: list[Path] = []

    def recognize_at(path: Path) -> list[OcrToken]:
        calls.append(path)
        return [_token("İstanbul", 0.97)]

    image = _image(canonical=tmp_path / "canonical.png", gray_clahe=tmp_path / "gray.png")

    variant, tokens, attempts = run_ladder(recognize_at, image, threshold=0.80)

    assert variant == "canonical"
    assert [token.text for token in tokens] == ["İstanbul"]
    assert attempts == ("canonical",)
    assert calls == [tmp_path / "canonical.png"]  # gray_clahe was never tried


def test_run_ladder_escalates_once_and_keeps_the_confident_rung(tmp_path: Path) -> None:
    responses = {
        "canonical.png": [_token("a", 0.40)],
        "gray.png": [_token("a", 0.95), _token("b", 0.92)],
        "binarized.png": [_token("a", 0.10)],
    }

    def recognize_at(path: Path) -> list[OcrToken]:
        return responses[path.name]

    image = _image(
        canonical=tmp_path / "canonical.png",
        gray_clahe=tmp_path / "gray.png",
        binarized=tmp_path / "binarized.png",
    )

    variant, tokens, attempts = run_ladder(recognize_at, image, threshold=0.80)

    assert variant == "gray_clahe"
    assert tokens == responses["gray.png"]
    # binarized is never reached: gray_clahe already looked confident enough,
    # so the engine reports a single, unambiguous winning variant.
    assert attempts == ("canonical", "gray_clahe")


def test_run_ladder_skips_a_variant_the_image_never_prepared(tmp_path: Path) -> None:
    calls: list[str] = []

    def recognize_at(path: Path) -> list[OcrToken]:
        calls.append(path.name)
        return [_token("a", 0.40)]

    image = _image(canonical=tmp_path / "canonical.png", binarized=tmp_path / "binarized.png")

    _variant, _tokens, attempts = run_ladder(recognize_at, image, threshold=0.80)

    assert "gray.png" not in calls
    assert attempts == ("canonical", "binarized")


def test_run_ladder_falls_back_to_select_best_once_every_rung_is_weak(tmp_path: Path) -> None:
    responses = {
        "canonical.png": [_token("a", 0.30)],
        "gray.png": [],
        "binarized.png": [_token("a", 0.60), _token("b", 0.55)],
    }

    def recognize_at(path: Path) -> list[OcrToken]:
        return responses[path.name]

    image = _image(
        canonical=tmp_path / "canonical.png",
        gray_clahe=tmp_path / "gray.png",
        binarized=tmp_path / "binarized.png",
    )

    variant, tokens, attempts = run_ladder(recognize_at, image, threshold=0.80)

    assert attempts == ("canonical", "gray_clahe", "binarized")
    assert variant == "binarized"  # highest total confidence among three weak attempts
    assert tokens == responses["binarized.png"]


def test_run_ladder_raises_when_the_image_prepared_no_ladder_variant(tmp_path: Path) -> None:
    image = _image()

    with pytest.raises(ValueError, match="hiçbir hazır varyant"):
        run_ladder(lambda _path: [], image, threshold=0.80)
