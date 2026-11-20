"""Offline model manifest loading, integrity checks, and engine configuration."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from kitapkatalog.ocr.contracts import REQUIRED_ENGINE_IDS

_REQUIRED_ARTIFACT_SUFFIXES: dict[str, tuple[str, ...]] = {
    "rapidocr_ppocrv6": (
        "PP-OCRv6_det_small.onnx",
        "PP-OCRv6_rec_small.onnx",
        "PP-OCRv6_det_medium.onnx",
        "PP-OCRv6_rec_medium.onnx",
        "ch_ppocr_mobile_v2.0_cls_mobile.onnx",
    ),
    "tesseract": ("tur.traineddata", "eng.traineddata"),
    "easyocr": ("craft_mlt_25k.pth", "latin_g2.pth"),
    "paddleocr_vl": ("model.gguf", "mmproj.gguf"),
    "surya": ("model.gguf", "mmproj.gguf"),
    "qwen3_field_extractor": ("Qwen3-4B-Q4_K_M.gguf",),
}


class ModelManifestError(RuntimeError):
    """The offline model bundle is absent, incomplete, or corrupt."""


@dataclass(frozen=True, slots=True)
class ArtifactSpec:
    path: str
    sha256: str | None


@dataclass(frozen=True, slots=True)
class EngineSpec:
    engine_id: str
    required: bool
    family: str
    version: str
    license: str
    artifacts: tuple[ArtifactSpec, ...]


@dataclass(frozen=True, slots=True)
class ManifestValidation:
    valid: bool
    errors: tuple[str, ...]
    warnings: tuple[str, ...]
    artifact_digests: dict[str, str]

    def require(self) -> None:
        if not self.valid:
            raise ModelManifestError("; ".join(self.errors))


@dataclass(frozen=True, slots=True)
class ModelManifest:
    schema_version: int
    runtime_offline: bool
    engines: tuple[EngineSpec, ...]
    extractor: EngineSpec | None
    runtime_artifacts: tuple[ArtifactSpec, ...] = ()

    @classmethod
    def load(cls, path: str | Path) -> ModelManifest:
        manifest_path = Path(path)
        try:
            payload = json.loads(manifest_path.read_text(encoding="utf-8"))
        except FileNotFoundError as exc:
            raise ModelManifestError(f"Model manifesti bulunamadı: {manifest_path}") from exc
        except (OSError, json.JSONDecodeError) as exc:
            raise ModelManifestError(f"Model manifesti okunamadı: {manifest_path}: {exc}") from exc
        try:
            engines = tuple(_engine_spec(item) for item in payload["engines"])
            extractor_payload = payload.get("extractor")
            extractor = _engine_spec(extractor_payload) if extractor_payload else None
            runtime_artifacts = tuple(
                ArtifactSpec(
                    path=str(item["path"]),
                    sha256=_optional_hash(item.get("sha256")),
                )
                for item in payload.get("runtime_artifacts", ())
            )
            return cls(
                schema_version=int(payload["schema_version"]),
                runtime_offline=bool(payload["runtime_offline"]),
                engines=engines,
                extractor=extractor,
                runtime_artifacts=runtime_artifacts,
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ModelManifestError(f"Model manifest şeması bozuk: {exc}") from exc

    def engine(self, engine_id: str) -> EngineSpec:
        matches = [engine for engine in self.engines if engine.engine_id == engine_id]
        if len(matches) != 1:
            raise ModelManifestError(
                f"Manifestte {engine_id!r} için tam bir motor kaydı bekleniyordu"
            )
        return matches[0]

    def validate(
        self,
        model_root: str | Path,
        *,
        strict_hashes: bool = True,
        include_extractor: bool = False,
    ) -> ManifestValidation:
        root = Path(model_root)
        errors: list[str] = []
        warnings: list[str] = []
        digests: dict[str, str] = {}
        if self.schema_version != 1:
            errors.append(f"Desteklenmeyen model manifest sürümü: {self.schema_version}")
        if not self.runtime_offline:
            errors.append("Manifest runtime_offline=true olmalıdır")

        ids = [engine.engine_id for engine in self.engines]
        duplicates = sorted({engine_id for engine_id in ids if ids.count(engine_id) > 1})
        if duplicates:
            errors.append(f"Yinelenen motor kimlikleri: {', '.join(duplicates)}")
        missing = sorted(set(REQUIRED_ENGINE_IDS) - set(ids))
        extra_required = sorted(
            engine.engine_id
            for engine in self.engines
            if engine.required and engine.engine_id not in REQUIRED_ENGINE_IDS
        )
        if missing:
            errors.append(f"Zorunlu beş OCR motoru eksik: {', '.join(missing)}")
        if extra_required:
            errors.append(f"Bilinmeyen zorunlu OCR motorları: {', '.join(extra_required)}")
        for required_id in REQUIRED_ENGINE_IDS:
            matches = [engine for engine in self.engines if engine.engine_id == required_id]
            if matches and not matches[0].required:
                errors.append(f"{required_id} manifestte required=true olmalıdır")

        specs = list(self.engines)
        if include_extractor:
            if self.extractor is None:
                errors.append("Alan çıkarıcı model manifestte eksik")
            else:
                specs.append(self.extractor)
        for spec in specs:
            paths = [artifact.path.replace("\\", "/") for artifact in spec.artifacts]
            if len(paths) != len(set(paths)):
                errors.append(f"{spec.engine_id} yinelenen model dosyası içeriyor")
            for suffix in _REQUIRED_ARTIFACT_SUFFIXES.get(spec.engine_id, ()):
                if sum(path.endswith(suffix) for path in paths) != 1:
                    errors.append(
                        f"{spec.engine_id} için {suffix!r} ile biten tek artifact gerekli"
                    )
        resolved_root = root.resolve()
        for spec in specs:
            for artifact in spec.artifacts:
                relative = Path(artifact.path)
                if relative.is_absolute() or ".." in relative.parts:
                    errors.append(f"Güvensiz model yolu: {artifact.path}")
                    continue
                path = root / relative
                resolved_path = path.resolve()
                if not resolved_path.is_relative_to(resolved_root):
                    errors.append(f"Model yolu kök klasörün dışına çıkıyor: {artifact.path}")
                    continue
                if not path.is_file():
                    errors.append(f"Model dosyası eksik: {path}")
                    continue
                digest = _sha256(path)
                digests[artifact.path] = digest
                if artifact.sha256 is None:
                    message = f"Model SHA-256 değeri manifestte yok: {artifact.path}"
                    (errors if strict_hashes else warnings).append(message)
                elif artifact.sha256.lower() != digest:
                    errors.append(
                        f"Model bütünlük hatası: {artifact.path} "
                        f"(beklenen {artifact.sha256}, bulunan {digest})"
                    )
        for artifact in self.runtime_artifacts:
            relative = Path(artifact.path)
            if relative.is_absolute() or ".." in relative.parts:
                errors.append(f"Güvensiz runtime yolu: {artifact.path}")
                continue
            path = root / relative
            resolved_path = path.resolve()
            if not resolved_path.is_relative_to(resolved_root):
                errors.append(f"Runtime yolu kök klasörün dışına çıkıyor: {artifact.path}")
                continue
            if not path.is_file():
                errors.append(f"Runtime dosyası eksik: {path}")
                continue
            digest = _sha256(path)
            digests[artifact.path] = digest
            if artifact.sha256 is None:
                message = f"Runtime SHA-256 değeri manifestte yok: {artifact.path}"
                (errors if strict_hashes else warnings).append(message)
            elif artifact.sha256.lower() != digest:
                errors.append(
                    f"Runtime bütünlük hatası: {artifact.path} "
                    f"(beklenen {artifact.sha256}, bulunan {digest})"
                )
        return ManifestValidation(not errors, tuple(errors), tuple(warnings), digests)


def _engine_spec(payload: dict[str, Any]) -> EngineSpec:
    artifacts = tuple(
        ArtifactSpec(path=str(item["path"]), sha256=_optional_hash(item.get("sha256")))
        for item in payload.get("artifacts", ())
    )
    return EngineSpec(
        engine_id=str(payload.get("id", "")),
        required=bool(payload.get("required", False)),
        family=str(payload.get("family", "")),
        version=str(payload["version"]),
        license=str(payload["license"]),
        artifacts=artifacts,
    )


def _optional_hash(value: Any) -> str | None:
    if value is None:
        return None
    digest = str(value).lower()
    if len(digest) != 64 or any(character not in "0123456789abcdef" for character in digest):
        raise ValueError(f"Geçersiz SHA-256: {value!r}")
    return digest


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()
