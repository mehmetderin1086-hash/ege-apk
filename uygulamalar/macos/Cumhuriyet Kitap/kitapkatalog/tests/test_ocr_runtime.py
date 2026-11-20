from __future__ import annotations

import json
import sys
from contextlib import suppress
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import pytest
from PIL import Image

from kitapkatalog.images import CoverPreprocessor
from kitapkatalog.ocr.contracts import InvalidEngineResultError, OcrExecutionError
from kitapkatalog.ocr.easyocr import EasyOcrAdapter
from kitapkatalog.ocr.rapidocr import RapidOcrAdapter
from kitapkatalog.ocr.registry import (
    FROZEN_SIDECAR_ENVIRONMENT_VARIABLE,
    VISION_SIDECAR_ARGUMENT,
    _default_vision_sidecar,
)
from kitapkatalog.ocr.sidecar import PaddleOcrVlAdapter
from kitapkatalog.ocr.sidecar_runtime import (
    SidecarRuntimeError,
    _normalize_response,
    _prompt_for,
    _read_image_paths,
)
from kitapkatalog.ocr.tesseract import TesseractAdapter


class _RapidOutput:
    def __init__(self, rows: list[tuple[list[list[float]], str, float]]) -> None:
        self.boxes = [row[0] for row in rows]
        self.txts = [row[1] for row in rows]
        self.scores = [row[2] for row in rows]


class _RapidEngine:
    def __init__(self, rows: list[tuple[list[list[float]], str, float]]) -> None:
        self.output = _RapidOutput(rows)
        self.calls: list[tuple[str, dict[str, Any]]] = []

    def __call__(self, path: str, **kwargs: Any) -> _RapidOutput:
        self.calls.append((path, kwargs))
        return self.output


def _prepared(tmp_path: Path):
    source = tmp_path / "cover.png"
    Image.new("RGB", (600, 900), "white").save(source)
    return CoverPreprocessor(tmp_path / "derivatives").prepare(source)


def _box(left: float, top: float, right: float, bottom: float) -> list[list[float]]:
    return [[left, top], [right, top], [right, bottom], [left, bottom]]


def test_rapid_small_always_runs_and_high_confidence_skips_medium(tmp_path: Path) -> None:
    small = _RapidEngine([(_box(10, 10, 200, 50), "İstanbul", 0.99)])
    medium = _RapidEngine([(_box(10, 10, 200, 50), "unused", 0.99)])
    adapter = RapidOcrAdapter(engine=small, medium_engine=medium)

    result = adapter.recognize(_prepared(tmp_path))

    assert len(small.calls) == 1
    assert medium.calls == []
    assert result.engine_id == "rapidocr_ppocrv6"
    assert result.raw_text == "İstanbul"
    assert result.metadata["small_full_cover"] is True
    assert result.metadata["medium_escalated"] is False


def test_rapid_medium_escalates_and_collapses_to_one_vote(tmp_path: Path) -> None:
    small = _RapidEngine([(_box(10, 10, 200, 50), "Istanbul", 0.55)])
    medium = _RapidEngine(
        [
            (_box(10, 10, 200, 50), "İstanbul", 0.98),
            (_box(10, 80, 300, 120), "Yayınevi", 0.97),
        ]
    )
    adapter = RapidOcrAdapter(
        engine=small,
        medium_engine=medium,
        escalation_threshold=0.80,
    )

    result = adapter.recognize(_prepared(tmp_path))

    assert len(small.calls) == len(medium.calls) == 1
    assert result.engine_id == "rapidocr_ppocrv6"
    assert [token.text for token in result.tokens] == ["İstanbul", "Yayınevi"]
    assert all(token.token_id.startswith("rapidocr_ppocrv6:") for token in result.tokens)
    assert result.metadata["medium_escalated"] is True
    assert result.metadata["small_token_count"] == 1
    assert result.metadata["medium_token_count"] == 2


class _VariantAwareRapidEngine:
    """Routes by a filename marker so which rung was read is observable.

    Every prepared derivative keeps ``PREPROCESSING_VERSION`` in its
    filename (``...-canonical.png``, ``...-gray-clahe.png``,
    ``...-binarized.png``), so a substring match is enough to tell the
    fake which rung of the ladder just called it.
    """

    def __init__(self, by_marker: dict[str, list[tuple[list[list[float]], str, float]]]) -> None:
        self.by_marker = by_marker
        self.calls: list[str] = []

    def __call__(self, path: str, **_kwargs: Any) -> _RapidOutput:
        self.calls.append(path)
        for marker, rows in self.by_marker.items():
            if marker in path:
                return _RapidOutput(rows)
        return _RapidOutput([])


def test_rapid_ladder_escalates_past_a_weak_canonical_and_stops_on_a_confident_rung(
    tmp_path: Path,
) -> None:
    small = _VariantAwareRapidEngine(
        {
            "canonical": [(_box(10, 10, 200, 50), "bulanık", 0.30)],
            "gray-clahe": [(_box(10, 10, 200, 50), "İstanbul", 0.95)],
            "binarized": [(_box(10, 10, 200, 50), "unused", 0.99)],
        }
    )
    medium = _VariantAwareRapidEngine({"canonical": [(_box(10, 10, 200, 50), "bulanık", 0.35)]})
    adapter = RapidOcrAdapter(engine=small, medium_engine=medium, escalation_threshold=0.80)

    result = adapter.recognize(_prepared(tmp_path))

    assert result.variant == "gray_clahe"
    assert result.raw_text == "İstanbul"
    assert result.metadata["variant_attempts"] == ("canonical", "gray_clahe")
    # The weak canonical rung escalated small→medium internally and still
    # only cast one vote for it; the winning gray_clahe rung did not need to.
    assert result.metadata["medium_escalated"] is False
    assert [call for call in small.calls if "canonical" in call]
    assert [call for call in small.calls if "gray-clahe" in call]
    assert not [call for call in small.calls if "binarized" in call]
    assert len(medium.calls) == 1


def test_rapid_ladder_falls_back_to_the_best_variant_when_every_rung_is_weak(
    tmp_path: Path,
) -> None:
    small = _VariantAwareRapidEngine(
        {
            "canonical": [(_box(10, 10, 200, 50), "a", 0.30)],
            "gray-clahe": [(_box(10, 10, 200, 50), "b", 0.20)],
            "binarized": [(_box(10, 10, 200, 50), "c", 0.60), (_box(10, 80, 200, 120), "d", 0.55)],
        }
    )
    medium = _VariantAwareRapidEngine({})  # every rung stays below threshold on the small pass
    adapter = RapidOcrAdapter(engine=small, medium_engine=medium, escalation_threshold=0.80)

    result = adapter.recognize(_prepared(tmp_path))

    assert result.metadata["variant_attempts"] == ("canonical", "gray_clahe", "binarized")
    # binarized has the highest total confidence of the three weak attempts.
    assert result.variant == "binarized"
    assert [token.text for token in result.tokens] == ["c", "d"]


def test_rapid_runtime_settings_expose_the_variant_ladder() -> None:
    adapter = RapidOcrAdapter(
        engine=_RapidEngine([]), medium_engine=_RapidEngine([]), escalation_threshold=0.80
    )

    settings = adapter.runtime_settings()

    assert settings["variant_ladder"] == ["canonical", "gray_clahe", "binarized"]
    assert settings["variant_escalation_threshold"] == 0.80


def test_runtime_settings_change_model_digest() -> None:
    first = RapidOcrAdapter(
        engine=_RapidEngine([]),
        medium_engine=_RapidEngine([]),
        escalation_threshold=0.80,
        artifact_digest="same",
    )
    second = RapidOcrAdapter(
        engine=_RapidEngine([]),
        medium_engine=_RapidEngine([]),
        escalation_threshold=0.81,
        artifact_digest="same",
    )
    assert first.model_digest() != second.model_digest()

    tess_a = TesseractAdapter(languages="tur+eng", psm=11, artifact_digest="same")
    tess_b = TesseractAdapter(languages="tur", psm=6, artifact_digest="same")
    assert tess_a.model_digest() != tess_b.model_digest()
    assert tess_a.runtime_settings()["adapter_revision"] == "tesseract-tsv-v2"
    assert tess_a.runtime_settings()["output_format"] == "tsv-parameter"


def test_tesseract_adapter_revision_invalidates_model_digest() -> None:
    class LegacyTesseractAdapter(TesseractAdapter):
        adapter_revision = "tesseract-tsv-v1"

    legacy = LegacyTesseractAdapter(artifact_digest="same")
    current = TesseractAdapter(artifact_digest="same")

    assert legacy.model_digest() != current.model_digest()


def test_installation_paths_do_not_invalidate_identical_runtime_digest() -> None:
    first_tesseract = TesseractAdapter(
        executable="/Applications/KitapKatalog.app/bin/tesseract",
        artifact_digest="same-runtime-and-models",
    )
    moved_tesseract = TesseractAdapter(
        executable="/private/tmp/KitapKatalog.app/bin/tesseract",
        artifact_digest="same-runtime-and-models",
    )
    assert first_tesseract.model_digest() == moved_tesseract.model_digest()

    first_vision = PaddleOcrVlAdapter(
        executable=sys.executable,
        model_path=Path("/models/paddle/model.gguf"),
        mmproj_path=Path("/models/paddle/mmproj.gguf"),
        model_version="1.6",
        artifact_digest="same-runtime-and-models",
        backend_executable="/Applications/KitapKatalog.app/bin/llama-server",
    )
    moved_vision = PaddleOcrVlAdapter(
        executable=sys.executable,
        model_path=Path("/models/paddle/model.gguf"),
        mmproj_path=Path("/models/paddle/mmproj.gguf"),
        model_version="1.6",
        artifact_digest="same-runtime-and-models",
        backend_executable="/private/tmp/KitapKatalog.app/bin/llama-server",
    )
    assert first_vision.model_digest() == moved_vision.model_digest()


_TESSERACT_TSV_HEADER = (
    "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\t"
    "left\ttop\twidth\theight\tconf\ttext\n"
)


def test_tesseract_uses_parameter_tsv_and_parses_positioned_tokens(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    completed = SimpleNamespace(
        returncode=0,
        stdout=(_TESSERACT_TSV_HEADER + "5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t96.5\tİstanbul\n"),
        stderr="Estimating resolution as 300",
    )
    commands: list[list[str]] = []

    def run(command: list[str], **_kwargs: Any) -> SimpleNamespace:
        commands.append(command)
        return completed

    monkeypatch.setattr("kitapkatalog.ocr.tesseract.subprocess.run", run)
    adapter = TesseractAdapter(executable=sys.executable)

    result = adapter.recognize(_prepared(tmp_path))

    assert commands[0][-2:] == ["-c", "tessedit_create_tsv=1"]
    assert "tsv" not in commands[0]
    assert result.raw_text == "İstanbul"
    assert result.tokens[0].confidence == pytest.approx(0.965)
    assert result.tokens[0].polygon == (
        (10.0, 20.0),
        (110.0, 20.0),
        (110.0, 50.0),
        (10.0, 50.0),
    )


def test_tesseract_rejects_missing_tsv_config_even_with_zero_exit(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "kitapkatalog.ocr.tesseract.subprocess.run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=0,
            stdout="Türkiye'nin Bütün Ağaçları ve Çalıları\n",
            stderr="read_params_file: Can't open tsv",
        ),
    )

    with pytest.raises(OcrExecutionError, match="yapılandırmasını açamadı"):
        TesseractAdapter(executable=sys.executable).recognize(_prepared(tmp_path))


def test_tesseract_rejects_plain_text_without_tsv_header(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "kitapkatalog.ocr.tesseract.subprocess.run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=0,
            stdout="Türkiye'nin Bütün Ağaçları ve Çalıları\n",
            stderr="",
        ),
    )

    with pytest.raises(OcrExecutionError, match="geçerli TSV başlığı"):
        TesseractAdapter(executable=sys.executable).recognize(_prepared(tmp_path))


def test_tesseract_rejects_text_rows_that_produce_no_valid_token(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "kitapkatalog.ocr.tesseract.subprocess.run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=0,
            stdout=(_TESSERACT_TSV_HEADER + "5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t-1\tBaşlık\n"),
            stderr="",
        ),
    )

    with pytest.raises(OcrExecutionError, match="token üretmedi"):
        TesseractAdapter(executable=sys.executable).recognize(_prepared(tmp_path))


def test_tesseract_accepts_valid_empty_tsv_for_a_textless_cover(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(
        "kitapkatalog.ocr.tesseract.subprocess.run",
        lambda *_args, **_kwargs: SimpleNamespace(
            returncode=0,
            stdout=_TESSERACT_TSV_HEADER,
            stderr="",
        ),
    )

    result = TesseractAdapter(executable=sys.executable).recognize(_prepared(tmp_path))

    assert result.tokens == ()
    assert result.raw_text == ""


def test_tesseract_ladder_escalates_to_a_confident_binarized_rung(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    weak = _TESSERACT_TSV_HEADER + "5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t20.0\tbulanık\n"
    strong = _TESSERACT_TSV_HEADER + "5\t1\t1\t1\t1\t1\t10\t20\t100\t30\t92.0\tKitap\n"

    def run(command: list[str], **_kwargs: Any) -> SimpleNamespace:
        stdout = strong if "binarized" in command[1] else weak
        return SimpleNamespace(returncode=0, stdout=stdout, stderr="")

    monkeypatch.setattr("kitapkatalog.ocr.tesseract.subprocess.run", run)

    result = TesseractAdapter(executable=sys.executable).recognize(_prepared(tmp_path))

    assert result.variant == "binarized"
    assert result.raw_text == "Kitap"
    assert result.metadata["variant_attempts"] == ("canonical", "gray_clahe", "binarized")


def test_vision_prompts_and_profiles_are_engine_specific() -> None:
    common = {
        "model_path": "/models/model.gguf",
        "mmproj_path": "/models/mmproj.gguf",
        "image_path": "/images/cover.png",
    }
    paddle = _prompt_for({"engine_id": "paddleocr_vl", **common})
    surya = _prompt_for({"engine_id": "surya", **common})
    assert paddle == "OCR:"
    assert "data-bbox" in surya
    assert paddle != surya


def test_native_paddle_text_and_surya_html_are_normalized() -> None:
    paddle = _normalize_response(
        "İstanbul\nYapı Kredi Yayınları",
        expected_engine_id="paddleocr_vl",
        image_size=(1000, 2000),
    )
    assert [token["text"] for token in paddle["tokens"]] == [
        "İstanbul",
        "Yapı Kredi Yayınları",
    ]
    assert all(token["polygon"] is None for token in paddle["tokens"])

    surya = _normalize_response(
        '<div data-label="Text" data-bbox="100 200 900 300">Türkçe <b>kitap</b></div>',
        expected_engine_id="surya",
        image_size=(1000, 2000),
    )
    assert surya["tokens"][0]["text"] == "Türkçe kitap"
    assert surya["tokens"][0]["polygon"] == [
        [100.0, 400.0],
        [900.0, 400.0],
        [900.0, 600.0],
        [100.0, 600.0],
    ]


def test_default_vision_sidecar_uses_module_in_source_runtime(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv(FROZEN_SIDECAR_ENVIRONMENT_VARIABLE, raising=False)

    executable, arguments, environment = _default_vision_sidecar("/models/llama-server")

    assert executable == sys.executable
    assert arguments == ("-m", "kitapkatalog.ocr.sidecar_runtime")
    assert environment["KITAPKATALOG_LLAMA_BACKEND"] == "/models/llama-server"


def test_default_vision_sidecar_uses_frozen_entry_dispatch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    executable = tmp_path / "KitapKatalog"
    executable.touch()
    monkeypatch.setenv(
        FROZEN_SIDECAR_ENVIRONMENT_VARIABLE,
        str(executable),
    )

    selected, arguments, environment = _default_vision_sidecar("/models/llama-server")

    assert selected == executable
    assert arguments == (VISION_SIDECAR_ARGUMENT,)
    assert environment["KITAPKATALOG_LLAMA_BACKEND"] == "/models/llama-server"


def test_sidecar_normalizer_rejects_wrong_engine_identity() -> None:
    output = json.dumps(
        {
            "protocol": 1,
            "engine_id": "surya",
            "tokens": [{"text": "Kitap", "confidence": 0.9, "polygon": None}],
        }
    )
    with pytest.raises(SidecarRuntimeError, match="motor kimliği"):
        _normalize_response(output, expected_engine_id="paddleocr_vl")


def test_adapter_rejects_sidecar_identity_mismatch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    model = tmp_path / "model.gguf"
    mmproj = tmp_path / "mmproj.gguf"
    model.write_bytes(b"model")
    mmproj.write_bytes(b"mmproj")
    completed = SimpleNamespace(
        returncode=0,
        stdout=json.dumps(
            {
                "protocol": 1,
                "engine_id": "surya",
                "raw_text": "Kitap",
                "tokens": [],
                "warnings": [],
                "metadata": {},
            }
        ),
        stderr="",
    )
    monkeypatch.setattr(
        PaddleOcrVlAdapter,
        "_run_sidecar",
        lambda *args, **kwargs: completed,
    )
    adapter = PaddleOcrVlAdapter(
        executable=sys.executable,
        model_path=model,
        mmproj_path=mmproj,
        model_version="test",
    )
    with pytest.raises(InvalidEngineResultError, match="motor kimliği"):
        adapter.recognize(_prepared(tmp_path))


def _prepared_in(root: Path):
    root.mkdir(parents=True, exist_ok=True)
    return _prepared(root)


def _sidecar_adapter(tmp_path: Path) -> PaddleOcrVlAdapter:
    model = tmp_path / "model.gguf"
    mmproj = tmp_path / "mmproj.gguf"
    model.write_bytes(b"model")
    mmproj.write_bytes(b"mmproj")
    return PaddleOcrVlAdapter(
        executable=sys.executable,
        model_path=model,
        mmproj_path=mmproj,
        model_version="test",
    )


def _sidecar_payload(text: str) -> dict[str, object]:
    return {
        "protocol": 1,
        "engine_id": "paddleocr_vl",
        "raw_text": text,
        "tokens": [{"text": text, "confidence": 0.9, "polygon": None}],
        "warnings": [],
        "metadata": {},
    }


def test_sidecar_batch_sends_one_request_for_every_image(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    images = [_prepared_in(tmp_path / f"book{index}") for index in range(3)]
    requests: list[dict[str, object]] = []

    def fake_run(self, command, request, environment, *, count):
        requests.append(request)
        return SimpleNamespace(
            returncode=0,
            stdout=json.dumps(
                {
                    "protocol": 1,
                    "engine_id": "paddleocr_vl",
                    "results": [_sidecar_payload(f"yüz {index}") for index in range(3)],
                }
            ),
            stderr="",
        )

    monkeypatch.setattr(PaddleOcrVlAdapter, "_run_sidecar", fake_run)

    results = _sidecar_adapter(tmp_path).recognize_many(images)

    # One process for three images is the whole point: one model load, not three.
    assert len(requests) == 1
    assert requests[0]["images"] == [str(image.canonical_path) for image in images]
    assert [result.raw_text for result in results] == ["yüz 0", "yüz 1", "yüz 2"]
    assert [result.image_sha256 for result in results] == [image.image_sha256 for image in images]


def test_sidecar_single_image_response_still_understood(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    completed = SimpleNamespace(
        returncode=0,
        stdout=json.dumps(_sidecar_payload("tek yüz")),
        stderr="",
    )
    monkeypatch.setattr(
        PaddleOcrVlAdapter,
        "_run_sidecar",
        lambda *args, **kwargs: completed,
    )

    result = _sidecar_adapter(tmp_path).recognize(_prepared_in(tmp_path / "single"))

    assert result.raw_text == "tek yüz"


def test_sidecar_rejects_a_result_count_that_does_not_match_the_request(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    completed = SimpleNamespace(
        returncode=0,
        stdout=json.dumps(
            {
                "protocol": 1,
                "engine_id": "paddleocr_vl",
                "results": [_sidecar_payload("yalnız biri")],
            }
        ),
        stderr="",
    )
    monkeypatch.setattr(
        PaddleOcrVlAdapter,
        "_run_sidecar",
        lambda *args, **kwargs: completed,
    )
    images = [_prepared_in(tmp_path / f"cover{index}") for index in range(2)]

    with pytest.raises(InvalidEngineResultError, match="2 görüntü için 1 sonuç"):
        _sidecar_adapter(tmp_path).recognize_many(images)


def test_sidecar_runtime_reads_an_image_group_and_rejects_a_missing_member(
    tmp_path: Path,
) -> None:
    present = tmp_path / "a.png"
    Image.new("RGB", (10, 10), "white").save(present)
    payload = {"image_path": str(present), "images": [str(present), str(present)]}

    assert _read_image_paths(payload) == [str(present.resolve())] * 2

    payload["images"] = [str(present), str(tmp_path / "yok.png")]
    with pytest.raises(SidecarRuntimeError, match=r"images\[1\] bulunamadı"):
        _read_image_paths(payload)

    with pytest.raises(SidecarRuntimeError, match="boş olmayan bir liste"):
        _read_image_paths({"image_path": str(present), "images": []})


def test_sidecar_runtime_defaults_to_the_single_image_field() -> None:
    assert _read_image_paths({"image_path": "/images/cover.png"}) == ["/images/cover.png"]


class _FakeEasyReader:
    """Stands in for easyocr.Reader with the same detail=1 row shape."""

    def __init__(self, rows: list[Any]) -> None:
        self.rows = rows
        self.calls: list[str] = []

    def readtext(self, path: str, **_kwargs: Any) -> list[Any]:
        self.calls.append(path)
        return self.rows


def test_easyocr_maps_rows_to_positioned_tokens(tmp_path: Path) -> None:
    reader = _FakeEasyReader(
        [
            (_box(10, 10, 200, 50), "İstanbul", 0.93),
            (_box(10, 60, 260, 100), "Şiirleri", 0.88),
        ]
    )
    adapter = EasyOcrAdapter(reader=reader)

    result = adapter.recognize(_prepared_in(tmp_path / "easy"))

    assert result.engine_id == "easyocr"
    assert result.evidence_kind == "classic"
    assert result.raw_text == "İstanbul\nŞiirleri"
    # Turkish letters must survive untouched, and the boxes are what makes this
    # engine count as positioned classic evidence.
    assert [token.text for token in result.tokens] == ["İstanbul", "Şiirleri"]
    assert result.tokens[0].polygon == ((10.0, 10.0), (200.0, 10.0), (200.0, 50.0), (10.0, 50.0))
    assert result.tokens[0].confidence == pytest.approx(0.93)


def test_easyocr_ladder_escalates_to_a_confident_gray_clahe_rung(tmp_path: Path) -> None:
    class _VariantAwareEasyReader:
        def __init__(self) -> None:
            self.calls: list[str] = []

        def readtext(self, path: str, **_kwargs: Any) -> list[Any]:
            self.calls.append(path)
            if "gray-clahe" in path:
                return [(_box(10, 10, 200, 50), "Kitap", 0.93)]
            return [(_box(10, 10, 200, 50), "bulanık", 0.20)]

    reader = _VariantAwareEasyReader()

    result = EasyOcrAdapter(reader=reader).recognize(_prepared(tmp_path))

    assert result.variant == "gray_clahe"
    assert result.raw_text == "Kitap"
    assert result.metadata["variant_attempts"] == ("canonical", "gray_clahe")
    assert not any("binarized" in call for call in reader.calls)


def test_easyocr_drops_blank_rows_without_failing(tmp_path: Path) -> None:
    reader = _FakeEasyReader(
        [
            (_box(10, 10, 200, 50), "   ", 0.99),
            (_box(10, 60, 260, 100), "Kitap", 0.91),
        ]
    )

    result = EasyOcrAdapter(reader=reader).recognize(_prepared_in(tmp_path / "blank"))

    assert [token.text for token in result.tokens] == ["Kitap"]


def test_easyocr_confidence_is_clamped_to_the_unit_interval(tmp_path: Path) -> None:
    reader = _FakeEasyReader([(_box(0, 0, 10, 10), "A", 1.4), (_box(0, 20, 10, 30), "B", -0.3)])

    result = EasyOcrAdapter(reader=reader).recognize(_prepared_in(tmp_path / "clamp"))

    assert [token.confidence for token in result.tokens] == [1.0, 0.0]


def test_easyocr_rejects_a_malformed_row_instead_of_guessing(tmp_path: Path) -> None:
    reader = _FakeEasyReader([("kutu değil", "Kitap", 0.9)])

    with pytest.raises(OcrExecutionError, match="beklenmeyen satır"):
        EasyOcrAdapter(reader=reader).recognize(_prepared_in(tmp_path / "bozuk"))


def test_easyocr_reports_a_missing_offline_model_directory(tmp_path: Path) -> None:
    adapter = EasyOcrAdapter(
        reader=_FakeEasyReader([]),
        model_storage_directory=tmp_path / "olmayan",
    )

    availability = adapter.availability()

    assert not availability.available
    assert any("model klasörü" in problem for problem in availability.problems)


def test_easyocr_release_drops_the_reader_so_a_heavy_model_can_load(tmp_path: Path) -> None:
    adapter = EasyOcrAdapter(reader=_FakeEasyReader([(_box(0, 0, 10, 10), "A", 0.9)]))
    adapter.recognize(_prepared_in(tmp_path / "release"))

    adapter.release()

    assert adapter._reader is None


def test_a_timed_out_sidecar_takes_its_grandchild_down_with_it(tmp_path: Path) -> None:
    """A sidecar holds a llama-server worth one to two gigabytes.

    Killing only the sidecar reparents that grandchild, which then keeps its
    memory and its port while no longer being visible to the memory admission
    controller — the accounting silently loses the largest allocation there is.
    """

    import os
    import signal
    import subprocess
    import time

    from kitapkatalog.ocr.sidecar import _terminate_process_group

    marker = tmp_path / "torun.pid"
    # A sidecar stand-in that spawns a long-lived grandchild, like llama-server.
    script = (
        "import os, subprocess, sys, time;"
        f"c = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)']);"
        f"open({str(marker)!r}, 'w').write(str(c.pid));"
        "time.sleep(120)"
    )
    process = subprocess.Popen(
        [sys.executable, "-c", script],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not marker.is_file():
            time.sleep(0.05)
        assert marker.is_file(), "torun süreç başlatılamadı"
        grandchild = int(marker.read_text())
        os.kill(grandchild, 0)  # alive before the group is signalled

        _terminate_process_group(process)

        for _attempt in range(200):
            try:
                os.kill(grandchild, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        else:
            os.kill(grandchild, signal.SIGKILL)
            pytest.fail("torun llama-server süreci yetim kaldı")
    finally:
        with suppress(ProcessLookupError, PermissionError, OSError):
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)


def test_the_sidecar_budget_exceeds_the_one_the_sidecar_uses_itself(tmp_path: Path) -> None:
    adapter = _sidecar_adapter(tmp_path)

    # The sidecar spends startup plus one request budget per image; an outer
    # budget below that fires first and skips the sidecar's own cleanup.
    inner = adapter.startup_timeout_seconds + adapter.timeout_seconds * 4
    outer = adapter.startup_timeout_seconds + adapter.timeout_seconds * 4

    assert outer >= inner
