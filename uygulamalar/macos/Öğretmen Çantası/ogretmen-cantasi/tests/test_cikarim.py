"""Müfredat çıkarıcısının testleri.

Çıkarım tek seferlik bir iş ama sessiz veri kaybı en pahalı hata türü: JSON
"geçerli" görünürken bir bölüm komşusuna emilmiş olabiliyor. Bu testler
çıkarıcının kendi kurallarını sabitliyor.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest

PROJE = Path(__file__).resolve().parents[1]


def _cikarici():
    spec = importlib.util.spec_from_file_location(
        "mufredat_cikar", PROJE / "scripts/mufredat_cikar.py"
    )
    modul = importlib.util.module_from_spec(spec)
    # dataclass, sınıfın modülünü sys.modules'te arıyor; kaydetmeden yüklenirse
    # `@dataclass` süslemesi çöküyor.
    sys.modules["mufredat_cikar"] = modul
    spec.loader.exec_module(modul)
    return modul


mc = _cikarici()


def satirlar(*metinler: str, sayfa: int = 20) -> list:
    return [mc.Satir(m, sayfa) for m in metinler]


def test_hece_tiresi_kucuk_harfte_birlesir() -> None:
    sonuc = mc.tireleri_birlestir(satirlar("uygunlu-", "ğunu yorumlamaları"))
    assert sonuc[0].metin == "uygunluğunu yorumlamaları"


def test_buyuk_harfle_devam_eden_bolunme_de_birlesir() -> None:
    """Belgede "CO-" / "VID-19" iki satıra bölünmüş."""
    sonuc = mc.tireleri_birlestir(satirlar("Öğrencilere CO-", "VID-19, kuş gribi gibi"))
    assert sonuc[0].metin == "Öğrencilere COVID-19, kuş gribi gibi"


def test_bolum_isareti_govdeye_yapistirilmaz() -> None:
    """Tireyle biten bir satırın ardından gelen başlık birleştirilmemeli."""
    sonuc = mc.tireleri_birlestir(satirlar("bir şey ve KOD-", "DERS SAATİ 38"))
    assert len(sonuc) == 2
    assert sonuc[1].metin == "DERS SAATİ 38"


def test_kucuk_harfle_baslamayan_normal_satir_birlesmez() -> None:
    sonuc = mc.tireleri_birlestir(satirlar("bir tire ile biten cümle-", "Yeni cümle başlar"))
    assert len(sonuc) == 2


def test_eksik_bolum_isareti_raporlanir() -> None:
    """Bölüm bulunamazsa metni komşusuna emiliyor; bu sessiz kalmamalı."""
    govde = [
        "Tema açıklaması.",
        "DERS SAATİ 38",
        "ALAN",
        "BECERİLERİ FBAB1. Bilimsel Gözlem",
        "ÖĞRENME ÇIKTILARI",
        "VE SÜREÇ BİLEŞENLERİ BİY.9.1.1. Bir şey yapabilme a) Yapar.",
    ]
    _, eksikler = mc.temayi_kur(1, "YAŞAM", govde)
    assert "kopru_kurma" in eksikler
    assert "icerik_cercevesi" in eksikler


def test_dogrulama_saat_uyusmazligini_yakalar() -> None:
    veri = {
        "siniflar": [
            {
                "sinif": 9,
                "haftalik_ders_saati": 2,
                "okul_temelli_planlama_saati": 4,
                "toplam_ders_saati": 72,
                "toplam_ogrenme_ciktisi": 15,
                "temalar": [
                    {
                        "no": 1,
                        "ad": "YAŞAM",
                        "ders_saati": 30,  # 30 + 30 + 4 = 64 ≠ 72
                        "ogrenme_ciktilari": [],
                        "icerik_cercevesi": "x",
                        "ogrenme_kanitlari": "x",
                        "on_degerlendirme": "x",
                        "anahtar_kavramlar": ["a"],
                    },
                    {
                        "no": 2,
                        "ad": "ORGANİZASYON",
                        "ders_saati": 30,
                        "ogrenme_ciktilari": [],
                        "icerik_cercevesi": "x",
                        "ogrenme_kanitlari": "x",
                        "on_degerlendirme": "x",
                        "anahtar_kavramlar": ["a"],
                    },
                ],
            }
        ]
    }
    hatalar = mc.dogrula(veri)
    assert any("tema saatleri" in h for h in hatalar)
    assert any("öğrenme çıktısı çıkarıldı" in h for h in hatalar)


def test_kod_bosluklu_dizilse_de_okunur() -> None:
    """Belgede bir yerde "BİY. 9.2.1" diye boşluklu dizilmiş."""
    uygulamalar = mc.uygulamalari_ayristir("BİY. 9.2.1 a) Bir şey yapılır. BİY.9.2.2 b) Başka şey.")
    assert set(uygulamalar) == {"BİY.9.2.1", "BİY.9.2.2"}


def test_sayfa_numarasi_yalniz_ilk_satirda_atilir(tmp_path: Path) -> None:
    """Tema tablosunda sayfa numarasıyla aynı değerli GERÇEK hücreler var."""
    import pymupdf

    belge = pymupdf.open()
    belge.new_page()
    belge.new_page()
    ucuncu = belge.new_page()  # sayfa numarası "3" olacak
    ucuncu.insert_text((60, 60), "3")  # sayfanın kendi numarası — atılmalı
    ucuncu.insert_text((60, 90), "OKUL TEMELLI PLANLAMA*")
    ucuncu.insert_text((60, 120), "3")  # gerçek tablo hücresi — korunmalı
    yol = tmp_path / "t.pdf"
    belge.save(yol)
    belge.close()

    okunan = [s.metin for s in mc.pdf_satirlari(yol) if s.sayfa == 3]
    assert okunan.count("3") == 1, "tablo hücresi sayfa numarası sanılıp atılmamalı"
    assert "OKUL TEMELLI PLANLAMA*" in okunan


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_uretilen_json_pdfle_uyusuyor(sinif: int) -> None:
    """Depodaki JSON, betiğin kendi doğrulamasından geçmeli."""
    import json

    veri = json.loads((PROJE / "veri/mufredat_maarif_2024.json").read_text(encoding="utf-8"))
    assert mc.dogrula(veri) == []
    duzey = next(d for d in veri["siniflar"] if d["sinif"] == sinif)
    assert sum(t["ders_saati"] for t in duzey["temalar"]) + duzey["okul_temelli_planlama_saati"] == (
        duzey["toplam_ders_saati"]
    )


def test_bilinmeyen_surum_acik_hatayla_reddedilir(monkeypatch: pytest.MonkeyPatch) -> None:
    """2018 belgesi Maarif ayrıştırıcısından geçirilirse sessizce yanlış JSON
    çıkardı; betik bilinmeyen sürümü açık hatayla reddetmeli."""
    monkeypatch.setattr(sys, "argv", ["mufredat_cikar", "--surum", "mfp_2018"])
    with pytest.raises(SystemExit) as hata:
        mc.main()
    assert "ayrıştırıcı yok" in str(hata.value)
