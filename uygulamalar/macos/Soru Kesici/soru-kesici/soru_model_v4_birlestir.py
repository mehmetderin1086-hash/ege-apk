#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ql_v3 ile güvenli Palme ekini ayrı bir ql_v4 veri setinde birleştirir.

Kaynak veri setleri salt okunur kabul edilir. Çıktı daha önce var olamaz ve
kaynak köklerinin içine yazılamaz. Görüntüler mümkünse hardlink, dosya sistemi
izin vermiyorsa kopya olarak oluşturulur.

Temizlik sırası:

* eski üreticinin aynı geometriye yazdığı class 1 + class 3 çifti, üretici
  kanıtına göre tek class 3 (solution_or_answer) satırına dönüştürülür;
* ``(document_sha256, page)`` mantıksal sayfa anahtarında doğrulanmış ek,
  eski pseudo-label sayfasının tamamının yerini alır; diagnostic anahtarları
  bütün eğitim girdilerinden bastırılır;
* görüntüler açılıp RGB piksel ızgarasının SHA-256 özeti alınır;
* aynı piksel grubunda normalize YOLO etiketleri çelişirse grubun tamamı
  atılır, çelişmiyorsa deterministik tek temsilci tutulur;
* yayınevi grupları ve aynı sayfayla birbirine bağlanan gruplar bölünmeden,
  sayfa ağırlıklı 70/15/7/8 splitlerine yeniden atanır;
* ek manifestteki Palme grubu train'e; ql_v3'te kanıtlanmış nadir sınıf
  destek grupları validation/holdout'a sabitlenir. Birleşim bileşeni iki
  farklı zorunlu split isterse işlem fail-closed durur.

Kullanım::

    python soru_model_v4_birlestir.py \
      --ql-v3-manifest /veri/ql_v3/manifest.json \
      --palme-manifest /veri/palme/manifest.json \
      --palme-diagnostic-manifest /veri/palme/diagnostic_manifest.json \
      --cikti /veri/ql_v4
"""

import argparse
import collections
import dataclasses
import decimal
import errno
import hashlib
import json
import math
import os
import pathlib
import shutil
import struct
import sys
import tempfile

from PIL import Image


SEMA_SURUMU = "soru-kesici.question-layout-training/v1"
SINIFLAR = (
    "question_anchor",
    "question_body",
    "shared_stimulus",
    "solution_or_answer",
)
SPLITLER = ("train", "validation", "calibration", "holdout")
SPLIT_HEDEFLERI = {
    "train": 0.70,
    "validation": 0.15,
    "calibration": 0.07,
    "holdout": 0.08,
}
TANISAL_SEMA_SURUMU = "soru-kesici.question-layout-diagnostic/v1"
# ql_v3 gerçek sınıf dağılımından, kaynak/piksel bağlantıları korunarak seçilen
# nadir sınıf destek grupları. Bir grup girdide yoksa kural uygulanmaz.
NADIR_SINIF_ZORUNLU_GRUPLARI = {
    "pub-b89ade": (
        "train",
        ("shared_stimulus_train_support", "solution_or_answer_train_support"),
    ),
    "pub-17ba07": (
        "validation",
        ("shared_stimulus_validation_support",),
    ),
    "pub-26be78": (
        "validation",
        ("solution_or_answer_validation_support",),
    ),
    "pub-8bf958": (
        "holdout",
        ("shared_stimulus_holdout_support",),
    ),
    "pub-974342": (
        "holdout",
        ("solution_or_answer_holdout_support",),
    ),
}
GORUNTU_UZANTILARI = frozenset({
    ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp",
})

_PROVENANS_HASH_ALANLARI = frozenset({
    "archive_sha256",
    "source_archive_sha256",
    "book_sha256",
    "input_sha256",
    "image_sha256",
    "label_sha256",
})
_PROVENANS_KIMLIK_ALANLARI = frozenset({
    "annotation_origin",
    "archive_id",
    "book_id",
    "pipeline_id",
    "pipeline_version",
    "source_profile",
})
_PROVENANS_TAM_SAYI_ALANLARI = frozenset({
    "page_index",
    "archive_index",
    "crop_dpi",
    "render_dpi",
})
_PROVENANS_ORAN_ALANLARI = frozenset({
    "alignment_score",
    "alignment_remote_gap",
    "confidence",
})
_SINIR_TOLERANSI = decimal.Decimal("0.000001")


class BirlestirmeHatasi(ValueError):
    """Güvenli biçimde ql_v4 üretilemedi."""


@dataclasses.dataclass(frozen=True)
class _Ornek:
    rol: str
    dataset_id: str
    manifest_sha256: str
    eski_split: str
    veri_koku: str
    image_rel: str
    label_rel: str
    image_yolu: str
    label_yolu: str
    document_sha256: str
    page: int
    publisher_group: str
    pixel_sha256: str
    etiketler: tuple
    etiket_satirlari: tuple
    govde_cozume_yeniden_siniflanan: int
    cikarilan_tekrar: int
    provenance: dict


class _BirlesimKumesi:
    """Deterministik, küçük bir union-find."""

    def __init__(self):
        self._ebeveyn = {}

    def ekle(self, deger):
        self._ebeveyn.setdefault(deger, deger)

    def bul(self, deger):
        self.ekle(deger)
        ebeveyn = self._ebeveyn[deger]
        if ebeveyn != deger:
            self._ebeveyn[deger] = self.bul(ebeveyn)
        return self._ebeveyn[deger]

    def birlestir(self, sol, sag):
        sol_kok, sag_kok = self.bul(sol), self.bul(sag)
        if sol_kok == sag_kok:
            return sol_kok
        # JSON sırası veya giriş sırası kökü değiştirmesin.
        yeni, eski = sorted((sol_kok, sag_kok))
        self._ebeveyn[eski] = yeni
        return yeni


def _dosya_sha256(yol):
    ozet = hashlib.sha256()
    with open(yol, "rb") as dosya:
        for parca in iter(lambda: dosya.read(1 << 20), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _sha256_mi(deger):
    return (
        isinstance(deger, str)
        and len(deger) == 64
        and all(harf in "0123456789abcdef" for harf in deger.lower())
    )


def _guvenli_goreli_yol(deger, alan, nokta_olabilir=False):
    if not isinstance(deger, str) or not deger.strip():
        raise BirlestirmeHatasi(f"{alan}: boş/olmayan yol")
    ham = deger.strip()
    if "\x00" in ham or "://" in ham:
        raise BirlestirmeHatasi(f"{alan}: harici/geçersiz yol")
    if pathlib.PureWindowsPath(ham).drive:
        raise BirlestirmeHatasi(f"{alan}: mutlak Windows yolu yasak")
    ham = ham.replace("\\", "/")
    saf = pathlib.PurePosixPath(ham)
    if saf.is_absolute():
        raise BirlestirmeHatasi(f"{alan}: yalnız göreli yol kullanılabilir")
    parcalar = tuple(parca for parca in saf.parts if parca not in ("", "."))
    if ".." in parcalar:
        raise BirlestirmeHatasi(f"{alan}: üst dizine çıkış yasak")
    if not parcalar:
        if nokta_olabilir:
            return "."
        raise BirlestirmeHatasi(f"{alan}: boş göreli yol")
    return "/".join(parcalar)


def _kok_altindaki_dosya(kok, goreli, alan):
    hedef = os.path.realpath(os.path.join(kok, *goreli.split("/")))
    try:
        ortak = os.path.commonpath((os.path.realpath(kok), hedef))
    except ValueError:
        ortak = ""
    if ortak != os.path.realpath(kok):
        raise BirlestirmeHatasi(f"{alan}: veri kökü dışına çıkıyor")
    if not os.path.isfile(hedef):
        raise BirlestirmeHatasi(f"{alan}: dosya bulunamadı")
    return hedef


def _guvenli_kimlik_mi(deger):
    return (
        isinstance(deger, str)
        and 0 < len(deger.strip()) <= 128
        and "://" not in deger
        and "/" not in deger
        and "\\" not in deger
        and not any(ord(harf) < 32 for harf in deger)
    )


def _dataset_kimligi(deger, manifest_sha256, rol):
    if _guvenli_kimlik_mi(deger):
        return deger.strip()
    return f"{rol}-{manifest_sha256[:16]}"


def _provenans_temizle(ornek):
    """Yalnız opak kimlik/hash/sayaç provenance alanlarını geçirir."""
    kaynaklar = []
    if isinstance(ornek.get("provenance"), dict):
        kaynaklar.append(ornek["provenance"])
    # Manifestin doğrulanmış üst seviye alanları nested metadata'yı ezer.
    kaynaklar.append(ornek)
    temiz = {}
    for kaynak in kaynaklar:
        for alan in _PROVENANS_HASH_ALANLARI:
            deger = kaynak.get(alan)
            if _sha256_mi(deger):
                temiz[alan] = deger.lower()
        for alan in _PROVENANS_KIMLIK_ALANLARI:
            deger = kaynak.get(alan)
            if _guvenli_kimlik_mi(deger):
                temiz[alan] = deger.strip()
        for alan in _PROVENANS_TAM_SAYI_ALANLARI:
            deger = kaynak.get(alan)
            if isinstance(deger, int) and not isinstance(deger, bool) \
                    and deger >= 0:
                temiz[alan] = deger
        for alan in _PROVENANS_ORAN_ALANLARI:
            deger = kaynak.get(alan)
            if not isinstance(deger, (int, float)) \
                    or isinstance(deger, bool):
                continue
            try:
                oran = float(deger)
            except (OverflowError, ValueError):
                continue
            if math.isfinite(oran) and 0 <= oran <= 1:
                temiz[alan] = oran
    return temiz


def _ondalik_yaz(deger):
    if deger == 0:
        return "0"
    return format(deger.normalize(), "f")


def _etiketleri_oku(yol, alan):
    try:
        with open(yol, encoding="utf-8") as dosya:
            satirlar = dosya.read().splitlines()
    except (OSError, UnicodeError) as hata:
        raise BirlestirmeHatasi(f"{alan}: etiket okunamadı: {hata}") from hata

    ham_etiketler = []
    for satir_no, satir in enumerate(satirlar, 1):
        satir = satir.strip()
        if not satir:
            continue
        bolumler = satir.split()
        if len(bolumler) != 5:
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: YOLO satırı 5 alan olmalı")
        try:
            sinif = int(bolumler[0])
            koordinatlar = tuple(
                decimal.Decimal(deger) for deger in bolumler[1:])
        except (ValueError, decimal.InvalidOperation) as hata:
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: sayısal alan geçersiz") from hata
        if not 0 <= sinif < len(SINIFLAR):
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: sınıf kimliği 0..3 olmalı")
        if not all(deger.is_finite() for deger in koordinatlar):
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: koordinatlar sonlu olmalı")
        x, y, genislik, yukseklik = koordinatlar
        if not (
            0 <= x <= 1
            and 0 <= y <= 1
            and 0 < genislik <= 1
            and 0 < yukseklik <= 1
        ):
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: normalize kutu [0,1] dışında")
        if (
            x - genislik / 2 < -_SINIR_TOLERANSI
            or x + genislik / 2 > 1 + _SINIR_TOLERANSI
            or y - yukseklik / 2 < -_SINIR_TOLERANSI
            or y + yukseklik / 2 > 1 + _SINIR_TOLERANSI
        ):
            raise BirlestirmeHatasi(
                f"{alan}:{satir_no}: kutu görüntü dışına taşıyor")
        ham_etiketler.append((sinif,) + koordinatlar)

    cozum_geometrileri = {
        etiket[1:] for etiket in ham_etiketler if etiket[0] == 3
    }
    # Eski soru_model_veri üreticisi çözüm rolündeki her m için önce class 1,
    # hemen ardından aynı kutuya class 3 yazıyordu. Yeni üretici aynı rolde
    # yalnız class 3 yazıyor. Bu nedenle exact 1+3 çifti belirsizlik değil;
    # intended semantik class 3'tür ve class 1 satırı migrasyonda silinir.
    govde_cozume_yeniden_siniflanan = sum(
        1 for etiket in ham_etiketler
        if etiket[0] == 1 and etiket[1:] in cozum_geometrileri
    )
    yeniden_siniflanmis = [
        etiket for etiket in ham_etiketler
        if not (etiket[0] == 1 and etiket[1:] in cozum_geometrileri)
    ]
    benzersiz = tuple(sorted(set(yeniden_siniflanmis)))
    cikarilan_tekrar = len(yeniden_siniflanmis) - len(benzersiz)
    kanonik_satirlar = tuple(
        " ".join((
            str(etiket[0]),
            *(_ondalik_yaz(deger) for deger in etiket[1:]),
        ))
        for etiket in benzersiz
    )
    return (
        benzersiz,
        kanonik_satirlar,
        govde_cozume_yeniden_siniflanan,
        cikarilan_tekrar,
    )


def _rgb_piksel_sha256(yol):
    """Boyut + açılmış RGB piksel ızgarasının kanonik SHA-256 özeti."""
    try:
        with Image.open(yol) as goruntu:
            goruntu.load()
            rgb = goruntu.convert("RGB")
            genislik, yukseklik = rgb.size
            ozet = hashlib.sha256()
            ozet.update(b"soru-kesici/rgb-pixels/v1\0")
            ozet.update(struct.pack(">QQ", genislik, yukseklik))
            ozet.update(rgb.tobytes())
            return ozet.hexdigest()
    except Exception as hata:  # Pillow farklı çözme istisnaları kullanabilir.
        raise BirlestirmeHatasi(
            f"görüntü RGB olarak çözülemedi: {yol}: {hata}") from hata


def _manifest_oku(manifest_yolu, rol):
    manifest_yolu = os.path.abspath(os.fspath(manifest_yolu))
    try:
        with open(manifest_yolu, encoding="utf-8") as dosya:
            manifest = json.load(dosya)
    except (OSError, ValueError) as hata:
        raise BirlestirmeHatasi(
            f"{rol} manifesti okunamadı: {hata}") from hata
    if not isinstance(manifest, dict):
        raise BirlestirmeHatasi(f"{rol} manifesti JSON nesnesi olmalı")
    if manifest.get("schema_version") != SEMA_SURUMU:
        raise BirlestirmeHatasi(f"{rol}: schema_version uyumsuz")
    if tuple(manifest.get("classes") or ()) != SINIFLAR:
        raise BirlestirmeHatasi(f"{rol}: 4 sınıflı sözleşme/sıra uyumsuz")

    manifest_sha = _dosya_sha256(manifest_yolu)
    dataset_id = _dataset_kimligi(
        manifest.get("dataset_id"), manifest_sha, rol)
    root_rel = _guvenli_goreli_yol(
        manifest.get("root", "."), f"{rol}.root", nokta_olabilir=True)
    manifest_dizini = os.path.dirname(manifest_yolu)
    veri_koku = os.path.realpath(os.path.join(
        manifest_dizini, *(() if root_rel == "." else root_rel.split("/"))))
    try:
        ortak = os.path.commonpath((os.path.realpath(manifest_dizini),
                                    veri_koku))
    except ValueError:
        ortak = ""
    if ortak != os.path.realpath(manifest_dizini):
        raise BirlestirmeHatasi(f"{rol}.root manifest dışına çıkıyor")
    if not os.path.isdir(veri_koku):
        raise BirlestirmeHatasi(f"{rol}.root veri dizini bulunamadı")

    splitler = manifest.get("splits")
    if not isinstance(splitler, dict):
        raise BirlestirmeHatasi(f"{rol}.splits nesnesi eksik")
    bilinmeyen = sorted(set(splitler) - set(SPLITLER))
    if bilinmeyen:
        raise BirlestirmeHatasi(
            f"{rol}: bilinmeyen split: {', '.join(bilinmeyen)}")

    ornekler = []
    for split in SPLITLER:
        split_ornekleri = splitler.get(split, [])
        if not isinstance(split_ornekleri, list):
            raise BirlestirmeHatasi(f"{rol}.splits.{split} liste olmalı")
        for sira, ornek in enumerate(split_ornekleri):
            alan = f"{rol}.splits.{split}[{sira}]"
            if not isinstance(ornek, dict):
                raise BirlestirmeHatasi(f"{alan}: nesne olmalı")
            image_rel = _guvenli_goreli_yol(
                ornek.get("image"), f"{alan}.image")
            label_rel = _guvenli_goreli_yol(
                ornek.get("label"), f"{alan}.label")
            if pathlib.PurePosixPath(image_rel).suffix.lower() \
                    not in GORUNTU_UZANTILARI:
                raise BirlestirmeHatasi(
                    f"{alan}.image: desteklenmeyen görüntü uzantısı")
            if pathlib.PurePosixPath(label_rel).suffix.lower() != ".txt":
                raise BirlestirmeHatasi(f"{alan}.label: .txt olmalı")
            image_yolu = _kok_altindaki_dosya(
                veri_koku, image_rel, f"{alan}.image")
            label_yolu = _kok_altindaki_dosya(
                veri_koku, label_rel, f"{alan}.label")
            for ozet_alani, dosya_yolu in (
                ("image_sha256", image_yolu),
                ("label_sha256", label_yolu),
            ):
                beklenen_ozet = ornek.get(ozet_alani)
                if beklenen_ozet is None \
                        and isinstance(ornek.get("provenance"), dict):
                    beklenen_ozet = ornek["provenance"].get(ozet_alani)
                if beklenen_ozet is None:
                    continue
                if not _sha256_mi(beklenen_ozet) \
                        or beklenen_ozet.lower() != _dosya_sha256(dosya_yolu):
                    raise BirlestirmeHatasi(
                        f"{alan}.{ozet_alani} dosyayla eşleşmiyor")

            belge_sha = ornek.get("document_sha256")
            if not _sha256_mi(belge_sha):
                raise BirlestirmeHatasi(
                    f"{alan}.document_sha256 geçersiz")
            page = ornek.get("page")
            if not isinstance(page, int) or isinstance(page, bool) or page < 1:
                raise BirlestirmeHatasi(
                    f"{alan}.page pozitif tam sayı olmalı")
            grup = ornek.get("publisher_group")
            if not _guvenli_kimlik_mi(grup):
                raise BirlestirmeHatasi(
                    f"{alan}.publisher_group güvenli/opak kimlik olmalı")
            grup = grup.strip()

            (
                etiketler,
                etiket_satirlari,
                govde_cozume_yeniden_siniflanan,
                cikarilan_tekrar,
            ) = _etiketleri_oku(label_yolu, f"{alan}.label")
            piksel_sha = _rgb_piksel_sha256(image_yolu)
            ornekler.append(_Ornek(
                rol=rol,
                dataset_id=dataset_id,
                manifest_sha256=manifest_sha,
                eski_split=split,
                veri_koku=veri_koku,
                image_rel=image_rel,
                label_rel=label_rel,
                image_yolu=image_yolu,
                label_yolu=label_yolu,
                document_sha256=belge_sha.lower(),
                page=page,
                publisher_group=grup,
                pixel_sha256=piksel_sha,
                etiketler=etiketler,
                etiket_satirlari=etiket_satirlari,
                govde_cozume_yeniden_siniflanan=(
                    govde_cozume_yeniden_siniflanan
                ),
                cikarilan_tekrar=cikarilan_tekrar,
                provenance=_provenans_temizle(ornek),
            ))
    if not ornekler:
        raise BirlestirmeHatasi(f"{rol}: manifestte örnek yok")
    return {
        "dataset_id": dataset_id,
        "manifest_sha256": manifest_sha,
        "veri_koku": veri_koku,
        "ornekler": ornekler,
    }


def _diagnostic_anahtarlari_oku(
        manifest_yolu, supplement_diagnostic_haritasi):
    """Doğrulanmış supplement'in eğitim dışı mantıksal sayfalarını okur."""
    if manifest_yolu is None:
        return {
            "manifest_sha256": None,
            "dataset_id": None,
            "anahtarlar": frozenset(),
        }
    manifest_yolu = os.path.abspath(os.fspath(manifest_yolu))
    try:
        with open(manifest_yolu, encoding="utf-8") as dosya:
            manifest = json.load(dosya)
    except (OSError, ValueError) as hata:
        raise BirlestirmeHatasi(
            f"Palme diagnostic manifesti okunamadı: {hata}") from hata
    if not isinstance(manifest, dict):
        raise BirlestirmeHatasi(
            "Palme diagnostic manifesti JSON nesnesi olmalı")
    if manifest.get("schema_version") != TANISAL_SEMA_SURUMU:
        raise BirlestirmeHatasi(
            "Palme diagnostic schema_version uyumsuz")
    if tuple(manifest.get("classes") or ()) != SINIFLAR:
        raise BirlestirmeHatasi(
            "Palme diagnostic 4 sınıflı sözleşme/sıra uyumsuz")
    diagnostic_dataset_id = manifest.get("dataset_id")
    supplement = supplement_diagnostic_haritasi.get(
        diagnostic_dataset_id)
    if supplement is None:
        raise BirlestirmeHatasi(
            "Palme diagnostic dataset_id hiçbir supplement ile eşleşmiyor")
    if manifest.get("partition") != "diagnostic_holdout":
        raise BirlestirmeHatasi(
            "Palme diagnostic partition diagnostic_holdout olmalı")
    ornekler = manifest.get("samples")
    if not isinstance(ornekler, list) or not ornekler:
        raise BirlestirmeHatasi(
            "Palme diagnostic samples dolu liste olmalı")
    anahtarlar = set()
    for sira, ornek in enumerate(ornekler):
        alan = f"palme_diagnostic.samples[{sira}]"
        if not isinstance(ornek, dict):
            raise BirlestirmeHatasi(f"{alan}: nesne olmalı")
        belge_sha = ornek.get("document_sha256")
        if not _sha256_mi(belge_sha):
            raise BirlestirmeHatasi(
                f"{alan}.document_sha256 geçersiz")
        page = ornek.get("page")
        if not isinstance(page, int) or isinstance(page, bool) or page < 1:
            raise BirlestirmeHatasi(
                f"{alan}.page pozitif tam sayı olmalı")
        grup = ornek.get("publisher_group")
        if grup not in supplement["publisher_groups"]:
            raise BirlestirmeHatasi(
                f"{alan}.publisher_group supplement ile eşleşmiyor")
        anahtar = (belge_sha.lower(), page)
        if anahtar in anahtarlar:
            raise BirlestirmeHatasi(
                f"{alan}: yinelenen diagnostic mantıksal sayfa")
        anahtarlar.add(anahtar)
    return {
        "manifest_sha256": _dosya_sha256(manifest_yolu),
        "dataset_id": manifest["dataset_id"],
        "supplement_dataset_id": supplement["dataset_id"],
        "anahtarlar": frozenset(anahtarlar),
    }


def _palme_grubunu_bul(ek_ornekleri, istenen=None):
    gruplar = sorted({ornek.publisher_group for ornek in ek_ornekleri})
    if istenen is not None:
        if not _guvenli_kimlik_mi(istenen) or istenen.strip() not in gruplar:
            raise BirlestirmeHatasi(
                "--palme-grubu ek manifestte bulunan güvenli bir grup olmalı")
        return istenen.strip()
    palme_adli = [
        grup for grup in gruplar if "palme" in grup.casefold()
    ]
    if len(palme_adli) == 1:
        return palme_adli[0]
    if len(gruplar) == 1:
        return gruplar[0]
    raise BirlestirmeHatasi(
        "ek manifestte Palme grubu belirsiz; --palme-grubu verilmeli")


def _temsilci_anahtari(ornek):
    # Eşdeğer sayfada ekin provenance'ını korumayı tercih et.
    return (
        0 if ornek.rol == "palme_supplement" else 1,
        ornek.dataset_id,
        ornek.publisher_group,
        ornek.document_sha256,
        ornek.page,
        ornek.image_rel,
        ornek.label_rel,
    )


def _splitleri_ata(kok_ornekleri, bileşen_gruplari, zorunlu_atamalar):
    agirliklar = {
        kok: len(ornekler)
        for kok, ornekler in kok_ornekleri.items()
        if ornekler
    }
    if len(agirliklar) < len(SPLITLER):
        raise BirlestirmeHatasi(
            "bütün yayınevi/tekrar bileşenleri korununca dört zorunlu "
            "split'i dolduracak en az 4 dolu grup yok")
    toplam = sum(agirliklar.values())
    hedef_sayilar = {
        split: toplam * SPLIT_HEDEFLERI[split] for split in SPLITLER
    }
    atama = {}
    sayilar = {split: 0 for split in SPLITLER}
    for kok, split in sorted(zorunlu_atamalar.items()):
        if split not in SPLITLER:
            raise BirlestirmeHatasi(
                f"bilinmeyen zorunlu split: {split}")
        if kok not in agirliklar:
            raise BirlestirmeHatasi(
                "zorunlu split bileşeninde tutulmuş örnek yok")
        atama[kok] = split
        sayilar[split] += agirliklar[kok]

    kalan = [
        kok for kok in agirliklar if kok not in atama
    ]
    kalan.sort(key=lambda kok: (
        -agirliklar[kok],
        tuple(sorted(bileşen_gruplari.get(kok, (kok,)))),
    ))
    split_sirasi = {split: sira for sira, split in enumerate(SPLITLER)}
    for sira, kok in enumerate(kalan):
        agirlik = agirliklar[kok]
        boslar = [split for split in SPLITLER if sayilar[split] == 0]
        kalan_adet = len(kalan) - sira
        adaylar = boslar if kalan_adet == len(boslar) else list(SPLITLER)

        def puan(split):
            # En büyük bileşenden başlayıp hedef kapasitesine göre en az
            # dolu split'i seçmek, küçük calibration/holdout hedeflerinin
            # ilk büyük grupları yutmasını önler.
            doluluk = (
                (sayilar[split] + agirlik)
                / max(hedef_sayilar[split], 1.0)
            )
            return doluluk, split_sirasi[split]

        secilen = min(adaylar, key=puan)
        atama[kok] = secilen
        sayilar[secilen] += agirlik

    if any(sayilar[split] == 0 for split in SPLITLER):
        bos = ", ".join(split for split in SPLITLER if sayilar[split] == 0)
        raise BirlestirmeHatasi(f"zorunlu split boş kaldı: {bos}")
    # Örneği kalmayan bileşenler çıktıda görünmez; yine de audit ataması
    # deterministik olsun.
    for kok in bileşen_gruplari:
        atama.setdefault(kok, "train")
    return atama, sayilar


def _bagla_veya_kopyala(kaynak, hedef):
    os.makedirs(os.path.dirname(hedef), exist_ok=True)
    try:
        os.link(kaynak, hedef)
        return "hardlink"
    except OSError as hata:
        kopyalanabilir = {
            errno.EXDEV,
            errno.EPERM,
            errno.EACCES,
            errno.EMLINK,
            getattr(errno, "ENOTSUP", errno.EINVAL),
            getattr(errno, "EOPNOTSUPP", errno.EINVAL),
        }
        if hata.errno not in kopyalanabilir:
            raise
    shutil.copy2(kaynak, hedef)
    return "copy"


def _kaynak_provenansi(ornek):
    sonuc = {
        "role": ornek.rol,
        "dataset_id": ornek.dataset_id,
        "manifest_sha256": ornek.manifest_sha256,
        "split": ornek.eski_split,
        "image_relpath": ornek.image_rel,
        "label_relpath": ornek.label_rel,
        "document_sha256": ornek.document_sha256,
        "page": ornek.page,
        "publisher_group": ornek.publisher_group,
    }
    if ornek.provenance:
        sonuc["metadata"] = dict(sorted(ornek.provenance.items()))
    return sonuc


def _cikis_tekrarlarini_dogrula(manifest_yolu):
    with open(manifest_yolu, encoding="utf-8") as dosya:
        manifest = json.load(dosya)
    kok = os.path.dirname(os.path.abspath(manifest_yolu))
    piksel_splitleri = collections.defaultdict(set)
    mantiksal_splitleri = collections.defaultdict(set)
    mantiksal_sayac = collections.Counter()
    grup_splitleri = collections.defaultdict(set)
    for split in SPLITLER:
        for sira, ornek in enumerate(manifest["splits"][split]):
            image_rel = _guvenli_goreli_yol(
                ornek.get("image"), f"çıktı.{split}[{sira}].image")
            image_yolu = _kok_altindaki_dosya(
                kok, image_rel, f"çıktı.{split}[{sira}].image")
            piksel_sha = _rgb_piksel_sha256(image_yolu)
            if ornek.get("pixel_sha256") != piksel_sha:
                raise BirlestirmeHatasi(
                    f"çıktı piksel özeti uyuşmuyor: {image_rel}")
            piksel_splitleri[piksel_sha].add(split)
            mantiksal = (
                ornek.get("document_sha256"),
                ornek.get("page"),
            )
            mantiksal_splitleri[mantiksal].add(split)
            mantiksal_sayac[mantiksal] += 1
            grup_splitleri[ornek["publisher_group"]].add(split)
    kalan_tekrar = {
        sha: splitler for sha, splitler in piksel_splitleri.items()
        if len(splitler) > 1
    }
    if kalan_tekrar:
        raise BirlestirmeHatasi(
            "çapraz-split çözülmüş RGB piksel tekrarı kaldı")
    mantiksal_tekrar = {
        anahtar: adet for anahtar, adet in mantiksal_sayac.items()
        if adet > 1
    }
    if mantiksal_tekrar:
        raise BirlestirmeHatasi(
            "çıktıda yinelenen mantıksal belge/sayfa kaldı")
    mantiksal_sizma = {
        anahtar: splitler
        for anahtar, splitler in mantiksal_splitleri.items()
        if len(splitler) > 1
    }
    if mantiksal_sizma:
        raise BirlestirmeHatasi(
            "mantıksal belge/sayfa birden çok split'e sızdı")
    sizan_gruplar = {
        grup: splitler for grup, splitler in grup_splitleri.items()
        if len(splitler) > 1
    }
    if sizan_gruplar:
        raise BirlestirmeHatasi("yayınevi grubu birden çok split'e sızdı")


def _cikti_kaynaktan_ayri_mi(cikti, veri_kokleri):
    cikti_gercek = os.path.realpath(cikti)
    for veri_koku in veri_kokleri:
        veri_gercek = os.path.realpath(veri_koku)
        try:
            ortak = os.path.commonpath((cikti_gercek, veri_gercek))
        except ValueError:
            ortak = ""
        if ortak in (cikti_gercek, veri_gercek):
            raise BirlestirmeHatasi(
                "ql_v4 çıktısı kaynak veri kökünden tamamen ayrı olmalı")


def _zorunlu_splitleri_coz(birlesim, tum_gruplar, palme_gruplari):
    istekler = [
        (grup, "train", "verified_palme_supplement_train")
        for grup in sorted(palme_gruplari)
    ]
    for grup, (split, nedenler) in sorted(
            NADIR_SINIF_ZORUNLU_GRUPLARI.items()):
        if grup in tum_gruplar:
            istekler.extend((grup, split, neden) for neden in nedenler)
    atamalar = {}
    nedenler = collections.defaultdict(set)
    for grup, split, neden in istekler:
        kok = birlesim.bul(grup)
        onceki = atamalar.get(kok)
        if onceki is not None and onceki != split:
            bagli = sorted(
                g for g in tum_gruplar if birlesim.bul(g) == kok)
            raise BirlestirmeHatasi(
                "bağlantılı bileşen çelişkili zorunlu split istiyor: "
                f"{bagli}: {onceki} ve {split}")
        atamalar[kok] = split
        nedenler[kok].add(neden)
    return atamalar, {
        kok: sorted(degerler) for kok, degerler in nedenler.items()
    }


def _sinif_destegi_raporu(tutulan, atama, birlesim):
    ornek_sayilari = {
        sinif: {split: 0 for split in SPLITLER}
        for sinif in range(len(SINIFLAR))
    }
    kutu_sayilari = {
        sinif: {split: 0 for split in SPLITLER}
        for sinif in range(len(SINIFLAR))
    }
    for temsilci, _kaynaklar in tutulan:
        split = atama[birlesim.bul(temsilci.publisher_group)]
        sayac = collections.Counter(
            etiket[0] for etiket in temsilci.etiketler)
        for sinif, adet in sayac.items():
            ornek_sayilari[sinif][split] += 1
            kutu_sayilari[sinif][split] += adet
    gerekli = ("train", "validation", "holdout")
    sinif_raporu = {}
    eksikler = []
    for sinif, ad in enumerate(SINIFLAR):
        eksik = [
            split for split in gerekli
            if ornek_sayilari[sinif][split] == 0
        ] if sinif in (2, 3) else []
        if eksik:
            eksikler.append({"class": ad, "splits": eksik})
        sinif_raporu[ad] = {
            "sample_counts": ornek_sayilari[sinif],
            "box_counts": kutu_sayilari[sinif],
            "required_publication_splits": (
                list(gerekli) if sinif in (2, 3) else []
            ),
            "missing_required_splits": eksik,
            "calibration_supported": (
                ornek_sayilari[sinif]["calibration"] > 0
            ),
        }
    return {
        "classes": sinif_raporu,
        "publication_gate": {
            "rare_class_coverage_ok": not eksikler,
            "missing_rare_class_support": eksikler,
            "calibration_support_required": False,
            "calibration_support": {
                SINIFLAR[sinif]: (
                    ornek_sayilari[sinif]["calibration"] > 0
                )
                for sinif in (2, 3)
            },
        },
    }


def _tekrarlanabilir_liste(deger, alan, bos_olabilir=False):
    if deger is None:
        if bos_olabilir:
            return []
        raise BirlestirmeHatasi(f"{alan}: en az bir değer gerekli")
    if isinstance(deger, (str, os.PathLike)):
        sonuc = [deger]
    else:
        try:
            sonuc = list(deger)
        except TypeError as hata:
            raise BirlestirmeHatasi(f"{alan}: liste olmalı") from hata
    if not sonuc and not bos_olabilir:
        raise BirlestirmeHatasi(f"{alan}: en az bir değer gerekli")
    return sonuc


def birlestir(
        ql_v3_manifest,
        palme_manifest,
        cikti,
        palme_grubu=None,
        palme_diagnostic_manifest=None):
    """İki V1 manifesti temizleyip atomik olarak yeni ql_v4 üretir."""
    cikti = os.path.abspath(os.fspath(cikti))
    if os.path.lexists(cikti):
        raise BirlestirmeHatasi("çıktı zaten var; üzerine yazılmayacak")
    temel = _manifest_oku(ql_v3_manifest, "ql_v3")
    palme_manifestleri = _tekrarlanabilir_liste(
        palme_manifest, "palme_manifest")
    ekler = [
        _manifest_oku(yol, "palme_supplement")
        for yol in palme_manifestleri
    ]
    if len({ek["manifest_sha256"] for ek in ekler}) != len(ekler):
        raise BirlestirmeHatasi(
            "aynı Palme supplement manifesti birden çok kez verilemez")
    if len({ek["dataset_id"] for ek in ekler}) != len(ekler):
        raise BirlestirmeHatasi(
            "Palme supplement dataset_id değerleri benzersiz olmalı")
    if palme_grubu is None:
        istenen_gruplar = [None] * len(ekler)
    else:
        istenen_gruplar = _tekrarlanabilir_liste(
            palme_grubu, "palme_grubu")
        if len(istenen_gruplar) != len(ekler):
            raise BirlestirmeHatasi(
                "palme_grubu sayısı supplement manifesti sayısıyla eşleşmeli")
    supplement_bilgileri = []
    for ek, istenen in zip(ekler, istenen_gruplar):
        grup = _palme_grubunu_bul(ek["ornekler"], istenen)
        supplement_bilgileri.append({
            "dataset_id": ek["dataset_id"],
            "manifest_sha256": ek["manifest_sha256"],
            "publisher_group": grup,
            "publisher_groups": {
                ornek.publisher_group for ornek in ek["ornekler"]
            },
        })
    palme_gruplari = {
        bilgi["publisher_group"] for bilgi in supplement_bilgileri
    }
    tum_ornekler = temel["ornekler"] + [
        ornek for ek in ekler for ornek in ek["ornekler"]
    ]
    diagnostic_haritasi = {
        bilgi["dataset_id"] + "-diagnostic": bilgi
        for bilgi in supplement_bilgileri
    }
    diagnostic_yollari = _tekrarlanabilir_liste(
        palme_diagnostic_manifest,
        "palme_diagnostic_manifest",
        bos_olabilir=True,
    )
    diagnostic_raporlari = [
        _diagnostic_anahtarlari_oku(yol, diagnostic_haritasi)
        for yol in diagnostic_yollari
    ]
    if len({
            rapor["manifest_sha256"] for rapor in diagnostic_raporlari
    }) != len(diagnostic_raporlari):
        raise BirlestirmeHatasi(
            "aynı Palme diagnostic manifesti birden çok kez verilemez")
    if len({
            rapor["dataset_id"] for rapor in diagnostic_raporlari
    }) != len(diagnostic_raporlari):
        raise BirlestirmeHatasi(
            "Palme diagnostic dataset_id değerleri benzersiz olmalı")
    diagnostic = {
        "manifest_sha256": [
            rapor["manifest_sha256"] for rapor in diagnostic_raporlari
        ],
        "dataset_id": [
            rapor["dataset_id"] for rapor in diagnostic_raporlari
        ],
        "anahtarlar": frozenset(
            anahtar
            for rapor in diagnostic_raporlari
            for anahtar in rapor["anahtarlar"]
        ),
    }
    ek_train_anahtarlari = {
        (ornek.document_sha256, ornek.page)
        for ek in ekler for ornek in ek["ornekler"]
    }
    train_diagnostic_kesisimi = (
        ek_train_anahtarlari & diagnostic["anahtarlar"]
    )
    if train_diagnostic_kesisimi:
        raise BirlestirmeHatasi(
            "Palme train ve diagnostic manifestleri aynı mantıksal sayfayı "
            "içeriyor")

    birlesim = _BirlesimKumesi()
    tum_gruplar = sorted({
        ornek.publisher_group for ornek in tum_ornekler
    })
    for grup in tum_gruplar:
        birlesim.ekle(grup)

    ham_piksel_gruplari = collections.defaultdict(list)
    belge_gruplari = collections.defaultdict(set)
    for ornek in tum_ornekler:
        ham_piksel_gruplari[ornek.pixel_sha256].append(ornek)
        belge_gruplari[ornek.document_sha256].add(ornek.publisher_group)
    # Piksel tekrarı, hangi temsilci kalırsa kalsın yayınevi bileşenlerini
    # birbirine bağlar. Aynı belge SHA'sının hatalı biçimde farklı gruplarla
    # gelmesi de belge split sızıntısını önlemek için aynı bileşene alınır.
    for ornekler in ham_piksel_gruplari.values():
        ilk = ornekler[0].publisher_group
        for ornek in ornekler[1:]:
            birlesim.birlestir(ilk, ornek.publisher_group)
    for gruplar in belge_gruplari.values():
        gruplar = sorted(gruplar)
        for grup in gruplar[1:]:
            birlesim.birlestir(gruplar[0], grup)

    mantiksal_gruplar = collections.defaultdict(list)
    for ornek in tum_ornekler:
        mantiksal_gruplar[
            (ornek.document_sha256, ornek.page)
        ].append(ornek)
    mantiksal_tutulan = []
    diagnostic_bastirilan = 0
    diagnostic_bastirilan_ql_v3 = 0
    supplement_ile_degistirilen_ql_v3 = 0
    supplement_ile_degistirilen_sayfa = 0
    mantiksal_es_tekrar_atilan = 0
    mantiksal_belirsiz_grup = 0
    mantiksal_belirsiz_ornek = 0
    for anahtar in sorted(mantiksal_gruplar):
        ornekler = mantiksal_gruplar[anahtar]
        if anahtar in diagnostic["anahtarlar"]:
            diagnostic_bastirilan += len(ornekler)
            diagnostic_bastirilan_ql_v3 += sum(
                ornek.rol == "ql_v3" for ornek in ornekler)
            continue
        supplement = [
            ornek for ornek in ornekler
            if ornek.rol == "palme_supplement"
        ]
        if supplement:
            etiket_kumeleri = {
                ornek.etiketler for ornek in supplement
            }
            if len(etiket_kumeleri) != 1:
                raise BirlestirmeHatasi(
                    "aynı mantıksal sayfada doğrulanmış supplement "
                    "etiketleri çelişiyor")
            ql_v3_sayisi = sum(
                ornek.rol == "ql_v3" for ornek in ornekler)
            if ql_v3_sayisi:
                supplement_ile_degistirilen_sayfa += 1
                supplement_ile_degistirilen_ql_v3 += ql_v3_sayisi
            temsilci = min(supplement, key=_temsilci_anahtari)
            kaynaklar = tuple(
                sorted(supplement, key=_temsilci_anahtari))
            mantiksal_es_tekrar_atilan += len(ornekler) - 1
        else:
            etiket_kumeleri = {
                ornek.etiketler for ornek in ornekler
            }
            if len(etiket_kumeleri) != 1:
                mantiksal_belirsiz_grup += 1
                mantiksal_belirsiz_ornek += len(ornekler)
                continue
            temsilci = min(ornekler, key=_temsilci_anahtari)
            kaynaklar = tuple(
                sorted(ornekler, key=_temsilci_anahtari))
            mantiksal_es_tekrar_atilan += len(ornekler) - 1
        mantiksal_tutulan.append((temsilci, kaynaklar))

    piksel_gruplari = collections.defaultdict(list)
    for paket in mantiksal_tutulan:
        piksel_gruplari[paket[0].pixel_sha256].append(paket)
    tutulan = []
    belirsiz_grup = 0
    belirsiz_ornek = 0
    es_tekrar_atilan = 0
    for piksel_sha in sorted(piksel_gruplari):
        paketler = piksel_gruplari[piksel_sha]
        etiket_kumeleri = {
            paket[0].etiketler for paket in paketler
        }
        if len(etiket_kumeleri) != 1:
            belirsiz_grup += 1
            belirsiz_ornek += len(paketler)
            continue
        secilen_paket = min(
            paketler, key=lambda paket: _temsilci_anahtari(paket[0]))
        temsilci = secilen_paket[0]
        kaynaklar = tuple(sorted(
            (
                kaynak
                for _paket_temsilcisi, paket_kaynaklari in paketler
                for kaynak in paket_kaynaklari
            ),
            key=_temsilci_anahtari,
        ))
        tutulan.append((temsilci, kaynaklar))
        es_tekrar_atilan += len(paketler) - 1
    if not tutulan:
        raise BirlestirmeHatasi("temizlikten sonra hiç örnek kalmadı")
    kalan_supplement_datasetleri = {
        kaynak.dataset_id
        for _temsilci, kaynaklar in tutulan
        for kaynak in kaynaklar
        if kaynak.rol == "palme_supplement"
    }
    eksik_supplementler = sorted(
        {ek["dataset_id"] for ek in ekler} -
        kalan_supplement_datasetleri
    )
    if eksik_supplementler:
        raise BirlestirmeHatasi(
            "Palme supplement'in bütün sayfaları çelişkili tekrar olarak "
            f"elendi: {eksik_supplementler}")

    bileşen_gruplari = collections.defaultdict(set)
    for grup in tum_gruplar:
        bileşen_gruplari[birlesim.bul(grup)].add(grup)
    kok_ornekleri = collections.defaultdict(list)
    for temsilci, kaynaklar in tutulan:
        kok = birlesim.bul(temsilci.publisher_group)
        kok_ornekleri[kok].append((temsilci, kaynaklar))
    zorunlu_atamalar, zorunlu_nedenler = _zorunlu_splitleri_coz(
        birlesim, tum_gruplar, palme_gruplari)
    atama, split_sayilari = _splitleri_ata(
        kok_ornekleri, bileşen_gruplari, zorunlu_atamalar)
    zorunlu_train_kokleri = {
        birlesim.bul(grup) for grup in palme_gruplari
    }
    if any(
            atama[kok] != "train" for kok in zorunlu_train_kokleri):
        raise BirlestirmeHatasi(
            "Palme birleşim grupları train'e atanamadı")
    sinif_destegi = _sinif_destegi_raporu(
        tutulan, atama, birlesim)

    _cikti_kaynaktan_ayri_mi(
        cikti,
        (temel["veri_koku"], *(ek["veri_koku"] for ek in ekler)),
    )
    ust = os.path.dirname(cikti)
    os.makedirs(ust, exist_ok=True)
    gecici = tempfile.mkdtemp(
        prefix=f".{os.path.basename(cikti)}-hazirlaniyor-", dir=ust)

    split_sirasi = {split: sira for sira, split in enumerate(SPLITLER)}
    sirali_tutulan = sorted(
        tutulan,
        key=lambda oge: (
            split_sirasi[atama[birlesim.bul(oge[0].publisher_group)]],
            oge[0].pixel_sha256,
            _temsilci_anahtari(oge[0]),
        ),
    )
    manifest_splitleri = {split: [] for split in SPLITLER}
    aktarim = {"hardlink": 0, "copy": 0, "rewritten_label": 0}
    try:
        for temsilci, kaynaklar in sirali_tutulan:
            kok = birlesim.bul(temsilci.publisher_group)
            split = atama[kok]
            uzanti = pathlib.PurePosixPath(
                temsilci.image_rel).suffix.lower()
            dosya_koku = temsilci.pixel_sha256
            image_rel = f"images/{split}/{dosya_koku}{uzanti}"
            label_rel = f"labels/{split}/{dosya_koku}.txt"
            image_hedef = os.path.join(gecici, *image_rel.split("/"))
            label_hedef = os.path.join(gecici, *label_rel.split("/"))

            kip = _bagla_veya_kopyala(temsilci.image_yolu, image_hedef)
            aktarim[kip] += 1
            image_sha256 = _dosya_sha256(image_hedef)
            etiket_metni = "\n".join(temsilci.etiket_satirlari)
            if etiket_metni:
                etiket_metni += "\n"
            try:
                with open(temsilci.label_yolu, "rb") as dosya:
                    kaynak_etiket = dosya.read()
            except OSError as hata:
                raise BirlestirmeHatasi(
                    f"kaynak etiket yeniden okunamadı: {hata}") from hata
            hedef_etiket = etiket_metni.encode("utf-8")
            if kaynak_etiket == hedef_etiket:
                kip = _bagla_veya_kopyala(
                    temsilci.label_yolu, label_hedef)
                aktarim[kip] += 1
            else:
                os.makedirs(os.path.dirname(label_hedef), exist_ok=True)
                with open(label_hedef, "wb") as dosya:
                    dosya.write(hedef_etiket)
                aktarim["rewritten_label"] += 1
            label_sha256 = hashlib.sha256(hedef_etiket).hexdigest()

            manifest_splitleri[split].append({
                "image": image_rel,
                "label": label_rel,
                "image_sha256": image_sha256,
                "label_sha256": label_sha256,
                "document_sha256": temsilci.document_sha256,
                "page": temsilci.page,
                "publisher_group": temsilci.publisher_group,
                "pixel_sha256": temsilci.pixel_sha256,
                "provenance": {
                    "representative_role": temsilci.rol,
                    "sources": [
                        _kaynak_provenansi(ornek) for ornek in kaynaklar
                    ],
                },
            })

        if any(not manifest_splitleri[split] for split in SPLITLER):
            raise BirlestirmeHatasi("çıktıda zorunlu split boş kaldı")
        toplam = sum(split_sayilari.values())
        gercek_oranlar = {
            split: split_sayilari[split] / toplam for split in SPLITLER
        }
        oran_sapmalari = {
            split: gercek_oranlar[split] - SPLIT_HEDEFLERI[split]
            for split in SPLITLER
        }
        parmak_izi_nesnesi = {
            "ql_v3_manifest_sha256": temel["manifest_sha256"],
            "palme_manifest_sha256": sorted(
                ek["manifest_sha256"] for ek in ekler),
            "palme_diagnostic_manifest_sha256": sorted(
                diagnostic["manifest_sha256"]),
            "samples": [
                {
                    "pixel_sha256": ornek["pixel_sha256"],
                    "split": split,
                    "document_sha256": ornek["document_sha256"],
                    "page": ornek["page"],
                    "publisher_group": ornek["publisher_group"],
                    "image_sha256": ornek["image_sha256"],
                    "label_sha256": ornek["label_sha256"],
                }
                for split in SPLITLER
                for ornek in manifest_splitleri[split]
            ],
        }
        parmak_izi = hashlib.sha256(json.dumps(
            parmak_izi_nesnesi,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")).hexdigest()
        bileşen_raporu = []
        for kok, gruplar in sorted(
                bileşen_gruplari.items(),
                key=lambda oge: tuple(sorted(oge[1]))):
            bileşen_raporu.append({
                "groups": sorted(gruplar),
                "pages": len(kok_ornekleri.get(kok, ())),
                "split": atama[kok],
                "forced_train": kok in zorunlu_train_kokleri,
                "forced_split": (
                    zorunlu_atamalar.get(kok)
                    if kok in zorunlu_atamalar else None
                ),
                "forced_split_reasons": zorunlu_nedenler.get(kok, []),
            })
        source_manifests = {
            "ql_v3": temel["manifest_sha256"],
            "palme_supplements": [
                bilgi["manifest_sha256"]
                for bilgi in sorted(
                    supplement_bilgileri,
                    key=lambda b: b["dataset_id"],
                )
            ],
        }
        source_dataset_ids = {
            "ql_v3": temel["dataset_id"],
            "palme_supplements": sorted(
                ek["dataset_id"] for ek in ekler),
        }
        if diagnostic["manifest_sha256"]:
            source_manifests["palme_diagnostics"] = sorted(
                diagnostic["manifest_sha256"])
            source_dataset_ids["palme_diagnostics"] = sorted(
                diagnostic["dataset_id"])
        manifest = {
            "schema_version": SEMA_SURUMU,
            "dataset_id": f"ql_v4-{parmak_izi[:16]}",
            "classes": list(SINIFLAR),
            "root": ".",
            "splits": manifest_splitleri,
            "merge": {
                "builder": "soru_model_v4_birlestir/v2",
                "source_manifests": source_manifests,
                "source_dataset_ids": source_dataset_ids,
                "palme_publisher_groups": sorted(palme_gruplari),
                "verified_supplements": [
                    {
                        "dataset_id": bilgi["dataset_id"],
                        "manifest_sha256": bilgi["manifest_sha256"],
                        "publisher_group": bilgi["publisher_group"],
                    }
                    for bilgi in sorted(
                        supplement_bilgileri,
                        key=lambda b: b["dataset_id"],
                    )
                ],
                "target_ratios": dict(SPLIT_HEDEFLERI),
                "actual_pages": dict(split_sayilari),
                "actual_ratios": gercek_oranlar,
                "ratio_deviation": oran_sapmalari,
                "publisher_group_components": bileşen_raporu,
                "class_support": sinif_destegi["classes"],
                "publication_gate": sinif_destegi["publication_gate"],
                "stats": {
                    "input_samples": len(tum_ornekler),
                    "output_samples": len(tutulan),
                    "logical_page_groups": len(mantiksal_gruplar),
                    "logical_page_duplicate_samples_removed":
                        mantiksal_es_tekrar_atilan,
                    "logical_page_ambiguous_groups_removed":
                        mantiksal_belirsiz_grup,
                    "logical_page_ambiguous_samples_removed":
                        mantiksal_belirsiz_ornek,
                    "verified_pages_replacing_ql_v3":
                        supplement_ile_degistirilen_sayfa,
                    "ql_v3_samples_replaced_by_verified":
                        supplement_ile_degistirilen_ql_v3,
                    "diagnostic_pages_declared":
                        len(diagnostic["anahtarlar"]),
                    "diagnostic_pages_matched_in_inputs": len(
                        set(mantiksal_gruplar) &
                        set(diagnostic["anahtarlar"])
                    ),
                    "diagnostic_input_samples_suppressed":
                        diagnostic_bastirilan,
                    "diagnostic_ql_v3_samples_suppressed":
                        diagnostic_bastirilan_ql_v3,
                    "input_decoded_duplicate_groups": sum(
                        1 for grup in ham_piksel_gruplari.values()
                        if len(grup) > 1),
                    "decoded_duplicate_groups": sum(
                        1 for grup in piksel_gruplari.values()
                        if len(grup) > 1),
                    "equivalent_duplicate_samples_removed":
                        es_tekrar_atilan,
                    "ambiguous_duplicate_groups_removed": belirsiz_grup,
                    "ambiguous_samples_removed": belirsiz_ornek,
                    "body_solution_samples_reclassified": sum(
                        bool(ornek.govde_cozume_yeniden_siniflanan)
                        for ornek in tum_ornekler
                    ),
                    "body_rows_reclassified_to_solution": sum(
                        ornek.govde_cozume_yeniden_siniflanan
                        for ornek in tum_ornekler
                    ),
                    "duplicate_label_rows_removed": sum(
                        ornek.cikarilan_tekrar for ornek in tum_ornekler),
                    "hardlinks_created": aktarim["hardlink"],
                    "copies_created": aktarim["copy"],
                    "labels_rewritten": aktarim["rewritten_label"],
                },
            },
        }
        manifest_yolu = os.path.join(gecici, "manifest.json")
        with open(manifest_yolu, "w", encoding="utf-8") as dosya:
            json.dump(
                manifest, dosya, ensure_ascii=False, indent=2, sort_keys=True)
            dosya.write("\n")

        # Mevcut eğitim sözleşmesi ve fiziksel dosyalar son staging durumunda
        # doğrulanır; başarısızsa kaynaklara/nihai çıktı yoluna dokunulmaz.
        import soru_model_egitim
        rapor = soru_model_egitim.manifest_dogrula(manifest_yolu)
        if not rapor["ok"]:
            raise BirlestirmeHatasi(
                "ql_v4 manifest doğrulaması başarısız: "
                + "; ".join(rapor["hatalar"][:5]))
        _cikis_tekrarlarini_dogrula(manifest_yolu)

        if os.path.lexists(cikti):
            raise BirlestirmeHatasi(
                "çıktı oluşturma sırasında belirdi; üzerine yazılmayacak")
        os.rename(gecici, cikti)
        gecici = None
        return {
            "ok": True,
            "cikti": cikti,
            "manifest_yolu": os.path.join(cikti, "manifest.json"),
            "dataset_id": manifest["dataset_id"],
            "split_sayilari": dict(split_sayilari),
            "istatistik": dict(manifest["merge"]["stats"]),
        }
    finally:
        if gecici is not None:
            shutil.rmtree(gecici, ignore_errors=True)


def main(argv=None):
    ayrac = argparse.ArgumentParser(
        description="ql_v3 + Palme ekini temiz ql_v4 olarak birleştir")
    ayrac.add_argument("--ql-v3-manifest", required=True)
    ayrac.add_argument(
        "--palme-manifest",
        required=True,
        action="append",
        help="tekrarlanabilir; her doğrulanmış supplement manifesti",
    )
    ayrac.add_argument(
        "--palme-diagnostic-manifest",
        action="append",
        help=(
            "tekrarlanabilir; supplement'lerin eğitim dışı mantıksal "
            "sayfaları, ql_v3 karşılıkları da bastırılır"
        ),
    )
    ayrac.add_argument("--cikti", required=True)
    ayrac.add_argument(
        "--palme-grubu",
        action="append",
        help=(
            "isteğe bağlı ve manifest sırasıyla tekrarlanabilir; ek "
            "manifestte birden çok grup varsa train'e sabitlenecek grup"
        ),
    )
    args = ayrac.parse_args(argv)
    try:
        sonuc = birlestir(
            args.ql_v3_manifest,
            args.palme_manifest,
            args.cikti,
            palme_grubu=args.palme_grubu,
            palme_diagnostic_manifest=args.palme_diagnostic_manifest,
        )
    except BirlestirmeHatasi as hata:
        print(f"HATA: {hata}", file=sys.stderr)
        return 2
    print(json.dumps(sonuc, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
