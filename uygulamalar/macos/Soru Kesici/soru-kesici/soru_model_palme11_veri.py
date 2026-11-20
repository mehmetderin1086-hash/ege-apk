#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""İki doğrulanmış Palme 11. sınıf crop paketinden tam-sayfa veri üretir.

Bu üretici yalnız aşağıdaki içerik-kimlikleri sabitlenmiş kaynak çiftlerini
kabul eder:

* standart Palme 11. Sınıf Biyoloji Soru Bankası + 1068 PNG paketi;
* Fen Lisesi Palme 11. Sınıf Biyoloji Soru Bankası + 1057 PNG paketi.

Her crop, kaynak PDF'nin aynı numaralı sayfasında ölçeği düzeltilerek aranır.
En iyi eşleşme için hem mutlak skor hem de aynı eşleşmenin yakın çevresi
dışındaki ikinci tepeye uzaklık zorunludur. Yalnız bu kapıları geçen tam
sayfalar etiketlenir. Ünite 12 içeren sayfanın tamamı ayrı diagnostic
holdout'a gider; ünite 1-11 sayfaları train supplement olarak yayımlanır.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import csv
import dataclasses
import hashlib
import io
import json
import math
import os
import pathlib
import re
import shutil
import stat
import statistics
import subprocess
import tempfile
import warnings
import zipfile
from typing import Callable, Iterable

from PIL import Image

import soru_model_palme_veri as ortak


EGITIM_SEMA_SURUMU = ortak.EGITIM_SEMA_SURUMU
TANISAL_SEMA_SURUMU = ortak.TANISAL_SEMA_SURUMU
SINIFLAR = ortak.SINIFLAR
YAYINEVI_GRUBU = "pub-palme-11-biyoloji-2018"
ETIKET_KAYNAGI = "verified_multiscale_crop_alignment"
RAPOR_SEMA_SURUMU = "soru-kesici.palme11-crop-alignment/v1"
URETICI_SURUMU = "1"

VARSAYILAN_DPI = 130
VARSAYILAN_MIN_SKOR = 0.68
VARSAYILAN_MIN_UZAK_FARK = 0.03
VARSAYILAN_MAX_ORTUSME = 0.02
VARSAYILAN_MAX_UYE = 5_000
VARSAYILAN_MAX_TOPLAM_BAYT = 8 * 1024**3
VARSAYILAN_MAX_UYE_BAYT = 64 * 1024**2
VARSAYILAN_MAX_PIKSEL = 30_000_000

_STANDART_DESEN = re.compile(
    r"^unit_(?P<folder_unit>\d{2})_(?P<unit_slug>[a-z0-9_]+)/png/"
    r"u(?P<unit>\d{2})_(?P<exam>mini|test)(?P<exam_no>\d{2})_"
    r"q(?P<question>\d{2})_p(?P<page>\d{3})\.png$",
    re.IGNORECASE,
)
_FEN_DESEN = re.compile(
    r"^Palme11_1057_Soru_PNG/questions_png/"
    r"U(?P<unit>\d{2})_(?P<exam>MS|T)(?P<exam_no>\d{2})_"
    r"Q(?P<question>\d{2})_p(?P<page>\d{3})\.png$",
    re.IGNORECASE,
)
_FEN_MANIFEST = "Palme11_1057_Soru_PNG/manifest.csv"
_FEN_README = "Palme11_1057_Soru_PNG/README.md"
_FEN_DIZINLER = frozenset({
    "Palme11_1057_Soru_PNG/",
    "Palme11_1057_Soru_PNG/questions_png/",
})
_FEN_CSV_ALANLARI = (
    "id",
    "ünite",
    "ünite_adı",
    "sınav_türü",
    "sınav_no",
    "soru_no",
    "kaynak_sayfa",
    "konu",
    "cevap",
    "png",
)


class Palme11VeriHatasi(RuntimeError):
    """Palme 11 veri üretimini kısmi çıktı bırakmadan durdurur."""


@dataclasses.dataclass(frozen=True)
class Palme11Profili:
    kimlik: str
    book_id: str
    dosya_turu: str
    crop_dpi: int
    pdf_sha256: str | None
    pdf_bayt: int | None
    pdf_sayfa: int | None
    zip_sha256: str | None
    zip_bayt: int | None
    crop_sayisi: int | None
    metadata_hashleri: tuple[tuple[str, str], ...] = ()


STANDART_PROFIL = Palme11Profili(
    kimlik="palme11-standard-2018",
    book_id="palme-11-biyoloji-sb-2018",
    dosya_turu="standard",
    crop_dpi=180,
    pdf_sha256=(
        "34483d35a9b83499774ebeec46e231184bd06bfd19001d163ae702b5179cbf0d"
    ),
    pdf_bayt=93_474_717,
    pdf_sayfa=320,
    zip_sha256=(
        "2bf6a4aef418d09b93651230be881c03dd5e096e2b730dd41ef3466319723063"
    ),
    zip_bayt=79_004_975,
    crop_sayisi=1_068,
)

FEN_PROFIL = Palme11Profili(
    kimlik="palme11-fen-2018",
    book_id="palme-11-biyoloji-fen-lisesi-sb-2018",
    dosya_turu="fen",
    crop_dpi=144,
    pdf_sha256=(
        "452c8c480e0c08586f74297c93323440811a6e059611cd9a7e6662d43049354a"
    ),
    pdf_bayt=86_260_310,
    pdf_sayfa=336,
    zip_sha256=(
        "7530a1b73efb8c988c563ad645450f5d45ee701175f5c2b8f6614b880e98fe56"
    ),
    zip_bayt=62_317_750,
    crop_sayisi=1_057,
    metadata_hashleri=(
        (
            _FEN_MANIFEST,
            "c9641a5dd20287aa51a95b4c0ce2cb520f532ece5d68b1d21407c986daf02fe6",
        ),
        (
            _FEN_README,
            "5d79a99ef473298606379acfa317c510eacabf75f8280ce91881fb71fa85f45f",
        ),
    ),
)


@dataclasses.dataclass(frozen=True)
class Palme11Kaynagi:
    profil: Palme11Profili
    pdf_yolu: str
    zip_yolu: str


@dataclasses.dataclass(frozen=True)
class CropKaydi:
    profil_kimligi: str
    book_id: str
    uye_adi: str
    unite: int
    sinav_turu: str
    sinav_no: int
    soru: int
    sayfa: int
    boyut: int
    crc: int
    encoded_sha256: str
    pixel_sha256: str
    genislik: int
    yukseklik: int

    @property
    def yerel_soru_id(self) -> str:
        kisaltma = "MS" if self.sinav_turu == "mini" else "T"
        return (
            f"U{self.unite:02d}_{kisaltma}{self.sinav_no:02d}_"
            f"Q{self.soru:02d}"
        )

    @property
    def soru_id(self) -> str:
        return f"{self.book_id}:{self.yerel_soru_id}"


def _sha256_dosya(yol: str) -> str:
    ozet = hashlib.sha256()
    with open(yol, "rb") as kaynak:
        for parca in iter(lambda: kaynak.read(1 << 20), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _sha256_bayt(veri: bytes) -> str:
    return hashlib.sha256(veri).hexdigest()


def _rgb_piksel_sha256(gorsel: Image.Image) -> str:
    rgb = gorsel.convert("RGB")
    ozet = hashlib.sha256()
    ozet.update(b"soru-kesici/rgb-pixels/v1\0")
    ozet.update(rgb.width.to_bytes(8, "big"))
    ozet.update(rgb.height.to_bytes(8, "big"))
    ozet.update(rgb.tobytes())
    return ozet.hexdigest()


def _json_yaz(yol: str, veri: object) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(yol)), exist_ok=True)
    with open(yol, "w", encoding="utf-8") as hedef:
        json.dump(veri, hedef, ensure_ascii=False, indent=2, sort_keys=True)
        hedef.write("\n")


def _profil_uyesini_coz(
    profil: Palme11Profili,
    uye_adi: str,
) -> tuple[int, str, int, int, int] | None:
    desen = _STANDART_DESEN if profil.dosya_turu == "standard" \
        else _FEN_DESEN
    eslesme = desen.fullmatch(uye_adi)
    if eslesme is None:
        return None
    unite = int(eslesme.group("unit"))
    if profil.dosya_turu == "standard" \
            and int(eslesme.group("folder_unit")) != unite:
        raise Palme11VeriHatasi(
            f"klasör/üye ünite kimliği uyuşmuyor: {uye_adi}"
        )
    sinav_ham = eslesme.group("exam").casefold()
    sinav_turu = "mini" if sinav_ham in ("mini", "ms") else "test"
    sinav_no = int(eslesme.group("exam_no"))
    soru = int(eslesme.group("question"))
    sayfa = int(eslesme.group("page"))
    if not 1 <= unite <= 12:
        raise Palme11VeriHatasi(f"ünite 1..12 dışında: {uye_adi}")
    if min(sinav_no, soru, sayfa) < 1:
        raise Palme11VeriHatasi(f"sıfır/negatif soru kimliği: {uye_adi}")
    if profil.pdf_sayfa is not None and sayfa > profil.pdf_sayfa:
        raise Palme11VeriHatasi(
            f"crop PDF sayfa sayısını aşıyor: {uye_adi}"
        )
    return unite, sinav_turu, sinav_no, soru, sayfa


def _fen_csv_dogrula(
    csv_bayt: bytes,
    kayitlar: list[CropKaydi],
) -> dict:
    try:
        metin = csv_bayt.decode("utf-8-sig")
        okuyucu = csv.DictReader(io.StringIO(metin))
        if tuple(okuyucu.fieldnames or ()) != _FEN_CSV_ALANLARI:
            raise Palme11VeriHatasi("Fen manifest.csv sütunları uyumsuz")
        satirlar = list(okuyucu)
    except UnicodeError as hata:
        raise Palme11VeriHatasi(
            f"Fen manifest.csv UTF-8 okunamadı: {hata}"
        ) from hata

    uye_haritasi = {kayit.uye_adi: kayit for kayit in kayitlar}
    gorulen: set[str] = set()
    for sira, satir in enumerate(satirlar, 2):
        if any(not (satir.get(alan) or "").strip()
               for alan in _FEN_CSV_ALANLARI):
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: boş alan var"
            )
        uye = "Palme11_1057_Soru_PNG/" + satir["png"].strip()
        kayit = uye_haritasi.get(uye)
        if kayit is None:
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: PNG ZIP'te yok: {uye}"
            )
        if uye in gorulen:
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: yinelenen PNG: {uye}"
            )
        gorulen.add(uye)
        try:
            sayisal = (
                int(satir["ünite"]),
                int(satir["sınav_no"]),
                int(satir["soru_no"]),
                int(satir["kaynak_sayfa"]),
            )
        except ValueError as hata:
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: sayısal alan geçersiz"
            ) from hata
        beklenen_tur = "mini" if kayit.sinav_turu == "mini" else "test"
        if sayisal != (
            kayit.unite,
            kayit.sinav_no,
            kayit.soru,
            kayit.sayfa,
        ) or satir["sınav_türü"].strip().casefold() != beklenen_tur:
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: dosya adı metadata ile uyuşmuyor"
            )
        if satir["id"].strip().upper() != kayit.yerel_soru_id:
            raise Palme11VeriHatasi(
                f"Fen manifest.csv:{sira}: soru id uyuşmuyor"
            )
    if gorulen != set(uye_haritasi):
        eksik = sorted(set(uye_haritasi) - gorulen)[:3]
        raise Palme11VeriHatasi(
            f"Fen manifest.csv tüm PNG'leri kapsamıyor: {eksik}"
        )
    return {
        "rows": len(satirlar),
        "unique_png": len(gorulen),
        "columns": list(_FEN_CSV_ALANLARI),
        "empty_fields": 0,
    }


def zip_denetle(
    zip_yolu: str,
    profil: Palme11Profili,
    *,
    max_uye: int = VARSAYILAN_MAX_UYE,
    max_toplam_bayt: int = VARSAYILAN_MAX_TOPLAM_BAYT,
    max_uye_bayt: int = VARSAYILAN_MAX_UYE_BAYT,
    max_piksel: int = VARSAYILAN_MAX_PIKSEL,
) -> dict:
    """ZIP'i güvenlik, gerçek PNG, kimlik ve metadata açısından doğrular."""
    if not os.path.isfile(zip_yolu):
        raise Palme11VeriHatasi(f"ZIP bulunamadı: {zip_yolu}")
    zip_bayt = os.path.getsize(zip_yolu)
    if profil.zip_bayt is not None and zip_bayt != profil.zip_bayt:
        raise Palme11VeriHatasi(
            f"{profil.kimlik}: ZIP boyutu beklenen kimlikle uyuşmuyor"
        )
    zip_sha = _sha256_dosya(zip_yolu)
    if profil.zip_sha256 is not None and zip_sha != profil.zip_sha256:
        raise Palme11VeriHatasi(
            f"{profil.kimlik}: ZIP SHA-256 beklenen kimlikle uyuşmuyor"
        )

    kayitlar: list[CropKaydi] = []
    metadata: dict[str, bytes] = {}
    gorulen_yollar: set[str] = set()
    gorulen_sorular: set[tuple[int, str, int, int]] = set()
    toplam = 0
    dizinler: list[str] = []
    try:
        with zipfile.ZipFile(zip_yolu) as arsiv:
            uyeler = arsiv.infolist()
            if len(uyeler) > max_uye:
                raise Palme11VeriHatasi(
                    f"ZIP üye sınırını aşıyor: {len(uyeler)} > {max_uye}"
                )
            for bilgi in uyeler:
                try:
                    ad = ortak._guvenli_uye_adi(bilgi.filename)
                except ortak.PalmeVeriHatasi as hata:
                    raise Palme11VeriHatasi(str(hata)) from hata
                kimlik = ad.casefold()
                if kimlik in gorulen_yollar:
                    raise Palme11VeriHatasi(
                        f"ZIP yinelenen üye yolu içeriyor: {ad}"
                    )
                gorulen_yollar.add(kimlik)
                unix_modu = (bilgi.external_attr >> 16) & 0xFFFF
                if unix_modu and stat.S_ISLNK(unix_modu):
                    raise Palme11VeriHatasi(
                        f"ZIP sembolik bağ içeriyor: {ad}"
                    )
                if bilgi.flag_bits & 0x1:
                    raise Palme11VeriHatasi(f"ZIP şifreli üye içeriyor: {ad}")
                if bilgi.is_dir():
                    dizinler.append(ad + ("" if ad.endswith("/") else "/"))
                    continue
                if bilgi.file_size < 0 or bilgi.file_size > max_uye_bayt:
                    raise Palme11VeriHatasi(
                        f"ZIP üyesi boyut sınırını aşıyor: {ad}"
                    )
                toplam += bilgi.file_size
                if toplam > max_toplam_bayt:
                    raise Palme11VeriHatasi(
                        "ZIP toplam açılmış boyut sınırını aşıyor"
                    )
                try:
                    veri = arsiv.read(bilgi)
                except Exception as hata:
                    raise Palme11VeriHatasi(
                        f"ZIP üyesi CRC/okuma hatası: {ad}: {hata}"
                    ) from hata
                if len(veri) != bilgi.file_size:
                    raise Palme11VeriHatasi(f"ZIP üye boyutu değişti: {ad}")

                cozum = _profil_uyesini_coz(profil, ad)
                if cozum is None:
                    izinli_metadata = dict(profil.metadata_hashleri)
                    if ad not in izinli_metadata:
                        raise Palme11VeriHatasi(
                            f"profilde tanımsız ZIP üyesi: {ad}"
                        )
                    ozet = _sha256_bayt(veri)
                    if ozet != izinli_metadata[ad]:
                        raise Palme11VeriHatasi(
                            f"metadata SHA-256 uyuşmuyor: {ad}"
                        )
                    metadata[ad] = veri
                    continue

                unite, sinav_turu, sinav_no, soru, sayfa = cozum
                mantiksal = (unite, sinav_turu, sinav_no, soru)
                if mantiksal in gorulen_sorular:
                    raise Palme11VeriHatasi(
                        f"ZIP yinelenen mantıksal soru içeriyor: {ad}"
                    )
                gorulen_sorular.add(mantiksal)
                try:
                    with warnings.catch_warnings():
                        warnings.simplefilter(
                            "error", Image.DecompressionBombWarning
                        )
                        with Image.open(io.BytesIO(veri)) as acik:
                            if acik.format != "PNG":
                                raise Palme11VeriHatasi(
                                    f"uzantısı PNG ama içerik {acik.format}: {ad}"
                                )
                            if acik.width * acik.height > max_piksel:
                                raise Palme11VeriHatasi(
                                    f"PNG piksel sınırını aşıyor: {ad}"
                                )
                            acik.load()
                            gorsel = acik.convert("RGB")
                except Palme11VeriHatasi:
                    raise
                except Exception as hata:
                    raise Palme11VeriHatasi(
                        f"PNG çözülemedi: {ad}: {hata}"
                    ) from hata
                kayitlar.append(CropKaydi(
                    profil_kimligi=profil.kimlik,
                    book_id=profil.book_id,
                    uye_adi=ad,
                    unite=unite,
                    sinav_turu=sinav_turu,
                    sinav_no=sinav_no,
                    soru=soru,
                    sayfa=sayfa,
                    boyut=bilgi.file_size,
                    crc=bilgi.CRC,
                    encoded_sha256=_sha256_bayt(veri),
                    pixel_sha256=_rgb_piksel_sha256(gorsel),
                    genislik=gorsel.width,
                    yukseklik=gorsel.height,
                ))
    except (OSError, zipfile.BadZipFile, zipfile.LargeZipFile) as hata:
        raise Palme11VeriHatasi(f"ZIP okunamadı: {hata}") from hata

    if profil.crop_sayisi is not None \
            and len(kayitlar) != profil.crop_sayisi:
        raise Palme11VeriHatasi(
            f"{profil.kimlik}: crop sayısı {len(kayitlar)} "
            f"!= {profil.crop_sayisi}"
        )
    if not kayitlar:
        raise Palme11VeriHatasi("ZIP içinde doğrulanabilir PNG crop yok")
    if profil.dosya_turu == "fen":
        if set(dizinler) != _FEN_DIZINLER:
            raise Palme11VeriHatasi("Fen ZIP dizin sözleşmesi uyuşmuyor")
        if set(metadata) != {_FEN_MANIFEST, _FEN_README}:
            raise Palme11VeriHatasi("Fen ZIP metadata üyeleri eksik")
        csv_raporu = _fen_csv_dogrula(metadata[_FEN_MANIFEST], kayitlar)
    else:
        if dizinler or metadata:
            raise Palme11VeriHatasi(
                "standart ZIP yalnız köksüz PNG üyeleri içermeli"
            )
        csv_raporu = None

    piksel_gruplari = collections.Counter(
        kayit.pixel_sha256 for kayit in kayitlar
    )
    encoded_gruplari = collections.Counter(
        kayit.encoded_sha256 for kayit in kayitlar
    )
    return {
        "profil": profil,
        "kayitlar": sorted(
            kayitlar,
            key=lambda k: (
                k.sayfa,
                k.unite,
                k.sinav_turu,
                k.sinav_no,
                k.soru,
                k.uye_adi,
            ),
        ),
        "zip_sha256": zip_sha,
        "zip_size": zip_bayt,
        "member_count": len(gorulen_yollar),
        "crop_count": len(kayitlar),
        "total_uncompressed_bytes": toplam,
        "unique_encoded_images": len(encoded_gruplari),
        "unique_decoded_rgb_images": len(piksel_gruplari),
        "duplicate_encoded_members": sum(
            adet - 1 for adet in encoded_gruplari.values() if adet > 1
        ),
        "duplicate_decoded_rgb_members": sum(
            adet - 1 for adet in piksel_gruplari.values() if adet > 1
        ),
        "csv": csv_raporu,
        "metadata_sha256": {
            ad: _sha256_bayt(veri) for ad, veri in sorted(metadata.items())
        },
    }


def _pdf_kimligini_dogrula(kaynak: Palme11Kaynagi) -> dict:
    profil = kaynak.profil
    if not os.path.isfile(kaynak.pdf_yolu):
        raise Palme11VeriHatasi(f"PDF bulunamadı: {kaynak.pdf_yolu}")
    boyut = os.path.getsize(kaynak.pdf_yolu)
    if profil.pdf_bayt is not None and boyut != profil.pdf_bayt:
        raise Palme11VeriHatasi(
            f"{profil.kimlik}: PDF boyutu beklenen kimlikle uyuşmuyor"
        )
    ozet = _sha256_dosya(kaynak.pdf_yolu)
    if profil.pdf_sha256 is not None and ozet != profil.pdf_sha256:
        raise Palme11VeriHatasi(
            f"{profil.kimlik}: PDF SHA-256 beklenen kimlikle uyuşmuyor"
        )
    sayfa_sayisi = profil.pdf_sayfa
    if sayfa_sayisi is not None:
        pdfinfo = shutil.which("pdfinfo")
        if not pdfinfo:
            raise Palme11VeriHatasi(
                f"{profil.kimlik}: pdfinfo bulunamadı"
            )
        try:
            ortam = os.environ.copy()
            ortam["LC_ALL"] = "C"
            islem = subprocess.run(
                [pdfinfo, kaynak.pdf_yolu],
                check=False,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=60,
                env=ortam,
            )
        except (OSError, subprocess.SubprocessError) as hata:
            raise Palme11VeriHatasi(
                f"{profil.kimlik}: PDF sayfa sayısı okunamadı: {hata}"
            ) from hata
        if islem.returncode != 0:
            ayrinti = (islem.stderr or islem.stdout).strip()[:240]
            raise Palme11VeriHatasi(
                f"{profil.kimlik}: pdfinfo başarısız: {ayrinti}"
            )
        eslesmeler = re.findall(
            r"^Pages:\s*([0-9]+)\s*$",
            islem.stdout,
            flags=re.MULTILINE,
        )
        if len(eslesmeler) != 1:
            raise Palme11VeriHatasi(
                f"{profil.kimlik}: pdfinfo Pages alanı tekil değil"
            )
        gercek = int(eslesmeler[0])
        if gercek != sayfa_sayisi:
            raise Palme11VeriHatasi(
                f"{profil.kimlik}: PDF sayfa sayısı {gercek} != "
                f"{sayfa_sayisi}"
            )
    return {"sha256": ozet, "size": boyut, "pages": sayfa_sayisi}


def _benzersiz_kayitlari_sec(zip_raporlari: list[dict]) -> tuple[list, list]:
    gruplar: dict[str, list[CropKaydi]] = collections.defaultdict(list)
    for rapor in zip_raporlari:
        for kayit in rapor["kayitlar"]:
            gruplar[kayit.pixel_sha256].append(kayit)
    tutulan: list[CropKaydi] = []
    atilan: list[dict] = []
    for piksel_sha in sorted(gruplar):
        adaylar = sorted(
            gruplar[piksel_sha],
            key=lambda k: (k.profil_kimligi, k.uye_adi),
        )
        tutulan.append(adaylar[0])
        for kayit in adaylar[1:]:
            atilan.append({
                "pixel_sha256": piksel_sha,
                "kept_question_id": adaylar[0].soru_id,
                "removed_question_id": kayit.soru_id,
            })
    return sorted(
        tutulan,
        key=lambda k: (
            k.profil_kimligi,
            k.sayfa,
            k.unite,
            k.sinav_turu,
            k.sinav_no,
            k.soru,
        ),
    ), atilan


def crop_eslestir_uzak_tepe(
    sayfa: Image.Image,
    crop: Image.Image,
    *,
    min_skor: float,
    min_uzak_fark: float,
) -> dict:
    """En iyi crop eşleşmesini ve yerel komşuluk dışı ikinci tepeyi ölçer."""
    if not 0 < min_skor <= 1:
        raise ValueError("min_skor 0..1 aralığında olmalı")
    if not 0 <= min_uzak_fark <= 1:
        raise ValueError("min_uzak_fark 0..1 aralığında olmalı")
    if crop.width > sayfa.width or crop.height > sayfa.height:
        raise Palme11VeriHatasi(
            f"crop render sayfasından büyük: {crop.size} > {sayfa.size}"
        )
    cv2, np = ortak._cv2_ve_numpy()
    sayfa_gri = cv2.cvtColor(
        np.asarray(sayfa.convert("RGB"), dtype=np.uint8),
        cv2.COLOR_RGB2GRAY,
    )
    crop_gri = cv2.cvtColor(
        np.asarray(crop.convert("RGB"), dtype=np.uint8),
        cv2.COLOR_RGB2GRAY,
    )
    if float(crop_gri.std()) < 2.0:
        raise Palme11VeriHatasi(
            "crop eşleştirme için yeterli doku taşımıyor"
        )
    sonuc = cv2.matchTemplate(
        sayfa_gri,
        crop_gri,
        cv2.TM_CCOEFF_NORMED,
    )
    _min, en_iyi, _min_yer, en_iyi_yer = cv2.minMaxLoc(sonuc)
    x, y = int(en_iyi_yer[0]), int(en_iyi_yer[1])
    uzak = sonuc.copy()
    yarim_w = max(1, crop.width // 2)
    yarim_h = max(1, crop.height // 2)
    x0, x1 = max(0, x - yarim_w), min(uzak.shape[1], x + yarim_w + 1)
    y0, y1 = max(0, y - yarim_h), min(uzak.shape[0], y + yarim_h + 1)
    uzak[y0:y1, x0:x1] = -1.0
    _u_min, ikinci, _u_min_yer, ikinci_yer = cv2.minMaxLoc(uzak)
    fark = min(1.0, max(0.0, float(en_iyi) - float(ikinci)))
    if not math.isfinite(float(en_iyi)) or float(en_iyi) < min_skor:
        raise Palme11VeriHatasi(
            f"crop eşleşme skoru düşük: {float(en_iyi):.6f} < "
            f"{min_skor:.6f}"
        )
    if not math.isfinite(fark) or fark < min_uzak_fark:
        raise Palme11VeriHatasi(
            f"crop uzak-tepe farkı düşük: {fark:.6f} < "
            f"{min_uzak_fark:.6f}"
        )
    return {
        "skor": float(en_iyi),
        "uzak_skor": float(ikinci),
        "uzak_fark": fark,
        "kutu": (x, y, x + crop.width, y + crop.height),
        "uzak_yer": (int(ikinci_yer[0]), int(ikinci_yer[1])),
    }


def turuncu_capa_kutusu(crop: Image.Image) -> tuple[int, int, int, int]:
    """Crop sol-üstündeki turuncu soru numarasını bulur."""
    try:
        return ortak.turkuaz_capa_kutusu(
            crop,
            hue_alt=0,
            hue_ust=20,
            sat_alt=100,
            value_alt=70,
        )
    except ortak.PalmeVeriHatasi as hata:
        raise Palme11VeriHatasi(str(hata)) from hata


def govde_icerik_kutusu(
    eslesme_kutusu: tuple[int, int, int, int],
    crop: Image.Image,
) -> tuple[int, int, int, int]:
    """Crop'un yalnız sonda kalan boş paddingini gövde kutusundan çıkarır.

    Palme PNG'lerinde sütun ayırıcı çizgi crop'un sağ/sol kenarı boyunca
    uzayabildiği için kenar şeritleri içerik satırı hesabına katılmaz. Eşleşme
    yine tam crop ile yapılır; yalnız eğitimdeki body hedefi son gerçek içerik
    satırının az ötesinde biter.
    """
    _cv2, np = ortak._cv2_ve_numpy()
    rgb = np.asarray(crop.convert("RGB"), dtype=np.uint8)
    kenar = max(2, round(crop.width * 0.02))
    if crop.width - 2 * kenar < 16:
        raise Palme11VeriHatasi("crop içerik analizi için çok dar")
    ic = rgb[:, kenar:crop.width - kenar, :]
    en_koyu = ic.min(axis=2)
    en_acik = ic.max(axis=2)
    # Koyu metin/çizgi veya doygun renk gerçek içeriktir. Saf/çok yakın beyaz
    # JPEG/antialias artıkları satırı tek başına aktif sayamaz.
    on_plan = (en_koyu < 242) | ((en_acik - en_koyu) > 18)
    satir_pikseli = on_plan.sum(axis=1)
    min_satir_pikseli = max(3, round(ic.shape[1] * 0.004))
    aktif = np.flatnonzero(satir_pikseli >= min_satir_pikseli)
    if aktif.size == 0:
        raise Palme11VeriHatasi("crop içinde gövde içeriği bulunamadı")
    son = int(aktif[-1]) + 1
    dolgu = max(3, round(crop.height * 0.01))
    icerik_yuksekligi = min(crop.height, son + dolgu)
    if icerik_yuksekligi < max(16, round(crop.height * 0.05)):
        raise Palme11VeriHatasi("crop gövde içerik kutusu çok kısa")
    x0, y0, x1, y1 = eslesme_kutusu
    if (x1 - x0, y1 - y0) != crop.size:
        raise Palme11VeriHatasi("eşleşme/crop boyutu içerik analizinde uyuşmuyor")
    return (x0, y0, x1, y0 + icerik_yuksekligi)


def _renderer_sonucunu_rgb(sonuc: object, sayfa: int) -> Image.Image:
    try:
        return ortak._renderer_sonucunu_rgb(sonuc, sayfa)
    except ortak.PalmeVeriHatasi as hata:
        raise Palme11VeriHatasi(str(hata)) from hata


def _manifesti_dogrula(manifest_yolu: str) -> None:
    """Supplement manifestini standart doğrulayıcıyla, boş validation hariç, sınar."""
    import soru_model_egitim
    rapor = soru_model_egitim.manifest_dogrula(manifest_yolu)
    izinli = {"validation split'i boş/eksik"}
    hatalar = [hata for hata in rapor["hatalar"] if hata not in izinli]
    if hatalar:
        raise Palme11VeriHatasi(
            "üretilen manifest doğrulanamadı: " + "; ".join(hatalar[:5])
        )


def _oran_ozeti(degerler: list[float]) -> dict:
    sirali = sorted(float(deger) for deger in degerler)
    if not sirali:
        return {"min": None, "p05": None, "median": None, "max": None}
    p05 = sirali[max(0, math.ceil(len(sirali) * 0.05) - 1)]
    return {
        "min": round(sirali[0], 6),
        "p05": round(p05, 6),
        "median": round(statistics.median(sirali), 6),
        "max": round(sirali[-1], 6),
    }


def palme11_veri_seti_uret(
    kaynaklar: Iterable[Palme11Kaynagi],
    cikti_dizini: str,
    *,
    dpi: int = VARSAYILAN_DPI,
    min_skor: float = VARSAYILAN_MIN_SKOR,
    min_uzak_fark: float = VARSAYILAN_MIN_UZAK_FARK,
    max_ortusme: float = VARSAYILAN_MAX_ORTUSME,
    max_uye: int = VARSAYILAN_MAX_UYE,
    max_toplam_bayt: int = VARSAYILAN_MAX_TOPLAM_BAYT,
    max_uye_bayt: int = VARSAYILAN_MAX_UYE_BAYT,
    max_piksel: int = VARSAYILAN_MAX_PIKSEL,
    renderer: Callable[[str, int, int], object] | None = None,
) -> dict:
    """İki profile ait doğrulanmış train + diagnostic holdout üretir."""
    kaynaklar = sorted(
        list(kaynaklar), key=lambda kaynak: kaynak.profil.kimlik
    )
    if not kaynaklar:
        raise ValueError("en az bir Palme11 kaynağı gerekli")
    profil_kimlikleri = [kaynak.profil.kimlik for kaynak in kaynaklar]
    if len(profil_kimlikleri) != len(set(profil_kimlikleri)):
        raise ValueError("aynı profil birden çok kez verilemez")
    if not isinstance(dpi, int) or isinstance(dpi, bool) or dpi <= 0:
        raise ValueError("dpi pozitif tam sayı olmalı")
    cikti_dizini = os.path.abspath(os.fspath(cikti_dizini))
    if os.path.lexists(cikti_dizini):
        raise Palme11VeriHatasi(
            f"çıktı yolu zaten var; üzerine yazılmadı: {cikti_dizini}"
        )

    pdf_raporlari = {
        kaynak.profil.kimlik: _pdf_kimligini_dogrula(kaynak)
        for kaynak in kaynaklar
    }
    zip_raporlari = [
        zip_denetle(
            kaynak.zip_yolu,
            kaynak.profil,
            max_uye=max_uye,
            max_toplam_bayt=max_toplam_bayt,
            max_uye_bayt=max_uye_bayt,
            max_piksel=max_piksel,
        )
        for kaynak in kaynaklar
    ]
    kayitlar, atilan_tekrarlar = _benzersiz_kayitlari_sec(zip_raporlari)
    kaynak_haritasi = {
        kaynak.profil.kimlik: kaynak for kaynak in kaynaklar
    }
    zip_rapor_haritasi = {
        rapor["profil"].kimlik: rapor for rapor in zip_raporlari
    }
    sayfalar: dict[tuple[str, int], list[CropKaydi]] = \
        collections.defaultdict(list)
    for kayit in kayitlar:
        sayfalar[(kayit.profil_kimligi, kayit.sayfa)].append(kayit)

    kimlik_nesnesi = {
        "profiles": [
            {
                "id": kaynak.profil.kimlik,
                "pdf_sha256": pdf_raporlari[kaynak.profil.kimlik]["sha256"],
                "zip_sha256": zip_rapor_haritasi[kaynak.profil.kimlik]
                ["zip_sha256"],
                "crop_dpi": kaynak.profil.crop_dpi,
            }
            for kaynak in kaynaklar
        ],
        "dpi": dpi,
        "min_score": min_skor,
        "min_remote_gap": min_uzak_fark,
        "kept_crop_pixel_sha256": [
            kayit.pixel_sha256 for kayit in kayitlar
        ],
    }
    kimlik_sha = hashlib.sha256(json.dumps(
        kimlik_nesnesi,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")).hexdigest()
    dataset_id = f"palme11-verified-{kimlik_sha[:16]}"

    ebeveyn = os.path.dirname(cikti_dizini)
    os.makedirs(ebeveyn, exist_ok=True)
    staging = tempfile.mkdtemp(prefix=".palme11-veri-", dir=ebeveyn)
    render_fonksiyonu = renderer or ortak.pdftoppm_sayfa_render
    train_ornekler: list[dict] = []
    tanisal_ornekler: list[dict] = []
    sayfa_raporlari: list[dict] = []
    tum_skorlar: list[float] = []
    tum_uzak_farklar: list[float] = []
    tum_son_bosluk_kirpmalari: list[float] = []
    try:
        with contextlib.ExitStack() as yigin:
            arsivler = {
                kaynak.profil.kimlik: yigin.enter_context(
                    zipfile.ZipFile(kaynak.zip_yolu)
                )
                for kaynak in kaynaklar
            }
            for (profil_kimligi, sayfa_no) in sorted(sayfalar):
                kaynak = kaynak_haritasi[profil_kimligi]
                profil = kaynak.profil
                sayfa = _renderer_sonucunu_rgb(
                    render_fonksiyonu(kaynak.pdf_yolu, sayfa_no, dpi),
                    sayfa_no,
                )
                sorular: list[dict] = []
                for kayit in sorted(
                    sayfalar[(profil_kimligi, sayfa_no)],
                    key=lambda k: (
                        k.unite,
                        k.sinav_turu,
                        k.sinav_no,
                        k.soru,
                    ),
                ):
                    veri = arsivler[profil_kimligi].read(kayit.uye_adi)
                    if _sha256_bayt(veri) != kayit.encoded_sha256:
                        raise Palme11VeriHatasi(
                            f"ZIP üyesi audit sonrasında değişti: "
                            f"{kayit.uye_adi}"
                        )
                    with Image.open(io.BytesIO(veri)) as acik:
                        acik.load()
                        ham_crop = acik.convert("RGB")
                    crop = ortak._crop_olcekle(
                        ham_crop,
                        dpi=dpi,
                        crop_dpi=profil.crop_dpi,
                    )
                    try:
                        eslesme = crop_eslestir_uzak_tepe(
                            sayfa,
                            crop,
                            min_skor=min_skor,
                            min_uzak_fark=min_uzak_fark,
                        )
                        yerel_capa = turuncu_capa_kutusu(crop)
                        govde = govde_icerik_kutusu(
                            eslesme["kutu"], crop)
                    except (Palme11VeriHatasi,
                            ortak.PalmeVeriHatasi) as hata:
                        raise Palme11VeriHatasi(
                            f"{kayit.uye_adi}: {hata}"
                        ) from hata
                    mx0, my0, mx1, my1 = eslesme["kutu"]
                    bx0, by0, bx1, by1 = govde
                    ax0, ay0, ax1, ay1 = yerel_capa
                    capa = (
                        mx0 + ax0,
                        my0 + ay0,
                        mx0 + ax1,
                        my0 + ay1,
                    )
                    if not (
                        bx0 <= capa[0] < capa[2] <= bx1
                        and by0 <= capa[1] < capa[3] <= by1
                    ):
                        raise Palme11VeriHatasi(
                            f"{kayit.uye_adi}: çapa gövde kutusu dışında"
                        )
                    skor = float(eslesme["skor"])
                    uzak_fark = float(eslesme["uzak_fark"])
                    tum_skorlar.append(skor)
                    tum_uzak_farklar.append(uzak_fark)
                    tum_son_bosluk_kirpmalari.append(
                        eslesme["kutu"][3] - govde[3]
                    )
                    sorular.append({
                        "question_id": kayit.soru_id,
                        "local_question_id": kayit.yerel_soru_id,
                        "member": kayit.uye_adi,
                        "unit": kayit.unite,
                        "exam_type": kayit.sinav_turu,
                        "exam_no": kayit.sinav_no,
                        "question": kayit.soru,
                        "source_page": sayfa_no,
                        "encoded_crop_sha256": kayit.encoded_sha256,
                        "pixel_sha256": kayit.pixel_sha256,
                        "original_crop_size": [ham_crop.width, ham_crop.height],
                        "aligned_crop_size": [crop.width, crop.height],
                        "alignment_score": round(skor, 6),
                        "alignment_remote_score": round(
                            float(eslesme["uzak_skor"]), 6
                        ),
                        "alignment_remote_gap": round(uzak_fark, 6),
                        "matched_crop_box": list(eslesme["kutu"]),
                        "body_box": list(govde),
                        "trailing_padding_trimmed_px": (
                            eslesme["kutu"][3] - govde[3]
                        ),
                        "anchor_box": list(capa),
                    })
                sorular.sort(key=lambda soru: (
                    soru["body_box"][1],
                    soru["body_box"][0],
                    soru["unit"],
                    soru["local_question_id"],
                ))
                try:
                    ortak.govde_kutularini_dogrula(
                        sorular, max_ortusme=max_ortusme
                    )
                except ortak.PalmeVeriHatasi as hata:
                    raise Palme11VeriHatasi(str(hata)) from hata
                bolum = (
                    "diagnostic_holdout"
                    if any(soru["unit"] == 12 for soru in sorular)
                    else "train"
                )
                ad = f"{profil_kimligi}-p{sayfa_no:04d}"
                image_rel = f"images/{bolum}/{ad}.png"
                label_rel = f"labels/{bolum}/{ad}.txt"
                image_yolu = os.path.join(staging, *image_rel.split("/"))
                label_yolu = os.path.join(staging, *label_rel.split("/"))
                os.makedirs(os.path.dirname(image_yolu), exist_ok=True)
                os.makedirs(os.path.dirname(label_yolu), exist_ok=True)
                sayfa.save(image_yolu, "PNG", compress_level=3)
                satirlar = []
                for soru in sorular:
                    satirlar.append(ortak._yolo_satiri(
                        0, soru["anchor_box"], sayfa.width, sayfa.height
                    ))
                    satirlar.append(ortak._yolo_satiri(
                        1, soru["body_box"], sayfa.width, sayfa.height
                    ))
                with open(label_yolu, "w", encoding="utf-8") as hedef:
                    hedef.write("\n".join(satirlar) + "\n")
                ornek = {
                    "image": image_rel,
                    "label": label_rel,
                    "document_sha256": pdf_raporlari[profil_kimligi]["sha256"],
                    "page": sayfa_no,
                    "publisher_group": YAYINEVI_GRUBU,
                    "annotation_origin": ETIKET_KAYNAGI,
                    "alignment_score": round(
                        min(soru["alignment_score"] for soru in sorular), 6
                    ),
                    "alignment_remote_gap": round(
                        min(
                            soru["alignment_remote_gap"]
                            for soru in sorular
                        ),
                        6,
                    ),
                    "source_profile": profil_kimligi,
                    "crop_dpi": profil.crop_dpi,
                    "render_dpi": dpi,
                    "book_id": profil.book_id,
                    "book_sha256": pdf_raporlari[profil_kimligi]["sha256"],
                    "source_archive_sha256": (
                        zip_rapor_haritasi[profil_kimligi]["zip_sha256"]
                    ),
                    "page_index": sayfa_no - 1,
                    "image_sha256": _sha256_dosya(image_yolu),
                    "label_sha256": _sha256_dosya(label_yolu),
                }
                if bolum == "train":
                    train_ornekler.append(ornek)
                else:
                    tanisal_ornekler.append(ornek)
                sayfa_raporlari.append({
                    "source_profile": profil_kimligi,
                    "book_id": profil.book_id,
                    "page": sayfa_no,
                    "partition": bolum,
                    "width": sayfa.width,
                    "height": sayfa.height,
                    "units": sorted({soru["unit"] for soru in sorular}),
                    "image": image_rel,
                    "label": label_rel,
                    "minimum_alignment_score": ornek["alignment_score"],
                    "minimum_alignment_remote_gap": (
                        ornek["alignment_remote_gap"]
                    ),
                    "questions": sorular,
                })

        if not train_ornekler:
            raise Palme11VeriHatasi("ünite 1-11 train sayfası üretilemedi")
        if not tanisal_ornekler:
            raise Palme11VeriHatasi(
                "ünite 12 diagnostic holdout sayfası üretilemedi"
            )
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
            "policy": (
                "Ünite 12 içeren tam sayfalar; eğitim manifesti dışında"
            ),
            "samples": tanisal_ornekler,
        }
        profil_raporlari = []
        for kaynak in kaynaklar:
            profil = kaynak.profil
            zip_raporu = zip_rapor_haritasi[profil.kimlik]
            profil_raporlari.append({
                "source_profile": profil.kimlik,
                "book_id": profil.book_id,
                "crop_reference_dpi": profil.crop_dpi,
                "pdf": dict(pdf_raporlari[profil.kimlik]),
                "zip": {
                    "sha256": zip_raporu["zip_sha256"],
                    "size": zip_raporu["zip_size"],
                    "member_count": zip_raporu["member_count"],
                    "crop_count": zip_raporu["crop_count"],
                    "total_uncompressed_bytes": (
                        zip_raporu["total_uncompressed_bytes"]
                    ),
                    "unique_encoded_images": (
                        zip_raporu["unique_encoded_images"]
                    ),
                    "unique_decoded_rgb_images": (
                        zip_raporu["unique_decoded_rgb_images"]
                    ),
                    "metadata_sha256": zip_raporu["metadata_sha256"],
                    "csv": zip_raporu["csv"],
                },
            })
        rapor = {
            "schema_version": RAPOR_SEMA_SURUMU,
            "generator_version": URETICI_SURUMU,
            "dataset_id": dataset_id,
            "classes": list(SINIFLAR),
            "label_classes_present": [0, 1],
            "annotation_origin": ETIKET_KAYNAGI,
            "publisher_group": YAYINEVI_GRUBU,
            "sources": profil_raporlari,
            "settings": {
                "render_dpi": dpi,
                "minimum_alignment_score": min_skor,
                "minimum_alignment_remote_gap": min_uzak_fark,
                "maximum_small_box_overlap": max_ortusme,
                "hsv_anchor_hue": [0, 20],
                "unit12_policy": "full_page_diagnostic_holdout",
                "body_box_policy": (
                    "full_crop_match_then_trailing_whitespace_trim"
                ),
            },
            "deduplication": {
                "input_crop_count": sum(
                    rapor["crop_count"] for rapor in zip_raporlari
                ),
                "unique_decoded_rgb_crop_count": len(kayitlar),
                "decoded_rgb_duplicates_removed": len(atilan_tekrarlar),
                "removed": atilan_tekrarlar,
            },
            "alignment": {
                "score": _oran_ozeti(tum_skorlar),
                "remote_gap": _oran_ozeti(tum_uzak_farklar),
                "trailing_padding_trimmed_px": _oran_ozeti(
                    tum_son_bosluk_kirpmalari
                ),
            },
            "summary": {
                "train_pages": len(train_ornekler),
                "diagnostic_holdout_pages": len(tanisal_ornekler),
                "question_count": sum(
                    len(sayfa["questions"]) for sayfa in sayfa_raporlari
                ),
                "train_questions": sum(
                    len(sayfa["questions"])
                    for sayfa in sayfa_raporlari
                    if sayfa["partition"] == "train"
                ),
                "diagnostic_holdout_questions": sum(
                    len(sayfa["questions"])
                    for sayfa in sayfa_raporlari
                    if sayfa["partition"] == "diagnostic_holdout"
                ),
            },
            "pages": sayfa_raporlari,
        }
        manifest_yolu = os.path.join(staging, "manifest.json")
        _json_yaz(manifest_yolu, manifest)
        _json_yaz(
            os.path.join(staging, "diagnostic_manifest.json"),
            tanisal_manifest,
        )
        _json_yaz(
            os.path.join(staging, "provenance_alignment_report.json"),
            rapor,
        )
        _manifesti_dogrula(manifest_yolu)
        if os.path.lexists(cikti_dizini):
            raise Palme11VeriHatasi(
                "çıktı üretim sırasında belirdi; üzerine yazılmadı"
            )
        os.rename(staging, cikti_dizini)
        staging = ""
        return {
            "ok": True,
            "output": cikti_dizini,
            "manifest": os.path.join(cikti_dizini, "manifest.json"),
            "diagnostic_manifest": os.path.join(
                cikti_dizini, "diagnostic_manifest.json"
            ),
            "report": os.path.join(
                cikti_dizini, "provenance_alignment_report.json"
            ),
            "dataset_id": dataset_id,
            "summary": rapor["summary"],
            "alignment": rapor["alignment"],
            "deduplication": rapor["deduplication"],
        }
    except Exception:
        if staging:
            shutil.rmtree(staging, ignore_errors=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Palme 11 standart + Fen Lisesi crop ZIP'lerinden doğrulanmış "
            "tam-sayfa train/diagnostic veri seti üret"
        )
    )
    parser.add_argument("--standart-pdf", required=True)
    parser.add_argument("--standart-zip", required=True)
    parser.add_argument("--fen-pdf", required=True)
    parser.add_argument("--fen-zip", required=True)
    parser.add_argument("--cikti", required=True)
    parser.add_argument("--dpi", type=int, default=VARSAYILAN_DPI)
    parser.add_argument(
        "--min-skor", type=float, default=VARSAYILAN_MIN_SKOR
    )
    parser.add_argument(
        "--min-uzak-fark", type=float, default=VARSAYILAN_MIN_UZAK_FARK
    )
    parser.add_argument(
        "--max-ortusme", type=float, default=VARSAYILAN_MAX_ORTUSME
    )
    args = parser.parse_args(argv)
    kaynaklar = [
        Palme11Kaynagi(
            STANDART_PROFIL, args.standart_pdf, args.standart_zip
        ),
        Palme11Kaynagi(FEN_PROFIL, args.fen_pdf, args.fen_zip),
    ]
    try:
        sonuc = palme11_veri_seti_uret(
            kaynaklar,
            args.cikti,
            dpi=args.dpi,
            min_skor=args.min_skor,
            min_uzak_fark=args.min_uzak_fark,
            max_ortusme=args.max_ortusme,
        )
    except (Palme11VeriHatasi, ValueError) as hata:
        parser.exit(2, f"HATA: {hata}\n")
    print(json.dumps(sonuc, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
