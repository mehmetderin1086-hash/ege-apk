from __future__ import annotations

import pytest

from kitapkatalog.calibration import CalibrationBin, ConfidenceCalibrationProfile
from kitapkatalog.consensus import (
    ConsensusError,
    GraphemeSource,
    _independent_confidence,
    align_graphemes,
    grapheme_clusters,
    reconcile_results,
)
from kitapkatalog.ocr.contracts import (
    REQUIRED_ENGINE_IDS,
    EngineOcrResult,
    OcrToken,
)

_TRUSTED_CALIBRATION = ConfidenceCalibrationProfile(
    version="test-calibration-v1",
    bins=(
        CalibrationBin(upper_bound=0.995, calibrated_probability=0.50, sample_count=250),
        CalibrationBin(upper_bound=1.0, calibrated_probability=0.999, sample_count=250),
    ),
    total_samples=500,
)


def _result(
    engine_id: str,
    text: str,
    *,
    image_hash: str = "a" * 64,
    polygon: tuple[tuple[float, float], ...] | None = (
        (10.0, 20.0),
        (300.0, 20.0),
        (300.0, 80.0),
        (10.0, 80.0),
    ),
    confidence: float = 0.995,
) -> EngineOcrResult:
    kind = "classic" if engine_id in REQUIRED_ENGINE_IDS[:3] else "vision"
    return EngineOcrResult(
        engine_id=engine_id,
        model_version="test-v1",
        image_sha256=image_hash,
        variant="canonical",
        tokens=(
            OcrToken(
                token_id=f"{engine_id}:0",
                text=text,
                confidence=confidence,
                polygon=polygon,
                line_id="line:0",
            ),
        ),
        raw_text=text,
        duration_ms=1,
        evidence_kind=kind,
    )


def test_graphemes_keep_turkish_letters_and_combining_marks() -> None:
    assert grapheme_clusters("Iİıi çğöşü") == (
        "I",
        "İ",
        "ı",
        "i",
        " ",
        "ç",
        "ğ",
        "ö",
        "ş",
        "ü",
    )
    assert grapheme_clusters("I\u0307") == ("İ",)
    aligned = align_graphemes("Şiir", "Siir")
    assert len(aligned) == 4


def test_consensus_preserves_turkish_majority_and_provenance() -> None:
    texts = {
        "rapidocr_ppocrv6": "İstanbul Şiirleri",
        "tesseract": "İstanbul Şiirleri",
        "easyocr": "Istanbul Siirleri",
        "paddleocr_vl": "İstanbul Şiirleri",
        "surya": "İstanbul Şiirleri",
    }
    document = reconcile_results(
        (_result(engine, text) for engine, text in texts.items()),
        calibration_profile=_TRUSTED_CALIBRATION,
    )
    assert document.five_ocr_complete
    assert document.raw_text == "İstanbul Şiirleri"
    span = document.spans[0]
    assert span.eligible_for_auto
    assert span.classic_visual_evidence
    assert set(span.supporting_engines) == set(REQUIRED_ENGINE_IDS)
    dotted_i = span.graphemes[0]
    assert dotted_i.value == "İ"
    assert {source.engine_id for source in dotted_i.sources} == {
        "rapidocr_ppocrv6",
        "tesseract",
        "paddleocr_vl",
        "surya",
    }
    assert all(source.token_ids for source in dotted_i.sources)


def test_uncalibrated_consensus_can_never_be_auto_accepted() -> None:
    document = reconcile_results(_result(engine, "İnce Memed") for engine in REQUIRED_ENGINE_IDS)
    assert document.spans
    assert document.spans[0].confidence < 0.98
    assert not document.spans[0].eligible_for_auto


def test_unpositioned_vlm_only_text_cannot_be_auto_accepted() -> None:
    results = [
        _result("rapidocr_ppocrv6", "Kitap Başlığı"),
        _result("tesseract", "Kitap Başlığı"),
        _result("easyocr", "Kitap Başlığı"),
        _result("paddleocr_vl", "Kanıtsız yeni iddia", polygon=None),
        _result("surya", "Kanıtsız yeni iddia", polygon=None),
    ]
    document = reconcile_results(results)
    ungrounded = next(span for span in document.spans if span.text == "Kanıtsız yeni iddia")
    assert not ungrounded.classic_visual_evidence
    assert not ungrounded.eligible_for_auto


def test_different_word_tokenization_is_aligned_as_one_line() -> None:
    results = [_result(engine, "Kitap Başlığı") for engine in REQUIRED_ENGINE_IDS]
    results[1] = EngineOcrResult(
        engine_id="tesseract",
        model_version="test-v1",
        image_sha256="a" * 64,
        variant="canonical",
        tokens=(
            OcrToken(
                "tesseract:0",
                "Kitap",
                0.995,
                ((10.0, 20.0), (120.0, 20.0), (120.0, 80.0), (10.0, 80.0)),
                "line:0",
            ),
            OcrToken(
                "tesseract:1",
                "Başlığı",
                0.995,
                ((130.0, 20.0), (300.0, 20.0), (300.0, 80.0), (130.0, 80.0)),
                "line:0",
            ),
        ),
        raw_text="Kitap Başlığı",
        duration_ms=1,
        evidence_kind="classic",
    )
    span = reconcile_results(results).spans[0]
    assert span.text == "Kitap Başlığı"
    assert {"tesseract:0", "tesseract:1"} <= set(span.source_token_ids)


def test_coarse_vision_box_does_not_merge_and_drop_classic_title_lines() -> None:
    image_hash = "a" * 64

    def classic(engine_id: str, third_line: str) -> EngineOcrResult:
        texts = ("Türkiye'nin", "Bütün", third_line)
        boxes = (
            ((100.0, 100.0), (500.0, 100.0), (500.0, 180.0), (100.0, 180.0)),
            ((220.0, 190.0), (380.0, 190.0), (380.0, 240.0), (220.0, 240.0)),
            ((80.0, 250.0), (520.0, 250.0), (520.0, 340.0), (80.0, 340.0)),
        )
        return EngineOcrResult(
            engine_id=engine_id,
            model_version="test-v1",
            image_sha256=image_hash,
            variant="canonical",
            tokens=tuple(
                OcrToken(
                    token_id=f"{engine_id}:{index}",
                    text=text,
                    confidence=0.995,
                    polygon=boxes[index],
                    line_id=f"line:{index}",
                )
                for index, text in enumerate(texts)
            ),
            raw_text="\n".join(texts),
            duration_ms=1,
            evidence_kind="classic",
        )

    results = [
        classic("rapidocr_ppocrv6", "Ağaçları ve Çalıları"),
        EngineOcrResult(
            engine_id="tesseract",
            model_version="test-v1",
            image_sha256=image_hash,
            variant="canonical",
            tokens=(),
            raw_text="",
            duration_ms=1,
            evidence_kind="classic",
        ),
        classic("easyocr", "Ağaçları ve Çalıları"),
        _result(
            "paddleocr_vl",
            "Türkiye'nin Bütün Ağaçları ve Çalıları",
            polygon=None,
        ),
        _result(
            "surya",
            "Türkiye'nin\nBütün",
            polygon=((70.0, 90.0), (530.0, 90.0), (530.0, 330.0), (70.0, 330.0)),
        ),
    ]

    document = reconcile_results(results)
    normalized_lines = [" ".join(span.text.split()) for span in document.spans]

    assert "Ağaçları ve Çalıları" in normalized_lines
    assert "Ağaçları ve Çalıları" in document.raw_text


def test_consensus_is_independent_of_worker_completion_order() -> None:
    image_hash = "a" * 64
    boxes = (
        ((100.0, 100.0), (500.0, 100.0), (500.0, 180.0), (100.0, 180.0)),
        ((220.0, 190.0), (380.0, 190.0), (380.0, 240.0), (220.0, 240.0)),
        ((80.0, 250.0), (520.0, 250.0), (520.0, 340.0), (80.0, 340.0)),
    )

    def positioned(engine_id: str) -> EngineOcrResult:
        lines = ("Türkiye'nin", "Bütün", "Ağaçları ve Çalıları")
        return EngineOcrResult(
            engine_id=engine_id,
            model_version="test-v1",
            image_sha256=image_hash,
            variant="canonical",
            tokens=tuple(
                OcrToken(
                    token_id=f"{engine_id}:{index}",
                    text=text,
                    confidence=0.995,
                    polygon=boxes[index],
                    line_id=f"line:{index}",
                )
                for index, text in enumerate(lines)
            ),
            raw_text="\n".join(lines),
            duration_ms=1,
            evidence_kind="classic",
        )

    by_engine = {
        "rapidocr_ppocrv6": positioned("rapidocr_ppocrv6"),
        "tesseract": EngineOcrResult(
            engine_id="tesseract",
            model_version="test-v1",
            image_sha256=image_hash,
            variant="canonical",
            tokens=(
                OcrToken(
                    token_id="tesseract:0",
                    text="se",
                    confidence=0.30,
                    polygon=(
                        (250.0, 178.0),
                        (285.0, 178.0),
                        (285.0, 196.0),
                        (250.0, 196.0),
                    ),
                    line_id="line:noise",
                ),
            ),
            raw_text="se",
            duration_ms=1,
            evidence_kind="classic",
        ),
        "easyocr": positioned("easyocr"),
        "paddleocr_vl": _result(
            "paddleocr_vl",
            "Türkiye'nin Bütün Ağaçları ve Çalıları",
            polygon=None,
        ),
        "surya": _result(
            "surya",
            "Türkiye'nin\nBütün",
            polygon=((70.0, 90.0), (530.0, 90.0), (530.0, 330.0), (70.0, 330.0)),
        ),
    }
    canonical = reconcile_results(by_engine[engine_id] for engine_id in REQUIRED_ENGINE_IDS)
    completion_order = ("easyocr", "paddleocr_vl", "rapidocr_ppocrv6", "surya", "tesseract")
    reordered = reconcile_results(by_engine[engine_id] for engine_id in completion_order)

    assert reordered == canonical
    lines = {span.text for span in reordered.spans}
    assert {"Türkiye'nin", "Bütün", "Ağaçları ve Çalıları"} <= lines


def test_one_vote_per_engine_and_all_five_are_required() -> None:
    four = [_result(engine, "Başlık") for engine in REQUIRED_ENGINE_IDS[:4]]
    with pytest.raises(ConsensusError, match="Beş zorunlu motor"):
        reconcile_results(four)
    duplicate = [_result(engine, "Başlık") for engine in REQUIRED_ENGINE_IDS]
    duplicate.append(_result("surya", "Başlık"))
    with pytest.raises(ConsensusError, match="yalnız bir oy"):
        reconcile_results(duplicate)


def test_results_from_different_images_are_rejected() -> None:
    results = [_result(engine, "Başlık") for engine in REQUIRED_ENGINE_IDS]
    results[-1] = _result("surya", "Başlık", image_hash="b" * 64)
    with pytest.raises(ConsensusError, match="aynı kanonik"):
        reconcile_results(results)


def test_classic_engine_must_provide_visual_boxes() -> None:
    results = [_result(engine, "Başlık") for engine in REQUIRED_ENGINE_IDS]
    results[0] = _result("rapidocr_ppocrv6", "Başlık", polygon=None)
    with pytest.raises(ConsensusError, match="konumlandırılmamış"):
        reconcile_results(results)


def test_three_classic_engines_do_not_count_as_three_independent_reads() -> None:
    """The classic engines share one preprocessed image, so they fail together.

    Counting each as fully independent multiplies away a shared error and can
    reach near-certainty on a cover all three misread.
    """

    def source(engine_id: str) -> GraphemeSource:
        return GraphemeSource(
            engine_id=engine_id,
            token_ids=(f"{engine_id}:0",),
            source_index=0,
            source_grapheme="a",
            confidence=0.99,
            has_visual_evidence=True,
        )

    classic_only = _independent_confidence(
        [source(engine) for engine in ("rapidocr_ppocrv6", "tesseract", "easyocr")],
        0,
    )
    mixed = _independent_confidence(
        [source(engine) for engine in ("rapidocr_ppocrv6", "paddleocr_vl", "surya")],
        0,
    )

    # Same number of agreeing engines, but three correlated reads are weaker
    # evidence than one classic plus two independent vision reads.
    assert classic_only < mixed


def test_a_turkish_majority_of_four_is_still_automatically_acceptable() -> None:
    # easyocr's latin model routinely drops Turkish diacritics. Demanding
    # unanimity would send every Turkish title to review.
    texts = {
        "rapidocr_ppocrv6": "İstanbul Şiirleri",
        "tesseract": "İstanbul Şiirleri",
        "easyocr": "Istanbul Siirleri",
        "paddleocr_vl": "İstanbul Şiirleri",
        "surya": "İstanbul Şiirleri",
    }

    document = reconcile_results(
        (_result(engine, text) for engine, text in texts.items()),
        calibration_profile=_TRUSTED_CALIBRATION,
    )

    assert document.spans[0].eligible_for_auto


def test_a_clear_majority_already_matches_the_dictionary_and_is_left_alone() -> None:
    # Support margin is 3 vs 2 (<=1), so the lexicon is consulted, but the
    # deterministic majority is already "GÜNEŞ" — a real Turkish word — so
    # consulting it changes nothing.
    texts = {
        "rapidocr_ppocrv6": "GÜNEŞ",
        "tesseract": "GÜNEŞ",
        "easyocr": "GUNES",
        "paddleocr_vl": "GÜNEŞ",
        "surya": "GUNES",
    }
    results = [_result(engine, text) for engine, text in texts.items()]

    without_lexicon = reconcile_results(results, lexicon=None)
    with_lexicon = reconcile_results(results)

    assert without_lexicon.spans[0].text == "GÜNEŞ"
    assert with_lexicon.spans[0].text == "GÜNEŞ"
    assert not with_lexicon.spans[0].diacritic_lexicon_applied


def test_a_genuine_tie_is_broken_by_the_turkish_dictionary() -> None:
    # Two engines read "GUNES", two read "GÜNEŞ", and a fifth engine's noise
    # ("GXNXS") keeps both diacritic positions tied at 2 supporting engines
    # each, rather than letting a third vote break the tie on its own.
    texts = {
        "rapidocr_ppocrv6": "GUNES",
        "tesseract": "GÜNEŞ",
        "easyocr": "GUNES",
        "paddleocr_vl": "GÜNEŞ",
        "surya": "GXNXS",
    }
    results = [_result(engine, text) for engine, text in texts.items()]

    without_lexicon = reconcile_results(results, lexicon=None)
    with_lexicon = reconcile_results(results)

    # The tie-break the lexicon overrides is deterministic but arbitrary; pin
    # down that it actually differs from the dictionary-corrected answer so
    # this test is proof the lexicon did something, not a no-op.
    assert without_lexicon.spans[0].text == "GUNES"
    assert with_lexicon.spans[0].text == "GÜNEŞ"
    assert with_lexicon.spans[0].diacritic_lexicon_applied

    # The corrected letters carry real GraphemeSource provenance from the
    # engines that actually produced "GÜNEŞ" — nothing was fabricated.
    swapped = {"Ü": "paddleocr_vl", "Ş": "paddleocr_vl"}
    for grapheme in with_lexicon.spans[0].graphemes:
        if grapheme.value in swapped:
            engine_ids = {source.engine_id for source in grapheme.sources}
            assert engine_ids == {"tesseract", "paddleocr_vl"}
            assert all(source.source_grapheme == grapheme.value for source in grapheme.sources)


def test_a_tied_word_absent_from_the_dictionary_keeps_the_deterministic_choice() -> None:
    # Same tie shape as the "GÜNEŞ" case, but neither "ZUNUS" nor "ZÜNÜŞ" is
    # a Turkish word, so the lexicon must have no opinion and the outcome
    # must be identical with and without it.
    texts = {
        "rapidocr_ppocrv6": "ZUNUS",
        "tesseract": "ZÜNÜŞ",
        "easyocr": "ZUNUS",
        "paddleocr_vl": "ZÜNÜŞ",
        "surya": "ZXNXS",
    }
    results = [_result(engine, text) for engine, text in texts.items()]

    without_lexicon = reconcile_results(results, lexicon=None)
    with_lexicon = reconcile_results(results)

    assert with_lexicon.spans[0].text == without_lexicon.spans[0].text
    assert not with_lexicon.spans[0].diacritic_lexicon_applied


def test_the_dictionary_never_produces_a_form_no_engine_observed() -> None:
    texts = {
        "rapidocr_ppocrv6": "GUNES",
        "tesseract": "GÜNEŞ",
        "easyocr": "GUNES",
        "paddleocr_vl": "GÜNEŞ",
        "surya": "GXNXS",
    }
    results = [_result(engine, text) for engine, text in texts.items()]
    document = reconcile_results(results)

    observed_texts = set(texts.values())
    assert document.spans[0].text in observed_texts
