#!/usr/bin/env python3
"""Guyton Colab OCR JSONL çıktısını Soru Çözücü kitap hafızasına aktar."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from biyo_cozucu.depo import Depo
from biyo_cozucu.modeller import Pasaj
from biyo_cozucu.veri.kitap import ASGARI_SAYFA_KARAKTERI, paragraflara_bol


def aktar(
    jsonl: Path,
    veritabani: Path,
    *,
    kaynak: str,
    beklenen_sayfa: int,
) -> tuple[int, int, int, int, list[int]]:
    """Kayıtları aktar ve (eklenen, yinelenen, boş, hatalı, eksik) döndür."""
    depo = Depo(veritabani)
    eklenen = yinelenen = bos = hatali = 0
    sayfalar: set[int] = set()

    with jsonl.open(encoding="utf-8") as dosya:
        for satir_no, satir in enumerate(dosya, 1):
            if not satir.strip():
                continue
            try:
                kayit = json.loads(satir)
                sayfa = int(kayit["page"])
                metin = str(kayit.get("text", ""))
            except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
                raise ValueError(f"Geçersiz JSONL satırı {satir_no}: {exc}") from exc
            if not 1 <= sayfa <= beklenen_sayfa:
                raise ValueError(f"Beklenmeyen sayfa {sayfa}; aralık 1-{beklenen_sayfa}")
            if sayfa in sayfalar:
                raise ValueError(f"Yinelenen sayfa kaydı: {sayfa}")
            sayfalar.add(sayfa)
            if kayit.get("error"):
                hatali += 1
                continue
            if len(metin.strip()) < ASGARI_SAYFA_KARAKTERI:
                bos += 1
                continue
            for govde in paragraflara_bol(metin):
                kimlik = depo.pasaj_ekle(
                    Pasaj(metin=govde, kaynak=kaynak, sayfa=sayfa)
                )
                if kimlik is None:
                    yinelenen += 1
                else:
                    eklenen += 1

    eksik = sorted(set(range(1, beklenen_sayfa + 1)) - sayfalar)
    return eklenen, yinelenen, bos, hatali, eksik


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--beklenen-sayfa", type=int, required=True)
    parser.add_argument(
        "--veritabani",
        type=Path,
        default=Path.home() / ".biyo-cozucu/biyo.db",
    )
    parser.add_argument("--kaynak", default="Guyton ve Hall Tıbbi Fizyoloji")
    args = parser.parse_args()

    eklenen, yinelenen, bos, hatali, eksik = aktar(
        args.jsonl,
        args.veritabani,
        kaynak=args.kaynak,
        beklenen_sayfa=args.beklenen_sayfa,
    )
    print(
        f"eklenen pasaj: {eklenen} · yinelenen: {yinelenen} · "
        f"boş/kısa sayfa: {bos} · hatalı: {hatali} · eksik: {len(eksik)}"
    )
    if eksik:
        print("Eksik sayfalar:", ", ".join(map(str, eksik[:50])))
    return 0 if not eksik and not hatali else 2


if __name__ == "__main__":
    raise SystemExit(main())
