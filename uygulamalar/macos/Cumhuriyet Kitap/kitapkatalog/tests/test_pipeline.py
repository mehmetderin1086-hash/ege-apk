from __future__ import annotations

import hashlib
import json
from collections.abc import Callable, Iterator, Sequence
from contextlib import AbstractContextManager, contextmanager
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

from kitapkatalog.calibration import CalibrationBin, ConfidenceCalibrationProfile
from kitapkatalog.images import CoverPreprocessor, PreparedImage
from kitapkatalog.isbn import BarcodeObservation
from kitapkatalog.ocr.contracts import (
    REQUIRED_ENGINE_IDS,
    VISION_ENGINE_IDS,
    EngineAvailability,
    EngineOcrResult,
    InvalidEngineResultError,
    OcrEngineAdapter,
    OcrToken,
)
from kitapkatalog.ocr.manifest import ModelManifest
from kitapkatalog.ocr.registry import EngineRegistryError, FiveEngineRegistry
from kitapkatalog.ocr.sidecar_runtime import _normalize_response, _server_command
from kitapkatalog.pipeline import (
    EngineCheckpoint,
    EngineResultStore,
    FiveOcrPipeline,
    InMemoryResultStore,
    PipelineConfig,
    PipelineError,
    ZstdJsonResultStore,
)
from kitapkatalog.resources import HEAVY_ENGINE_IDS

_TRUSTED_CALIBRATION = ConfidenceCalibrationProfile(
    version="test-calibration-v1",
    bins=(
        CalibrationBin(upper_bound=0.995, calibrated_probability=0.50, sample_count=250),
        CalibrationBin(upper_bound=1.0, calibrated_probability=0.999, sample_count=250),
    ),
    total_samples=500,
)


class FakeEngine(OcrEngineAdapter):
    def __init__(
        self,
        engine_id: str,
        *,
        text: str = "ISBN: 978-0-306-40615-7",
        fail_times: int = 0,
        available: bool = True,
        confidence: float = 0.999,
    ) -> None:
        self.engine_id = engine_id
        self.evidence_kind = "classic" if engine_id in REQUIRED_ENGINE_IDS[:3] else "vision"
        self.model_version = "fake-v1"
        self.text = text
        self.fail_times = fail_times
        self.is_available = available
        self.confidence = confidence
        self.calls = 0
        self.releases = 0

    def availability(self) -> EngineAvailability:
        return EngineAvailability(
            self.engine_id,
            self.is_available,
            self.model_version,
            () if self.is_available else ("sahte model eksik",),
        )

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        self.calls += 1
        if self.calls <= self.fail_times:
            raise RuntimeError(f"geçici hata {self.calls}")
        polygon = (
            ((10.0, 10.0), (500.0, 10.0), (500.0, 60.0), (10.0, 60.0))
            if self.evidence_kind == "classic"
            else None
        )
        return EngineOcrResult(
            engine_id=self.engine_id,
            model_version=self.model_version,
            image_sha256=image.image_sha256,
            variant="canonical",
            tokens=(
                OcrToken(
                    token_id=f"{self.engine_id}:0",
                    text=self.text,
                    confidence=self.confidence,
                    polygon=polygon,
                    line_id="line:0",
                ),
            ),
            raw_text=self.text,
            duration_ms=1,
            evidence_kind=self.evidence_kind,
        )

    def release(self) -> None:
        self.releases += 1


class FakeBarcodeScanner:
    def __init__(self, isbn: str = "9780306406157") -> None:
        self.isbn = isbn
        self.calls = 0

    def availability(self) -> tuple[bool, tuple[str, ...]]:
        return True, ()

    def scan(
        self,
        image_path: str | Path,
        *,
        variant: str = "canonical",
    ) -> tuple[BarcodeObservation, ...]:
        self.calls += 1
        return (BarcodeObservation(self.isbn, "EAN13", self.isbn, None, variant),)


def _photo(path: Path, *, color: str = "white") -> Path:
    Image.new("RGB", (1200, 1800), color).save(path)
    return path


def test_preprocessor_applies_exif_orientation_and_is_deterministic(tmp_path: Path) -> None:
    source = tmp_path / "rotated.jpg"
    image = Image.new("RGB", (600, 900), "white")
    exif = image.getexif()
    exif[274] = 6
    image.save(source, exif=exif)
    preprocessor = CoverPreprocessor(tmp_path / "derivatives")
    first = preprocessor.prepare(source)
    second = preprocessor.prepare(source)
    assert (first.width, first.height) == (900, 600)
    assert first.canonical_sha256 == second.canonical_sha256
    assert first.crop_sha256 == second.crop_sha256
    assert first.variant_paths["canonical"].is_file()
    assert first.variant_paths["gray_clahe"].is_file()


def _pipeline(
    tmp_path: Path,
    engines: list[FakeEngine],
    *,
    store: EngineResultStore | None = None,
    scanner: FakeBarcodeScanner | None = None,
    retries: int = 2,
    result_handler: Callable[[EngineCheckpoint], None] | None = None,
    engine_admission: Callable[[str], AbstractContextManager[Any]] | None = None,
    calibration_profile: ConfidenceCalibrationProfile | None = _TRUSTED_CALIBRATION,
) -> FiveOcrPipeline:
    return FiveOcrPipeline(
        registry=FiveEngineRegistry(engines),
        preprocessor=CoverPreprocessor(tmp_path / "derivatives"),
        result_store=store or InMemoryResultStore(),
        barcode_scanner=scanner,
        config=PipelineConfig(max_retries=retries),
        result_handler=result_handler,
        engine_admission=engine_admission,
        calibration_profile=calibration_profile,
    )


def test_all_five_engines_run_and_second_run_is_fully_cached(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    store = InMemoryResultStore()
    scanner = FakeBarcodeScanner()
    pipeline = _pipeline(tmp_path, engines, store=store, scanner=scanner)
    photo = _photo(tmp_path / "cover.jpg")

    first = pipeline.process_cover(photo)
    assert first.five_ocr_complete
    assert first.stage == "completed"
    assert first.isbns == ("9780306406157",)
    assert first.cache_hits == 0
    assert first.consensus.spans[0].source_polygon == first.consensus.spans[0].polygon
    assert [engine.calls for engine in engines] == [1, 1, 1, 1, 1]

    second = pipeline.process_cover(photo)
    assert second.cache_hits == 5
    assert [engine.calls for engine in engines] == [1, 1, 1, 1, 1]
    assert scanner.calls == 4  # Source + corrected cover; outside the five-OCR cache.


def test_engine_is_retried_twice_then_succeeds(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    engines[2].fail_times = 2
    pipeline = _pipeline(tmp_path, engines)
    result = pipeline.process_cover(_photo(tmp_path / "cover.png"))
    assert result.five_ocr_complete
    assert engines[2].calls == 3


def test_pipeline_fails_closed_instead_of_using_four_engines(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    engines[3].fail_times = 99
    pipeline = _pipeline(tmp_path, engines, retries=2)
    with pytest.raises(PipelineError, match="dört motorla devam ettirilmedi"):
        pipeline.process_cover(_photo(tmp_path / "cover.png"))
    assert engines[3].calls == 3
    assert engines[4].calls == 0


def test_unavailable_engine_stops_before_any_inference(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    engines[-1].is_available = False
    pipeline = _pipeline(tmp_path, engines)
    with pytest.raises(EngineRegistryError, match="tamamı hazır olmadan"):
        pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert sum(engine.calls for engine in engines) == 0


def test_registry_rejects_missing_or_duplicate_engines() -> None:
    with pytest.raises(EngineRegistryError, match="eksik"):
        FiveEngineRegistry(FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS[:4])
    duplicates = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    duplicates.append(FakeEngine("surya"))
    with pytest.raises(EngineRegistryError, match="Yinelenen"):
        FiveEngineRegistry(duplicates)


def test_pipeline_confidence_thresholds_are_ordered() -> None:
    with pytest.raises(ValueError, match="Güven eşikleri"):
        PipelineConfig(review_confidence=0.99, auto_confidence=0.98)
    with pytest.raises(ValueError, match="negatif"):
        PipelineConfig(max_retries=-1)


def _result(
    *, engine_id: str, image_sha256: str, variant: str, evidence_kind: str = "classic"
) -> EngineOcrResult:
    polygon = (
        ((10.0, 10.0), (100.0, 10.0), (100.0, 40.0), (10.0, 40.0))
        if evidence_kind == "classic"
        else None
    )
    return EngineOcrResult(
        engine_id=engine_id,
        model_version="test",
        image_sha256=image_sha256,
        variant=variant,
        tokens=(OcrToken(token_id="t:0", text="Kitap", confidence=0.9, polygon=polygon),),
        raw_text="Kitap",
        duration_ms=1,
        evidence_kind=evidence_kind,
    )


def test_validate_result_accepts_every_classic_ladder_variant(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(_photo(tmp_path / "cover.jpg"))

    for variant in ("canonical", "gray_clahe", "binarized"):
        result = _result(engine_id="tesseract", image_sha256=prepared.image_sha256, variant=variant)
        FiveOcrPipeline._validate_result(result, expected_engine_id="tesseract", image=prepared)


def test_validate_result_rejects_a_classic_variant_outside_the_ladder(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(_photo(tmp_path / "cover.jpg"))
    result = _result(engine_id="tesseract", image_sha256=prepared.image_sha256, variant="sepia")

    with pytest.raises(InvalidEngineResultError, match="izin verilmeyen varyant"):
        FiveOcrPipeline._validate_result(result, expected_engine_id="tesseract", image=prepared)


def test_validate_result_rejects_a_non_canonical_variant_from_a_vision_engine(
    tmp_path: Path,
) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(_photo(tmp_path / "cover.jpg"))
    result = _result(
        engine_id="surya",
        image_sha256=prepared.image_sha256,
        variant="gray_clahe",
        evidence_kind="vision",
    )

    with pytest.raises(InvalidEngineResultError, match="izin verilmeyen varyant"):
        FiveOcrPipeline._validate_result(result, expected_engine_id="surya", image=prepared)


def test_barcode_ocr_disagreement_requires_review(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    scanner = FakeBarcodeScanner("9789753638029")
    pipeline = _pipeline(tmp_path, engines, scanner=scanner)
    result = pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert result.isbn_conflict
    assert result.stage == "review"
    assert result.isbns == ("9780306406157", "9789753638029")


def test_single_ocr_isbn_is_not_an_automatic_identifier(tmp_path: Path) -> None:
    engines = [
        FakeEngine(
            engine,
            text=(
                "ISBN: 978-0-306-40615-7" if engine == "tesseract" else "Arka kapak tanıtım yazısı"
            ),
        )
        for engine in REQUIRED_ENGINE_IDS
    ]
    pipeline = _pipeline(tmp_path, engines)
    result = pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert result.isbns == ()
    assert result.stage == "review"
    assert any(candidate.source == "ocr:tesseract" for candidate in result.isbn_candidates)


def test_low_confidence_text_is_routed_to_review(tmp_path: Path) -> None:
    engines = [FakeEngine(engine, confidence=0.55) for engine in REQUIRED_ENGINE_IDS]
    pipeline = _pipeline(tmp_path, engines)
    result = pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert result.stage == "review"
    assert result.consensus.spans
    assert not result.consensus.spans[0].eligible_for_auto


def test_missing_calibration_profile_forces_review(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    pipeline = _pipeline(tmp_path, engines, calibration_profile=None)
    result = pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert result.stage == "review"
    assert not result.consensus.spans[0].eligible_for_auto
    assert any("kalibrasyon" in warning.casefold() for warning in result.warnings)


class FakeBatchEngine(FakeEngine):
    """A vision engine that reloads its model on every invocation.

    ``loads`` counts invocations, not images, which is exactly the quantity the
    warm-up is meant to reduce.
    """

    batches_model_load = True

    def __init__(self, engine_id: str, *, batch_fails: bool = False) -> None:
        super().__init__(engine_id)
        self.loads = 0
        self.batch_sizes: list[int] = []
        self.batch_fails = batch_fails

    def recognize_many(
        self,
        images: Sequence[PreparedImage],
    ) -> tuple[EngineOcrResult, ...]:
        self.loads += 1
        self.batch_sizes.append(len(images))
        if self.batch_fails:
            raise RuntimeError("toplu okuma başarısız")
        return tuple(super(FakeEngine, self).recognize_many(images))


def _batch_engines(**kwargs: Any) -> list[FakeEngine]:
    return [
        FakeBatchEngine(engine_id, **kwargs)
        if engine_id in VISION_ENGINE_IDS
        else FakeEngine(engine_id)
        for engine_id in REQUIRED_ENGINE_IDS
    ]


def _four_surfaces(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    return (
        _photo(tmp_path / "front.jpg", color="white"),
        _photo(tmp_path / "front_inside.jpg", color="gray"),
        _photo(tmp_path / "back_inside.jpg", color="silver"),
        _photo(tmp_path / "back.jpg", color="black"),
    )


def test_warm_up_loads_each_vision_model_once_for_all_four_surfaces(tmp_path: Path) -> None:
    engines = _batch_engines()
    pipeline = _pipeline(tmp_path, engines)
    front, front_inside, back_inside, back = _four_surfaces(tmp_path)

    result = pipeline.process_pair(
        front,
        back,
        front_inside_path=front_inside,
        back_inside_path=back_inside,
    )

    assert result.front.five_ocr_complete
    assert result.back.five_ocr_complete
    vision = [engine for engine in engines if engine.engine_id in VISION_ENGINE_IDS]
    # One invocation covering four surfaces, not four invocations.
    assert [engine.loads for engine in vision] == [1, 1]
    assert [engine.batch_sizes for engine in vision] == [[4], [4]]
    # Every surface still produced its own result from every engine.
    assert [engine.calls for engine in engines] == [4, 4, 4, 4, 4]


def test_warm_up_results_are_not_reported_as_cache_hits(tmp_path: Path) -> None:
    pipeline = _pipeline(tmp_path, _batch_engines())
    front, front_inside, back_inside, back = _four_surfaces(tmp_path)

    first = pipeline.process_pair(
        front, back, front_inside_path=front_inside, back_inside_path=back_inside
    )
    assert first.front.cache_hits == 0
    assert first.back.cache_hits == 0

    second = pipeline.process_pair(
        front, back, front_inside_path=front_inside, back_inside_path=back_inside
    )
    assert second.front.cache_hits == 5
    assert second.back.cache_hits == 5


def test_warm_up_failure_falls_back_to_per_surface_reads(tmp_path: Path) -> None:
    engines = _batch_engines(batch_fails=True)
    pipeline = _pipeline(tmp_path, engines)
    front, front_inside, back_inside, back = _four_surfaces(tmp_path)

    result = pipeline.process_pair(
        front, back, front_inside_path=front_inside, back_inside_path=back_inside
    )

    assert result.front.five_ocr_complete
    assert result.back.five_ocr_complete
    # The batch attempt failed, so every surface was read individually instead.
    assert [engine.calls for engine in engines] == [4, 4, 4, 4, 4]


def test_warm_up_produces_the_same_consensus_as_the_unbatched_path(tmp_path: Path) -> None:
    photo = _photo(tmp_path / "cover.jpg")
    batched = _pipeline(tmp_path / "batched", _batch_engines())
    plain = _pipeline(tmp_path / "plain", [FakeEngine(name) for name in REQUIRED_ENGINE_IDS])

    with batched.warm_covers([photo, photo]):
        warmed = batched.process_cover(photo)
    direct = plain.process_cover(photo)

    assert warmed.consensus.raw_text == direct.consensus.raw_text
    assert warmed.consensus.engine_ids == direct.consensus.engine_ids
    assert warmed.stage == direct.stage
    assert [(span.text, span.confidence) for span in warmed.consensus.spans] == [
        (span.text, span.confidence) for span in direct.consensus.spans
    ]


def test_warm_up_is_skipped_for_a_single_surface(tmp_path: Path) -> None:
    engines = _batch_engines()
    pipeline = _pipeline(tmp_path, engines)
    with pipeline.warm_covers([_photo(tmp_path / "only.jpg")]):
        pass
    # Grouping one image would pay the same model load for no saving.
    assert [engine.loads for engine in engines if engine.engine_id in VISION_ENGINE_IDS] == [0, 0]


def test_pair_runs_five_ocr_on_both_covers(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    pipeline = _pipeline(tmp_path, engines)
    result = pipeline.process_pair(
        _photo(tmp_path / "book_front.jpg", color="white"),
        _photo(tmp_path / "book_back.jpg", color="gray"),
    )
    assert result.front.five_ocr_complete
    assert result.back.five_ocr_complete
    assert result.front.cover_role == "front"
    assert result.back.cover_role == "back"
    assert [engine.calls for engine in engines] == [2, 2, 2, 2, 2]


def test_each_engine_emits_a_complete_durable_checkpoint(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    checkpoints: list[EngineCheckpoint] = []
    pipeline = _pipeline(tmp_path, engines, result_handler=checkpoints.append)
    pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert [checkpoint.result.engine_id for checkpoint in checkpoints] == list(REQUIRED_ENGINE_IDS)
    assert all(len(checkpoint.cache_key) == 64 for checkpoint in checkpoints)
    assert all(len(checkpoint.model_digest) == 64 for checkpoint in checkpoints)
    assert all(len(checkpoint.config_hash) == 64 for checkpoint in checkpoints)
    assert all(not checkpoint.from_cache for checkpoint in checkpoints)
    assert all(checkpoint.raw_result_path is None for checkpoint in checkpoints)
    assert all(checkpoint.cover_role == "unknown" for checkpoint in checkpoints)


def test_zstd_store_exposes_atomic_raw_result_paths(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    checkpoints: list[EngineCheckpoint] = []
    pipeline = _pipeline(
        tmp_path,
        engines,
        store=ZstdJsonResultStore(tmp_path / "ocr-raw"),
        result_handler=checkpoints.append,
    )
    first = pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert first.cache_hits == 0
    assert all(
        checkpoint.raw_result_path is not None
        and checkpoint.raw_result_path.suffix == ".zst"
        and checkpoint.raw_result_path.is_file()
        for checkpoint in checkpoints
    )
    second = pipeline.process_cover(tmp_path / "cover.jpg")
    assert second.cache_hits == 5


def test_registry_releases_all_ocr_models_before_extraction(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    pipeline = _pipeline(tmp_path, engines)
    pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    pipeline.registry.release_all()
    assert [engine.releases for engine in engines] == [1, 1, 1, 1, 1]


def test_registry_can_release_only_the_heavy_engines(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    pipeline = _pipeline(tmp_path, engines)
    pipeline.process_cover(_photo(tmp_path / "cover.jpg"))

    pipeline.registry.release_all(only=HEAVY_ENGINE_IDS)

    # The light in-process engines stay loaded, so the next book does not pay to
    # load them again; only the heavy ones free headroom for Qwen.
    released = {engine.engine_id: engine.releases for engine in engines if engine.releases}
    assert set(released) == set(VISION_ENGINE_IDS)


def test_every_uncached_engine_is_bracketed_by_resource_admission(tmp_path: Path) -> None:
    engines = [FakeEngine(engine) for engine in REQUIRED_ENGINE_IDS]
    events: list[tuple[str, str]] = []

    @contextmanager
    def admission(engine_id: str) -> Iterator[None]:
        events.append(("enter", engine_id))
        try:
            yield
        finally:
            events.append(("exit", engine_id))

    pipeline = _pipeline(tmp_path, engines, engine_admission=admission)
    pipeline.process_cover(_photo(tmp_path / "cover.jpg"))
    assert events == [
        event
        for engine_id in REQUIRED_ENGINE_IDS
        for event in (("enter", engine_id), ("exit", engine_id))
    ]


def test_model_manifest_checks_every_required_artifact_and_hash(tmp_path: Path) -> None:
    relative_artifacts = {
        "rapidocr_ppocrv6": [
            "rapidocr/PP-OCRv6_det_small.onnx",
            "rapidocr/PP-OCRv6_rec_small.onnx",
            "rapidocr/PP-OCRv6_det_medium.onnx",
            "rapidocr/PP-OCRv6_rec_medium.onnx",
            "rapidocr/ch_ppocr_mobile_v2.0_cls_mobile.onnx",
        ],
        "tesseract": ["tessdata/tur.traineddata", "tessdata/eng.traineddata"],
        "easyocr": ["easyocr/craft_mlt_25k.pth", "easyocr/latin_g2.pth"],
        "paddleocr_vl": ["paddleocr-vl/model.gguf", "paddleocr-vl/mmproj.gguf"],
        "surya": ["surya/model.gguf", "surya/mmproj.gguf"],
    }
    model_root = tmp_path / "models"
    engines = []
    for engine_id, paths in relative_artifacts.items():
        artifacts = []
        for relative in paths:
            path = model_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            content = f"{engine_id}:{relative}".encode()
            path.write_bytes(content)
            artifacts.append({"path": relative, "sha256": hashlib.sha256(content).hexdigest()})
        engines.append(
            {
                "id": engine_id,
                "required": True,
                "family": "test",
                "version": "test-v1",
                "license": "test",
                "artifacts": artifacts,
            }
        )
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "runtime_offline": True,
                "engines": engines,
            }
        ),
        encoding="utf-8",
    )
    manifest = ModelManifest.load(manifest_path)
    assert manifest.validate(model_root).valid

    missing_medium_payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    rapid_artifacts = missing_medium_payload["engines"][0]["artifacts"]
    missing_medium_payload["engines"][0]["artifacts"] = [
        item for item in rapid_artifacts if not item["path"].endswith("PP-OCRv6_rec_medium.onnx")
    ]
    missing_medium_path = tmp_path / "missing-medium.json"
    missing_medium_path.write_text(json.dumps(missing_medium_payload), encoding="utf-8")
    missing_medium = ModelManifest.load(missing_medium_path).validate(model_root)
    assert not missing_medium.valid
    assert any("PP-OCRv6_rec_medium.onnx" in error for error in missing_medium.errors)

    corrupt = model_root / relative_artifacts["surya"][0]
    corrupt.write_bytes(b"corrupt")
    validation = manifest.validate(model_root)
    assert not validation.valid
    assert any("bütünlük hatası" in error for error in validation.errors)


def test_local_llama_server_sidecar_is_offline_and_schema_normalized() -> None:
    request = {
        "engine_id": "paddleocr_vl",
        "model_path": "/models/model.gguf",
        "mmproj_path": "/models/mmproj.gguf",
        "image_path": "/images/cover.png",
    }
    command = _server_command("/runtime/llama-server", request, 18765)
    assert command[0] == "/runtime/llama-server"
    assert "--offline" in command
    assert command[command.index("--host") + 1] == "127.0.0.1"
    assert command[command.index("--parallel") + 1] == "1"

    payload = _normalize_response(
        'log line\n```json\n{"protocol":1,"raw_text":"İstanbul",'
        '"tokens":[{"text":"İstanbul","confidence":0.99,'
        '"polygon":[[1,2],[3,2],[3,4],[1,4]]}],"warnings":[]}\n```'
    )
    assert payload["protocol"] == 1
    assert payload["raw_text"] == "İstanbul"
    assert payload["tokens"][0]["polygon"][0] == [1.0, 2.0]
