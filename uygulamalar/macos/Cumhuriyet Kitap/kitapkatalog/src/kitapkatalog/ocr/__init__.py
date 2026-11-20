"""OCR engine adapters and fail-closed five-engine orchestration."""

from kitapkatalog.ocr.contracts import (
    CLASSIC_ENGINE_IDS,
    REQUIRED_ENGINE_IDS,
    EngineAvailability,
    EngineOcrResult,
    EngineUnavailableError,
    OcrEngineAdapter,
    OcrError,
    OcrExecutionError,
    OcrToken,
)
from kitapkatalog.ocr.easyocr import EasyOcrAdapter
from kitapkatalog.ocr.manifest import ModelManifest, ModelManifestError
from kitapkatalog.ocr.rapidocr import RapidOcrAdapter
from kitapkatalog.ocr.registry import (
    EngineRegistryError,
    FiveEngineRegistry,
    build_offline_registry,
)
from kitapkatalog.ocr.sidecar import PaddleOcrVlAdapter, SuryaOcrAdapter
from kitapkatalog.ocr.tesseract import TesseractAdapter

__all__ = [
    "CLASSIC_ENGINE_IDS",
    "REQUIRED_ENGINE_IDS",
    "EasyOcrAdapter",
    "EngineAvailability",
    "EngineOcrResult",
    "EngineRegistryError",
    "EngineUnavailableError",
    "FiveEngineRegistry",
    "ModelManifest",
    "ModelManifestError",
    "OcrEngineAdapter",
    "OcrError",
    "OcrExecutionError",
    "OcrToken",
    "PaddleOcrVlAdapter",
    "RapidOcrAdapter",
    "SuryaOcrAdapter",
    "TesseractAdapter",
    "build_offline_registry",
]
