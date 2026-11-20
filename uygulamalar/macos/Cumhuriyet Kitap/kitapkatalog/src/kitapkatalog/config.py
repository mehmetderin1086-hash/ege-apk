from __future__ import annotations

import os
import stat

from kitapkatalog import portable
from dataclasses import dataclass
from pathlib import Path

from platformdirs import user_data_path


@dataclass(frozen=True, slots=True)
class AppPaths:
    root: Path
    database: Path
    assets: Path
    derivatives: Path
    ocr_raw: Path
    models: Path
    exports: Path
    logs: Path
    # ``False`` is used for an explicit database path whose parent may be a
    # shared/user-owned directory such as /tmp or Documents.  KitapKatalog may
    # create private children there, but must never chmod pre-existing dirs.
    owns_data_root: bool = True

    @property
    def voice_assets(self) -> Path:
        return self.assets / "voice"

    @property
    def transcripts(self) -> Path:
        return self.root / "transcripts"

    @classmethod
    def default(cls) -> AppPaths:
        override = os.environ.get("KITAPKATALOG_DATA_DIR")
        root = (
            Path(override).expanduser()
            if override
            else user_data_path("KitapKatalog", "MehmetDerin", ensure_exists=False)
        )
        model_override = os.environ.get("KITAPKATALOG_MODEL_DIR")
        models = Path(model_override).expanduser() if model_override else root / "models"
        return cls(
            root=root,
            database=root / "catalog.sqlite3",
            assets=root / "assets",
            derivatives=root / "derivatives",
            ocr_raw=root / "ocr-raw",
            models=models,
            exports=root / "exports",
            logs=root / "logs",
        )

    def ensure(self) -> None:
        directories = (
            self.root,
            self.assets,
            self.derivatives,
            self.ocr_raw,
            self.models,
            self.exports,
            self.logs,
            self.voice_assets,
            self.transcripts,
        )
        root = self.root.resolve()
        for directory in directories:
            existed = directory.exists()
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            # An externally configured model bundle may intentionally be shared.
            # Harden only the application data tree; never chmod a directory
            # outside it merely because KITAPKATALOG_MODEL_DIR points there.
            resolved = directory.resolve()
            if (resolved == root or resolved.is_relative_to(root)) and (
                self.owns_data_root or not existed
            ):
                directory.chmod(0o700)

        # Older releases could create the catalogue and its WAL sidecars under
        # a permissive shell/Finder umask.  The private 0700 root already blocks
        # traversal, but repairing regular existing database files as well keeps
        # copied/moved data roots private.  Do not follow user-created symlinks.
        for candidate in (
            self.database,
            Path(f"{self.database}-wal"),
            Path(f"{self.database}-shm"),
        ):
            try:
                metadata = candidate.lstat()
            except FileNotFoundError:
                continue
            if stat.S_ISREG(metadata.st_mode):
                portable.sikilastir_0600(candidate)


@dataclass(frozen=True, slots=True)
class RuntimeLimits:
    chunk_books: int = 250
    microbatch_pairs: int = 8
    book_workers: int = 2
    soft_rss_bytes: int = 10 * 1024**3
    hard_rss_bytes: int = 12 * 1024**3
    lease_seconds: int = 300
    max_retries: int = 2
