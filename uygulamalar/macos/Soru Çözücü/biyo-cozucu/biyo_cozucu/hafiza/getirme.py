"""Çözüm üretiminden önceki örnek getirme adımı.

İki aşamalı: önce hibrit erişimle geniş bir aday havuzu, sonra çözüm türü ve
konu uyumuna göre yeniden sıralama. Literatürdeki tutarlı bulgu, örnek
seçiminde yalnız anlamsal benzerliğin yetersiz olduğu — aynı konudan ama farklı
muhakeme yapısındaki bir örnek modeli yanlış yola sokabiliyor.
"""

from __future__ import annotations

import re

from ..gomme import Gomlemci
from ..metin import imza as metin_imzasi
from ..metin import kirp
from ..modeller import Kanit
from .indeks import OrnekIndeksi

# "I.", "II.", "1)", "a)" gibi alt madde sınırları.
_ALT_MADDE = re.compile(r"(?:^|\n|\s)(?:[IVX]{1,4}\.|\d{1,2}[).]|[a-eçğıöşü][).])\s+")

# Çözüm türü uyumu toplamalı bir bonus değil, birincil sıralama kademesidir:
# havuza giren en zayıf aday bile en güçlünün ESIK_ORANI katı kadar yakın
# olduğundan, uyumu güvenle öne almak için bonusun bu farkı (1 - ESIK_ORANI)
# aşması gerekirdi — kademe bunu sabit seçmeden ifade eder. Konu uyumu kademe
# içinde toplamalı kalır; yapı kadar belirleyici değildir.
KONU_UYUM_BONUSU = 0.15
ESIK_ORANI = 0.42


def _sorgular(soru: str, azami_parca: int = 6) -> list[str]:
    """Uzun/çok maddeli soruyu tek sorgu yapmak erişimi tek alt maddeye kilitler.

    Bütün metnin yanına anlamlı alt maddeleri de ayrı sorgu olarak ekler.
    """
    sorgular = [soru]
    parcalar = [p.strip() for p in _ALT_MADDE.split(soru) if len(p.split()) >= 5]
    if len(parcalar) > 1:
        sorgular.extend(parcalar[1 : 1 + azami_parca])
    return sorgular


def benzer_ornekler(
    indeks: OrnekIndeksi,
    soru: str,
    *,
    gomlemci: Gomlemci | None = None,
    k: int = 3,
    cozum_turu: str | None = None,
    konu: str | None = None,
    haric_imzalar: set[str] | None = None,
    azami_cozum_karakteri: int = 1800,
) -> list[Kanit]:
    """Soruya en uygun referans örnekleri kanıt olarak döndürür."""
    if not len(indeks):
        return []

    haric = haric_imzalar or set()
    kendi_imzasi = metin_imzasi(soru)

    havuz: dict[int, float] = {}
    for sorgu in _sorgular(soru):
        sonuclar = indeks.ara(sorgu, gomlemci, k=max(k * 3, 8))
        if not sonuclar:
            continue
        en_iyi = max(sonuclar[0][1], 1e-9)
        for indeks_no, skor in sonuclar:
            oran = skor / en_iyi
            if oran < ESIK_ORANI:
                continue
            # Aynı örnek birden çok alt maddede çıkarsa en güçlü eşleşmesi kalır.
            havuz[indeks_no] = max(havuz.get(indeks_no, 0.0), oran)

    if not havuz:
        return []

    hedef_tur = (cozum_turu or "").strip()
    hedef_konu = (konu or "").strip().casefold()

    # (tür uyumu, sıralama puanı, ham benzerlik, indeks). Ham benzerlik ayrı
    # taşınır: `Kanit.skor` arayüzde "benzerlik" diye sunuluyor, konu bonusunu
    # ona katmak 1'i aşan "kosinüs" değerleri gösterirdi.
    puanli: list[tuple[int, float, float, int]] = []
    for indeks_no, oran in havuz.items():
        ornek = indeks.ornekler[indeks_no]
        if metin_imzasi(ornek.soru) in haric or metin_imzasi(ornek.soru) == kendi_imzasi:
            continue  # kendini (veya kör test sorusunu) örnek olarak gösterme
        tur_uyumu = 1 if hedef_tur and ornek.cozum_turu == hedef_tur else 0
        agirlikli = oran
        if hedef_konu and ornek.konu.casefold() == hedef_konu:
            agirlikli += KONU_UYUM_BONUSU
        puanli.append((tur_uyumu, agirlikli, oran, indeks_no))

    puanli.sort(key=lambda x: (-x[0], -x[1], x[3]))
    secilen = puanli[:k]

    # Tür etiketi kural tabanlı bir sezgiseldir ve yanılabilir; yanıldığında
    # kademe en benzer örneği listeden tümüyle düşürürdü. En az iki yer varsa
    # o örneğe son sırayı ayırarak hatanın maliyetini bir slotla sınırlıyoruz.
    if k >= 2 and len(puanli) > len(secilen):
        en_benzer = max(puanli, key=lambda x: (x[1], -x[3]))
        if en_benzer not in secilen:
            secilen = [*secilen[:k - 1], en_benzer]

    kanitlar: list[Kanit] = []
    for sira, (tur_uyumu, _agirlikli, oran, indeks_no) in enumerate(secilen, 1):
        ornek = indeks.ornekler[indeks_no]
        kanitlar.append(
            Kanit(
                etiket=f"Ö{sira}",
                ornek_id=ornek.id,
                soru=ornek.soru,
                cozum=kirp(ornek.cozum, azami_cozum_karakteri),
                konu=ornek.konu,
                cozum_turu=ornek.cozum_turu,
                cevap=ornek.cevap,
                skor=round(float(oran), 4),
                tur_uyumlu=bool(tur_uyumu),
            )
        )
    return kanitlar
