from __future__ import annotations

import json
import os
import sqlite3
import stat
import zipfile
from pathlib import Path

import pytest

import kitapkatalog.archive as archive_module
from kitapkatalog.archive import (
    ArchiveError,
    create_archive,
    extract_archive,
    inspect_archive,
)


def _database(path: Path) -> None:
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE kitap (id INTEGER PRIMARY KEY, baslik TEXT)")
        connection.execute("INSERT INTO kitap (baslik) VALUES (?)", ("İnce Memed",))


def test_atomic_archive_with_utf8_cover_and_extract(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    assets = tmp_path / "assets"
    cover = assets / "şiir" / "ön.jpg"
    cover.parent.mkdir(parents=True)
    cover.write_bytes(b"cover-bytes")

    target = tmp_path / "yedek.kitaparsiv"
    info = create_archive(
        database,
        target,
        asset_root=assets,
        cover_paths=[cover],
        include_covers=True,
    )
    assert info.cover_count == 1
    assert info.covers_included
    assert target.is_file()
    assert not list(tmp_path.glob("*.part"))

    extracted = extract_archive(target, tmp_path / "restored")
    with sqlite3.connect(extracted) as connection:
        assert connection.execute("SELECT baslik FROM kitap").fetchone()[0] == "İnce Memed"
    extracted_cover = tmp_path / "restored" / "covers" / "şiir" / "ön.jpg"
    assert extracted_cover.read_bytes() == b"cover-bytes"
    assert stat.S_IMODE((tmp_path / "restored").stat().st_mode) == 0o700
    assert stat.S_IMODE(extracted_cover.parent.stat().st_mode) == 0o700
    assert stat.S_IMODE(extracted.stat().st_mode) == 0o600
    assert stat.S_IMODE(extracted_cover.stat().st_mode) == 0o600


def test_snapshot_includes_wal_data(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    connection = sqlite3.connect(database)
    connection.execute("PRAGMA journal_mode=WAL")
    connection.execute("CREATE TABLE t (value TEXT)")
    connection.execute("INSERT INTO t VALUES ('kalıcı')")
    connection.commit()

    target = tmp_path / "wal.kitaparsiv"
    create_archive(database, target)
    connection.close()
    restored = extract_archive(target, tmp_path / "wal-restored")
    with sqlite3.connect(restored) as restored_db:
        assert restored_db.execute("SELECT value FROM t").fetchone()[0] == "kalıcı"


def test_inspection_rejects_traversal_member(tmp_path: Path) -> None:
    path = tmp_path / "unsafe.kitaparsiv"
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("../kaçış", b"x")
        archive.writestr("manifest.json", b"{}")
    with pytest.raises(ArchiveError, match="güvensiz"):
        inspect_archive(path)


def test_external_cover_is_rejected(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    assets = tmp_path / "assets"
    assets.mkdir()
    external = tmp_path / "external.jpg"
    external.write_bytes(b"x")
    with pytest.raises(ArchiveError, match="dışında"):
        create_archive(
            database,
            tmp_path / "bad.kitaparsiv",
            asset_root=assets,
            cover_paths=[external],
            include_covers=True,
        )


def test_archive_is_private_even_under_permissive_umask(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    previous_umask = os.umask(0o022)
    try:
        target = create_archive(database, tmp_path / "private.kitaparsiv").path
    finally:
        os.umask(previous_umask)

    assert stat.S_IMODE(target.stat().st_mode) == 0o600


def test_inspection_rejects_undeclared_member(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    target = create_archive(database, tmp_path / "extra.kitaparsiv").path
    with zipfile.ZipFile(target, "a") as archive:
        archive.writestr("covers/bildirilmeyen/payload.html", b"payload")

    with pytest.raises(ArchiveError, match="üye kümesi"):
        inspect_archive(target)


def test_inspection_rejects_duplicate_zip_member(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    target = create_archive(database, tmp_path / "duplicate.kitaparsiv").path
    with (
        pytest.warns(UserWarning, match="Duplicate name"),
        zipfile.ZipFile(target, "a") as archive,
    ):
        archive.writestr("manifest.json", b"{}")

    with pytest.raises(ArchiveError, match="yinelenen ZIP üyesi"):
        inspect_archive(target)


def test_inspection_rejects_encrypted_member_flag(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    target = create_archive(database, tmp_path / "encrypted.kitaparsiv").path

    payload = bytearray(target.read_bytes())
    for signature, flag_offset in ((b"PK\x03\x04", 6), (b"PK\x01\x02", 8)):
        start = 0
        while (position := payload.find(signature, start)) >= 0:
            offset = position + flag_offset
            flags = int.from_bytes(payload[offset : offset + 2], "little") | 0x1
            payload[offset : offset + 2] = flags.to_bytes(2, "little")
            start = position + 4
    target.write_bytes(payload)

    with pytest.raises(ArchiveError, match="şifreli üye"):
        inspect_archive(target)


def test_inspection_rejects_special_file_member(tmp_path: Path) -> None:
    target = tmp_path / "special.kitaparsiv"
    member = zipfile.ZipInfo("covers/link.jpg")
    member.create_system = 3
    member.external_attr = (stat.S_IFLNK | 0o777) << 16
    with zipfile.ZipFile(target, "w") as archive:
        archive.writestr(member, b"hedef")

    with pytest.raises(ArchiveError, match="özel dosya türü"):
        inspect_archive(target)


def test_inspection_rejects_manifest_before_unbounded_read(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    target = tmp_path / "oversized-manifest.kitaparsiv"
    monkeypatch.setattr(archive_module, "MAX_MANIFEST_BYTES", 32)
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("manifest.json", b"{" + b" " * 32 + b"}")

    with pytest.raises(ArchiveError, match=r"manifesti.*bellek sınırını"):
        inspect_archive(target)


def test_direct_inspection_enforces_member_and_expanded_size_limits(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    member_target = tmp_path / "too-many.kitaparsiv"
    monkeypatch.setattr(archive_module, "MAX_ARCHIVE_MEMBERS", 1)
    with zipfile.ZipFile(member_target, "w") as archive:
        archive.writestr("manifest.json", b"{}")
        archive.writestr("catalog/catalog.sqlite3", b"db")
    with pytest.raises(ArchiveError, match="çok fazla dosya"):
        inspect_archive(member_target)

    size_target = tmp_path / "too-large.kitaparsiv"
    monkeypatch.setattr(archive_module, "MAX_ARCHIVE_MEMBERS", 20_000)
    monkeypatch.setattr(archive_module, "MAX_ARCHIVE_TOTAL_BYTES", 4)
    with zipfile.ZipFile(size_target, "w") as archive:
        archive.writestr("manifest.json", b"{}")
        archive.writestr("catalog/catalog.sqlite3", b"abc")
    with pytest.raises(ArchiveError, match="açılmış boyutu"):
        inspect_archive(size_target)


@pytest.mark.parametrize("payload", [b"[]", b'"metin"', b"\xff"])
def test_inspection_normalizes_non_object_or_non_utf8_manifest(
    tmp_path: Path, payload: bytes
) -> None:
    target = tmp_path / "invalid-manifest.kitaparsiv"
    with zipfile.ZipFile(target, "w") as archive:
        archive.writestr("manifest.json", payload)

    with pytest.raises(ArchiveError, match=r"Geçersiz|manifestinin"):
        inspect_archive(target)


def test_inspection_rejects_missing_created_at_inside_archive_boundary(
    tmp_path: Path,
) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    target = create_archive(database, tmp_path / "missing-created.kitaparsiv").path
    with zipfile.ZipFile(target) as source:
        database_payload = source.read("catalog/catalog.sqlite3")
        manifest = json.loads(source.read("manifest.json"))
    manifest.pop("created_at")
    with zipfile.ZipFile(target, "w") as archive:
        archive.writestr("catalog/catalog.sqlite3", database_payload)
        archive.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False).encode("utf-8"))

    with pytest.raises(ArchiveError, match="oluşturulma tarihi"):
        inspect_archive(target)


def test_invalid_new_archive_never_replaces_existing_target(tmp_path: Path) -> None:
    database = tmp_path / "catalog.sqlite3"
    _database(database)
    target = create_archive(database, tmp_path / "korunan.kitaparsiv").path
    original = target.read_bytes()

    assets = tmp_path / "assets"
    real = assets / "real"
    real.mkdir(parents=True)
    cover = real / "cover.jpg"
    cover.write_bytes(b"cover")
    alias = assets / "alias"
    alias.symlink_to(real, target_is_directory=True)

    with pytest.raises(ArchiveError, match="aynı arşiv yoluna"):
        create_archive(
            database,
            target,
            asset_root=assets,
            cover_paths=[cover, alias / "cover.jpg"],
            include_covers=True,
        )

    assert target.read_bytes() == original
    assert not list(tmp_path.glob(".korunan.kitaparsiv.*.part"))
