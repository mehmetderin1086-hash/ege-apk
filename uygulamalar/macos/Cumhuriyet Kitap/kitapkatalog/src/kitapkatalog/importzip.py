"""Safe expansion of a user-uploaded ZIP archive into import staging.

This mirrors the zip-slip/bomb/encryption checks ``kitapkatalog.archive``
applies to a ``.kitaparsiv`` restore, but is deliberately independent from it:
an untrusted photo-batch ZIP has a looser member policy (legacy cp437-encoded
Turkish folder names must still resolve, since the folder becomes a shelf
name) and a different error contract — one bad member is skipped and
reported rather than aborting the whole archive, so a single corrupt file
does not block a shelf's worth of good photos.
"""

from __future__ import annotations

import os
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

#: Above this declared-size/compressed-size ratio a member is treated as a
#: compression bomb and rejected rather than extracted.
MAX_COMPRESSION_RATIO = 100


class ZipExpansionError(RuntimeError):
    """The archive as a whole cannot be safely expanded."""


@dataclass(frozen=True, slots=True)
class ZipExpansion:
    #: Extracted file paths, in ``destination``, with the archive's folder
    #: structure preserved (so folder-as-shelf pairing still works).
    files: tuple[Path, ...]
    #: (archive member name, Turkish rejection reason) for every skipped member.
    rejected: tuple[tuple[str, str], ...]


def _decode_member_name(filename: str, flag_bits: int) -> str:
    """Recover a Turkish folder/file name legacy zip writers mangled.

    Without the UTF-8 flag, :mod:`zipfile` decodes ``filename`` as cp437; many
    Windows/macOS zip tools write UTF-8 bytes there anyway without setting the
    flag, which turns ``ş``, ``ğ``, ``ı`` into cp437 mojibake.  Re-encoding as
    cp437 is a lossless round trip (it covers all 256 byte values), so it
    recovers the original bytes for a fresh UTF-8 decode.
    """

    if flag_bits & 0x800:
        raw = filename
    else:
        raw = filename.encode("cp437").decode("utf-8", errors="replace")
    return unicodedata.normalize("NFC", raw.replace("\\", "/"))


def _unsafe_path_reason(name: str) -> str | None:
    path = PurePosixPath(name)
    if (
        not path.parts
        or path.is_absolute()
        or ".." in path.parts
        or any(part in {"", "."} for part in path.parts)
    ):
        return "Güvensiz ZIP yolu"
    return None


def expand_zip_upload(
    zip_path: Path,
    destination: Path,
    *,
    allowed_suffixes: frozenset[str] | set[str],
    max_members: int,
    max_total_bytes: int,
    max_file_bytes: int,
) -> ZipExpansion:
    """Extract ``zip_path`` under ``destination``, keeping its folder structure.

    Every member is validated before a byte is written.  A member that fails
    a safety or type check is skipped and recorded in ``rejected`` instead of
    aborting the whole archive.  Exceeding ``max_members``/``max_total_bytes``
    (the caller's remaining request-wide budget) aborts the whole archive,
    since one oversized ZIP must not be able to blow past that budget by
    itself.
    """

    destination = Path(destination)
    rejected: list[tuple[str, str]] = []
    extracted: list[Path] = []

    try:
        with zipfile.ZipFile(zip_path) as archive:
            members = [member for member in archive.infolist() if not member.is_dir()]
            if len(members) > max_members:
                raise ZipExpansionError(
                    f"ZIP içinde çok fazla dosya var ({len(members)} > {max_members})"
                )
            declared_total = sum(member.file_size for member in members)
            if declared_total > max_total_bytes:
                raise ZipExpansionError("ZIP'in açılmış boyutu izin verilen sınırı aşıyor")

            destination.mkdir(parents=True, exist_ok=True)
            resolved_destination = destination.resolve()
            seen_names: set[str] = set()
            total_written = 0

            for member in members:
                name = _decode_member_name(member.filename, member.flag_bits)

                if reason := _unsafe_path_reason(name):
                    rejected.append((name, reason))
                    continue
                if member.flag_bits & 0x1:
                    rejected.append((name, "Şifreli ZIP üyesi desteklenmiyor"))
                    continue
                mode = member.external_attr >> 16
                if mode and (mode & 0o170000) not in {0, 0o100000}:
                    rejected.append(
                        (name, "Özel dosya türü (sembolik bağlantı vb.) desteklenmiyor")
                    )
                    continue

                suffix = PurePosixPath(name).suffix.lower()
                if suffix == ".zip":
                    rejected.append((name, "İç içe ZIP desteklenmiyor"))
                    continue
                if suffix not in allowed_suffixes:
                    rejected.append(
                        (name, f"Desteklenmeyen dosya türü: {suffix or '(uzantısız)'}")
                    )
                    continue
                if member.file_size > max_file_bytes:
                    rejected.append((name, "Dosya boyutu sınırı aşıyor"))
                    continue
                if (
                    member.compress_size > 0
                    and member.file_size / member.compress_size > MAX_COMPRESSION_RATIO
                ):
                    rejected.append(
                        (name, "Sıkıştırma oranı güvenli sınırın dışında (zip bombası şüphesi)")
                    )
                    continue

                filesystem_name = name.casefold()
                if filesystem_name in seen_names:
                    rejected.append((name, "Dosya sisteminde çakışan ad"))
                    continue

                output = destination.joinpath(*PurePosixPath(name).parts)
                try:
                    resolved_output = output.resolve()
                    resolved_output.relative_to(resolved_destination)
                except (OSError, ValueError):
                    rejected.append((name, "Güvensiz ZIP yolu"))
                    continue

                output.parent.mkdir(parents=True, exist_ok=True)
                part = output.with_name(f".{output.name}.{os.getpid()}.part")
                try:
                    with archive.open(member) as source, part.open("wb") as target:
                        written = 0
                        while block := source.read(1024 * 1024):
                            written += len(block)
                            total_written += len(block)
                            if written > max_file_bytes:
                                raise ZipExpansionError("Dosya boyutu sınırı aşıyor")
                            if total_written > max_total_bytes:
                                raise ZipExpansionError(
                                    "ZIP'in açılmış boyutu izin verilen sınırı aşıyor"
                                )
                            target.write(block)
                        target.flush()
                        os.fsync(target.fileno())
                except ZipExpansionError:
                    part.unlink(missing_ok=True)
                    raise
                except (OSError, RuntimeError, NotImplementedError, zipfile.BadZipFile) as exc:
                    part.unlink(missing_ok=True)
                    rejected.append((name, f"Açılamadı: {exc}"))
                    continue
                part.replace(output)
                seen_names.add(filesystem_name)
                extracted.append(output)
    except zipfile.BadZipFile as exc:
        raise ZipExpansionError(f"Geçersiz ZIP dosyası: {exc}") from exc
    except NotImplementedError as exc:
        raise ZipExpansionError(f"Desteklenmeyen ZIP sıkıştırma yöntemi: {exc}") from exc

    return ZipExpansion(files=tuple(extracted), rejected=tuple(rejected))
