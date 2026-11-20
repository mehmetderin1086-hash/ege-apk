"""Aday yeniden sıralama: dar marjda bağlama uyan okuma + kapı vetosu."""
from __future__ import annotations

from sinav_okur.guvenlik_kapisi import ASGARI_KARAR_MARJI
from sinav_okur.htr.yeniden_siralama import (
    DEGISIM_GUVEN_TAVANI,
    adaylari_yeniden_sirala,
    puan_sonucunu_kisitla,
)
from sinav_okur.modeller import (
    CevapAnahtari,
    PuanSonucu,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.terim_sozlugu import TerimSozlugu


def _soru() -> Soru:
    return Soru(
        no=1,
        tip=SoruTipi.BOSLUK_DOLDURMA,
        metin="Hücrenin enerji merkezi?",
        puan=10,
        anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
    )


def _sozluk(*terimler) -> TerimSozlugu:
    s = TerimSozlugu()
    for t in terimler:
        s.ekle(t, 1.0)
    return s


def _tanima(metin, adaylar, marj=0.02):
    return TanimaSonucu(
        metin=metin,
        guven=0.7,
        karar_marji=marj,
        alternatifler=[
            {"metin": m, "guven": g, "destek": 1} for m, g in adaylar
        ],
    )


def test_yuksek_marjda_hic_calismaz():
    tanima = _tanima(
        "kloroplast",
        [("kloroplast", 0.80), ("mitokondri", 0.79)],
        marj=ASGARI_KARAR_MARJI + 0.1,
    )
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar is None
    assert yeni is tanima


def test_dusuk_marjda_anahtara_uyan_aday_secilir():
    tanima = _tanima("kloroplast", [("kloroplast", 0.80), ("mitokondri", 0.79)])
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar is not None
    assert yeni.metin == "mitokondri"
    assert karar["onceki"] == "kloroplast"


def test_kazanan_degisince_otomatik_kabul_kapanir():
    tanima = _tanima("kloroplast", [("kloroplast", 0.80), ("mitokondri", 0.79)])
    tanima.otomatik_kabul = True
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar is not None
    assert yeni.otomatik_kabul is False
    assert "Aday yeniden sıralama" in yeni.belirsizlik_nedeni


def test_kapi_kanit_alanlari_korunur():
    tanima = _tanima("kloroplast", [("kloroplast", 0.80), ("mitokondri", 0.79)])
    tanima.uzlasma_guveni = 0.5
    tanima.bagimsiz_motor_sayisi = 2
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar is not None
    assert yeni.uzlasma_guveni == 0.5
    assert yeni.bagimsiz_motor_sayisi == 2
    assert yeni.karar_marji == tanima.karar_marji


def test_puan_artisinda_guven_tavanlanir():
    sonuc = PuanSonucu(puan=10.0, max_puan=10.0, guven=0.95)
    sonuc.puanlama_guveni = 0.95
    puan_sonucunu_kisitla(sonuc, onceki_puan=0.0)
    assert sonuc.incele is True
    assert sonuc.otomatik_kabul is False
    assert sonuc.guven <= DEGISIM_GUVEN_TAVANI
    assert sonuc.puanlama_guveni <= DEGISIM_GUVEN_TAVANI


def test_puan_artmadiginda_guven_tavanlanmaz():
    sonuc = PuanSonucu(puan=0.0, max_puan=10.0, guven=0.95)
    sonuc.puanlama_guveni = 0.95
    puan_sonucunu_kisitla(sonuc, onceki_puan=10.0)
    assert sonuc.incele is True
    assert sonuc.guven == 0.95  # düşen puanda tavan uygulanmaz


def test_tek_adayda_guvenli_geri_dusus():
    tanima = _tanima("mitokondri", [("mitokondri", 0.8)])
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar is None
    assert yeni is tanima


def test_alternatifsiz_tanima_cokmez():
    tanima = TanimaSonucu(metin="mitokondri", guven=0.7, karar_marji=0.0)
    yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), None)
    assert karar is None
    assert yeni is tanima


def test_skor_bilesenleri_kararda():
    tanima = _tanima("kloroplast", [("kloroplast", 0.80), ("mitokondri", 0.79)])
    _yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    assert karar["tur"] == "aday_yeniden_siralama"
    assert len(karar["skorlar"]) == 2
    assert all("skor" in s and "ocr" in s for s in karar["skorlar"])


# --- Code-review regresyonları -------------------------------------------


def test_sozluk_duzeltmesi_yeniden_siralamada_korunur():
    """Düzeltilmiş metin aday havuzuna girmezse her seferinde geri alınırdı."""
    from sinav_okur.terim_sozlugu import sozlukle_duzelt

    ham = TanimaSonucu(
        metin="mitokondi hücrenin enerji merkezidir",
        guven=0.71,
        karar_marji=0.02,
        alternatifler=[
            {"metin": "mitokondi hücrenin enerji merkezidir", "guven": 0.55},
            {"metin": "mitokondi hücrenin eneri merkezidir", "guven": 0.50},
        ],
    )
    duzeltilmis, degisimler = sozlukle_duzelt(ham, _sozluk("mitokondri"))
    assert degisimler  # sözlük gerçekten düzeltmiş olmalı
    yeni, karar = adaylari_yeniden_sirala(
        duzeltilmis, _soru(), _sozluk("mitokondri")
    )
    assert yeni.metin.startswith("mitokondri")
    assert karar is None  # düzeltilmiş metin kazandı; sahte "değişim" yok


def test_ham_ocr_adayi_havuza_alinmaz():
    """ham_ocr kaydının güveni kalibre ölçekte; motor adaylarıyla karışmamalı."""
    tanima = TanimaSonucu(
        metin="mitokondri",
        guven=0.9,
        karar_marji=0.02,
        alternatifler=[
            {"metin": "kloroplast", "guven": 0.55},
            {"metin": "mitokondi", "guven": 0.50, "kaynak": "ham_ocr"},
        ],
    )
    _yeni, karar = adaylari_yeniden_sirala(tanima, _soru(), _sozluk("mitokondri"))
    if karar is not None:
        assert all(
            "mitokondi " not in s["metin"] for s in karar["skorlar"]
        )
