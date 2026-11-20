"""El yazısı fontlarının Türkçe karakter kapsamını cmap ile doğrulama.

Araştırmanın kritik bulgusu: popüler el yazısı fontlarının çoğu ğ/İ/ş gibi
Türkçe karakterleri sessizce eksik bırakır (tofu/eksik glif). Sentetik veriye
girmeden önce her font gerçekten tüm Türkçe karakterleri içeriyor mu diye
cmap tablosundan denetlenir.
"""

from __future__ import annotations

from pathlib import Path

from fontTools.ttLib import TTFont

# Türkçe'ye özgü + temel Latin: hepsi fontun cmap'inde bulunmalı
ZORUNLU_KARAKTERLER = "abcçdefgğhıijklmnoöprsştuüvyzABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ0123456789.,;:()/-%"

# Araştırmada Türkçe-tam olduğu doğrulanan OFL Google el yazısı fontları
ONERILEN_FONTLAR = [
    "Caveat", "Caveat Brush", "Dancing Script", "Pacifico", "Patrick Hand",
    "Kalam", "Amatic SC", "Indie Flower", "Marck Script", "Courgette",
    "Great Vibes", "Sacramento", "Bad Script", "Merienda", "Itim",
]

# Türkçe karakterleri EKSİK olduğu bilinen, kaçınılması gereken fontlar
KACINILACAK_FONTLAR = [
    "Handlee", "Gochi Hand", "Homemade Apple", "Nanum Pen Script",
]


def eksik_karakterler(font_yolu: str | Path) -> list[str]:
    """Fontun cmap'inde bulunmayan zorunlu karakterleri döner (boşsa font uygun)."""
    font = TTFont(str(font_yolu), fontNumber=0, lazy=True)
    kapsanan: set[int] = set()
    for tablo in font["cmap"].tables:
        kapsanan.update(tablo.cmap.keys())
    font.close()
    return [ch for ch in ZORUNLU_KARAKTERLER if ord(ch) not in kapsanan]


def turkce_uygun_mu(font_yolu: str | Path) -> bool:
    return not eksik_karakterler(font_yolu)


def fontlari_dogrula(font_dizini: str | Path) -> dict[str, list[str]]:
    """Dizindeki tüm .ttf/.otf fontları denetler; {font_yolu: eksik_karakterler}."""
    rapor: dict[str, list[str]] = {}
    for yol in sorted(Path(font_dizini).glob("**/*")):
        if yol.suffix.lower() in {".ttf", ".otf"}:
            try:
                rapor[str(yol)] = eksik_karakterler(yol)
            except Exception as e:  # bozuk font dosyası
                rapor[str(yol)] = [f"HATA: {e}"]
    return rapor
