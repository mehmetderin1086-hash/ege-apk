"""Türkçe metin normalizasyonu: NFC, ı/İ dönüşümü, eşleştirme öncesi temizlik."""

from __future__ import annotations

import re
import unicodedata

# Türkçe'de büyük→küçük dönüşüm ASCII'den farklıdır: İ→i, I→ı.
_BUYUK_KUCUK = str.maketrans({"İ": "i", "I": "ı"})

# Aksan katlaması: OCR'ın noktalı karakterleri kaçırdığı durumda toleranslı karşılaştırma.
_AKSAN_KATLAMA = str.maketrans(
    {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
)

_NOKTALAMA = re.compile(r"[^\w\s]", re.UNICODE)
_BOSLUK = re.compile(r"\s+")


def nfc(metin: str) -> str:
    """Ayrık aksanları (combining marks) tek koda birleştirir."""
    return unicodedata.normalize("NFC", metin)


def kucult(metin: str) -> str:
    """Türkçe kurallarına göre küçük harfe çevirir (İ→i, I→ı)."""
    return nfc(metin).translate(_BUYUK_KUCUK).lower()


def eslesme_bicimi(metin: str) -> str:
    """Eşleştirme için kanonik biçim: küçük harf, noktalama yok, tek boşluk."""
    m = kucult(metin)
    m = _NOKTALAMA.sub(" ", m)
    return _BOSLUK.sub(" ", m).strip()


def aksansiz(metin: str) -> str:
    """Aksan katlanmış biçim (ş→s, ğ→g...); OCR toleransı için ikincil karşılaştırma."""
    return eslesme_bicimi(metin).translate(_AKSAN_KATLAMA)


def cumleler(metin: str) -> list[str]:
    """Kaba cümle bölme: nokta/soru/ünlem ve satır sonlarına göre."""
    parcalar = re.split(r"[.!?\n]+", metin)
    return [p.strip() for p in parcalar if p.strip()]
