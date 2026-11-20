"""Fail-closed five-OCR cover pipeline with durable per-engine checkpoints."""

from __future__ import annotations

import hashlib
import json
import os
import tempfile
import threading
from collections.abc import Callable, Iterator, Sequence
from contextlib import AbstractContextManager, contextmanager, nullcontext, suppress
from dataclasses import asdict, dataclass, replace
from pathlib import Path
from typing import Any, Protocol

from kitapkatalog.calibration import ConfidenceCalibrationProfile
from kitapkatalog.consensus import ConsensusDocument, reconcile_results
from kitapkatalog.domain import BOOK_SURFACE_ORDER, CoverRole
from kitapkatalog.images import CoverPreprocessor, PreparedImage, project_polygon_to_source
from kitapkatalog.isbn import (
    BarcodeObservation,
    IsbnCandidate,
    extract_isbn_candidates,
    merge_isbn_evidence,
)
from kitapkatalog.ocr.contracts import (
    CLASSIC_ENGINE_IDS,
    EngineOcrResult,
    InvalidEngineResultError,
    OcrEngineAdapter,
)
from kitapkatalog.ocr.registry import FiveEngineRegistry
from kitapkatalog.ocr.variants import ALLOWED_CLASSIC_VARIANTS, ALLOWED_VISION_VARIANTS


class PipelineError(RuntimeError):
    """The cover could not reach a safe five-OCR-complete state."""


class ResultStoreError(PipelineError):
    """A cached engine checkpoint is corrupt or cannot be persisted."""


class BarcodeScanner(Protocol):
    def availability(self) -> tuple[bool, tuple[str, ...]]: ...

    def scan(
        self,
        image_path: str | Path,
        *,
        variant: str = "canonical",
    ) -> tuple[BarcodeObservation, ...]: ...


class EngineResultStore(Protocol):
    def load(self, cache_key: str) -> EngineOcrResult | None: ...

    def save(self, cache_key: str, result: EngineOcrResult) -> None: ...


@dataclass(frozen=True, slots=True)
class PipelineConfig:
    max_retries: int = 2
    require_barcode_scanner: bool = False
    auto_confidence: float = 0.98
    review_confidence: float = 0.80
    config_version: str = "five-ocr-v1"
    calibration_digest: str = "uncalibrated"

    def __post_init__(self) -> None:
        if self.max_retries < 0:
            raise ValueError("max_retries negatif olamaz")
        if not 0.0 <= self.review_confidence < self.auto_confidence <= 1.0:
            raise ValueError(
                "Güven eşikleri 0 <= review_confidence < auto_confidence <= 1 olmalıdır"
            )

    def digest(self) -> str:
        payload = json.dumps(asdict(self), sort_keys=True, separators=(",", ":")).encode()
        return hashlib.sha256(payload).hexdigest()


@dataclass(frozen=True, slots=True)
class PipelineEvent:
    stage: str
    cover_role: str = "unknown"
    image_sha256: str | None = None
    engine_id: str | None = None
    attempt: int | None = None
    from_cache: bool = False
    message: str | None = None


@dataclass(frozen=True, slots=True)
class EngineCheckpoint:
    """Complete payload for one atomic durable DB checkpoint."""

    prepared: PreparedImage
    result: EngineOcrResult
    cache_key: str
    model_digest: str
    config_hash: str
    from_cache: bool
    raw_result_path: Path | None
    cover_role: str


@dataclass(frozen=True, slots=True)
class CoverPipelineResult:
    cover_role: str
    prepared: PreparedImage
    engine_results: tuple[EngineOcrResult, ...]
    consensus: ConsensusDocument
    barcodes: tuple[BarcodeObservation, ...]
    isbn_candidates: tuple[IsbnCandidate, ...]
    isbns: tuple[str, ...]
    isbn_conflict: bool
    cache_hits: int
    stage: str
    warnings: tuple[str, ...]

    @property
    def five_ocr_complete(self) -> bool:
        return self.consensus.five_ocr_complete and len(self.engine_results) == 5


@dataclass(frozen=True, slots=True)
class PairPipelineResult:
    front: CoverPipelineResult
    back: CoverPipelineResult
    isbns: tuple[str, ...]
    isbn_conflict: bool
    stage: str
    front_inside: CoverPipelineResult | None = None
    back_inside: CoverPipelineResult | None = None

    @property
    def by_role(self) -> dict[CoverRole, CoverPipelineResult]:
        values: dict[CoverRole, CoverPipelineResult | None] = {
            CoverRole.FRONT: self.front,
            CoverRole.FRONT_INSIDE: self.front_inside,
            CoverRole.BACK_INSIDE: self.back_inside,
            CoverRole.BACK: self.back,
        }
        return {role: value for role in BOOK_SURFACE_ORDER if (value := values[role]) is not None}

    @property
    def covers(self) -> tuple[CoverPipelineResult, ...]:
        return tuple(self.by_role.values())


class InMemoryResultStore:
    """Deterministic checkpoint store for tests and ephemeral CLI work."""

    def __init__(self) -> None:
        self._results: dict[str, EngineOcrResult] = {}

    def load(self, cache_key: str) -> EngineOcrResult | None:
        return self._results.get(cache_key)

    def save(self, cache_key: str, result: EngineOcrResult) -> None:
        self._results[cache_key] = result


class ZstdJsonResultStore:
    """Content-addressed `.json.zst` checkpoints written atomically."""

    def __init__(self, root: str | Path) -> None:
        self.root = Path(root)

    def _path(self, cache_key: str) -> Path:
        if len(cache_key) != 64 or any(
            character not in "0123456789abcdef" for character in cache_key
        ):
            raise ResultStoreError(f"Geçersiz OCR önbellek anahtarı: {cache_key!r}")
        return self.root / cache_key[:2] / f"{cache_key}.json.zst"

    def path_for(self, cache_key: str) -> Path:
        """Public path used by the DB checkpoint's raw_result_path column."""

        return self._path(cache_key)

    @staticmethod
    def _zstandard() -> Any:
        try:
            import zstandard
        except ImportError as exc:
            raise ResultStoreError(
                "Sıkıştırılmış OCR checkpointleri için zstandard eksik. "
                "`pip install 'zstandard>=0.23,<1'` komutunu çalıştırın."
            ) from exc
        return zstandard

    def load(self, cache_key: str) -> EngineOcrResult | None:
        path = self._path(cache_key)
        if not path.exists():
            return None
        zstandard = self._zstandard()
        try:
            payload = json.loads(
                zstandard.ZstdDecompressor().decompress(path.read_bytes()).decode("utf-8")
            )
            return EngineOcrResult.from_dict(payload)
        except Exception as exc:
            raise ResultStoreError(f"OCR checkpointi bozuk: {path}: {exc}") from exc

    def save(self, cache_key: str, result: EngineOcrResult) -> None:
        path = self._path(cache_key)
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary: Path | None = None
        zstandard = self._zstandard()
        try:
            raw = json.dumps(
                result.to_dict(),
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
            compressed = zstandard.ZstdCompressor(level=8).compress(raw)
            with tempfile.NamedTemporaryFile(
                mode="wb",
                dir=path.parent,
                prefix=f".{path.name}.",
                suffix=".part",
                delete=False,
            ) as handle:
                temporary = Path(handle.name)
                handle.write(compressed)
                handle.flush()
                os.fsync(handle.fileno())
            temporary.replace(path)
        except Exception as exc:
            if temporary is not None:
                with suppress(OSError):
                    temporary.unlink(missing_ok=True)
            raise ResultStoreError(f"OCR checkpointi yazılamadı: {path}: {exc}") from exc


class FiveOcrPipeline:
    def __init__(
        self,
        *,
        registry: FiveEngineRegistry,
        preprocessor: CoverPreprocessor,
        result_store: EngineResultStore,
        barcode_scanner: BarcodeScanner | None = None,
        config: PipelineConfig | None = None,
        event_handler: Callable[[PipelineEvent], None] | None = None,
        result_handler: Callable[[EngineCheckpoint], None] | None = None,
        calibration_profile: ConfidenceCalibrationProfile | None = None,
        engine_admission: (Callable[[str], AbstractContextManager[Any]] | None) = None,
    ) -> None:
        self.registry = registry
        self.preprocessor = preprocessor
        self.result_store = result_store
        self.barcode_scanner = barcode_scanner
        calibration_digest = (
            calibration_profile.digest() if calibration_profile is not None else "uncalibrated"
        )
        selected_config = config or PipelineConfig()
        if selected_config.calibration_digest not in {
            "uncalibrated",
            calibration_digest,
        }:
            raise ValueError("PipelineConfig kalibrasyon özeti yüklenen profille uyuşmuyor")
        self.config = replace(
            selected_config,
            calibration_digest=calibration_digest,
        )
        self.calibration_profile = calibration_profile
        self.event_handler = event_handler
        self.result_handler = result_handler
        self.engine_admission = engine_admission
        self._model_digests = {
            engine.engine_id: engine.model_digest() for engine in self.registry.engines
        }
        self._runtime_validated = False
        self._runtime_validation_lock = threading.Lock()
        self._callback_local = threading.local()
        self._cache_locks = tuple(threading.Lock() for _ in range(257))
        # Warm-up state is per book worker: a thread groups one book's surfaces,
        # runs the batch-capable engines over all of them at once, and the
        # ordinary per-cover path then finds those results already stored.
        self._warm_local = threading.local()

    def _emit(self, event: PipelineEvent) -> None:
        handler = getattr(self._callback_local, "event_handler", self.event_handler)
        if handler is not None:
            handler(event)

    def _result_callback(self) -> Callable[[EngineCheckpoint], None] | None:
        return getattr(self._callback_local, "result_handler", self.result_handler)

    @contextmanager
    def callbacks(
        self,
        *,
        event_handler: Callable[[PipelineEvent], None] | None,
        result_handler: Callable[[EngineCheckpoint], None] | None,
    ) -> Iterator[None]:
        """Install callbacks only for the current worker thread."""

        missing = object()
        previous_event = getattr(self._callback_local, "event_handler", missing)
        previous_result = getattr(self._callback_local, "result_handler", missing)
        self._callback_local.event_handler = event_handler
        self._callback_local.result_handler = result_handler
        try:
            yield
        finally:
            if previous_event is missing:
                del self._callback_local.event_handler
            else:
                self._callback_local.event_handler = previous_event
            if previous_result is missing:
                del self._callback_local.result_handler
            else:
                self._callback_local.result_handler = previous_result

    @contextmanager
    def warm_covers(self, source_paths: Sequence[str | Path]) -> Iterator[None]:
        """Read a book's surfaces with each batch-capable engine in one call.

        Engines whose model is reloaded per invocation dominate a book's cost:
        four surfaces mean four model loads each.  Inside this block those
        engines see all four surfaces at once, so the model loads once and the
        results land in the ordinary result store.  The per-cover path that runs
        afterwards finds them there and keeps every existing guarantee — the
        five-engine gate, per-surface checkpoints and validation are untouched.

        Warm-up is strictly an optimisation.  Any failure here is swallowed and
        the ordinary path runs exactly as before, with its own retries and its
        own error reporting.
        """

        # Save and restore rather than assign, so a nested block cannot strand
        # the outer one without its warm results.
        missing = object()
        previous_prepared = getattr(self._warm_local, "prepared", missing)
        previous_computed = getattr(self._warm_local, "computed", missing)
        self._warm_local.prepared = {}
        self._warm_local.computed = set()
        try:
            self._warm_covers(source_paths)
            yield
        finally:
            if previous_prepared is missing:
                self._warm_local.prepared = {}
            else:
                self._warm_local.prepared = previous_prepared
            if previous_computed is missing:
                self._warm_local.computed = set()
            else:
                self._warm_local.computed = previous_computed

    def _warm_covers(self, source_paths: Sequence[str | Path]) -> None:
        engines = [engine for engine in self.registry.engines if engine.batches_model_load]
        if not engines or len(source_paths) < 2:
            return
        try:
            self.validate_runtime()
            prepared = [self.preprocessor.prepare(path) for path in source_paths]
        except Exception:
            # Preparation problems belong to the ordinary path, which reports
            # them with the right cover role and event stream.
            return
        self._warm_local.prepared = {
            str(Path(image.source_path).resolve()): image for image in prepared
        }
        for engine in engines:
            try:
                pending = self._uncached_images(prepared, engine.engine_id)
            except Exception:
                # Reading the result store is part of the optimisation, not of
                # the guarantees; the ordinary path re-reads it anyway.
                continue
            if len(pending) < 2:
                continue
            self._emit(
                PipelineEvent(
                    stage="engine_warming",
                    cover_role="batch",
                    engine_id=engine.engine_id,
                    message=f"{len(pending)} yüz tek model yüklemesiyle okunuyor",
                )
            )
            try:
                admission = (
                    self.engine_admission(engine.engine_id)
                    if self.engine_admission is not None
                    else nullcontext()
                )
                with admission:
                    results = engine.recognize_many(pending)
                if len(results) != len(pending):
                    raise PipelineError(
                        f"{engine.engine_id} {len(pending)} yüz için {len(results)} sonuç döndürdü"
                    )
                for image, result in zip(pending, results, strict=True):
                    self._validate_result(
                        result,
                        expected_engine_id=engine.engine_id,
                        image=image,
                    )
                cache_keys = [self._cache_key(image, engine.engine_id) for image in pending]
                for cache_key, result in zip(cache_keys, results, strict=True):
                    self.result_store.save(cache_key, result)
                self._warm_local.computed.update(cache_keys)
            except Exception as exc:
                self._emit(
                    PipelineEvent(
                        stage="engine_warm_skipped",
                        cover_role="batch",
                        engine_id=engine.engine_id,
                        message=str(exc),
                    )
                )

    def _uncached_images(
        self,
        prepared: Sequence[PreparedImage],
        engine_id: str,
    ) -> list[PreparedImage]:
        """Images this engine has no stored result for, each listed once.

        The same surface can be named twice for one book — a single scan used
        as both the front and the front inside, say.  Sending it twice would pay
        for the same inference twice and then misreport the second read.
        """

        seen: set[str] = set()
        pending: list[PreparedImage] = []
        for image in prepared:
            cache_key = self._cache_key(image, engine_id)
            if cache_key in seen or self.result_store.load(cache_key) is not None:
                continue
            seen.add(cache_key)
            pending.append(image)
        return pending

    def _warm_prepared(self, source_path: str | Path) -> PreparedImage | None:
        prepared: dict[str, PreparedImage] = getattr(self._warm_local, "prepared", {})
        if not prepared:
            return None
        try:
            return prepared.get(str(Path(source_path).resolve()))
        except OSError:
            return None

    def _consume_warm_key(self, cache_key: str) -> bool:
        """Report whether this run, not an earlier one, produced the result.

        Warm-up results are stored exactly like cached ones, but calling them
        cache hits would misreport reuse across runs, which the job progress and
        the tests both rely on.
        """

        computed: set[str] = getattr(self._warm_local, "computed", set())
        if cache_key in computed:
            computed.discard(cache_key)
            return True
        return False

    def validate_runtime(self, *, force: bool = False) -> None:
        if self._runtime_validated and not force:
            return
        with self._runtime_validation_lock:
            if self._runtime_validated and not force:
                return
            self.registry.require_all_available()
            if self.config.require_barcode_scanner:
                if self.barcode_scanner is None:
                    raise PipelineError(
                        "Barkod tarayıcı zorunlu fakat yapılandırılmamış; "
                        "ZxingBarcodeScanner ekleyin"
                    )
                available, problems = self.barcode_scanner.availability()
                if not available:
                    raise PipelineError("Barkod tarayıcı kullanılamıyor: " + "; ".join(problems))
            self._runtime_validated = True

    def _cache_key(self, image: PreparedImage, engine_id: str) -> str:
        payload = {
            "source_sha256": image.source_sha256,
            "crop_sha256": image.crop_sha256,
            "preprocessing_version": image.preprocessing_version,
            "engine_id": engine_id,
            "model_digest": self._model_digests[engine_id],
            "config_hash": self.config.digest(),
        }
        return hashlib.sha256(
            json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()
        ).hexdigest()

    def _raw_result_path(self, cache_key: str) -> Path | None:
        path_for = getattr(self.result_store, "path_for", None)
        if not callable(path_for):
            return None
        return Path(path_for(cache_key))

    @staticmethod
    def _validate_result(
        result: EngineOcrResult,
        *,
        expected_engine_id: str,
        image: PreparedImage,
    ) -> None:
        if result.engine_id != expected_engine_id:
            raise InvalidEngineResultError(
                f"{expected_engine_id} kendisini {result.engine_id} olarak tanıttı"
            )
        if result.image_sha256 != image.image_sha256:
            raise InvalidEngineResultError(
                f"{expected_engine_id} sonucu farklı bir görüntü hashine ait"
            )
        expected_kind = "classic" if expected_engine_id in CLASSIC_ENGINE_IDS else "vision"
        if result.evidence_kind != expected_kind:
            raise InvalidEngineResultError(
                f"{expected_engine_id} kanıt türü {expected_kind} olmalıdır"
            )
        allowed_variants = (
            ALLOWED_CLASSIC_VARIANTS if expected_kind == "classic" else ALLOWED_VISION_VARIANTS
        )
        if result.variant not in allowed_variants:
            raise InvalidEngineResultError(
                f"{expected_engine_id} izin verilmeyen varyant döndürdü: {result.variant!r}"
            )
        if expected_kind == "classic" and any(token.polygon is None for token in result.tokens):
            raise InvalidEngineResultError(
                f"{expected_engine_id} konumsuz klasik OCR tokenı döndürdü"
            )

    def _checkpoint_result(
        self,
        *,
        prepared: PreparedImage,
        result: EngineOcrResult,
        cache_key: str,
        cover_role: str,
        from_cache: bool,
    ) -> None:
        handler = self._result_callback()
        if handler is None:
            return
        try:
            handler(
                EngineCheckpoint(
                    prepared=prepared,
                    result=result,
                    cache_key=cache_key,
                    model_digest=self._model_digests[result.engine_id],
                    config_hash=self.config.digest(),
                    from_cache=from_cache,
                    raw_result_path=self._raw_result_path(cache_key),
                    cover_role=cover_role,
                )
            )
        except Exception as exc:
            source = "önbellek sonucu" if from_cache else "sonucu"
            raise PipelineError(
                f"{result.engine_id} {source} kalıcı kayda geçirilemedi: {exc}"
            ) from exc

    def _run_engine(
        self,
        engine: OcrEngineAdapter,
        prepared: PreparedImage,
        *,
        cover_role: str,
    ) -> tuple[EngineOcrResult, bool]:
        cache_key = self._cache_key(prepared, engine.engine_id)
        cache_lock = self._cache_locks[int(cache_key[:8], 16) % len(self._cache_locks)]
        # Re-check under a striped content lock. Two queued copies of the same
        # cover must not launch the same expensive OCR call concurrently.
        with cache_lock:
            cached = self.result_store.load(cache_key)
            if cached is not None:
                from_cache = not self._consume_warm_key(cache_key)
                self._validate_result(
                    cached,
                    expected_engine_id=engine.engine_id,
                    image=prepared,
                )
                self._checkpoint_result(
                    prepared=prepared,
                    result=cached,
                    cache_key=cache_key,
                    cover_role=cover_role,
                    from_cache=from_cache,
                )
                self._emit(
                    PipelineEvent(
                        stage="engine_done",
                        cover_role=cover_role,
                        image_sha256=prepared.image_sha256,
                        engine_id=engine.engine_id,
                        from_cache=from_cache,
                    )
                )
                return cached, from_cache

            final_error: BaseException | None = None
            for attempt in range(1, self.config.max_retries + 2):
                self._emit(
                    PipelineEvent(
                        stage="engine_waiting",
                        cover_role=cover_role,
                        image_sha256=prepared.image_sha256,
                        engine_id=engine.engine_id,
                        attempt=attempt,
                    )
                )
                try:
                    admission = (
                        self.engine_admission(engine.engine_id)
                        if self.engine_admission is not None
                        else nullcontext()
                    )
                    with admission:
                        self._emit(
                            PipelineEvent(
                                stage="engine_running",
                                cover_role=cover_role,
                                image_sha256=prepared.image_sha256,
                                engine_id=engine.engine_id,
                                attempt=attempt,
                            )
                        )
                        result = engine.recognize(prepared)
                    self._validate_result(
                        result,
                        expected_engine_id=engine.engine_id,
                        image=prepared,
                    )
                    self.result_store.save(cache_key, result)
                    self._checkpoint_result(
                        prepared=prepared,
                        result=result,
                        cache_key=cache_key,
                        cover_role=cover_role,
                        from_cache=False,
                    )
                    self._emit(
                        PipelineEvent(
                            stage="engine_done",
                            cover_role=cover_role,
                            image_sha256=prepared.image_sha256,
                            engine_id=engine.engine_id,
                            attempt=attempt,
                        )
                    )
                    return result, False
                except PipelineError:
                    # Persistence failures are not inference failures. The
                    # content result is already durable and will be reused.
                    raise
                except Exception as exc:
                    final_error = exc
                    self._emit(
                        PipelineEvent(
                            stage="engine_retry",
                            cover_role=cover_role,
                            image_sha256=prepared.image_sha256,
                            engine_id=engine.engine_id,
                            attempt=attempt,
                            message=str(exc),
                        )
                    )

            assert final_error is not None
            self._emit(
                PipelineEvent(
                    stage="error",
                    cover_role=cover_role,
                    image_sha256=prepared.image_sha256,
                    engine_id=engine.engine_id,
                    message=str(final_error),
                )
            )
            raise PipelineError(
                f"{engine.engine_id} {self.config.max_retries + 1} denemede "
                f"tamamlanamadı; kayıt dört motorla devam ettirilmedi: {final_error}"
            ) from final_error

    def process_cover(
        self,
        source_path: str | Path,
        *,
        cover_role: str = "unknown",
    ) -> CoverPipelineResult:
        if cover_role not in {*(role.value for role in CoverRole), "unknown"}:
            raise ValueError(f"Geçersiz kapak rolü: {cover_role}")
        self.validate_runtime()
        self._emit(PipelineEvent(stage="preprocessing", cover_role=cover_role))
        # Preprocessing is deterministic and content addressed, so reusing the
        # warm-up's result is the same image, not merely an equivalent one.
        prepared = self._warm_prepared(source_path) or self.preprocessor.prepare(source_path)
        self._emit(
            PipelineEvent(
                stage="preprocessed",
                cover_role=cover_role,
                image_sha256=prepared.image_sha256,
            )
        )
        results: list[EngineOcrResult] = []
        cache_hits = 0
        for engine in self.registry.engines:
            result, from_cache = self._run_engine(
                engine,
                prepared,
                cover_role=cover_role,
            )
            results.append(result)
            cache_hits += int(from_cache)

        if len(results) != 5:
            raise PipelineError(
                f"İç tutarlılık hatası: uzlaştırma öncesi beş yerine {len(results)} sonuç var"
            )
        self._emit(
            PipelineEvent(
                stage="five_ocr_complete",
                cover_role=cover_role,
                image_sha256=prepared.image_sha256,
            )
        )
        consensus = reconcile_results(
            results,
            require_all_five=True,
            auto_confidence=self.config.auto_confidence,
            calibration_profile=self.calibration_profile,
        )
        consensus = replace(
            consensus,
            spans=tuple(
                replace(
                    span,
                    source_polygon=project_polygon_to_source(
                        span.polygon,
                        prepared.homography_to_source,
                    ),
                )
                for span in consensus.spans
            ),
        )
        self._emit(
            PipelineEvent(
                stage="reconciled",
                cover_role=cover_role,
                image_sha256=prepared.image_sha256,
            )
        )

        barcodes: tuple[BarcodeObservation, ...] = ()
        warnings = list(prepared.quality.warnings)
        if self.calibration_profile is None or not self.calibration_profile.trusted:
            warnings.append("Güvenilir kalibrasyon profili yok; otomatik alan kabulü kapalı")
        if self.barcode_scanner is not None:
            decoded: list[BarcodeObservation] = []
            barcode_errors: list[str] = []
            # Only the back surfaces carry an ISBN barcode. Paying the rescale
            # and rotation ladder on a front cover would upscale a multi-megapixel
            # image several times per book to find something that is not there.
            exhaustive = cover_role in {CoverRole.BACK.value, CoverRole.BACK_INSIDE.value}
            for variant, path in (
                ("source_oriented", prepared.source_path),
                ("canonical", prepared.canonical_path),
            ):
                try:
                    decoded.extend(
                        self.barcode_scanner.scan(
                            path,
                            variant=variant,
                            exhaustive=exhaustive,
                        )
                    )
                except TypeError:
                    # An injected scanner may predate the exhaustive flag.
                    decoded.extend(self.barcode_scanner.scan(path, variant=variant))
                except Exception as exc:
                    barcode_errors.append(f"{variant}: {exc}")
            barcodes = tuple(
                {
                    (
                        observation.text,
                        observation.format,
                        observation.isbn,
                        observation.variant,
                    ): observation
                    for observation in decoded
                }.values()
            )
            if barcode_errors and not decoded and self.config.require_barcode_scanner:
                raise PipelineError(
                    "Zorunlu barkod taraması iki görüntüde de başarısız: "
                    + "; ".join(barcode_errors)
                )
            warnings.extend(f"Barkod taraması yapılamadı: {error}" for error in barcode_errors)

        candidates_by_source: dict[tuple[str, str], IsbnCandidate] = {}
        for result in results:
            for candidate in extract_isbn_candidates(
                result.raw_text, source=f"ocr:{result.engine_id}"
            ):
                candidates_by_source.setdefault((candidate.isbn, candidate.source), candidate)
        for candidate in extract_isbn_candidates(consensus.raw_text, source="ocr:consensus"):
            candidates_by_source.setdefault((candidate.isbn, candidate.source), candidate)
        candidates = tuple(candidates_by_source.values())
        isbns, conflict = merge_isbn_evidence(candidates, barcodes)
        uncorroborated_ocr_isbn = bool(candidates) and not isbns and not barcodes
        needs_text_review = not consensus.spans or any(
            span.text.strip() and not span.eligible_for_auto for span in consensus.spans
        )
        stage = (
            "review" if conflict or uncorroborated_ocr_isbn or needs_text_review else "completed"
        )
        self._emit(
            PipelineEvent(
                stage=stage,
                cover_role=cover_role,
                image_sha256=prepared.image_sha256,
            )
        )
        return CoverPipelineResult(
            cover_role=cover_role,
            prepared=prepared,
            engine_results=tuple(results),
            consensus=consensus,
            barcodes=barcodes,
            isbn_candidates=candidates,
            isbns=isbns,
            isbn_conflict=conflict,
            cache_hits=cache_hits,
            stage=stage,
            warnings=tuple(warnings),
        )

    def process_pair(
        self,
        front_path: str | Path,
        back_path: str | Path,
        *,
        front_inside_path: str | Path | None = None,
        back_inside_path: str | Path | None = None,
    ) -> PairPipelineResult:
        warm_paths = [
            path
            for path in (front_path, front_inside_path, back_inside_path, back_path)
            if path is not None
        ]
        with self.warm_covers(warm_paths):
            front = self.process_cover(front_path, cover_role="front")
            front_inside = (
                self.process_cover(front_inside_path, cover_role="front_inside")
                if front_inside_path is not None
                else None
            )
            back_inside = (
                self.process_cover(back_inside_path, cover_role="back_inside")
                if back_inside_path is not None
                else None
            )
            back = self.process_cover(back_path, cover_role="back")
        covers = tuple(
            cover for cover in (front, front_inside, back_inside, back) if cover is not None
        )
        all_isbns, pair_conflict = merge_isbn_evidence(
            tuple(candidate for cover in covers for candidate in cover.isbn_candidates),
            tuple(barcode for cover in covers for barcode in cover.barcodes),
        )
        conflict = any(cover.isbn_conflict for cover in covers) or pair_conflict
        return PairPipelineResult(
            front=front,
            back=back,
            isbns=all_isbns,
            isbn_conflict=conflict,
            front_inside=front_inside,
            back_inside=back_inside,
            stage=(
                "review"
                if conflict or any(cover.stage != "completed" for cover in covers)
                else "completed"
            ),
        )
