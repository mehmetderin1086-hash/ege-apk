from __future__ import annotations

import hashlib
import json
import os
import shutil
import sqlite3
import stat
import tempfile
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from sqlalchemy.engine import make_url

from bioprof.config import Settings


class BackupError(RuntimeError):
    pass


_MAX_ARCHIVE_MEMBERS = 100_000
_MAX_MEMBER_SIZE = 2 * 1024 * 1024 * 1024
_MAX_TOTAL_SIZE = 20 * 1024 * 1024 * 1024
_MAX_COMPRESSION_RATIO = 500


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


class BackupService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def _database_path(self) -> Path:
        url = make_url(self.settings.db_url)
        if url.get_backend_name() != "sqlite":
            raise BackupError("Yalnız SQLite veritabanları yedeklenebilir.")
        database = url.database
        if not database or database == ":memory:" or database.startswith("file:"):
            raise BackupError("Yedekleme için dosya tabanlı bir SQLite veritabanı gerekli.")
        path = Path(database).expanduser()
        return path if path.is_absolute() else Path.cwd() / path

    def _remove_unbundled_sources(self, database: sqlite3.Connection) -> int:
        tables = {
            str(row[0])
            for row in database.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        if "sources" not in tables:
            return 0

        object_root = self.settings.objects_dir.resolve()
        excluded: list[str] = []
        for source_id, status_value, object_path_value in database.execute(
            "SELECT id, status, object_path FROM sources"
        ):
            status_name = str(status_value).casefold()
            object_path = Path(str(object_path_value)).expanduser()
            try:
                bundled = (
                    object_path.resolve().is_relative_to(object_root)
                    and object_path.is_file()
                    and not object_path.is_symlink()
                )
            except OSError:
                bundled = False
            if status_name in {"quarantined", "needs_review"} or not bundled:
                excluded.append(str(source_id))

        if not excluded:
            return 0
        if "chunks" in tables:
            database.executemany("DELETE FROM chunks WHERE source_id = ?", ((x,) for x in excluded))
        if "chunk_fts" in tables:
            database.executemany(
                "DELETE FROM chunk_fts WHERE source_id = ?", ((x,) for x in excluded)
            )
        database.executemany("DELETE FROM sources WHERE id = ?", ((x,) for x in excluded))
        database.commit()
        # SQLite leaves deleted content in free pages. Compact the private snapshot
        # so quarantined text and metadata are not recoverable from the backup file.
        database.execute("VACUUM")
        return len(excluded)

    def create(self, destination: Path) -> Path:
        destination = destination.expanduser().resolve()
        destination.parent.mkdir(parents=True, exist_ok=True)
        db_path = self._database_path()
        if db_path.is_symlink():
            raise BackupError("Veritabanı sembolik bağlantı üzerinden yedeklenemez.")
        with tempfile.TemporaryDirectory(prefix="bioprof-backup-") as temp_name:
            temp = Path(temp_name)
            files: list[dict[str, Any]] = []
            excluded_sources = 0

            if db_path.exists():
                snapshot = temp / "bioprof.sqlite3"
                source = sqlite3.connect(db_path)
                target = sqlite3.connect(snapshot)
                try:
                    source.backup(target)
                    excluded_sources = self._remove_unbundled_sources(target)
                finally:
                    target.close()
                    source.close()
                files.append({"path": "bioprof.sqlite3", "sha256": _sha256(snapshot)})

            for directory_name in ("objects", "artifacts"):
                source_dir = self.settings.data_dir / directory_name
                if not source_dir.exists():
                    continue
                if source_dir.is_symlink():
                    raise BackupError("Yedek kaynağında sembolik bağlantı reddedildi.")
                source_root = source_dir.resolve()
                for source_path in source_dir.rglob("*"):
                    if source_path.is_symlink():
                        raise BackupError("Yedek kaynağında sembolik bağlantı reddedildi.")
                    if not source_path.is_file():
                        continue
                    if not source_path.resolve().is_relative_to(source_root):
                        raise BackupError("Yedek kaynağı izin verilen dizinin dışına çıkıyor.")
                    relative = source_path.relative_to(self.settings.data_dir)
                    target_path = temp / relative
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source_path, target_path)
                    files.append({"path": relative.as_posix(), "sha256": _sha256(target_path)})

            manifest = {
                "format": "bioprof-backup-v1",
                "created_at": datetime.now(UTC).isoformat(),
                "excluded_unbundled_sources": excluded_sources,
                "files": sorted(files, key=lambda item: item["path"]),
            }
            (temp / "manifest.json").write_text(
                json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
            )

            temporary_archive = destination.with_suffix(destination.suffix + ".partial")
            temporary_archive.unlink(missing_ok=True)
            try:
                with zipfile.ZipFile(temporary_archive, "w", zipfile.ZIP_DEFLATED) as archive:
                    for item in temp.rglob("*"):
                        if item.is_file():
                            archive.write(item, item.relative_to(temp).as_posix())
                os.replace(temporary_archive, destination)
                destination.chmod(0o600)
            finally:
                temporary_archive.unlink(missing_ok=True)
        return destination

    def verify(self, archive_path: Path) -> dict[str, Any]:
        archive_path = archive_path.expanduser().resolve()
        if not zipfile.is_zipfile(archive_path):
            raise BackupError("Geçerli bir BioProf ZIP yedeği değil.")
        with tempfile.TemporaryDirectory(prefix="bioprof-verify-") as temp_name:
            temp = Path(temp_name)
            with zipfile.ZipFile(archive_path) as archive:
                self._safe_extract(archive, temp)
            manifest_path = temp / "manifest.json"
            if not manifest_path.exists():
                raise BackupError("Yedek manifesti eksik.")
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            if manifest.get("format") != "bioprof-backup-v1":
                raise BackupError("Desteklenmeyen yedek biçimi.")
            entries = manifest.get("files")
            if not isinstance(entries, list):
                raise BackupError("Yedek dosya listesi geçersiz.")
            expected: set[str] = {"manifest.json"}
            for entry in entries:
                if not isinstance(entry, dict):
                    raise BackupError("Yedek manifest girdisi geçersiz.")
                relative = str(entry.get("path", ""))
                checksum = entry.get("sha256")
                if (
                    not relative
                    or relative in expected
                    or not isinstance(checksum, str)
                    or len(checksum) != 64
                ):
                    raise BackupError("Yedek manifest girdisi güvenli değil.")
                expected.add(relative)
                path = temp / relative
                if not path.is_file() or _sha256(path) != checksum:
                    raise BackupError(f"Yedek dosyası doğrulanamadı: {relative}")
            actual = {
                path.relative_to(temp).as_posix() for path in temp.rglob("*") if path.is_file()
            }
            if actual != expected:
                raise BackupError("Yedek manifest dışında dosya içeriyor veya dosya eksik.")
            return manifest

    def restore(self, archive_path: Path, target_dir: Path) -> Path:
        """Restore into an empty explicit directory; never overwrites live application data."""
        manifest = self.verify(archive_path)
        target_dir = target_dir.expanduser().resolve()
        if target_dir == Path.home().resolve() or target_dir == Path("/"):
            raise BackupError("Geniş sistem dizinine geri yükleme reddedildi.")
        if target_dir.exists() and any(target_dir.iterdir()):
            raise BackupError("Geri yükleme hedefi boş olmalıdır.")
        target_dir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(archive_path) as archive:
            allowed = {"manifest.json", *(str(item["path"]) for item in manifest["files"])}
            self._safe_extract(archive, target_dir, allowed=allowed)
        (target_dir / "manifest.json").unlink(missing_ok=True)
        return target_dir

    @staticmethod
    def _safe_extract(
        archive: zipfile.ZipFile,
        target: Path,
        *,
        allowed: set[str] | None = None,
    ) -> None:
        target_resolved = target.resolve()
        members = archive.infolist()
        if len(members) > _MAX_ARCHIVE_MEMBERS:
            raise BackupError("Yedek çok fazla dosya içeriyor.")
        total_size = 0
        names: set[str] = set()
        for member in members:
            if member.filename in names:
                raise BackupError("Yedekte yinelenen dosya yolu bulundu.")
            names.add(member.filename)
            if "\\" in member.filename or member.flag_bits & 0x1:
                raise BackupError("Yedekte güvenli olmayan dosya bulundu.")
            member_path = (target / member.filename).resolve()
            if not member_path.is_relative_to(target_resolved):
                raise BackupError("Yedekte güvenli olmayan dosya yolu bulundu.")
            unix_mode = (member.external_attr >> 16) & 0xFFFF
            if unix_mode and stat.S_ISLNK(unix_mode):
                raise BackupError("Yedekte sembolik bağlantı reddedildi.")
            if member.file_size > _MAX_MEMBER_SIZE:
                raise BackupError("Yedekte izin verilenden büyük dosya bulundu.")
            total_size += member.file_size
            if total_size > _MAX_TOTAL_SIZE:
                raise BackupError("Yedeğin açılmış toplam boyutu sınırı aşıyor.")
            if (
                member.file_size > 10 * 1024 * 1024
                and member.file_size > max(1, member.compress_size) * _MAX_COMPRESSION_RATIO
            ):
                raise BackupError("Şüpheli sıkıştırma oranına sahip yedek reddedildi.")
            if allowed is not None and not member.is_dir() and member.filename not in allowed:
                raise BackupError("Yedek manifest dışında dosya içeriyor.")
        for member in members:
            destination = (target / member.filename).resolve()
            if member.is_dir():
                destination.mkdir(parents=True, exist_ok=True, mode=0o700)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            try:
                with archive.open(member) as source, destination.open("xb") as output:
                    shutil.copyfileobj(source, output, length=1024 * 1024)
                os.chmod(destination, 0o600)
            except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
                raise BackupError("Yedek dosyası güvenle açılamadı.") from exc
