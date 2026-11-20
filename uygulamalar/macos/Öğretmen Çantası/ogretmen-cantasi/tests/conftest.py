"""Dosyalar arası paylaşılan test fixture'ları.

`baglanti`/`yil` servis testlerinin, `istemci` web testlerinin ortak zeminidir;
dört dosyada kopya dururken `depo.baglan` ya da kurulum sözleşmesi değişince
hepsi ayrı ayrı düzeltilmek zorunda kalıyordu.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from ogretmen_cantasi import depo, servis
from ogretmen_cantasi import takvim as tk
from ogretmen_cantasi.web import sunucu as web_sunucu


@pytest.fixture
def baglanti():
    b = depo.baglan(":memory:")
    yield b
    b.close()


@pytest.fixture
def yil(baglanti):
    ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
    return servis.ogretim_yili_kur(baglanti, ad, d1, d2)


@pytest.fixture
def istemci(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path))
    # Modül seviyesinde okunan yol yerine her çağrıda ortamdan okunuyor;
    # yine de bağlantıyı testin geçici dizinine sabitliyoruz.
    monkeypatch.setattr(web_sunucu, "_baglanti", lambda: depo.baglan(tmp_path / "veri.db"))
    uygulama = web_sunucu.uygulama_kur()
    with TestClient(uygulama, base_url="http://127.0.0.1") as istemci:
        istemci.headers["X-CSRF-Token"] = uygulama.state.csrf_token
        yield istemci
