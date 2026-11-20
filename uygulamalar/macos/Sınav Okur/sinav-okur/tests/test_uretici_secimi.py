"""Anahtar üreticisinin seçimi: yerel motor → Claude API → taslak."""

from __future__ import annotations

import pytest

from sinav_okur.webapp.baglam import WebBaglam, _yedekli_uretici
from sinav_okur.yapay_zeka import YapayZekaCevabi, YapayZekaHatasi


def _baglam(**alanlar) -> WebBaglam:
    baglam = object.__new__(WebBaglam)
    baglam.yerel_uretici = None
    baglam.yerel_uret = None
    for ad, deger in alanlar.items():
        setattr(baglam, ad, deger)
    return baglam


def _cevap(no: int = 1) -> YapayZekaCevabi:
    return YapayZekaCevabi(no, "cevap", ["ölçüt"])


def test_yerel_kullanilamazsa_buluta_dusulur(monkeypatch):
    monkeypatch.delenv("SINAV_OKUR_ANAHTAR_URETICI", raising=False)
    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_motor_durumu",
        lambda: {"hazir": False, "kullanilabilir": False, "mesaj": ""},
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.claude_api_durumu", lambda: {"hazir": True}
    )

    uretici, hazir, ad = _baglam()._uretici_sec()

    assert hazir is True
    assert "kaynakla sınırlandırılmış" in ad


def test_bozuk_yerel_motor_bulut_hazirken_gollemez(monkeypatch):
    """Yerel motor kurulu görünüp üretemiyorsa çalışan buluta düşülmeli."""
    monkeypatch.delenv("SINAV_OKUR_ANAHTAR_URETICI", raising=False)
    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_motor_durumu",
        lambda: {"hazir": False, "kullanilabilir": True, "mesaj": ""},
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.claude_api_durumu", lambda: {"hazir": True}
    )

    def bozuk_yerel(sorular, **_ayar):
        raise YapayZekaHatasi("model yüklenemedi")

    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_cevap_anahtarlari_uret", bozuk_yerel
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.cevap_anahtarlari_uret",
        lambda sorular, **_a: [_cevap()],
    )

    uretici, hazir, _ad = _baglam()._uretici_sec()

    assert hazir is True
    assert uretici([(1, "soru", 10.0)], ders="", kanitlar=None)[0].soru_no == 1


def test_bulut_kapaliyken_yerel_hatasi_yutulmaz(monkeypatch):
    monkeypatch.delenv("SINAV_OKUR_ANAHTAR_URETICI", raising=False)
    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_motor_durumu",
        lambda: {"hazir": True, "kullanilabilir": True, "mesaj": ""},
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.claude_api_durumu", lambda: {"hazir": False}
    )
    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_cevap_anahtarlari_uret",
        lambda sorular, **_a: [_cevap()],
    )

    uretici, hazir, ad = _baglam()._uretici_sec()

    assert hazir is True
    assert ad == "yerel model (biyo-cozucu)"


def test_bulut_tercihi_yerel_motoru_atlar(monkeypatch):
    monkeypatch.setenv("SINAV_OKUR_ANAHTAR_URETICI", "bulut")

    def cagrilmamali():
        raise AssertionError("bulut tercihinde yerel motor sorgulanmamalı")

    monkeypatch.setattr(
        "sinav_okur.yerel_motor.yerel_motor_durumu", cagrilmamali
    )
    monkeypatch.setattr(
        "sinav_okur.yapay_zeka.claude_api_durumu", lambda: {"hazir": True}
    )

    _uretici, hazir, ad = _baglam()._uretici_sec()

    assert hazir is True
    assert "kaynakla sınırlandırılmış" in ad


def test_yedekli_uretici_yalniz_yapay_zeka_hatasinda_duser():
    def birincil(sorular, **_a):
        raise ValueError("beklenmeyen hata")

    uretici = _yedekli_uretici(birincil, lambda sorular, **_a: [_cevap()])

    with pytest.raises(ValueError):
        uretici([(1, "soru", 10.0)])
