"""Build-time assembly of the fully offline OCR/model directory.

This module deliberately has no download code.  Distributors place licensed
artifacts in a source directory, run :func:`assemble_bundle`, and ship the
resulting locked manifest together with the application.  At runtime,
``ModelManager`` only verifies those bytes and refuses an incomplete five-OCR
bundle.
"""

from __future__ import annotations

import json
import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from kitapkatalog.model_manager import load_manifest, sha256_file

REQUIRED_EXECUTABLES = ("tesseract", "llama-server")


class BundleAssemblyError(RuntimeError):
    """A local source bundle is missing or violates the manifest contract."""


@dataclass(frozen=True, slots=True)
class BundleAssembly:
    target: Path
    manifest: Path
    artifact_count: int
    byte_count: int
    executables: tuple[str, ...]


def _safe_relative(value: str) -> Path:
    posix = PurePosixPath(value)
    if posix.is_absolute() or not posix.parts or ".." in posix.parts:
        raise BundleAssemblyError(f"Güvensiz manifest yolu: {value}")
    return Path(*posix.parts)


def _all_specs(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    return [*manifest.get("engines", []), manifest["extractor"]]


def _all_artifacts(manifest: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    artifacts = [
        (str(spec["id"]), artifact)
        for spec in _all_specs(manifest)
        for artifact in spec.get("artifacts", [])
    ]
    artifacts.extend(("runtime", artifact) for artifact in manifest.get("runtime_artifacts", []))
    artifacts.extend(("optional", artifact) for artifact in manifest.get("optional_artifacts", []))
    return artifacts


def _atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    part = path.with_name(f".{path.name}.{os.getpid()}.part")
    try:
        part.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(part, path)
    finally:
        part.unlink(missing_ok=True)


def lock_manifest(manifest: dict[str, Any], model_root: Path) -> dict[str, Any]:
    """Return a deep-copied manifest with every artifact SHA-256 populated."""

    locked = json.loads(json.dumps(manifest))
    missing: list[str] = []
    for owner, artifact in _all_artifacts(locked):
        relative = _safe_relative(str(artifact["path"]))
        source = model_root / relative
        if not source.is_file():
            missing.append(f"{owner}: {relative.as_posix()}")
            continue
        artifact["sha256"] = sha256_file(source)
        artifact["size"] = source.stat().st_size
    if missing:
        raise BundleAssemblyError(
            "Model paketi eksik; hiçbir hash manifesti yazılmadı: " + ", ".join(missing)
        )
    locked["locked"] = True
    locked["network_downloads_allowed"] = False
    return locked


def _copy_file(source: Path, destination: Path) -> int:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    return destination.stat().st_size


def _copy_runtime_tree(
    source_root: Path,
    staging: Path,
) -> tuple[int, int, list[dict[str, Any]]]:
    """Copy dylibs/data needed by native wrappers and return manifest entries."""

    runtime_root = source_root / "runtime"
    if not runtime_root.is_dir():
        return 0, 0, []
    byte_count = 0
    artifact_count = 0
    declarations: list[dict[str, Any]] = []
    for source in sorted(runtime_root.rglob("*")):
        if not source.is_file():
            continue
        relative = Path("runtime") / source.relative_to(runtime_root)
        destination = staging / relative
        byte_count += _copy_file(source, destination)
        if os.access(source, os.X_OK):
            destination.chmod(destination.stat().st_mode | 0o111)
        artifact_count += 1
        declarations.append(
            {
                "path": relative.as_posix(),
                "sha256": None,
                "executable": os.access(source, os.X_OK),
            }
        )
    return byte_count, artifact_count, declarations


def _copy_installed_rapidocr(staging: Path) -> int:
    try:
        from rapidocr import __file__ as rapidocr_init
    except ImportError as exc:
        raise BundleAssemblyError(
            "RapidOCR paketi kurulu değil; [rapidocr] bağımlılığını build ortamına kurun"
        ) from exc
    source_root = Path(rapidocr_init).resolve().parent / "models"
    total = 0
    for name in (
        "PP-OCRv6_det_small.onnx",
        "PP-OCRv6_rec_small.onnx",
        "ch_ppocr_mobile_v2.0_cls_mobile.onnx",
    ):
        source = source_root / name
        if not source.is_file():
            raise BundleAssemblyError(f"Kurulu RapidOCR modeli bulunamadı: {source}")
        total += _copy_file(source, staging / "rapidocr" / name)
    return total


def assemble_bundle(
    source_root: Path,
    target_root: Path,
    *,
    template_manifest: Path | None = None,
    copy_installed_rapidocr: bool = True,
    require_executables: bool = True,
) -> BundleAssembly:
    """Copy local assets into a new directory, hash-lock, then atomically publish.

    ``source_root`` mirrors the paths in ``model_manifest.json``.  It may omit
    RapidOCR small ONNX files when ``copy_installed_rapidocr`` is true. Medium
    detector/recognizer files are always copied from ``source_root``; the build
    helper never downloads them. The source should contain platform-native
    ``bin/tesseract`` and ``bin/llama-server`` for a distributable package.
    """

    source_root = Path(source_root).resolve()
    target_root = Path(target_root).resolve()
    if source_root == target_root:
        raise BundleAssemblyError("Kaynak ve hedef model klasörü aynı olamaz")
    if target_root.exists():
        raise BundleAssemblyError(f"Hedef zaten var; üzerine yazılmadı: {target_root}")
    manifest = load_manifest(template_manifest)
    parent = target_root.parent
    parent.mkdir(parents=True, exist_ok=True)
    byte_count = 0
    artifact_count = 0
    executables: list[str] = []

    with tempfile.TemporaryDirectory(prefix=".kitapkatalog-models-", dir=parent) as temp:
        staging = Path(temp) / "models"
        staging.mkdir()
        rapidocr_paths = {
            "rapidocr/PP-OCRv6_det_small.onnx",
            "rapidocr/PP-OCRv6_rec_small.onnx",
            "rapidocr/ch_ppocr_mobile_v2.0_cls_mobile.onnx",
        }
        if copy_installed_rapidocr:
            byte_count += _copy_installed_rapidocr(staging)
            artifact_count += len(rapidocr_paths)

        missing: list[str] = []
        for spec in _all_specs(manifest):
            for artifact in spec.get("artifacts", []):
                relative = _safe_relative(str(artifact["path"]))
                if copy_installed_rapidocr and relative.as_posix() in rapidocr_paths:
                    continue
                source = source_root / relative
                if not source.is_file():
                    missing.append(f"{spec['id']}: {relative.as_posix()}")
                    continue
                byte_count += _copy_file(source, staging / relative)
                artifact_count += 1
        if missing:
            raise BundleAssemblyError("Yerel model dosyaları eksik: " + ", ".join(missing))

        runtime_bytes, runtime_count, runtime_declarations = _copy_runtime_tree(
            source_root, staging
        )
        byte_count += runtime_bytes
        artifact_count += runtime_count

        for executable in REQUIRED_EXECUTABLES:
            candidates = (
                source_root / "bin" / executable,
                source_root / "bin" / f"{executable}.exe",
            )
            source = next((item for item in candidates if item.is_file()), None)
            if source is None:
                if require_executables:
                    raise BundleAssemblyError(f"Yerel çalıştırılabilir dosya eksik: {executable}")
                continue
            destination = staging / "bin" / source.name
            byte_count += _copy_file(source, destination)
            destination.chmod(destination.stat().st_mode | 0o111)
            executables.append(source.name)
            artifact_count += 1

        calibration_source = source_root / "calibration" / "ensemble.json"
        if calibration_source.is_file():
            from kitapkatalog.calibration import (
                CalibrationError,
                ConfidenceCalibrationProfile,
            )

            try:
                ConfidenceCalibrationProfile.load(calibration_source)
            except CalibrationError as exc:
                raise BundleAssemblyError(f"Kalibrasyon profili bozuk: {exc}") from exc
            relative = Path("calibration") / "ensemble.json"
            byte_count += _copy_file(calibration_source, staging / relative)
            artifact_count += 1
            manifest["optional_artifacts"] = [
                {
                    "path": relative.as_posix(),
                    "sha256": None,
                    "role": "confidence_calibration",
                }
            ]

        manifest["runtime_artifacts"] = [
            {
                "path": f"bin/{name}",
                "sha256": None,
                "executable": True,
            }
            for name in executables
        ] + runtime_declarations
        locked = lock_manifest(manifest, staging)
        locked["bundle"] = {
            "platform": os.uname().sysname if hasattr(os, "uname") else os.name,
            "executables": executables,
            "artifact_count": artifact_count,
            "byte_count": byte_count,
        }
        locked_path = staging / "model_manifest.lock.json"
        _atomic_json(locked_path, locked)
        os.replace(staging, target_root)

    return BundleAssembly(
        target=target_root,
        manifest=target_root / "model_manifest.lock.json",
        artifact_count=artifact_count,
        byte_count=byte_count,
        executables=tuple(executables),
    )


def verify_locked_bundle(model_root: Path) -> list[str]:
    """Return human-readable violations; an empty list means byte-level validity."""

    model_root = Path(model_root)
    manifest_path = model_root / "model_manifest.lock.json"
    if not manifest_path.is_file():
        return ["model_manifest.lock.json eksik"]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"kilit manifesti okunamadı: {exc}"]
    problems: list[str] = []
    if not manifest.get("locked") or manifest.get("network_downloads_allowed") is not False:
        problems.append("manifest çevrimdışı ve kilitli değil")
    for owner, artifact in _all_artifacts(manifest):
        relative = _safe_relative(str(artifact["path"]))
        path = model_root / relative
        if not path.is_file():
            problems.append(f"{owner}: {relative.as_posix()} eksik")
            continue
        expected = artifact.get("sha256")
        if not expected:
            problems.append(f"{owner}: {relative.as_posix()} hash'i eksik")
        elif sha256_file(path) != expected:
            problems.append(f"{owner}: {relative.as_posix()} SHA-256 uyuşmuyor")
        if "size" in artifact and path.stat().st_size != int(artifact["size"]):
            problems.append(f"{owner}: {relative.as_posix()} boyutu uyuşmuyor")
    return problems
