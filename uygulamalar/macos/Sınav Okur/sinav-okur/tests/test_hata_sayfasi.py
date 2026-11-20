"""HTTP hata işleyici: tarayıcıya şablonlu sayfa, API/programatik istemciye JSON."""
from __future__ import annotations

import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from sinav_okur.webapp import uygulama_kur


@pytest.fixture()
def istemci(tmp_path):
    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    with TestClient(app) as c:
        yield c


def test_tarayici_istegi_sablonlu_hata_alir(istemci) -> None:
    yanit = istemci.get(
        "/kagit/999999", headers={"Accept": "text/html,application/xhtml+xml"}
    )
    assert yanit.status_code == 404
    assert "text/html" in yanit.headers["content-type"]
    assert "Sayfa bulunamadı" in yanit.text
    assert 'href="/"' in yanit.text  # ana sayfaya dönüş bağlantısı


def test_programatik_istek_json_alir(istemci) -> None:
    yanit = istemci.get("/kagit/999999")  # Accept: */* → JSON korunur
    assert yanit.status_code == 404
    assert yanit.json()["detail"]


def test_api_yolu_html_accept_ile_bile_json_kalir(istemci) -> None:
    yanit = istemci.get("/api/v1/health", headers={"Accept": "text/html"})
    assert yanit.status_code == 401
    assert yanit.json()["detail"]


def test_bilinmeyen_rota_da_sablonlu(istemci) -> None:
    yanit = istemci.get("/boyle-bir-sayfa-yok", headers={"Accept": "text/html"})
    assert yanit.status_code == 404
    assert "Sayfa bulunamadı" in yanit.text
