"""Soru dosyası hazırlama uçlarının FastAPI üzerinden sözleşme testleri."""

from __future__ import annotations

import io
import json

import pytest

pytest.importorskip("fastapi")
pytest.importorskip("PIL")

from fastapi.testclient import TestClient
from PIL import Image

from biyo_cozucu.cozucu import Ayarlar
from biyo_cozucu.modeller import Cozum
from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.webapp import uygulama_kur


@pytest.fixture
def dosya_istemcisi(tmp_path, sahte_gomlemci, monkeypatch):
    from biyo_cozucu import gomme as gomme_modulu
    from biyo_cozucu import motor as motor_modulu

    monkeypatch.setattr(gomme_modulu, "gomlemci_yukle", lambda *a, **k: sahte_gomlemci)
    monkeypatch.setattr(
        motor_modulu,
        "motor_yukle",
        lambda *a, **k: SahteMotor(
            json.dumps(
                {"adimlar": ["Görsel okundu"], "cevap": "B", "guven": 0.85},
                ensure_ascii=False,
            )
        ),
    )
    return TestClient(uygulama_kur(tmp_path, motor_turu="sahte", ayarlar=Ayarlar()))


def _png() -> bytes:
    tampon = io.BytesIO()
    Image.new("RGB", (80, 50), "white").save(tampon, format="PNG")
    return tampon.getvalue()


def test_coz_formu_coklu_dosya_alani_tasir(dosya_istemcisi):
    yanit = dosya_istemcisi.get("/coz")
    assert 'name="dosyalar"' in yanit.text
    assert "multiple" in yanit.text
    assert ".pdf" in yanit.text
    assert 'class="dosya-secici"' in yanit.text
    assert "En fazla 12 dosya" in yanit.text
    assert "Çözüm burada görünecek" in yanit.text
    assert "Görsel okuma etkin" in yanit.text


def test_resim_cozum_kuyruguna_hazirlanir(dosya_istemcisi):
    yanit = dosya_istemcisi.post(
        "/coz/dosya/hazirla",
        data={"soru_notu": "Şıkları da açıkla."},
        files={"dosyalar": ("ekran.png", _png(), "image/png")},
    )
    assert yanit.status_code == 200
    veri = yanit.json()
    assert veri["toplam"] == 1
    assert veri["sorular"][0]["gorsel"]
    assert "Şıkları da açıkla" in veri["sorular"][0]["soru"]


def test_hazirlanan_gorsel_onizlenebilir(dosya_istemcisi):
    hazir = dosya_istemcisi.post(
        "/coz/dosya/hazirla",
        files={"dosyalar": ("soru.png", _png(), "image/png")},
    ).json()
    imza = hazir["sorular"][0]["gorsel"]
    yanit = dosya_istemcisi.get(f"/coz/gorsel/{imza}.png")
    assert yanit.status_code == 200
    assert yanit.headers["content-type"].startswith("image/png")


def test_gecersiz_hazir_gorsel_imzasi_reddedilir(dosya_istemcisi):
    with dosya_istemcisi.stream(
        "POST",
        "/coz/akis",
        data={"soru": "Şekilde ne var?", "gorsel_imza": "../gizli"},
    ) as yanit:
        govde = "".join(yanit.iter_text())
    assert "event: hata" in govde
    assert "geçersiz" in govde


def test_coklu_dosyadaki_siklar_formdaki_ortak_siklarla_ezilmez(
    dosya_istemcisi, monkeypatch
):
    """Elle girilen tek soru şıkları, PDF/TXT kuyruğuna sızmamalı."""

    class CasusCozucu:
        def __init__(self):
            self.cagrilar = []

        def coz(self, soru, **secenekler):
            self.cagrilar.append((soru, secenekler.get("secenekler")))
            return Cozum(soru=soru, adimlar=["Denetlendi"], cevap="A", guven=0.9)

    casus = CasusCozucu()
    monkeypatch.setattr(dosya_istemcisi.app.state.durum, "cozucu", lambda **_: casus)
    yanit = dosya_istemcisi.post(
        "/coz",
        data={"soru": "", "secenekler": "A) ORTAK\nB) YANLIŞ"},
        files=[
            ("dosyalar", ("bir.txt", b"Ribozomun gorevi nedir?", "text/plain")),
            ("dosyalar", ("iki.txt", b"Mitokondri ne yapar?", "text/plain")),
        ],
    )
    assert yanit.status_code == 200
    assert len(casus.cagrilar) == 2
    assert [secenekler for _soru, secenekler in casus.cagrilar] == [None, None]


def test_tek_siksiz_dosya_formdaki_siklarla_tamamlanabilir(
    dosya_istemcisi, monkeypatch
):
    class CasusCozucu:
        secenekler = None

        def coz(self, soru, **secenekler):
            self.secenekler = secenekler.get("secenekler")
            return Cozum(soru=soru, adimlar=["Denetlendi"], cevap="B", guven=0.9)

    casus = CasusCozucu()
    monkeypatch.setattr(dosya_istemcisi.app.state.durum, "cozucu", lambda **_: casus)
    yanit = dosya_istemcisi.post(
        "/coz",
        data={"soru": "", "secenekler": "A) Solunum\nB) Protein sentezi"},
        files={"dosyalar": ("soru.txt", b"Ribozomun gorevi?", "text/plain")},
    )
    assert yanit.status_code == 200
    assert casus.secenekler == {"A": "Solunum", "B": "Protein sentezi"}
