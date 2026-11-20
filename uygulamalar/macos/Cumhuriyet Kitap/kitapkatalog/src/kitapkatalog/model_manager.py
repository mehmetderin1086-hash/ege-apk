from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
from collections.abc import Iterable
from dataclasses import dataclass
from importlib.resources import files
from pathlib import Path
from typing import Any

from kitapkatalog.calibration import (
    CalibrationError,
    ConfidenceCalibrationProfile,
)
from kitapkatalog.config import AppPaths


class ModelBundleError(RuntimeError):
    """Raised when the mandatory offline runtime is incomplete."""


@dataclass(frozen=True, slots=True)
class ArtifactStatus:
    path: Path
    exists: bool
    expected_sha256: str | None
    actual_sha256: str | None
    valid: bool
    reason: str | None = None


@dataclass(frozen=True, slots=True)
class EngineStatus:
    engine_id: str
    version: str
    family: str
    license: str
    available: bool
    reasons: tuple[str, ...]
    artifacts: tuple[ArtifactStatus, ...]


def sha256_file(path: Path, *, chunk_size: int = 4 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest(override: Path | None = None) -> dict[str, Any]:
    if override is not None:
        return json.loads(override.read_text(encoding="utf-8"))
    resource = files("kitapkatalog").joinpath("resources/model_manifest.json")
    return json.loads(resource.read_text(encoding="utf-8"))


def _candidate_executable(name: str, model_root: Path) -> Path | None:
    env_name = f"KITAPKATALOG_{name.upper().replace('-', '_')}_BIN"
    override = os.environ.get(env_name)
    if override:
        path = Path(override).expanduser()
        return path if path.is_file() else None
    bundled = model_root / "bin" / name
    if bundled.is_file():
        return bundled
    located = shutil.which(name)
    return Path(located) if located else None


def _artifact_status(model_root: Path, artifact: dict[str, Any]) -> ArtifactStatus:
    path = model_root / artifact["path"]
    expected = artifact.get("sha256")
    if not path.is_file():
        return ArtifactStatus(path, False, expected, None, False, "dosya eksik")
    actual = sha256_file(path)
    if expected and actual != expected:
        return ArtifactStatus(path, True, expected, actual, False, "SHA-256 uyuşmuyor")
    if not expected:
        return ArtifactStatus(
            path,
            True,
            None,
            actual,
            False,
            "SHA-256 manifestte sabitlenmemiş",
        )
    return ArtifactStatus(path, True, expected, actual, True)


def _package_present(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


class ModelManager:
    """Validates the build-time assembled model bundle without using the network."""

    def __init__(
        self,
        paths: AppPaths | None = None,
        *,
        manifest_path: Path | None = None,
    ) -> None:
        self.paths = paths or AppPaths.default()
        locked_manifest = self.paths.models / "model_manifest.lock.json"
        selected_manifest = (
            manifest_path
            if manifest_path is not None
            else (locked_manifest if locked_manifest.is_file() else None)
        )
        self.manifest = load_manifest(selected_manifest)

    def offline_environment(self) -> dict[str, str]:
        easyocr_dir = self.paths.models / "easyocr"
        return {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "EASYOCR_MODULE_PATH": str(easyocr_dir),
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }

    def apply_offline_environment(self) -> None:
        for key, value in self.offline_environment().items():
            os.environ[key] = value

    def _engine_reasons(self, engine_id: str) -> list[str]:
        reasons: list[str] = []
        if engine_id == "rapidocr_ppocrv6":
            if not _package_present("rapidocr"):
                reasons.append("rapidocr Python paketi kurulu değil")
            if not _package_present("onnxruntime"):
                reasons.append("onnxruntime Python paketi kurulu değil")
        elif engine_id == "tesseract":
            if _candidate_executable("tesseract", self.paths.models) is None:
                reasons.append("tesseract çalıştırılabilir dosyası bulunamadı")
            reasons.extend(self._runtime_reasons("tesseract"))
        elif engine_id == "easyocr":
            if not _package_present("easyocr"):
                reasons.append("easyocr Python paketi kurulu değil")
        elif engine_id in {"paddleocr_vl", "surya"}:
            if _candidate_executable("llama-server", self.paths.models) is None:
                reasons.append("yerel llama-server vision runtime bulunamadı")
            reasons.extend(self._runtime_reasons("llama-server"))
        return reasons

    def _runtime_reasons(self, executable: str) -> list[str]:
        declarations = [
            artifact
            for artifact in self.manifest.get("runtime_artifacts", [])
            if Path(str(artifact.get("path", ""))).name in {executable, f"{executable}.exe"}
        ]
        if not declarations:
            return []
        # A relocatable bundle may legitimately contain both the public wrapper
        # in ``bin/`` and the runtime's private executable below ``runtime/``.
        # Readiness is anchored to the public entry point selected by
        # ``_candidate_executable``; support-tree files are still hash-checked
        # by ``verify_declared_hashes``.
        public_paths = {f"bin/{executable}", f"bin/{executable}.exe"}
        public_declarations = [
            artifact
            for artifact in declarations
            if str(artifact.get("path", "")).replace("\\", "/") in public_paths
        ]
        selected = public_declarations or declarations
        if len(selected) != 1:
            return [f"{executable} runtime kaydı manifestte tekil değil"]
        status = _artifact_status(self.paths.models, selected[0])
        return [] if status.valid else [f"{executable}: {status.reason}"]

    def engine_statuses(self) -> tuple[EngineStatus, ...]:
        statuses: list[EngineStatus] = []
        for spec in self.manifest["engines"]:
            artifacts = tuple(
                _artifact_status(self.paths.models, artifact)
                for artifact in spec.get("artifacts", [])
            )
            reasons = self._engine_reasons(spec["id"])
            reasons.extend(
                f"{status.path.name}: {status.reason}" for status in artifacts if not status.valid
            )
            statuses.append(
                EngineStatus(
                    engine_id=spec["id"],
                    version=spec["version"],
                    family=spec["family"],
                    license=spec["license"],
                    available=not reasons,
                    reasons=tuple(reasons),
                    artifacts=artifacts,
                )
            )
        return tuple(statuses)

    def extractor_status(self) -> EngineStatus:
        spec = self.manifest["extractor"]
        artifacts = tuple(
            _artifact_status(self.paths.models, artifact) for artifact in spec.get("artifacts", [])
        )
        reasons: list[str] = []
        if _candidate_executable("llama-server", self.paths.models) is None:
            reasons.append("yerel llama-server bulunamadı")
        reasons.extend(self._runtime_reasons("llama-server"))
        reasons.extend(
            f"{status.path.name}: {status.reason}" for status in artifacts if not status.valid
        )
        return EngineStatus(
            engine_id=spec["id"],
            version=spec["version"],
            family="field-extractor",
            license=spec["license"],
            available=not reasons,
            reasons=tuple(reasons),
            artifacts=artifacts,
        )

    def require_all_ocr(self) -> tuple[EngineStatus, ...]:
        statuses = self.engine_statuses()
        missing = [status for status in statuses if not status.available]
        if missing:
            details = "; ".join(
                f"{status.engine_id}: {', '.join(status.reasons)}" for status in missing
            )
            raise ModelBundleError(f"Beş OCR paketi tamamlanmamış: {details}")
        return statuses

    def verify_declared_hashes(self) -> list[str]:
        warnings: list[str] = []
        specs: Iterable[dict[str, Any]] = (
            *self.manifest["engines"],
            self.manifest["extractor"],
        )
        for spec in specs:
            for artifact in spec.get("artifacts", []):
                status = _artifact_status(self.paths.models, artifact)
                if status.exists and status.expected_sha256 is None:
                    warnings.append(f"{spec['id']}: {artifact['path']} için SHA-256 sabit değil")
                elif not status.valid:
                    warnings.append(f"{spec['id']}: {artifact['path']} — {status.reason}")
        for artifact in self.manifest.get("runtime_artifacts", []):
            status = _artifact_status(self.paths.models, artifact)
            if status.exists and status.expected_sha256 is None:
                warnings.append(f"runtime: {artifact['path']} için SHA-256 sabit değil")
            elif not status.valid:
                warnings.append(f"runtime: {artifact['path']} — {status.reason}")
        for artifact in self.manifest.get("optional_artifacts", []):
            status = _artifact_status(self.paths.models, artifact)
            if status.exists and status.expected_sha256 is None:
                warnings.append(f"optional: {artifact['path']} için SHA-256 sabit değil")
            elif not status.valid:
                warnings.append(f"optional: {artifact['path']} — {status.reason}")
        return warnings

    @property
    def local_calibration_path(self) -> Path:
        """Where a profile fitted from this catalogue's own reviews lives.

        Not inside the model bundle: that directory ships inside a signed app
        and is read-only, and a locally fitted profile has nothing to check
        against the bundle's hash lock anyway.
        """

        return self.paths.root / "calibration" / "ensemble.json"

    def optional_calibration_profile(
        self,
    ) -> ConfidenceCalibrationProfile | None:
        relative = "calibration/ensemble.json"
        path = self.paths.models / relative
        declared = any(
            str(artifact.get("path", "")).replace("\\", "/") == relative
            for artifact in self.manifest.get("optional_artifacts", [])
        )
        if declared or path.exists():
            return self.load_calibration_profile()
        return self.local_calibration_profile()

    def local_calibration_profile(self) -> ConfidenceCalibrationProfile | None:
        """Load the profile fitted from this catalogue's reviews, if any.

        The shipped bundle takes precedence when it declares one; this is the
        fallback that lets a user's own review work switch automatic acceptance
        on without waiting for a vendored profile.
        """

        path = self.local_calibration_path
        if not path.is_file():
            return None
        try:
            return ConfidenceCalibrationProfile.load(path)
        except CalibrationError as exc:
            raise ModelBundleError(f"Yerel kalibrasyon profili bozuk: {exc}") from exc

    def load_calibration_profile(self) -> ConfidenceCalibrationProfile:
        """Load an optional calibration profile only when it is hash-locked."""

        relative = "calibration/ensemble.json"
        path = self.paths.models / relative
        declarations = [
            artifact
            for artifact in self.manifest.get("optional_artifacts", [])
            if str(artifact.get("path", "")).replace("\\", "/") == relative
        ]
        if not path.is_file():
            raise ModelBundleError(f"Kalibrasyon profili bulunamadı: {path}")
        if len(declarations) != 1:
            raise ModelBundleError(
                "Kalibrasyon profili kilit manifestinde tekil olarak tanımlı değil"
            )
        status = _artifact_status(self.paths.models, declarations[0])
        if not status.valid:
            raise ModelBundleError(f"Kalibrasyon profili güvenilir değil: {status.reason}")
        try:
            return ConfidenceCalibrationProfile.load(path)
        except CalibrationError as exc:
            raise ModelBundleError(f"Kalibrasyon profili bozuk: {exc}") from exc

    def calibration_report(self) -> dict[str, Any]:
        path = self.paths.models / "calibration" / "ensemble.json"
        if not path.is_file():
            declared = any(
                str(artifact.get("path", "")).replace("\\", "/") == "calibration/ensemble.json"
                for artifact in self.manifest.get("optional_artifacts", [])
            )
            return {
                "present": False,
                "trusted": False,
                "automatic_acceptance": False,
                "reasons": [
                    (
                        "manifestte tanımlı kalibrasyon profili eksik"
                        if declared
                        else "kalibrasyon profili yok; sonuçlar incelemeye gider"
                    )
                ],
            }
        try:
            profile = self.load_calibration_profile()
        except ModelBundleError as exc:
            return {
                "present": True,
                "trusted": False,
                "automatic_acceptance": False,
                "reasons": [str(exc)],
            }
        reasons = (
            []
            if profile.trusted
            else [f"örnek sayısı yetersiz: {profile.total_samples} < {profile.minimum_samples}"]
        )
        return {
            "present": True,
            "trusted": profile.trusted,
            "automatic_acceptance": profile.trusted,
            "version": profile.version,
            "total_samples": profile.total_samples,
            "minimum_samples": profile.minimum_samples,
            "digest": profile.digest(),
            "reasons": reasons,
        }

    def runtime_report(self) -> dict[str, Any]:
        engines = self.engine_statuses()
        extractor = self.extractor_status()
        return {
            "offline": True,
            "model_root": str(self.paths.models),
            "five_ocr_ready": all(item.available for item in engines),
            "engines": [
                {
                    "id": item.engine_id,
                    "version": item.version,
                    "available": item.available,
                    "reasons": list(item.reasons),
                }
                for item in engines
            ],
            "extractor": {
                "id": extractor.engine_id,
                "version": extractor.version,
                "available": extractor.available,
                "reasons": list(extractor.reasons),
            },
            "calibration": self.calibration_report(),
            "hash_warnings": self.verify_declared_hashes(),
        }
