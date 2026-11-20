"""Faz 0 ortak puanlama servisi: kuru puanlama depoya yazmaz."""
from __future__ import annotations

from sinav_okur.modeller import CevapAnahtari, Sinav, Soru, SoruTipi
from sinav_okur.yeniden_puanlama import (
    metni_puanla,
    rag_onbellegini_temizle,
    referans_pasajlari_getir,
)


def _sinav() -> Sinav:
    return Sinav(
        kimlik="TEST-1",
        baslik="Test",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.BOSLUK_DOLDURMA,
                metin="Hücrenin enerji merkezi nedir?",
                puan=10,
                anahtar=CevapAnahtari(dogru_cevaplar=["mitokondri"]),
            )
        ],
    )


def test_metni_puanla_depoya_yazmaz(depo):
    sinav = _sinav()
    depo.sinav_kaydet(sinav)
    once = depo.kagitlar(sinav.kimlik)
    sonuc = metni_puanla(sinav, 1, "mitokondri")
    assert sonuc.puan == 10
    assert depo.kagitlar(sinav.kimlik) == once


def test_metni_puanla_ragsiz_calisir():
    sonuc = metni_puanla(_sinav(), 1, "mitokondri", referans_pasajlari=None)
    assert sonuc.otomatik_kabul is True
    assert sonuc.incele is False


def test_bos_metin_incelemeye_duser():
    sonuc = metni_puanla(_sinav(), 1, "   ")
    assert sonuc.incele is True
    assert sonuc.guven == 0.0
    assert sonuc.otomatik_kabul is False


def test_kalibrasyon_notu_puana_uygulanmaz():
    ornekler = [
        {
            "soru_no": 1,
            "otomatik_puan": 10.0,
            "ogretmen_puani": 8.0,
            "ocr_metni": "mitokondri",
            "duzeltilmis_metin": "mitokondri",
        }
        for _ in range(6)
    ]
    sonuc = metni_puanla(_sinav(), 1, "mitokondri", duzeltme_ornekleri=ornekler)
    assert sonuc.puan == 10  # eğilim yalnız açıklama, puana uygulanmaz
    assert any("kalibrasyon eğilimi" in d for d in sonuc.detaylar)


def test_referans_pasajlari_indekssiz_none_doner(tmp_path):
    rag_onbellegini_temizle()
    assert referans_pasajlari_getir(tmp_path / "yok", "soru") is None
    assert referans_pasajlari_getir(None, "soru") is None
