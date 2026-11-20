"""Portable, atomic ``.kitaparsiv`` backup creation and inspection.

The archive format is intentionally simple: a ZIP container holding a
transactionally consistent SQLite snapshot, a versioned manifest and,
optionally, managed cover assets.  Restoring is kept separate from opening an
archive so merely inspecting an unknown file never mutates the catalogue.
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import tempfile
import unicodedata
import uuid
import zipfile
from collections.abc import Iterable
from dataclasses import dataclass, replace
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath

ARCHIVE_FORMAT_VERSION = 1
DATABASE_MEMBER = "catalog/catalog.sqlite3"
MANIFEST_MEMBER = "manifest.json"
MAX_ARCHIVE_MEMBERS = 20_000
MAX_ARCHIVE_TOTAL_BYTES = 8 * 1024**3
MAX_MANIFEST_BYTES = 16 * 1024**2
COVER_PATH_PROVENANCE_ALGORITHM = "sha256-salted-nfc-posix-v1"


class ArchiveError(RuntimeError):
    """Raised for an incomplete, corrupt or unsafe KitapKatalog archive."""


@dataclass(frozen=True, slots=True)
class ArchiveInfo:
    path: Path
    format_version: int
    created_at: str
    database_sha256: str
    database_size: int
    cover_count: int
    covers_included: bool


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _sqlite_snapshot(source: Path, destination: Path) -> None:
    """Use SQLite's backup API so WAL transactions are included consistently."""

    if not source.is_file():
        raise ArchiveError(f"Katalog veritabanı bulunamadı: {source}")
    try:
        with (
            sqlite3.connect(f"file:{source}?mode=ro", uri=True) as source_db,
            sqlite3.connect(destination) as destination_db,
        ):
            source_db.backup(destination_db, pages=512)
    except sqlite3.Error as exc:
        raise ArchiveError(f"SQLite anlık görüntüsü alınamadı: {exc}") from exc


def _cover_member(asset_root: Path, cover: Path) -> str:
    try:
        relative = cover.resolve().relative_to(asset_root.resolve())
    except ValueError as exc:
        raise ArchiveError(f"Yönetilen kapak, varlık kökünün dışında olamaz: {cover}") from exc
    if any(part in {"", ".", ".."} for part in relative.parts):
        raise ArchiveError(f"Güvensiz kapak yolu: {cover}")
    return PurePosixPath("covers", *relative.parts).as_posix()


def cover_path_fingerprint(path: str | Path, salt: str) -> str:
    """Hash a stored cover path without publishing the absolute path itself."""

    salt_bytes = bytes.fromhex(salt)
    normalized = unicodedata.normalize("NFC", Path(path).as_posix()).encode("utf-8")
    return hashlib.sha256(salt_bytes + b"\0" + normalized).hexdigest()


def create_archive(
    database: Path,
    target: Path,
    *,
    asset_root: Path | None = None,
    cover_paths: Iterable[Path] = (),
    include_covers: bool = False,
) -> ArchiveInfo:
    """Create an archive through a same-directory ``.part`` then atomically replace."""

    database = Path(database)
    target = Path(target)
    if target.suffix.lower() != ".kitaparsiv":
        target = target.with_suffix(".kitaparsiv")
    target.parent.mkdir(parents=True, exist_ok=True)
    if include_covers and asset_root is None:
        raise ArchiveError("Kapakları eklemek için asset_root belirtilmelidir")

    covers = tuple(dict.fromkeys(Path(path) for path in cover_paths))
    missing = [str(path) for path in covers if not path.is_file()]
    if include_covers and missing:
        raise ArchiveError(f"Arşivlenecek kapak bulunamadı: {', '.join(missing[:5])}")

    part = target.with_name(f".{target.name}.{os.getpid()}.{uuid.uuid4().hex}.part")
    try:
        # ZipFile otherwise creates the container with the caller's umask
        # (commonly 0644 under Finder/CLI).  A catalogue may contain student and
        # loan data, so make privacy independent of the launching shell.
        descriptor = os.open(part, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(descriptor)
        with tempfile.TemporaryDirectory(prefix="kitapkatalog-archive-") as temp_dir:
            snapshot = Path(temp_dir) / "catalog.sqlite3"
            _sqlite_snapshot(database, snapshot)
            database_hash = _sha256(snapshot)
            created_at = datetime.now(UTC).isoformat()
            cover_members: list[dict[str, object]] = []
            cover_path_salt = os.urandom(16).hex() if include_covers else None
            if include_covers:
                assert asset_root is not None
                assert cover_path_salt is not None
                for cover in covers:
                    member = _cover_member(asset_root, cover)
                    cover_members.append(
                        {
                            "member": member,
                            "size": cover.stat().st_size,
                            "sha256": _sha256(cover),
                            "source_path_fingerprint": cover_path_fingerprint(
                                cover, cover_path_salt
                            ),
                        }
                    )
                members = [str(item["member"]) for item in cover_members]
                if len(set(members)) != len(members):
                    raise ArchiveError("Birden fazla kapak aynı arşiv yoluna çözümleniyor")

            manifest = {
                "format": "KitapKatalogArchive",
                "format_version": ARCHIVE_FORMAT_VERSION,
                "created_at": created_at,
                "database": {
                    "member": DATABASE_MEMBER,
                    "size": snapshot.stat().st_size,
                    "sha256": database_hash,
                },
                "covers_included": include_covers,
                "covers": cover_members,
                "cover_path_provenance": (
                    {
                        "algorithm": COVER_PATH_PROVENANCE_ALGORITHM,
                        "salt": cover_path_salt,
                    }
                    if cover_path_salt is not None
                    else None
                ),
            }
            with zipfile.ZipFile(
                part, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6
            ) as archive:
                archive.write(snapshot, DATABASE_MEMBER)
                if include_covers:
                    for cover, item in zip(covers, cover_members, strict=True):
                        archive.write(cover, str(item["member"]))
                archive.writestr(
                    MANIFEST_MEMBER,
                    json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"),
                )
        # Validate the complete temporary artifact before replacing a user's
        # previous known-good backup.  This also closes the window in which a
        # logically invalid ZIP could be published under the final name.
        validated = inspect_archive(part, verify_hashes=True)
        os.chmod(part, 0o600)
        with part.open("rb") as handle:
            os.fsync(handle.fileno())
        os.replace(part, target)
        os.chmod(target, 0o600)
        directory = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except (OSError, zipfile.BadZipFile) as exc:
        raise ArchiveError(f"Arşiv oluşturulamadı: {exc}") from exc
    finally:
        part.unlink(missing_ok=True)
    return replace(validated, path=target)


def _safe_members(archive: zipfile.ZipFile) -> None:
    members = archive.infolist()
    if len(members) > MAX_ARCHIVE_MEMBERS:
        raise ArchiveError(f"Arşivde çok fazla dosya var ({len(members)})")
    total_size = sum(member.file_size for member in members)
    if total_size > MAX_ARCHIVE_TOTAL_BYTES:
        raise ArchiveError("Arşivin açılmış boyutu izin verilen sınırı aşıyor")
    names = [member.filename for member in members]
    if len(set(names)) != len(names):
        raise ArchiveError("Arşivde yinelenen ZIP üyesi bulundu")
    filesystem_names: set[str] = set()
    for member in members:
        path = PurePosixPath(member.filename)
        if (
            not path.parts
            or path == PurePosixPath(".")
            or path.is_absolute()
            or ".." in path.parts
            or "\\" in member.filename
            or member.filename != path.as_posix()
        ):
            raise ArchiveError(f"Arşivde güvensiz yol bulundu: {member.filename}")
        filesystem_name = unicodedata.normalize("NFC", path.as_posix()).casefold()
        if filesystem_name in filesystem_names:
            raise ArchiveError(f"Arşivde dosya sisteminde çakışan üye bulundu: {member.filename}")
        filesystem_names.add(filesystem_name)
        if member.flag_bits & 0x1:
            raise ArchiveError(f"Arşivde şifreli üye bulundu: {member.filename}")
        if member.is_dir():
            continue
        # Reject links and other special Unix file types when mode metadata exists.
        mode = member.external_attr >> 16
        if mode and (mode & 0o170000) not in {0, 0o100000}:
            raise ArchiveError(f"Arşivde özel dosya türü bulundu: {member.filename}")


def _hash_member(archive: zipfile.ZipFile, member: str) -> str:
    digest = hashlib.sha256()
    with archive.open(member) as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _manifest_sha256(value: object, *, label: str) -> str:
    if not isinstance(value, str) or len(value) != 64:
        raise ArchiveError(f"{label} SHA-256 alanı geçersiz")
    normalized = value.casefold()
    if any(character not in "0123456789abcdef" for character in normalized):
        raise ArchiveError(f"{label} SHA-256 alanı geçersiz")
    return normalized


def inspect_archive(path: Path, *, verify_hashes: bool = True) -> ArchiveInfo:
    path = Path(path)
    try:
        with zipfile.ZipFile(path) as archive:
            _safe_members(archive)
            manifest_info = archive.getinfo(MANIFEST_MEMBER)
            if manifest_info.file_size > MAX_MANIFEST_BYTES:
                raise ArchiveError(
                    "Arşiv manifesti izin verilen bellek sınırını aşıyor "
                    f"({manifest_info.file_size} > {MAX_MANIFEST_BYTES})"
                )
            manifest = json.loads(archive.read(MANIFEST_MEMBER))
            if not isinstance(manifest, dict):
                raise ArchiveError("Arşiv manifestinin üst düzeyi nesne olmalıdır")
            if manifest.get("format") != "KitapKatalogArchive":
                raise ArchiveError("Tanınmayan arşiv biçimi")
            raw_version = manifest.get("format_version")
            if isinstance(raw_version, bool):
                raise ArchiveError("Manifest sürümü geçersiz")
            version = int(manifest["format_version"])
            if version != ARCHIVE_FORMAT_VERSION:
                raise ArchiveError(f"Desteklenmeyen arşiv sürümü: {version}")
            created_at = manifest.get("created_at")
            if not isinstance(created_at, str) or not created_at.strip():
                raise ArchiveError("Manifest oluşturulma tarihi geçersiz")
            database = manifest.get("database")
            if not isinstance(database, dict):
                raise ArchiveError("Manifest veritabanı kaydı geçersiz")
            if database.get("member") != DATABASE_MEMBER:
                raise ArchiveError("Manifest veritabanı yolu geçersiz")
            raw_database_size = database.get("size")
            if isinstance(raw_database_size, bool):
                raise ArchiveError("Manifest veritabanı boyutu geçersiz")
            database_size = int(raw_database_size)
            if database_size < 0:
                raise ArchiveError("Manifest veritabanı boyutu geçersiz")
            database_sha256 = _manifest_sha256(database.get("sha256"), label="Veritabanı")
            database_info = archive.getinfo(DATABASE_MEMBER)
            if database_info.file_size != database_size:
                raise ArchiveError("Veritabanı boyutu manifestle uyuşmuyor")
            if verify_hashes and _hash_member(archive, DATABASE_MEMBER) != database_sha256:
                raise ArchiveError("Veritabanı SHA-256 değeri uyuşmuyor")

            covers = manifest.get("covers", [])
            if not isinstance(covers, list):
                raise ArchiveError("Manifest kapak listesi geçersiz")
            covers_included = manifest.get("covers_included")
            if not isinstance(covers_included, bool):
                raise ArchiveError("Manifest kapak içerme bilgisi geçersiz")
            provenance = manifest.get("cover_path_provenance")
            provenance_salt: str | None = None
            if provenance is not None:
                if not isinstance(provenance, dict):
                    raise ArchiveError("Manifest kapak yol kanıtı geçersiz")
                if provenance.get("algorithm") != COVER_PATH_PROVENANCE_ALGORITHM:
                    raise ArchiveError("Manifest kapak yol kanıtı algoritması geçersiz")
                raw_salt = provenance.get("salt")
                if not isinstance(raw_salt, str) or len(raw_salt) != 32:
                    raise ArchiveError("Manifest kapak yol kanıtı tuzu geçersiz")
                try:
                    bytes.fromhex(raw_salt)
                except ValueError as exc:
                    raise ArchiveError("Manifest kapak yol kanıtı tuzu geçersiz") from exc
                provenance_salt = raw_salt
            cover_names: list[str] = []
            for item in covers:
                if not isinstance(item, dict):
                    raise ArchiveError("Manifest kapak kaydı geçersiz")
                member_name = item.get("member")
                if not isinstance(member_name, str):
                    raise ArchiveError("Manifest kapak yolu geçersiz")
                member_path = PurePosixPath(member_name)
                if (
                    member_name.endswith("/")
                    or len(member_path.parts) < 2
                    or member_path.parts[0] != "covers"
                ):
                    raise ArchiveError(f"Manifest kapak yolu geçersiz: {member_name}")
                cover_names.append(member_name)
                info = archive.getinfo(member_name)
                raw_cover_size = item.get("size")
                if isinstance(raw_cover_size, bool):
                    raise ArchiveError(f"Kapak boyutu geçersiz: {member_name}")
                cover_size = int(raw_cover_size)
                if cover_size < 0:
                    raise ArchiveError(f"Kapak boyutu geçersiz: {member_name}")
                if info.file_size != cover_size:
                    raise ArchiveError(f"Kapak boyutu uyuşmuyor: {member_name}")
                cover_sha256 = _manifest_sha256(item.get("sha256"), label=f"Kapak ({member_name})")
                if verify_hashes and _hash_member(archive, member_name) != cover_sha256:
                    raise ArchiveError(f"Kapak SHA-256 değeri uyuşmuyor: {member_name}")
                raw_path_fingerprint = item.get("source_path_fingerprint")
                if provenance_salt is None:
                    if raw_path_fingerprint is not None:
                        raise ArchiveError("Manifest kapak yol kanıtı eksik")
                else:
                    _manifest_sha256(
                        raw_path_fingerprint,
                        label=f"Kapak yolu ({member_name})",
                    )

            if len(set(cover_names)) != len(cover_names):
                raise ArchiveError("Manifestte yinelenen kapak yolu var")

            if covers and not covers_included:
                raise ArchiveError("Manifest kapak içerme bilgisi tutarsız")
            expected_members = {MANIFEST_MEMBER, DATABASE_MEMBER, *cover_names}
            actual_members = {member.filename for member in archive.infolist()}
            if actual_members != expected_members:
                unexpected = sorted(actual_members - expected_members)
                missing = sorted(expected_members - actual_members)
                detail = []
                if unexpected:
                    detail.append("bildirilmeyen=" + ", ".join(unexpected[:5]))
                if missing:
                    detail.append("eksik=" + ", ".join(missing[:5]))
                raise ArchiveError("Arşiv üye kümesi manifestle uyuşmuyor: " + "; ".join(detail))
    except (
        KeyError,
        ValueError,
        TypeError,
        RuntimeError,
        NotImplementedError,
        OSError,
        json.JSONDecodeError,
        zipfile.BadZipFile,
    ) as exc:
        raise ArchiveError(f"Geçersiz veya bozuk .kitaparsiv: {exc}") from exc

    return ArchiveInfo(
        path=path,
        format_version=version,
        created_at=created_at,
        database_sha256=database_sha256,
        database_size=database_size,
        cover_count=len(covers),
        covers_included=covers_included,
    )


def extract_archive(
    archive_path: Path,
    destination: Path,
    *,
    verify_hashes: bool = True,
) -> Path:
    """Extract into an empty destination after validating every declared hash."""

    info = inspect_archive(archive_path, verify_hashes=verify_hashes)
    destination = Path(destination)
    if destination.exists() and any(destination.iterdir()):
        raise ArchiveError(f"Hedef klasör boş değil: {destination}")
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    destination.chmod(0o700)
    try:
        with zipfile.ZipFile(info.path) as archive:
            _safe_members(archive)
            for member in archive.infolist():
                output = destination.joinpath(*PurePosixPath(member.filename).parts)
                output.resolve().relative_to(destination.resolve())
                if member.is_dir():
                    output.mkdir(parents=True, exist_ok=True, mode=0o700)
                    output.chmod(0o700)
                    continue
                output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                output.parent.chmod(0o700)
                descriptor = os.open(
                    output,
                    os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                    0o600,
                )
                with os.fdopen(descriptor, "wb") as target, archive.open(member) as source:
                    while block := source.read(4 * 1024 * 1024):
                        target.write(block)
    except (OSError, zipfile.BadZipFile) as exc:
        raise ArchiveError(f"Arşiv çıkarılamadı: {exc}") from exc
    return destination / DATABASE_MEMBER
