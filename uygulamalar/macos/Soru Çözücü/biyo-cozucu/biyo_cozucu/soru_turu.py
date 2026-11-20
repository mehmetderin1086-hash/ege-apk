"""Sorunun beklediği cevap türünü metninden çıkarır.

Öğretmen türü elle seçebilir; bu modül seçilmediğinde devreye girer. Kural
tabanlı, çünkü tür çıkarımı için model çalıştırmak her soruya saniyeler
eklerdi ve buradaki ipuçları (şık listesi, "D/Y", "……", "eşleştiriniz")
zaten yüzeyde duruyor.

Sıra önemlidir: bir soru hem şık listesi hem "sıralayınız" içerebilir;
en belirleyici ipucu önce denenir.
"""

from __future__ import annotations

import re

from .metin import esitle

# "…", "___", "....." gibi boşluk işaretleri. Tekrarlar tek boşluk sayılır:
# "……" iki ayrı U+2026 karakteridir ama kullanıcı için tek bir boşluktur.
_BOSLUK = re.compile(r"(?:\.{3,}|…+|_{3,}|-{4,})")

# "I - a", "1-c", "II/b" gibi eşleştirme çiftleri.
_ESLESTIRME_CIFTI = re.compile(
    r"\b(?:[IVX]{1,4}|\d{1,2})\s*[-–/]\s*[a-eA-E]\b"
)

# DİKKAT: ipuçları `esitle()` çıktısıyla karşılaştırılır. `esitle` yalnız
# küçük harfe indirip "ı"yı "i" yapar; ğ/ş/ç/ö/ü OLDUĞU GİBİ kalır. Bu yüzden
# kalıplar ASCII değil, katlanmış Türkçe biçimde yazılmalıdır
# ("doğru mu yanliş mi", "kaçtir", "açiklayiniz").
_DOGRU_YANLIS_IPUCLARI = (
    "doğru mu yanliş mi", "doğru/yanliş", "d/y", "(d)", "(y)",
    "doğru yanliş", "ifadelerin doğru", "doğruysa d", "yanlişsa y",
    "doğru ise d", "yanliş ise y", "doğru mudur", "yanliş midir",
)
_ESLESTIRME_IPUCLARI = (
    "eşleştir", "eşleşme", "hangisiyle eşleşir", "karşisina yaziniz",
)
_SIRALAMA_IPUCLARI = (
    "siralayiniz", "siraya diziniz", "doğru siralama", "sirasiyla yaziniz",
    "hangi sirayla", "siralay",
)
_BOSLUK_IPUCLARI = (
    "boşluklari doldur", "boşluğu doldur", "boşluğa getirilecek",
    "noktali yerlere", "tamamlayiniz",
)
_KISA_CEVAP_IPUCLARI = (
    "kaç tanedir", "kaçtir", "kaç adet", "kaç atp", "kaç molekül",
    "kaç üretilir", "adini yaziniz", "adi nedir", "ismini yaziniz",
    "kim tarafindan", "sayisi kaçtir", "kaç ",
)
# Açıklama isteyen sorular kısa cevaba düşmemeli.
_ACIK_UCLU_IPUCLARI = (
    "açiklayiniz", "açikla", "neden", "niçin", "yorumlay", "tartiş",
    "karşilaştir", "gerekçelendir", "nasil gerçekleşir",
)


def _icerir(alcak: str, ipuclari: tuple[str, ...]) -> bool:
    return any(ipucu in alcak for ipucu in ipuclari)


def cevap_turunu_cikar(
    soru: str,
    secenekler: dict[str, str] | None = None,
    cozum: str = "",
) -> str:
    """Soru (ve varsa şıklar/çözüm) için beklenen cevap türü."""
    alcak = esitle(f"{soru} {cozum}")

    # Şık listesi en güçlü işaret — ama D/Y şıkları çoktan seçmeli değildir.
    if secenekler:
        degerler = {esitle(d).strip() for d in secenekler.values()}
        if degerler and degerler <= {"doğru", "yanliş", "d", "y"}:
            return "dogru_yanlis"
        return "coktan_secmeli"

    if _icerir(alcak, _DOGRU_YANLIS_IPUCLARI):
        return "dogru_yanlis"
    if _icerir(alcak, _ESLESTIRME_IPUCLARI) or _ESLESTIRME_CIFTI.search(soru):
        return "eslestirme"
    if _icerir(alcak, _SIRALAMA_IPUCLARI):
        return "siralama"
    if _icerir(alcak, _BOSLUK_IPUCLARI) or _BOSLUK.search(soru):
        return "bosluk_doldurma"
    # Açıklama istendiğinde "kaç" geçse bile açık uçludur
    # ("Kaç ATP üretilir, açıklayınız" bir kısa cevap sorusu değildir).
    if _icerir(alcak, _ACIK_UCLU_IPUCLARI):
        return "acik_uclu"
    if _icerir(alcak, _KISA_CEVAP_IPUCLARI):
        return "kisa_cevap"
    return "acik_uclu"


def bosluk_sayisi(soru: str) -> int:
    """Boşluk doldurma sorusundaki boşluk adedi (cevap sayısını denetlemek için)."""
    return len(_BOSLUK.findall(soru))
