from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from kitapkatalog.config import AppPaths
from kitapkatalog.model_manager import ModelBundleError, ModelManager, sha256_file


def paths_at(root: Path) -> AppPaths:
    return AppPaths(
        root=root,
        database=root / "catalog.sqlite3",
        assets=root / "assets",
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=root / "models",
        exports=root / "exports",
        logs=root / "logs",
    )


def test_sha256_file(tmp_path: Path) -> None:
    target = tmp_path / "a.bin"
    target.write_bytes(b"abc")
    assert sha256_file(target) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


def test_missing_bundle_is_explicit(tmp_path: Path) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    manager = ModelManager(paths)
    report = manager.runtime_report()
    assert report["offline"] is True
    assert report["five_ocr_ready"] is False
    assert len(report["engines"]) == 5
    with pytest.raises(ModelBundleError, match="Beş OCR"):
        manager.require_all_ocr()


def test_manifest_hash_validation(tmp_path: Path) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    artifact = paths.models / "dummy.bin"
    artifact.write_bytes(b"abc")
    manifest = {
        "engines": [
            {
                "id": "dummy",
                "version": "1",
                "family": "dummy",
                "license": "MIT",
                "artifacts": [
                    {
                        "path": "dummy.bin",
                        "sha256": (
                            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                        ),
                    }
                ],
            }
        ],
        "extractor": {
            "id": "dummy-extractor",
            "version": "1",
            "license": "MIT",
            "artifacts": [],
        },
    }
    manifest_path = tmp_path / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    manager = ModelManager(paths, manifest_path=manifest_path)
    statuses = manager.engine_statuses()
    assert statuses[0].artifacts[0].valid is True


def test_unlocked_artifact_cannot_make_engine_ready(tmp_path: Path) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    (paths.models / "dummy.bin").write_bytes(b"abc")
    manifest = {
        "engines": [
            {
                "id": "dummy",
                "version": "1",
                "family": "dummy",
                "license": "MIT",
                "artifacts": [{"path": "dummy.bin", "sha256": None}],
            }
        ],
        "extractor": {
            "id": "dummy-extractor",
            "version": "1",
            "license": "MIT",
            "artifacts": [],
        },
    }
    manifest_path = tmp_path / "unlocked.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    status = ModelManager(paths, manifest_path=manifest_path).engine_statuses()[0]
    assert status.available is False
    assert any("sabitlenmemiş" in reason for reason in status.reasons)


def test_hash_locked_runtime_tampering_makes_engine_unavailable(tmp_path: Path) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    runtime = paths.models / "bin" / "tesseract"
    runtime.parent.mkdir()
    runtime.write_bytes(b"trusted")
    runtime.chmod(0o755)
    manifest = {
        "engines": [
            {
                "id": "tesseract",
                "version": "1",
                "family": "tesseract",
                "license": "MIT",
                "artifacts": [],
            }
        ],
        "extractor": {
            "id": "dummy-extractor",
            "version": "1",
            "license": "MIT",
            "artifacts": [],
        },
        "runtime_artifacts": [
            {
                "path": "bin/tesseract",
                "sha256": hashlib.sha256(b"trusted").hexdigest(),
            }
        ],
    }
    manifest_path = tmp_path / "locked.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    manager = ModelManager(paths, manifest_path=manifest_path)
    assert manager.engine_statuses()[0].available

    runtime.write_bytes(b"tampered")
    status = manager.engine_statuses()[0]
    assert not status.available
    assert any("SHA-256" in reason for reason in status.reasons)


def test_public_runtime_wrapper_wins_over_private_support_binary(
    tmp_path: Path,
) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    public = paths.models / "bin" / "tesseract"
    private = paths.models / "runtime" / "tesseract" / "bin" / "tesseract"
    public.parent.mkdir()
    private.parent.mkdir(parents=True)
    public.write_bytes(b"public")
    private.write_bytes(b"private")
    public.chmod(0o755)
    private.chmod(0o755)
    manifest = {
        "engines": [
            {
                "id": "tesseract",
                "version": "1",
                "family": "tesseract",
                "license": "MIT",
                "artifacts": [],
            }
        ],
        "extractor": {
            "id": "dummy-extractor",
            "version": "1",
            "license": "MIT",
            "artifacts": [],
        },
        "runtime_artifacts": [
            {
                "path": "bin/tesseract",
                "sha256": hashlib.sha256(b"public").hexdigest(),
            },
            {
                "path": "runtime/tesseract/bin/tesseract",
                "sha256": hashlib.sha256(b"private").hexdigest(),
            },
        ],
    }
    manifest_path = tmp_path / "locked-with-support-tree.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    manager = ModelManager(paths, manifest_path=manifest_path)
    assert manager.engine_statuses()[0].available

    public.write_bytes(b"tampered")
    status = manager.engine_statuses()[0]
    assert not status.available
    assert any("SHA-256" in reason for reason in status.reasons)


def test_calibration_requires_hash_lock_and_reports_trust(tmp_path: Path) -> None:
    paths = paths_at(tmp_path)
    paths.ensure()
    calibration = paths.models / "calibration" / "ensemble.json"
    calibration.parent.mkdir()
    payload = {
        "schema_version": 1,
        "version": "calibration-v1",
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
    calibration.write_text(json.dumps(payload), encoding="utf-8")
    manifest = {
        "engines": [],
        "extractor": {
            "id": "dummy-extractor",
            "version": "1",
            "license": "MIT",
            "artifacts": [],
        },
        "optional_artifacts": [
            {
                "path": "calibration/ensemble.json",
                "sha256": sha256_file(calibration),
            }
        ],
    }
    manifest_path = tmp_path / "locked.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    manager = ModelManager(paths, manifest_path=manifest_path)

    profile = manager.optional_calibration_profile()
    assert profile is not None and profile.trusted
    assert manager.calibration_report()["automatic_acceptance"] is True

    calibration.write_text("{}", encoding="utf-8")
    with pytest.raises(ModelBundleError, match="güvenilir değil"):
        manager.optional_calibration_profile()
