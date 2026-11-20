"""Sınav kâğıdının üst bilgisinden öğrenci kimliğini yerel OCR ile çıkarır.

Kimlik OCR'ı notlandırmadan ayrı tutulur: ad/numara hatası puanı etkilemez ve
emin olunmayan alanlar kesin bilgi gibi sunulmaz. Varsayılan Apple Vision
tanıyıcıda iki farklı görüntü hazırlığı karşılaştırılarak bir uzlaşma güveni
hesaplanır.
"""

from __future__ import annotations

import re
from difflib import SequenceMatcher
from typing import Any

import cv2
import numpy as np

from .htr import Taniyici

_AD_SOYAD = re.compile(
    r"\b(?:ad[ıi]?\s*soyad[ıi]?|ad\s*[-/]\s*soyad)\b\s*[:.;-]*\s*(.*)",
    re.IGNORECASE,
)
_SINIF_NO = re.compile(
    r"\b(?:s[ıi]n[ıi]f[ıi]?)(?:\s*/\s*(?:no|numara(?:s[ıi])?))?\b"
    r"\s*[:.;-]*\s*(.*)",
    re.IGNORECASE,
)
_NO = re.compile(
    r"\b(?:ö[ğg]renci\s*)?(?:okul\s*)?(?:no|numara(?:s[ıi])?)\b"
    r"\s*[:.;-]*\s*([0-9OIl|]{1,20})",
    re.IGNORECASE,
)
_SINIF = re.compile(r"([0-9gq])\s*[/.-]\s*([A-Za-zÇĞİÖŞÜçğıöşü])")
_EK_ALAN = re.compile(
    r"^\s*(tarih|ders|şube|sube|grup|kitapçık|kitapcik)\s*[:.;-]\s*(.+)$",
    re.IGNORECASE,
)


def _temiz_deger(metin: str) -> str:
    metin = re.sub(r"[.…·_]{2,}", " ", metin)
    metin = re.sub(r"^[^0-9A-Za-zÇĞİÖŞÜçğıöşü]+", "", metin)
    metin = re.sub(r"[^0-9A-Za-zÇĞİÖŞÜçğıöşü/' -]+", " ", metin)
    return re.sub(r"\s+", " ", metin).strip(" .:;-_/")


def _ad_soyad_ayir(deger: str) -> tuple[str, str]:
    deger = _temiz_deger(deger)
    # Bir sonraki alan yanlışlıkla aynı OCR satırına birleştiyse burada kes.
    deger = re.split(
        r"\b(?:s[ıi]n[ıi]f|no|numara|aç[ıi]klama)\b",
        deger,
        maxsplit=1,
        flags=re.IGNORECASE,
    )[0].strip()
    parcalar = [
        p.strip("/'").title()
        for p in deger.split()
        if len(p.strip("/'")) >= 2
    ]
    if not parcalar:
        return "", ""
    if len(parcalar) == 1:
        return parcalar[0], ""
    return " ".join(parcalar[:-1]), parcalar[-1]


def _numara_duzelt(deger: str) -> str:
    ceviri = str.maketrans({"O": "0", "I": "1", "l": "1", "|": "1"})
    return "".join(c for c in deger.translate(ceviri) if c.isdigit())[:20]


def _sinif_ve_no(deger: str) -> tuple[str, str, str]:
    eslesme = _SINIF.search(deger)
    if not eslesme:
        return "", "", ""
    seviye = eslesme.group(1)
    duzeltme = ""
    if seviye.casefold() in {"g", "q"}:
        seviye = "9"
        duzeltme = "Sınıf rakamı OCR benzerliğinden 9 olarak düzeltildi."
    sube = eslesme.group(2).upper()
    kalan = deger[eslesme.end():]
    no_eslesme = re.search(r"(?:no\s*[:.-]?\s*)?([0-9OIl|]{1,20})", kalan, re.I)
    numara = _numara_duzelt(no_eslesme.group(1)) if no_eslesme else ""
    return seviye, sube, numara or "", duzeltme


def _metni_cozumle(metin: str) -> dict[str, Any]:
    sonuc: dict[str, Any] = {
        "ad": "",
        "soyad": "",
        "numara": "",
        "sinif": "",
        "sube": "",
        "ek_alanlar": {},
        "uyarilar": [],
    }
    satirlar = [re.sub(r"\s+", " ", s).strip() for s in metin.splitlines() if s.strip()]
    for satir in satirlar:
        if not sonuc["ad"]:
            ad_eslesme = _AD_SOYAD.search(satir)
            if ad_eslesme:
                sonuc["ad"], sonuc["soyad"] = _ad_soyad_ayir(ad_eslesme.group(1))
        sinif_eslesme = _SINIF_NO.search(satir)
        if sinif_eslesme and not sonuc["sinif"]:
            sinif, sube, numara, duzeltme = _sinif_ve_no(sinif_eslesme.group(1))
            sonuc["sinif"], sonuc["sube"] = sinif, sube
            if numara:
                sonuc["numara"] = numara
            if duzeltme:
                sonuc["uyarilar"].append(duzeltme)
        if not sonuc["numara"]:
            no_eslesme = _NO.search(satir)
            if no_eslesme:
                sonuc["numara"] = _numara_duzelt(no_eslesme.group(1))
            else:
                # Kurşun kalemde "no:9" Vision tarafından "nai9" gibi
                # okunabiliyor; etiket ile rakam yine aynı kısa satırdaysa koru.
                bozuk_no = re.search(r"\bn[oa]\D{0,3}(\d{1,20})\b", satir, re.I)
                if bozuk_no:
                    sonuc["numara"] = bozuk_no.group(1)
        ek = _EK_ALAN.match(satir)
        if ek:
            sonuc["ek_alanlar"][ek.group(1).casefold()] = _temiz_deger(ek.group(2))
        norm = satir.casefold().replace("\u0307", "")
        if (
            "okulu" in norm or "lisesi" in norm or "üniversitesi" in norm
        ) and "okul" not in sonuc["ek_alanlar"]:
            sonuc["ek_alanlar"]["okul"] = satir
        if (
            ("sınav" in norm or "sinav" in norm)
            and "adı soyadı" not in norm
            and "sinav_basligi" not in sonuc["ek_alanlar"]
        ):
            sonuc["ek_alanlar"]["sinav_basligi"] = satir
    return sonuc


def _alan_guveni(adaylar: list[str], tanima_guvenleri: list[float]) -> float:
    dolu = [a.casefold().strip() for a in adaylar if a.strip()]
    if not dolu:
        return 0.0
    temel = min(0.85, max(tanima_guvenleri or [0.5]))
    if len(dolu) == 1:
        return round(temel * 0.62, 3)
    benzerlik = max(
        SequenceMatcher(None, a, b).ratio()
        for i, a in enumerate(dolu)
        for b in dolu[i + 1:]
    )
    return round(min(0.96, 0.35 + 0.61 * benzerlik) * temel, 3)


def kimlik_bilgisi_oku(
    sayfalar: list[np.ndarray],
    taniyici: Taniyici,
    dpi: int = 300,
) -> dict[str, Any]:
    """En fazla dört sayfanın üst bilgisini okuyup öğrenci bütünlüğünü denetle."""
    okumalar: list[tuple[dict[str, Any], float, str]] = []
    sayfa_kimlikleri: list[dict[str, Any]] = []
    from .kalite import kursun_kalem_gri

    for sayfa in sayfalar[:4]:
        h, w = sayfa.shape[:2]
        ust = sayfa[: max(1, round(h * 0.32)), :].copy()
        varyantlar = [ust]
        # Vision tüm satırları okuyabildiği için eşiklenmiş ikinci görüş,
        # özellikle kurşun kalem ad/numarada uzlaşma kanıtı sağlar.
        if taniyici.__class__.__name__ == "VisionTaniyici":
            gri = kursun_kalem_gri(ust)
            ikili = cv2.threshold(
                gri, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
            )[1]
            varyantlar.append(cv2.cvtColor(ikili, cv2.COLOR_GRAY2BGR))
        for varyant in varyantlar:
            try:
                okuma = taniyici.kutu_taniy(varyant, dpi)
            except Exception:
                continue
            if not okuma.metin.strip():
                continue
            cozum = _metni_cozumle(okuma.metin)
            okumalar.append((cozum, float(okuma.guven), okuma.metin))
            if cozum["ad"] or cozum["numara"] or cozum["sinif"]:
                sayfa_kimlikleri.append(
                    {**cozum, "guven": float(okuma.guven)}
                )

    if not okumalar:
        return {
            "ad": "", "soyad": "", "numara": "", "sinif": "", "sube": "",
            "guven": 0.0, "alan_guvenleri": {}, "ek_alanlar": {},
            "uyarilar": ["Kâğıtta öğrenci kimlik alanı otomatik bulunamadı."],
            "incele": True, "ham_metinler": [],
        }

    alanlar = ("ad", "soyad", "numara", "sinif", "sube")
    alan_guvenleri: dict[str, float] = {}
    secilen: dict[str, str] = {}
    for alan in alanlar:
        adaylar = [str(o[0].get(alan, "")) for o in okumalar]
        dolu = [(i, a) for i, a in enumerate(adaylar) if a]
        if not dolu:
            secilen[alan] = ""
            alan_guvenleri[alan] = 0.0
            continue
        # En çok diğer okumaya benzeyen değer uzlaşma adayıdır.
        en_iyi_i, en_iyi = max(
            dolu,
            key=lambda x: sum(
                SequenceMatcher(None, x[1].casefold(), b.casefold()).ratio()
                for _j, b in dolu
            ),
        )
        secilen[alan] = en_iyi
        alan_guvenleri[alan] = _alan_guveni(
            [a for _i, a in dolu],
            [okumalar[i][1] for i, _a in dolu],
        )

    ek_alanlar: dict[str, str] = {}
    uyarilar: list[str] = []
    for cozum, _guven, _ham in okumalar:
        ek_alanlar.update({k: v for k, v in cozum["ek_alanlar"].items() if v})
        uyarilar.extend(cozum["uyarilar"])
    bulunan_guvenler = [
        alan_guvenleri[a] for a in alanlar if secilen[a]
    ]
    guven = min(bulunan_guvenler) if bulunan_guvenler else 0.0
    kritik_eksik = not (secilen["ad"] or secilen["numara"])
    incele = kritik_eksik or guven < 0.72
    if incele:
        uyarilar.append(
            "Öğrenci kimliği düşük güvenli veya eksik; ad, soyad, numara ve "
            "sınıf/şube öğretmen tarafından doğrulanmalıdır."
        )
    from .ogrenci import kimlikler_uyumlu

    uyumlu, uyum_uyarisi = kimlikler_uyumlu(sayfa_kimlikleri)
    if not uyumlu:
        incele = True
        guven = min(guven, 0.25)
        uyarilar.append(uyum_uyarisi)
    return {
        **secilen,
        "guven": round(guven, 3),
        "alan_guvenleri": alan_guvenleri,
        "ek_alanlar": ek_alanlar,
        "uyarilar": list(dict.fromkeys(uyarilar)),
        "incele": incele,
        "ham_metinler": [ham for _c, _g, ham in okumalar],
        "sayfa_kimlikleri": sayfa_kimlikleri,
    }
