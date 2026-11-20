"""Gölge kapı telemetri paneli: depo sorgusu, eşik süpürmesi ve /kapi rotası."""
from __future__ import annotations

from sinav_okur.analiz import esik_supurmesi
from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _kapi_karari(
    kabul: bool,
    *,
    guven: float = 0.95,
    nedenler: list[str] | None = None,
) -> dict:
    return {
        "tur": "guvenlik_kapisi",
        "mod": "golge",
        "otomatik_kabul": kabul,
        "nedenler": nedenler if nedenler is not None else (
            ["Kalibre OCR ve puanlama güvenleri eşikleri geçti."] if kabul else []
        ),
        "kalibre_guven": guven,
        "uzlasma_guveni": 0.93,
        "bagimsiz_motor": 2,
        "karar_marji": 0.2,
        "puanlama_guveni": 0.9,
    }


def _kagit_yaz(depo, sinav, karar: dict, metin: str = "mitokondri") -> int:
    return depo.kagit_kaydet(
        KagitSonucu(
            sinav_kimlik=sinav.kimlik,
            islenen_sayfalar=[1],
            kutular=[
                KutuSonucu(
                    soru_no=sinav.sorular[0].no,
                    tanima=TanimaSonucu(metin=metin, guven=karar["kalibre_guven"]),
                    puan=PuanSonucu(
                        puan=5, max_puan=sinav.sorular[0].puan, guven=0.9,
                        kararlar=[karar],
                    ),
                )
            ],
        ),
        ogrenci_ad="Öğrenci",
    )


def test_kapi_kayitlari_karar_alanlarini_doker(depo, ornek_sinav) -> None:
    depo.sinav_kaydet(ornek_sinav)
    _kagit_yaz(depo, ornek_sinav, _kapi_karari(True, guven=0.94))
    kayitlar = depo.kapi_kayitlari()
    assert len(kayitlar) == 1
    kayit = kayitlar[0]
    assert kayit["otomatik_kabul"] is True
    assert kayit["kalibre_guven"] == 0.94
    assert kayit["ogretmen_degistirdi"] is False


def test_kapi_kayitlari_duzeltmeyi_isaretler(depo, ornek_sinav) -> None:
    depo.sinav_kaydet(ornek_sinav)
    kagit_id = _kagit_yaz(depo, ornek_sinav, _kapi_karari(True))
    kutu = depo.kutular(kagit_id)[0]
    depo.kutu_guncelle(kutu["id"], duzeltilmis_metin="lizozom")
    assert depo.kapi_kayitlari()[0]["ogretmen_degistirdi"] is True


def test_esik_supurmesi_ocr_vetosunu_yeniden_yorumlar() -> None:
    kayitlar = [
        # 0,88 güvenle reddedilmiş, tek vetosu OCR güveni: 0,86 eşiğinde kabul olur.
        {
            "otomatik_kabul": False,
            "nedenler": ["Kalibre OCR güveni düşük (0.88)."],
            "kalibre_guven": 0.88,
            "ogretmen_degistirdi": True,
        },
        # Kategorik vetolu kutu hiçbir eşikte kabul edilmez.
        {
            "otomatik_kabul": False,
            "nedenler": ["Görsel cevap türü otomatik kesinleştirilemez."],
            "kalibre_guven": 0.99,
            "ogretmen_degistirdi": False,
        },
        # Boş kutu kabulü güvenden bağımsızdır.
        {
            "otomatik_kabul": True,
            "nedenler": ["İki aşamalı görüntü denetimi cevap bölgesini boş buldu."],
            "kalibre_guven": 0.0,
            "ogretmen_degistirdi": False,
        },
    ]
    sonuc = {s["esik"]: s for s in esik_supurmesi(kayitlar, esikler=(0.86, 0.90))}
    assert sonuc[0.86]["sim_kabul"] == 2  # OCR-vetolu + boş
    assert sonuc[0.86]["sim_yanlis_kabul"] == 1  # düzeltilen OCR-vetolu kutu
    assert sonuc[0.90]["sim_kabul"] == 1  # yalnız boş kutu
    assert sonuc[0.90]["sim_yanlis_kabul"] == 0


def test_esik_supurmesi_oneki_kapi_mesajiyla_uyumlu() -> None:
    """Süpürme, OCR güven vetosunu mesaj önekinden tanır; kapının ürettiği
    gerçek mesajın öneki değişirse bu sözleşme testi kırmızı yanar."""
    from sinav_okur.analiz import _OCR_GUVEN_VETO_ONEKI
    from sinav_okur.guvenlik_kapisi import otomatik_karari_degerlendir
    from sinav_okur.modeller import (
        CevapAnahtari, PuanSonucu, RubrikKalemi, Soru, SoruTipi, TanimaSonucu,
    )

    soru = Soru(
        no=1, tip=SoruTipi.KISA_CEVAP, metin="Organel?", puan=10,
        anahtar=CevapAnahtari(rubrik=[RubrikKalemi(metin="mitokondri", puan=10)]),
    )
    tanima = TanimaSonucu(
        metin="mitokondri", guven=0.5, uzlasma_guveni=0.95,
        karar_marji=0.5, bagimsiz_motor_sayisi=2, girdi_kalitesi=0.9,
    )
    puan = otomatik_karari_degerlendir(
        tanima, PuanSonucu(puan=10, max_puan=10, guven=0.9, puanlama_guveni=0.9),
        soru,
    )
    assert any(
        n.startswith(_OCR_GUVEN_VETO_ONEKI) for n in puan.kabul_nedenleri
    ), "Kapı mesajı değişti: analiz._OCR_GUVEN_VETO_ONEKI güncellenmeli"


def test_esik_supurmesi_bos_girdi() -> None:
    sonuc = esik_supurmesi([], esikler=(0.90,))
    assert sonuc == [
        {"esik": 0.90, "sim_kabul": 0, "sim_kabul_orani": 0.0, "sim_yanlis_kabul": 0}
    ]


def test_kapi_sayfasi_acilir(tmp_path) -> None:
    import pytest

    fastapi = pytest.importorskip("fastapi")
    from fastapi.testclient import TestClient

    from sinav_okur.webapp import uygulama_kur

    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    with TestClient(app) as istemci:
        yanit = istemci.get("/kapi")
    assert yanit.status_code == 200
    assert "Güvenlik kapısı telemetrisi" in yanit.text
    assert "Kalibrasyon dosyası yok" in yanit.text or "Kalibrasyon durumu" in yanit.text
