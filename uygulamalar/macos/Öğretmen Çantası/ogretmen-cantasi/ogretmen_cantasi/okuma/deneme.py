"""Yayınevi deneme sonuç dosyasından biyoloji netlerini çıkarır.

Yayınevleri farklı sütun adları kullanıyor; hem "Doğru/Yanlış/Boş" hem hazır
"Net" sütunu desteklenir. Net verilmemişse dörtte bir yanlış götürme kuralıyla
hesaplanır (YKS'de geçerli kural).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .tablo import Tablo, baslik_satirini_bul, sutun_bul

AD_BASLIKLARI = ("adı soyadı", "ad soyad", "isim", "öğrenci")
NUMARA_BASLIKLARI = ("okul no", "öğrenci no", "numara", "no")
DOGRU_BASLIKLARI = ("doğru", "dogru", "d")
YANLIS_BASLIKLARI = ("yanlış", "yanlis", "y")
BOS_BASLIKLARI = ("boş", "bos", "b")
NET_BASLIKLARI = ("net",)
BIYOLOJI_BASLIKLARI = ("biyoloji", "biy")

BASLIK_ANAHTARLARI = (
    *AD_BASLIKLARI,
    *DOGRU_BASLIKLARI,
    *YANLIS_BASLIKLARI,
    *NET_BASLIKLARI,
    *BIYOLOJI_BASLIKLARI,
)


@dataclass
class DenemeSatiri:
    ad_soyad: str
    numara: str = ""
    dogru: int = 0
    yanlis: int = 0
    bos: int = 0
    net: float = 0.0


@dataclass
class DenemeSonucu:
    satirlar: list[DenemeSatiri] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)


def net_hesapla(dogru: int, yanlis: int) -> float:
    """YKS kuralı: dört yanlış bir doğruyu götürür."""
    return round(max(0.0, dogru - yanlis / 4), 2)


def _sayi(deger: str) -> float:
    temiz = deger.replace(",", ".").strip()
    try:
        return float(temiz)
    except ValueError:
        return 0.0


def _tam_sayi(deger: str) -> int:
    return int(_sayi(deger))


def _biyoloji_sutunlari(basliklar: list[str]) -> dict[str, int]:
    """Çok dersli sonuç dosyasında biyoloji sütun kümesini bulur.

    Yayınevi dosyalarında her ders için ayrı D/Y/N sütunları olur ve hangisinin
    biyolojiye ait olduğu ancak üstteki ders adından anlaşılır. Biyoloji
    başlığı bulunduktan sonra sağındaki ilk üç-dört sayısal sütun o derse aittir.
    """
    for i, baslik in enumerate(basliklar):
        if any(b in baslik.casefold() for b in BIYOLOJI_BASLIKLARI):
            pencere = basliklar[i : i + 5]
            haritada: dict[str, int] = {}
            for ofset, hucre in enumerate(pencere):
                kucuk = hucre.casefold().strip()
                if kucuk in DOGRU_BASLIKLARI or "doğru" in kucuk:
                    haritada["dogru"] = i + ofset
                elif kucuk in YANLIS_BASLIKLARI or "yanlış" in kucuk:
                    haritada["yanlis"] = i + ofset
                elif kucuk in BOS_BASLIKLARI or "boş" in kucuk:
                    haritada["bos"] = i + ofset
                elif kucuk in NET_BASLIKLARI:
                    haritada["net"] = i + ofset
            if haritada:
                return haritada
    return {}


def denemeyi_coz(tablo: Tablo) -> DenemeSonucu:
    sonuc = DenemeSonucu()
    satirlar = tablo.dolu_satirlar()
    if not satirlar:
        sonuc.uyarilar.append("Dosyada okunabilir satır yok.")
        return sonuc

    baslik_indeksi = baslik_satirini_bul(satirlar, BASLIK_ANAHTARLARI)
    if baslik_indeksi < 0:
        sonuc.uyarilar.append(
            "Başlık satırı bulunamadı. Netleri elle girebilir ya da dosyanın "
            "başlık satırını içeren bölümünü gönderebilirsiniz."
        )
        return sonuc

    basliklar = satirlar[baslik_indeksi]
    ad_sutunu = sutun_bul(basliklar, AD_BASLIKLARI)
    numara_sutunu = sutun_bul(basliklar, NUMARA_BASLIKLARI)

    sutunlar = _biyoloji_sutunlari(basliklar)
    if not sutunlar:
        sutunlar = {
            "dogru": sutun_bul(basliklar, DOGRU_BASLIKLARI),
            "yanlis": sutun_bul(basliklar, YANLIS_BASLIKLARI),
            "bos": sutun_bul(basliklar, BOS_BASLIKLARI),
            "net": sutun_bul(basliklar, NET_BASLIKLARI),
        }
        sutunlar = {k: v for k, v in sutunlar.items() if v >= 0}
        if sutunlar:
            sonuc.uyarilar.append(
                "Biyoloji sütunu ayırt edilemedi; dosyadaki ilk doğru/yanlış "
                "sütunları kullanıldı. Kontrol edin."
            )

    if ad_sutunu < 0 or not sutunlar:
        sonuc.uyarilar.append("Ad ya da net sütunları bulunamadı.")
        return sonuc

    for satir in satirlar[baslik_indeksi + 1 :]:
        if ad_sutunu >= len(satir):
            continue
        ad = " ".join(satir[ad_sutunu].split())
        if len(ad) < 3 or re.fullmatch(r"[\d\s.,-]+", ad):
            continue

        def al(anahtar: str, kaynak: list[str] = satir) -> str:
            indeks = sutunlar.get(anahtar, -1)
            return kaynak[indeks] if 0 <= indeks < len(kaynak) else ""

        dogru = _tam_sayi(al("dogru"))
        yanlis = _tam_sayi(al("yanlis"))
        bos = _tam_sayi(al("bos"))
        net_metni = al("net")
        net = _sayi(net_metni) if net_metni else net_hesapla(dogru, yanlis)

        if not (dogru or yanlis or bos or net):
            continue
        sonuc.satirlar.append(
            DenemeSatiri(
                ad_soyad=ad,
                numara=satir[numara_sutunu].strip() if 0 <= numara_sutunu < len(satir) else "",
                dogru=dogru,
                yanlis=yanlis,
                bos=bos,
                net=net,
            )
        )

    if not sonuc.satirlar:
        sonuc.uyarilar.append("Hiç öğrenci sonucu okunamadı.")
    else:
        sonuc.uyarilar.append(f"{len(sonuc.satirlar)} öğrenci sonucu okundu.")
    return sonuc
