"""Construction and fail-fast validation of the fixed five-engine registry."""

from __future__ import annotations

import gc
import hashlib
import os
import sys
from collections.abc import Collection, Iterable
from pathlib import Path

from kitapkatalog.ocr.contracts import (
    REQUIRED_ENGINE_IDS,
    EngineAvailability,
    EngineUnavailableError,
    OcrEngineAdapter,
)
from kitapkatalog.ocr.easyocr import EasyOcrAdapter
from kitapkatalog.ocr.manifest import EngineSpec, ModelManifest, ModelManifestError
from kitapkatalog.ocr.rapidocr import RapidOcrAdapter
from kitapkatalog.ocr.sidecar import PaddleOcrVlAdapter, SuryaOcrAdapter
from kitapkatalog.ocr.tesseract import TesseractAdapter


class EngineRegistryError(EngineUnavailableError):
    """The registry is not the exact required five-engine set."""


FROZEN_SIDECAR_ENVIRONMENT_VARIABLE = "KITAPKATALOG_FROZEN_VISION_SIDECAR_EXECUTABLE"
VISION_SIDECAR_ARGUMENT = "--vision-sidecar"


class FiveEngineRegistry:
    def __init__(self, engines: Iterable[OcrEngineAdapter]) -> None:
        indexed: dict[str, OcrEngineAdapter] = {}
        duplicates: list[str] = []
        for engine in engines:
            if engine.engine_id in indexed:
                duplicates.append(engine.engine_id)
            indexed[engine.engine_id] = engine
        if duplicates:
            raise EngineRegistryError(f"Yinelenen OCR motoru: {', '.join(sorted(set(duplicates)))}")
        missing = sorted(set(REQUIRED_ENGINE_IDS) - set(indexed))
        extra = sorted(set(indexed) - set(REQUIRED_ENGINE_IDS))
        if missing or extra:
            details: list[str] = []
            if missing:
                details.append(f"eksik: {', '.join(missing)}")
            if extra:
                details.append(f"bilinmeyen: {', '.join(extra)}")
            raise EngineRegistryError(
                "Kayıt tam olarak beş zorunlu motoru içermelidir (" + "; ".join(details) + ")"
            )
        self._engines = tuple(indexed[engine_id] for engine_id in REQUIRED_ENGINE_IDS)

    @property
    def engines(self) -> tuple[OcrEngineAdapter, ...]:
        return self._engines

    def inspect(self) -> tuple[EngineAvailability, ...]:
        return tuple(engine.availability() for engine in self._engines)

    def require_all_available(self) -> None:
        unavailable = [item for item in self.inspect() if not item.available]
        if unavailable:
            details = " | ".join(
                f"{item.engine_id}: {'; '.join(item.problems)}" for item in unavailable
            )
            raise EngineRegistryError(
                "Beş OCR motorunun tamamı hazır olmadan işleme başlanamaz. " + details
            )

    def release_all(self, *, only: Collection[str] | None = None) -> None:
        """Drop resident model state, optionally for a subset of engines.

        ``only`` exists because the memory that must be freed before another
        large model is admitted belongs to the heavy engines.  Dropping the
        light in-process engines as well buys no headroom and makes them reload
        for the next book, so callers guarding a heavy admission name the heavy
        engines instead of clearing everything.
        """

        problems: list[str] = []
        for engine in self._engines:
            if only is not None and engine.engine_id not in only:
                continue
            try:
                engine.release()
            except Exception as exc:
                problems.append(f"{engine.engine_id}: {exc}")
        gc.collect()
        if problems:
            raise EngineRegistryError(
                "OCR modellerinin bir bölümü bellekten bırakılamadı: " + "; ".join(problems)
            )


def _bundle_digest(
    spec: EngineSpec,
    artifact_digests: dict[str, str],
    *,
    runtime_artifacts: tuple[str, ...] = (),
) -> str:
    digest = hashlib.sha256()
    digest.update(spec.engine_id.encode())
    digest.update(b"\0")
    digest.update(spec.version.encode())
    for artifact in sorted(spec.artifacts, key=lambda item: item.path):
        actual = artifact_digests.get(artifact.path)
        if actual is None:
            raise ModelManifestError(f"Doğrulanmış model özeti bulunamadı: {artifact.path}")
        digest.update(b"\0")
        digest.update(artifact.path.encode())
        digest.update(b"=")
        digest.update(actual.encode())
    for relative in sorted(runtime_artifacts):
        actual = artifact_digests.get(relative)
        if actual is None:
            raise ModelManifestError(f"Doğrulanmış runtime özeti bulunamadı: {relative}")
        digest.update(b"\0runtime:")
        digest.update(relative.encode())
        digest.update(b"=")
        digest.update(actual.encode())
    return digest.hexdigest()


def _prefer_bundled_executable(root: Path, configured: str | Path) -> str | Path:
    configured_path = Path(configured)
    if configured_path.parent != Path(".") or configured_path.is_absolute():
        return configured
    for filename in (configured_path.name, f"{configured_path.name}.exe"):
        bundled = root / "bin" / filename
        if bundled.is_file():
            return bundled
    return configured


def _locked_runtime_path(
    root: Path,
    executable: str | Path,
    artifact_digests: dict[str, str],
) -> tuple[str, ...]:
    path = Path(executable)
    try:
        relative = path.resolve().relative_to(root.resolve()).as_posix()
    except (OSError, ValueError):
        return ()
    return (relative,) if relative in artifact_digests else ()


def _default_vision_sidecar(
    vision_backend: str | Path,
) -> tuple[str | Path, tuple[str, ...], dict[str, str]]:
    """Return a source or frozen launch command for the vision JSON worker."""

    frozen_executable = os.environ.get(FROZEN_SIDECAR_ENVIRONMENT_VARIABLE)
    if frozen_executable:
        return (
            Path(frozen_executable).expanduser(),
            (VISION_SIDECAR_ARGUMENT,),
            {"KITAPKATALOG_LLAMA_BACKEND": str(vision_backend)},
        )
    return (
        sys.executable,
        ("-m", "kitapkatalog.ocr.sidecar_runtime"),
        {"KITAPKATALOG_LLAMA_BACKEND": str(vision_backend)},
    )


def build_offline_registry(
    *,
    manifest_path: str | Path,
    model_root: str | Path,
    vision_sidecar: str | Path | None = None,
    vision_backend: str | Path = "llama-server",
    tesseract_executable: str | Path = "tesseract",
    strict_hashes: bool = True,
) -> FiveEngineRegistry:
    """Build the exact five engines from an integrity-checked offline bundle."""

    root = Path(model_root)
    tesseract_executable = _prefer_bundled_executable(root, tesseract_executable)
    vision_backend = _prefer_bundled_executable(root, vision_backend)
    manifest = ModelManifest.load(manifest_path)
    validation = manifest.validate(root, strict_hashes=strict_hashes)
    validation.require()
    specs = {engine.engine_id: engine for engine in manifest.engines}

    def artifact(engine_id: str, suffix: str) -> Path:
        matches = [
            item.path
            for item in specs[engine_id].artifacts
            if item.path.replace("\\", "/").endswith(suffix)
        ]
        if len(matches) != 1:
            raise ModelManifestError(
                f"{engine_id} için {suffix!r} ile biten tek model dosyası bekleniyordu"
            )
        return root / matches[0]

    rapid_spec = specs["rapidocr_ppocrv6"]
    tesseract_spec = specs["tesseract"]
    easy_spec = specs["easyocr"]
    paddle_spec = specs["paddleocr_vl"]
    surya_spec = specs["surya"]
    if vision_sidecar is None:
        (
            sidecar_executable,
            sidecar_args,
            sidecar_environment,
        ) = _default_vision_sidecar(vision_backend)
        checked_backend: str | Path | None = vision_backend
    else:
        sidecar_executable = vision_sidecar
        sidecar_args = ()
        sidecar_environment = {}
        checked_backend = None
    engines: tuple[OcrEngineAdapter, ...] = (
        RapidOcrAdapter(
            model_version=rapid_spec.version,
            model_paths={
                "det": artifact("rapidocr_ppocrv6", "PP-OCRv6_det_small.onnx"),
                "rec": artifact("rapidocr_ppocrv6", "PP-OCRv6_rec_small.onnx"),
                "cls": artifact("rapidocr_ppocrv6", "ch_ppocr_mobile_v2.0_cls_mobile.onnx"),
            },
            medium_model_paths={
                "det": artifact("rapidocr_ppocrv6", "PP-OCRv6_det_medium.onnx"),
                "rec": artifact("rapidocr_ppocrv6", "PP-OCRv6_rec_medium.onnx"),
            },
            artifact_digest=_bundle_digest(rapid_spec, validation.artifact_digests),
        ),
        TesseractAdapter(
            executable=tesseract_executable,
            tessdata_dir=artifact("tesseract", "tur.traineddata").parent,
            model_version=tesseract_spec.version,
            artifact_digest=_bundle_digest(
                tesseract_spec,
                validation.artifact_digests,
                runtime_artifacts=_locked_runtime_path(
                    root, tesseract_executable, validation.artifact_digests
                ),
            ),
        ),
        EasyOcrAdapter(
            model_storage_directory=artifact("easyocr", "latin_g2.pth").parent,
            model_version=easy_spec.version,
            artifact_digest=_bundle_digest(easy_spec, validation.artifact_digests),
        ),
        PaddleOcrVlAdapter(
            executable=sidecar_executable,
            model_path=artifact("paddleocr_vl", "model.gguf"),
            mmproj_path=artifact("paddleocr_vl", "mmproj.gguf"),
            model_version=paddle_spec.version,
            artifact_digest=_bundle_digest(
                paddle_spec,
                validation.artifact_digests,
                runtime_artifacts=_locked_runtime_path(
                    root, vision_backend, validation.artifact_digests
                ),
            ),
            extra_args=sidecar_args,
            environment=sidecar_environment,
            backend_executable=checked_backend,
        ),
        SuryaOcrAdapter(
            executable=sidecar_executable,
            model_path=artifact("surya", "model.gguf"),
            mmproj_path=artifact("surya", "mmproj.gguf"),
            model_version=surya_spec.version,
            artifact_digest=_bundle_digest(
                surya_spec,
                validation.artifact_digests,
                runtime_artifacts=_locked_runtime_path(
                    root, vision_backend, validation.artifact_digests
                ),
            ),
            extra_args=sidecar_args,
            environment=sidecar_environment,
            backend_executable=checked_backend,
        ),
    )
    return FiveEngineRegistry(engines)
