"""EasyOCR 1.7.2 / CRAFT adapter."""

from __future__ import annotations

import importlib.metadata
import importlib.util
import sys
import time
from pathlib import Path
from typing import Any

from kitapkatalog.images import PreparedImage
from kitapkatalog.ocr.contracts import (
    EngineAvailability,
    EngineOcrResult,
    EngineUnavailableError,
    OcrEngineAdapter,
    OcrExecutionError,
    OcrToken,
)
from kitapkatalog.ocr.variants import CLASSIC_VARIANT_LADDER, run_ladder


class EasyOcrAdapter(OcrEngineAdapter):
    engine_id = "easyocr"
    evidence_kind = "classic"

    def __init__(
        self,
        *,
        model_storage_directory: Path | None = None,
        gpu: bool | str = False,
        model_version: str = "1.7.2+latin_g2",
        artifact_digest: str | None = None,
        reader: Any | None = None,
        escalation_threshold: float = 0.80,
    ) -> None:
        if not 0.0 <= float(escalation_threshold) <= 1.0:
            raise ValueError("escalation_threshold 0 ile 1 arasında olmalıdır")
        self.model_storage_directory = (
            Path(model_storage_directory) if model_storage_directory else None
        )
        self.gpu = gpu
        self.model_version = model_version
        self.artifact_digest = artifact_digest
        self._reader = reader
        self.escalation_threshold = float(escalation_threshold)

    def availability(self) -> EngineAvailability:
        problems: list[str] = []
        if self._reader is None and importlib.util.find_spec("easyocr") is None:
            problems.append(
                "EasyOCR/torch eksik; `pip install 'kitapkatalog[easyocr]'` komutunu çalıştırın"
            )
        elif self._reader is None:
            try:
                version = importlib.metadata.version("easyocr")
                if version != "1.7.2":
                    problems.append(f"EasyOCR 1.7.2 gerekli; kurulu sürüm: {version}")
            except importlib.metadata.PackageNotFoundError:
                problems.append("EasyOCR paket sürümü doğrulanamadı")
            if importlib.util.find_spec("torch") is None:
                problems.append(
                    "PyTorch eksik; `pip install 'kitapkatalog[easyocr]'` komutunu çalıştırın"
                )
        if self.model_storage_directory is not None and not self.model_storage_directory.is_dir():
            problems.append(
                f"EasyOCR çevrimdışı model klasörü bulunamadı: {self.model_storage_directory}"
            )
        return EngineAvailability(self.engine_id, not problems, self.model_version, tuple(problems))

    def _load(self) -> Any:
        if self._reader is not None:
            return self._reader
        self.require_available()
        try:
            import easyocr
        except ImportError as exc:
            raise EngineUnavailableError(
                "EasyOCR yüklenemedi; `pip install 'kitapkatalog[easyocr]'` komutunu çalıştırın"
            ) from exc
        kwargs: dict[str, Any] = {
            "gpu": self.gpu,
            "download_enabled": False,
        }
        if self.model_storage_directory:
            kwargs["model_storage_directory"] = str(self.model_storage_directory)
            kwargs["user_network_directory"] = str(self.model_storage_directory)
        try:
            self._reader = easyocr.Reader(["tr", "en"], **kwargs)
        except Exception as exc:
            raise EngineUnavailableError(
                "EasyOCR çevrimdışı başlatılamadı. latin_g2/CRAFT model dosyalarını "
                f"model klasörüne yerleştirin: {exc}"
            ) from exc
        return self._reader

    def _recognize_at(self, reader: Any, image_path: Path) -> list[OcrToken]:
        try:
            rows = reader.readtext(str(image_path), detail=1, paragraph=False)
        except Exception as exc:
            raise OcrExecutionError(f"EasyOCR görüntüyü işleyemedi: {exc}") from exc
        tokens: list[OcrToken] = []
        for index, row in enumerate(rows):
            try:
                box, text, confidence = row[:3]
                polygon = tuple((float(point[0]), float(point[1])) for point in box)
            except (TypeError, ValueError, IndexError) as exc:
                raise OcrExecutionError("EasyOCR beklenmeyen satır çıktısı üretti") from exc
            if not str(text).strip():
                continue
            tokens.append(
                OcrToken(
                    token_id=f"{self.engine_id}:{index}",
                    text=str(text),
                    confidence=max(0.0, min(1.0, float(confidence))),
                    polygon=polygon,
                    line_id=f"line:{index}",
                )
            )
        return tokens

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        reader = self._load()
        started = time.perf_counter()
        variant, tokens, attempts = run_ladder(
            lambda path: self._recognize_at(reader, path),
            image,
            threshold=self.escalation_threshold,
            ladder=CLASSIC_VARIANT_LADDER,
        )
        duration = round((time.perf_counter() - started) * 1000)
        return EngineOcrResult(
            engine_id=self.engine_id,
            model_version=self.model_version,
            image_sha256=image.image_sha256,
            variant=variant,
            tokens=tuple(tokens),
            raw_text="\n".join(token.text for token in tokens),
            duration_ms=duration,
            evidence_kind=self.evidence_kind,
            metadata={"variant_attempts": attempts},
        )

    def release(self) -> None:
        self._reader = None
        torch = sys.modules.get("torch")
        if torch is None:
            return
        try:
            if hasattr(torch, "mps") and torch.backends.mps.is_available():
                torch.mps.empty_cache()
            if hasattr(torch, "cuda") and torch.cuda.is_available():
                torch.cuda.empty_cache()
        except (AttributeError, RuntimeError):
            # Releasing the Python model reference is the invariant.  Device
            # cache APIs differ between torch builds and are best effort.
            pass

    def runtime_settings(self) -> dict[str, Any]:
        return {
            "languages": ["tr", "en"],
            "gpu": str(self.gpu),
            "detail": 1,
            "paragraph": False,
            "download_enabled": False,
            "variant_ladder": list(CLASSIC_VARIANT_LADDER),
            "variant_escalation_threshold": self.escalation_threshold,
        }
