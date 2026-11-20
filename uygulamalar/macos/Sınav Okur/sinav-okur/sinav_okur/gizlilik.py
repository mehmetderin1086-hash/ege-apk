"""Yerel-öncelikli öğrenci gizliliği ve güvenli saklama yardımcıları."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path


def anonim_kimlik(deger: str, tuz: str = "sinav-okur") -> str:
    return hashlib.sha256(f"{tuz}:{deger}".encode("utf-8")).hexdigest()[:16]


def metinden_kimlikleri_maskele(
    metin: str,
    *,
    ad: str = "",
    soyad: str = "",
    ogrenci_no: str = "",
) -> str:
    """Haricî bir modele gönderilmeden önce doğrudan kimlikleri kaldır."""
    sonuc = str(metin)
    for deger, etiket in (
        (ad, "[OGRENCI_ADI]"),
        (soyad, "[OGRENCI_SOYADI]"),
        (ogrenci_no, "[OGRENCI_NO]"),
    ):
        if str(deger).strip():
            sonuc = re.sub(
                re.escape(str(deger).strip()),
                etiket,
                sonuc,
                flags=re.IGNORECASE,
            )
    return sonuc


def guvenli_veri_yolu(yol: str | Path, izinli_kokler: list[str | Path]) -> Path:
    aday = Path(yol).resolve()
    if not any(
        aday == Path(kok).resolve()
        or Path(kok).resolve() in aday.parents
        for kok in izinli_kokler
    ):
        raise ValueError("Dosya uygulamanın güvenli veri dizini dışında.")
    return aday


def gizlilik_durumu() -> dict:
    """Arayüzün göstereceği varsayılan veri ilkeleri."""
    return {
        "yerel_depolama": True,
        "harici_servis_varsayilan": False,
        "kimlik_maskeleme": True,
        "egitim_izni_zorunlu": True,
        "varsayilan_saklama_gunu": 365,
        "aciklama": (
            "Kâğıtlar ve öğrenci kimlikleri bu Mac'te saklanır. Açık izin "
            "olmadan eğitim verisine veya haricî modele kimlik aktarılmaz."
        ),
    }

