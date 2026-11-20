"""İtiraz ve yeniden değerlendirme kaydı."""
from __future__ import annotations

import pytest

from sinav_okur.modeller import CevapAnahtari, PuanSonucu, Sinav, Soru, SoruTipi, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _sinav() -> Sinav:
    return Sinav(
        kimlik="ITR-1",
        baslik="İtiraz testi",
        sorular=[
            Soru(
                no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="Soru", puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
            )
        ],
    )


def _kagit(depo, sinav, puan=4.0):
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
        ogrenci_ad="Ali",
    )


def test_itiraz_acilir_ve_acik_durumda(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    itiraz_id = depo.itiraz_ac(kagit_id, kutu["id"], "Cevabım doğruydu")
    kayit = depo.itirazlar(sinav.kimlik)[0]
    assert kayit["id"] == itiraz_id
    assert kayit["durum"] == "acik"
    assert kayit["onceki_puan"] == 4.0
    assert kayit["soru_no"] == 1
    # Puan değişmemeli
    assert depo.kutu(kutu["id"])["son_puan"] == 4.0


def test_bos_gerekce_reddedilir(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    with pytest.raises(ValueError):
        depo.itiraz_ac(kagit_id, None, "   ")


def test_kabul_puani_gunceller_ve_duzeltme_ogrenimi_dogar(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    itiraz_id = depo.itiraz_ac(kagit_id, kutu["id"], "Tam puan almalıydım")
    depo.itiraz_karara_bagla(itiraz_id, kabul=True, yeni_puan=10.0, karar_notu="Haklı")
    assert depo.kutu(kutu["id"])["son_puan"] == 10.0
    kayit = depo.itirazlar(sinav.kimlik)[0]
    assert kayit["durum"] == "kabul"
    assert kayit["yeni_puan"] == 10.0
    assert any(
        o["ogretmen_puani"] == 10.0 for o in depo.duzeltme_ornekleri(sinav.kimlik)
    )


def test_ret_puani_degistirmez(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    itiraz_id = depo.itiraz_ac(kagit_id, kutu["id"], "İtiraz")
    depo.itiraz_karara_bagla(itiraz_id, kabul=False, karar_notu="Anahtar doğru")
    assert depo.kutu(kutu["id"])["son_puan"] == 4.0
    assert depo.itirazlar(sinav.kimlik)[0]["durum"] == "ret"


def test_durum_filtresi(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    acik = depo.itiraz_ac(kagit_id, kutu["id"], "Bir")
    kapali = depo.itiraz_ac(kagit_id, kutu["id"], "İki")
    depo.itiraz_karara_bagla(kapali, kabul=False)
    assert len(depo.itirazlar(sinav.kimlik, durum="acik")) == 1
    assert depo.itirazlar(sinav.kimlik, durum="acik")[0]["id"] == acik


def test_analiz_soru_bazinda_itiraz_sayar(depo):
    from sinav_okur.analiz import sinav_analizi

    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    depo.itiraz_ac(kagit_id, kutu["id"], "İtiraz")
    analiz = sinav_analizi(depo, sinav)
    assert analiz["sorular"][0]["itiraz"] == 1


def test_bilinmeyen_itiraz_karari_hata_verir(depo):
    with pytest.raises(KeyError):
        depo.itiraz_karara_bagla(9999, kabul=True, yeni_puan=5.0)


pytest.importorskip("fastapi")


def test_webapp_itiraz_akisi(tmp_path):
    from fastapi.testclient import TestClient

    from sinav_okur.depo import Depo
    from sinav_okur.webapp import uygulama_kur

    db = Depo(tmp_path / "t.db")
    sinav = _sinav()
    db.sinav_kaydet(sinav)
    kagit_id = _kagit(db, sinav)
    kutu = db.kutular(kagit_id)[0]
    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))

    r = c.post(
        f"/kagit/{kagit_id}/itiraz",
        data={"kutu_id": str(kutu["id"]), "gerekce": "Cevabım doğru"},
        follow_redirects=False,
    )
    assert r.status_code == 303
    liste = c.get(f"/sinav/{sinav.kimlik}/itirazlar")
    assert liste.status_code == 200
    assert "Cevabım doğru" in liste.text

    itiraz_id = db.itirazlar(sinav.kimlik)[0]["id"]
    c.post(
        f"/itiraz/{itiraz_id}/karar",
        data={
            "karar": "kabul",
            "yeni_puan": "9",
            "karar_notu": "Haklı",
            "kimlik": sinav.kimlik,
        },
        follow_redirects=False,
    )
    assert db.kutu(kutu["id"])["son_puan"] == 9.0


# --- İnceleme regresyonları ----------------------------------------------


def test_baska_kagida_ait_kutuya_itiraz_reddedilir(depo):
    a, b = _sinav(), _sinav()
    b.kimlik = "ITR-2"
    depo.sinav_kaydet(a)
    depo.sinav_kaydet(b)
    kagit_a = _kagit(depo, a)
    kagit_b = _kagit(depo, b)
    kutu_b = depo.kutular(kagit_b)[0]
    with pytest.raises(ValueError):
        depo.itiraz_ac(kagit_a, kutu_b["id"], "çapraz itiraz")
    assert depo.kutu(kutu_b["id"])["son_puan"] == 4.0


def test_sinir_disi_puan_reddedilir(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    itiraz_id = depo.itiraz_ac(kagit_id, kutu["id"], "İtiraz")
    with pytest.raises(ValueError):
        depo.itiraz_karara_bagla(itiraz_id, kabul=True, yeni_puan=999.0)
    assert depo.kutu(kutu["id"])["son_puan"] == 4.0


def test_kapanmis_itiraz_tekrar_karara_baglanamaz(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    kagit_id = _kagit(depo, sinav)
    kutu = depo.kutular(kagit_id)[0]
    itiraz_id = depo.itiraz_ac(kagit_id, kutu["id"], "İtiraz")
    depo.itiraz_karara_bagla(itiraz_id, kabul=True, yeni_puan=8.0)
    with pytest.raises(ValueError):
        depo.itiraz_karara_bagla(itiraz_id, kabul=True, yeni_puan=10.0)
    assert depo.kutu(kutu["id"])["son_puan"] == 8.0
