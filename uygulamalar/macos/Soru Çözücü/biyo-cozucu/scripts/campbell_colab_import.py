#!/usr/bin/env python3
"""Colab Surya OCR JSONL çıktısını Campbell pasajlarına birleştir."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from biyo_cozucu.depo import Depo
from biyo_cozucu.modeller import Pasaj
from biyo_cozucu.veri.kitap import ASGARI_SAYFA_KARAKTERI, paragraflara_bol


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jsonl", type=Path)
    parser.add_argument(
        "--veritabani",
        type=Path,
        default=Path.home() / ".biyo-cozucu/biyo.db",
    )
    parser.add_argument("--kaynak", default="Campbell Biyoloji")
    args = parser.parse_args()

    depo = Depo(args.veritabani)
    eklenen = atlanan = bos = hatali = 0
    sayfalar: set[int] = set()
    with args.jsonl.open(encoding="utf-8") as dosya:
        for satir_no, satir in enumerate(dosya, 1):
            if not satir.strip():
                continue
            try:
                kayit = json.loads(satir)
                sayfa = int(kayit["page"])
                metin = str(kayit.get("text", ""))
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
                raise ValueError(f"Geçersiz JSONL satırı {satir_no}: {exc}") from exc
            sayfalar.add(sayfa)
            if kayit.get("error"):
                hatali += 1
                continue
            if len(metin.strip()) < ASGARI_SAYFA_KARAKTERI:
                bos += 1
                continue
            for govde in paragraflara_bol(metin):
                kimlik = depo.pasaj_ekle(
                    Pasaj(metin=govde, kaynak=args.kaynak, sayfa=sayfa)
                )
                if kimlik is None:
                    atlanan += 1
                else:
                    eklenen += 1

    beklenen = set(range(141, 150)) | set(range(162, 1102))
    eksik = sorted(beklenen - sayfalar)
    print(
        f"Sayfa kaydı: {len(sayfalar)}/{len(beklenen)} · "
        f"eklenen pasaj: {eklenen} · yinelenen: {atlanan} · "
        f"boş: {bos} · hatalı: {hatali} · eksik: {len(eksik)}"
    )
    if eksik:
        print("Eksik sayfalar:", ", ".join(map(str, eksik[:50])))
    return 0 if not eksik and not hatali else 2


if __name__ == "__main__":
    raise SystemExit(main())
