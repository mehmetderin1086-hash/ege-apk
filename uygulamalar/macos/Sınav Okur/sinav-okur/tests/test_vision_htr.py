from types import SimpleNamespace

import numpy as np

from sinav_okur.htr.vision import VisionTaniyici


def test_vision_taniyici_satirlari_siralar_ve_guveni_hesaplar(
    monkeypatch, tmp_path
):
    def sahte_vision(_yol, _arac):
        return [
            SimpleNamespace(
                text="ikinci satır",
                confidence=0.8,
                x=0.1,
                y=0.4,
            ),
            SimpleNamespace(
                text="ilk satır",
                confidence=0.6,
                x=0.1,
                y=0.2,
            ),
        ]

    monkeypatch.setattr("sinav_okur.serbest.vision_ocr", sahte_vision)
    taniyici = VisionTaniyici(tmp_path / "araclar")

    sonuc = taniyici.kutu_taniy(np.full((80, 300, 3), 255, np.uint8))

    assert sonuc.metin == "ilk satır\nikinci satır"
    assert sonuc.guven == 0.7


def test_vision_taniyici_bos_sonuca_yuzde_yuz_vermez(monkeypatch, tmp_path):
    monkeypatch.setattr("sinav_okur.serbest.vision_ocr", lambda *_a: [])
    taniyici = VisionTaniyici(tmp_path / "araclar")

    sonuc = taniyici.kutu_taniy(np.full((80, 300, 3), 255, np.uint8))

    assert sonuc.metin == ""
    assert sonuc.guven == 0.0
