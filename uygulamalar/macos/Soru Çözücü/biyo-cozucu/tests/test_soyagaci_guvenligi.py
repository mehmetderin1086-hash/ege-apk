"""Görsel soyağacı katmanı: model gözler, Python kalıtımı çözer."""

from __future__ import annotations

import pytest

from biyo_cozucu.kalitim.soyagaci import (
    CekirdekAile,
    aile_okuma_mesajlari,
    aileyi_ayikla,
    uyumluluk_coz,
    uyumluluk_sorusu_mu,
)

SORU = (
    "Aşağıdaki soyağacında bir hastalığın kalıtımı verilmiştir. "
    "I. Otozomal çekinik olarak kalıtılmaktadır. "
    "II. Otozomal baskın olarak kalıtılmaktadır. "
    "III. X kromozomundaki çekinik bir alelle kalıtılmaktadır. "
    "ifadelerinden hangileri doğru olabilir?"
)
SIKLAR = {
    "A": "Yalnız I",
    "B": "Yalnız III",
    "C": "I ve lI",  # gerçek OCR kusuru: ikinci I yerine küçük l
    "D": "I ve III",
    "E": "II ve III",
}


def test_canli_vlm_cumlesinden_aile_okunur():
    ham = (
        "En alttaki çocuk bir hasta dişi (siyah daire) ve hemen üstündeki "
        "anne ve babanın her ikisi de sağlıklıdır (beyaz kare ve beyaz daire)."
    )
    assert aileyi_ayikla(ham) == CekirdekAile("disi", True, False, False)


def test_canli_vlm_etiketli_satirlarindan_aile_okunur():
    ham = (
        "En alttaki çocuk: Hasta dişi.\n"
        "Üstteki anne: Sağlıklı dişi.\n"
        "Üstteki baba: Sağlıklı erkek."
    )
    assert aileyi_ayikla(ham) == CekirdekAile("disi", True, False, False)


@pytest.mark.parametrize("ham", ["", "BELİRSİZ", "Hasta bir birey var."])
def test_eksik_gorsel_okumada_birey_uydurulmaz(ham):
    assert aileyi_ayikla(ham) is None


def test_saglikli_ebeveynlerden_hasta_kiz_yalniz_ot_resesife_uyar():
    sonuc = uyumluluk_coz(
        SORU,
        SIKLAR,
        CekirdekAile("disi", True, anne_hasta=False, baba_hasta=False),
    )
    assert sonuc is not None
    assert sonuc.cevap == "A"
    assert any("babanın da hasta" in adim for adim in sonuc.adimlar)
    assert any("otozomal baskınla bağdaşmaz" in adim for adim in sonuc.adimlar)


def test_hasta_babali_hasta_kizda_xe_bagli_cekinik_elenmez():
    sonuc = uyumluluk_coz(
        SORU,
        SIKLAR,
        CekirdekAile("disi", True, anne_hasta=False, baba_hasta=True),
    )
    # Otozomal çekinik, otozomal baskın ve X'e bağlı çekinik birlikte
    # mümkün; bu kümeyi veren şık yoksa araç cevap UYDURMAMALIDIR.
    assert sonuc is None


def test_siklarda_dogru_kume_yoksa_cevap_uydurulmaz():
    sonuc = uyumluluk_coz(
        SORU,
        {"A": "Yalnız II", "B": "II ve III"},
        CekirdekAile("disi", True, anne_hasta=False, baba_hasta=False),
    )
    assert sonuc is None


def test_desteklenmeyen_soyagaci_sorusu_araca_girmez():
    soru = "Soyağacına göre 4 numaralı bireyin hasta olma olasılığı kaçtır?"
    assert not uyumluluk_sorusu_mu(soru, {"A": "1/2", "B": "1/4"})


def test_okuma_istemi_cozum_ve_sik_sizdirmaz():
    metin = " ".join(m["content"] for m in aile_okuma_mesajlari())
    assert "otozomal" not in metin.casefold()
    assert "cevap" not in metin.casefold()
    assert "BELİRSİZ" in metin
