"""RapidOCR / PP-OCRv6 small+medium adapter.

The small detector/recognizer always sees the complete canonical cover. A
second, locally bundled medium detector/recognizer is loaded only when the
small pass contains no text or at least one low-confidence token. Both passes
are collapsed into one :class:`EngineOcrResult`, so RapidOCR still contributes
exactly one vote to the five-engine ensemble.
"""

from __future__ import annotations

import importlib.metadata
import importlib.util
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


class RapidOcrAdapter(OcrEngineAdapter):
    engine_id = "rapidocr_ppocrv6"
    evidence_kind = "classic"

    def __init__(
        self,
        *,
        model_version: str = "PP-OCRv6-small+medium",
        model_paths: dict[str, Path] | None = None,
        medium_model_paths: dict[str, Path] | None = None,
        artifact_digest: str | None = None,
        engine: Any | None = None,
        medium_engine: Any | None = None,
        escalation_threshold: float = 0.80,
        text_score: float = 0.50,
        box_threshold: float = 0.50,
    ) -> None:
        for label, value in (
            ("escalation_threshold", escalation_threshold),
            ("text_score", text_score),
            ("box_threshold", box_threshold),
        ):
            if not 0.0 <= float(value) <= 1.0:
                raise ValueError(f"{label} 0 ile 1 arasında olmalıdır")
        self.model_version = model_version
        self.model_paths = {key: Path(value) for key, value in (model_paths or {}).items()}
        self.medium_model_paths = {
            key: Path(value) for key, value in (medium_model_paths or {}).items()
        }
        self.artifact_digest = artifact_digest
        self.escalation_threshold = float(escalation_threshold)
        self.text_score = float(text_score)
        self.box_threshold = float(box_threshold)
        self._small_engine = engine
        self._medium_engine = medium_engine

    def availability(self) -> EngineAvailability:
        problems: list[str] = []
        injected_both = self._small_engine is not None and self._medium_engine is not None
        if not injected_both and importlib.util.find_spec("rapidocr") is None:
            problems.append(
                "rapidocr/onnxruntime eksik; `pip install 'kitapkatalog[rapidocr]'` "
                "komutunu çalıştırın"
            )
        elif not injected_both:
            try:
                version = importlib.metadata.version("rapidocr")
                major_minor = tuple(int(part) for part in version.split(".")[:2])
                if major_minor < (3, 9):
                    problems.append(
                        f"RapidOCR {version} kurulu; PP-OCRv6 için rapidocr>=3.9 gerekli"
                    )
            except (importlib.metadata.PackageNotFoundError, ValueError):
                problems.append("RapidOCR paket sürümü doğrulanamadı")
            if importlib.util.find_spec("onnxruntime") is None:
                problems.append(
                    "ONNX Runtime eksik; `pip install 'kitapkatalog[rapidocr]'` komutunu çalıştırın"
                )
        for label, path in self.model_paths.items():
            if not path.is_file():
                problems.append(f"small/{label} model dosyası bulunamadı: {path}")
        for label, path in self.medium_model_paths.items():
            if not path.is_file():
                problems.append(f"medium/{label} model dosyası bulunamadı: {path}")
        if self._small_engine is None:
            for label in ("det", "rec", "cls"):
                if label not in self.model_paths:
                    problems.append(f"PP-OCRv6 small/{label} model yolu yapılandırılmadı")
        if self._medium_engine is None:
            for label in ("det", "rec"):
                if label not in self.medium_model_paths:
                    problems.append(f"PP-OCRv6 medium/{label} model yolu yapılandırılmadı")
        return EngineAvailability(self.engine_id, not problems, self.model_version, tuple(problems))

    @staticmethod
    def _parameters(model_paths: dict[str, Path]) -> dict[str, Any]:
        parameter_names = {
            "det": "Det.model_path",
            "rec": "Rec.model_path",
            "cls": "Cls.model_path",
        }
        return {parameter_names.get(key, key): str(value) for key, value in model_paths.items()}

    def _new_engine(self, model_paths: dict[str, Path]) -> Any:
        self.require_available()
        try:
            from rapidocr import RapidOCR
        except ImportError as exc:  # defensive: environment may change after availability()
            raise EngineUnavailableError(
                "RapidOCR yüklenemedi; `pip install 'kitapkatalog[rapidocr]'` komutunu çalıştırın"
            ) from exc
        try:
            return RapidOCR(params=self._parameters(model_paths))
        except Exception as exc:
            raise EngineUnavailableError(f"RapidOCR başlatılamadı: {exc}") from exc

    def _load_small(self) -> Any:
        if self._small_engine is None:
            self._small_engine = self._new_engine(self.model_paths)
        return self._small_engine

    def _load_medium(self) -> Any:
        if self._medium_engine is None:
            parameters = dict(self.medium_model_paths)
            parameters["cls"] = self.model_paths["cls"]
            self._medium_engine = self._new_engine(parameters)
        return self._medium_engine

    @staticmethod
    def _unpack(output: Any) -> tuple[list[Any], list[str], list[float]]:
        if all(hasattr(output, name) for name in ("boxes", "txts", "scores")):
            boxes = output.boxes
            texts = output.txts
            scores = output.scores
            if boxes is None or texts is None or scores is None:
                return [], [], []
            return list(boxes), [str(text) for text in texts], [float(score) for score in scores]
        # RapidOCR 1.x/2.x returns (result, elapsed), where result contains
        # [polygon, text, score] rows.
        rows = output[0] if isinstance(output, tuple) and len(output) == 2 else output
        if rows is None:
            return [], [], []
        try:
            return (
                [row[0] for row in rows],
                [str(row[1]) for row in rows],
                [float(row[2]) for row in rows],
            )
        except (IndexError, TypeError, ValueError) as exc:
            raise OcrExecutionError(
                "RapidOCR beklenmeyen çıktı üretti; rapidocr 3.x sürümünü doğrulayın"
            ) from exc

    def _run_pass(self, engine: Any, image_path: Path, *, pass_name: str) -> list[OcrToken]:
        try:
            output = engine(
                str(image_path),
                text_score=self.text_score,
                box_thresh=self.box_threshold,
            )
            boxes, texts, scores = self._unpack(output)
        except OcrExecutionError:
            raise
        except Exception as exc:
            raise OcrExecutionError(
                f"RapidOCR {pass_name} geçişi görüntüyü işleyemedi: {exc}"
            ) from exc
        if not (len(boxes) == len(texts) == len(scores)):
            raise OcrExecutionError(
                f"RapidOCR {pass_name} kutu/metin/güven dizileri farklı uzunluklarda döndü"
            )
        tokens: list[OcrToken] = []
        for index, (box, text, score) in enumerate(zip(boxes, texts, scores, strict=True)):
            if not text.strip():
                continue
            polygon = tuple((float(point[0]), float(point[1])) for point in box)
            tokens.append(
                OcrToken(
                    token_id=f"{pass_name}:{index}",
                    text=text,
                    confidence=max(0.0, min(1.0, score)),
                    polygon=polygon,
                    line_id=f"line:{index}",
                )
            )
        return tokens

    @staticmethod
    def _bounds(token: OcrToken) -> tuple[float, float, float, float] | None:
        if token.polygon is None:
            return None
        xs = [point[0] for point in token.polygon]
        ys = [point[1] for point in token.polygon]
        return min(xs), min(ys), max(xs), max(ys)

    @classmethod
    def _overlap(cls, left: OcrToken, right: OcrToken) -> float:
        left_box = cls._bounds(left)
        right_box = cls._bounds(right)
        if left_box is None or right_box is None:
            return 0.0
        intersection_width = max(
            0.0, min(left_box[2], right_box[2]) - max(left_box[0], right_box[0])
        )
        intersection_height = max(
            0.0, min(left_box[3], right_box[3]) - max(left_box[1], right_box[1])
        )
        intersection = intersection_width * intersection_height
        if intersection <= 0:
            return 0.0
        left_area = max(0.0, left_box[2] - left_box[0]) * max(0.0, left_box[3] - left_box[1])
        right_area = max(0.0, right_box[2] - right_box[0]) * max(0.0, right_box[3] - right_box[1])
        union = left_area + right_area - intersection
        return intersection / union if union else 0.0

    def _collapse_passes(
        self,
        small_tokens: list[OcrToken],
        medium_tokens: list[OcrToken],
    ) -> tuple[OcrToken, ...]:
        """Collapse two model sizes into one positioned RapidOCR observation."""

        selected: list[OcrToken] = []
        consumed_medium: set[int] = set()
        for small in small_tokens:
            candidates = [
                (self._overlap(small, medium), index, medium)
                for index, medium in enumerate(medium_tokens)
                if index not in consumed_medium
            ]
            overlap, match_index, medium = max(
                candidates,
                key=lambda item: item[0],
                default=(0.0, -1, small),
            )
            if overlap >= 0.20:
                consumed_medium.add(match_index)
            use_medium = (
                overlap >= 0.20
                and small.confidence < self.escalation_threshold
                and medium.confidence >= small.confidence
            )
            selected.append(medium if use_medium else small)
        selected.extend(
            token for index, token in enumerate(medium_tokens) if index not in consumed_medium
        )

        def reading_order(token: OcrToken) -> tuple[float, float]:
            bounds = self._bounds(token)
            return (bounds[1], bounds[0]) if bounds else (float("inf"), float("inf"))

        normalized: list[OcrToken] = []
        for index, token in enumerate(sorted(selected, key=reading_order)):
            normalized.append(
                OcrToken(
                    token_id=f"{self.engine_id}:{index}",
                    text=token.text,
                    confidence=token.confidence,
                    polygon=token.polygon,
                    line_id=f"line:{index}",
                    paragraph_id=token.paragraph_id,
                    language=token.language,
                )
            )
        return tuple(normalized)

    def _recognize_at(
        self, image_path: Path, *, pass_metadata: dict[str, dict[str, Any]]
    ) -> list[OcrToken]:
        """Run the small→medium escalation on one prepared derivative.

        The variant ladder in :mod:`kitapkatalog.ocr.variants` wraps this;
        every rung it tries still goes through the existing small/medium
        policy and still contributes exactly one vote.
        """

        small_tokens = self._run_pass(self._load_small(), image_path, pass_name="small")
        escalated = not small_tokens or any(
            token.confidence < self.escalation_threshold for token in small_tokens
        )
        medium_tokens = (
            self._run_pass(self._load_medium(), image_path, pass_name="medium")
            if escalated
            else []
        )
        tokens = list(self._collapse_passes(small_tokens, medium_tokens))
        pass_metadata[str(image_path)] = {
            "small_full_cover": True,
            "medium_escalated": escalated,
            "small_token_count": len(small_tokens),
            "medium_token_count": len(medium_tokens),
        }
        return tokens

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        started = time.perf_counter()
        pass_metadata: dict[str, dict[str, Any]] = {}
        variant, tokens, attempts = run_ladder(
            lambda path: self._recognize_at(path, pass_metadata=pass_metadata),
            image,
            threshold=self.escalation_threshold,
            ladder=CLASSIC_VARIANT_LADDER,
        )
        duration = round((time.perf_counter() - started) * 1000)
        metadata = dict(pass_metadata[str(image.variant_paths[variant])])
        metadata["escalation_threshold"] = self.escalation_threshold
        metadata["variant_attempts"] = attempts
        return EngineOcrResult(
            engine_id=self.engine_id,
            model_version=self.model_version,
            image_sha256=image.image_sha256,
            variant=variant,
            tokens=tuple(tokens),
            raw_text="\n".join(token.text for token in tokens),
            duration_ms=duration,
            evidence_kind=self.evidence_kind,
            metadata=metadata,
        )

    def release(self) -> None:
        self._small_engine = None
        self._medium_engine = None

    def runtime_settings(self) -> dict[str, Any]:
        return {
            "policy": "small-full-cover_medium-on-any-low-confidence_v1",
            "escalation_threshold": self.escalation_threshold,
            "text_score": self.text_score,
            "box_threshold": self.box_threshold,
            "variant_ladder": list(CLASSIC_VARIANT_LADDER),
            "variant_escalation_threshold": self.escalation_threshold,
        }
