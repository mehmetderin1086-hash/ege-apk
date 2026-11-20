#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Palme AYT soru crop'larından doğrulanmış tam-sayfa YOLO verisi üretir.

Kaynak ZIP'teki ``Uxx-Txx-Sxx_Sayfa_NNN.jpg`` dosyaları, aynı kitabın PDF
sayfasının 130 dpi renderı üzerinde OpenCV ``TM_CCOEFF_NORMED`` ile aranır.
Yalnız eşik üstü, birbiriyle çakışmayan ve turkuaz soru numarası çapası
bulunabilen crop'lar kabul edilir. Herhangi bir hata bütün koşuyu durdurur;
kısmi veri seti yayınlanmaz.

Ünite 12-25 sayfaları standart eğitim manifestinin ``train`` split'ine
girer. Ünite 26-27 içeren sayfanın TAMAMI tanısal holdout'a ayrılır ve eğitim
manifestine girmez. Etiketler yalnız:

* 0: ``question_anchor``
* 1: ``question_body``

Standart dört sınıflı sözleşme manifestte korunur; sınıf 2/3 etiketi üretilmez.
Bu dosya mevcut ql_v3 veri setini okumaz veya değiştirmez.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
import warnings
import zipfile
from dataclasses import dataclass
from typing import Callable, Iterable

from PIL import Image


EGITIM_SEMA_SURUMU = "soru-kesici.question-layout-training/v1"
TANISAL_SEMA_SURUMU = "soru-kesici.question-layout-diagnostic/v1"
RAPOR_SEMA_SURUMU = "soru-kesici.palme-crop-alignment/v1"
SINIFLAR = (
    "question_anchor",
    "question_body",
    "shared_stimulus",
    "solution_or_answer",
)
YAYINEVI_GRUBU = "pub-palme-ayt-biyoloji-sb-2018"
ETIKET_KAYNAGI = "verified_crop_alignment"
URETICI_SURUMU = "1"

VARSAYILAN_DPI = 130
VARSAYILAN_CROP_DPI = 130
VARSAYILAN_ESIK = 0.68
VARSAYILAN_MAX_UYE = 5_000
VARSAYILAN_MAX_TOPLAM_BAYT = 8 * 1024**3
VARSAYILAN_MAX_UYE_BAYT = 64 * 1024**2
VARSAYILAN_MAX_PIKSEL = 30_000_000
VARSAYILAN_MAX_ORTUSME = 0.02

_AD_DESENI = re.compile(
    r"^U(?P<unite>\d{2})-T(?P<test>\d{2})-S(?P<soru>\d{2})"
    r"_Sayfa_(?P<sayfa>\d{3})\.jpe?g$",
    re.IGNORECASE,
)


class PalmeVeriHatasi(RuntimeError):
    """Veri üretimini güvenli biçimde durduran doğrulama hatası."""


@dataclass(frozen=True, order=True)
class CropKaydi:
    """ZIP içindeki tek bir doğrulanmış soru crop'u."""

    sayfa: int
    unite: int
    test: int
    soru: int
    uye_adi: str
    boyut: int
    crc: int

    @property
    def soru_id(self) -> str:
        return f"U{self.unite:02d}-T{self.test:02d}-S{self.soru:02d}"


def _sha256_dosya(yol: str) -> str:
    ozet = hashlib.sha256()
    with open(yol, "rb") as kaynak:
        for parca in iter(lambda: kaynak.read(1 << 20), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _sha256_bayt(veri: bytes) -> str:
    return hashlib.sha256(veri).hexdigest()


def _json_yaz(yol: str, veri: object) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(yol)), exist_ok=True)
    with open(yol, "w", encoding="utf-8") as hedef:
        json.dump(veri, hedef, ensure_ascii=False, indent=2, sort_keys=True)
        hedef.write("\n")


def _guvenli_uye_adi(ad: str) -> str:
    """ZIP üye adını kanonik POSIX göreli yola çevirir."""
    if not isinstance(ad, str) or not ad or "\x00" in ad:
        raise PalmeVeriHatasi("ZIP içinde boş/geçersiz üye adı")
    ad = ad.replace("\\", "/")
    if ad.startswith("/") or re.match(r"^[A-Za-z]:", ad):
        raise PalmeVeriHatasi(f"ZIP mutlak yol içeriyor: {ad!r}")
    parcalar = pathlib.PurePosixPath(ad).parts
    if not parcalar or any(p in ("", ".", "..") for p in parcalar):
        raise PalmeVeriHatasi(f"ZIP yol geçişi içeriyor: {ad!r}")
    return "/".join(parcalar)


def crop_adini_coz(ad: str) -> tuple[int, int, int, int] | None:
    """Crop basename'ini ``(ünite, test, soru, sayfa)`` olarak ayrıştırır."""
    eslesme = _AD_DESENI.fullmatch(pathlib.PurePosixPath(ad).name)
    if not eslesme:
        return None
    return tuple(
        int(eslesme.group(alan))
        for alan in ("unite", "test", "soru", "sayfa")
    )


def zip_denetle(
    zip_yolu: str,
    *,
    max_uye: int = VARSAYILAN_MAX_UYE,
    max_toplam_bayt: int = VARSAYILAN_MAX_TOPLAM_BAYT,
    max_uye_bayt: int = VARSAYILAN_MAX_UYE_BAYT,
) -> dict:
    """ZIP merkez dizinini güvenlik ve ad sözleşmesi açısından doğrular."""
    for ad, deger in (
        ("max_uye", max_uye),
        ("max_toplam_bayt", max_toplam_bayt),
        ("max_uye_bayt", max_uye_bayt),
    ):
        if not isinstance(deger, int) or isinstance(deger, bool) or deger <= 0:
            raise ValueError(f"{ad} pozitif tam sayı olmalı")
    if not os.path.isfile(zip_yolu):
        raise PalmeVeriHatasi(f"ZIP bulunamadı: {zip_yolu}")

    kayitlar: list[CropKaydi] = []
    yok_sayilan: list[str] = []
    gorulen_yollar: set[str] = set()
    gorulen_sorular: set[tuple[int, int, int, int]] = set()
    toplam = 0
    try:
        with zipfile.ZipFile(zip_yolu) as arsiv:
            uyeler = arsiv.infolist()
            if len(uyeler) > max_uye:
                raise PalmeVeriHatasi(
                    f"ZIP üye sınırını aşıyor: {len(uyeler)} > {max_uye}"
                )
            for bilgi in uyeler:
                guvenli_ad = _guvenli_uye_adi(bilgi.filename)
                yol_kimligi = guvenli_ad.casefold()
                if yol_kimligi in gorulen_yollar:
                    raise PalmeVeriHatasi(
                        f"ZIP yinelenen üye yolu içeriyor: {guvenli_ad}"
                    )
                gorulen_yollar.add(yol_kimligi)

                unix_modu = (bilgi.external_attr >> 16) & 0xFFFF
                if unix_modu and stat.S_ISLNK(unix_modu):
                    raise PalmeVeriHatasi(
                        f"ZIP sembolik bağ içeriyor: {guvenli_ad}"
                    )
                if bilgi.flag_bits & 0x1:
                    raise PalmeVeriHatasi(
                        f"ZIP şifreli üye içeriyor: {guvenli_ad}"
                    )
                if bilgi.is_dir():
                    continue
                if bilgi.file_size < 0 or bilgi.file_size > max_uye_bayt:
                    raise PalmeVeriHatasi(
                        f"ZIP üyesi boyut sınırını aşıyor: {guvenli_ad}"
                    )
                toplam += bilgi.file_size
                if toplam > max_toplam_bayt:
                    raise PalmeVeriHatasi(
                        "ZIP toplam açılmış boyut sınırını aşıyor: "
                        f"{toplam} > {max_toplam_bayt}"
                    )

                cozum = crop_adini_coz(guvenli_ad)
                uzanti = pathlib.PurePosixPath(guvenli_ad).suffix.casefold()
                if cozum is None:
                    if uzanti in (".jpg", ".jpeg"):
                        raise PalmeVeriHatasi(
                            "Ad sözleşmesine uymayan JPEG üyesi: "
                            f"{guvenli_ad}"
                        )
                    yok_sayilan.append(guvenli_ad)
                    continue
                unite, test, soru, sayfa = cozum
                mantiksal = (unite, test, soru, sayfa)
                if mantiksal in gorulen_sorular:
                    raise PalmeVeriHatasi(
                        "ZIP yinelenen mantıksal soru içeriyor: "
                        f"U{unite:02d}-T{test:02d}-S{soru:02d}, sayfa {sayfa}"
                    )
                gorulen_sorular.add(mantiksal)
                kayitlar.append(
                    CropKaydi(
                        sayfa=sayfa,
                        unite=unite,
                        test=test,
                        soru=soru,
                        uye_adi=guvenli_ad,
                        boyut=bilgi.file_size,
                        crc=bilgi.CRC,
                    )
                )
    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile) as hata:
        raise PalmeVeriHatasi(f"ZIP okunamadı: {hata}") from hata

    if not kayitlar:
        raise PalmeVeriHatasi("ZIP içinde ad sözleşmesine uyan soru JPEG'i yok")
    return {
        "kayitlar": sorted(kayitlar),
        "yok_sayilan": sorted(yok_sayilan),
        "uye_sayisi": len(gorulen_yollar),
        "crop_sayisi": len(kayitlar),
        "toplam_acilmis_bayt": toplam,
    }


def _cv2_ve_numpy():
    try:
        import cv2  # type: ignore
        import numpy as np
    except ImportError as hata:
        raise PalmeVeriHatasi(
            "OpenCV gerekli; bu projede `.venv-ml/bin/python` kullanın"
        ) from hata
    return cv2, np


def _crop_oku(
    arsiv: zipfile.ZipFile,
    kayit: CropKaydi,
    *,
    max_piksel: int,
) -> tuple[Image.Image, str]:
    try:
        veri = arsiv.read(kayit.uye_adi)
    except (OSError, KeyError, RuntimeError, zipfile.BadZipFile) as hata:
        raise PalmeVeriHatasi(
            f"ZIP üyesi okunamadı: {kayit.uye_adi}: {hata}"
        ) from hata
    if len(veri) != kayit.boyut:
        raise PalmeVeriHatasi(
            f"ZIP üye boyutu değişti: {kayit.uye_adi}"
        )
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(veri)) as acik:
                if acik.width * acik.height > max_piksel:
                    raise PalmeVeriHatasi(
                        f"Crop piksel sınırını aşıyor: {kayit.uye_adi}"
                    )
                acik.load()
                gorsel = acik.convert("RGB")
    except PalmeVeriHatasi:
        raise
    except Exception as hata:
        raise PalmeVeriHatasi(
            f"Crop görüntüsü bozuk: {kayit.uye_adi}: {hata}"
        ) from hata
    return gorsel, _sha256_bayt(veri)


def pdftoppm_sayfa_render(
    pdf_yolu: str,
    sayfa: int,
    dpi: int,
) -> Image.Image:
    """PDF'nin verilen 1-tabanlı sayfasını pdftoppm ile RGB render eder."""
    arac = shutil.which("pdftoppm")
    if not arac:
        raise PalmeVeriHatasi(
            "pdftoppm bulunamadı; renderer enjekte edin veya Poppler kurun"
        )
    if sayfa < 1:
        raise PalmeVeriHatasi(f"geçersiz PDF sayfası: {sayfa}")
    with tempfile.TemporaryDirectory(prefix="palme-render-") as gecici:
        onek = os.path.join(gecici, "sayfa")
        komut = [
            arac,
            "-f",
            str(sayfa),
            "-l",
            str(sayfa),
            "-r",
            str(dpi),
            "-png",
            "-singlefile",
            pdf_yolu,
            onek,
        ]
        try:
            sonuc = subprocess.run(
                komut,
                capture_output=True,
                text=True,
                timeout=180,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as hata:
            raise PalmeVeriHatasi(
                f"PDF sayfa {sayfa} render edilemedi: {hata}"
            ) from hata
        png = onek + ".png"
        if sonuc.returncode != 0 or not os.path.isfile(png):
            detay = (sonuc.stderr or sonuc.stdout or "").strip()[:400]
            raise PalmeVeriHatasi(
                f"PDF sayfa {sayfa} render edilemedi: {detay}"
            )
        try:
            with Image.open(png) as acik:
                acik.load()
                return acik.convert("RGB")
        except Exception as hata:
            raise PalmeVeriHatasi(
                f"PDF sayfa {sayfa} renderı okunamadı: {hata}"
            ) from hata


def _crop_olcekle(
    crop: Image.Image,
    *,
    dpi: int,
    crop_dpi: int,
) -> Image.Image:
    oran = dpi / crop_dpi
    if math.isclose(oran, 1.0, rel_tol=0.0, abs_tol=1e-12):
        return crop.copy()
    genislik = max(1, round(crop.width * oran))
    yukseklik = max(1, round(crop.height * oran))
    return crop.resize((genislik, yukseklik), Image.Resampling.LANCZOS)


def crop_eslestir(
    sayfa: Image.Image,
    crop: Image.Image,
    *,
    min_skor: float = VARSAYILAN_ESIK,
) -> dict:
    """Crop'u sayfada TM_CCOEFF_NORMED ile bulur; eşik altında hata verir."""
    if not 0 < min_skor <= 1:
        raise ValueError("min_skor 0..1 aralığında olmalı")
    if crop.width > sayfa.width or crop.height > sayfa.height:
        raise PalmeVeriHatasi(
            "crop render sayfasından büyük: "
            f"{crop.size} > {sayfa.size}"
        )
    cv2, np = _cv2_ve_numpy()
    sayfa_rgb = np.asarray(sayfa.convert("RGB"), dtype=np.uint8)
    crop_rgb = np.asarray(crop.convert("RGB"), dtype=np.uint8)
    sayfa_gri = cv2.cvtColor(sayfa_rgb, cv2.COLOR_RGB2GRAY)
    crop_gri = cv2.cvtColor(crop_rgb, cv2.COLOR_RGB2GRAY)
    if float(crop_gri.std()) < 2.0:
        raise PalmeVeriHatasi("crop eşleştirme için yeterli doku taşımıyor")
    sonuc = cv2.matchTemplate(
        sayfa_gri,
        crop_gri,
        cv2.TM_CCOEFF_NORMED,
    )
    _min_deger, max_deger, _min_yer, max_yer = cv2.minMaxLoc(sonuc)
    skor = float(max_deger)
    if not math.isfinite(skor) or skor < min_skor:
        raise PalmeVeriHatasi(
            f"crop eşleşme skoru düşük: {skor:.6f} < {min_skor:.6f}"
        )
    x0, y0 = (int(max_yer[0]), int(max_yer[1]))
    return {
        "skor": skor,
        "kutu": (x0, y0, x0 + crop.width, y0 + crop.height),
    }


def turkuaz_capa_kutusu(
    crop: Image.Image,
    *,
    hue_alt: int = 80,
    hue_ust: int = 100,
    sat_alt: int = 55,
    value_alt: int = 45,
) -> tuple[int, int, int, int]:
    """Crop sol-üstündeki turkuaz soru numarasının deterministik kutusu."""
    if not 0 <= hue_alt <= hue_ust <= 179:
        raise ValueError("OpenCV hue sınırları 0..179 içinde olmalı")
    cv2, np = _cv2_ve_numpy()
    rgb = np.asarray(crop.convert("RGB"), dtype=np.uint8)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV)
    roi_h = min(crop.height, max(32, round(crop.height * 0.12)))
    roi_w = min(crop.width, max(48, round(crop.width * 0.28)))
    roi = hsv[:roi_h, :roi_w]
    maske = cv2.inRange(
        roi,
        (hue_alt, sat_alt, value_alt),
        (hue_ust, 255, 255),
    )
    adet, _etiketler, istatistik, _merkezler = (
        cv2.connectedComponentsWithStats(maske, connectivity=8)
    )
    olcek = max(crop.width / 385.0, crop.height / 500.0, 0.5)
    min_alan = max(2, round(2 * olcek * olcek))
    parcalar = []
    for i in range(1, adet):
        x = int(istatistik[i, cv2.CC_STAT_LEFT])
        y = int(istatistik[i, cv2.CC_STAT_TOP])
        w = int(istatistik[i, cv2.CC_STAT_WIDTH])
        h = int(istatistik[i, cv2.CC_STAT_HEIGHT])
        alan = int(istatistik[i, cv2.CC_STAT_AREA])
        if alan >= min_alan:
            parcalar.append((x, y, x + w, y + h, alan))
    if not parcalar:
        raise PalmeVeriHatasi(
            "crop sol-üstünde turkuaz soru numarası çapası bulunamadı"
        )
    ilk = min(parcalar, key=lambda p: (p[1], p[0], -p[4]))
    y_sinir = ilk[1] + max(18, round(roi_h * 0.18))
    x_sinir = ilk[0] + max(48, round(roi_w * 0.65))
    secili = [
        p for p in parcalar
        if p[1] <= y_sinir and p[0] <= x_sinir
    ]
    toplam_alan = sum(p[4] for p in secili)
    if toplam_alan < max(5, round(5 * olcek * olcek)):
        raise PalmeVeriHatasi("turkuaz soru numarası çapası çok küçük")
    dolgu = max(1, round(2 * olcek))
    x0 = max(0, min(p[0] for p in secili) - dolgu)
    y0 = max(0, min(p[1] for p in secili) - dolgu)
    x1 = min(crop.width, max(p[2] for p in secili) + dolgu)
    y1 = min(crop.height, max(p[3] for p in secili) + dolgu)
    if x1 <= x0 or y1 <= y0:
        raise PalmeVeriHatasi("turkuaz çapa kutusu dejenere")
    return (x0, y0, x1, y1)


def _kutu_alani(kutu: Iterable[float]) -> float:
    x0, y0, x1, y1 = kutu
    return max(0.0, x1 - x0) * max(0.0, y1 - y0)


def _kucuk_kutu_ortusmesi(a: Iterable[float], b: Iterable[float]) -> float:
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    w = max(0.0, min(ax1, bx1) - max(ax0, bx0))
    h = max(0.0, min(ay1, by1) - max(ay0, by0))
    return w * h / max(min(_kutu_alani(a), _kutu_alani(b)), 1e-9)


def govde_kutularini_dogrula(
    sorular: list[dict],
    *,
    max_ortusme: float = VARSAYILAN_MAX_ORTUSME,
) -> None:
    """Aynı sayfadaki yinelenen veya anlamlı örtüşen gövdeleri reddeder."""
    if not 0 <= max_ortusme < 1:
        raise ValueError("max_ortusme 0..1 aralığında olmalı")
    for i, sol in enumerate(sorular):
        for sag in sorular[i + 1:]:
            oran = _kucuk_kutu_ortusmesi(
                sol["body_box"],
                sag["body_box"],
            )
            if oran > max_ortusme:
                raise PalmeVeriHatasi(
                    "aynı sayfada yinelenen/örtüşen soru kutuları: "
                    f"{sol['question_id']} ↔ {sag['question_id']} "
                    f"(küçük-kutu örtüşmesi={oran:.6f})"
                )


def _yolo_satiri(
    sinif: int,
    kutu: Iterable[float],
    genislik: int,
    yukseklik: int,
) -> str:
    x0, y0, x1, y1 = (float(v) for v in kutu)
    x0, x1 = sorted((max(0.0, min(genislik, x0)),
                     max(0.0, min(genislik, x1))))
    y0, y1 = sorted((max(0.0, min(yukseklik, y0)),
                     max(0.0, min(yukseklik, y1))))
    if x1 <= x0 or y1 <= y0:
        raise PalmeVeriHatasi("YOLO kutusu dejenere")
    cx = (x0 + x1) / (2 * genislik)
    cy = (y0 + y1) / (2 * yukseklik)
    w = (x1 - x0) / genislik
    h = (y1 - y0) / yukseklik
    return f"{sinif} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}"


def _sayfa_bolumu(sorular: list[dict]) -> str:
    uniteler = {int(s["unit"]) for s in sorular}
    bilinmeyen = sorted(u for u in uniteler if not 12 <= u <= 27)
    if bilinmeyen:
        raise PalmeVeriHatasi(
            f"eğitim politikasında tanımsız ünite: {bilinmeyen}"
        )
    # Bir sayfada hem U25 hem U26 olsa dahi sayfanın tamamı tanısala gider.
    if uniteler & {26, 27}:
        return "diagnostic_holdout"
    return "train"


def _renderer_sonucunu_rgb(sonuc: object, sayfa: int) -> Image.Image:
    if isinstance(sonuc, Image.Image):
        gorsel = sonuc.convert("RGB")
    elif isinstance(sonuc, (str, os.PathLike)):
        try:
            with Image.open(os.fspath(sonuc)) as acik:
                acik.load()
                gorsel = acik.convert("RGB")
        except Exception as hata:
            raise PalmeVeriHatasi(
                f"renderer sayfa {sayfa} çıktısı okunamadı: {hata}"
            ) from hata
    else:
        raise PalmeVeriHatasi(
            f"renderer sayfa {sayfa} için PIL.Image veya yol döndürmeli"
        )
    if gorsel.width <= 0 or gorsel.height <= 0:
        raise PalmeVeriHatasi(f"renderer sayfa {sayfa} boş görüntü döndürdü")
    return gorsel


def palme_veri_seti_uret(
    pdf_yolu: str,
    zip_yolu: str,
    cikti_dizini: str,
    *,
    dpi: int = VARSAYILAN_DPI,
    crop_dpi: int = VARSAYILAN_CROP_DPI,
    min_skor: float = VARSAYILAN_ESIK,
    max_ortusme: float = VARSAYILAN_MAX_ORTUSME,
    max_uye: int = VARSAYILAN_MAX_UYE,
    max_toplam_bayt: int = VARSAYILAN_MAX_TOPLAM_BAYT,
    max_uye_bayt: int = VARSAYILAN_MAX_UYE_BAYT,
    max_piksel: int = VARSAYILAN_MAX_PIKSEL,
    renderer: Callable[[str, int, int], object] | None = None,
) -> dict:
    """Palme AYT supplement veri setini atomik olarak üretir."""
    if not os.path.isfile(pdf_yolu):
        raise PalmeVeriHatasi(f"PDF bulunamadı: {pdf_yolu}")
    if not isinstance(dpi, int) or isinstance(dpi, bool) or dpi <= 0:
        raise ValueError("dpi pozitif tam sayı olmalı")
    if not isinstance(crop_dpi, int) or isinstance(crop_dpi, bool) \
            or crop_dpi <= 0:
        raise ValueError("crop_dpi pozitif tam sayı olmalı")
    if not isinstance(max_piksel, int) or max_piksel <= 0:
        raise ValueError("max_piksel pozitif tam sayı olmalı")
    cikti_dizini = os.path.abspath(os.fspath(cikti_dizini))
    if os.path.lexists(cikti_dizini):
        raise PalmeVeriHatasi(
            f"çıktı yolu zaten var; üzerine yazılmadı: {cikti_dizini}"
        )

    zip_raporu = zip_denetle(
        zip_yolu,
        max_uye=max_uye,
        max_toplam_bayt=max_toplam_bayt,
        max_uye_bayt=max_uye_bayt,
    )
    pdf_sha = _sha256_dosya(pdf_yolu)
    zip_sha = _sha256_dosya(zip_yolu)
    dataset_id = (
        f"palme-ayt-{pdf_sha[:12]}-{zip_sha[:12]}-dpi{dpi}"
    )
    render_fonksiyonu = renderer or pdftoppm_sayfa_render

    sayfalara_gore: dict[int, list[CropKaydi]] = {}
    for kayit in zip_raporu["kayitlar"]:
        sayfalara_gore.setdefault(kayit.sayfa, []).append(kayit)

    ebeveyn = os.path.dirname(cikti_dizini)
    os.makedirs(ebeveyn, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=".palme-veri-", dir=ebeveyn)
    train_ornekler: list[dict] = []
    tanisal_ornekler: list[dict] = []
    sayfa_raporlari: list[dict] = []
    try:
        with zipfile.ZipFile(zip_yolu) as arsiv:
            for sayfa_no in sorted(sayfalara_gore):
                sayfa = _renderer_sonucunu_rgb(
                    render_fonksiyonu(pdf_yolu, sayfa_no, dpi),
                    sayfa_no,
                )
                sorular = []
                for kayit in sorted(sayfalara_gore[sayfa_no]):
                    ham_crop, crop_sha = _crop_oku(
                        arsiv,
                        kayit,
                        max_piksel=max_piksel,
                    )
                    crop = _crop_olcekle(
                        ham_crop,
                        dpi=dpi,
                        crop_dpi=crop_dpi,
                    )
                    try:
                        eslesme = crop_eslestir(
                            sayfa,
                            crop,
                            min_skor=min_skor,
                        )
                        yerel_capa = turkuaz_capa_kutusu(crop)
                    except PalmeVeriHatasi as hata:
                        raise PalmeVeriHatasi(
                            f"{kayit.uye_adi}: {hata}"
                        ) from hata
                    bx0, by0, bx1, by1 = eslesme["kutu"]
                    ax0, ay0, ax1, ay1 = yerel_capa
                    capa = (
                        bx0 + ax0,
                        by0 + ay0,
                        bx0 + ax1,
                        by0 + ay1,
                    )
                    if not (
                        bx0 <= capa[0] < capa[2] <= bx1
                        and by0 <= capa[1] < capa[3] <= by1
                    ):
                        raise PalmeVeriHatasi(
                            f"{kayit.uye_adi}: çapa gövde kutusu dışında"
                        )
                    sorular.append({
                        "question_id": kayit.soru_id,
                        "member": kayit.uye_adi,
                        "unit": kayit.unite,
                        "test": kayit.test,
                        "question": kayit.soru,
                        "source_page": sayfa_no,
                        "crop_sha256": crop_sha,
                        "original_crop_size": list(ham_crop.size),
                        "aligned_crop_size": list(crop.size),
                        "alignment_score": round(
                            float(eslesme["skor"]), 6
                        ),
                        "body_box": list(eslesme["kutu"]),
                        "anchor_box": list(capa),
                    })
                sorular.sort(
                    key=lambda s: (
                        s["body_box"][1],
                        s["body_box"][0],
                        s["unit"],
                        s["test"],
                        s["question"],
                    )
                )
                govde_kutularini_dogrula(
                    sorular,
                    max_ortusme=max_ortusme,
                )
                bolum = _sayfa_bolumu(sorular)
                ad = f"palme-ayt-p{sayfa_no:04d}"
                img_rel = f"images/{bolum}/{ad}.png"
                lbl_rel = f"labels/{bolum}/{ad}.txt"
                img_yolu = os.path.join(staging, *img_rel.split("/"))
                lbl_yolu = os.path.join(staging, *lbl_rel.split("/"))
                os.makedirs(os.path.dirname(img_yolu), exist_ok=True)
                os.makedirs(os.path.dirname(lbl_yolu), exist_ok=True)
                sayfa.save(img_yolu, "PNG", compress_level=3)
                satirlar = []
                for soru in sorular:
                    satirlar.append(
                        _yolo_satiri(
                            0,
                            soru["anchor_box"],
                            sayfa.width,
                            sayfa.height,
                        )
                    )
                    satirlar.append(
                        _yolo_satiri(
                            1,
                            soru["body_box"],
                            sayfa.width,
                            sayfa.height,
                        )
                    )
                with open(lbl_yolu, "w", encoding="utf-8") as hedef:
                    hedef.write("\n".join(satirlar) + "\n")

                ornek = {
                    "image": img_rel,
                    "label": lbl_rel,
                    "document_sha256": pdf_sha,
                    "page": sayfa_no,
                    "publisher_group": YAYINEVI_GRUBU,
                    "annotation_origin": ETIKET_KAYNAGI,
                    "alignment_score": round(
                        min(s["alignment_score"] for s in sorular), 6
                    ),
                    "image_sha256": _sha256_dosya(img_yolu),
                    "label_sha256": _sha256_dosya(lbl_yolu),
                }
                if bolum == "train":
                    train_ornekler.append(ornek)
                else:
                    tanisal_ornekler.append(ornek)
                sayfa_raporlari.append({
                    "page": sayfa_no,
                    "partition": bolum,
                    "width": sayfa.width,
                    "height": sayfa.height,
                    "units": sorted({s["unit"] for s in sorular}),
                    "image": img_rel,
                    "label": lbl_rel,
                    "minimum_alignment_score": ornek["alignment_score"],
                    "questions": sorular,
                })

        if not train_ornekler:
            raise PalmeVeriHatasi("ünite 12-25 için eğitim sayfası üretilemedi")

        manifest = {
            "schema_version": EGITIM_SEMA_SURUMU,
            "dataset_id": dataset_id,
            "classes": list(SINIFLAR),
            "root": ".",
            "splits": {
                "train": train_ornekler,
                "validation": [],
                "calibration": [],
                "holdout": [],
            },
        }
        tanisal_manifest = {
            "schema_version": TANISAL_SEMA_SURUMU,
            "dataset_id": dataset_id + "-diagnostic",
            "classes": list(SINIFLAR),
            "root": ".",
            "partition": "diagnostic_holdout",
            "policy": "Ünite 26-27 içeren tam sayfalar; eğitim manifesti dışında",
            "samples": tanisal_ornekler,
        }
        rapor = {
            "schema_version": RAPOR_SEMA_SURUMU,
            "generator_version": URETICI_SURUMU,
            "dataset_id": dataset_id,
            "classes": list(SINIFLAR),
            "label_classes_present": [0, 1],
            "annotation_origin": ETIKET_KAYNAGI,
            "publisher_group": YAYINEVI_GRUBU,
            "source_pdf": {
                "sha256": pdf_sha,
                "size": os.path.getsize(pdf_yolu),
            },
            "source_zip": {
                "sha256": zip_sha,
                "size": os.path.getsize(zip_yolu),
                "member_count": zip_raporu["uye_sayisi"],
                "crop_count": zip_raporu["crop_sayisi"],
                "total_uncompressed_bytes": (
                    zip_raporu["toplam_acilmis_bayt"]
                ),
                "ignored_non_image_members": zip_raporu["yok_sayilan"],
            },
            "settings": {
                "dpi": dpi,
                "crop_reference_dpi": crop_dpi,
                "minimum_alignment_score": min_skor,
                "maximum_small_box_overlap": max_ortusme,
                "hsv_anchor_hue": [80, 100],
            },
            "summary": {
                "train_pages": len(train_ornekler),
                "diagnostic_holdout_pages": len(tanisal_ornekler),
                "question_count": sum(
                    len(s["questions"]) for s in sayfa_raporlari
                ),
                "train_questions": sum(
                    len(s["questions"])
                    for s in sayfa_raporlari
                    if s["partition"] == "train"
                ),
                "diagnostic_holdout_questions": sum(
                    len(s["questions"])
                    for s in sayfa_raporlari
                    if s["partition"] == "diagnostic_holdout"
                ),
            },
            "pages": sayfa_raporlari,
        }
        _json_yaz(os.path.join(staging, "manifest.json"), manifest)
        _json_yaz(
            os.path.join(staging, "diagnostic_manifest.json"),
            tanisal_manifest,
        )
        _json_yaz(
            os.path.join(staging, "provenance_alignment_report.json"),
            rapor,
        )
        os.replace(staging, cikti_dizini)
        staging = ""
        return {
            "ok": True,
            "output": cikti_dizini,
            "manifest": os.path.join(cikti_dizini, "manifest.json"),
            "diagnostic_manifest": os.path.join(
                cikti_dizini,
                "diagnostic_manifest.json",
            ),
            "report": os.path.join(
                cikti_dizini,
                "provenance_alignment_report.json",
            ),
            "summary": rapor["summary"],
        }
    except Exception:
        if staging:
            shutil.rmtree(staging, ignore_errors=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Palme AYT crop → tam sayfa question-layout veri seti"
    )
    parser.add_argument("--pdf", required=True, help="Kaynak Palme AYT PDF")
    parser.add_argument("--zip", required=True, dest="zip_yolu",
                        help="Soru fotoğrafları ZIP'i")
    parser.add_argument("--cikti", required=True,
                        help="Yeni/var olmayan çıktı dizini")
    parser.add_argument("--dpi", type=int, default=VARSAYILAN_DPI)
    parser.add_argument("--crop-dpi", type=int,
                        default=VARSAYILAN_CROP_DPI)
    parser.add_argument("--min-skor", type=float,
                        default=VARSAYILAN_ESIK)
    parser.add_argument("--max-ortusme", type=float,
                        default=VARSAYILAN_MAX_ORTUSME)
    parser.add_argument("--max-uye", type=int,
                        default=VARSAYILAN_MAX_UYE)
    parser.add_argument("--max-toplam-bayt", type=int,
                        default=VARSAYILAN_MAX_TOPLAM_BAYT)
    parser.add_argument("--max-uye-bayt", type=int,
                        default=VARSAYILAN_MAX_UYE_BAYT)
    args = parser.parse_args(argv)
    try:
        sonuc = palme_veri_seti_uret(
            args.pdf,
            args.zip_yolu,
            args.cikti,
            dpi=args.dpi,
            crop_dpi=args.crop_dpi,
            min_skor=args.min_skor,
            max_ortusme=args.max_ortusme,
            max_uye=args.max_uye,
            max_toplam_bayt=args.max_toplam_bayt,
            max_uye_bayt=args.max_uye_bayt,
        )
    except (PalmeVeriHatasi, ValueError) as hata:
        parser.exit(2, f"HATA: {hata}\n")
    print(json.dumps(sonuc, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
