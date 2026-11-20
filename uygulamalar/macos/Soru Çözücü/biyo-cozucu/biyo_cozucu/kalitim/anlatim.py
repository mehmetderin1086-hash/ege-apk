"""Deterministik hesabı Türkçe çözüm adımlarına çevirir.

Saf şablon — model çağırmaz. Neden gerekli: çözücü doğru cevabı bulsa bile
öğretmene "cevap C" demek yetmez, GEREKÇE lazım. Bu modül olmadan kalıtım
yolu ile üretilen çözümler adımsız kalırdı ve `degerlendirme.cozum_puanla`
adım örtüşmesini sıfır sayardı.

Model isteğe bağlı olarak bu adımları düzyazıya çevirebilir (`cikarim`
katmanında), ama CEVABI DEĞİŞTİREMEZ — cevap hesaptan gelir ve çağrıdan
önce sabitlenir.
"""

from __future__ import annotations

from fractions import Fraction

from .punnett import HesapSonucu
from .tanim import Caprazlama, _alellere_bol

_TUR_BASLIGI = {
    "olasilik": "Olasılık hesabı",
    "fenotip_orani": "Fenotip oranı",
    "genotip_orani": "Genotip oranı",
    "cesit_sayisi": "Çeşit sayısı",
    "gamet_cesidi": "Gamet çeşidi",
    "gamet_olasiligi": "Gamet olasılığı",
    "kromozom_sayisi": "Kromozom sayısı",
    "kontrol_caprazi": "Kontrol çaprazı",
}


def _birey_ozeti(caprazlama: Caprazlama) -> str:
    parcalar = []
    for birey in caprazlama.ebeveynler:
        genotip = " ".join(
            birey.genotip.get(k.ad, "") for k in caprazlama.lokuslar
            if birey.genotip.get(k.ad)
        )
        etiket = birey.etiket or ("dişi" if birey.cinsiyet == "disi" else
                                  "erkek" if birey.cinsiyet == "erkek" else "birey")
        parcalar.append(f"{etiket}: {genotip}" if genotip else etiket)
    return " × ".join(parcalar)


def _lokus_ozeti(caprazlama: Caprazlama) -> str:
    parcalar = []
    for lokus in caprazlama.lokuslar:
        nitelik = []
        if lokus.baskinlik != "tam":
            nitelik.append({"eksik": "eksik baskın", "es": "eş baskın",
                            "coklu_alel": "çok alelli",
                            "kan_grubu": "kan grubu"}.get(lokus.baskinlik, lokus.baskinlik))
        if lokus.konum != "otozom":
            nitelik.append(f"{lokus.konum.upper()}'e bağlı")
        ek = f" ({', '.join(nitelik)})" if nitelik else ""
        parcalar.append(f"{lokus.ad}: {'/'.join(lokus.aleller)}{ek}")
    return "; ".join(parcalar)


def _deger_metni(deger: object) -> str:
    if isinstance(deger, Fraction):
        if deger.denominator == 1:
            return str(deger.numerator)
        return f"{deger.numerator}/{deger.denominator}"
    return str(deger)


def adimlar(caprazlama: Caprazlama, sonuc: HesapSonucu) -> list[str]:
    """Hesabın Türkçe adım listesi (en fazla 6 — istemdeki sınırla aynı)."""
    satirlar: list[str] = []

    lokuslar = _lokus_ozeti(caprazlama)
    if lokuslar:
        satirlar.append(f"Karakterler — {lokuslar}.")

    bireyler = _birey_ozeti(caprazlama)
    if bireyler:
        satirlar.append(f"Çaprazlama: {bireyler}.")

    if caprazlama.bagli_gruplar:
        gruplar = ", ".join("-".join(g) for g in caprazlama.bagli_gruplar)
        satirlar.append(f"Bağlı genler ({gruplar}) aynı kromozomda taşınır.")

    # Çözücünün kendi ürettiği hesap adımları (dağılım, çarpım, koşul).
    satirlar.extend(sonuc.adimlar)

    if sonuc.deger is not None:
        baslik = _TUR_BASLIGI.get(caprazlama.istek.tur, "Sonuç")
        satirlar.append(f"{baslik}: {_deger_metni(sonuc.deger)}.")
    elif sonuc.oran:
        satirlar.append(f"Oran: {':'.join(str(o) for o in sonuc.oran)}.")

    for varsayim in sonuc.varsayimlar:
        satirlar.append(f"Not: {varsayim}")

    # İstemdeki 6 adım sınırıyla aynı: çözüm biçimi kaynaktan kaynağa
    # değişmemeli, yoksa model few-shot'ta gördüğünden farklı bir şey üretir.
    if len(satirlar) > 6:
        satirlar = [*satirlar[:5], satirlar[-1]]
    return satirlar


def dagilim_ozeti(sonuc: HesapSonucu, *, azami: int = 6) -> str:
    """Dağılımı okunabilir tek satıra indirger — uyarı/günlük metni için."""
    if not sonuc.dagilim:
        return ""
    ogeler = sorted(sonuc.dagilim.items(), key=lambda o: -o[1])[:azami]
    return " · ".join(f"{a}: {_deger_metni(p)}" for a, p in ogeler)


def genotip_okunur(genotip: str, lokus) -> str:
    """Genotipi alel alel ayırıp okunur hâle getirir ("XRXr" → "XR Xr")."""
    return " ".join(_alellere_bol(genotip, lokus))
