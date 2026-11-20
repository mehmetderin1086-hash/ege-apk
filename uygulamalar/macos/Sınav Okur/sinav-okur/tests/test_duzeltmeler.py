"""Kod incelemesi bulgularının regresyon testleri."""
import warnings

import numpy as np
import pytest

from sinav_okur.modeller import CevapAnahtari, RubrikKalemi, Sinav, Soru, SoruTipi
from sinav_okur.puanlama import PuanlamaAyar
from sinav_okur.puanlama.rubrik import rubrik_puanla


class SahteGomlemci:
    """'parafraz' ↔ ilk kaleme sınırda (0.59) benzerlik veren gömlemci."""

    def __init__(self, benzerlik):
        self.benzerlik = benzerlik

    def gom(self, metinler):
        # ilk metin kalem, sonrakiler cevap cümleleri; sınırda benzerlik kur
        n = len(metinler)
        vek = np.zeros((n, 2))
        vek[0] = [1.0, 0.0]
        for i in range(1, n):
            b = self.benzerlik
            vek[i] = [b, (1 - b**2) ** 0.5]
        return vek


def test_bulgu1_ret_karari_sinirda_incele():
    """Sınırda anlamsal eşleşme (0.59, eşik 0.60) sessizce 0 almamalı, incele olmalı."""
    soru = Soru(no=1, tip=SoruTipi.KISA_CEVAP, metin="x", puan=10,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("mitokondri enerji üretir", 10)]))
    # sözcüksel net ret (alakasız kelimeler) + anlamsal tam sınırda
    sonuc = rubrik_puanla("bambaşka alakasız kelimeler burada", soru,
                          gomlemci=SahteGomlemci(0.59))
    assert sonuc.puan == 0
    assert sonuc.incele  # min-güven düzeltmesi olmadan max ile incele=False kalırdı


def test_bulgu4_sayisal_cevap_str_zorlama():
    """Tırnaksız sayısal cevap (int) puanlamada TypeError vermemeli."""
    soru = Soru(no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="x", puan=5,
                anahtar=CevapAnahtari(dogru_cevaplar=[1453, "1453"]))
    from sinav_okur.puanlama.bosluk import bosluk_puanla
    sonuc = bosluk_puanla("1453", soru)  # patlamouyor
    assert sonuc.puan == 5


def test_bulgu4_sinav_kimlik_sayisal():
    """kimlik sayısal gelse bile str'a zorlanmalı."""
    s = Sinav(kimlik=2026, baslik="T", sorular=[
        {"no": 1, "tip": "bosluk_doldurma", "metin": "x", "puan": 5,
         "anahtar": {"dogru_cevaplar": ["m"]}}])
    assert s.kimlik == "2026"
    assert isinstance(s.kimlik, str)


def test_bulgu6_kisa_kalem_altdize_yanlis_pozitif():
    """Kısa kalem 'su', cevaptaki 'susuz' ile eşleşmemeli (alt-dize yanlış pozitifi)."""
    soru = Soru(no=1, tip=SoruTipi.KISA_CEVAP, metin="x", puan=10,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("su", 10)]))
    yanlis = rubrik_puanla("bitki susuz kalınca solar", soru)
    assert yanlis.puan == 0  # 'susuz' içinde 'su' geçse de kelime değil
    dogru = rubrik_puanla("cevap su moleküküdür", soru)
    assert dogru.puan == 10  # gerçek 'su' kelimesi


def test_bulgu8_eksik_rubrik_uyarisi():
    """Rubrik toplamı soru puanından düşükse uyarı verilmeli."""
    with pytest.warns(UserWarning, match="düşük"):
        Soru(no=1, tip=SoruTipi.KISA_CEVAP, metin="x", puan=20,
             anahtar=CevapAnahtari(rubrik=[RubrikKalemi("a", 5), RubrikKalemi("b", 5)]))


def _serbest_tek_soru(tmp_path):
    import cv2

    from sinav_okur.serbest import SerbestKutu, SerbestSablon

    ana = np.full((800, 600, 3), 255, np.uint8)
    for sira in range(12):
        cv2.putText(
            ana,
            f"1. Biyoloji sorusu satir {sira}",
            (35, 55 + sira * 45),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (0, 0, 0),
            1,
        )
    ogrenci = ana.copy()
    cv2.putText(
        ogrenci,
        "mitokondri",
        (90, 680),
        cv2.FONT_HERSHEY_SCRIPT_SIMPLEX,
        1.2,
        (25, 25, 25),
        3,
    )
    ana_yolu = tmp_path / "temiz.png"
    ogrenci_yolu = tmp_path / "ogrenci.png"
    cv2.imwrite(str(ana_yolu), ana)
    cv2.imwrite(str(ogrenci_yolu), ogrenci)
    sinav = Sinav(
        kimlik="SERBEST-REG",
        baslik="Serbest regresyon",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Enerji organelini yazınız.",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("mitokondri", 10)]
                ),
            )
        ],
    )
    sablon = SerbestSablon(
        sinav_kimlik=sinav.kimlik,
        dpi=200,
        sayfa_gorselleri=[str(ana_yolu)],
        kutular=[SerbestKutu(1, 1, 0.05, 0.55, 0.90, 0.40)],
    )
    return sinav, sablon, ogrenci_yolu


def test_bulgu3_fazladan_ayni_sayfa_puani_ciftlemez(tmp_path):
    """Aynı öğrenci sayfası iki kez yüklenirse soru puanı çiftlenmemeli."""
    from sinav_okur.htr import YapayTaniyici
    from sinav_okur.serbest import serbest_kagit_isle

    sinav, sablon, ogrenci = _serbest_tek_soru(tmp_path)
    sonuc = serbest_kagit_isle(
        [ogrenci, ogrenci],
        sinav,
        sablon,
        YapayTaniyici("mitokondri", 0.9),
    )

    assert len(sonuc.kutular) == 1
    assert sonuc.max_puan == 10


def test_bulgu2_murekkep_var_tanima_bos_incele(tmp_path):
    """Mürekkep varken OCR boş dönerse otomatik 0 yerine inceleme zorunlu."""
    from sinav_okur.htr import YapayTaniyici
    from sinav_okur.serbest import serbest_kagit_isle

    sinav, sablon, ogrenci = _serbest_tek_soru(tmp_path)
    sonuc = serbest_kagit_isle(
        ogrenci,
        sinav,
        sablon,
        YapayTaniyici(metin="", guven=1.0),
    )

    assert len(sonuc.kutular) == 1
    assert sonuc.kutular[0].puan.incele is True
    assert sonuc.kutular[0].puan.puan == 0
