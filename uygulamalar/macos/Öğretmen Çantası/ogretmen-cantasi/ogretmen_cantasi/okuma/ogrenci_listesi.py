"""e-Okul sınıf listesinden öğrenci adlarını çıkarır.

e-Okul'un verdiği dosyada başlık satırı sabit değil ("Okul No" / "No" /
"Öğrenci No", "Adı Soyadı" / "Ad Soyad"). Başlık bulunamazsa sütunlar
içerikten tahmin edilir: numara sütunu kısa sayılardan, ad sütunu en az iki
kelimelik metinlerden oluşur.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .tablo import Tablo, baslik_satirini_bul, sutun_bul

NUMARA_BASLIKLARI = ("okul no", "öğrenci no", "ogrenci no", "numara", "no")
AD_BASLIKLARI = ("adı soyadı", "ad soyad", "adısoyadı", "ad-soyad", "isim", "öğrenci")
BASLIK_ANAHTARLARI = (*NUMARA_BASLIKLARI, *AD_BASLIKLARI, "cinsiyet", "sınıf")

# "9-A", "11/C", "10 B", "12A" gibi şube yazımları.
SUBE_KALIBI = re.compile(r"\b(9|1[0-2])\s*[-/ ]?\s*([A-ZÇĞİÖŞÜ])\b")


@dataclass
class OkunanOgrenci:
    numara: str
    ad_soyad: str


@dataclass
class ListeSonucu:
    ogrenciler: list[OkunanOgrenci] = field(default_factory=list)
    sube_adi: str = ""
    uyarilar: list[str] = field(default_factory=list)


def _ad_gibi(deger: str) -> bool:
    if len(deger) < 3 or any(k.isdigit() for k in deger):
        return False
    return len(deger.split()) >= 2


def _numara_gibi(deger: str) -> bool:
    return bool(re.fullmatch(r"\d{1,4}", deger.strip()))


def _sutunlari_tahmin_et(satirlar: list[list[str]]) -> tuple[int, int]:
    """Başlık yoksa sütunları içerikten bulur."""
    en_genis = max((len(s) for s in satirlar), default=0)
    ad_sayilari = [0] * en_genis
    numara_sayilari = [0] * en_genis
    for satir in satirlar:
        for i, hucre in enumerate(satir):
            if i >= en_genis:
                break
            if _ad_gibi(hucre):
                ad_sayilari[i] += 1
            elif _numara_gibi(hucre):
                numara_sayilari[i] += 1
    ad_sutunu = max(range(en_genis), key=lambda i: ad_sayilari[i]) if en_genis else -1
    numara_sutunu = (
        max(range(en_genis), key=lambda i: numara_sayilari[i]) if en_genis else -1
    )
    if ad_sayilari and ad_sayilari[ad_sutunu] == 0:
        ad_sutunu = -1
    if numara_sayilari and numara_sayilari[numara_sutunu] == 0:
        numara_sutunu = -1
    return numara_sutunu, ad_sutunu


def sube_adi_bul(tablo: Tablo) -> str:
    for satir in tablo.satirlar[:15]:
        for hucre in satir:
            eslesme = SUBE_KALIBI.search(hucre.upper())
            if eslesme:
                return f"{eslesme.group(1)}-{eslesme.group(2)}"
    return ""


def listeyi_coz(tablo: Tablo) -> ListeSonucu:
    sonuc = ListeSonucu(sube_adi=sube_adi_bul(tablo))
    satirlar = tablo.dolu_satirlar()
    if not satirlar:
        sonuc.uyarilar.append("Dosyada okunabilir satır yok.")
        return sonuc

    baslik_indeksi = baslik_satirini_bul(satirlar, BASLIK_ANAHTARLARI)
    if baslik_indeksi >= 0:
        basliklar = satirlar[baslik_indeksi]
        numara_sutunu = sutun_bul(basliklar, NUMARA_BASLIKLARI)
        ad_sutunu = sutun_bul(basliklar, AD_BASLIKLARI)
        govde = satirlar[baslik_indeksi + 1 :]
    else:
        numara_sutunu, ad_sutunu = -1, -1
        govde = satirlar

    if ad_sutunu < 0:
        tahmin_numara, tahmin_ad = _sutunlari_tahmin_et(govde)
        ad_sutunu = tahmin_ad
        if numara_sutunu < 0:
            numara_sutunu = tahmin_numara
        if ad_sutunu >= 0:
            sonuc.uyarilar.append(
                "Başlık satırı tanınmadı; ad sütunu içerikten tahmin edildi, kontrol edin."
            )

    if ad_sutunu < 0:
        sonuc.uyarilar.append("Ad-soyad sütunu bulunamadı. İsimleri elle yapıştırabilirsiniz.")
        return sonuc

    gorulen: set[str] = set()
    for satir in govde:
        if ad_sutunu >= len(satir):
            continue
        ad = " ".join(satir[ad_sutunu].split())
        if not _ad_gibi(ad):
            continue
        numara = satir[numara_sutunu].strip() if 0 <= numara_sutunu < len(satir) else ""
        anahtar = f"{numara}|{ad.casefold()}"
        if anahtar in gorulen:
            continue
        gorulen.add(anahtar)
        sonuc.ogrenciler.append(OkunanOgrenci(numara=numara, ad_soyad=ad))

    if not sonuc.ogrenciler:
        sonuc.uyarilar.append("Hiç öğrenci satırı okunamadı.")
    return sonuc


def metinden_coz(metin: str) -> ListeSonucu:
    """Yapıştırılan isim listesini çözer: her satır bir öğrenci."""
    sonuc = ListeSonucu()
    for ham in metin.splitlines():
        satir = " ".join(ham.split())
        if not satir:
            continue
        eslesme = re.match(r"^(\d{1,4})[\s.\-:)]+(.+)$", satir)
        if eslesme:
            numara, ad = eslesme.group(1), eslesme.group(2).strip()
        else:
            numara, ad = "", satir
        if not _ad_gibi(ad):
            sonuc.uyarilar.append(f"Ad gibi görünmedi, atlandı: {satir}")
            continue
        sonuc.ogrenciler.append(OkunanOgrenci(numara=numara, ad_soyad=ad))
    return sonuc
