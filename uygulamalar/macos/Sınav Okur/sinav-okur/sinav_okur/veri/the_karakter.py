"""T-H-E gerçek Türkçe el yazısı karakterlerini güvenli biçimde dışa aktar.

T-H-E'nin altı CSV'si bağımsız veri parçaları değildir. ``version1`` özgün ve
artırılmış örnekleri, ``version2``/``version4`` bunların alt kümelerini,
``version5`` ise birleştirilmiş sınıfları içerir. Gerçek-veri-only eğitim için
yalnız ``version6.csv`` kabul edilir. Kaynak README 78 sınıf dese de 2026-07-23
itibarıyla indirilen dosya 76 sınıf/76.000 satırdır; büyük ``Ç`` ve ``Ş``
sınıfları eksiktir.

Bu modül karakterleri yan yana dizip sahte kelime/satır üretmez. Böyle bir
bileşim insanın gerçekten yazdığı bir satır değildir ve ürün HTR metriğine
katılamaz.

Kaynak: https://github.com/bartosgaye/thedataset
Lisans uyarısı: Makalede ``public-domain``/``free-to-use`` ifadeleri geçse de
depo açık bir SPDX lisans dosyası yayımlamıyor. Bu nedenle manifest veriyi
yeniden dağıtılabilir açık lisanslı bir kaynak olarak değil, atıf ve izin
kontrolü gerektiren özel kullanım girdisi olarak işaretler.
"""

from __future__ import annotations

import csv
import hashlib
import json
import random
from pathlib import Path

import numpy as np
from PIL import Image

# T-H-E etiketleri. Macarca özel harfler 33-39 ve 72-78 aralığındadır.
THE_HARITA: dict[int, str] = {
    1: "a", 2: "b", 3: "c", 4: "d", 5: "e", 6: "f", 7: "g", 8: "h", 9: "i",
    10: "j", 11: "k", 12: "l", 13: "m", 14: "n", 15: "o", 16: "p", 17: "q",
    18: "r", 19: "s", 20: "t", 21: "u", 22: "v", 23: "w", 24: "x", 25: "y",
    26: "z", 27: "ç", 28: "ğ", 29: "ı", 30: "ş", 31: "ö", 32: "ü",
    40: "A", 41: "B", 42: "C", 43: "D", 44: "E", 45: "F", 46: "G", 47: "H",
    48: "I", 49: "J", 50: "K", 51: "L", 52: "M", 53: "N", 54: "O", 55: "P",
    56: "Q", 57: "R", 58: "S", 59: "T", 60: "U", 61: "V", 62: "W", 63: "X",
    64: "Y", 65: "Z", 66: "Ç", 67: "Ğ", 68: "İ", 69: "Ş", 70: "Ö", 71: "Ü",
}

TURKCE_ALFABE = "abcçdefgğhıijklmnoöprsştuüvyz"
TURKCE_BUYUK_ALFABE = "ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ"
TURKCE_KARAKTERLER = set(TURKCE_ALFABE + TURKCE_BUYUK_ALFABE)
TURKCE_HARITA = {k: v for k, v in THE_HARITA.items() if v in TURKCE_KARAKTERLER}
THE_MAKALE_URL = "https://acta.uni-obuda.hu/EdibogluBartos_Hoscan_Kauer_Hajnal_106.pdf"
THE_LISANS = "LicenseRef-THE-Unspecified-Verify-Permission"


def _sha256(yol: Path) -> str:
    ozet = hashlib.sha256()
    with yol.open("rb") as f:
        for blok in iter(lambda: f.read(1024 * 1024), b""):
            ozet.update(blok)
    return ozet.hexdigest()


def _surum6_yolu_dogrula(csv_yolu: Path) -> None:
    if csv_yolu.name.lower() != "version6.csv":
        raise ValueError(
            "Gerçek-veri-only eğitimde yalnız T-H-E version6.csv kabul edilir; "
            "diğer sürümler artırılmış/örtüşen veya sınıf-birleştirilmiş veridir."
        )


def glif_bankasi(
    csv_yolu: str | Path,
    *,
    yalniz_turkce: bool = True,
    surum6_zorunlu: bool = False,
) -> dict[str, list[np.ndarray]]:
    """CSV'yi okuyup karakter → 28×28 özgün glif bankası kur.

    ``surum6_zorunlu`` üretim/CLI yolunda açılır. Birim testlerinde küçük örnek
    CSV kullanılabilmesi için varsayılan olarak kapalıdır.
    """
    yol = Path(csv_yolu)
    if surum6_zorunlu:
        _surum6_yolu_dogrula(yol)
    harita = TURKCE_HARITA if yalniz_turkce else THE_HARITA
    banka: dict[str, list[np.ndarray]] = {}
    with yol.open(newline="") as f:
        for satir in csv.reader(f):
            if not satir or len(satir) < 785:
                continue
            try:
                etiket = int(satir[0])
                # Upstream CSV 28×28 görüntüyü sütun-major düzleştirir. Doğrudan
                # reshape yatık/transpoze glif üretir; satır-major görüntüye dön.
                piksel = np.asarray(satir[1:785], dtype=np.uint8).reshape(28, 28).T
            except (ValueError, TypeError):
                continue
            karakter = harita.get(etiket)
            if karakter is not None:
                banka.setdefault(karakter, []).append(piksel)
    if not banka:
        raise ValueError(f"{yol}: geçerli T-H-E Türkçe karakter satırı bulunamadı")
    return banka


def _beyaz_kagit(px: np.ndarray) -> np.ndarray:
    """T-H-E ikili görüntüsünü beyaz kâğıt/koyu mürekkep yönüne getir."""
    kenar = np.concatenate([px[0], px[-1], px[:, 0], px[:, -1]])
    return 255 - px if float(kenar.mean()) < 128 else px


def the_karakter_aktar(
    csv_yolu: str | Path,
    cikti_dizini: str | Path,
    *,
    test_orani: float = 0.1,
    tohum: int = 42,
    surum6_zorunlu: bool = True,
) -> dict:
    """Özgün 58 Türkçe sınıfı PNG + JSONL olarak dışa aktar.

    T-H-E yazar kimliği yayımlamadığı için bölme yazar-ayrık değildir. Bu durum
    ``veri_manifesti.json`` içine açıkça yazılır; sonuç ürün/sınav doğruluğu
    olarak raporlanmamalıdır.
    """
    if not 0 <= test_orani < 1:
        raise ValueError("test_orani 0 ile 1 arasında olmalı")
    kaynak = Path(csv_yolu)
    banka = glif_bankasi(
        kaynak, yalniz_turkce=True, surum6_zorunlu=surum6_zorunlu
    )
    cikti = Path(cikti_dizini)
    (cikti / "img").mkdir(parents=True, exist_ok=True)
    rng = random.Random(tohum)
    kayitlar: list[dict] = []
    sinif_sayilari: dict[str, int] = {}

    for karakter in sorted(banka):
        ornekler = list(banka[karakter])
        rng.shuffle(ornekler)
        test_adedi = round(len(ornekler) * test_orani)
        for sira, piksel in enumerate(ornekler):
            bolum = "test" if sira < test_adedi else "train"
            etiket = next(k for k, v in THE_HARITA.items() if v == karakter)
            dosya = f"img/{etiket:02d}_{sira:04d}.png"
            Image.fromarray(_beyaz_kagit(piksel), mode="L").save(cikti / dosya)
            kayitlar.append(
                {"image": dosya, "text": karakter, "label": etiket, "split": bolum}
            )
        sinif_sayilari[karakter] = len(ornekler)

    labels_yolu = cikti / "labels.jsonl"
    with labels_yolu.open("w", encoding="utf-8") as f:
        for kayit in kayitlar:
            f.write(json.dumps(kayit, ensure_ascii=False) + "\n")

    manifest = {
        "dataset": "T-H-E Dataset Version VI",
        "source": "https://github.com/bartosgaye/thedataset",
        "source_file": kaynak.name,
        "source_sha256": _sha256(kaynak),
        "license": THE_LISANS,
        "license_evidence": THE_MAKALE_URL,
        "license_evidence_note": (
            "Makalede public-domain/free-to-use ifadeleri bulunsa da depoda açık SPDX "
            "lisansı yoktur; yeniden dağıtım öncesi hak sahibinden izin doğrulanmalıdır."
        ),
        "citation": "Ediboğlu Bartos et al., Acta Polytechnica Hungarica, 2020",
        "real_handwriting": True,
        "augmentation_used": False,
        "composition_used": False,
        "source_orientation": "column-major; transposed to upright row-major",
        "classes": len(banka),
        "expected_turkish_classes": len(TURKCE_HARITA),
        "missing_turkish_characters": sorted(set(TURKCE_HARITA.values()) - set(banka)),
        "upstream_integrity_warning": (
            "Makale 78 sınıf/78.000 özgün örnek bildirse de yayımlanan Version VI "
            "dosyasında 66=Ç ve 69=Ş satırları yoktur."
        ),
        "samples": len(kayitlar),
        "split_kind": "stratified-sample-random",
        "writer_disjoint": False,
        "warning": "Kaynak yazar kimliği vermediği için test bölümü ürün metriği değildir.",
        "class_counts": sinif_sayilari,
    }
    manifest_yolu = cikti / "veri_manifesti.json"
    manifest_yolu.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return {
        "yazilan": len(kayitlar),
        "sinif": len(banka),
        "labels": str(labels_yolu),
        "manifest": str(manifest_yolu),
    }


def the_satir_uret(*args, **kwargs):
    """Eski gerçek-glif bileşimini bilinçli olarak engelle."""
    raise RuntimeError(
        "T-H-E karakterlerini yan yana dizmek gerçek insan satırı üretmez. "
        "Gerçek-veri-only hatta the_karakter_aktar kullanın."
    )
