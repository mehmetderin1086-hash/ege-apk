"""`.kitaparsiv` yedeğinden geri yükleme: hazırlık → onay → açılışta değişim.

Tasarım (Codex çapraz değerlendirmesiyle sertleştirildi):

- Değişim, uygulama AÇILIŞINDA ve veritabanı açılmadan önce yapılır
  (`open_application` kancası) — web/CLI/Qt tüm giriş yolları görür.
- Eşzamanlılık, SQLite kilidiyle DEĞİL uygulama-geneli dosya kilidiyle
  çözülür: normal süreçler ömür boyu PAYLAŞIMLI kilit tutar, geri yükleme
  ÖZEL kilit ister. Kilit alınamazsa işaret BEKLEMEDE bırakılır (hata
  değildir); ilk tek-süreçli açılışta uygulanır.
- Staged veritabanı ONAY aşamasında güncel şemaya migrate edilir, kapak
  yolları çakışmasız ad alanına (`assets/geri-yukleme-<id>/`) yeniden
  yazılır ve içine benzersiz `restore_id` gömülür. Böylece migration
  başarısızlığı değişimden ÖNCE yakalanır ve idempotans denetimi WAL'a
  duyarlı dosya hash'i yerine veritabanı İÇİNDEN yapılır.
- Eski veritabanı önce SQLite Backup API ile kopyalanır (+ kapaklı
  `.kitaparsiv` güvenlik arşivi), sonra TEK atomik `os.replace` ile yeni
  dosya yerine konur — hiçbir çökme penceresinde "veritabanı yok" anı
  oluşmaz, eski veri her zaman en az bir kopyada yaşar.
"""

from __future__ import annotations

import errno
import hashlib
import json
import logging
import os
import re
import shutil
import sqlite3
import uuid
import zipfile
from contextlib import closing
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any

from kitapkatalog import __version__
from kitapkatalog.archive import (
    COVER_PATH_PROVENANCE_ALGORITHM,
    DATABASE_MEMBER,
    MANIFEST_MEMBER,
    MAX_ARCHIVE_MEMBERS,
    MAX_ARCHIVE_TOTAL_BYTES,
    ArchiveError,
    cover_path_fingerprint,
    extract_archive,
    inspect_archive,
)
from kitapkatalog.config import AppPaths
from kitapkatalog.database import (
    _APPLICATION_ID,
    SCHEMA_VERSION,
    StateConflictError,
    _unicode_nocase,
)

_LOG = logging.getLogger(__name__)

RESTORE_DIRNAME = "geri-yukleme"
MARKER_NAME = "bekleyen.json"
RESULT_NAME = "son-sonuc.json"
LOCK_NAME = "uygulama.lock"
RESTORE_ID_KEY = "restore_id"
_STAGING_PATTERN = re.compile(r"^hazirlik-[0-9a-f]{12}$")
_MAX_MEMBERS = MAX_ARCHIVE_MEMBERS
_MAX_TOTAL_BYTES = MAX_ARCHIVE_TOTAL_BYTES
# Yükleme ucu da aynı tavanı kullanır (diske yazmadan ÖNCE kesmek için).
MAX_UPLOAD_BYTES = _MAX_TOTAL_BYTES
_KEEP_PREVIOUS = 3
_RESTORE_FREE_RESERVE = 256 * 1024**2
_RESTORE_ARCHIVE_MIN_OVERHEAD = 16 * 1024**2
_COVER_COLUMNS = ("front_path", "front_inside_path", "back_inside_path", "back_path")


def _now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def _restore_dir(paths: AppPaths) -> Path:
    directory = paths.root / RESTORE_DIRNAME
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    return directory


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _existing_file_size(path: Path) -> int:
    try:
        return path.stat().st_size if path.is_file() else 0
    except OSError:
        return 0


def _live_database_size(db_path: Path) -> int:
    """Conservatively include committed pages and a not-yet-checkpointed WAL."""

    physical = _existing_file_size(db_path) + _existing_file_size(Path(f"{db_path}-wal"))
    logical = 0
    try:
        with closing(_connect_catalog(db_path, readonly=True)) as connection:
            page_count = int(connection.execute("PRAGMA page_count").fetchone()[0])
            page_size = int(connection.execute("PRAGMA page_size").fetchone()[0])
            logical = page_count * page_size
    except (OSError, sqlite3.Error, TypeError, ValueError):
        pass
    return max(physical, logical)


def _restore_apply_required_bytes(live_db: Path, covers: list[Path]) -> int:
    """Peak additional space for raw copy + snapshot + portable archive.

    ``create_archive`` temporarily holds a second SQLite snapshot while writing
    the final archive.  At peak, restore therefore needs three database-sized
    allocations (raw previous copy, archive snapshot and archive payload), plus
    one copy of every managed cover and a safety reserve.
    """

    database_bytes = _live_database_size(live_db)
    cover_bytes = sum(_existing_file_size(path) for path in covers)
    archive_input = database_bytes + cover_bytes
    archive_overhead = max(_RESTORE_ARCHIVE_MIN_OVERHEAD, archive_input // 20)
    return database_bytes * 3 + cover_bytes + archive_overhead + _RESTORE_FREE_RESERVE


def _storage_exhausted(error: BaseException) -> bool:
    """Recognise ENOSPC/EDQUOT even when ArchiveError wraps the OSError."""

    current: BaseException | None = error
    seen: set[int] = set()
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        if isinstance(current, OSError) and current.errno in {errno.ENOSPC, errno.EDQUOT}:
            return True
        current = current.__cause__ or current.__context__
    return False


def _cleanup_retryable_files(*paths: Path | None) -> None:
    for path in paths:
        if path is None:
            continue
        try:
            if path.is_file() and not path.is_symlink():
                path.unlink(missing_ok=True)
        except OSError:
            _LOG.warning("Yeniden denenebilir geri yükleme artığı temizlenemedi: %s", path)


def _fsync_file_and_dir(path: Path) -> None:
    with path.open("rb") as handle:
        os.fsync(handle.fileno())
    dir_fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(dir_fd)
    finally:
        os.close(dir_fd)


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    # Benzersiz geçici ad: eşzamanlı iki yazım birbirinin .tmp'sini ezmesin.
    temp = path.with_name(f".{path.name}.{uuid.uuid4().hex[:8]}.tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temp.chmod(0o600)
    os.replace(temp, path)
    path.chmod(0o600)
    _fsync_file_and_dir(path)


class AppLock:
    """Uygulama-geneli dosya kilidi.

    Normal süreçler `acquire_shared` ile ömür boyu paylaşımlı kilit tutar;
    geri yükleme `try_acquire_exclusive` ile özel kilit ister. `fcntl`
    olmayan platformlarda kilitsiz (no-op) çalışır ve geri yükleme yine
    açılışın en başında, veritabanı açılmadan koşturulduğu için pratik
    koruma korunur.
    """

    def __init__(self, paths: AppPaths) -> None:
        self.path = paths.root / LOCK_NAME
        self._fd: int | None = None

    def _open(self) -> int:
        if self._fd is None:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        return self._fd

    def acquire_shared(self) -> None:
        try:
            import fcntl
        except ImportError:  # pragma: no cover - yalnız POSIX dışı
            return
        fcntl.flock(self._open(), fcntl.LOCK_SH)

    def try_acquire_exclusive(self) -> bool:
        try:
            import fcntl
        except ImportError:  # pragma: no cover - yalnız POSIX dışı
            return True
        try:
            fcntl.flock(self._open(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return False
        return True

    def release(self) -> None:
        if self._fd is None:
            return
        try:
            import fcntl

            fcntl.flock(self._fd, fcntl.LOCK_UN)
        except (ImportError, OSError):  # pragma: no cover
            pass
        os.close(self._fd)
        self._fd = None


@dataclass(frozen=True, slots=True)
class RestoreSummary:
    staging_id: str
    archive_created_at: str
    cover_count: int
    schema_version: int
    counts: dict[str, int]
    school_name: str | None

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _staged_db_path(paths: AppPaths, staging_id: str) -> Path:
    if not _STAGING_PATTERN.match(staging_id):
        raise ValueError(f"Geçersiz hazırlık kimliği: {staging_id}")
    return _restore_dir(paths) / staging_id / DATABASE_MEMBER


def _table_exists(connection: sqlite3.Connection, name: str) -> bool:
    row = connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", (name,)
    ).fetchone()
    return row is not None


def _connect_catalog(
    db_path: Path, *, readonly: bool = False, isolation_level: str | None = ""
) -> sqlite3.Connection:
    """Database ile aynı özel collation'ları taşıyan ham SQLite bağlantısı."""

    dsn = f"file:{db_path}?mode=ro" if readonly else str(db_path)
    connection = sqlite3.connect(dsn, uri=readonly, isolation_level=isolation_level)
    connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
    return connection


def _validate_catalog(connection: sqlite3.Connection) -> int:
    version = int(connection.execute("PRAGMA user_version").fetchone()[0])
    if version > SCHEMA_VERSION:
        raise ArchiveError(
            f"Bu yedek daha yeni bir sürümle alınmış (şema v{version}); önce uygulamayı güncelleyin"
        )
    if version < 1:
        raise ArchiveError("Yedekte geçerli bir KitapKatalog şema sürümü yok")

    app_id = int(connection.execute("PRAGMA application_id").fetchone()[0])
    if app_id != _APPLICATION_ID:
        raise ArchiveError("Bu dosya bir KitapKatalog kataloğu değil")

    integrity = [str(row[0]) for row in connection.execute("PRAGMA integrity_check")]
    if integrity != ["ok"]:
        detail = "; ".join(integrity[:5]) or "bilinmeyen bütünlük hatası"
        raise ArchiveError(f"Yedekteki veritabanı bozuk: {detail}")

    foreign_key_errors = list(connection.execute("PRAGMA foreign_key_check").fetchmany(5))
    if foreign_key_errors:
        detail = "; ".join(f"{row[0]} satır {row[1]} -> {row[2]}" for row in foreign_key_errors)
        raise ArchiveError(f"Yedekte yabancı anahtar bütünlüğü bozuk: {detail}")

    if not _table_exists(connection, "schema_migration"):
        raise ArchiveError("Yedekte schema_migration tablosu yok")
    try:
        migrations = [
            int(row[0])
            for row in connection.execute("SELECT version FROM schema_migration ORDER BY version")
        ]
    except (TypeError, ValueError) as exc:
        raise ArchiveError("Yedekteki schema_migration kayıtları geçersiz") from exc
    expected = list(range(1, version + 1))
    if migrations != expected:
        raise ArchiveError(
            "Yedekte user_version ile schema_migration kayıtları tutarsız "
            f"(user_version={version}, migrations={migrations})"
        )
    return version


def _read_restore_id(db_path: Path) -> str | None:
    if not db_path.is_file():
        return None
    try:
        with closing(_connect_catalog(db_path, readonly=True)) as connection:
            if not _table_exists(connection, "app_setting"):
                return None
            row = connection.execute(
                "SELECT value FROM app_setting WHERE key = ?", (RESTORE_ID_KEY,)
            ).fetchone()
            return str(row[0]) if row else None
    except sqlite3.Error:
        return None


def collect_cover_paths(db_path: Path, asset_root: Path) -> list[Path]:
    """Veritabanındaki kapak yollarından asset kökü altında gerçekten var
    olanları döner (güvenlik arşivi ve web arşiv ucu ortak kullanır)."""

    values: list[str] = []
    try:
        with closing(_connect_catalog(db_path, readonly=True)) as connection:
            if _table_exists(connection, "edition"):
                for row in connection.execute(f"SELECT {', '.join(_COVER_COLUMNS)} FROM edition"):
                    values.extend(value for value in tuple(row) if value)
            # Yönetilen görseller de arşive girmeli (yalnız edition sütunları
            # değil): GUI/CLI image_asset.managed_path üzerinden okur.
            if _table_exists(connection, "image_asset"):
                for row in connection.execute(
                    "SELECT managed_path FROM image_asset WHERE managed_path IS NOT NULL"
                ):
                    if row[0]:
                        values.append(row[0])
    except sqlite3.Error:
        return []
    root = asset_root.resolve()
    covers: list[Path] = []
    for value in dict.fromkeys(values):
        path = Path(value)
        try:
            if path.is_file() and path.resolve().is_relative_to(root):
                covers.append(path)
        except OSError:  # pragma: no cover - erişilemeyen yol
            continue
    return covers


# ── 1. Hazırlık (yükleme sonrası doğrulama) ─────────────────────────


def _sweep_stale_staging(paths: AppPaths, *, keep_archive: Path | None = None) -> None:
    """Önceki deneme-yanılma turlarının hazirlik-*/yukleme-* kalıntılarını
    süpürür; bekleyen işaretin gösterdiği staging korunur."""

    restore_dir = _restore_dir(paths)
    protected = ""
    marker_path = restore_dir / MARKER_NAME
    if marker_path.is_file():
        try:
            protected = json.loads(marker_path.read_text(encoding="utf-8")).get("staging", "")
        except (OSError, json.JSONDecodeError):
            protected = ""
    for stale in restore_dir.glob("hazirlik-*"):
        if stale.name != protected:
            shutil.rmtree(stale, ignore_errors=True)
    for upload in restore_dir.glob("yukleme-*.kitaparsiv"):
        if keep_archive is None or upload != keep_archive:
            upload.unlink(missing_ok=True)


def stage_archive(archive_path: Path, paths: AppPaths) -> RestoreSummary:
    _sweep_stale_staging(paths, keep_archive=archive_path)

    # Ucuz zip-başlığı sınırları hash doğrulamasından ÖNCE (infolist
    # decompress etmez); tam hash turu inspect'te BİR kez koşar, extract
    # aynı doğrulamayı tekrarlamaz.
    with zipfile.ZipFile(archive_path) as archive:
        members = archive.infolist()
        if len(members) > _MAX_MEMBERS:
            raise ArchiveError(f"Arşivde çok fazla dosya var ({len(members)})")
        total = sum(member.file_size for member in members)
        if total > _MAX_TOTAL_BYTES:
            raise ArchiveError("Arşivin açılmış boyutu izin verilen sınırı aşıyor")
    info = inspect_archive(archive_path, verify_hashes=True)
    free = shutil.disk_usage(paths.root).free
    if free < total * 2 + info.database_size:
        raise ArchiveError("Geri yükleme için yeterli disk alanı yok")

    staging_id = f"hazirlik-{uuid.uuid4().hex[:12]}"
    destination = _restore_dir(paths) / staging_id
    try:
        db_path = extract_archive(archive_path, destination, verify_hashes=False)
        with closing(_connect_catalog(db_path, readonly=True)) as connection:
            version = _validate_catalog(connection)
            counts: dict[str, int] = {}
            for table in ("edition", "copy", "member", "loan"):
                counts[table] = (
                    int(connection.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0])
                    if _table_exists(connection, table)
                    else 0
                )
            school_name = None
            if _table_exists(connection, "app_setting"):
                row = connection.execute(
                    "SELECT value FROM app_setting WHERE key = 'school_name'"
                ).fetchone()
                school_name = str(row[0]) if row and row[0] else None
    except sqlite3.Error as exc:
        shutil.rmtree(destination, ignore_errors=True)
        raise ArchiveError(f"Yedekteki veritabanı okunamadı: {exc}") from exc
    except Exception:
        # Kısmi çıkarım dahil hiçbir dalda hazirlik-* kalıntısı bırakma.
        shutil.rmtree(destination, ignore_errors=True)
        raise

    return RestoreSummary(
        staging_id=staging_id,
        archive_created_at=info.created_at,
        cover_count=info.cover_count,
        schema_version=version,
        counts=counts,
        school_name=school_name,
    )


# ── 2. Onay (staged DB'yi değişime hazır hale getir + işaret bırak) ─


def _read_cover_path_provenance(
    manifest_path: Path, rels: list[PurePosixPath]
) -> tuple[str | None, dict[PurePosixPath, str]]:
    """Load optional v1+ salted source-path evidence from the staged manifest."""

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if not isinstance(manifest, dict):
            raise TypeError("manifest nesne değil")
        provenance = manifest.get("cover_path_provenance")
        if provenance is None:
            return None, {}
        if not isinstance(provenance, dict):
            raise TypeError("kapak yol kanıtı nesne değil")
        if provenance.get("algorithm") != COVER_PATH_PROVENANCE_ALGORITHM:
            raise ValueError("kapak yol kanıtı algoritması geçersiz")
        salt = provenance.get("salt")
        if not isinstance(salt, str) or len(salt) != 32:
            raise ValueError("kapak yol kanıtı tuzu geçersiz")
        bytes.fromhex(salt)
        raw_covers = manifest.get("covers")
        if not isinstance(raw_covers, list):
            raise TypeError("kapak listesi geçersiz")
        fingerprints: dict[PurePosixPath, str] = {}
        for item in raw_covers:
            if not isinstance(item, dict):
                raise TypeError("kapak kaydı geçersiz")
            member = item.get("member")
            fingerprint = item.get("source_path_fingerprint")
            if not isinstance(member, str) or not isinstance(fingerprint, str):
                raise TypeError("kapak yol kanıtı alanı geçersiz")
            member_path = PurePosixPath(member)
            if member_path.parts[:1] != ("covers",) or len(member_path.parts) < 2:
                raise ValueError("kapak üye yolu geçersiz")
            if len(fingerprint) != 64 or any(
                character not in "0123456789abcdef" for character in fingerprint.casefold()
            ):
                raise ValueError("kapak yol parmak izi geçersiz")
            relative = PurePosixPath(*member_path.parts[1:])
            if relative in fingerprints:
                raise ValueError("yinelenen kapak yol kanıtı")
            fingerprints[relative] = fingerprint.casefold()
        if set(fingerprints) != set(rels):
            raise ValueError("kapak yol kanıtı dosyalarla tutarsız")
    except (OSError, UnicodeError, json.JSONDecodeError, TypeError, ValueError) as exc:
        raise ArchiveError(f"Hazırlanan kapak yol kanıtı okunamadı: {exc}") from exc
    return salt, fingerprints


def _relocate_paths(
    connection: sqlite3.Connection,
    cover_root: Path,
    rels: list[PurePosixPath],
    *,
    provenance_salt: str | None,
    path_fingerprints: dict[PurePosixPath, str],
) -> dict[str, int]:
    """Arşiv kapaklarını yeni ad alanına yaz, eşleşmeyen yolları temizle.

    Yeni arşivlerde eşleme, manifestteki tuzlu kaynak-yol parmak iziyle;
    eski arşivlerde yalnız kanıtlanabilir ``assets/<göreli-yol>`` sonekiyle
    yapılır. Arşivde karşılığı olmayan veya belirsiz değerler NULL olur;
    restore edilmiş DB yerel makinedeki arşiv-dışı bir dosyayı taşımaz.
    """

    stats = {"rewritten": 0, "unmatched": 0, "cleared": 0}
    targets = [("edition", column) for column in _COVER_COLUMNS]
    if _table_exists(connection, "image_asset"):
        targets.append(("image_asset", "managed_path"))
    rel_parts = [rel.parts for rel in rels]
    for table, column in targets:
        rows = connection.execute(
            f"SELECT rowid, {column} FROM {table} WHERE {column} IS NOT NULL"
        ).fetchall()
        for rowid, value in rows:
            parts = PurePosixPath(Path(str(value)).as_posix()).parts
            stored_fingerprint = (
                cover_path_fingerprint(str(value), provenance_salt)
                if provenance_salt is not None
                else None
            )
            matches = [
                rel
                for rel, r_parts in zip(rels, rel_parts, strict=True)
                if r_parts
                and (
                    # New archives prove the exact historical DB path without
                    # exposing it in plaintext. This supports official custom
                    # --asset-root paths and rejects same-suffix external paths.
                    (
                        provenance_salt is not None
                        and path_fingerprints.get(rel) == stored_fingerprint
                    )
                    # Legacy v1 archives had no provenance. Keep only the
                    # defensible standard assets/<relative> compatibility path.
                    or (
                        provenance_salt is None
                        and len(parts) >= len(r_parts) + 1
                        and parts[-len(r_parts) :] == r_parts
                        and parts[-len(r_parts) - 1].casefold() == "assets"
                    )
                )
            ]
            if len(matches) == 1:
                new_value = str(cover_root.joinpath(*matches[0].parts))
                connection.execute(
                    f"UPDATE {table} SET {column} = ? WHERE rowid = ?",
                    (new_value, rowid),
                )
                stats["rewritten"] += 1
            else:
                connection.execute(f"UPDATE {table} SET {column} = NULL WHERE rowid = ?", (rowid,))
                stats["unmatched"] += 1
                stats["cleared"] += 1
    return stats


def confirm_restore(staging_id: str, paths: AppPaths) -> dict[str, Any]:
    restore_dir = _restore_dir(paths)
    marker_path = restore_dir / MARKER_NAME
    if marker_path.is_file():
        raise StateConflictError(
            "Zaten bekleyen bir geri yükleme var; önce onu uygulayın ya da vazgeçin"
        )
    db_path = _staged_db_path(paths, staging_id)
    if not db_path.is_file():
        raise KeyError("Hazırlık bulunamadı; yedeği yeniden yükleyin")

    restore_id = uuid.uuid4().hex[:16]
    cover_root = paths.assets / f"geri-yukleme-{restore_id}"
    covers_dir = db_path.parent.parent / "covers"
    rels: list[PurePosixPath] = []
    if covers_dir.is_dir():
        rels = [
            PurePosixPath(path.relative_to(covers_dir).as_posix())
            for path in sorted(covers_dir.rglob("*"))
            if path.is_file()
        ]
    provenance_salt, path_fingerprints = _read_cover_path_provenance(
        db_path.parent.parent / MANIFEST_MEMBER,
        rels,
    )

    # Migration onay anında koşar: başarısızlık değişimden ÖNCE yakalanır.
    from kitapkatalog.database import Database

    staged = Database(db_path)
    staged.close()

    # Migration tamamlandıktan sonra aynı bütünlük sözleşmesini güncel şema
    # üzerinde yeniden doğrula; eksik/geçersiz migration kaydı marker'a ulaşmaz.
    with closing(_connect_catalog(db_path, readonly=True)) as validation:
        migrated_version = _validate_catalog(validation)
    if migrated_version != SCHEMA_VERSION:
        raise ArchiveError(f"Hazırlanan katalog güncel şemaya taşınamadı (v{migrated_version})")

    connection = _connect_catalog(db_path)
    try:
        stats = _relocate_paths(
            connection,
            cover_root,
            rels,
            provenance_salt=provenance_salt,
            path_fingerprints=path_fingerprints,
        )
        connection.execute(
            "INSERT OR REPLACE INTO app_setting(key, value, updated_at) VALUES (?, ?, ?)",
            (RESTORE_ID_KEY, restore_id, _now()),
        )
        connection.commit()
    finally:
        connection.close()
    # WAL→DELETE geçişi başka bağlantı/ifade açıkken kilitlenir; taze bir
    # autocommit bağlantısında yapılır ([[sqlite-migration-ddl-autocommit]]).
    cleaner = _connect_catalog(db_path, isolation_level=None)
    try:
        row = cleaner.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if row and int(row[0]) != 0:
            raise ArchiveError(f"Hazırlık WAL checkpoint'i tamamlanamadı: {tuple(row)}")
        mode = cleaner.execute("PRAGMA journal_mode = DELETE").fetchone()
        if not mode or str(mode[0]).lower() != "delete":
            raise ArchiveError(f"Hazırlık journal_mode değiştirilemedi: {mode}")
    finally:
        cleaner.close()
    for suffix in ("-wal", "-shm"):
        Path(str(db_path) + suffix).unlink(missing_ok=True)

    marker = {
        "format": 1,
        "staging": staging_id,
        "restore_id": restore_id,
        "staged_sha256": _sha256(db_path),
        "confirmed_at": _now(),
        "app_version": __version__,
    }
    _atomic_write_json(marker_path, marker)
    return {"pending": True, "restore_id": restore_id, "relocation": stats}


def cancel_pending(paths: AppPaths) -> bool:
    restore_dir = _restore_dir(paths)
    marker_path = restore_dir / MARKER_NAME
    if not marker_path.is_file():
        return False
    try:
        staging = json.loads(marker_path.read_text(encoding="utf-8")).get("staging", "")
    except (OSError, json.JSONDecodeError):
        staging = ""
    marker_path.unlink(missing_ok=True)
    if staging and _STAGING_PATTERN.match(staging):
        shutil.rmtree(restore_dir / staging, ignore_errors=True)
    return True


def pending_info(paths: AppPaths) -> dict[str, Any]:
    restore_dir = _restore_dir(paths)
    info: dict[str, Any] = {"pending": None, "last_result": None}
    marker_path = restore_dir / MARKER_NAME
    if marker_path.is_file():
        try:
            info["pending"] = json.loads(marker_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            info["pending"] = {"error": "İşaret dosyası okunamadı"}
    result_path = restore_dir / RESULT_NAME
    if result_path.is_file():
        try:
            info["last_result"] = json.loads(result_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            info["last_result"] = None
    return info


# ── 3. Açılışta değişim (boot-swap) ─────────────────────────────────


def _fail_marker(restore_dir: Path, marker_path: Path, reason: str) -> dict[str, Any]:
    stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
    failed = restore_dir / f"basarisiz-{stamp}.json"
    try:
        os.replace(marker_path, failed)
    except OSError:
        marker_path.unlink(missing_ok=True)
    result = {"status": "failed", "reason": reason, "at": _now()}
    _atomic_write_json(restore_dir / RESULT_NAME, result)
    _LOG.error("Geri yükleme uygulanamadı: %s", reason)
    return result


def _checkpoint_and_copy(live_db: Path, target: Path) -> None:
    """Canlı DB'yi (WAL dahil) Backup API ile tutarlı biçimde kopyalar."""

    with closing(_connect_catalog(live_db)) as connection:
        row = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
        if row and int(row[0]) != 0:
            raise RuntimeError(f"WAL checkpoint tamamlanamadı: {tuple(row)}")
        with closing(_connect_catalog(target)) as backup:
            connection.backup(backup, pages=512)
    target.chmod(0o600)
    _fsync_file_and_dir(target)


def apply_pending_restore(paths: AppPaths, lock: AppLock) -> dict[str, Any] | None:
    """Bekleyen geri yüklemeyi uygular; `open_application` DB açılmadan çağırır.

    Hata durumları uygulamanın açılışını asla engellemez: kilit alınamazsa
    işaret beklemede bırakılır, diğer hatalarda işaret `basarisiz-*`'e taşınır
    ve mevcut veriyle normal açılış sürer.
    """

    restore_dir = paths.root / RESTORE_DIRNAME
    marker_path = restore_dir / MARKER_NAME
    if not marker_path.is_file():
        return None
    try:
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        staging_id = str(marker["staging"])
        restore_id = str(marker["restore_id"])
        staged_sha = str(marker["staged_sha256"])
        if not _STAGING_PATTERN.match(staging_id):
            raise ValueError(f"Geçersiz hazırlık kimliği: {staging_id}")
    except (OSError, json.JSONDecodeError, KeyError, ValueError) as exc:
        return _fail_marker(restore_dir, marker_path, f"İşaret dosyası geçersiz: {exc}")

    if not lock.try_acquire_exclusive():
        # Başka bir KitapKatalog süreci açık; hata DEĞİL — beklemede kalır.
        _LOG.warning("Geri yükleme ertelendi: başka bir uygulama süreci açık")
        return {"status": "deferred", "restore_id": restore_id}
    previous: Path | None = None
    backup_target: Path | None = None
    try:
        live_db = paths.database
        # İdempotans: değişim daha önce tamamlanıp temizlik yarıda kaldıysa.
        if _read_restore_id(live_db) == restore_id:
            marker_path.unlink(missing_ok=True)
            shutil.rmtree(restore_dir / staging_id, ignore_errors=True)
            result = {"status": "applied", "restore_id": restore_id, "at": _now()}
            _atomic_write_json(restore_dir / RESULT_NAME, result)
            return result

        staged_db = restore_dir / staging_id / DATABASE_MEMBER
        if not staged_db.is_file():
            return _fail_marker(restore_dir, marker_path, "Hazırlanan veritabanı kayıp")
        for suffix in ("-wal", "-shm"):
            if Path(str(staged_db) + suffix).exists():
                return _fail_marker(
                    restore_dir, marker_path, "Hazırlanan veritabanı temiz kapanmamış"
                )
        if _sha256(staged_db) != staged_sha:
            return _fail_marker(restore_dir, marker_path, "Hazırlanan veritabanı değişmiş")

        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        backup_archive = None
        if live_db.is_file():
            covers_for_budget = collect_cover_paths(live_db, paths.assets)
            required = _restore_apply_required_bytes(live_db, covers_for_budget)
            free = shutil.disk_usage(paths.root).free
            if free < required:
                reason = (
                    "Geri yükleme güvenlik kopyaları için yeterli boş alan yok "
                    f"(gerekli={required}, boş={free})"
                )
                _LOG.warning("Geri yükleme ertelendi: %s", reason)
                return {
                    "status": "deferred",
                    "restore_id": restore_id,
                    "reason": reason,
                    "required_bytes": required,
                    "free_bytes": free,
                }
            # (1) Ham kopya — Backup API, WAL dahil tutarlı.
            unique = restore_id
            previous = restore_dir / f"onceki-catalog-{stamp}-{unique}.sqlite3"
            _checkpoint_and_copy(live_db, previous)
            # (2) Kapaklı güvenlik arşivi (AutoBackup rotasyonu bu öneki silmez).
            from kitapkatalog.archive import create_archive

            backup_dir = paths.root / "yedekler"
            covers = collect_cover_paths(previous, paths.assets)
            backup_target = backup_dir / f"geri-yukleme-oncesi-{stamp}-{unique}.kitaparsiv"
            info = create_archive(
                previous,
                backup_target,
                asset_root=paths.assets,
                cover_paths=covers,
                include_covers=bool(covers),
            )
            backup_archive = str(info.path)

        # (3) Kapaklar çakışmasız ad alanına TEK dizin rename'iyle taşınır
        # (mevcut dosya ezilmez; copytree gibi kısmi-kopya bırakan yol YOK —
        # rename başarısızsa değişim swap'tan ÖNCE temiz iptal edilir).
        covers_src = restore_dir / staging_id / "covers"
        cover_root = paths.assets / f"geri-yukleme-{restore_id}"
        if covers_src.is_dir():
            if cover_root.exists():
                shutil.rmtree(covers_src, ignore_errors=True)
            else:
                paths.assets.mkdir(parents=True, exist_ok=True, mode=0o700)
                paths.assets.chmod(0o700)
                try:
                    os.replace(covers_src, cover_root)
                except OSError as exc:
                    return _fail_marker(restore_dir, marker_path, f"Kapaklar taşınamadı: {exc}")
                dir_fd = os.open(paths.assets, os.O_RDONLY)
                try:
                    os.fsync(dir_fd)
                finally:
                    os.close(dir_fd)

        # (4) Tek atomik değişim: hiçbir anda "veritabanı yok" penceresi oluşmaz.
        # Son checkpoint DENETLENİR: busy dönerse (AppLock'a uymayan bir
        # bağlantı) sidecar silinmez ve değişim iptal edilir — veri kaybı yok.
        if live_db.is_file():
            with closing(_connect_catalog(live_db)) as connection:
                row = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
                if row and int(row[0]) != 0:
                    return _fail_marker(
                        restore_dir,
                        marker_path,
                        f"Canlı veritabanı WAL checkpoint'i tamamlanamadı: {tuple(row)}",
                    )
        for suffix in ("-wal", "-shm"):
            Path(str(live_db) + suffix).unlink(missing_ok=True)
        os.replace(staged_db, live_db)

        # DEĞİŞİM TAMAMLANDI. Bundan sonraki her hata "başarısız" DEĞİLDİR:
        # veritabanı artık yeni katalogdur; temizlik en-iyi-çaba yapılır ve
        # işaret kalırsa sonraki açılış restore_id idempotansıyla uzlaşır.
        result = {
            "status": "applied",
            "restore_id": restore_id,
            "at": _now(),
            "backup_archive": backup_archive,
        }
        try:
            _fsync_file_and_dir(live_db)
            marker_path.unlink(missing_ok=True)
            shutil.rmtree(restore_dir / staging_id, ignore_errors=True)
            previous_files = sorted(restore_dir.glob("onceki-catalog-*.sqlite3"))
            for stale in previous_files[:-_KEEP_PREVIOUS]:
                stale.unlink(missing_ok=True)
            _atomic_write_json(restore_dir / RESULT_NAME, result)
        except Exception:
            _LOG.exception("Geri yükleme uygulandı ama temizlik tamamlanamadı")
        _LOG.info("Geri yükleme uygulandı (restore_id=%s)", restore_id)
        return result
    except Exception as exc:
        if _storage_exhausted(exc):
            # The live database has not been replaced on any path that reaches
            # this handler. Keep the marker/staging intact so the next launch
            # can retry, and release every allocation made by this attempt.
            previous_sidecars = (
                tuple(Path(f"{previous}{suffix}") for suffix in ("-wal", "-shm", "-journal"))
                if previous is not None
                else ()
            )
            _cleanup_retryable_files(previous, *previous_sidecars, backup_target)
            reason = f"Disk alanı yetersiz; geri yükleme yeniden denenecek: {exc}"
            _LOG.warning(reason)
            return {
                "status": "deferred",
                "restore_id": restore_id,
                "reason": reason,
            }
        return _fail_marker(restore_dir, marker_path, f"{type(exc).__name__}: {exc}")
    finally:
        lock.release()
