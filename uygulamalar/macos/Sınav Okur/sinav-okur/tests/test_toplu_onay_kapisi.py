"""Toplu onay yalnız düşük riskli bekleyenleri mühürlemeli.

Ölçülen zincir: "miyoz" gibi kararsız bir yazım ya da nihai sonucu yanlış
bir sayısal cevap, "Bekleyenleri toplu onayla" düğmesiyle tek tıkta
kalıcılaşıyordu — öğretmen yanlış puanı hiç görmeden.
"""

from __future__ import annotations

import json

import pytest

pytest.importorskip("fastapi")

from fastapi.testclient import TestClient

from sinav_okur.depo import Depo
from sinav_okur.modeller import (
    CevapAnahtari,
    PuanSonucu,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.webapp import uygulama_kur
from sinav_okur.webapp.kagit import _toplu_onaya_uygun

KIMLIK = "TOPLU-ONAY"


def _sinav() -> Sinav:
    return Sinav(
        kimlik=KIMLIK,
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Kromozom sayısını koruyan bölünme ..... dur.",
                puan=10.0,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitoz"]),
            ),
            Soru(
                no=2,
                tip=SoruTipi.KISA_CEVAP,
                metin="Mitokondrinin görevi nedir?",
                puan=10.0,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("Mitokondri ATP üretir", 10.0)]
                ),
            ),
        ],
    )


class _SahteKutu(dict):
    """depo.kutular() satırlarının sözlük benzeri erişimini taklit eder."""


def _kutu(**alanlar) -> _SahteKutu:
    taban = {
        "duzeltilmis_metin": None,
        "taninan_metin": "mitoz",
        "risk": 0.0,
        "puanlama_guveni": 0.9,
        "kararlar_json": "[]",
    }
    taban.update(alanlar)
    return _SahteKutu(taban)


def test_bos_metin_atlanir():
    uygun, neden = _toplu_onaya_uygun(_kutu(taninan_metin=""))

    assert uygun is False
    assert "boş" in neden


def test_kararsiz_terim_karari_atlanir():
    kutu = _kutu(
        kararlar_json=json.dumps(
            [{"tur": "bosluk", "karar": "kararsiz_terim", "rakip": "mayoz"}]
        )
    )

    uygun, neden = _toplu_onaya_uygun(kutu)

    assert uygun is False
    assert "kararsiz_terim" in neden


def test_sinirda_esleme_atlanir():
    """70-88 bandındaki "geçici tam puan" toplu onayla mühürlenemez."""
    kutu = _kutu(
        kararlar_json=json.dumps(
            [{"tur": "bosluk", "karar": "sinirda_esleme", "skor": 74}]
        )
    )

    assert _toplu_onaya_uygun(kutu)[0] is False


def test_ara_islemdeki_sayisal_karar_atlanir():
    kutu = _kutu(
        kararlar_json=json.dumps(
            [{"tur": "sayisal_sonuc", "dogru": False, "ara_islemde": True}]
        )
    )

    uygun, neden = _toplu_onaya_uygun(kutu)

    assert uygun is False
    assert "ara işlemde" in neden


def test_kismi_rubrik_karari_atlanir():
    kutu = _kutu(
        kararlar_json=json.dumps(
            [{"tur": "rubrik", "karar": "kismi", "puan": 4.0}]
        )
    )

    assert _toplu_onaya_uygun(kutu)[0] is False


def test_yuksek_riskli_kutu_atlanir():
    assert _toplu_onaya_uygun(_kutu(risk=0.7))[0] is False


def test_dusuk_puanlama_guveni_atlanir():
    assert _toplu_onaya_uygun(_kutu(puanlama_guveni=0.4))[0] is False


def test_temiz_kutu_onaylanir():
    """Düzeltme, güvenli kutuların toplu onayını engellemez."""
    kutu = _kutu(
        kararlar_json=json.dumps(
            [{"tur": "rubrik", "karar": "tam", "puan": 10.0}]
        )
    )

    assert _toplu_onaya_uygun(kutu) == (True, "")


def test_uctan_uca_kararsiz_cevap_muhurlenmez(tmp_path):
    """Gerçek rota üzerinden: kararsız yazım toplu onayla kapanmamalı."""
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    kutular = [
        KutuSonucu(
            soru_no=1,
            tanima=TanimaSonucu(metin="miyoz", guven=0.9),
            puan=PuanSonucu(
                0.0,
                10.0,
                0.4,
                ["Kararsız eşleşme"],
                incele=True,
                risk=0.6,
                kararlar=[
                    {
                        "tur": "bosluk",
                        "karar": "kararsiz_terim",
                        "eslesen": "mitoz",
                        "rakip": "mayoz",
                    }
                ],
                puanlama_guveni=0.4,
            ),
        ),
        KutuSonucu(
            soru_no=2,
            tanima=TanimaSonucu(metin="Mitokondri ATP üretir", guven=0.95),
            puan=PuanSonucu(
                10.0,
                10.0,
                0.95,
                ["✓"],
                incele=True,
                kararlar=[{"tur": "rubrik", "karar": "tam", "puan": 10.0}],
                puanlama_guveni=0.95,
            ),
        ),
    ]
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(sinav_kimlik=KIMLIK, islenen_sayfalar=[1], kutular=kutular),
        ogrenci_ad="Ayşe",
    )
    istemci = TestClient(
        uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp"))
    )

    yanit = istemci.post(
        f"/kagit/{kagit_id}/kutulari-onayla", follow_redirects=False
    )

    assert yanit.status_code == 303
    assert "toplu_onay=1" in yanit.headers["location"]
    assert "atlanan=1" in yanit.headers["location"]
    durumlar = {k["soru_no"]: k["incele"] for k in depo.kutular(kagit_id)}
    assert durumlar[1] == 1, "kararsız cevap hâlâ incelemede olmalı"
    assert durumlar[2] == 0, "temiz cevap onaylanmalı"
