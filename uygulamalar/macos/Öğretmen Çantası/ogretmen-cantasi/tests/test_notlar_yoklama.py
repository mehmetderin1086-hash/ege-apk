"""Not hesabı ve sesli yoklama çözümlemesinin testleri."""

from __future__ import annotations

import pytest

from ogretmen_cantasi import notlar, yoklama

SINIF = [
    yoklama.Ogrenci(1, "101", "Ayşe Yılmaz"),
    yoklama.Ogrenci(2, "102", "Mehmet Kaya"),
    yoklama.Ogrenci(3, "103", "Ali Demir"),
    yoklama.Ogrenci(4, "104", "Zeynep Şahin"),
    yoklama.Ogrenci(5, "105", "Ilgaz Çetin"),
]


def puan(tur: str, deger: float | None, donem: int = 1, resmi: bool = True) -> notlar.Puan:
    return notlar.Puan(tur=tur, ad=tur, deger=deger, donem=donem, resmi=resmi)


# --- not hesabı ---------------------------------------------------------


def test_donem_ortalamasi_esit_agirlikli() -> None:
    puanlar = [
        puan(notlar.TUR_YAZILI, 80),
        puan(notlar.TUR_YAZILI, 60),
        puan(notlar.TUR_PERFORMANS, 100),
    ]
    assert notlar.donem_ortalamasi(puanlar) == 80.0


def test_girilmemis_not_sifir_sayilmaz() -> None:
    puanlar = [puan(notlar.TUR_YAZILI, 80), puan(notlar.TUR_YAZILI, None)]
    assert notlar.donem_ortalamasi(puanlar) == 80.0


def test_ic_takip_resmi_ortalamaya_girmez() -> None:
    puanlar = [
        puan(notlar.TUR_YAZILI, 60),
        puan(notlar.TUR_IC_TAKIP, 100, resmi=False),
    ]
    assert notlar.donem_ortalamasi(puanlar) == 60.0


def test_hic_not_yoksa_ortalama_yok() -> None:
    assert notlar.donem_ortalamasi([]) is None
    assert notlar.donem_ortalamasi([puan(notlar.TUR_YAZILI, None)]) is None


def test_eksik_sinav_sayisi_raporlanir() -> None:
    sonuc = notlar.donem_sonucu(1, [puan(notlar.TUR_YAZILI, 70)])
    assert sonuc.eksik[notlar.TUR_YAZILI] == 1
    assert sonuc.eksik[notlar.TUR_PERFORMANS] == 1


def test_yil_sonu_iki_donemin_ortalamasi() -> None:
    assert notlar.yil_sonu_puani(70, 90) == 80.0
    assert notlar.yil_sonu_puani(None, None) is None


def test_tek_donemle_yil_sonu_hesaplanmaz() -> None:
    """Yıl ortasında "geçti/kaldı" damgası vurulmamalı."""
    assert notlar.yil_sonu_puani(70, None) is None
    karne = notlar.karne_kur(1, "A", [puan(notlar.TUR_YAZILI, 80, donem=1)])
    assert karne.donemler[1].ortalama == 80.0
    assert karne.yil_sonu is None
    assert karne.gecti is None


def test_gecme_puani_kurallardan_gelir() -> None:
    kurallar = notlar.Kurallar(gecme_puani=60.0)
    puanlar = [puan(notlar.TUR_YAZILI, 55, donem=1), puan(notlar.TUR_YAZILI, 55, donem=2)]
    karne = notlar.karne_kur(1, "A", puanlar, kurallar)
    assert karne.yil_sonu == 55.0
    assert karne.gecti is False, "eşik 60 iken 55 geçmemeli"
    assert notlar.sinif_istatistigi([karne], 1, kurallar)["zayif"] == 1
    assert notlar.sinif_istatistigi([karne], 1)["zayif"] == 0, "varsayılan eşik 50"


def test_karne_ve_gecme_durumu() -> None:
    puanlar = [
        puan(notlar.TUR_YAZILI, 40, donem=1),
        puan(notlar.TUR_PERFORMANS, 50, donem=1),
        puan(notlar.TUR_YAZILI, 60, donem=2),
        puan(notlar.TUR_IC_TAKIP, 90, donem=2, resmi=False),
    ]
    karne = notlar.karne_kur(1, "Ayşe Yılmaz", puanlar)
    assert karne.donemler[1].ortalama == 45.0
    assert karne.donemler[2].ortalama == 60.0
    assert karne.yil_sonu == 52.5
    assert karne.gecti is True
    assert karne.ic_takip_ortalamasi == 90.0


def test_ozel_agirliklar_uygulanir() -> None:
    kurallar = notlar.Kurallar(
        agirliklar={notlar.TUR_YAZILI: 2.0, notlar.TUR_PERFORMANS: 1.0, notlar.TUR_PROJE: 1.0}
    )
    puanlar = [puan(notlar.TUR_YAZILI, 90), puan(notlar.TUR_PERFORMANS, 60)]
    assert notlar.donem_ortalamasi(puanlar, kurallar) == 80.0


def test_sinif_istatistigi() -> None:
    karneler = [
        notlar.karne_kur(1, "A", [puan(notlar.TUR_YAZILI, 40)]),
        notlar.karne_kur(2, "B", [puan(notlar.TUR_YAZILI, 80)]),
    ]
    istatistik = notlar.sinif_istatistigi(karneler, 1)
    assert istatistik == {
        "ogrenci": 2,
        "ortalama": 60.0,
        "en_dusuk": 40.0,
        "en_yuksek": 80.0,
        "zayif": 1,
    }


def test_devamsizlik_uyarisi_kademeli() -> None:
    assert notlar.devamsizlik_uyarisi(3) == ""
    assert "yaklaşıyor" in notlar.devamsizlik_uyarisi(7)
    assert "aşıldı" in notlar.devamsizlik_uyarisi(11)


# --- sesli yoklama ------------------------------------------------------


def test_turkce_kucultme_I_harfini_dogru_cevirir() -> None:
    assert yoklama.turkce_kucult("ILGAZ") == "ılgaz"
    assert yoklama.turkce_kucult("İSMAİL") == "ismail"


def test_gelmeyenler_isaretlenir_kalan_var_sayilir() -> None:
    cozum = yoklama.cozumle("Ayşe Yılmaz yok, Mehmet Kaya yok", SINIF)
    harita = cozum.durum_haritasi(SINIF)
    assert harita[1] == yoklama.DURUM_YOK
    assert harita[2] == yoklama.DURUM_YOK
    assert harita[3] == yoklama.DURUM_VAR
    assert harita[5] == yoklama.DURUM_VAR


def test_sadece_ad_soylense_de_eslesir() -> None:
    cozum = yoklama.cozumle("Zeynep yok", SINIF)
    assert cozum.atamalar[0].ogrenci.id == 4


def test_gec_ve_izinli_ayrilir() -> None:
    cozum = yoklama.cozumle("Ali Demir geç geldi, Zeynep Şahin izinli", SINIF)
    durumlar = {a.ogrenci.id: a.durum for a in cozum.atamalar}
    assert durumlar[3] == yoklama.DURUM_GEC
    assert durumlar[4] == yoklama.DURUM_IZINLI


def test_gelmeyenler_onekli_dokum() -> None:
    cozum = yoklama.cozumle("Gelmeyenler: Ayşe Yılmaz ve Ali Demir", SINIF)
    assert {a.ogrenci.id for a in cozum.atamalar} == {1, 3}
    assert all(a.durum == yoklama.DURUM_YOK for a in cozum.atamalar)


def test_tanimsiz_isim_eslesmeyenlere_dusler() -> None:
    cozum = yoklama.cozumle("Kerem Aslantürk yok", SINIF)
    assert cozum.eslesmeyenler
    assert not cozum.atamalar


def test_ayni_ad_belirsiz_isaretlenir() -> None:
    sinif = [*SINIF, yoklama.Ogrenci(6, "106", "Ayşe Korkmaz")]
    cozum = yoklama.cozumle("Ayşe yok", sinif)
    assert cozum.belirsizler, "iki Ayşe varken eşleşme kesin sayılmamalı"
    assert not cozum.atamalar


def test_bos_sinifta_cozum_bos_doner() -> None:
    cozum = yoklama.cozumle("Ayşe yok", [])
    assert not cozum.atamalar and not cozum.eslesmeyenler


def test_devamsizlik_ozeti() -> None:
    kayitlar = [
        ("2026-09-15", 1, yoklama.DURUM_VAR),
        ("2026-09-15", 2, yoklama.DURUM_YOK),
        ("2026-09-22", 1, yoklama.DURUM_YOK),
        ("2026-09-22", 2, yoklama.DURUM_IZINLI),
    ]
    # Salı (isoweekday 2) programda 2 saat: her iki günde de 2 saatin 1'i
    # kaçırılmış → 0,5 + 0,5 = 1 gün.
    ozet = yoklama.devamsizlik_ozeti(kayitlar, gunler={2: 2})
    assert ozet["yok_saat"] == 2
    assert ozet["yok_gun"] == 1.0
    assert ozet["izinli_saat"] == 1
    assert ozet["devam_orani"] == 50.0


def test_devamsizlik_ozeti_programsiz_gunun_kayit_sayisina_duser() -> None:
    kayitlar = [
        ("2026-09-15", 1, yoklama.DURUM_YOK),
        ("2026-09-15", 2, yoklama.DURUM_YOK),
    ]
    ozet = yoklama.devamsizlik_ozeti(kayitlar)
    assert ozet["yok_gun"] == 1.0


@pytest.mark.parametrize(
    ("dokum", "beklenen"),
    [
        ("ayşe yılmaz yok", 1),
        ("AYŞE YILMAZ YOK", 1),
        ("Ayse Yilmaz yok", 1),
    ],
)
def test_yazim_farklari_ayni_ogrenciye_gider(dokum: str, beklenen: int) -> None:
    cozum = yoklama.cozumle(dokum, SINIF)
    eslesenler = cozum.atamalar + cozum.belirsizler
    assert eslesenler[0].ogrenci.id == beklenen
