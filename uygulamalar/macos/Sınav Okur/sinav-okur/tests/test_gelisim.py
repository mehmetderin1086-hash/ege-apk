"""Kalıcı öğrenci kimliği ve sınavlar arası gelişim."""
from __future__ import annotations

import sqlite3

import pytest

from sinav_okur.depo import Depo
from sinav_okur.gelisim import ogrenci_serisi, sinif_gelisimi
from sinav_okur.modeller import CevapAnahtari, PuanSonucu, Sinav, Soru, SoruTipi, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _sinav(kimlik: str) -> Sinav:
    return Sinav(
        kimlik=kimlik,
        baslik=f"Yazılı {kimlik}",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Soru",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
            )
        ],
    )


def _kagit(depo, sinav, puan, ad="Ali", soyad="Yılmaz", no="101"):
    return depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=1,
                    tanima=TanimaSonucu(metin="mitokondri", guven=0.9),
                    puan=PuanSonucu(puan=puan, max_puan=10.0, guven=0.9),
                )
            ],
        ),
        ogrenci_ad=ad,
        ogrenci_soyad=soyad,
        ogrenci_no=no,
        sinif="9A",
    )


def test_yeni_depoda_ogrenci_tablosu_olusur(tmp_path):
    depo = Depo(tmp_path / "yeni.db")
    with sqlite3.connect(depo.yol) as con:
        tablolar = {
            r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
    assert "ogrenci" in tablolar
    sutunlar = {r[1] for r in sqlite3.connect(depo.yol).execute("PRAGMA table_info(kagit)")}
    assert "ogrenci_kimlik" in sutunlar


def test_eski_veritabaninda_alter_veri_kaybetmez(tmp_path):
    """Migrasyon deseninin doğrulandığı ilk test: eski DB'de veri korunmalı."""
    yol = tmp_path / "eski.db"
    depo = Depo(yol)
    sinav = _sinav("ESKI-1")
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav, 8.0)
    del depo

    # Yeni sütunu silip "eski sürüm" veritabanı taklit edilemez (SQLite DROP
    # COLUMN sınırlı), bunun yerine aynı dosya yeniden açılır: ALTER'ların
    # ikinci kez çalışması veri kaybettirmemeli.
    yeniden = Depo(yol)
    assert yeniden.kagit(kagit_id)["ogrenci_ad"] == "Ali"
    toplam, maxp = yeniden.kagit_toplam(kagit_id)
    assert toplam == 8.0 and maxp == 10.0
    guncel = yeniden.sinav_yukle("ESKI-1")
    assert guncel.sorular[0].anahtar.dogru_cevaplar == ["mitokondri"]


def test_ayni_numara_iki_sinavda_tek_ogrenciye_baglanir(tmp_path):
    depo = Depo(tmp_path / "t.db")
    for kimlik, puan in (("S-1", 6.0), ("S-2", 9.0)):
        sinav = _sinav(kimlik)
        depo.sinav_kaydet(sinav)
        _kagit(depo, sinav, puan)
    sonuc = depo.ogrencileri_esle()
    assert sonuc["baglanan"] == 2
    assert len(depo.ogrenciler()) == 1
    ogrenci = depo.ogrenciler()[0]
    assert len(depo.ogrenci_kagitlari(ogrenci["id"])) == 2


def test_kimliksiz_kagit_baglanmaz(tmp_path):
    depo = Depo(tmp_path / "t.db")
    sinav = _sinav("S-1")
    depo.sinav_kaydet(sinav)
    _kagit(depo, sinav, 5.0, ad="", soyad="", no="")
    sonuc = depo.ogrencileri_esle()
    assert sonuc["baglanan"] == 0
    assert sonuc["atlanan"] == 1
    assert depo.ogrenciler() == []


def test_gelisim_serisi_kronolojik_ve_egilimli(tmp_path):
    depo = Depo(tmp_path / "t.db")
    for kimlik, puan in (("S-1", 5.0), ("S-2", 9.0)):
        sinav = _sinav(kimlik)
        depo.sinav_kaydet(sinav)
        _kagit(depo, sinav, puan)
    depo.ogrencileri_esle()
    ogrenci = depo.ogrenciler()[0]
    seri = ogrenci_serisi(depo, ogrenci["id"])
    assert [n["yuzde"] for n in seri["noktalar"]] == [50.0, 90.0]
    assert seri["egilim"] == 40.0
    assert seri["ortalama"] == 70.0


def test_tek_sinavli_ogrenci_egilim_uretmez(tmp_path):
    depo = Depo(tmp_path / "t.db")
    sinav = _sinav("S-1")
    depo.sinav_kaydet(sinav)
    _kagit(depo, sinav, 7.0)
    depo.ogrencileri_esle()
    ogrenci = depo.ogrenciler()[0]
    assert ogrenci_serisi(depo, ogrenci["id"])["egilim"] is None


def test_sinif_gelisimi_matrisi(tmp_path):
    depo = Depo(tmp_path / "t.db")
    for kimlik in ("S-1", "S-2"):
        sinav = _sinav(kimlik)
        depo.sinav_kaydet(sinav)
        _kagit(depo, sinav, 8.0, ad="Ali", no="101")
        _kagit(depo, sinav, 4.0, ad="Ayşe", soyad="Demir", no="102")
    depo.ogrencileri_esle()
    veri = sinif_gelisimi(depo)
    assert len(veri["satirlar"]) == 2
    assert veri["sinavlar"] == ["S-1", "S-2"]
    assert veri["baglanmamis"] == 0


def test_bilinmeyen_ogrenci_bos_seri(tmp_path):
    depo = Depo(tmp_path / "t.db")
    assert ogrenci_serisi(depo, 999) == {}


# --- Webapp ---------------------------------------------------------------

pytest.importorskip("fastapi")


def test_gelisim_sayfasi_ve_ogrenci_detayi(tmp_path):
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    depo = Depo(tmp_path / "t.db")
    for kimlik, puan in (("S-1", 5.0), ("S-2", 9.0)):
        sinav = _sinav(kimlik)
        depo.sinav_kaydet(sinav)
        _kagit(depo, sinav, puan)
    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))

    bos = c.get("/gelisim")
    assert bos.status_code == 200
    assert "Henüz gelişim verisi yok" in bos.text

    c.post("/gelisim/esle", data={"sinav_kimlik": ""}, follow_redirects=False)
    dolu = c.get("/gelisim").text
    assert "Ali" in dolu

    ogrenci = depo.ogrenciler()[0]
    detay = c.get(f"/ogrenci/{ogrenci['id']}")
    assert detay.status_code == 200
    assert "Sınav sınav başarı" in detay.text
    assert c.get("/ogrenci/9999").status_code == 404


def test_saklama_suresi_dolunca_ogrenci_kaydi_da_anonimlesir(tmp_path):
    """kagit.ogrenci_kimlik kalırsa tek JOIN ile kimlik geri gelir."""
    import sqlite3 as _sq

    depo = Depo(tmp_path / "t.db")
    sinav = _sinav("S-1")
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav, 8.0)
    depo.ogrencileri_esle()
    assert depo.kagit(kagit_id)["ogrenci_kimlik"] is not None

    with _sq.connect(depo.yol) as con:
        con.execute(
            "UPDATE kagit SET saklama_son_tarihi=datetime('now','-1 day') WHERE id=?",
            (kagit_id,),
        )
    depo.suresi_dolanlari_anonimlestir()

    kagit = depo.kagit(kagit_id)
    assert kagit["ogrenci_ad"] is None
    assert kagit["ogrenci_kimlik"] is None
    assert depo.ogrenciler() == []  # yetim öğrenci kaydı da silinmeli
