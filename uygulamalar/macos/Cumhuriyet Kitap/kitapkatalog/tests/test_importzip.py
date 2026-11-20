"""Safe expansion of an uploaded ZIP for bulk import.

Mirrors the zip-slip/bomb/encryption threats ``kitapkatalog.archive`` already
guards a ``.kitaparsiv`` restore against, but for an untrusted photo-batch
ZIP: a bad member is skipped and reported rather than aborting the whole
archive, and legacy cp437-mangled Turkish folder names must still resolve
since a folder becomes a shelf name.
"""

from __future__ import annotations

import io
import zipfile
from pathlib import Path

import pytest

from kitapkatalog.importzip import ZipExpansionError, expand_zip_upload

_IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png"})


def _zip_bytes(entries: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return buffer.getvalue()


def _write_zip(path: Path, entries: dict[str, bytes]) -> Path:
    path.write_bytes(_zip_bytes(entries))
    return path


def _mark_first_member_encrypted(data: bytes) -> bytes:
    """Flip the general-purpose encryption bit without real PKZip crypto.

    :mod:`zipfile` always resets this bit to zero while writing, so the only
    way to exercise the detection path is to patch the already-written bytes.
    """

    patched = bytearray(data)
    local = patched.find(b"PK\x03\x04")
    assert local != -1
    patched[local + 6] |= 0x01
    central = patched.find(b"PK\x01\x02")
    assert central != -1
    patched[central + 8] |= 0x01
    return bytes(patched)


def _cp437_mangled_zip(path: Path, real_name: str, data: bytes = b"cover-bytes") -> Path:
    """A ZIP whose member name is UTF-8 bytes without the UTF-8 flag set.

    Real-world zip tools that write Turkish folder names this way are common;
    :mod:`zipfile` cannot be told to skip the UTF-8 flag for a non-ASCII
    ``str`` filename, so a byte-length-matched ASCII placeholder is written
    first and then swapped for the real UTF-8 bytes in the raw archive.
    """

    real_bytes = real_name.encode("utf-8")
    placeholder = "Q" * len(real_bytes)
    raw = _zip_bytes({placeholder: data})
    patched = raw.replace(placeholder.encode("ascii"), real_bytes)
    path.write_bytes(patched)
    return path


def _expand(
    path: Path,
    destination: Path,
    *,
    allowed_suffixes=_IMAGE_SUFFIXES,
    max_members: int = 1000,
    max_total_bytes: int = 10 * 1024**2,
    max_file_bytes: int = 5 * 1024**2,
):
    return expand_zip_upload(
        path,
        destination,
        allowed_suffixes=allowed_suffixes,
        max_members=max_members,
        max_total_bytes=max_total_bytes,
        max_file_bytes=max_file_bytes,
    )


def test_a_relative_escape_is_rejected_but_siblings_still_extract(tmp_path: Path) -> None:
    zip_path = _write_zip(
        tmp_path / "archive.zip", {"../evil.jpg": b"x", "ok.jpg": b"good-bytes"}
    )

    result = _expand(zip_path, tmp_path / "out")

    assert [path.name for path in result.files] == ["ok.jpg"]
    assert result.rejected == (("../evil.jpg", "Güvensiz ZIP yolu"),)


def test_an_absolute_member_path_is_rejected(tmp_path: Path) -> None:
    zip_path = _write_zip(tmp_path / "archive.zip", {"/etc/evil.jpg": b"x"})

    result = _expand(zip_path, tmp_path / "out")

    assert result.files == ()
    assert result.rejected == (("/etc/evil.jpg", "Güvensiz ZIP yolu"),)


def test_an_encrypted_member_is_rejected_without_being_opened(tmp_path: Path) -> None:
    zip_path = tmp_path / "archive.zip"
    zip_path.write_bytes(_mark_first_member_encrypted(_zip_bytes({"secret.jpg": b"x" * 40})))

    result = _expand(zip_path, tmp_path / "out")

    assert result.files == ()
    assert result.rejected == (("secret.jpg", "Şifreli ZIP üyesi desteklenmiyor"),)


def test_a_compression_bomb_ratio_is_rejected(tmp_path: Path) -> None:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("bomb.jpg", b"0" * 2_000_000)
    zip_path = tmp_path / "bomb.zip"
    zip_path.write_bytes(buffer.getvalue())

    result = _expand(zip_path, tmp_path / "out", max_total_bytes=10 * 1024**3)

    assert result.files == ()
    assert result.rejected == (
        ("bomb.jpg", "Sıkıştırma oranı güvenli sınırın dışında (zip bombası şüphesi)"),
    )


def test_a_nested_zip_member_is_rejected(tmp_path: Path) -> None:
    zip_path = _write_zip(
        tmp_path / "archive.zip",
        {"inner.zip": b"PK\x03\x04not-a-real-nested-archive", "ok.jpg": b"good"},
    )

    result = _expand(zip_path, tmp_path / "out", allowed_suffixes=_IMAGE_SUFFIXES | {".zip"})

    assert [path.name for path in result.files] == ["ok.jpg"]
    assert result.rejected == (("inner.zip", "İç içe ZIP desteklenmiyor"),)


def test_an_unlisted_extension_is_rejected(tmp_path: Path) -> None:
    zip_path = _write_zip(tmp_path / "archive.zip", {"notes.txt": b"hello"})

    result = _expand(zip_path, tmp_path / "out")

    assert result.files == ()
    assert result.rejected == (("notes.txt", "Desteklenmeyen dosya türü: .txt"),)


def test_a_file_over_the_per_member_cap_is_rejected(tmp_path: Path) -> None:
    zip_path = _write_zip(tmp_path / "archive.zip", {"big.jpg": b"x" * 200})

    result = _expand(zip_path, tmp_path / "out", max_file_bytes=100)

    assert result.files == ()
    assert result.rejected == (("big.jpg", "Dosya boyutu sınırı aşıyor"),)


def test_too_many_declared_members_aborts_the_whole_archive(tmp_path: Path) -> None:
    zip_path = _write_zip(
        tmp_path / "archive.zip", {f"kitap-{i}.jpg": b"x" for i in range(5)}
    )

    with pytest.raises(ZipExpansionError, match="çok fazla dosya"):
        _expand(zip_path, tmp_path / "out", max_members=4)


def test_the_declared_total_size_budget_aborts_the_whole_archive(tmp_path: Path) -> None:
    zip_path = _write_zip(tmp_path / "archive.zip", {"kitap.jpg": b"x" * 1000})

    with pytest.raises(ZipExpansionError, match="açılmış boyutu"):
        _expand(zip_path, tmp_path / "out", max_total_bytes=100)


def test_a_turkish_shelf_folder_survives_legacy_cp437_encoding(tmp_path: Path) -> None:
    zip_path = _cp437_mangled_zip(tmp_path / "archive.zip", "DOLAP-ŞİİR/kitap1-1.jpg")

    result = _expand(zip_path, tmp_path / "out")

    assert len(result.files) == 1
    extracted = result.files[0]
    assert extracted.parent.name == "DOLAP-ŞİİR"
    assert extracted.name == "kitap1-1.jpg"
    assert extracted.read_bytes() == b"cover-bytes"


def test_folder_structure_is_preserved_so_each_folder_still_pairs_as_a_book(
    tmp_path: Path,
) -> None:
    entries = {
        f"Dolap {shelf}/kitap-{index}.jpg": bytes([shelf]) * 10
        for shelf in (1, 2)
        for index in range(1, 5)
    }
    zip_path = _write_zip(tmp_path / "archive.zip", entries)

    result = _expand(zip_path, tmp_path / "out")

    by_folder: dict[str, list[str]] = {}
    for path in result.files:
        by_folder.setdefault(path.parent.name, []).append(path.name)
    assert sorted(by_folder) == ["Dolap 1", "Dolap 2"]
    assert len(by_folder["Dolap 1"]) == 4
    assert len(by_folder["Dolap 2"]) == 4


def test_a_duplicate_filesystem_name_after_casefolding_is_rejected(tmp_path: Path) -> None:
    # Case-insensitive filesystems collapse these two members to one path;
    # only the first write should win, the second is reported as rejected.
    zip_path = _write_zip(
        tmp_path / "archive.zip",
        {"Dolap 1/kitap.jpg": b"first", "dolap 1/KITAP.JPG": b"second"},
    )

    result = _expand(zip_path, tmp_path / "out")

    assert len(result.files) == 1
    assert len(result.rejected) == 1
    assert result.rejected[0][1] == "Dosya sisteminde çakışan ad"
