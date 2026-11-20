"""Sınav üretimi ve kazanım analizinin testleri."""

from __future__ import annotations

import pytest

from ogretmen_cantasi import sinav as sn


def havuz_kur() -> list[sn.Soru]:
    sorular: list[sn.Soru] = []
    numara = 1
    for tema, kazanim_sayisi in (("BİY.9.1", 7), ("BİY.9.2", 8)):
        for k in range(1, kazanim_sayisi + 1):
            for _ in range(3):
                sorular.append(
                    sn.Soru(
                        id=numara,
                        kazanim_kodu=f"{tema}.{k}",
                        metin=f"{numara}. açık uçlu soru",
                        rubrik="Tam cevap 10, kısmi 5",
                    )
                )
                numara += 1
    return sorular


def test_soru_dagitimi_toplami_korur() -> None:
    paylar = sn.soru_sayilarini_dagit({"BİY.9.1": 60, "BİY.9.2": 40}, 10)
    assert sum(paylar.values()) == 10
    assert paylar == {"BİY.9.1": 6, "BİY.9.2": 4}


def test_soru_dagitimi_kesirli_yuzdeyi_tam_sayiya_indirir() -> None:
    paylar = sn.soru_sayilarini_dagit({"a": 33, "b": 33, "c": 34}, 7)
    assert sum(paylar.values()) == 7


def test_sinav_uretimi_dagilima_uyar() -> None:
    sinav, uyarilar = sn.sinav_uret(
        ad="1. Yazılı",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz_kur(),
        dagilim={"BİY.9.1": 60, "BİY.9.2": 40},
        soru_sayisi=10,
    )
    assert not uyarilar
    assert len(sinav.sorular) == 10
    tema1 = [s for s in sinav.sorular if s.kazanim_kodu.startswith("BİY.9.1.")]
    assert len(tema1) == 6


def test_toplam_puan_yuze_tamamlanir() -> None:
    sinav, _ = sn.sinav_uret(
        ad="1. Yazılı",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz_kur(),
        dagilim={"BİY.9.1": 50, "BİY.9.2": 50},
        soru_sayisi=8,
    )
    assert sinav.toplam_puan == pytest.approx(100.0, abs=0.5)


def test_belirtke_gerceklesen_yuzdeyi_gosterir() -> None:
    sinav, _ = sn.sinav_uret(
        ad="1. Yazılı",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz_kur(),
        dagilim={"BİY.9.1": 60, "BİY.9.2": 40},
        soru_sayisi=10,
        adlar={"BİY.9.1": "YAŞAM", "BİY.9.2": "ORGANİZASYON"},
    )
    satirlar = {s.anahtar: s for s in sinav.belirtke}
    assert satirlar["BİY.9.1"].ad == "YAŞAM"
    assert satirlar["BİY.9.1"].soru_sayisi == 6
    assert satirlar["BİY.9.1"].puan == pytest.approx(60.0, abs=1.0)


def test_yetersiz_havuz_uyari_verir_ama_sinavi_uretir() -> None:
    havuz = [sn.Soru(id=1, kazanim_kodu="BİY.9.1.1", metin="tek soru")]
    sinav, uyarilar = sn.sinav_uret(
        ad="Yazılı",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz,
        dagilim={"BİY.9.1": 100},
        soru_sayisi=5,
    )
    assert uyarilar and "havuzda 1 var" in uyarilar[0]
    assert len(sinav.sorular) == 1


def test_bos_havuz_hata_verir() -> None:
    with pytest.raises(sn.SinavKurulamadi):
        sn.sinav_uret(
            ad="Yazılı", sube_adi="9-A", sinif=9, havuz=[], dagilim={"BİY.9.1": 100}, soru_sayisi=5
        )


def test_ab_gruplari_ayni_sorulari_farkli_sirada_tasir() -> None:
    sinav, _ = sn.sinav_uret(
        ad="Yazılı",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz_kur(),
        dagilim={"BİY.9.1": 50, "BİY.9.2": 50},
        soru_sayisi=10,
    )
    a, b = sinav.gruplar["A"], sinav.gruplar["B"]
    assert {s.id for s in a} == {s.id for s in b}
    assert [s.id for s in a] != [s.id for s in b]


def test_ayni_tohum_ayni_sinavi_uretir() -> None:
    ortak = {
        "ad": "Yazılı",
        "sube_adi": "9-A",
        "sinif": 9,
        "havuz": havuz_kur(),
        "dagilim": {"BİY.9.1": 60, "BİY.9.2": 40},
        "soru_sayisi": 10,
        "tohum": 42,
    }
    birinci, _ = sn.sinav_uret(**ortak)
    ikinci, _ = sn.sinav_uret(**ortak)
    assert [s.id for s in birinci.gruplar["B"]] == [s.id for s in ikinci.gruplar["B"]]


def test_ogrenci_kazanim_analizi() -> None:
    analiz = sn.ogrenci_kazanim_analizi(
        [("BİY.9.1.1", 8, 10), ("BİY.9.1.1", 2, 10), ("BİY.9.1.2", 9, 10)]
    )
    haritada = {a.kazanim_kodu: a for a in analiz}
    assert haritada["BİY.9.1.1"].yuzde == 50.0
    assert haritada["BİY.9.1.1"].durum == "orta"
    assert haritada["BİY.9.1.2"].durum == "iyi"


def test_sinif_analizi_ve_zayif_kazanimlar() -> None:
    kayitlar = [
        (1, "BİY.9.1.1", 3, 10),
        (2, "BİY.9.1.1", 4, 10),
        (1, "BİY.9.1.2", 9, 10),
        (2, "BİY.9.1.2", 8, 10),
    ]
    analiz = sn.sinif_kazanim_analizi(kayitlar)
    assert analiz["BİY.9.1.1"].yuzde == 35.0
    assert analiz["BİY.9.1.2"].yuzde == 85.0
    assert sn.zayif_kazanimlar(analiz) == ["BİY.9.1.1"]


def test_puanlanmamis_kazanimda_yuzde_yok() -> None:
    basari = sn.KazanimBasarisi("BİY.9.1.1", 0, 0)
    assert basari.yuzde is None
    assert basari.durum == "veri yok"


@pytest.mark.parametrize("soru_sayisi", [3, 6, 7, 8, 12, 13, 20])
def test_puanlar_tam_toplanir(soru_sayisi: int) -> None:
    paylar = sn.puanlari_dagit(100.0, soru_sayisi)
    assert len(paylar) == soru_sayisi
    assert sum(paylar) == 100.0
    assert all((p * 2).is_integer() for p in paylar), "puanlar yarım puanın katı olmalı"


def test_uretilen_sinavin_toplami_tam_yuz() -> None:
    for adet in (5, 6, 7, 9):
        sinav, _ = sn.sinav_uret(
            ad="Yazılı",
            sube_adi="9-A",
            sinif=9,
            havuz=havuz_kur(),
            dagilim={"BİY.9.1": 60, "BİY.9.2": 40},
            soru_sayisi=adet,
        )
        assert sinav.toplam_puan == 100.0, f"{adet} soruda toplam {sinav.toplam_puan}"


def test_belirtke_uzun_kodu_kisa_koda_saymaz() -> None:
    """"BİY.11.1.1" başlığı "BİY.11.1.10" sorusunu da sayıyordu."""
    sorular = [
        sn.Soru(id=1, kazanim_kodu="BİY.11.1.1", metin="a", puan=50),
        sn.Soru(id=2, kazanim_kodu="BİY.11.1.10", metin="b", puan=50),
    ]
    satirlar = {s.anahtar: s for s in sn.belirtke_kur(sorular, {"BİY.11.1.1": 50, "BİY.11.1.10": 50})}
    assert satirlar["BİY.11.1.1"].soru_sayisi == 1
    assert satirlar["BİY.11.1.10"].soru_sayisi == 1


def test_negatif_yuzde_fazla_soru_sectirmez() -> None:
    havuz = [sn.Soru(id=i, kazanim_kodu="BİY.9.1.1" if i <= 13 else "BİY.9.2.1", metin=f"s{i}")
             for i in range(1, 19)]
    sinav, _ = sn.sinav_uret(
        ad="Yazılı", sube_adi="9-A", sinif=9, havuz=havuz,
        dagilim={"BİY.9.1": 120, "BİY.9.2": -20}, soru_sayisi=10,
    )
    assert len(sinav.sorular) == 10


def test_belirtke_hedefleri_yuze_normalize_edilir() -> None:
    sorular = [
        sn.Soru(id=1, kazanim_kodu="BİY.9.1.1", metin="a", puan=50),
        sn.Soru(id=2, kazanim_kodu="BİY.9.2.1", metin="b", puan=50),
    ]
    satirlar = sn.belirtke_kur(sorular, {"BİY.9.1": 60, "BİY.9.2": 60})
    assert sum(s.hedef_yuzde for s in satirlar) == pytest.approx(100.0, abs=0.2)


def test_olculmemis_kazanim_zayif_sayilmaz() -> None:
    analiz = {
        "BİY.9.1.1": sn.KazanimBasarisi("BİY.9.1.1", 0, 0),
        "BİY.9.1.2": sn.KazanimBasarisi("BİY.9.1.2", 2, 10),
    }
    assert sn.zayif_kazanimlar(analiz) == ["BİY.9.1.2"]
