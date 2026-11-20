#!/usr/bin/env python3
"""Sınav Okur için Claude API anahtarını uygulamanın anahtar konumuna kurar.

Kaynak varsayılan olarak ``~/.config/claude-api/key`` (tek satır, 0600). Ham
anahtar hiçbir koşulda terminale yazdırılmaz. Hedef dosya 0600 izniyle geçici
dosyadan atomik taşınarak oluşturulur; başkalarınca okunabilir bir an olmaz.
Hedefte aynı anahtar varsa dokunulmaz ("doğrulandı"); farklıysa ``--degistir``
gerekir. Çalıştırma: ``uv run python scripts/claude_api_bagla.py``.
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from pathlib import Path

from sinav_okur.yapay_zeka import (
    YapayZekaHatasi,
    anahtar_biciminde_mi,
    anahtar_yolu,
    anahtari_canli_sina,
)

VARSAYILAN_KAYNAK = Path.home() / ".config" / "claude-api" / "key"


def _oku(yol: Path) -> str | None:
    try:
        return yol.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        return None


def kur(kaynak: Path, hedef: Path, *, degistir: bool = False) -> str:
    """Anahtarı hedefe kur; ``"kuruldu"`` ya da ``"doğrulandı"`` döndürür."""
    ham = _oku(kaynak)
    if ham is None:
        raise SystemExit(f"Anahtar kaynağı okunamadı: {kaynak}")
    if not anahtar_biciminde_mi(ham):
        raise SystemExit(
            "Anahtar kaynağı geçersiz biçimde (tek satır, boşluksuz ASCII "
            f"olmalı): {kaynak}"
        )
    if hedef.is_file():
        mevcut = _oku(hedef)
        if mevcut == ham:
            os.chmod(hedef, 0o600)
            return "doğrulandı"
        # Boş dosya anahtar sayılmaz; okunamayan (None) ya da farklı içerik
        # kullanıcının elindeki bir şeyi ezeceğinden açık onay ister.
        if mevcut != "" and not degistir:
            raise SystemExit(
                f"Hedefte farklı ya da okunamayan bir anahtar dosyası var: "
                f"{hedef}. Değiştirmek için --degistir verin."
            )
    hedef.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, gecici = tempfile.mkstemp(
        dir=hedef.parent, prefix=".claude-api-", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as dosya:
            dosya.write(ham + "\n")
            dosya.flush()
            os.fsync(dosya.fileno())
        os.chmod(gecici, 0o600)
        os.replace(gecici, hedef)
    except BaseException:
        Path(gecici).unlink(missing_ok=True)
        raise
    return "kuruldu"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--kaynak", type=Path, default=VARSAYILAN_KAYNAK)
    parser.add_argument(
        "--hedef", type=Path, default=None,
        help="varsayılan: uygulamanın anahtar dosyası (claude-api.key)",
    )
    parser.add_argument(
        "--degistir", action="store_true",
        help="hedefte farklı bir anahtar varsa üzerine yaz",
    )
    parser.add_argument(
        "--canli", action="store_true",
        help="anahtarı token harcamayan GET /v1/models ile Anthropic'e sına",
    )
    args = parser.parse_args(argv)

    hedef = (args.hedef or anahtar_yolu()).expanduser()
    sonuc = kur(args.kaynak.expanduser(), hedef, degistir=args.degistir)
    print(f"Claude API anahtarı {sonuc}: {hedef} (izin 0600)")
    if args.canli:
        try:
            anahtari_canli_sina(_oku(hedef) or "")
        except YapayZekaHatasi as exc:
            print(f"Canlı doğrulama başarısız: {exc}", file=sys.stderr)
            return 1
        print("Canlı doğrulama: Anthropic anahtarı kabul etti.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
