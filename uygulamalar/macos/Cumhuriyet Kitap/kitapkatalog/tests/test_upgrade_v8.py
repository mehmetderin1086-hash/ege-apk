"""Fail-closed v7 -> current schema upgrade and automatic rollback gates."""

from __future__ import annotations

import errno
import os
import sqlite3
import stat
from pathlib import Path

import pytest

from kitapkatalog.archive import create_archive, inspect_archive
from kitapkatalog.config import AppPaths
from kitapkatalog.database import SCHEMA_VERSION, Database, _unicode_nocase
from kitapkatalog.upgrade import (
    SchemaUpgradeError,
    _restore_database_from_archive,
    open_database_safely,
)


def _paths(tmp_path: Path) -> AppPaths:
    paths = AppPaths(
        root=tmp_path,
        database=tmp_path / "catalog.sqlite3",
        assets=tmp_path / "assets",
        derivatives=tmp_path / "derivatives",
        ocr_raw=tmp_path / "ocr-raw",
        models=tmp_path / "models",
        exports=tmp_path / "exports",
        logs=tmp_path / "logs",
    )
    paths.ensure()
    return paths


def _v7_catalog(paths: AppPaths) -> None:
    """Build a real v7 schema without allowing Database to run v8."""

    cover = paths.assets / "front.jpg"
    cover.write_bytes(b"root-managed-cover")
    with sqlite3.connect(paths.database, isolation_level=None) as connection:
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        connection.execute("PRAGMA foreign_keys = ON")
        for version in range(1, 8):
            getattr(Database, f"_migrate_v{version}")(connection)
        stamp = "2026-08-08T12:00:00+00:00"
        connection.execute(
            "INSERT INTO work(id, canonical_title, created_at, updated_at) VALUES (1, ?, ?, ?)",
            ("Yükseltme Kitabı", stamp, stamp),
        )
        connection.execute(
            """
            INSERT INTO edition(id, work_id, title, front_path, created_at, updated_at)
            VALUES (1, 1, ?, ?, ?, ?)
            """,
            ("Yükseltme Kitabı", str(cover), stamp, stamp),
        )
        connection.execute(
            """
            INSERT INTO copy(id, edition_id, inventory_code, created_at, updated_at)
            VALUES (1, 1, '2026-000001', ?, ?)
            """,
            (stamp, stamp),
        )
        connection.execute(
            """
            INSERT INTO member(id, member_type, school_number, first_name, last_name,
                               class_name, created_at, updated_at)
            VALUES (1, 'student', '101', 'Ada', 'Yılmaz', '9-A', ?, ?)
            """,
            (stamp, stamp),
        )
        connection.execute(
            """
            INSERT INTO loan(id, copy_id, member_id, edition_id, title_snapshot,
                             inventory_code_snapshot, loaned_at, due_at,
                             created_at, updated_at)
            VALUES (1, 1, 1, 1, 'Yükseltme Kitabı', '2026-000001', ?, '2026-08-20', ?, ?)
            """,
            (stamp, stamp, stamp),
        )


@pytest.mark.skipif(SCHEMA_VERSION < 8, reason="v8 migration not installed yet")
def test_upgrade_requires_verified_cover_backup_and_preserves_counts(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    _v7_catalog(paths)

    result = open_database_safely(paths)
    try:
        assert result.from_version == 7
        assert result.to_version == SCHEMA_VERSION
        assert result.backup is not None and result.backup.is_file()
        assert stat.S_IMODE(result.backup.stat().st_mode) == 0o600
        assert inspect_archive(result.backup).cover_count == 1
        assert result.database.fetchone("PRAGMA user_version")[0] == SCHEMA_VERSION
        assert result.database.fetchone("SELECT COUNT(*) FROM edition")[0] == 1
        assert result.database.fetchone("SELECT COUNT(*) FROM copy")[0] == 1
        assert result.database.fetchone("SELECT COUNT(*) FROM member")[0] == 1
        assert result.database.fetchone("SELECT COUNT(*) FROM loan")[0] == 1
    finally:
        result.database.close()


@pytest.mark.skipif(SCHEMA_VERSION < 8, reason="v8 migration not installed yet")
def test_postflight_failure_atomically_restores_v7(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog import upgrade

    paths = _paths(tmp_path)
    _v7_catalog(paths)
    original_validate = upgrade._validate_file

    def fail_current(path: Path, *, expected_version: int | None = None):
        if expected_version == SCHEMA_VERSION:
            raise SchemaUpgradeError("fault injection: postflight")
        return original_validate(path, expected_version=expected_version)

    monkeypatch.setattr(upgrade, "_validate_file", fail_current)
    with pytest.raises(SchemaUpgradeError, match="geri döndürüldü"):
        open_database_safely(paths)

    with sqlite3.connect(f"file:{paths.database}?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 7
        assert connection.execute("SELECT COUNT(*) FROM edition").fetchone()[0] == 1
        assert connection.execute("SELECT COUNT(*) FROM loan").fetchone()[0] == 1
    backups = list((paths.root / "yedekler").glob("surum-yukseltme-oncesi-*.kitaparsiv"))
    assert len(backups) == 1
    assert stat.S_IMODE(backups[0].stat().st_mode) == 0o600


def test_new_catalog_is_private_and_does_not_create_upgrade_backup(tmp_path: Path) -> None:
    paths = _paths(tmp_path)
    previous_umask = os.umask(0o022)
    try:
        result = open_database_safely(paths)
    finally:
        os.umask(previous_umask)
    try:
        assert result.backup is None
        assert stat.S_IMODE(paths.database.stat().st_mode) == 0o600
        assert result.database.fetchone("PRAGMA user_version")[0] == SCHEMA_VERSION
    finally:
        result.database.close()


def test_existing_unversioned_foreign_sqlite_is_rejected_without_mutation(
    tmp_path: Path,
) -> None:
    paths = _paths(tmp_path)
    with sqlite3.connect(paths.database) as connection:
        connection.execute("CREATE TABLE foreign_records(value TEXT)")
        connection.execute("INSERT INTO foreign_records VALUES ('koru')")

    with pytest.raises(SchemaUpgradeError, match="otomatik dönüştürme reddedildi"):
        open_database_safely(paths)

    with sqlite3.connect(paths.database) as connection:
        assert connection.execute("SELECT value FROM foreign_records").fetchone()[0] == "koru"
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 0
    assert not (paths.root / "yedekler").exists()


def test_rollback_partial_copy_is_private_and_always_removed(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog import upgrade

    paths = _paths(tmp_path)
    _v7_catalog(paths)
    archive = create_archive(paths.database, tmp_path / "rollback.kitaparsiv").path
    observed_modes: list[int] = []

    def fail_after_partial_copy(source, target, *, length: int = 0) -> None:
        target.write(source.read(min(length or 32, 32)))
        target.flush()
        observed_modes.append(stat.S_IMODE(os.fstat(target.fileno()).st_mode))
        raise OSError(errno.ENOSPC, "fault injection: disk full")

    monkeypatch.setattr(upgrade.shutil, "copyfileobj", fail_after_partial_copy)
    previous_umask = os.umask(0o022)
    try:
        with pytest.raises(OSError, match="disk full"):
            _restore_database_from_archive(paths, archive)
    finally:
        os.umask(previous_umask)

    assert observed_modes == [0o600]
    assert list(paths.root.glob(".catalog.sqlite3.rollback-*")) == []
    with sqlite3.connect(f"file:{paths.database}?mode=ro", uri=True) as connection:
        assert connection.execute("PRAGMA user_version").fetchone()[0] == 7
