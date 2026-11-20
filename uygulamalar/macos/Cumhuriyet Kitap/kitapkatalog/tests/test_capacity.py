from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import pytest

from kitapkatalog.capacity import (
    CapacityError,
    estimate_import_capacity,
    require_capacity,
)
from kitapkatalog.domain import StorageMode


def test_managed_copy_and_reference_have_different_cost(tmp_path: Path) -> None:
    image = tmp_path / "ön.jpg"
    image.write_bytes(b"x" * 1024)
    managed = estimate_import_capacity(
        [image],
        data_root=tmp_path / "managed",
        model_root=tmp_path / "models",
        storage_mode=StorageMode.MANAGED_COPY,
        expected_model_bundle_bytes=0,
    )
    referenced = estimate_import_capacity(
        [image],
        data_root=tmp_path / "reference",
        model_root=tmp_path / "models",
        storage_mode=StorageMode.REFERENCE,
        expected_model_bundle_bytes=0,
    )
    assert managed.managed_copy_bytes == 1024
    assert referenced.managed_copy_bytes == 0
    assert managed.required_additional_bytes > referenced.required_additional_bytes


def test_missing_input_is_rejected(tmp_path: Path) -> None:
    with pytest.raises(CapacityError, match="bulunamadı"):
        estimate_import_capacity(
            [tmp_path / "missing.jpg"],
            data_root=tmp_path / "data",
            model_root=tmp_path / "models",
        )


def test_shortfall_error_is_actionable(tmp_path: Path) -> None:
    image = tmp_path / "arka.jpg"
    image.write_bytes(b"x")
    estimate = estimate_import_capacity(
        [image],
        data_root=tmp_path / "data",
        model_root=tmp_path / "models",
        expected_model_bundle_bytes=0,
    )
    insufficient = replace(estimate, free_bytes=1)
    with pytest.raises(CapacityError, match="GiB eksik"):
        require_capacity(insufficient)
