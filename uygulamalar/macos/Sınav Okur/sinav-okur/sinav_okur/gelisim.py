"""Öğrencinin sınavlar arası gelişimi.

Kâğıtlar `kagit.ogrenci_kimlik` ile kalıcı öğrenci kayıtlarına bağlandıktan
sonra aynı öğrencinin farklı sınavlardaki sonuçları yan yana getirilebilir.
Bağlama otomatik yapılmaz — bkz. ``Depo.ogrencileri_esle``.
"""

from __future__ import annotations

import statistics


def ogrenci_serisi(depo, ogrenci_kimlik: int) -> dict:
    """Bir öğrencinin sınav sınav yüzde serisi ve eğilimi."""
    ogrenci = depo.ogrenci(ogrenci_kimlik)
    if ogrenci is None:
        return {}
    noktalar = []
    for kagit in depo.ogrenci_kagitlari(ogrenci_kimlik):
        toplam, maxp = depo.kagit_toplam(kagit["id"])
        if not maxp:
            continue
        noktalar.append(
            {
                "kagit_id": kagit["id"],
                "sinav_kimlik": kagit["sinav_kimlik"],
                "sinav_baslik": kagit["sinav_baslik"] or kagit["sinav_kimlik"],
                "tarih": kagit["olusturuldu"],
                "toplam": round(toplam, 2),
                "max": round(maxp, 2),
                "yuzde": round(toplam / maxp * 100, 1),
                "onaylandi": bool(kagit["onaylandi"]),
            }
        )
    yuzdeler = [n["yuzde"] for n in noktalar]
    # Eğilim yalnız ≥2 sınavda anlamlı; tek sınavlı öğrenci trend üretmez.
    egilim = (
        round(yuzdeler[-1] - yuzdeler[0], 1) if len(yuzdeler) >= 2 else None
    )
    return {
        "ogrenci": ogrenci,
        "noktalar": noktalar,
        "ortalama": round(statistics.mean(yuzdeler), 1) if yuzdeler else None,
        "egilim": egilim,
        "sinav_sayisi": len(noktalar),
    }


def sinif_gelisimi(depo, sinif: str | None = None) -> dict:
    """Öğrenci × sınav matrisi ve bağlanmamış kâğıt uyarısı."""
    seriler = []
    for ogrenci in depo.ogrenciler(sinif):
        seri = ogrenci_serisi(depo, ogrenci["id"])
        if seri.get("noktalar"):
            seriler.append(seri)
    sinav_kimlikleri: list[str] = []
    for seri in seriler:
        for nokta in seri["noktalar"]:
            if nokta["sinav_kimlik"] not in sinav_kimlikleri:
                sinav_kimlikleri.append(nokta["sinav_kimlik"])
    satirlar = []
    for seri in seriler:
        yuzdeler = {n["sinav_kimlik"]: n["yuzde"] for n in seri["noktalar"]}
        satirlar.append(
            {
                "ogrenci": seri["ogrenci"],
                "yuzdeler": [yuzdeler.get(k) for k in sinav_kimlikleri],
                "ortalama": seri["ortalama"],
                "egilim": seri["egilim"],
            }
        )
    satirlar.sort(key=lambda s: (s["ogrenci"]["ad"] or "", s["ogrenci"]["soyad"] or ""))
    baglanmamis = sum(
        1 for k in depo.kagitlar() if k["ogrenci_kimlik"] is None
    )
    return {
        "sinavlar": sinav_kimlikleri,
        "satirlar": satirlar,
        "baglanmamis": baglanmamis,
    }
