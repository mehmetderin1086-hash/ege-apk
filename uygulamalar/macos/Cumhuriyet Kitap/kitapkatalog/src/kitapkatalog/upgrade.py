"""Fail-closed catalogue schema upgrades with a verified rollback archive.

``Database`` migrations are individually atomic, but opening a newer release
used to run them before the daily backup scheduler had a chance to execute.
This module closes that operational gap: an existing older catalogue is
validated and archived (including managed covers), the migration is run, and
the resulting catalogue is validated again before it is returned to the
application.  Any failure restores the pre-upgrade SQLite snapshot atomically.
"""

from __future__ import annotations

import logging
import os
import shutil
import sqlite3
import stat

from kitapkatalog import portable
import tempfile
import uuid
from contextlib import closing, suppress
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from kitapkatalog.archive import ArchiveInfo, create_archive, extract_archive
from kitapkatalog.config import AppPaths
from kitapkatalog.database import _APPLICATION_ID, SCHEMA_VERSION, Database, DatabaseError
from kitapkatalog.restore import (
    _connect_catalog,
    _table_exists,
    _validate_catalog,
    collect_cover_paths,
)

_LOG = logging.getLogger(__name__)
_STABLE_TABLES = ("work", "edition", "copy", "member", "loan", "import_job")


class SchemaUpgradeError(DatabaseError):
    """The preflight, migration, postflight, or rollback could not complete."""


@dataclass(frozen=True, slots=True)
class UpgradeResult:
    database: Database
    from_version: int
    to_version: int
    backup: Path | None


def existing_schema_version(path: Path) -> int | None:
    """Return an existing database's user_version without creating a file."""

    path = Path(path)
    if not path.is_file():
        return None
    metadata = path.lstat()
    if not portable.kullanici_sahibi_mi(metadata):
        raise SchemaUpgradeError(
            f"Katalog güvenli, kullanıcıya ait normal bir dosya değil: {path}"
        )
    try:
        with sqlite3.connect(f"file:{path}?mode=ro", uri=True) as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version == 0:
                objects = int(
                    connection.execute(
                        "SELECT COUNT(*) FROM sqlite_master "
                        "WHERE name NOT LIKE 'sqlite_%'"
                    ).fetchone()[0]
                )
                application_id = int(
                    connection.execute("PRAGMA application_id").fetchone()[0]
                )
                if objects or application_id not in {0, _APPLICATION_ID}:
                    raise SchemaUpgradeError(
                        "Şema sürümü olmayan mevcut SQLite dosyası boş bir "
                        "KitapKatalog kataloğu değil; otomatik dönüştürme reddedildi"
                    )
            return version
    except sqlite3.Error as exc:
        raise SchemaUpgradeError(f"Katalog şema sürümü okunamadı: {exc}") from exc


def schema_upgrade_needed(path: Path) -> bool:
    version = existing_schema_version(path)
    return version is not None and 0 < version < SCHEMA_VERSION


def _stable_counts(connection: sqlite3.Connection) -> dict[str, int]:
    counts: dict[str, int] = {}
    for table in _STABLE_TABLES:
        if _table_exists(connection, table):
            counts[table] = int(
                connection.execute(f'SELECT COUNT(*) FROM "{table}"').fetchone()[0]
            )
    return counts


def _validate_file(path: Path, *, expected_version: int | None = None) -> tuple[int, dict[str, int]]:
    try:
        with closing(_connect_catalog(path, readonly=True)) as connection:
            version = _validate_catalog(connection)
            counts = _stable_counts(connection)
    except Exception as exc:
        if isinstance(exc, SchemaUpgradeError):
            raise
        raise SchemaUpgradeError(str(exc)) from exc
    if expected_version is not None and version != expected_version:
        raise SchemaUpgradeError(
            f"Yükseltme sonrası şema beklenen sürümde değil: {version} != {expected_version}"
        )
    return version, counts


def _upgrade_backup(paths: AppPaths, from_version: int) -> ArchiveInfo:
    directory = paths.root / "yedekler"
    directory.mkdir(parents=True, exist_ok=True)
    os.chmod(directory, 0o700)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S-%fZ")
    target = directory / (
        f"surum-yukseltme-oncesi-v{from_version}-v{SCHEMA_VERSION}-{stamp}.kitaparsiv"
    )
    covers = collect_cover_paths(paths.database, paths.assets)
    info = create_archive(
        paths.database,
        target,
        asset_root=paths.assets,
        cover_paths=covers,
        include_covers=bool(covers),
    )
    os.chmod(info.path, 0o600)
    return info


def _fsync_file_and_directory(path: Path) -> None:
    with path.open("rb") as handle:
        os.fsync(handle.fileno())
    descriptor = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def _restore_database_from_archive(paths: AppPaths, archive: Path) -> None:
    """Atomically put the archived SQLite snapshot back in place."""

    paths.root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".schema-rollback-", dir=paths.root) as temp:
        extracted = Path(temp) / "archive"
        extract_archive(archive, extracted, verify_hashes=True)
        snapshot = extracted / "catalog" / "catalog.sqlite3"
        replacement = paths.root / f".catalog.sqlite3.rollback-{uuid.uuid4().hex}"
        descriptor = -1
        published = False
        try:
            # Privacy must hold while bytes are being copied, not only after
            # success. O_EXCL also prevents a pre-planted link/path collision.
            descriptor = os.open(
                replacement,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                0o600,
            )
            target = os.fdopen(descriptor, "wb")
            descriptor = -1  # target now owns the descriptor
            with snapshot.open("rb") as source, target:
                shutil.copyfileobj(source, target, length=4 * 1024 * 1024)
                target.flush()
                os.fsync(target.fileno())
            _fsync_file_and_directory(replacement)
            for suffix in ("-wal", "-shm"):
                Path(str(paths.database) + suffix).unlink(missing_ok=True)
            os.replace(replacement, paths.database)
            published = True
            os.chmod(paths.database, 0o600)
            _fsync_file_and_directory(paths.database)
        finally:
            if descriptor >= 0:
                os.close(descriptor)
            if not published:
                replacement.unlink(missing_ok=True)


def open_database_safely(paths: AppPaths) -> UpgradeResult:
    """Open/migrate the catalogue, requiring a verified backup for upgrades.

    The caller must hold the application-wide *exclusive* lock whenever an
    older existing schema is present.  New/current databases use the ordinary
    ``Database`` path and return ``backup=None``.
    """

    version = existing_schema_version(paths.database)
    if version is None or version == 0 or version == SCHEMA_VERSION:
        database = Database(paths.database)
        with suppress(FileNotFoundError):  # SQLite creates it before returning.
            os.chmod(paths.database, 0o600)
        return UpgradeResult(database, version or 0, SCHEMA_VERSION, None)
    if version > SCHEMA_VERSION:
        raise SchemaUpgradeError(
            f"Veritabanı sürümü {version}; uygulamanın desteklediği en yeni sürüm "
            f"{SCHEMA_VERSION}"
        )

    before_version, before_counts = _validate_file(paths.database, expected_version=version)
    info = _upgrade_backup(paths, before_version)
    database: Database | None = None
    try:
        database = Database(paths.database)
        database.close()
        database = None
        after_version, after_counts = _validate_file(
            paths.database, expected_version=SCHEMA_VERSION
        )
        if after_counts != before_counts:
            raise SchemaUpgradeError(
                "Şema yükseltmesi temel kayıt sayılarını değiştirdi "
                f"(önce={before_counts}, sonra={after_counts})"
            )
        database = Database(paths.database)
        os.chmod(paths.database, 0o600)
        _LOG.info(
            "Katalog şeması v%s -> v%s yükseltildi; doğrulanmış yedek: %s",
            before_version,
            after_version,
            info.path,
        )
        return UpgradeResult(database, before_version, after_version, info.path)
    except BaseException as migration_error:
        if database is not None:
            database.close()
        try:
            _restore_database_from_archive(paths, info.path)
            restored_version, restored_counts = _validate_file(
                paths.database, expected_version=before_version
            )
            if restored_counts != before_counts:
                raise SchemaUpgradeError(
                    "Geri dönüş kayıt sayıları yükseltme öncesiyle uyuşmuyor"
                )
            _LOG.error(
                "Şema yükseltmesi geri alındı; katalog yeniden v%s", restored_version
            )
        except BaseException as rollback_error:
            raise SchemaUpgradeError(
                "Şema yükseltmesi başarısız oldu ve otomatik geri dönüş de "
                f"tamamlanamadı. Güvenli arşiv: {info.path}. "
                f"Yükseltme hatası: {migration_error}; geri dönüş hatası: {rollback_error}"
            ) from rollback_error
        raise SchemaUpgradeError(
            "Şema yükseltmesi başarısız oldu; canlı katalog doğrulanmış "
            f"v{before_version} yedeğine geri döndürüldü. Yedek: {info.path}. "
            f"Hata: {migration_error}"
        ) from migration_error
