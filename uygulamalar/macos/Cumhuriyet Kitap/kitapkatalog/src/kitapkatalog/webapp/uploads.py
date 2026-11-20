"""Bounded, atomic upload staging for the local web application.

Multipart parsers may spool incoming files before a route sees them, so every
route still needs its own durable-storage limits.  This module gives all upload
surfaces the same guarantees: safe names, byte budgets, a free-space reserve,
content checks, fsync + atomic rename, and no abandoned ``.part`` file.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import time
import unicodedata
import uuid
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from fastapi import HTTPException

# Taban sınıf: hem rota parametresinden gelen FastAPI UploadFile'ını hem de
# ``request.form()`` çıktısını kapsar.
from starlette.datastructures import UploadFile

_CHUNK_BYTES = 1 << 20
_FREE_SPACE_RESERVE = 256 * 1024**2
_MAX_IMAGE_PIXELS = 100_000_000

UploadKind = Literal["archive", "audio", "document", "image", "xlsx"]


@dataclass(slots=True)
class UploadBudget:
    """Shared byte budget for a multi-file request."""

    maximum: int
    used: int = 0

    def consume(self, amount: int) -> None:
        if amount < 0 or self.used + amount > self.maximum:
            raise HTTPException(
                status_code=413,
                detail=f"Yükleme grubunun toplam sınırı aşıldı ({_size(self.maximum)}).",
            )
        self.used += amount

    def release(self, amount: int) -> None:
        self.used = max(0, self.used - max(0, amount))


def safe_upload_name(filename: str | None, fallback: str = "dosya") -> str:
    """Drop client paths and control characters without losing pairing names."""

    name = Path(filename or fallback).name.strip().replace("\x00", "")
    name = "".join(character for character in name if character.isprintable())
    return name[:180] or fallback


def _safe_component(value: str) -> str | None:
    """One directory name that can never escape its parent."""

    name = Path(value.replace("\x00", "")).name
    name = "".join(character for character in name if character.isprintable())
    # Baştaki/sondaki noktalar atılır: ".." ve gizli dizin adları elenir.
    name = name.strip().strip(". ")
    return name[:80] or None


def safe_relative_directory(filename: str | None, *, max_depth: int = 6) -> tuple[str, ...]:
    """Sanitize a browser-supplied relative path into staging subdirectories.

    Directory uploads send ``webkitRelativePath`` as the multipart filename so
    that per-folder book grouping survives staging.  Only the directory part is
    kept, every component is reduced to a plain name, and the depth is bounded;
    the result therefore always stays inside the staging root.
    """

    raw = (filename or "").replace("\\", "/")
    components = [
        component for part in raw.split("/")[:-1] if (component := _safe_component(part))
    ]
    # Derinlik aşılırsa EN İÇTEKİ klasörler korunur: kitabı gruplayan ve dolap
    # adını veren yaprak klasördür, kökteki "Kütüphane" değil.
    return tuple(components[-max_depth:])


def staging_folder(filename: str | None) -> tuple[str, str] | None:
    """Return ``(staging directory name, display name)`` for one upload.

    Sanitizing is lossy: ``Kitap 1/`` and ``Kitap_1/`` — or two folders that
    differ only past the length/depth cut — collapse to the same name.  Merging
    them in staging would group two shelves' books together, so the directory
    carries a digest of the *original* path while the display name (which
    becomes the shelf) stays the clean, readable one.  ``None`` means the file
    was picked outside any folder.
    """

    components = safe_relative_directory(filename)
    if not components:
        return None
    raw = unicodedata.normalize("NFC", (filename or "").replace("\\", "/"))
    digest = hashlib.sha256(raw.rsplit("/", 1)[0].encode("utf-8")).hexdigest()[:10]
    display = components[-1]
    return f"{display}-{digest}", display


def _size(value: int) -> str:
    if value >= 1024**3:
        return f"{value / 1024**3:.1f} GiB"
    return f"{value / 1024**2:.0f} MiB"


def _unique_target(directory: Path, name: str) -> Path:
    candidate = directory / name
    stem, suffix = candidate.stem, candidate.suffix
    counter = 1
    while candidate.exists():
        candidate = directory / f"{stem}-{counter}{suffix}"
        counter += 1
    return candidate


def _verify_image(path: Path) -> None:
    from PIL import Image, UnidentifiedImageError

    try:
        import pillow_heif

        pillow_heif.register_heif_opener()
    except ImportError:
        pass
    try:
        with Image.open(path) as image:
            width, height = image.size
            if width < 1 or height < 1 or width * height > _MAX_IMAGE_PIXELS:
                raise ValueError("Görsel boyutları güvenli sınırların dışında")
            image.verify()
    except (OSError, UnidentifiedImageError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Dosya geçerli bir görsel değil") from exc


def _verify_xlsx(path: Path) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            names = set(archive.namelist())
            required = {"[Content_Types].xml", "xl/workbook.xml"}
            if not required.issubset(names):
                raise ValueError("Eksik Excel bileşeni")
    except (OSError, ValueError, zipfile.BadZipFile) as exc:
        raise HTTPException(status_code=400, detail="Dosya geçerli bir .xlsx çalışma kitabı değil") from exc


def _verify_pdf(path: Path) -> None:
    try:
        with path.open("rb") as handle:
            header = handle.read(8)
        if not header.startswith(b"%PDF-"):
            raise ValueError("PDF imzası yok")
    except (OSError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Dosya geçerli bir PDF değil") from exc


def _verify_zip(path: Path) -> None:
    try:
        with path.open("rb") as handle:
            header = handle.read(4)
        if header != b"PK\x03\x04":
            raise ValueError("ZIP imzası yok")
    except (OSError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Dosya geçerli bir ZIP değil") from exc


def _verify_audio(path: Path) -> None:
    """Cheap container signature gate; the transcoder performs the deep check."""

    try:
        with path.open("rb") as handle:
            header = handle.read(16)
        valid = (
            header.startswith((b"RIFF", b"OggS", b"fLaC", b"ID3", b"\x1aE\xdf\xa3"))
            or header[:2] in {b"\xff\xf1", b"\xff\xf9", b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"}
            or b"ftyp" in header
        )
        if not valid:
            raise ValueError("Ses kapsayıcı imzası yok")
    except (OSError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Dosya geçerli bir ses kaydı değil") from exc


def _verify_content(path: Path, *, kind: UploadKind, suffix: str) -> None:
    if kind == "image":
        _verify_image(path)
    elif kind == "xlsx":
        _verify_xlsx(path)
    elif kind == "audio":
        _verify_audio(path)
    elif kind == "document":
        if suffix == ".pdf":
            _verify_pdf(path)
        elif suffix == ".zip":
            _verify_zip(path)
        else:
            _verify_image(path)


async def stage_upload(
    directory: Path,
    upload: UploadFile,
    *,
    allowed_suffixes: set[str] | frozenset[str],
    maximum_bytes: int,
    kind: UploadKind,
    budget: UploadBudget | None = None,
    target_name: str | None = None,
) -> Path:
    """Stream one upload into ``directory`` and publish it atomically."""

    directory.mkdir(parents=True, exist_ok=True)
    name = safe_upload_name(target_name or upload.filename)
    suffix = Path(name).suffix.lower()
    if suffix not in allowed_suffixes:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen dosya türü: {name}")
    if shutil.disk_usage(directory).free <= _FREE_SPACE_RESERVE:
        raise HTTPException(status_code=507, detail="Yükleme için güvenli boş disk alanı kalmadı")

    target = _unique_target(directory, name)
    part = directory / f".{target.name}.{uuid.uuid4().hex}.part"
    written = 0
    try:
        with part.open("xb") as handle:
            while chunk := await upload.read(_CHUNK_BYTES):
                if written + len(chunk) > maximum_bytes:
                    raise HTTPException(
                        status_code=413,
                        detail=f"{name} dosya sınırını aşıyor ({_size(maximum_bytes)}).",
                    )
                if shutil.disk_usage(directory).free - len(chunk) <= _FREE_SPACE_RESERVE:
                    raise HTTPException(
                        status_code=507,
                        detail="Yükleme sırasında güvenli boş disk alanı sınırına ulaşıldı",
                    )
                if budget is not None:
                    budget.consume(len(chunk))
                handle.write(chunk)
                written += len(chunk)
            if written == 0:
                raise HTTPException(status_code=400, detail=f"{name} boş bir dosya")
            handle.flush()
            os.fsync(handle.fileno())
        _verify_content(part, kind=kind, suffix=suffix)
        os.replace(part, target)
        return target
    except BaseException:
        part.unlink(missing_ok=True)
        if budget is not None:
            budget.release(written)
        raise


def cleanup_staging(directory: Path, *, root: Path) -> None:
    """Remove only a staging subtree proven to be below its designated root."""

    resolved_root = root.resolve()
    resolved = directory.resolve()
    if resolved == resolved_root or not resolved.is_relative_to(resolved_root):
        raise ValueError(f"Güvenli olmayan staging temizleme hedefi: {directory}")
    shutil.rmtree(resolved, ignore_errors=True)


def purge_expired_files(directory: Path, *, maximum_age_seconds: int) -> int:
    """Delete abandoned regular staging files, never directories or symlinks."""

    if not directory.is_dir():
        return 0
    cutoff = time.time() - maximum_age_seconds
    removed = 0
    for path in directory.iterdir():
        try:
            if path.is_file() and not path.is_symlink() and path.stat().st_mtime < cutoff:
                path.unlink()
                removed += 1
        except FileNotFoundError:
            continue
    return removed
