from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

import kitapkatalog.model_bundle as model_bundle
from kitapkatalog.model_bundle import (
    BundleAssemblyError,
    assemble_bundle,
    lock_manifest,
    verify_locked_bundle,
)
from kitapkatalog.model_manager import load_manifest


def _manifest() -> dict:
    return {
        "schema_version": 1,
        "engines": [
            {
                "id": "one",
                "artifacts": [{"path": "one/model.bin", "sha256": None}],
            }
        ],
        "extractor": {
            "id": "fields",
            "artifacts": [{"path": "fields/model.gguf", "sha256": None}],
        },
    }


def test_lock_manifest_hashes_every_artifact(tmp_path: Path) -> None:
    (tmp_path / "one").mkdir()
    (tmp_path / "fields").mkdir()
    (tmp_path / "one/model.bin").write_bytes(b"ocr")
    (tmp_path / "fields/model.gguf").write_bytes(b"qwen")
    locked = lock_manifest(_manifest(), tmp_path)
    assert locked["locked"] is True
    assert locked["network_downloads_allowed"] is False
    assert locked["engines"][0]["artifacts"][0]["sha256"] == hashlib.sha256(b"ocr").hexdigest()
    assert _manifest()["engines"][0]["artifacts"][0]["sha256"] is None


def test_lock_manifest_is_all_or_nothing(tmp_path: Path) -> None:
    with pytest.raises(BundleAssemblyError, match="hiçbir hash"):
        lock_manifest(_manifest(), tmp_path)


def test_verify_detects_tampering(tmp_path: Path) -> None:
    (tmp_path / "one").mkdir()
    (tmp_path / "fields").mkdir()
    model = tmp_path / "one/model.bin"
    model.write_bytes(b"ocr")
    (tmp_path / "fields/model.gguf").write_bytes(b"qwen")
    locked = lock_manifest(_manifest(), tmp_path)
    (tmp_path / "model_manifest.lock.json").write_text(json.dumps(locked), encoding="utf-8")
    assert verify_locked_bundle(tmp_path) == []
    model.write_bytes(b"changed")
    problems = verify_locked_bundle(tmp_path)
    assert any("SHA-256" in problem for problem in problems)


def test_rejects_traversal_path(tmp_path: Path) -> None:
    manifest = _manifest()
    manifest["engines"][0]["artifacts"][0]["path"] = "../secret"
    with pytest.raises(BundleAssemblyError, match="Güvensiz"):
        lock_manifest(manifest, tmp_path)


def test_runtime_executables_are_hash_locked_and_verified(tmp_path: Path) -> None:
    manifest = _manifest()
    manifest["runtime_artifacts"] = [{"path": "bin/tesseract", "sha256": None, "executable": True}]
    (tmp_path / "one").mkdir()
    (tmp_path / "fields").mkdir()
    (tmp_path / "bin").mkdir()
    (tmp_path / "one/model.bin").write_bytes(b"ocr")
    (tmp_path / "fields/model.gguf").write_bytes(b"qwen")
    runtime = tmp_path / "bin/tesseract"
    runtime.write_bytes(b"runtime")

    locked = lock_manifest(manifest, tmp_path)
    assert locked["runtime_artifacts"][0]["sha256"] == hashlib.sha256(b"runtime").hexdigest()
    (tmp_path / "model_manifest.lock.json").write_text(json.dumps(locked), encoding="utf-8")
    assert verify_locked_bundle(tmp_path) == []

    runtime.write_bytes(b"tampered")
    assert any(
        "runtime" in problem and "SHA-256" in problem for problem in verify_locked_bundle(tmp_path)
    )


def test_assembly_takes_medium_models_from_local_source(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = tmp_path / "source"
    target = tmp_path / "bundle"
    source.mkdir()
    manifest = load_manifest()
    installed_paths = {
        "rapidocr/PP-OCRv6_det_small.onnx",
        "rapidocr/PP-OCRv6_rec_small.onnx",
        "rapidocr/ch_ppocr_mobile_v2.0_cls_mobile.onnx",
    }
    for spec in [*manifest["engines"], manifest["extractor"]]:
        for artifact in spec["artifacts"]:
            if artifact["path"] in installed_paths:
                continue
            path = source / artifact["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"local:{artifact['path']}".encode())
    for executable in ("tesseract", "llama-server"):
        path = source / "bin" / executable
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(f"runtime:{executable}".encode())
    dylib = source / "runtime" / "llama" / "libmtmd.dylib"
    dylib.parent.mkdir(parents=True)
    dylib.write_bytes(b"support-library")
    alias = source / "runtime" / "llama" / "libmtmd.0.dylib"
    alias.symlink_to(dylib.name)

    def fake_installed(staging: Path) -> int:
        total = 0
        for relative in installed_paths:
            path = staging / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            payload = f"installed:{relative}".encode()
            path.write_bytes(payload)
            total += len(payload)
        return total

    monkeypatch.setattr(model_bundle, "_copy_installed_rapidocr", fake_installed)
    outcome = assemble_bundle(source, target)

    assert (
        target / "rapidocr/PP-OCRv6_det_medium.onnx"
    ).read_bytes() == b"local:rapidocr/PP-OCRv6_det_medium.onnx"
    assert (
        target / "rapidocr/PP-OCRv6_rec_medium.onnx"
    ).read_bytes() == b"local:rapidocr/PP-OCRv6_rec_medium.onnx"
    locked = json.loads(outcome.manifest.read_text(encoding="utf-8"))
    assert {item["path"] for item in locked["runtime_artifacts"]} == {
        "bin/tesseract",
        "bin/llama-server",
        "runtime/llama/libmtmd.dylib",
        "runtime/llama/libmtmd.0.dylib",
    }
    assert not (target / "runtime/llama/libmtmd.0.dylib").is_symlink()
    assert (target / "runtime/llama/libmtmd.0.dylib").read_bytes() == b"support-library"
    assert all(item["sha256"] for item in locked["runtime_artifacts"])
    assert verify_locked_bundle(target) == []


def test_optional_calibration_is_validated_copied_and_hash_locked(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    source = tmp_path / "source"
    target = tmp_path / "bundle"
    source.mkdir()
    manifest = load_manifest()
    installed_paths = {
        "rapidocr/PP-OCRv6_det_small.onnx",
        "rapidocr/PP-OCRv6_rec_small.onnx",
        "rapidocr/ch_ppocr_mobile_v2.0_cls_mobile.onnx",
    }
    for spec in [*manifest["engines"], manifest["extractor"]]:
        for artifact in spec["artifacts"]:
            if artifact["path"] in installed_paths:
                continue
            path = source / artifact["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"local:{artifact['path']}".encode())
    for executable in ("tesseract", "llama-server"):
        path = source / "bin" / executable
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(f"runtime:{executable}".encode())
    calibration = source / "calibration" / "ensemble.json"
    calibration.parent.mkdir()
    calibration.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "version": "real-set-v1",
                "total_samples": 500,
                "minimum_samples": 200,
                "bins": [
                    {
                        "upper_bound": 1.0,
                        "calibrated_probability": 0.99,
                        "sample_count": 500,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    def fake_installed(staging: Path) -> int:
        total = 0
        for relative in installed_paths:
            path = staging / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            payload = f"installed:{relative}".encode()
            path.write_bytes(payload)
            total += len(payload)
        return total

    monkeypatch.setattr(model_bundle, "_copy_installed_rapidocr", fake_installed)
    outcome = assemble_bundle(source, target)
    locked = json.loads(outcome.manifest.read_text(encoding="utf-8"))
    declaration = locked["optional_artifacts"][0]
    assert declaration["path"] == "calibration/ensemble.json"
    assert declaration["sha256"] == hashlib.sha256(calibration.read_bytes()).hexdigest()
    assert (target / declaration["path"]).is_file()
    assert verify_locked_bundle(target) == []

    (target / declaration["path"]).write_text("{}", encoding="utf-8")
    assert any(
        "optional" in problem and "SHA-256" in problem for problem in verify_locked_bundle(target)
    )
