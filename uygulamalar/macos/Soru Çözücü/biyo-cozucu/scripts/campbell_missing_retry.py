#!/usr/bin/env python3
"""Campbell entegrasyonunda pasajsız kalan sayfaları bir kez daha OCR'la.

Ana koşu uzun olduğu için tekil OCR boşları gerçek boş sayfalarla karışabilir.
Bu yardımcı, veritabanında pasajı olmayan sayfaları aynı Surya arka ucuyla toplu
okur, yeterli metin dönenleri ekler ve her kalan sayfa için denetim kaydı yazar.
"""

from __future__ import annotations

import argparse
import json
import sqlite3
from pathlib import Path

import pypdfium2

from biyo_cozucu.depo import Depo
from biyo_cozucu.modeller import Pasaj
from biyo_cozucu.veri.kitap import (
    ASGARI_SAYFA_KARAKTERI,
    _grubu_oku,
    paragraflara_bol,
)


def _eksik_sayfalar(veritabani: Path, kaynak: str, son: int) -> list[int]:
    with sqlite3.connect(veritabani) as baglanti:
        kayitli = {
            int(satir[0])
            for satir in baglanti.execute(
                "SELECT DISTINCT sayfa FROM pasaj "
                "WHERE aktif=1 AND kaynak=? AND sayfa BETWEEN 1 AND ?",
                (kaynak, son),
            )
        }
    return sorted(set(range(1, son + 1)) - kayitli)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("--veritabani", type=Path, required=True)
    parser.add_argument("--kaynak", default="Campbell Biyoloji")
    parser.add_argument("--son", type=int, default=1101)
    parser.add_argument("--ocr-motoru", default="surya")
    parser.add_argument("--denetim", type=Path, required=True)
    args = parser.parse_args()

    eksikler = _eksik_sayfalar(args.veritabani, args.kaynak, args.son)
    depo = Depo(args.veritabani)
    belge = pypdfium2.PdfDocument(str(args.pdf))
    kayitlar: list[dict[str, object]] = []
    hata = 0
    eklenen = 0

    try:
        for bas in range(0, len(eksikler), 4):
            grup = eksikler[bas : bas + 4]
            try:
                okunanlar = _grubu_oku(
                    belge,
                    grup,
                    ocr="zorla",
                    ocr_motoru=args.ocr_motoru,
                )
            except Exception as exc:  # noqa: BLE001 - tek grup diğer eksikleri engellemesin
                hata += len(grup)
                for sayfa in grup:
                    kayitlar.append(
                        {
                            "page": sayfa,
                            "length": 0,
                            "inserted": 0,
                            "error": f"{type(exc).__name__}: {exc}",
                        }
                    )
                continue

            for sayfa, metin, _ocr_kullanildi in okunanlar:
                govdeler = (
                    paragraflara_bol(metin)
                    if len(metin.strip()) >= ASGARI_SAYFA_KARAKTERI
                    else []
                )
                sayfa_eklenen = 0
                for govde in govdeler:
                    if depo.pasaj_ekle(
                        Pasaj(metin=govde, kaynak=args.kaynak, sayfa=sayfa)
                    ) is not None:
                        sayfa_eklenen += 1
                eklenen += sayfa_eklenen
                kayitlar.append(
                    {
                        "page": sayfa,
                        "length": len(metin.strip()),
                        "inserted": sayfa_eklenen,
                        "error": "",
                    }
                )
    finally:
        belge.close()

    args.denetim.parent.mkdir(parents=True, exist_ok=True)
    gecici = args.denetim.with_suffix(args.denetim.suffix + ".tmp")
    gecici.write_text(
        "".join(json.dumps(kayit, ensure_ascii=False) + "\n" for kayit in kayitlar),
        encoding="utf-8",
    )
    gecici.replace(args.denetim)

    kalan = _eksik_sayfalar(args.veritabani, args.kaynak, args.son)
    print(
        f"Yeniden OCR: {len(eksikler)} sayfa · eklenen pasaj: {eklenen} · "
        f"hata: {hata} · pasajsız kalan: {len(kalan)}"
    )
    return 1 if hata else 0


if __name__ == "__main__":
    raise SystemExit(main())
