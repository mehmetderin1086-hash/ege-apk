"""Cevap anahtarı kurma ve etki önizlemesi."""
from __future__ import annotations

import pytest

from sinav_okur.anahtar_duzen import (
    anahtar_etkisini_onizle,
    anahtar_satirlari,
    eslestirmeleri_coz,
    formdan_anahtar_uret,
    rubrik_kur,
)
from sinav_okur.modeller import (
    CevapAnahtari,
    PuanSonucu,
    Sinav,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def test_anahtar_satirlari_bolme():
    assert anahtar_satirlari("a\nb; c\n\n") == ["a", "b", "c"]
    assert anahtar_satirlari("") == []


def test_bosluk_tipi_dogru_cevaplara_gider():
    tip, anahtar = formdan_anahtar_uret(
        SoruTipi.BOSLUK_DOLDURMA, 10.0, ["mitokondri", "mitokondriler"]
    )
    assert tip == SoruTipi.BOSLUK_DOLDURMA
    assert anahtar.dogru_cevaplar == ["mitokondri", "mitokondriler"]
    assert anahtar.onay_durumu == "onayli"


def test_siralama_tipi_siralamaya_gider():
    _tip, anahtar = formdan_anahtar_uret(
        SoruTipi.SIRALAMA, 10.0, ["profaz", "metafaz"]
    )
    assert anahtar.siralama == ["profaz", "metafaz"]


def test_eslestirme_cift_cikarilir():
    _tip, anahtar = formdan_anahtar_uret(
        SoruTipi.ESLESTIRME, 10.0, ["A = 1", "B -> 2", "C : 3"]
    )
    assert anahtar.eslestirmeler == {"A": "1", "B": "2", "C": "3"}


def test_eslestirmede_cift_yoksa_kisa_cevaba_duser():
    tip, anahtar = formdan_anahtar_uret(
        SoruTipi.ESLESTIRME, 10.0, ["Öğrenci eşleştirmeyi cümleyle yazmış"]
    )
    assert tip == SoruTipi.KISA_CEVAP
    assert anahtar.rubrik  # rubrikle puanlanır


def test_acik_uclu_rubrige_gider_ve_puanlar_toplanir():
    _tip, anahtar = formdan_anahtar_uret(
        SoruTipi.ACIK_UCLU, 9.0, ["kavram bir", "kavram iki", "kavram üç"]
    )
    assert len(anahtar.rubrik) == 3
    assert abs(sum(k.puan for k in anahtar.rubrik) - 9.0) < 1e-9


def test_rubrik_kur_artigi_son_kaleme_verir():
    kalemler = rubrik_kur(["a", "b", "c"], 10.0)
    assert abs(sum(k.puan for k in kalemler) - 10.0) < 1e-9
    assert kalemler[-1].puan != kalemler[0].puan


def test_eslestirmeleri_coz_bozuk_satiri_atlar():
    assert eslestirmeleri_coz(["A = 1", "bozuk satır", "B = 2"]) == {
        "A": "1",
        "B": "2",
    }


def _sinav(dogru) -> Sinav:
    return Sinav(
        kimlik="ANH-1",
        baslik="Anahtar testi",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Hücrenin enerji merkezi?",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=list(dogru)),
            )
        ],
    )


def _kagit_ekle(depo, sinav, metin, puan):
    return depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=1,
                    tanima=TanimaSonucu(metin=metin, guven=0.95),
                    puan=PuanSonucu(puan=puan, max_puan=10.0, guven=0.95),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
    )


def test_onizleme_depoya_yazmaz(depo):
    eski = _sinav(["hücre zarı"])
    depo.sinav_kaydet(eski)
    kagit_id = _kagit_ekle(depo, eski, "plazma zarı", 0.0)
    onceki = [dict(k) for k in depo.kutular(kagit_id)]

    yeni = _sinav(["plazma zarı"])
    onizleme = anahtar_etkisini_onizle(depo, eski, yeni)

    assert onizleme["toplam_etkilenen"] == 1
    sonraki = [dict(k) for k in depo.kutular(kagit_id)]
    assert onceki == sonraki  # tek bir alan bile değişmemeli


def test_onizleme_delta_isaretleri_dogru(depo):
    eski = _sinav(["hücre zarı"])
    depo.sinav_kaydet(eski)
    _kagit_ekle(depo, eski, "plazma zarı", 0.0)  # yeni anahtarla yükselecek
    _kagit_ekle(depo, eski, "hücre zarı", 10.0)  # yeni anahtarla düşecek

    yeni = _sinav(["plazma zarı"])
    onizleme = anahtar_etkisini_onizle(depo, eski, yeni)
    ozet = onizleme["sorular"][0]
    assert ozet["yukselen"] == 1
    assert ozet["dusen"] == 1
    assert ozet["etkilenen_kagit"] == 2


def test_onizleme_degisiklik_yoksa_bos(depo):
    sinav = _sinav(["mitokondri"])
    depo.sinav_kaydet(sinav)
    _kagit_ekle(depo, sinav, "mitokondri", 10.0)
    onizleme = anahtar_etkisini_onizle(depo, sinav, _sinav(["mitokondri"]))
    assert onizleme["toplam_etkilenen"] == 0


# --- Webapp akışı ---------------------------------------------------------

pytest.importorskip("fastapi")


def _webapp_kurulum(tmp_path):
    from sinav_okur.depo import Depo

    db = Depo(tmp_path / "t.db")
    sinav = _sinav(["hücre zarı"])
    db.sinav_kaydet(sinav)
    _kagit_ekle(db, sinav, "plazma zarı", 0.0)
    return db, sinav


def test_anahtar_duzenleyici_render(tmp_path):
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    db, sinav = _webapp_kurulum(tmp_path)
    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))
    r = c.get(f"/sinav/{sinav.kimlik}/anahtar")
    assert r.status_code == 200
    assert "Cevap anahtarını düzenle" in r.text
    assert "hücre zarı" in r.text


def test_onizleme_rotasi_puanlari_degistirmez(tmp_path):
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    db, sinav = _webapp_kurulum(tmp_path)
    kagit_id = db.kagitlar(sinav.kimlik)[0]["id"]
    onceki = db.kutular(kagit_id)[0]["son_puan"]
    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))
    r = c.post(
        f"/sinav/{sinav.kimlik}/anahtar/onizle",
        data={
            "soru_no": ["1"],
            "soru_tip": ["bosluk_doldurma"],
            "soru_anahtar": ["plazma zarı"],
            "soru_kazanim": ["Hücre yapısı"],
        },
    )
    assert r.status_code == 200
    assert "Etki önizlemesi" in r.text
    assert db.kutular(kagit_id)[0]["son_puan"] == onceki


def test_anahtar_uygula_surum_ve_yeniden_puanlama(tmp_path):
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    db, sinav = _webapp_kurulum(tmp_path)
    kagit_id = db.kagitlar(sinav.kimlik)[0]["id"]
    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))
    r = c.post(
        f"/sinav/{sinav.kimlik}/anahtar",
        data={
            "soru_no": ["1"],
            "soru_tip": ["bosluk_doldurma"],
            "soru_anahtar": ["plazma zarı"],
            "soru_kazanim": ["Hücre yapısı"],
        },
        follow_redirects=False,
    )
    assert r.status_code == 303
    # Cevap artık anahtara uyuyor → tam puan
    assert db.kutular(kagit_id)[0]["son_puan"] == 10.0
    guncel = db.sinav_yukle(sinav.kimlik)
    assert guncel.sorular[0].kazanımlar == ["Hücre yapısı"]
    assert db.kagit(kagit_id)["onaylandi"] == 0


def test_anahtar_uygulamasi_elle_puani_ezmez(tmp_path):
    """Öğretmenin gözle verdiği istisna puan, başka sorunun anahtarı
    düzeltilince sessizce silinmemeli."""
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    db, sinav = _webapp_kurulum(tmp_path)
    kagit_id = db.kagitlar(sinav.kimlik)[0]["id"]
    kutu = db.kutular(kagit_id)[0]
    db.kutu_guncelle(kutu_id=kutu["id"], son_puan=8.0)

    c = TestClient(uygulama_kur(str(tmp_path / "t.db"), str(tmp_path / "kirp")))
    c.post(
        f"/sinav/{sinav.kimlik}/anahtar",
        data={
            "soru_no": ["1"],
            "soru_tip": ["bosluk_doldurma"],
            "soru_anahtar": ["plazma zarı"],
            "soru_kazanim": [""],
        },
        follow_redirects=False,
    )
    assert db.kutu(kutu["id"])["son_puan"] == 8.0


def test_onizleme_onayli_kabul_yazimlarini_hesaba_katar(depo):
    eski = _sinav(["hücre zarı"])
    depo.sinav_kaydet(eski)
    _kagit_ekle(depo, eski, "plazma zarı", 0.0)
    depo.ogrenilmis_kabul_kaydet(eski.kimlik, 1, "plazma zarı", 2)
    kabul = depo.ogrenilmis_kabuller(eski.kimlik, 1)[0]
    depo.ogrenilmis_kabul_onayla(kabul["id"])

    # Anahtar değişmiyor; onaylı kabul sayesinde cevap tam puan almalı.
    onizleme = anahtar_etkisini_onizle(depo, eski, _sinav(["hücre zarı"]))
    assert onizleme["toplam_etkilenen"] == 1
    assert onizleme["ornekler"][0]["yeni_puan"] == 10.0
