from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.application import open_application
from kitapkatalog.config import AppPaths
from kitapkatalog.model_manager import ModelBundleError
from kitapkatalog.offline import _uninstall_for_tests, network_guard_installed


def _paths(root: Path) -> AppPaths:
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


def test_catalog_opens_without_models_but_processing_fails_closed(
    tmp_path: Path,
) -> None:
    context = open_application(_paths(tmp_path), enforce_offline=False)
    try:
        assert context.database.integrity_check() == "ok"
        assert context.models.runtime_report()["five_ocr_ready"] is False
        with pytest.raises(ModelBundleError, match="Beş OCR"):
            context.processing_scheduler()
    finally:
        context.close()


def test_normal_app_context_installs_network_guard(tmp_path: Path) -> None:
    _uninstall_for_tests()
    context = open_application(_paths(tmp_path))
    try:
        assert network_guard_installed()
    finally:
        context.close()
        _uninstall_for_tests()


def test_model_directory_can_be_separate_from_user_data(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    data = tmp_path / "data"
    models = tmp_path / "read-only-models"
    monkeypatch.setenv("KITAPKATALOG_DATA_DIR", str(data))
    monkeypatch.setenv("KITAPKATALOG_MODEL_DIR", str(models))
    paths = AppPaths.default()
    assert paths.root == data
    assert paths.models == models
    assert paths.database.parent == data
