"""Türkçe metin normalleştirme yardımcıları.

Türkçe'de `str.lower()` "I" harfini "i" yapar (doğrusu "ı"), `str.upper()` ise
"i" harfini "I" yapar (doğrusu "İ"). Karşılaştırma ve indeksleme bu yüzden
Python'un varsayılan katlamasıyla değil, buradaki `katla()` ile yapılır.
"""

from __future__ import annotations

import hashlib
import re
import unicodedata

_BOSLUK = re.compile(r"[ \t ]+")
_NOKTALAMA = re.compile(r"[^\w\s]", re.UNICODE)


def nfc(metin: str) -> str:
    """Unicode NFC normalleştirmesi — birleşik/ayrık aksanları tek biçime getirir."""
    # PDF metin katmanları satır sonu hecelemesini görünmez soft-hyphen ile
    # taşıyabiliyor. Arama/imza için içerik olmayan bu karakterleri temizle.
    return (
        unicodedata.normalize("NFC", metin)
        .replace("\u00ad", "")
        .replace("\u200b", "")
        .replace("\ufeff", "")
    )


def katla(metin: str) -> str:
    """Türkçe'ye uygun küçük harfe indirme (I→ı, İ→i). Gösterim için."""
    return nfc(metin).replace("I", "ı").replace("İ", "i").casefold()


def esitle(metin: str) -> str:
    """Eşleştirme için nokta-duyarsız katlama: "OPTIMUM" ve "optimum" aynı olur.

    `katla()` dilbilgisel olarak doğrudur ama Türkçe büyük harfte "i"nin
    karşılığı "İ"dir; kullanıcı alıntı sözcükleri "OPTIMUM" diye yazdığında
    doğru katlama "optımum" verir ve sözcük kendi küçük harfli hâliyle
    eşleşmez. İndeksleme/önbellek anahtarı gibi eşleştirme işlerinde bu
    ayrımı kaldırmak, "kır"/"kir" gibi seyrek asgari çiftlerin birleşmesi
    pahasına, çok daha fazla gerçek eşleşme kazandırır.
    """
    return katla(metin).replace("ı", "i")


def sadelestir(metin: str) -> str:
    """Karşılaştırma için metni sadeleştirir: eşitleme + noktalama/boşluk temizliği."""
    sade = _NOKTALAMA.sub(" ", esitle(metin))
    return " ".join(sade.split())


def imza(metin: str) -> str:
    """Sadeleştirilmiş metnin kararlı kısa özeti — önbellek anahtarı olarak kullanılır."""
    return hashlib.sha256(sadelestir(metin).encode("utf-8")).hexdigest()[:32]


def bosluk_topla(metin: str) -> str:
    """Satır yapısını koruyarak yatay boşlukları teke indirir."""
    return "\n".join(_BOSLUK.sub(" ", satir).strip() for satir in nfc(metin).splitlines())


def kirp(metin: str, azami: int) -> str:
    """Metni azami uzunluğa kırpar; kırpıldıysa sonuna işaret koyar."""
    metin = metin.strip()
    if len(metin) <= azami:
        return metin
    return metin[: max(0, azami - 1)].rstrip() + "…"
