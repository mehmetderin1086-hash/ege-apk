"""Streaming disk-capacity estimate performed before a large import."""

from __future__ import annotations

import shutil
from dataclasses import dataclass
from pathlib import Path

from kitapkatalog.domain import StorageMode


class CapacityError(RuntimeError):
    """The requested import cannot be sized or safely stored."""


@dataclass(frozen=True, slots=True)
class CapacityEstimate:
    image_count: int
    source_bytes: int
    managed_copy_bytes: int
    derivative_bytes: int
    ocr_evidence_bytes: int
    database_bytes: int
    model_bytes: int
    reserve_bytes: int
    required_additional_bytes: int
    free_bytes: int

    @property
    def sufficient(self) -> bool:
        return self.free_bytes >= self.required_additional_bytes

    @property
    def shortfall_bytes(self) -> int:
        return max(0, self.required_additional_bytes - self.free_bytes)


def _tree_bytes(root: Path) -> int:
    if not root.exists():
        return 0
    return sum(path.stat().st_size for path in root.rglob("*") if path.is_file())


def estimate_import_capacity(
    image_paths: list[Path] | tuple[Path, ...],
    *,
    data_root: Path,
    model_root: Path,
    storage_mode: StorageMode = StorageMode.MANAGED_COPY,
    expected_model_bundle_bytes: int = 10 * 1024**3,
) -> CapacityEstimate:
    """Estimate conservatively without loading image bytes into memory.

    Canonical PNG/CLAHE derivatives can exceed compressed phone JPEGs, so the
    estimate reserves three source bytes per source byte.  Raw evidence uses a
    per-cover floor for five engines, protecting text-dense back covers.
    """

    paths = tuple(dict.fromkeys(Path(path) for path in image_paths))
    if not paths:
        raise CapacityError("İçe aktarılacak fotoğraf seçilmedi")
    missing = [str(path) for path in paths if not path.is_file()]
    if missing:
        raise CapacityError(f"Fotoğraf bulunamadı: {', '.join(missing[:5])}")
    source_bytes = sum(path.stat().st_size for path in paths)
    image_count = len(paths)
    managed_bytes = source_bytes if storage_mode is StorageMode.MANAGED_COPY else 0
    derivative_bytes = max(image_count * 1024**2, source_bytes * 3)
    # Five compressed raw result files and consensus/provenance metadata.
    ocr_evidence_bytes = max(image_count * 5 * 128 * 1024, source_bytes // 4)
    database_bytes = max(image_count * 96 * 1024, 32 * 1024**2)

    installed_model_bytes = _tree_bytes(model_root)
    model_bytes = max(0, expected_model_bundle_bytes - installed_model_bytes)
    subtotal = managed_bytes + derivative_bytes + ocr_evidence_bytes + database_bytes + model_bytes
    # Keep both a fixed emergency reserve and 10% headroom for WAL/.part files.
    reserve_bytes = max(5 * 1024**3, subtotal // 10)
    required = subtotal + reserve_bytes
    data_root.mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(data_root).free
    return CapacityEstimate(
        image_count=image_count,
        source_bytes=source_bytes,
        managed_copy_bytes=managed_bytes,
        derivative_bytes=derivative_bytes,
        ocr_evidence_bytes=ocr_evidence_bytes,
        database_bytes=database_bytes,
        model_bytes=model_bytes,
        reserve_bytes=reserve_bytes,
        required_additional_bytes=required,
        free_bytes=free,
    )


def require_capacity(estimate: CapacityEstimate) -> None:
    if not estimate.sufficient:
        raise CapacityError(
            "Yetersiz disk alanı: "
            f"{estimate.required_additional_bytes / 1024**3:.2f} GiB gerekli, "
            f"{estimate.free_bytes / 1024**3:.2f} GiB boş, "
            f"{estimate.shortfall_bytes / 1024**3:.2f} GiB eksik"
        )
