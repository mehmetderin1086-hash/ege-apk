"""Öğrenci listesi içe aktarma ve yerel bulanık kimlik eşleştirme."""

from __future__ import annotations

import csv
import re
from pathlib import Path

from openpyxl import load_workbook
from rapidfuzz import fuzz

from .metin import eslesme_bicimi


_ALANLAR = {
    "ad": {"ad", "isim", "ogrenci adi", "öğrenci adı"},
    "soyad": {"soyad", "soyadi", "soyadı"},
    "ogrenci_no": {"no", "numara", "ogrenci no", "öğrenci no", "okul no"},
    "sinif": {"sinif", "sınıf"},
    "sube": {"sube", "şube"},
}


def _alan_adi(ham: object) -> str | None:
    norm = eslesme_bicimi(str(ham or ""))
    for alan, adlar in _ALANLAR.items():
        if norm in {eslesme_bicimi(x) for x in adlar}:
            return alan
    return None


def _satirlari_kayda_cevir(satirlar: list[list[object]]) -> list[dict]:
    if not satirlar:
        return []
    baslik = [_alan_adi(x) for x in satirlar[0]]
    if "ogrenci_no" not in baslik:
        raise ValueError("Öğrenci listesinde Numara/Öğrenci No sütunu gerekli.")
    sonuc = []
    for satir in satirlar[1:]:
        kayit = {
            alan: str(satir[i] if i < len(satir) and satir[i] is not None else "").strip()
            for i, alan in enumerate(baslik)
            if alan
        }
        if kayit.get("ogrenci_no"):
            sonuc.append(kayit)
    return sonuc


def ogrenci_listesi_oku(yol: str | Path) -> list[dict]:
    yol = Path(yol)
    if yol.suffix.casefold() in {".xlsx", ".xlsm"}:
        kitap = load_workbook(yol, read_only=True, data_only=True)
        sayfa = kitap.active
        satirlar = [list(satir) for satir in sayfa.iter_rows(values_only=True)]
        kitap.close()
        return _satirlari_kayda_cevir(satirlar)
    if yol.suffix.casefold() == ".csv":
        metin = yol.read_text(encoding="utf-8-sig")
        ornek = metin[:2048]
        try:
            ayrac = csv.Sniffer().sniff(ornek, delimiters=",;\t").delimiter
        except csv.Error:
            ayrac = ";"
        satirlar = list(csv.reader(metin.splitlines(), delimiter=ayrac))
        return _satirlari_kayda_cevir(satirlar)
    raise ValueError("Öğrenci listesi CSV veya XLSX olmalıdır.")


def ogrenci_esle(kimlik: dict, adaylar: list[dict]) -> dict | None:
    """OCR kimliğini yerel listedeki en güçlü tek adayla eşle."""
    if not adaylar:
        return None
    no = re.sub(r"\D", "", str(kimlik.get("numara", "")))
    ad_soyad = eslesme_bicimi(
        f"{kimlik.get('ad', '')} {kimlik.get('soyad', '')}".strip()
    )
    puanli = []
    for aday in adaylar:
        aday_no = re.sub(r"\D", "", str(aday.get("ogrenci_no", "")))
        aday_ad = eslesme_bicimi(
            f"{aday.get('ad', '')} {aday.get('soyad', '')}".strip()
        )
        no_skor = 100.0 if no and no == aday_no else (
            fuzz.ratio(no, aday_no) if no and aday_no else 0.0
        )
        ad_skor = fuzz.WRatio(ad_soyad, aday_ad) if ad_soyad and aday_ad else 0.0
        sinif_skor = 100.0 if (
            str(kimlik.get("sinif", "")).strip()
            and str(kimlik.get("sinif", "")).strip()
            == str(aday.get("sinif", "")).strip()
        ) else 0.0
        toplam = 0.58 * no_skor + 0.36 * ad_skor + 0.06 * sinif_skor
        puanli.append((toplam, no_skor, ad_skor, aday))
    puanli.sort(key=lambda x: x[0], reverse=True)
    en_iyi = puanli[0]
    ikinci = puanli[1][0] if len(puanli) > 1 else 0.0
    if en_iyi[0] < 64 or en_iyi[0] - ikinci < 7:
        return None
    return {
        **en_iyi[3],
        "eslesme_guveni": round(en_iyi[0] / 100, 4),
        "numara_skoru": round(en_iyi[1], 1),
        "ad_skoru": round(en_iyi[2], 1),
    }


def kimlikler_uyumlu(kimlikler: list[dict]) -> tuple[bool, str]:
    """Aynı gruba konan sayfaların farklı öğrenciye ait olma riskini bildir."""
    belirgin = [k for k in kimlikler if float(k.get("guven", 0)) >= 0.55]
    if len(belirgin) < 2:
        return True, ""
    numaralar = {
        re.sub(r"\D", "", str(k.get("numara", "")))
        for k in belirgin if str(k.get("numara", "")).strip()
    }
    if len(numaralar) > 1:
        return False, "Sayfalarda birbiriyle çelişen öğrenci numaraları bulundu."
    adlar = [
        eslesme_bicimi(f"{k.get('ad', '')} {k.get('soyad', '')}")
        for k in belirgin
    ]
    if any(fuzz.WRatio(a, b) < 55 for i, a in enumerate(adlar) for b in adlar[i + 1:]):
        return False, "Sayfalar farklı öğrencilere ait olabilir."
    return True, ""

