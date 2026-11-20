"""Çok boşluklu kısmi puan ve öğrenilmiş kabul yazımları."""
from __future__ import annotations

from sinav_okur.modeller import CevapAnahtari, Soru, SoruTipi, TanimaSonucu
from sinav_okur.ogrenme import ogrenilmis_kabul_yazimlari
from sinav_okur.puanlama import puanla


def _soru(dogru, puan=9.0) -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.BOSLUK_DOLDURMA,
        metin="Boşlukları doldurunuz.",
        puan=puan,
        anahtar=CevapAnahtari(dogru_cevaplar=list(dogru)),
    )


def test_uc_bosluktan_ikisi_dogruysa_kismi_puan():
    soru = _soru(["mitokondri", "kloroplast", "ribozom"])
    sonuc = puanla(
        TanimaSonucu(metin="mitokondri; kloroplast; lizozom", guven=0.95), soru
    )
    assert sonuc.puan == 6.0  # 2/3 × 9
    assert sonuc.incele is True


def test_tum_bosluklar_dogruysa_tam_puan_ve_incele_yok():
    soru = _soru(["mitokondri", "kloroplast", "ribozom"])
    sonuc = puanla(
        TanimaSonucu(metin="mitokondri; kloroplast; ribozom", guven=0.95), soru
    )
    assert sonuc.puan == 9.0
    assert sonuc.incele is False


def test_bosluk_sirasi_onemsiz():
    soru = _soru(["mitokondri", "kloroplast", "ribozom"])
    sonuc = puanla(
        TanimaSonucu(metin="ribozom, mitokondri, kloroplast", guven=0.95), soru
    )
    assert sonuc.puan == 9.0


def test_tek_bosluk_davranisi_degismez():
    """Regresyon: tek doğru cevaplı soru eski yolla puanlanmaya devam eder."""
    soru = _soru(["mitokondri"], puan=10.0)
    sonuc = puanla(TanimaSonucu(metin="mitokondri", guven=0.95), soru)
    assert sonuc.puan == 10.0
    assert sonuc.incele is False


def test_cok_kabullu_tek_bosluk_kismi_puanlamaya_dusmez():
    """Anahtarda çok yazım var ama cevap tek parça → eski yol."""
    soru = _soru(["hücre zarı", "plazma zarı"], puan=10.0)
    sonuc = puanla(TanimaSonucu(metin="plazma zarı", guven=0.95), soru)
    assert sonuc.puan == 10.0


def test_ogrenilmis_kabul_puan_verir_ama_otomatik_kabul_etmez():
    soru = _soru(["hücre zarı"], puan=10.0)
    sonuc = puanla(
        TanimaSonucu(metin="plazma zarı", guven=0.95),
        soru,
        ogrenilmis_kabuller=["plazma zarı"],
    )
    assert sonuc.puan == 10.0
    assert sonuc.incele is True
    assert sonuc.otomatik_kabul is False
    assert sonuc.kararlar[-1]["tur"] == "ogrenilmis_kabul"


def test_ogrenilmis_kabul_yoksa_yazim_sifir_alir():
    soru = _soru(["hücre zarı"], puan=10.0)
    sonuc = puanla(TanimaSonucu(metin="plazma zarı", guven=0.95), soru)
    assert sonuc.puan == 0.0


def _duzeltme(yazim, ogretmen=10.0, otomatik=0.0, soru_no=1):
    return {
        "soru_no": soru_no,
        "ocr_metni": yazim,
        "duzeltilmis_metin": yazim,
        "ogretmen_puani": ogretmen,
        "otomatik_puan": otomatik,
    }


def test_tek_destekli_yazim_oneri_uretmez():
    oneriler = ogrenilmis_kabul_yazimlari(
        [_duzeltme("plazma zarı")],
        soru_no=1,
        max_puan=10.0,
        anahtar_yazimlari=["hücre zarı"],
    )
    assert oneriler == []


def test_iki_destekli_yazim_oneri_uretir():
    oneriler = ogrenilmis_kabul_yazimlari(
        [_duzeltme("plazma zarı"), _duzeltme("plazma zarı")],
        soru_no=1,
        max_puan=10.0,
        anahtar_yazimlari=["hücre zarı"],
    )
    assert len(oneriler) == 1
    assert oneriler[0]["yazim"] == "plazma zarı"
    assert oneriler[0]["destek"] == 2
    assert oneriler[0]["onay_durumu"] == "oneri"


def test_anahtara_zaten_yakin_yazim_oneri_uretmez():
    oneriler = ogrenilmis_kabul_yazimlari(
        [_duzeltme("hücre zari"), _duzeltme("hücre zari")],
        soru_no=1,
        max_puan=10.0,
        anahtar_yazimlari=["hücre zarı"],
    )
    assert oneriler == []


def test_tam_puan_verilmeyen_yazim_oneri_uretmez():
    oneriler = ogrenilmis_kabul_yazimlari(
        [_duzeltme("plazma zarı", ogretmen=5.0)] * 3,
        soru_no=1,
        max_puan=10.0,
        anahtar_yazimlari=["hücre zarı"],
    )
    assert oneriler == []


def test_depo_ogrenilmis_kabul_yuvarlak_gidis(depo):
    depo.ogrenilmis_kabul_kaydet("S-1", 1, "plazma zarı", 2)
    kayitlar = depo.ogrenilmis_kabuller("S-1", 1)
    assert len(kayitlar) == 1
    assert kayitlar[0]["onay_durumu"] == "oneri"
    depo.ogrenilmis_kabul_onayla(kayitlar[0]["id"])
    onayli = depo.ogrenilmis_kabuller("S-1", 1, onay_durumu="onayli")
    assert len(onayli) == 1
    assert onayli[0]["yazim"] == "plazma zarı"


# --- İnceleme regresyonları ----------------------------------------------


def test_ondalik_virgullu_cevap_kismi_puana_dusmez():
    """Türkçe ondalık ayracı virgül; "0,5 mol" iki boşluk sanılmamalı."""
    soru = Soru(
        no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="Kaç mol?", puan=10,
        anahtar=CevapAnahtari(dogru_cevaplar=["0,5 mol", "0.5 mol"]),
    )
    sonuc = puanla(TanimaSonucu(metin="0,5 mol", guven=0.95), soru)
    assert sonuc.puan == 10.0


def test_aciklamali_cevap_alternatif_anahtarda_tam_puan_alir():
    soru = Soru(
        no=1, tip=SoruTipi.BOSLUK_DOLDURMA, metin="Organel?", puan=10,
        anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri", "mitokondriler"]),
    )
    sonuc = puanla(TanimaSonucu(metin="mitokondri", guven=0.95), soru)
    assert sonuc.puan == 10.0


def test_isaretli_iki_boslukta_eksik_cevap_yarim_puan():
    """Soru metninde iki boşluk işareti varsa tek cevap tam puan almamalı."""
    soru = Soru(
        no=1, tip=SoruTipi.BOSLUK_DOLDURMA,
        metin="Enerji ___ , fotosentez ___ organelinde gerçekleşir.", puan=10,
        anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri", "kloroplast"]),
    )
    tek = puanla(TanimaSonucu(metin="mitokondri", guven=0.95), soru)
    assert tek.puan == 5.0
    assert tek.incele is True
    ikisi = puanla(TanimaSonucu(metin="mitokondri, kloroplast", guven=0.95), soru)
    assert ikisi.puan == 10.0


def test_sinirda_eslesen_bosluk_incelemeye_duser():
    soru = Soru(
        no=1, tip=SoruTipi.BOSLUK_DOLDURMA,
        metin="___ ve ___ yazınız.", puan=10,
        anahtar=CevapAnahtari(dogru_cevaplar=["hücre zarı", "plazma zarı"]),
    )
    sonuc = puanla(TanimaSonucu(metin="hücre katı, plazma katı", guven=0.95), soru)
    assert sonuc.incele is True
