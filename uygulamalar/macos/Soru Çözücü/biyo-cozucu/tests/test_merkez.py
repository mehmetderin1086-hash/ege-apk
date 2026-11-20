"""Merkez hub'ı: servis yoklaması, başlatma tekilleştirmesi ve guard'lar."""

from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

pytest.importorskip("fastapi")

from fastapi.testclient import TestClient

from biyo_cozucu.webapp import merkez as merkez_modulu
from biyo_cozucu.webapp import uygulama_kur


@pytest.fixture
def uygulama(tmp_path):
    app = uygulama_kur(tmp_path, motor_turu="yok", gommesiz=True)
    try:
        yield app
    finally:
        app.state.kes_ve_coz_servisi.kapat()


def _sahte_servis(govde: dict, kod: int = 200):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            veri = json.dumps(govde).encode("utf-8")
            self.send_response(kod)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(veri)))
            self.end_headers()
            self.wfile.write(veri)

        def log_message(self, *a):
            pass

    sunucu = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=sunucu.serve_forever, daemon=True).start()
    return sunucu


def test_imza_yoklamasi_yabanci_servisi_calisiyor_saymaz():
    sunucu = _sahte_servis({"app": "baska-program", "status": "ready"})
    try:
        tanim = merkez_modulu.DisServis(
            "soru-kesici", "Soru Kesici", "", "✂",
            (sunucu.server_address[1],), "soru-kesici",
        )
        assert merkez_modulu._senkron_calisiyor_mu(tanim) is False
    finally:
        sunucu.shutdown()
        sunucu.server_close()


def test_imza_yoklamasi_dogru_servisi_bulur():
    sunucu = _sahte_servis({"app": "soru-kesici", "status": "ready", "version": "v3.4"})
    try:
        tanim = merkez_modulu.DisServis(
            "soru-kesici", "Soru Kesici", "", "✂",
            (sunucu.server_address[1],), "soru-kesici",
        )
        assert merkez_modulu._senkron_calisiyor_mu(tanim) is True
    finally:
        sunucu.shutdown()
        sunucu.server_close()


def test_yoklama_dolu_ama_yabanci_portu_cakisma_der(uygulama):
    import asyncio

    sunucu = _sahte_servis({"app": "yabanci"})
    try:
        tanim = merkez_modulu.DisServis(
            "soru-kesici", "Soru Kesici", "", "✂",
            (sunucu.server_address[1],), "soru-kesici",
        )
        sonuc = asyncio.run(merkez_modulu._servisi_yokla(tanim))
        assert sonuc.durum == "cakisma"
        assert str(sunucu.server_address[1]) in sonuc.ayrinti
    finally:
        sunucu.shutdown()
        sunucu.server_close()


def test_bioprof_imzasi_status_ve_surum_ister():
    assert merkez_modulu._imza_uyar_mi("bioprof", {"status": "ok", "version": "1"})[0]
    assert not merkez_modulu._imza_uyar_mi("bioprof", {"status": "ok"})[0]
    assert not merkez_modulu._imza_uyar_mi("bioprof", {"app": "biyo-cozucu"})[0]


def test_merkez_sayfasi_servis_kartlarini_gosterir(uygulama):
    with TestClient(uygulama) as istemci:
        yanit = istemci.get("/merkez")
    assert yanit.status_code == 200
    for beklenen in ("Soru Kesici", "BioProf", "SesLab", "Kes ve çöz"):
        assert beklenen in yanit.text


def test_kok_merkeze_yonlendirir(uygulama):
    with TestClient(
        uygulama, follow_redirects=False, client=("127.0.0.1", 50123)
    ) as istemci:
        yanit = istemci.get("/")
    assert yanit.status_code == 303
    assert yanit.headers["location"] == "/merkez"


def test_bilinmeyen_servis_reddedilir(uygulama):
    with TestClient(
        uygulama, follow_redirects=False, client=("127.0.0.1", 50123)
    ) as istemci:
        yanit = istemci.post("/merkez/baslat/olmayan")
    assert yanit.status_code == 404


def test_yabanci_origin_reddedilir(uygulama):
    with TestClient(
        uygulama, follow_redirects=False, client=("127.0.0.1", 50123)
    ) as istemci:
        yanit = istemci.post(
            "/merkez/baslat/soru-kesici",
            headers={"Origin": "https://kotu-site.example"},
        )
    assert yanit.status_code == 403


def test_yardimci_servis_buradan_baslatilamaz(uygulama):
    with TestClient(
        uygulama, follow_redirects=False, client=("127.0.0.1", 50123)
    ) as istemci:
        yanit = istemci.post("/merkez/baslat/seslab")
    assert yanit.status_code == 400


def test_zaten_calisan_servis_yeniden_baslatilmaz(uygulama, monkeypatch):
    monkeypatch.setattr(merkez_modulu, "_senkron_calisiyor_mu", lambda s: True)

    def _patlat(*a, **k):  # pragma: no cover - çağrılmamalı
        raise AssertionError("Çalışan servis için komut kurulmamalı.")

    monkeypatch.setattr(merkez_modulu, "_baslatma_komutu", _patlat)
    with TestClient(
        uygulama, follow_redirects=False, client=("127.0.0.1", 50123)
    ) as istemci:
        yanit = istemci.post("/merkez/baslat/soru-kesici")
    assert yanit.status_code == 303
    assert "zaten" in yanit.headers["location"]


def test_kilit_altinda_ikinci_baslatma_engellenir(uygulama, monkeypatch, tmp_path):
    import fcntl

    monkeypatch.setattr(merkez_modulu, "LOG_DIZINI", tmp_path)
    monkeypatch.setattr(merkez_modulu, "_senkron_calisiyor_mu", lambda s: False)
    kilit = tmp_path / "baslat-soru-kesici.lock"
    tutamac = kilit.open("a+")
    fcntl.flock(tutamac, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        mesaj = merkez_modulu._servisi_baslat("soru-kesici")
    finally:
        fcntl.flock(tutamac, fcntl.LOCK_UN)
        tutamac.close()
    assert "başlatılıyor" in mesaj
