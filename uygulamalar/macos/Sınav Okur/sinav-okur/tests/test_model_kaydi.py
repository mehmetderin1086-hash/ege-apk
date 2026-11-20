"""model_kaydi: çalışan OCR motorlarının yeniden üretilebilir kaydı."""
import json

from sinav_okur.htr.model_kaydi import model_kaydi


class _Motor:
    """Test için asgari motor: opsiyonel model_yolu ve device taşır."""

    def __init__(self, model_yolu=None, device=None):
        if model_yolu is not None:
            self.model_yolu = str(model_yolu)
        if device is not None:
            self.device = device


def test_kok_sema():
    kayit = model_kaydi([("vision", _Motor())])
    assert kayit["boru_hatti"] == "siyah-kursun-v2"
    assert isinstance(kayit["motorlar"], list)


def test_ad_ve_sinif_alanlari():
    kayit = model_kaydi([("vision", _Motor())])
    m = kayit["motorlar"][0]
    assert m["ad"] == "vision"
    assert m["sinif"].endswith("_Motor")


def test_yolsuz_motorda_parmakizi_yok():
    m = model_kaydi([("vision", _Motor())])["motorlar"][0]
    assert "parmakizi" not in m
    assert "model_yolu" not in m


def test_dosya_yolu_parmakizi_uretir(tmp_path):
    yol = tmp_path / "model.bin"
    yol.write_bytes(b"agirlik")
    m = model_kaydi([("trocr", _Motor(model_yolu=yol))])["motorlar"][0]
    assert len(m["parmakizi"]) == 16
    assert m["model_yolu"] == str(yol)


def test_dizin_yolu_config_ile_parmakizi(tmp_path):
    d = tmp_path / "trocr-tr"
    d.mkdir()
    (d / "config.json").write_text("{}")
    m = model_kaydi([("trocr", _Motor(model_yolu=d))])["motorlar"][0]
    assert "parmakizi" in m


def test_dosya_degisince_parmakizi_degisir(tmp_path):
    yol = tmp_path / "model.bin"
    yol.write_bytes(b"bir")
    ilk = model_kaydi([("t", _Motor(model_yolu=yol))])["motorlar"][0]["parmakizi"]
    yol.write_bytes(b"cok daha uzun icerik farkli boyut")
    ikinci = model_kaydi([("t", _Motor(model_yolu=yol))])["motorlar"][0]["parmakizi"]
    assert ilk != ikinci


def test_device_aygit_olarak_kaydedilir():
    m = model_kaydi([("mlx", _Motor(device="mps"))])["motorlar"][0]
    assert m["aygit"] == "mps"


def test_json_serilesebilir():
    kayit = model_kaydi([("vision", _Motor(device="cpu"))])
    json.dumps(kayit)  # istisna atmamalı
