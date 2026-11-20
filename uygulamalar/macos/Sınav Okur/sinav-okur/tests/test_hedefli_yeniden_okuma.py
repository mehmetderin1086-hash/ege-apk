"""Hedefli kutu yeniden okuma: pahalı görünümler yalnız kanıt zayıfken."""
from __future__ import annotations

import pytest

pytest.importorskip("cv2")
import numpy as np

from sinav_okur.htr.coklu import CokluTaniyici
from sinav_okur.kalite import ocr_varyantlari, ocr_varyantlari_genis
from sinav_okur.modeller import TanimaSonucu


class SayaclıMotor:
    """Çağrı sayan sahte motor; her çağrıda sabit metin/güven döner."""

    def __init__(self, metin="mitokondri", guven=0.9):
        self.metin = metin
        self.guven = guven
        self.cagri = 0
        self.varyantlar: list[tuple[int, int]] = []

    def kutu_taniy(self, kirp, dpi=300):
        self.cagri += 1
        self.varyantlar.append(tuple(kirp.shape[:2]))
        return TanimaSonucu(metin=self.metin, guven=self.guven)


def _gorsel(yukseklik=120, genislik=400):
    gorsel = np.full((yukseklik, genislik, 3), 255, np.uint8)
    gorsel[40:70, 30:260] = 40  # koyu bir yazı izi
    return gorsel


def test_yuksek_kanitta_asama_iki_calismaz():
    motor = SayaclıMotor(guven=0.95)
    t = CokluTaniyici([("a", motor, 1.0), ("b", SayaclıMotor(guven=0.93), 1.0)])
    gorsel = _gorsel()
    t.kutu_taniy(gorsel, 200)
    # Yalnız aşama-1 varyantları çalıştı
    assert motor.cagri == len(ocr_varyantlari(gorsel))


def test_dusuk_kanitta_asama_iki_calisir():
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici([("a", motor, 1.0), ("b", SayaclıMotor(guven=0.28), 1.0)],
                      azami_calisma=100)
    gorsel = _gorsel()
    sonuc = t.kutu_taniy(gorsel, 200)
    assert motor.cagri > len(ocr_varyantlari(gorsel))
    assert any(s.get("asama") == 2 for s in sonuc.motor_sonuclari)


def test_asama_iki_kapatilabilir():
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici(
        [("a", motor, 1.0), ("b", SayaclıMotor(guven=0.28), 1.0)],
        azami_calisma=100,
        asama_iki_acik=False,
    )
    gorsel = _gorsel()
    t.kutu_taniy(gorsel, 200)
    assert motor.cagri == len(ocr_varyantlari(gorsel))


def test_sure_butcesi_asilinca_asama_bir_sonucu_korunur():
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici(
        [("a", motor, 1.0), ("b", SayaclıMotor(guven=0.28), 1.0)],
        azami_calisma=100,
        asama_iki_sure_butcesi=0.0,  # bütçe hemen dolar
    )
    gorsel = _gorsel()
    sonuc = t.kutu_taniy(gorsel, 200)
    assert motor.cagri == len(ocr_varyantlari(gorsel))
    assert sonuc.metin == "mitokondri"


def test_azami_calisma_asama_biri_sinirlar():
    """`azami_calisma` aşama-1'in bütçesidir; aşama-2'nin kendi bütçesi var."""
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici([("a", motor, 1.0)], azami_calisma=3, asama_iki_acik=False)
    t.kutu_taniy(_gorsel(), 200)
    assert motor.cagri == 3


def test_tek_motorlu_kurulumda_motor_sayisi_asama_iki_tetiklemez():
    """Tek motor kuruluysa ikinci geçiş yeni bağımsız kanıt üretemez."""
    motor = SayaclıMotor(guven=0.95)
    t = CokluTaniyici([("a", motor, 1.0)], azami_calisma=100)
    gorsel = _gorsel()
    t.kutu_taniy(gorsel, 200)
    assert motor.cagri == len(ocr_varyantlari(gorsel))


def test_motor_coksa_ama_biri_sussa_asama_iki_calisir():
    class SessizMotor(SayaclıMotor):
        def kutu_taniy(self, kirp, dpi=300):
            self.cagri += 1
            return TanimaSonucu(metin="", guven=0.0)

    konusan = SayaclıMotor(guven=0.95)
    t = CokluTaniyici(
        [("a", konusan, 1.0), ("b", SessizMotor(), 1.0)], azami_calisma=100
    )
    gorsel = _gorsel()
    t.kutu_taniy(gorsel, 200)
    assert konusan.cagri > len(ocr_varyantlari(gorsel))


def test_genis_varyantlar_sozlesmesi():
    gorsel = _gorsel()
    varyantlar = ocr_varyantlari_genis(gorsel)
    adlar = {ad for ad, _ in varyantlar}
    assert "buyutulmus" in adlar
    assert "ters_kontrast" in adlar
    for _ad, goruntu in varyantlar:
        assert goruntu.ndim == 3 and goruntu.shape[2] == 3
    # Aşama-1 varyantlarını tekrarlamaz
    assert not adlar & {ad for ad, _ in ocr_varyantlari(gorsel)}


def test_bos_goruntude_genis_varyant_yok():
    assert ocr_varyantlari_genis(None) == []
    assert ocr_varyantlari_genis(np.zeros((0, 0, 3), np.uint8)) == []


def test_varsayilan_butcede_iki_motorla_asama_iki_calisir():
    """Aşama-1 varsayılan bütçeyi (5 varyant × 2 motor = 10) tüketse bile
    ikinci geçiş kendi bütçesiyle çalışmalı; aksi halde özellik üretimde ölü."""
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici([("a", motor, 1.0), ("b", SayaclıMotor(guven=0.28), 1.0)])
    gorsel = _gorsel()
    sonuc = t.kutu_taniy(gorsel, 200)
    assert any(s.get("asama") == 2 for s in sonuc.motor_sonuclari)


def test_asama_iki_kendi_calisma_sinirina_uyar():
    motor = SayaclıMotor(guven=0.30)
    t = CokluTaniyici(
        [("a", motor, 1.0), ("b", SayaclıMotor(guven=0.28), 1.0)],
        asama_iki_azami_calisma=2,
    )
    sonuc = t.kutu_taniy(_gorsel(), 200)
    asama2 = [s for s in sonuc.motor_sonuclari if s.get("asama") == 2]
    assert len(asama2) == 2
