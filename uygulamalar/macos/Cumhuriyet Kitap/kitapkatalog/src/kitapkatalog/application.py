"""Composition root shared by the CLI and PySide desktop entry points."""

from __future__ import annotations

import logging
import os
import threading
from dataclasses import dataclass
from pathlib import Path

from kitapkatalog.calibration import ConfidenceCalibrationProfile
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths, RuntimeLimits
from kitapkatalog.database import Database, DatabaseError
from kitapkatalog.extractor import EvidenceBoundExtractor
from kitapkatalog.images import CoverPreprocessor
from kitapkatalog.isbn import ZxingBarcodeScanner
from kitapkatalog.model_manager import ModelBundleError, ModelManager
from kitapkatalog.ocr.registry import build_offline_registry
from kitapkatalog.offline import install_network_guard
from kitapkatalog.pipeline import FiveOcrPipeline, PipelineConfig, ZstdJsonResultStore
from kitapkatalog.qwen_runtime import ManagedQwenClient
from kitapkatalog.scheduler import DurableScheduler, SchedulerResources


@dataclass(slots=True)
class ApplicationContext:
    paths: AppPaths
    database: Database
    catalog: Catalog
    models: ModelManager
    # Uygulama-geneli paylaşımlı kilit: açıkken bekleyen geri yükleme
    # uygulanamaz (restore.AppLock; süreç ömrü boyunca tutulur).
    app_lock: object | None = None

    def close(self) -> None:
        self.database.close()
        if self.app_lock is not None:
            self.app_lock.release()  # type: ignore[attr-defined]
            self.app_lock = None

    def processing_scheduler(
        self,
        *,
        limits: RuntimeLimits | None = None,
        event_handler: object | None = None,
        cancel: threading.Event | None = None,
    ) -> DurableScheduler:
        """Create the strict processing runtime only after all local assets pass."""

        statuses = self.models.require_all_ocr()
        extractor_status = self.models.extractor_status()
        if not extractor_status.available:
            raise ModelBundleError(
                "Qwen alan çıkarıcı paketi tamamlanmamış: " + "; ".join(extractor_status.reasons)
            )
        locked_manifest = self.paths.models / "model_manifest.lock.json"
        if not locked_manifest.is_file():
            raise ModelBundleError(f"Hash-kilitli model manifesti bulunamadı: {locked_manifest}")
        tesseract = _bundled_executable(self.paths.models, "tesseract")
        llama_server = _bundled_executable(self.paths.models, "llama-server")
        if tesseract is None or llama_server is None:
            raise ModelBundleError("Paketlenmiş Tesseract/llama-server bulunamadı")

        registry = build_offline_registry(
            manifest_path=locked_manifest,
            model_root=self.paths.models,
            vision_backend=llama_server,
            tesseract_executable=tesseract,
            strict_hashes=True,
        )
        preprocessor = CoverPreprocessor(self.paths.derivatives)
        result_store = ZstdJsonResultStore(self.paths.ocr_raw)
        barcode_scanner = ZxingBarcodeScanner()
        calibration_profile: ConfidenceCalibrationProfile | None = (
            self.models.optional_calibration_profile()
        )
        pipeline = FiveOcrPipeline(
            registry=registry,
            preprocessor=preprocessor,
            result_store=result_store,
            barcode_scanner=barcode_scanner,
            config=PipelineConfig(max_retries=2, require_barcode_scanner=True),
            event_handler=event_handler if callable(event_handler) else None,
            calibration_profile=calibration_profile,
        )
        qwen_path = self.paths.models / "qwen3" / "Qwen3-4B-Q4_K_M.gguf"
        extractor = EvidenceBoundExtractor(
            ManagedQwenClient(
                executable=llama_server,
                model_path=qwen_path,
            )
        )
        limits = limits or RuntimeLimits()
        resources = SchedulerResources.create(
            lock_root=self.paths.root / "locks",
            limits=limits,
            cancel=cancel,
        )
        scheduler = DurableScheduler(
            database=self.database,
            pipeline=pipeline,
            extractor=extractor,
            asset_root=self.paths.assets,
            resources=resources,
            limits=limits,
        )
        # Keep the verified statuses live long enough for debuggers/readiness
        # reports to prove all five exact IDs were checked.
        if len(statuses) != 5:
            raise ModelBundleError("Model yöneticisi beş OCR durumu döndürmedi")
        return scheduler


def open_application(
    paths: AppPaths | None = None,
    *,
    enforce_offline: bool = True,
) -> ApplicationContext:
    """Open catalogue/UI services without requiring model files at startup."""

    if enforce_offline:
        install_network_guard()
    selected = paths or AppPaths.default()
    selected.ensure()

    # Bekleyen geri yükleme, veritabanı açılmadan uygulanır; her giriş yolu
    # (web/CLI/Qt) buradan geçer. Hata açılışı asla engellemez.
    from kitapkatalog.restore import AppLock, apply_pending_restore

    app_lock = AppLock(selected)
    try:
        apply_pending_restore(selected, app_lock)
    except Exception:
        logging.getLogger(__name__).exception("Bekleyen geri yükleme uygulanamadı")
    exclusive_upgrade = False
    try:
        models = ModelManager(selected)
        models.apply_offline_environment()
        from kitapkatalog.upgrade import open_database_safely, schema_upgrade_needed

        exclusive_upgrade = schema_upgrade_needed(selected.database)
        if exclusive_upgrade and not app_lock.try_acquire_exclusive():
            raise DatabaseError(
                "Katalog şeması yükseltilecek ancak başka bir KitapKatalog "
                "süreci açık. Diğer pencereyi kapatıp yeniden deneyin."
            )
        if not exclusive_upgrade:
            app_lock.acquire_shared()
        result = open_database_safely(selected)
        database = result.database
        if exclusive_upgrade:
            app_lock.release()
            exclusive_upgrade = False
            app_lock.acquire_shared()
    except BaseException:
        # Açılış yarıda kalırsa paylaşımlı kilit sızmasın (sonraki geri
        # yükleme denemelerini süreç ömrü boyunca erteliyordu).
        app_lock.release()
        raise
    return ApplicationContext(
        paths=selected,
        database=database,
        catalog=Catalog(database),
        models=models,
        app_lock=app_lock,
    )


def _bundled_executable(model_root: Path, name: str) -> Path | None:
    env_name = f"KITAPKATALOG_{name.upper().replace('-', '_')}_BIN"
    if override := os.environ.get(env_name):
        path = Path(override).expanduser()
        return path if path.is_file() else None
    candidates = (model_root / "bin" / name, model_root / "bin" / f"{name}.exe")
    return next((path for path in candidates if path.is_file()), None)
