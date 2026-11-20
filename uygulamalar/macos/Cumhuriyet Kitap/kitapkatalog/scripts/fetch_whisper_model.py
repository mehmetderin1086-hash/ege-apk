#!/usr/bin/env python3
"""Whisper GGML modelini TEK SEFERLİK indir (çalışma anı çevrimdışı kalır).

Kullanım:
    python scripts/fetch_whisper_model.py            # varsayılan model
    python scripts/fetch_whisper_model.py --model ggml-large-v3-turbo-q8_0.bin
    python scripts/fetch_whisper_model.py --sha256 <beklenen-özet>

Model, KITAPKATALOG_MODEL_DIR (yoksa platform veri dizini) altındaki
``whisper/`` klasörüne atomik olarak yazılır; yanına ``.sha256`` yan dosyası
bırakılır ve sonraki koşularda mevcut dosya bu özetle doğrulanır.
whisper-server çalıştırılabilir dosyası için: ``brew install whisper-cpp``
(veya KITAPKATALOG_WHISPER_SERVER ile yol verin).
"""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from kitapkatalog.config import AppPaths
from kitapkatalog.whisper_runtime import (
    DEFAULT_WHISPER_MODEL_FILENAME,
)

_BASE_URL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/"
_CHUNK = 1024 * 1024


def _sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(_CHUNK):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model",
        default=DEFAULT_WHISPER_MODEL_FILENAME,
        help="İndirilecek GGML model dosya adı",
    )
    parser.add_argument(
        "--dest",
        type=Path,
        default=None,
        help="Hedef dizin (varsayılan: <model dizini>/whisper)",
    )
    parser.add_argument(
        "--sha256",
        default=None,
        help="Beklenen SHA-256; verilirse doğrulanır, verilmezse hesaplanıp yazılır",
    )
    arguments = parser.parse_args()

    destination_dir = (
        arguments.dest if arguments.dest is not None else AppPaths.default().models / "whisper"
    )
    destination_dir.mkdir(parents=True, exist_ok=True)
    target = destination_dir / arguments.model
    sidecar = target.with_suffix(target.suffix + ".sha256")

    if target.is_file():
        digest = _sha256_of(target)
        expected = arguments.sha256 or (sidecar.read_text().strip() if sidecar.is_file() else None)
        if expected and digest != expected:
            print(f"HATA: mevcut dosya özeti uyuşmuyor: {digest} != {expected}")
            return 2
        sidecar.write_text(digest + "\n")
        print(f"Model zaten var ve doğrulandı: {target}\nSHA-256: {digest}")
        return 0

    url = _BASE_URL + arguments.model
    part = target.with_name(target.name + ".part")
    print(f"İndiriliyor: {url}\nHedef: {target}")
    digest = hashlib.sha256()
    received = 0
    with urllib.request.urlopen(url) as response, open(part, "wb") as handle:
        total = int(response.headers.get("Content-Length") or 0)
        while chunk := response.read(_CHUNK):
            handle.write(chunk)
            digest.update(chunk)
            received += len(chunk)
            if total:
                percent = received * 100 // total
                print(f"\r  %{percent} ({received // (1024 * 1024)} MB)", end="")
        handle.flush()
        os.fsync(handle.fileno())
    print()

    computed = digest.hexdigest()
    if arguments.sha256 and computed != arguments.sha256:
        part.unlink(missing_ok=True)
        print(f"HATA: SHA-256 uyuşmadı: {computed} != {arguments.sha256}")
        return 2
    os.replace(part, target)
    sidecar.write_text(computed + "\n")
    print(f"Tamamlandı: {target}\nSHA-256: {computed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
