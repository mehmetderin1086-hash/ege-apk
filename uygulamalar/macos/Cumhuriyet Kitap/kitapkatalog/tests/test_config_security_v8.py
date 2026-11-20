from __future__ import annotations

import stat
from pathlib import Path

from kitapkatalog.config import AppPaths


def test_ensure_repairs_private_data_tree_and_existing_database_files(
    tmp_path: Path,
) -> None:
    root = tmp_path / "data"
    root.mkdir(mode=0o755)
    assets = root / "assets"
    assets.mkdir(mode=0o755)
    database = root / "catalog.sqlite3"
    database.write_bytes(b"existing")
    database.chmod(0o644)
    wal = Path(f"{database}-wal")
    wal.write_bytes(b"wal")
    wal.chmod(0o644)
    shm = Path(f"{database}-shm")
    shm.write_bytes(b"shm")
    shm.chmod(0o644)

    paths = AppPaths(
        root=root,
        database=database,
        assets=assets,
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=root / "models",
        exports=root / "exports",
        logs=root / "logs",
    )
    paths.ensure()

    directories = (
        paths.root,
        paths.assets,
        paths.derivatives,
        paths.ocr_raw,
        paths.models,
        paths.exports,
        paths.logs,
        paths.voice_assets,
        paths.transcripts,
    )
    assert all(stat.S_IMODE(path.stat().st_mode) == 0o700 for path in directories)
    assert stat.S_IMODE(database.stat().st_mode) == 0o600
    assert stat.S_IMODE(wal.stat().st_mode) == 0o600
    assert stat.S_IMODE(shm.stat().st_mode) == 0o600


def test_ensure_does_not_chmod_external_model_bundle(tmp_path: Path) -> None:
    root = tmp_path / "data"
    external_models = tmp_path / "shared-models"
    external_models.mkdir(mode=0o755)
    paths = AppPaths(
        root=root,
        database=root / "catalog.sqlite3",
        assets=root / "assets",
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=external_models,
        exports=root / "exports",
        logs=root / "logs",
    )

    paths.ensure()

    assert stat.S_IMODE(root.stat().st_mode) == 0o700
    assert stat.S_IMODE(external_models.stat().st_mode) == 0o755


def test_unowned_custom_database_parent_keeps_existing_directory_modes(
    tmp_path: Path,
) -> None:
    shared = tmp_path / "shared-parent"
    shared.mkdir(mode=0o755)
    existing_assets = shared / "assets"
    existing_assets.mkdir(mode=0o755)
    database = shared / "custom.sqlite3"
    database.write_bytes(b"existing")
    database.chmod(0o644)
    wal = Path(f"{database}-wal")
    wal.write_bytes(b"wal")
    wal.chmod(0o644)

    paths = AppPaths(
        root=shared,
        database=database,
        assets=existing_assets,
        derivatives=shared / "derivatives",
        ocr_raw=shared / "ocr-raw",
        models=shared / "models",
        exports=shared / "exports",
        logs=shared / "logs",
        owns_data_root=False,
    )
    paths.ensure()

    assert stat.S_IMODE(shared.stat().st_mode) == 0o755
    assert stat.S_IMODE(existing_assets.stat().st_mode) == 0o755
    for created in (
        paths.derivatives,
        paths.ocr_raw,
        paths.models,
        paths.exports,
        paths.logs,
        paths.voice_assets,
        paths.transcripts,
    ):
        assert stat.S_IMODE(created.stat().st_mode) == 0o700
    assert stat.S_IMODE(database.stat().st_mode) == 0o600
    assert stat.S_IMODE(wal.stat().st_mode) == 0o600
