"""TensorFlow kurmadan Keras çıkarım mantığını sahte modellerle doğrula."""

import json

import numpy as np
import pytest

pytest.importorskip("cv2")
import cv2

from sinav_okur.htr.keras_cnn import KerasKarakterTaniyici, _bilesen_kutulari
from sinav_okur.htr.keras_ctc import KerasCtcTaniyici


class _KarakterModel:
    def __init__(self, sinif=0):
        self.sinif = sinif

    def predict(self, x, verbose=0):
        out = np.full((len(x), 2), -5.0, dtype=np.float32)
        out[:, self.sinif] = 5.0
        return out


def test_ayrik_karakterleri_okur():
    g = np.full((70, 150), 255, dtype=np.uint8)
    cv2.rectangle(g, (15, 15), (40, 55), 0, -1)
    cv2.rectangle(g, (80, 15), (105, 55), 0, -1)
    taniyici = KerasKarakterTaniyici(model=_KarakterModel(0), etiketler=["a", "b"])
    sonuc = taniyici._satir_taniy(g)
    assert sonuc.metin.replace(" ", "") == "aa"
    assert sonuc.guven > 0.9


def test_birlesik_genis_bilesende_guven_duser():
    g = np.full((70, 180), 255, dtype=np.uint8)
    cv2.rectangle(g, (10, 20), (150, 50), 0, -1)
    taniyici = KerasKarakterTaniyici(model=_KarakterModel(), etiketler=["a", "b"])
    sonuc = taniyici._satir_taniy(g)
    assert sonuc.guven <= 0.45


def test_aksan_ve_nokta_ayri_karakter_sayilmaz():
    g = np.full((70, 90), 255, dtype=np.uint8)
    cv2.rectangle(g, (28, 20), (52, 55), 0, -1)
    cv2.rectangle(g, (36, 8), (43, 13), 0, -1)

    assert len(_bilesen_kutulari(g)) == 1


def test_yatay_aralik_iki_karakteri_ayirir():
    g = np.full((70, 150), 255, dtype=np.uint8)
    cv2.rectangle(g, (15, 15), (40, 55), 0, -1)
    cv2.rectangle(g, (85, 15), (110, 55), 0, -1)

    assert len(_bilesen_kutulari(g)) == 2


def test_kalibre_esik_altini_incelemeye_gonderir():
    class _KalibreModel:
        def predict(self, x, verbose=0):
            return np.tile(np.array([[0.95, 0.05]], dtype=np.float32), (len(x), 1))

    g = np.full((70, 80), 255, dtype=np.uint8)
    cv2.rectangle(g, (20, 15), (40, 55), 0, -1)
    taniyici = KerasKarakterTaniyici(
        model=_KalibreModel(), etiketler=["a", "b"], kabul_esigi=0.960251
    )
    sonuc = taniyici._satir_taniy(g)
    assert sonuc.metin == "a"
    assert sonuc.guven == pytest.approx(0.74)


def test_kalibre_esigi_model_klasorunden_otomatik_yukler(tmp_path):
    model_yolu = tmp_path / "turkce_karakter_cnn_casefold.keras"
    (tmp_path / "casefold_metrikleri.json").write_text(
        json.dumps({"selective": {"0.99": {"threshold": 0.960251}}}),
        encoding="utf-8",
    )
    taniyici = KerasKarakterTaniyici(
        model_yolu=model_yolu, model=_KarakterModel(), etiketler=["a", "b"]
    )
    assert taniyici.kabul_esigi == pytest.approx(0.960251)


def test_ctc_tekrarlari_ve_blank_siler():
    taniyici = KerasCtcTaniyici(model=object(), etiketler=["a", "b"])
    logits = np.full((6, 3), -8.0, dtype=np.float32)
    for t, i in enumerate([0, 0, 2, 1, 1, 2]):
        logits[t, i] = 8.0
    sonuc = taniyici._coz(logits)
    assert sonuc.metin == "ab"
    assert sonuc.guven > 0.99


def test_ctc_kalibre_esigi_model_klasorunden_yukler_ve_incelemeye_gonderir(tmp_path):
    model_yolu = tmp_path / "turkce_gercek_satir_ctc.keras"
    (tmp_path / "ctc_metrikleri.json").write_text(
        json.dumps({"auto_accept_99": {"threshold": 1.0}}),
        encoding="utf-8",
    )
    taniyici = KerasCtcTaniyici(
        model_yolu=model_yolu, model=object(), etiketler=["a", "b"]
    )
    logits = np.full((3, 3), -8.0, dtype=np.float32)
    for t, i in enumerate([0, 2, 1]):
        logits[t, i] = 8.0

    sonuc = taniyici._coz(logits)

    assert taniyici.kabul_esigi == pytest.approx(1.0)
    assert sonuc.metin == "ab"
    assert sonuc.guven == pytest.approx(0.74)


def test_karakter_modeli_etiket_sayisi_uyusmazligini_reddeder():
    model = _KarakterModel()
    model.output_shape = (None, 3)
    with pytest.raises(ValueError, match="Model/etiket uyuşmazlığı"):
        KerasKarakterTaniyici(model=model, etiketler=["a", "b"])


def test_ctc_modeli_etiket_ve_blank_sayisi_uyusmazligini_reddeder():
    class _CtcModel:
        output_shape = (None, 20, 4)

    with pytest.raises(ValueError, match="CTC model/etiket uyuşmazlığı"):
        KerasCtcTaniyici(model=_CtcModel(), etiketler=["a", "b"])
