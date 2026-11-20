"""Otomatik yedekleme: günde bir kez .kitaparsiv, son N dosya saklanır."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

from kitapkatalog.database import Database
from kitapkatalog.settings import AppSettings

_PREFIX = "kitapkatalog-otoyedek-"


class AutoBackup:
    def __init__(self, database: Database, settings: AppSettings, data_root: Path) -> None:
        self.db = database
        self.settings = settings
        self.data_root = Path(data_root)

    def backup_dir(self) -> Path:
        configured = (self.settings.backup_dir or "").strip()
        return Path(configured).expanduser() if configured else self.data_root / "yedekler"

    def run_if_due(self, *, now: datetime | None = None) -> Path | None:
        """Bugün yedek alınmadıysa alır; alınmışsa None döner."""

        now = now or datetime.now(UTC)
        last = self.settings.last_backup_at
        if last and last[:10] == now.date().isoformat():
            return None
        return self.run(now=now)

    def run(self, *, now: datetime | None = None) -> Path:
        from kitapkatalog.archive import create_archive
        from kitapkatalog.restore import collect_cover_paths

        now = now or datetime.now(UTC)
        directory = self.backup_dir()
        directory.mkdir(parents=True, exist_ok=True)
        self._cleanup_stale_parts(directory)
        target = directory / f"{_PREFIX}{now.strftime('%Y%m%d-%H%M%S')}.kitaparsiv"
        asset_root = self.data_root / "assets"
        covers = collect_cover_paths(self.db.path, asset_root)
        create_archive(
            self.db.path,
            target,
            asset_root=asset_root,
            cover_paths=covers,
            include_covers=bool(covers),
        )
        self.settings.set("last_backup_at", now.isoformat(timespec="seconds"))
        self._rotate(directory)
        return target

    @staticmethod
    def _cleanup_stale_parts(directory: Path) -> list[Path]:
        """Remove only interrupted auto-backup parts from an earlier process."""

        removed: list[Path] = []
        for path in directory.glob(f".{_PREFIX}*.kitaparsiv.*.part"):
            if path.is_file() and not path.is_symlink():
                path.unlink(missing_ok=True)
                removed.append(path)
        return removed

    def _rotate(self, directory: Path) -> list[Path]:
        keep = max(1, self.settings.backup_keep)
        backups = sorted(
            (
                path
                for path in directory.glob(f"{_PREFIX}*.kitaparsiv")
                if path.is_file()
            ),
            key=lambda path: path.name,
        )
        removed: list[Path] = []
        for path in backups[:-keep] if len(backups) > keep else []:
            path.unlink(missing_ok=True)
            removed.append(path)
        return removed
