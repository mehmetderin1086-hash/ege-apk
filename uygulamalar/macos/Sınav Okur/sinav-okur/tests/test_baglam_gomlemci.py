"""WebBaglam.gomlemci(): tembel yükleme ve güvenli geri düşme."""

from __future__ import annotations

import pytest

from sinav_okur.webapp.baglam import WebBaglam


def _bos_baglam() -> WebBaglam:
    baglam = object.__new__(WebBaglam)
    baglam._gomlemci_onbellegi = []
    return baglam


def test_gomlemci_bir_kez_yuklenir(monkeypatch):
    monkeypatch.setenv("SINAV_OKUR_GOMLEMCI", "acik")
    cagri = []

    def sahte_yukle():
        cagri.append(1)
        return "gomlemci"

    monkeypatch.setattr(
        "sinav_okur.puanlama.gomme.gomlemci_yukle", sahte_yukle
    )
    baglam = _bos_baglam()

    assert baglam.gomlemci() == "gomlemci"
    assert baglam.gomlemci() == "gomlemci"
    assert cagri == [1]


def test_yukleyici_patlarsa_none_donulur_ve_tekrar_denenmez(monkeypatch):
    """Ölçüldü: Keras 3 kurulu makinede yükleyici ValueError fırlatıyor.

    Puanlama bu durumda sözcüksel katmanla çalışmaya devam etmeli; her
    istekte 3 sn'lik başarısız yükleme tekrarlanmamalı.
    """
    monkeypatch.setenv("SINAV_OKUR_GOMLEMCI", "acik")
    cagri = []

    def patlayan_yukle():
        cagri.append(1)
        raise ValueError("Keras 3 desteklenmiyor")

    monkeypatch.setattr(
        "sinav_okur.puanlama.gomme.gomlemci_yukle", patlayan_yukle
    )
    baglam = _bos_baglam()

    assert baglam.gomlemci() is None
    assert baglam.gomlemci() is None
    assert cagri == [1]


def test_varsayilan_kapali_yukleyici_hic_cagrilmaz(monkeypatch):
    """Anlamsal puanlama bilinçli açılmalı; varsayılan sözcüksel kalır.

    Aksi hâlde bir sorunun anahtarını düzenlemek, dokunulmamış eski kutuların
    puanını yeni algoritmayla sessizce kaydırırdı.
    """

    def cagrilmamali():
        raise AssertionError("varsayılan kapalıyken yükleme olmamalı")

    monkeypatch.setattr(
        "sinav_okur.puanlama.gomme.gomlemci_yukle", cagrilmamali
    )
    monkeypatch.delenv("SINAV_OKUR_GOMLEMCI", raising=False)
    assert _bos_baglam().gomlemci() is None

    monkeypatch.setenv("SINAV_OKUR_GOMLEMCI", "kapali")
    assert _bos_baglam().gomlemci() is None
