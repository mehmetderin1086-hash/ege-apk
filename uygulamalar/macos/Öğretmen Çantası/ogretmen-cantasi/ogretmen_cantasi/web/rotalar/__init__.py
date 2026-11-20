"""Rota modülleri: her biri `bagla(uygulama)` ile kendi uç noktalarını FastAPI uygulamasına ekler."""

from . import (
    bugun,
    deneme,
    entegrasyon,
    kurulum,
    materyal,
    mcp,
    notlar,
    ogrenci,
    olcme,
    plan,
    sistem,
    sube,
    takvim,
    yardimci,
    yoklama,
)

__all__ = [
    "bugun",
    "deneme",
    "entegrasyon",
    "kurulum",
    "materyal",
    "mcp",
    "notlar",
    "ogrenci",
    "olcme",
    "plan",
    "sistem",
    "sube",
    "takvim",
    "yardimci",
    "yoklama",
]

# Kayıt sırası menü/öncelik açısından önemsiz; tek listede durur ki yeni bir
# modül eklerken import, __all__ ve bağlama çağrısı ayrı ayrı unutulmasın.
HEPSI = (
    bugun,
    kurulum,
    sube,
    plan,
    yoklama,
    notlar,
    ogrenci,
    olcme,
    takvim,
    deneme,
    materyal,
    entegrasyon,
    mcp,
    yardimci,
    sistem,
)
