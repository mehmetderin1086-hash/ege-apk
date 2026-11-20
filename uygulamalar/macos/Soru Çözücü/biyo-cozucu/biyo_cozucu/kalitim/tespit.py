"""Kalıtım sorusu ön süzgeci — ucuz, saf regex, model çağırmaz.

Neden çözüm türü etiketine bağlanmıyor: `hafiza.etiketleme.kural_ile_etiketle`
çıktısı ölçüldü ve 217 `kalitim_hesabi` etiketinin 29'u yanlış. En sık
tetikleyici `"taşıyıcı"` ipucunun "taşıyıcı protein"e çarpması. Kapıyı o
etikete bağlamak gerçek kalıtım sorularını kaçırır, yanlış etiketlileri de
gereksiz yere çıkarım çağrısına sokar.

Süzgecin işi kesin sınıflandırma değil, ucuza ELEMEK: geçen soru bir model
çağrısı harcar, geçmeyen soru mevcut yoldan gider.
"""

from __future__ import annotations

import re

# Genotip deseni: "AaBb", "XRXr", "SsKk × Sskk".
_GENOTIP = re.compile(r"\b[A-Za-z]{2,10}\b\s*[x×X]\s*\b[A-Za-z]{2,10}\b")

def genotip_gibi_mi(metin: str) -> bool:
    """Metin bir genotip yazımı mı: "MmSs", "mmss", "MMSS", "XRXr", "A0".

    Harf çiftleri AYNI karakterin büyük/küçük hâli olmalı. Salt "[A-Z][a-z]"
    deseni yetmiyordu: "mmss" ve "MMSS" (homozigot yazımlar) kaçıyordu ve
    kontrol çaprazı soruları bu yüzden süzgeçten geçemiyordu — şıkların
    tamamı genotip olan tipik soru bu.
    """
    ham = (metin or "").strip()
    if not ham or len(ham) > 12 or not ham.isalpha():
        return False
    # X'e bağlı gösterim: XRXr, XrY, XRY
    if ham.upper().startswith("X"):
        return bool(re.fullmatch(r"[Xx][A-Za-z]?([Xx][A-Za-z]?|[Yy])", ham))
    if len(ham) % 2:
        return False
    return all(
        ham[i].casefold() == ham[i + 1].casefold() for i in range(0, len(ham), 2)
    )


_KALITIM_SOZCUKLERI = (
    "çaprazla", "caprazla", "genotip", "fenotip", "homozigot", "heterozigot",
    "alel", "gamet", "soyağac", "soyagac", "kan grubu", "renk kör", "hemofili",
    "kalıtım", "kalitim", "baskın", "baskin", "çekinik", "cekinik",
    "kromozom", "melez", "arı döl", "dominant", "resesif", "kıllı kulak",
)

# "taşıyıcı" TEK BAŞINA sayılmaz: "taşıyıcı protein" biyoloji korpusunda çok
# yaygın ve mevcut etiketleyicinin ölçülmüş yanlış pozitif kaynağı.
_TASIYICI = re.compile(r"taşıyıc[ıi]|tasiyic[ıi]", re.IGNORECASE)
_TASIYICI_BAGLAM = re.compile(
    r"olasıl|ihtimal|soyağac|soyagac|anne|baba|çocuk|cocuk|evlen|genotip",
    re.IGNORECASE,
)

_NICEL = re.compile(
    r"olasıl|ihtimal|oran|kaç çeşit|kaç farklı|yüzde kaç|kaçtır|beklenir",
    re.IGNORECASE,
)
# Şıkları önerme listesi olan ("Yalnız I", "I ve III") yargı soruları.
_YARGI = re.compile(
    r"hangileri|hangisi (doğru|yanlış|söylenebilir)|söylenebilir|"
    r"doğrudur|yanlıştır|kesinlikle",
    re.IGNORECASE,
)


def kalitim_adayi_mi(soru: str, secenekler: dict[str, str] | None = None) -> bool:
    """Soru deterministik kalıtım çözücüsüne gönderilmeye değer mi.

    İki koşul birden: kalıtım alanına ait bir işaret VE nicel bir istek.
    Nicel istek şartı bilinçli — "aşağıdakilerden hangisi cinsiyete bağlı
    kalıtım göstermez" bir ezber sorusudur, hesapla çözülmez.
    """
    metin = " ".join((soru or "").split())
    if not metin:
        return False
    alcak = metin.casefold()

    alan = any(s in alcak for s in _KALITIM_SOZCUKLERI)
    if not alan and _TASIYICI.search(metin):
        alan = bool(_TASIYICI_BAGLAM.search(metin))
    if not alan:
        alan = bool(_GENOTIP.search(metin))
    if not alan:
        return False

    if _NICEL.search(metin):
        return True
    # Yargı biçimli kalıtım soruları ("... hangileri doğrudur?") nicel sözcük
    # taşımaz ve bu kapıdan hiç geçemiyordu: 50 soruluk ölçüm koşusunda kural
    # katmanı SIFIR kez çalıştı, 9 kalıtım sorusunun 6'sı burada elendi.
    # Kapıyı genişletmek risksiz: kural katmanı bir şıkka bağlayamazsa zaten
    # None döndürüp model yoluna bırakıyor.
    if _YARGI.search(metin):
        return True
    # Şıkların hepsi genotip gibi görünüyorsa (kontrol çaprazı soruları) nicel
    # sözcük olmasa da aday sayılır.
    if secenekler and len(secenekler) >= 3:
        genotip_sayisi = sum(1 for v in secenekler.values() if genotip_gibi_mi(v))
        if genotip_sayisi >= len(secenekler) - 1:
            return True
    return False
