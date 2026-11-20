#!/usr/bin/env python3
"""Gerçek soru arşivinden tekrarlanabilir 50-görsellik kör test dilimi kur.

Manifest yalnız soru imzalarını taşır. Beklenen cevaplar, ``--test-jsonl``
çıktısında bulunur fakat değerlendirme sırasında modele verilmez;
``kor_kosu`` bunları ancak üretilen cevap geldikten sonra puanlar.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

from biyo_cozucu.depo import Depo
from biyo_cozucu.gorsel_zeka import siniflandir
from biyo_cozucu.modeller import Ornek
from biyo_cozucu.olcum import Dilim


def _adaylar(depo: Depo, gorsel_dizini: Path) -> list[Ornek]:
    sonuc: list[Ornek] = []
    for ornek in depo.ornekler():
        if not ornek.gorsel or not ornek.cevap:
            continue
        if not (gorsel_dizini / f"{ornek.gorsel}.png").is_file():
            continue
        sonuc.append(ornek)
    return sonuc


def _sec(ornekler: list[Ornek], adet: int) -> list[Ornek]:
    """Açık görsel bağımlıları öne al, kalanı tür dengesiyle tamamla."""
    gerekli: list[Ornek] = []
    kalan: list[Ornek] = []
    for ornek in ornekler:
        karar = siniflandir(ornek.soru, ornek.secenekler, gorsel_var=True)
        (gerekli if karar.gerekli else kalan).append(ornek)

    oncelik = {
        "grafik_yorumlama": 0,
        "kalitim_hesabi": 1,
        "deney_kurgusu": 2,
        "siniflandirma": 3,
        "mekanizma_aciklama": 4,
    }
    kalan.sort(key=lambda o: (oncelik.get(o.cozum_turu, 9), o.id or 0))
    secilen = (gerekli + kalan)[:adet]
    if len(secilen) < adet:
        raise SystemExit(f"Yalnız {len(secilen)} uygun gerçek görselli soru bulundu.")
    return secilen


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--veri", type=Path, default=Path.home() / ".biyo-cozucu")
    p.add_argument("--adet", type=int, default=50)
    p.add_argument("--ad", default="dilim-gorsel-50-v2")
    p.add_argument("--test-jsonl", type=Path, required=True)
    a = p.parse_args()

    depo = Depo(a.veri / "biyo.db")
    try:
        adaylar = _adaylar(depo, a.veri / "gorseller")
    finally:
        depo.kapat()

    manifest = Path.cwd() / "olcumler" / f"{a.ad}.json"
    if manifest.is_file():
        dilim = Dilim.yukle(manifest)
        secilen, eksik = dilim.cozumle(adaylar)
        if eksik or len(secilen) != a.adet:
            raise SystemExit(
                f"Dondurulmuş dilim çözülemedi: bulunan={len(secilen)} eksik={len(eksik)}"
            )
    else:
        secilen = _sec(adaylar, a.adet)
        dilim = Dilim.ornekelerden(
            secilen,
            a.ad,
            aciklama=(
                "Gerçek arşivden, dosyası ve cevap anahtarı mevcut 50 görselli soru; "
                "açık görsel bağımlılar önce, kalanlar tür dengeli."
            ),
        )
        manifest = dilim.yaz(Path.cwd())
    a.test_jsonl.parent.mkdir(parents=True, exist_ok=True)
    a.test_jsonl.write_text(
        "".join(json.dumps(asdict(o), ensure_ascii=False) + "\n" for o in secilen),
        encoding="utf-8",
    )
    print(f"manifest={manifest} test={a.test_jsonl} adet={len(secilen)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
