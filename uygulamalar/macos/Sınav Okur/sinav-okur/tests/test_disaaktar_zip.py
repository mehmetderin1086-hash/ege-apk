"""Flywheel zip dökümü: sayı tutarlılığı ve eksik kırpıntı raporu."""
from __future__ import annotations

import io
import json
import zipfile

import pytest

fastapi = pytest.importorskip("fastapi")
from fastapi.testclient import TestClient

from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.webapp import uygulama_kur


def _duzeltilmis_kagit(depo, sinav, kirp_yolu, metin="mitokondri") -> int:
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=sinav.sorular[0].no,
                    tanima=TanimaSonucu(metin="rnitokondn", guven=0.4),
                    puan=PuanSonucu(puan=0, max_puan=sinav.sorular[0].puan, guven=0.4),
                    kirp_yolu=str(kirp_yolu),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
        yazar_grubu="yazar-01",
        egitim_izni=True,
    )
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(kutu["id"], duzeltilmis_metin=metin)
    return kagit_id


def test_disaaktar_zip_icerigi(tmp_path, depo_yolu_fabrikasi=None) -> None:
    from sinav_okur.depo import Depo

    db = tmp_path / "s.db"
    app = uygulama_kur(str(db), str(tmp_path / "kirp"), str(tmp_path / "veri"))
    depo = Depo(db)
    from sinav_okur.modeller import (
        CevapAnahtari, RubrikKalemi, Sinav, Soru, SoruTipi,
    )

    sinav = Sinav(
        kimlik="TEST-1",
        baslik="Test",
        ders="Biyoloji",
        sorular=[
            Soru(
                no=1, tip=SoruTipi.KISA_CEVAP, metin="Organel?", puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi(metin="mitokondri", puan=10)],
                ),
            )
        ],
    )
    depo.sinav_kaydet(sinav)
    var_olan = tmp_path / "kirp" / "soru_1.png"
    var_olan.parent.mkdir(parents=True, exist_ok=True)
    var_olan.write_bytes(b"png-degil-ama-dosya")
    _duzeltilmis_kagit(depo, sinav, var_olan)
    # Kırpıntısı sonradan silinmiş ikinci düzeltme: atlanmalı ve raporlanmalı.
    silinmis = tmp_path / "kirp" / "soru_2.png"
    silinmis.write_bytes(b"x")
    _duzeltilmis_kagit(depo, sinav, silinmis, metin="lizozom")
    silinmis.unlink()

    with TestClient(app) as istemci:
        yanit = istemci.get("/disaaktar.zip")
    assert yanit.status_code == 200
    with zipfile.ZipFile(io.BytesIO(yanit.content)) as paket:
        adlar = set(paket.namelist())
        assert "labels.jsonl" in adlar and "manifest.json" in adlar
        satirlar = [
            json.loads(s)
            for s in paket.read("labels.jsonl").decode("utf-8").splitlines()
        ]
        manifest = json.loads(paket.read("manifest.json"))
    # Var olan kırpıntı pakete girdi; JSONL satır sayısı paketteki görsellerle eşit.
    assert len(satirlar) == 1
    assert satirlar[0]["text"] == "mitokondri"
    assert satirlar[0]["image"].startswith("kirpintilar/")
    assert satirlar[0]["image"] in adlar
    assert manifest["ornek"] == 1
    # Silinen kırpıntı sessizce kaybolmadı: manifestte raporlandı.
    assert len(manifest["atlanan_kirpinti"]) == 1
