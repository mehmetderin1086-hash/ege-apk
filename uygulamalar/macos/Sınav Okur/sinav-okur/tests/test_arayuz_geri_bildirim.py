"""Arayüz turu Faz 1: esneklik profili geri okuma ve POST sonrası onay mesajları."""
from __future__ import annotations

import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from sinav_okur.webapp import uygulama_kur


@pytest.fixture()
def ortam(tmp_path, ornek_sinav):
    from sinav_okur.depo import Depo

    db = tmp_path / "s.db"
    app = uygulama_kur(str(db), str(tmp_path / "kirp"), str(tmp_path / "veri"))
    depo = Depo(db)
    depo.sinav_kaydet(ornek_sinav)
    with TestClient(app) as istemci:
        yield istemci, depo, ornek_sinav


def test_esneklik_profili_kaydedilir_ve_geri_okunur(ortam) -> None:
    istemci, depo, sinav = ortam
    yanit = istemci.post(
        f"/sinav/{sinav.kimlik}/esneklik",
        data={"profil": "esnek"},
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    assert "esneklik=esnek" in yanit.headers["location"]
    sayfa = istemci.get(f"/sinav/{sinav.kimlik}?esneklik=esnek").text
    assert 'value="esnek" selected' in sayfa  # seçim artık sabit "dengeli" değil
    assert "esnek" in sayfa and "kaydedildi" in sayfa  # onay bandosu


def test_kimlik_kaydi_onay_mesaji(ortam) -> None:
    istemci, depo, sinav = ortam
    from sinav_okur.modeller import PuanSonucu, TanimaSonucu
    from sinav_okur.sonuclar import KagitSonucu, KutuSonucu

    kagit_id = depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=sinav.sorular[0].no,
                    tanima=TanimaSonucu(metin="cevap", guven=0.9),
                    puan=PuanSonucu(
                        puan=1, max_puan=sinav.sorular[0].puan, guven=0.9
                    ),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
    )
    yanit = istemci.post(
        f"/kagit/{kagit_id}/kimlik",
        data={"ogrenci_ad": "Ece", "ogrenci_soyad": "Kara", "ogrenci_no": "122"},
        follow_redirects=False,
    )
    assert "kimlik_kaydedildi=1" in yanit.headers["location"]
    sayfa = istemci.get(f"/kagit/{kagit_id}?kimlik_kaydedildi=1").text
    assert "Öğrenci kimliği kaydedildi" in sayfa


def test_statik_arac_js_sunulur(ortam) -> None:
    istemci, _, _ = ortam
    yanit = istemci.get("/statik/arac.js")
    assert yanit.status_code == 200
    assert "yaziyorMu" in yanit.text
