"""Puanlayıcı kayıt defteri + OCR gürültüsüne dayanıklı yapısal puanlama."""
from __future__ import annotations

import pytest

from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.puanlama import (
    PUANLAYICILAR,
    puanla,
    puanlayici_coz,
    puanlayici_kaydet,
)
from sinav_okur.puanlama.yapisal import eslestirme_cozumle


@pytest.mark.parametrize("tip", list(SoruTipi))
def test_kayit_defteri_tum_tipleri_kapsar(tip):
    assert tip in PUANLAYICILAR
    assert callable(puanlayici_coz(tip))


def test_ozel_puanlayici_kaydedilebilir():
    from sinav_okur.modeller import PuanSonucu

    onceki = PUANLAYICILAR[SoruTipi.ETIK]
    try:
        def _sabit(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
            return PuanSonucu(7.0, soru.puan, 0.9, ["özel strateji"])

        puanlayici_kaydet(SoruTipi.ETIK, _sabit)
        soru = Soru(
            no=1, tip=SoruTipi.ETIK, metin="Etik değerlendirme", puan=10,
            anahtar=CevapAnahtari(rubrik=[RubrikKalemi("dürüstlük", 10)]),
        )
        sonuc = puanla(TanimaSonucu(metin="cevap", guven=0.95), soru)
        assert sonuc.puan == 7.0
        assert "özel strateji" in sonuc.detaylar
    finally:
        puanlayici_kaydet(SoruTipi.ETIK, onceki)


def _eslestirme_soru(puan=10.0) -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.ESLESTIRME,
        metin="Eşleştiriniz.",
        puan=puan,
        anahtar=CevapAnahtari(
            eslestirmeler={"1": "c", "2": "a", "3": "b"},
        ),
    )


@pytest.mark.parametrize(
    "cevap",
    [
        "1-c, 2-a, 3-b",
        "1c 2a 3b",
        "1) c\n2) a\n3) b",
        "1 : c\n2 : a\n3 : b",
        "1   c\n2   a\n3   b",
        "1 ile c, 2 ile a, 3 ile b",
    ],
)
def test_eslestirme_bicimleri_tam_puan_alir(cevap):
    sonuc = puanla(TanimaSonucu(metin=cevap, guven=0.95), _eslestirme_soru())
    assert sonuc.puan == 10.0


def test_eslestirme_kismi_dogruda_kismi_puan():
    sonuc = puanla(
        TanimaSonucu(metin="1-c, 2-b, 3-a", guven=0.95), _eslestirme_soru()
    )
    assert 0 < sonuc.puan < 10.0


def test_eslestirme_eksik_ciftte_incele():
    sonuc = puanla(TanimaSonucu(metin="1-c", guven=0.95), _eslestirme_soru())
    assert sonuc.incele is True


def test_eslestirme_cozumle_her_solu_bir_kez_esler():
    # Sol öğe iki kez yazılmışsa en iyi skorlu çift kalır.
    cozum = eslestirme_cozumle("1-c, 1-a, 2-b", ["1", "2"])
    assert set(cozum) == {"1", "2"}
    assert cozum["2"] == "b"


def test_eslestirme_cozumle_ayni_sagi_tekrar_kabul_eder():
    """Öğrenci aynı seçeneği iki soruya yazabilir; ikisi de ayrı değerlendirilir."""
    cozum = eslestirme_cozumle("1-c, 2-c", ["1", "2"])
    assert cozum == {"1": "c", "2": "c"}


def _siralama_soru() -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.SIRALAMA,
        metin="Sıralayınız.",
        puan=10,
        anahtar=CevapAnahtari(siralama=["profaz", "metafaz", "anafaz", "telofaz"]),
    )


def test_siralamada_tek_harf_hatasi_ogeyi_kaybettirmez():
    # "metafas" OCR hatası; tam find() bunu kaybediyordu.
    sonuc = puanla(
        TanimaSonucu(metin="profaz metafas anafaz telofaz", guven=0.95),
        _siralama_soru(),
    )
    assert sonuc.puan == 10.0


def test_siralamada_yanlis_sira_puan_dusurur():
    tam = puanla(
        TanimaSonucu(metin="profaz metafaz anafaz telofaz", guven=0.95),
        _siralama_soru(),
    )
    karisik = puanla(
        TanimaSonucu(metin="telofaz anafaz metafaz profaz", guven=0.95),
        _siralama_soru(),
    )
    assert karisik.puan < tam.puan


def test_puan_tavani_asilmaz():
    soru = _eslestirme_soru(puan=5.0)
    sonuc = puanla(TanimaSonucu(metin="1-c, 2-a, 3-b", guven=0.95), soru)
    assert sonuc.puan <= 5.0


# --- İnceleme regresyonları ----------------------------------------------


def test_siralamada_benzer_evre_adlari_sahte_bulma_uretmez():
    """'Profaz I' ile 'Profaz II' aynı pencereye kilitlenip puan şişirmemeli."""
    evreler = [
        "Profaz I", "Metafaz I", "Anafaz I", "Telofaz I",
        "Profaz II", "Metafaz II", "Anafaz II", "Telofaz II",
    ]
    soru = Soru(
        no=1, tip=SoruTipi.SIRALAMA, metin="Sıralayınız.", puan=8,
        anahtar=CevapAnahtari(siralama=evreler),
    )
    sonuc = puanla(
        TanimaSonucu(metin="Profaz I, Metafaz I, Anafaz I, Telofaz I", guven=0.95),
        soru,
    )
    assert sonuc.puan == 4.0
    assert sonuc.incele is True


def test_eslestirmede_cok_sozcuklu_ogeler_okunur():
    soru = Soru(
        no=1, tip=SoruTipi.ESLESTIRME, metin="Eşleştiriniz.", puan=10,
        anahtar=CevapAnahtari(
            eslestirmeler={"hücre zarı": "A", "çekirdek zarı": "B"}
        ),
    )
    sonuc = puanla(
        TanimaSonucu(metin="hücre zarı - A\nçekirdek zarı - B", guven=0.95), soru
    )
    assert sonuc.puan == 10.0
