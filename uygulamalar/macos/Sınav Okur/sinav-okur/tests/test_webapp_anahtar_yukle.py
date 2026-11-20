"""Cevap anahtarı yükleme akışı: dosya/belge → önizleme → uygula."""

from __future__ import annotations

import json

import pytest

pytest.importorskip("cv2")
pytest.importorskip("fastapi")

import cv2
import numpy as np
from fastapi.testclient import TestClient

from sinav_okur.depo import Depo
from sinav_okur.htr import YapayTaniyici
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

KIMLIK = "ANAHTAR-YUKLE"


def _sinav() -> Sinav:
    return Sinav(
        kimlik=KIMLIK,
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Mitokondrinin görevi nedir?",
                puan=10,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("eski ölçüt", 10)]),
            ),
            Soru(
                no=2,
                tip=SoruTipi.KISA_CEVAP,
                metin="Ribozomun görevi nedir?",
                puan=5,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("eski", 5)]),
            ),
        ],
    )


def _depo_kur(tmp_path) -> tuple[Depo, int]:
    """Bir kâğıdı ve iki cevabı olan sınav deposu kurar."""
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    metinler = {1: "Mitokondri ATP üretir", 2: "Protein sentezi yapar"}
    kutular = [
        KutuSonucu(
            soru_no=no,
            tanima=TanimaSonucu(metin=metin, guven=0.9, uzlasma_guveni=0.9),
            puan=PuanSonucu(puan=0.0, max_puan=10.0 if no == 1 else 5.0, guven=0.9),
            kirp_yolu=None,
        )
        for no, metin in metinler.items()
    ]
    kagit_id = depo.kagit_kaydet(
        KagitSonucu(sinav_kimlik=KIMLIK, islenen_sayfalar=[1], kutular=kutular),
        ogrenci_ad="Ayşe",
    )
    return depo, kagit_id


@pytest.fixture
def ortam(tmp_path):
    depo, kagit_id = _depo_kur(tmp_path)
    app = uygulama_kur(
        str(tmp_path / "t.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    return depo, app, kagit_id


def _token(html: str) -> str:
    return html.split('name="token" value="')[1].split('"')[0]


def test_yukleme_formu_acilir(ortam):
    _depo, app, _kagit = ortam

    yanit = TestClient(app).get(f"/sinav/{KIMLIK}/anahtar/yukle")

    assert yanit.status_code == 200
    assert "Anahtar dosyası" in yanit.text


def test_csv_yukle_onizle_uygula_zinciri(ortam):
    depo, app, kagit_id = ortam
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.csv",
                "soru_no,rubrik\n1,Mitokondri ATP üretir\n2,Protein sentezi yapar\n",
                "text/csv",
            )
        },
    )

    assert onizleme.status_code == 200
    assert "Ayrıştırılan anahtar" in onizleme.text
    # Önizleme depoya yazmaz.
    assert depo.sinav_yukle(KIMLIK).soru(1).anahtar.rubrik[0].metin == "eski ölçüt"

    uygula = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": _token(onizleme.text)},
        follow_redirects=False,
    )

    assert uygula.status_code == 303
    guncel = depo.sinav_yukle(KIMLIK)
    assert guncel.soru(1).anahtar.rubrik[0].metin == "Mitokondri ATP üretir"
    assert guncel.soru(1).anahtar.onay_durumu == "onayli"
    assert guncel.soru(1).anahtar.otomatik_uretildi is False
    # Anahtar sürümü denetim tablosuna düşer (geri alınabilirlik).
    assert len(depo.denetim_kayitlari(varlik_turu="sinav")) >= 1
    kutular = {k["soru_no"]: k for k in depo.kutular(kagit_id)}
    assert kutular[1]["otomatik_puan"] == pytest.approx(10.0)


def test_hatali_dosya_uygulanamaz_ve_depoyu_degistirmez(ortam):
    depo, app, _kagit = ortam

    yanit = TestClient(app).post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.csv",
                "soru_no,rubrik\n1,Yeni ölçüt\n99,Olmayan soru\n",
                "text/csv",
            )
        },
    )

    assert yanit.status_code == 200
    assert "Anahtar uygulanamaz" in yanit.text
    assert 'name="token"' not in yanit.text
    assert depo.sinav_yukle(KIMLIK).soru(1).anahtar.rubrik[0].metin == "eski ölçüt"


def test_desteklenmeyen_uzanti_reddedilir(ortam):
    _depo, app, _kagit = ortam

    yanit = TestClient(app).post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={"anahtar_dosyasi": ("anahtar.docx", b"veri", "application/msword")},
    )

    assert yanit.status_code == 200
    assert "Desteklenmeyen dosya türü" in yanit.text


def test_elle_verilen_puan_korunur(ortam):
    depo, app, kagit_id = ortam
    kutu = next(k for k in depo.kutular(kagit_id) if k["soru_no"] == 1)
    depo.kutu_guncelle(kutu["id"], son_puan=7.5, neden="öğretmen kararı")
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.csv",
                "soru_no,rubrik\n1,Mitokondri ATP üretir\n",
                "text/csv",
            )
        },
    )
    istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": _token(onizleme.text)},
        follow_redirects=False,
    )

    kutular = {k["soru_no"]: k for k in depo.kutular(kagit_id)}
    assert kutular[1]["son_puan"] == pytest.approx(7.5)


def test_belge_akisi_taslak_anahtar_uretir(tmp_path):
    depo, _kagit = _depo_kur(tmp_path)
    ocr_metni = "1) Mitokondri ATP üretir\n2) Protein sentezi yapar"

    def sahte_uret(mesajlar, **_ayar):
        return json.dumps(
            {
                "sorular": [
                    {
                        "no": 1,
                        "cevap_satirlari": [],
                        "rubrik_satirlari": ["Mitokondri ATP üretir"],
                    }
                ]
            },
            ensure_ascii=False,
        )

    app = uygulama_kur(
        str(tmp_path / "t.db"),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
        taniyici_fabrikasi=lambda: YapayTaniyici(ocr_metni),
        yerel_uret=sahte_uret,
    )
    gorsel = tmp_path / "anahtar.png"
    cv2.imwrite(str(gorsel), np.full((80, 200, 3), 255, dtype=np.uint8))
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/belge",
        files={"anahtar_belgeleri": ("anahtar.png", gorsel.read_bytes(), "image/png")},
    )

    assert onizleme.status_code == 200, onizleme.text
    assert "Taslak" in onizleme.text
    assert "Mitokondri ATP üretir" in onizleme.text

    istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": _token(onizleme.text)},
        follow_redirects=False,
    )

    anahtar = depo.sinav_yukle(KIMLIK).soru(1).anahtar
    assert anahtar.onay_durumu == "taslak"
    assert anahtar.otomatik_uretildi is True
    assert anahtar.uretim_yontemi == "Fotoğraf/PDF · OCR + yerel model"
    # Belgede olmayan 2. sorunun anahtarı korunur.
    assert depo.sinav_yukle(KIMLIK).soru(2).anahtar.rubrik[0].metin == "eski"


def test_belgeden_uydurulan_satir_puanlamayi_kapatir(tmp_path):
    depo, _kagit = _depo_kur(tmp_path)
    ocr_metni = "1) Mitokondri ATP üretir"

    def sahte_uret(mesajlar, **_ayar):
        return json.dumps(
            {
                "sorular": [
                    {
                        "no": 1,
                        "cevap_satirlari": [],
                        "rubrik_satirlari": [
                            "Mitokondri ATP üretir",
                            "Kloroplast fotosentezle glikoz sentezler",
                        ],
                    }
                ]
            },
            ensure_ascii=False,
        )

    app = uygulama_kur(
        str(tmp_path / "t.db"),
        str(tmp_path / "kirp"),
        str(tmp_path / "veri"),
        taniyici_fabrikasi=lambda: YapayTaniyici(ocr_metni),
        yerel_uret=sahte_uret,
    )
    gorsel = tmp_path / "anahtar.png"
    cv2.imwrite(str(gorsel), np.full((80, 200, 3), 255, dtype=np.uint8))
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/belge",
        files={"anahtar_belgeleri": ("anahtar.png", gorsel.read_bytes(), "image/png")},
    )
    istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": _token(onizleme.text)},
        follow_redirects=False,
    )

    assert depo.sinav_yukle(KIMLIK).soru(1).anahtar.otomatik_puanlama is False


def test_gecersiz_token_reddedilir(ortam):
    _depo, app, _kagit = ortam

    yanit = TestClient(app).post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": "../../etc/passwd"},
        follow_redirects=False,
    )

    assert yanit.status_code == 400


def test_token_iki_kez_uygulanamaz(ortam):
    """Çift tıklama iki kez sürümleme + yeniden puanlama yapmamalı."""
    _depo, app, _kagit = ortam
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.csv",
                "soru_no,rubrik\n1,Mitokondri ATP üretir\n",
                "text/csv",
            )
        },
    )
    token = _token(onizleme.text)

    ilk = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": token},
        follow_redirects=False,
    )
    ikinci = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": token},
        follow_redirects=False,
    )

    assert ilk.status_code == 303
    assert ikinci.status_code == 404


def test_arada_degisen_anahtar_sessizce_ezilmez(ortam):
    """Önizlemeden sonra anahtar başka yerden değişirse 409 ile uyarılır."""
    depo, app, _kagit = ortam
    istemci = TestClient(app)

    onizleme = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.csv",
                "soru_no,rubrik\n1,Mitokondri ATP üretir\n",
                "text/csv",
            )
        },
    )
    token = _token(onizleme.text)

    # Başka bir sekmede 2. sorunun anahtarı düzenlendi.
    arada = depo.sinav_yukle(KIMLIK)
    arada.soru(2).anahtar = CevapAnahtari(
        rubrik=[RubrikKalemi("elle yazılan yeni ölçüt", 5)], onay_durumu="onayli"
    )
    depo.sinav_kaydet(arada)

    yanit = istemci.post(
        f"/sinav/{KIMLIK}/anahtar/yukle/uygula",
        data={"token": token},
        follow_redirects=False,
    )

    assert yanit.status_code == 409
    assert depo.sinav_yukle(KIMLIK).soru(2).anahtar.rubrik[0].metin == (
        "elle yazılan yeni ölçüt"
    )


def test_tipe_uymayan_json_500_vermez(ortam):
    """Ölçüldü: bu dosya önizlemede ValueError ile 500 sayfası üretiyordu."""
    _depo, app, _kagit = ortam

    yanit = TestClient(app).post(
        f"/sinav/{KIMLIK}/anahtar/yukle/dosya",
        files={
            "anahtar_dosyasi": (
                "anahtar.json",
                json.dumps(
                    {
                        "sorular": [
                            {"no": 1, "anahtar": {"dogru_cevaplar": ["ATP"]}}
                        ]
                    }
                ),
                "application/json",
            )
        },
    )

    assert yanit.status_code == 200
    assert "Anahtar uygulanamaz" in yanit.text
    assert 'name="token"' not in yanit.text
