from __future__ import annotations

import pytest

from biyo_cozucu.metin import imza, katla, kirp, sadelestir
from biyo_cozucu.modeller import Cozum, Kanit, Ornek, cozum_turu_dogrula


def test_katla_turkce_i_harflerini_dogru_isler():
    assert katla("MİTOKONDRİ") == "mitokondri"
    assert katla("IŞIK") == "ışık"
    # Python'un varsayılan katlaması burada yanılır; farkın korunması testin amacı.
    assert "IŞIK".casefold() != katla("IŞIK")


def test_sadelestir_noktalama_ve_bosluk_temizler():
    assert sadelestir("  Mitoz,  bölünme!  ") == "mitoz bölünme"


def test_imza_bicimsel_farklara_duyarsiz():
    assert imza("Mitoz nedir?") == imza("  mitoz   NEDİR ")
    assert imza("Mitoz nedir?") != imza("Mayoz nedir?")


def test_pdf_soft_hyphen_imzayi_degistirmez():
    assert imza("ortak özel\u00ad lik") == imza("ortak özel lik")


def test_kirp_isaret_koyar():
    assert kirp("kısa", 10) == "kısa"
    kirpilmis = kirp("a" * 20, 10)
    assert len(kirpilmis) == 10 and kirpilmis.endswith("…")


def test_ornek_gecersiz_turleri_varsayilana_cevirir():
    ornek = Ornek(soru="s", cozum="c", cevap_turu="uydurma", cozum_turu="yok")
    assert ornek.cevap_turu == "acik_uclu"
    assert ornek.cozum_turu == "mekanizma_aciklama"


def test_indeks_metni_cozumu_icermez():
    """Sorgu ile belge aynı uzayda olmalı: hedef sorunun çözümü henüz yok."""
    ornek = Ornek(
        soru="Mitoz nedir?",
        cozum="ÇOK ÖZEL ÇÖZÜM METNİ",
        secenekler={"A": "bir", "B": "iki"},
        konu="hücre bölünmesi",
        etiketler=["kromozom"],
    )
    metin = ornek.indeks_metni()
    assert "ÇOK ÖZEL ÇÖZÜM METNİ" not in metin
    assert "A) bir" in metin and "hücre bölünmesi" in metin and "kromozom" in metin


def test_cozum_sozluk_json_gidis_donus():
    cozum = Cozum(
        soru="soru",
        adimlar=["a1", "a2"],
        cevap="B",
        guven=0.7,
        kanitlar=[
            Kanit(etiket="Ö1", ornek_id=3, soru="s", cozum="c", konu="k",
                  cozum_turu="hesaplama", skor=0.9, cevap="A")
        ],
        kitap_kaynaklari=["Campbell Biyoloji · s. 150"],
    )
    geri = Cozum.sozlukten(cozum.sozluk())
    assert geri.adimlar == ["a1", "a2"]
    assert geri.cevap == "B"
    assert geri.kanitlar[0].ornek_id == 3
    assert geri.kanitlar[0].cozum_turu == "hesaplama"
    assert geri.kitap_kaynaklari == ["Campbell Biyoloji · s. 150"]
    assert geri.kaynaklar() == [
        "örnek #3 (k · hesaplama)",
        "Campbell Biyoloji · s. 150",
    ]


def test_kanit_kaynak_adi_okunur():
    kanit = Kanit("Ö1", 12, "s", "c", "mitoz", "hesaplama", 0.5)
    assert kanit.kaynak_adi() == "örnek #12 (mitoz · hesaplama)"


@pytest.mark.parametrize("deger", ["", None, "saçma", "KALITIM_HESABI"])
def test_cozum_turu_dogrula_bilinmeyeni_varsayilana_cevirir(deger):
    assert cozum_turu_dogrula(deger) == "mekanizma_aciklama"


def test_cozum_metni_cevabi_sona_ekler():
    cozum = Cozum(soru="s", adimlar=["ilk", "ikinci"], cevap="C")
    assert cozum.metin() == "1. ilk\n2. ikinci\nCevap: C"
