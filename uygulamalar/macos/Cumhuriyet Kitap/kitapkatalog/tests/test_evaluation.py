from __future__ import annotations

import pytest

from kitapkatalog.evaluation import (
    CalibrationPoint,
    DatasetSplit,
    FieldEvaluation,
    _turkish_error_count,
    aligned_characters,
    character_error_rate,
    deterministic_split,
    edit_distance,
    evaluate_acceptance,
    expected_calibration_error,
)


def test_turkish_characters_are_not_folded() -> None:
    assert edit_distance("Iğdır", "İgdir") == 3
    assert character_error_rate("ş", "s") == 1.0


def test_group_split_is_stable_and_well_formed() -> None:
    first = deterministic_split("work:12|edition:3|session:99")
    assert first is deterministic_split("work:12|edition:3|session:99")
    assert first in set(DatasetSplit)


def test_ece_uses_confidence_bins() -> None:
    points = [CalibrationPoint(0.9, True), CalibrationPoint(0.8, False)]
    assert round(expected_calibration_error(points, bins=2), 2) == 0.35


def test_acceptance_report_passes_good_fixture() -> None:
    fields = [
        FieldEvaluation(
            predicted="İnce Memed",
            expected="İnce Memed",
            confidence=0.99,
            auto_accepted=True,
            has_visual_provenance=True,
            engine_support=("rapidocr_ppocrv6", "tesseract"),
        )
    ]
    report = evaluate_acceptance(
        fields,
        expected_ocr_texts=["İnce Memed"],
        ensemble_ocr_texts=["İnce Memed"],
        single_engine_ocr_texts={"tesseract": ["İnce Merned"]},
        readable_barcodes=["9789750800002"],
        predicted_barcodes=["9789750800002"],
    )
    # With a perfect ensemble the relative CER improvement is 100%.
    assert report.passed
    assert report.metrics.provenance_coverage == 1.0


def test_false_positive_isbn_fails_gate() -> None:
    report = evaluate_acceptance(
        [
            FieldEvaluation(
                predicted="Başlık",
                expected="Başlık",
                confidence=0.99,
                auto_accepted=True,
                has_visual_provenance=True,
                engine_support=("easyocr", "tesseract"),
            )
        ],
        expected_ocr_texts=["Başlık"],
        ensemble_ocr_texts=["Başlık"],
        single_engine_ocr_texts={},
        readable_barcodes=["9789750800002"],
        predicted_barcodes=["9789750800002", "9780000000000"],
    )
    assert not report.passed
    assert any("yanlış pozitif" in violation for violation in report.violations)


def test_alignment_keeps_one_insertion_from_condemning_the_rest() -> None:
    # One spurious "y" early on, and no Turkish letter actually mangled.
    # Comparing position by position shifted everything after the insertion and
    # counted six Turkish errors that never happened.
    assert _turkish_error_count("Ağaçları", "Ayğaçları") == 0


def test_a_shift_does_not_hide_a_real_turkish_error_either() -> None:
    # Same insertion, but "ğ" really was read as "g": exactly one error.
    assert _turkish_error_count("Ağaçları", "Aygaçları") == 1


def test_turkish_letters_are_still_counted_when_they_are_actually_wrong() -> None:
    assert _turkish_error_count("İstanbul", "Istanbul") == 1
    assert _turkish_error_count("çğıöşü", "cgiosu") == 6


def test_alignment_reports_missing_sides_as_empty_strings() -> None:
    pairs = aligned_characters("ab", "b")
    assert pairs == [("a", ""), ("b", "b")]


def test_calibration_error_is_also_measured_over_every_candidate() -> None:
    # Two badly-calibrated low-confidence candidates that were never accepted:
    # measuring only the accepted subset cannot see them at all.
    fields = [
        FieldEvaluation("Kitap", "Kitap", 0.99, True, True, ("a", "b")),
        FieldEvaluation("Yanlış", "Doğru", 0.10, False, True, ("a",)),
        FieldEvaluation("Yanlış", "Doğru", 0.10, False, True, ("a",)),
    ]

    report = evaluate_acceptance(
        fields,
        expected_ocr_texts=["x"],
        ensemble_ocr_texts=["x"],
        single_engine_ocr_texts={"a": ["x"]},
    )

    assert report.metrics.ece == pytest.approx(0.01, abs=1e-9)
    assert report.metrics.ece_all_candidates > report.metrics.ece


def test_recall_exposes_a_pipeline_that_accepts_almost_nothing() -> None:
    # Nine correct answers, only one of them accepted: perfect precision but a
    # tenth of the achievable coverage.
    fields = [FieldEvaluation("A", "A", 0.99, index == 0, True, ("a",)) for index in range(9)]

    report = evaluate_acceptance(
        fields,
        expected_ocr_texts=["x"],
        ensemble_ocr_texts=["x"],
        single_engine_ocr_texts={"a": ["x"]},
    )

    assert report.metrics.automatic_precision == 1.0
    assert report.metrics.automatic_recall == pytest.approx(1 / 9)
    assert report.metrics.automatic_f1 < 0.2


def test_field_breakdown_separates_a_solved_field_from_an_unsolved_one() -> None:
    fields = [
        FieldEvaluation("9789753638029", "9789753638029", 0.99, True, True, ("a",), "isbn"),
        FieldEvaluation("9789753638029", "9789753638029", 0.99, True, True, ("a",), "isbn"),
        FieldEvaluation("Yanlış Başlık", "Doğru Başlık", 0.99, True, True, ("a",), "title"),
    ]

    report = evaluate_acceptance(
        fields,
        expected_ocr_texts=["x"],
        ensemble_ocr_texts=["x"],
        single_engine_ocr_texts={"a": ["x"]},
    )

    by_field = report.metrics.by_field
    assert by_field["isbn"].precision == 1.0
    assert by_field["title"].precision == 0.0
    # The single overall number would have read 2/3 and hidden which field fails.
    assert report.metrics.automatic_precision == pytest.approx(2 / 3)
