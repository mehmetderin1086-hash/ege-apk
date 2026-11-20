#!/usr/bin/env python3
"""Colab'dan indirilen doğrulanmış paket parçalarını güvenle birleştir.

Örnek:
    uv run python scripts/reassemble_colab_parts.py \
      ~/Downloads/musfik_kenter_parts ~/Downloads/musfik_kenter.zip

``manifest.json`` her parça ile birleşik ZIP için SHA-256 içerir. Bu araç
eksik veya bozulmuş veriyi hedefe yazmadan önce durdurur; tamamlanmış hedefi
atomik olarak değiştirir.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path


BUFFER_SIZE = 1024 * 1024


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while data := source.read(BUFFER_SIZE):
            digest.update(data)
    return digest.hexdigest()


def reassemble(parts_dir: Path, destination: Path) -> Path:
    """Manifesti denetle, parçaları birleştir, birleşik ZIP'i doğrula."""
    parts_dir = parts_dir.expanduser().resolve()
    destination = destination.expanduser().resolve()
    manifest_path = parts_dir / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise ValueError(f"Manifest bulunamadı: {manifest_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"Manifest okunamadı: {manifest_path}") from error

    parts = manifest.get("parts")
    if not isinstance(parts, list) or not parts:
        raise ValueError("Manifestte geçerli parça listesi yok")
    if not isinstance(manifest.get("archive_bytes"), int) or not manifest.get("archive_sha256"):
        raise ValueError("Manifestte birleşik arşiv doğrulaması yok")

    destination.parent.mkdir(parents=True, exist_ok=True)
    staged = destination.with_name(f".{destination.name}.partial")
    try:
        with staged.open("wb") as target:
            for part in parts:
                name = part.get("name")
                expected_bytes = part.get("bytes")
                expected_hash = part.get("sha256")
                if not isinstance(name, str) or Path(name).name != name:
                    raise ValueError("Manifestte geçersiz parça adı")
                if not isinstance(expected_bytes, int) or not isinstance(expected_hash, str):
                    raise ValueError(f"{name}: parça doğrulaması eksik")
                source_path = parts_dir / name
                if not source_path.is_file():
                    raise ValueError(f"{name}: eksik parça")
                if source_path.stat().st_size != expected_bytes:
                    raise ValueError(f"{name}: beklenmeyen dosya boyutu")
                if sha256_file(source_path) != expected_hash:
                    raise ValueError(f"{name}: SHA-256 uyuşmuyor")
                with source_path.open("rb") as source:
                    while data := source.read(BUFFER_SIZE):
                        target.write(data)
            target.flush()
            os.fsync(target.fileno())

        if staged.stat().st_size != manifest["archive_bytes"]:
            raise ValueError("Birleşik arşiv boyutu uyuşmuyor")
        if sha256_file(staged) != manifest["archive_sha256"]:
            raise ValueError("Birleşik arşiv SHA-256 uyuşmuyor")
        staged.replace(destination)
    except Exception:
        staged.unlink(missing_ok=True)
        raise
    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("parts_dir", type=Path, help="manifest.json ve parçaların klasörü")
    parser.add_argument("destination", type=Path, help="oluşturulacak doğrulanmış ZIP")
    args = parser.parse_args()
    print(reassemble(args.parts_dir, args.destination))


if __name__ == "__main__":
    main()
