"""Kalibrasyon tablosunun kökeni ve hangi anahtarla uygulandığı.

İki sessiz defekt vardı: tablo hangi modelle öğrenildiği yazılmadan
saklanıyordu (model değişince eski çarpanlar uygulanmaya devam ediyordu) ve
GERÇEK türe göre öğrenilip TAHMİN edilen türe göre uygulanıyordu.
"""

from __future__ import annotations

import json

from biyo_cozucu.cozucu import KALIBRASYON_DOSYASI, kalibrasyonu_oku
from biyo_cozucu.degerlendirme import OrnekSonucu


def _tablo_yaz(kok, **ek):
    veri = {"tur_guvenilirligi": {"kalitim_hesabi": 0.44}, **ek}
    (kok / KALIBRASYON_DOSYASI).write_text(
        json.dumps(veri, ensure_ascii=False), encoding="utf-8"
    )


def test_modelsiz_eski_tablo_geriye_uyumlu_okunur(tmp_path):
    _tablo_yaz(tmp_path)
    assert kalibrasyonu_oku(tmp_path, model="yeni-model") == {"kalitim_hesabi": 0.44}


def test_ayni_model_tablosu_uygulanir(tmp_path):
    _tablo_yaz(tmp_path, model="biyo-mlx-v1")
    assert kalibrasyonu_oku(tmp_path, model="biyo-mlx-v1") == {"kalitim_hesabi": 0.44}


def test_farkli_model_tablosu_yok_sayilir(tmp_path):
    """Eski modelin zayıflıkları yeni modelin güvenini kırpmamalı."""
    _tablo_yaz(tmp_path, model="biyo-mlx-v1")
    assert kalibrasyonu_oku(tmp_path, model="Qwen3.5-4B") == {}


def test_model_verilmezse_kontrol_yapilmaz(tmp_path):
    _tablo_yaz(tmp_path, model="biyo-mlx-v1")
    assert kalibrasyonu_oku(tmp_path) == {"kalitim_hesabi": 0.44}


def test_ornek_sonucu_uretilen_turu_tasir():
    """Çarpan çıkarımda yalnız bu alana bakabilir; tablo da bununla öğrenilmeli."""
    sonuc = OrnekSonucu(
        ornek_id=1,
        soru="s",
        beklenen_cevap="A",
        uretilen_cevap="A",
        cevap_dogru=True,
        adim_ortusmesi=0.5,
        guven=0.9,
        incele=False,
        cozum_turu="kalitim_hesabi",
        uretilen_turu="grafik_yorumlama",
    )
    # Rapor gerçek türe, kalibrasyon tahmin edilen türe bakar; ikisi ayrı.
    assert sonuc.cozum_turu != sonuc.uretilen_turu
