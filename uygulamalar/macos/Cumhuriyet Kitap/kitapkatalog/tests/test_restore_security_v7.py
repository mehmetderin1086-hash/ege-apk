"""v0.7 restore şema/FK bütünlüğü ve kapak yolu güvenliği regresyonları."""

from __future__ import annotations

import sqlite3
from contextlib import closing
from pathlib import Path

import pytest

from kitapkatalog.archive import ArchiveError, create_archive
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths
from kitapkatalog.database import SCHEMA_VERSION, Database
from kitapkatalog.domain import BookInput
from kitapkatalog.restore import (
    RESTORE_DIRNAME,
    AppLock,
    apply_pending_restore,
    confirm_restore,
    stage_archive,
)


@pytest.fixture()
def paths(tmp_path: Path) -> AppPaths:
    selected = AppPaths(
        root=tmp_path / "hedef",
        database=tmp_path / "hedef" / "catalog.sqlite3",
        assets=tmp_path / "hedef" / "assets",
        derivatives=tmp_path / "hedef" / "derivatives",
        ocr_raw=tmp_path / "hedef" / "ocr-raw",
        models=tmp_path / "hedef" / "models",
        exports=tmp_path / "hedef" / "exports",
        logs=tmp_path / "hedef" / "logs",
    )
    selected.ensure()
    return selected


def _source_database(tmp_path: Path) -> tuple[Path, int]:
    source = tmp_path / "kaynak.sqlite3"
    database = Database(source)
    record = Catalog(database).save_book(BookInput(title="Güvenli Restore"))
    database.close()
    return source, record.edition_id


def _archive(database: Path, tmp_path: Path, name: str) -> Path:
    return create_archive(database, tmp_path / name).path


def test_stage_rejects_foreign_key_corruption(paths: AppPaths, tmp_path: Path) -> None:
    database, edition_id = _source_database(tmp_path)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute("PRAGMA foreign_keys = OFF")
        connection.execute("UPDATE edition SET work_id = 999999 WHERE id = ?", (edition_id,))
        connection.commit()

    archive = _archive(database, tmp_path, "fk-bozuk.kitaparsiv")
    with pytest.raises(ArchiveError, match="yabancı anahtar bütünlüğü"):
        stage_archive(archive, paths)
    assert list((paths.root / RESTORE_DIRNAME).glob("hazirlik-*")) == []


def test_stage_requires_exact_application_id(paths: AppPaths, tmp_path: Path) -> None:
    database, _ = _source_database(tmp_path)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute("PRAGMA application_id = 0")
    archive = _archive(database, tmp_path, "yanlis-app-id.kitaparsiv")

    with pytest.raises(ArchiveError, match="KitapKatalog kataloğu değil"):
        stage_archive(archive, paths)


def test_stage_requires_user_version_migration_consistency(paths: AppPaths, tmp_path: Path) -> None:
    database, _ = _source_database(tmp_path)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute("DELETE FROM schema_migration WHERE version = ?", (SCHEMA_VERSION,))
        connection.commit()
    archive = _archive(database, tmp_path, "migration-bozuk.kitaparsiv")

    with pytest.raises(ArchiveError, match="schema_migration kayıtları tutarsız"):
        stage_archive(archive, paths)


def test_confirm_clears_absolute_cover_without_archive_member(
    paths: AppPaths, tmp_path: Path
) -> None:
    database, edition_id = _source_database(tmp_path)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            "UPDATE edition SET front_path = '/etc/hosts' WHERE id = ?", (edition_id,)
        )
        connection.commit()
    archive = _archive(database, tmp_path, "mutlak-kapak.kitaparsiv")

    summary = stage_archive(archive, paths)
    result = confirm_restore(summary.staging_id, paths)

    assert result["relocation"]["cleared"] == 1
    staged = paths.root / RESTORE_DIRNAME / summary.staging_id / "catalog" / "catalog.sqlite3"
    with closing(sqlite3.connect(staged)) as connection:
        front_path = connection.execute(
            "SELECT front_path FROM edition WHERE id = ?", (edition_id,)
        ).fetchone()[0]
    assert front_path is None


def test_root_cover_does_not_capture_external_same_named_reference(
    paths: AppPaths, tmp_path: Path
) -> None:
    database, edition_id = _source_database(tmp_path)
    with closing(sqlite3.connect(database)) as connection:
        connection.execute(
            "UPDATE edition SET front_path = '/tmp/on.jpg' WHERE id = ?",
            (edition_id,),
        )
        connection.commit()
    assets = tmp_path / "assets"
    assets.mkdir()
    unrelated = assets / "on.jpg"
    unrelated.write_bytes(b"baska-kapak")
    archive = create_archive(
        database,
        tmp_path / "ayni-ad.kitaparsiv",
        asset_root=assets,
        cover_paths=[unrelated],
        include_covers=True,
    ).path

    summary = stage_archive(archive, paths)
    result = confirm_restore(summary.staging_id, paths)

    assert result["relocation"]["rewritten"] == 0
    assert result["relocation"]["cleared"] == 1
    staged = paths.root / RESTORE_DIRNAME / summary.staging_id / "catalog" / "catalog.sqlite3"
    with closing(sqlite3.connect(staged)) as connection:
        front_path = connection.execute(
            "SELECT front_path FROM edition WHERE id = ?", (edition_id,)
        ).fetchone()[0]
    assert front_path is None


def test_nested_cover_does_not_capture_external_same_suffix(
    paths: AppPaths, tmp_path: Path
) -> None:
    database, edition_id = _source_database(tmp_path)
    stamp = "2026-01-01T00:00:00+00:00"
    catalog_db = Database(database)
    try:
        with catalog_db.transaction() as connection:
            connection.execute(
                "INSERT INTO work(id, canonical_title, created_at, updated_at) "
                "VALUES (99, 'Harici', ?, ?)",
                (stamp, stamp),
            )
            connection.execute(
                "INSERT INTO edition(id, work_id, title, front_path, created_at, updated_at) "
                "VALUES (99, 99, 'Harici', '/tmp/foo/front.jpg', ?, ?)",
                (stamp, stamp),
            )
            # Resmî CLI --asset-root seçeneği varsayılan "assets" adına
            # bağlı değildir; tuzlu manifest kanıtı bu yolu yine ayırt eder.
            managed = tmp_path / "kitap-kapaklari" / "foo" / "front.jpg"
            managed.parent.mkdir(parents=True)
            managed.write_bytes(b"yonetilen")
            connection.execute(
                "UPDATE edition SET front_path = ? WHERE id = ?",
                (str(managed), edition_id),
            )
    finally:
        catalog_db.close()
    archive = create_archive(
        database,
        tmp_path / "ic-ice-ayni-ad.kitaparsiv",
        asset_root=tmp_path / "kitap-kapaklari",
        cover_paths=[managed],
        include_covers=True,
    ).path

    summary = stage_archive(archive, paths)
    result = confirm_restore(summary.staging_id, paths)

    assert result["relocation"] == {"rewritten": 1, "unmatched": 1, "cleared": 1}
    staged = paths.root / RESTORE_DIRNAME / summary.staging_id / "catalog" / "catalog.sqlite3"
    with closing(sqlite3.connect(staged)) as connection:
        rows = dict(connection.execute("SELECT id, front_path FROM edition"))
    assert rows[edition_id] is not None
    assert rows[99] is None

    applied = apply_pending_restore(paths, AppLock(paths))
    assert applied is not None and applied["status"] == "applied"
    with closing(sqlite3.connect(paths.database)) as connection:
        restored_rows = dict(connection.execute("SELECT id, front_path FROM edition"))
    restored_cover = Path(restored_rows[edition_id])
    assert restored_rows[99] is None
    assert restored_cover.is_relative_to(paths.assets)
    assert restored_cover.read_bytes() == b"yonetilen"
