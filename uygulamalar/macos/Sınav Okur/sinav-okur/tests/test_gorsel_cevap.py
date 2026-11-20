"""gorsel_cevabi_incele: grafik/tablo/çizim yapısal görüntü analizi.

Hough/kontur eşikleri sentetikte kararsız olabildiğinden testler eşik
değerlerini değil davranış sınıfını (algılandı/algılanmadı) doğrular; bunun
için büyük tuval + kalın çizgiler kullanılır.
"""
import numpy as np
import pytest

pytest.importorskip("cv2")
import cv2

from sinav_okur.gorsel_cevap import gorsel_cevabi_incele
from sinav_okur.modeller import SoruTipi


def _tuval(boyut=500):
    return np.full((boyut, boyut, 3), 255, np.uint8)


def test_bos_goruntu_algilanmaz():
    sonuc = gorsel_cevabi_incele(np.empty(0), SoruTipi.GRAFIK)
    assert sonuc["algilandi"] is False
    assert sonuc["neden"] == "Görüntü yok"


def test_none_goruntu_algilanmaz():
    sonuc = gorsel_cevabi_incele(None, SoruTipi.CIZIM)
    assert sonuc["algilandi"] is False


def test_grafik_eksen_ve_egri_algilanir():
    g = _tuval()
    # y ekseni (dikey), x ekseni (yatay), veri eğrisi (çapraz)
    cv2.line(g, (60, 40), (60, 440), (0, 0, 0), 4)
    cv2.line(g, (60, 440), (460, 440), (0, 0, 0), 4)
    cv2.line(g, (60, 440), (300, 120), (0, 0, 0), 4)
    sonuc = gorsel_cevabi_incele(g, SoruTipi.GRAFIK)
    assert sonuc["algilandi"] is True
    assert sonuc["tip"] == "grafik"


def test_grafik_bos_sayfa_algilanmaz():
    sonuc = gorsel_cevabi_incele(_tuval(), SoruTipi.GRAFIK)
    assert sonuc["algilandi"] is False


def test_tablo_izgara_algilanir():
    g = _tuval()
    for x in (100, 250, 400):
        cv2.line(g, (x, 60), (x, 440), (0, 0, 0), 4)
    for y in (100, 250, 400):
        cv2.line(g, (60, y), (440, y), (0, 0, 0), 4)
    sonuc = gorsel_cevabi_incele(g, SoruTipi.TABLO)
    assert sonuc["algilandi"] is True
    assert sonuc["yatay_cizgi"] >= 2 and sonuc["dikey_cizgi"] >= 2


def test_tablo_tek_cizgi_algilanmaz():
    g = _tuval()
    cv2.line(g, (60, 250), (440, 250), (0, 0, 0), 4)
    sonuc = gorsel_cevabi_incele(g, SoruTipi.TABLO)
    assert sonuc["algilandi"] is False


def test_cizim_bilesenler_algilanir():
    g = _tuval()
    cv2.circle(g, (150, 150), 60, (0, 0, 0), 4)
    cv2.rectangle(g, (280, 280), (400, 400), (0, 0, 0), 4)
    sonuc = gorsel_cevabi_incele(g, SoruTipi.CIZIM)
    assert sonuc["algilandi"] is True


def test_donen_sozluk_semasi():
    sonuc = gorsel_cevabi_incele(_tuval(), SoruTipi.GRAFIK)
    for anahtar in (
        "tip", "algilandi", "yatay_cizgi", "dikey_cizgi",
        "capraz_cizgi", "bilesen", "koyu_oran", "neden",
    ):
        assert anahtar in sonuc
