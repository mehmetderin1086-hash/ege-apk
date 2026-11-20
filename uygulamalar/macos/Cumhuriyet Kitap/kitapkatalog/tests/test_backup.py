"""Otomatik yedekleme: günlük tekillik, rotasyon, hedef klasör."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.archive import inspect_archive
from kitapkatalog.backup import AutoBackup
from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 9, 1, 8, 0, tzinfo=UTC)


@pytest.fixture()
def backup(tmp_path: Path) -> AutoBackup:
    database = Database(tmp_path / "catalog.sqlite3")
    Catalog(database).save_book(BookInput(title="Yedeklenecek Kitap"))
    return AutoBackup(database, AppSettings(database), tmp_path)


def test_run_if_due_once_per_day(backup: AutoBackup) -> None:
    first = backup.run_if_due(now=NOW)
    assert first is not None and first.is_file()
    assert first.suffix == ".kitaparsiv"
    # Aynı gün ikinci çağrı yedek almaz.
    assert backup.run_if_due(now=NOW + timedelta(hours=5)) is None
    # Ertesi gün yeniden alır.
    second = backup.run_if_due(now=NOW + timedelta(days=1))
    assert second is not None and second != first


def test_rotation_keeps_last_n(backup: AutoBackup) -> None:
    backup.settings.set("backup_keep", "3")
    for day in range(5):
        backup.run(now=NOW + timedelta(days=day))
    remaining = sorted(backup.backup_dir().glob("kitapkatalog-otoyedek-*.kitaparsiv"))
    assert len(remaining) == 3
    assert remaining[0].name.startswith("kitapkatalog-otoyedek-20260903")


def test_custom_backup_dir(backup: AutoBackup, tmp_path: Path) -> None:
    custom = tmp_path / "ozel-yedekler"
    backup.settings.set("backup_dir", str(custom))
    target = backup.run(now=NOW)
    assert target.parent == custom


def test_daily_backup_includes_managed_covers(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    book = catalog.save_book(BookInput(title="Kapaklı Yedek"))
    cover = tmp_path / "assets" / "web_covers" / "front.jpg"
    cover.parent.mkdir(parents=True)
    cover.write_bytes(b"managed-cover")
    catalog.set_cover_paths(book.edition_id, front_path=cover)
    backup = AutoBackup(database, AppSettings(database), tmp_path)

    target = backup.run(now=NOW)
    info = inspect_archive(target)

    assert info.covers_included is True
    assert info.cover_count == 1


def test_auto_backup_removes_only_its_stale_atomic_parts(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    backup = AutoBackup(database, AppSettings(database), tmp_path)
    directory = backup.backup_dir()
    directory.mkdir(parents=True)
    stale = directory / ".kitapkatalog-otoyedek-20260808-120000.kitaparsiv.123.part"
    unrelated = directory / ".baska-yedek.part"
    stale.write_bytes(b"partial")
    unrelated.write_bytes(b"koru")

    backup.run(now=NOW)

    assert not stale.exists()
    assert unrelated.read_bytes() == b"koru"
