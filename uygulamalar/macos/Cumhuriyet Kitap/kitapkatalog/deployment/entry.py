#!/usr/bin/env python3
"""Frozen application entry point.

The deployment entry point intentionally imports no OCR or Qt package until the
offline environment and network guard have been installed.
"""

from __future__ import annotations

import builtins
import os
import sys
from dataclasses import replace
from pathlib import Path

APP_NAME = "KitapKatalog"
MODEL_DIRECTORY_NAME = "KitapKatalog-models"
MODEL_ENVIRONMENT_VARIABLE = "KITAPKATALOG_MODEL_DIR"
FROZEN_SIDECAR_ENVIRONMENT_VARIABLE = "KITAPKATALOG_FROZEN_VISION_SIDECAR_EXECUTABLE"
VISION_SIDECAR_ARGUMENT = "--vision-sidecar"
RUNTIME_SMOKE_ARGUMENT = "--runtime-smoke"


def _offline_environment() -> dict[str, str]:
    return {
        "HF_HUB_OFFLINE": "1",
        "TRANSFORMERS_OFFLINE": "1",
        "HF_DATASETS_OFFLINE": "1",
        "DO_NOT_TRACK": "1",
        "PIP_DISABLE_PIP_VERSION_CHECK": "1",
        "PIP_NO_INDEX": "1",
        "KITAPKATALOG_NETWORK_DISABLED": "1",
    }


def _candidate_model_directories(executable: Path) -> tuple[Path, ...]:
    """Return sidecar locations from closest to furthest.

    macOS standalone output places the executable below
    ``KitapKatalog.app/Contents/MacOS``. Windows standalone output normally
    places it directly in the release directory. Walking a bounded number of
    parents supports both layouts without scanning arbitrary user folders.
    """

    directories: list[Path] = []
    current = executable.resolve().parent
    for _ in range(5):
        directories.extend(
            (
                current / MODEL_DIRECTORY_NAME,
                current / "models",
                current / "Resources" / MODEL_DIRECTORY_NAME,
            )
        )
        if current.parent == current:
            break
        current = current.parent
    return tuple(dict.fromkeys(directories))


def discover_model_directory(*, executable: Path | None = None) -> Path:
    explicit = os.environ.get(MODEL_ENVIRONMENT_VARIABLE)
    if explicit:
        return Path(explicit).expanduser().resolve()

    executable = executable or Path(sys.executable)
    for candidate in _candidate_model_directories(executable):
        if (candidate / "model_manifest.lock.json").is_file():
            return candidate

    # Development and separately installed model bundles live in the normal
    # application data directory. Importing config here is safe because the
    # offline environment is installed by ``configure_runtime`` first.
    from kitapkatalog.config import AppPaths

    return AppPaths.default().models.resolve()


def verify_runtime(model_directory: Path) -> None:
    from kitapkatalog.config import AppPaths
    from kitapkatalog.model_bundle import verify_locked_bundle
    from kitapkatalog.model_manager import ModelManager

    violations = verify_locked_bundle(model_directory)
    if violations:
        details = "\n- ".join(violations)
        raise RuntimeError(
            "Çevrimdışı model paketi eksik veya bozuk.\n"
            f"Konum: {model_directory}\n"
            f"- {details}\n"
            "Paket çalışma sırasında indirilmez; yerel model hazırlama aracını kullanın."
        )

    paths = replace(AppPaths.default(), models=model_directory)
    manager = ModelManager(
        paths,
        manifest_path=model_directory / "model_manifest.lock.json",
    )
    manager.apply_offline_environment()
    manager.require_all_ocr()
    extractor = manager.extractor_status()
    if not extractor.available:
        raise RuntimeError("Qwen alan çıkarıcı hazır değil: " + "; ".join(extractor.reasons))


def configure_runtime() -> Path:
    os.environ.update(_offline_environment())

    from kitapkatalog.offline import install_network_guard

    install_network_guard()
    if _running_as_frozen_application():
        os.environ[FROZEN_SIDECAR_ENVIRONMENT_VARIABLE] = str(Path(sys.executable).resolve())
    model_directory = discover_model_directory()
    os.environ[MODEL_ENVIRONMENT_VARIABLE] = str(model_directory)
    # A source/app-only distribution may start so its model readiness screen
    # can explain what is missing. If a locked bundle is present, however, any
    # corruption is fatal and is never silently bypassed.
    if (model_directory / "model_manifest.lock.json").is_file():
        verify_runtime(model_directory)
    return model_directory


def _running_as_frozen_application() -> bool:
    """Recognize Nuitka/PyInstaller-style executable runtimes."""

    return bool(getattr(sys, "frozen", False)) or hasattr(builtins, "__compiled__")


def _run_vision_sidecar() -> int:
    """Dispatch the frozen executable as a JSON-stdio vision worker.

    The parent application already validated the hash-locked model bundle.
    Re-hashing several gigabytes in every per-cover child would be both
    redundant and prohibitively expensive, so the child installs only the
    offline/network guard before validating its request paths itself.
    """

    os.environ.update(_offline_environment())
    from kitapkatalog.offline import install_network_guard

    install_network_guard()
    from kitapkatalog.ocr.sidecar_runtime import main as sidecar_main

    return int(sidecar_main())


def _run_runtime_smoke() -> int:
    """Prove that the frozen release contains its local runtime dependencies."""

    import importlib
    import json

    os.environ.update(_offline_environment())
    from kitapkatalog.offline import install_network_guard

    install_network_guard()
    modules = (
        "PySide6",
        "cv2",
        "numpy",
        "onnxruntime",
        "rapidocr",
        "easyocr",
        "torch",
        "torchvision",
        "zxingcpp",
        "pillow_heif",
        "pypdfium2",
        "openpyxl",
        "zstandard",
    )
    report: dict[str, object] = {
        "application": APP_NAME,
        "offline": os.environ.get("KITAPKATALOG_NETWORK_DISABLED") == "1",
        "python": sys.version.split()[0],
        "modules": {},
    }
    failures = 0
    module_report = report["modules"]
    assert isinstance(module_report, dict)
    for name in modules:
        try:
            module = importlib.import_module(name)
            module_report[name] = {
                "available": True,
                "version": str(getattr(module, "__version__", "unknown")),
            }
        except Exception as exc:
            failures += 1
            module_report[name] = {
                "available": False,
                "error": f"{type(exc).__name__}: {exc}",
            }
    report["ok"] = failures == 0
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    return 0 if failures == 0 else 2


def _show_fatal_error(message: str) -> None:
    print(f"{APP_NAME}: {message}", file=sys.stderr)
    try:
        from PySide6.QtWidgets import QApplication, QMessageBox
    except ImportError:
        return

    application = QApplication.instance() or QApplication([APP_NAME])
    QMessageBox.critical(None, f"{APP_NAME} başlatılamadı", message)
    if QApplication.instance() is application:
        application.processEvents()


def main() -> int:
    if sys.argv[1:] == [VISION_SIDECAR_ARGUMENT]:
        return _run_vision_sidecar()
    if sys.argv[1:] == [RUNTIME_SMOKE_ARGUMENT]:
        return _run_runtime_smoke()
    try:
        configure_runtime()
        try:
            from kitapkatalog.gui import main as gui_main
        except ImportError as exc:
            raise RuntimeError(
                "PySide6 arayüzü yüklenemedi. Bu platform için hazırlanmış "
                "KitapKatalog paketini kullanın."
            ) from exc
        result = gui_main()
        return int(result) if result is not None else 0
    except Exception as exc:  # The executable must surface startup failures.
        _show_fatal_error(str(exc))
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
