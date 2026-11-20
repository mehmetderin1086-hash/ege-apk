"""Dosya yolları ve çalışma zamanı ayarları.

Öğrenci verisi kullanıcının kişisel klasöründe kalır; depo dizininde tutulmaz.
Böylece proje klasörü git'e girse bile hiçbir öğrenci adı sürüm geçmişine
düşmez.
"""

from __future__ import annotations

import os
from pathlib import Path

PROJE = Path(__file__).resolve().parents[1]
VERI_DIZINI = PROJE / "veri"

UYGULAMA_ADI = "Öğretmen Çantası"
# Başlatıcının "portta gerçekten bu program mı çalışıyor" kontrolünde aradığı
# imza. Kardeş programların sunucusunu kendi sunucumuz sanmamak için gerekli.
IMZA = "ogretmen-cantasi"

# Port aralığı: 8000 PDF Studio, 8000-8010 Sınav Okur, 8010 SesLab,
# 8020-8030 Soru Çözücü, 8317 CLI Proxy, 8766 BioProf tarafından kullanılıyor.
PORT_BASLANGIC = 8040
PORT_BITIS = 8050


def veri_koku() -> Path:
    """Veritabanı, yedekler ve materyal dosyalarının tutulduğu kök dizin."""
    ozel = os.environ.get("OGRETMEN_CANTASI_VERI")
    if ozel:
        return Path(ozel).expanduser()
    return Path.home() / "Library" / "Application Support" / "OgretmenCantasi"


def veritabani_yolu() -> Path:
    return veri_koku() / "veri.db"


def yedek_dizini() -> Path:
    return veri_koku() / "yedekler"


def materyal_dizini() -> Path:
    return veri_koku() / "materyaller"


def entegrasyon_dizini() -> Path:
    return veri_koku() / "entegrasyonlar"


def entegrasyon_belirteci_yolu() -> Path:
    return entegrasyon_dizini() / "yerel-api.token"


def gunluk_dizini() -> Path:
    return Path.home() / "Library" / "Logs" / "OgretmenCantasi"


def dizinleri_hazirla() -> None:
    for dizin in (veri_koku(), yedek_dizini(), materyal_dizini(), entegrasyon_dizini()):
        dizin.mkdir(parents=True, exist_ok=True)
