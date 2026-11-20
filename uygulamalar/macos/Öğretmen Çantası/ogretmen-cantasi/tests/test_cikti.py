"""Çıktı üretiminin testleri.

Dosyaların yalnız üretilmesi değil, İÇİNDEKİ Türkçe metnin doğru okunması da
sınanır: yazı tipi gömme hatası ancak böyle yakalanır — bozuk PDF de geçerli
bir PDF'tir.
"""

from __future__ import annotations

import io
import zipfile
from datetime import date

import pymupdf
import pytest
from openpyxl import load_workbook

from ogretmen_cantasi import mufredat as m
from ogretmen_cantasi import sinav as sn
from ogretmen_cantasi import takvim as tk
from ogretmen_cantasi.cikti import belge, excel, pdf, word
from ogretmen_cantasi.plan import gunluk, yillik

TURKCE = "ÇĞİÖŞÜ çğıöşü"


@pytest.fixture(scope="module")
def program() -> m.Mufredat:
    return m.yukle(m.MAARIF_2024)


@pytest.fixture(scope="module")
def plan_satirlari(program: m.Mufredat) -> list[yillik.PlanSatiri]:
    _, d1, d2 = tk.varsayilan_ogretim_yili(2026)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    return yillik.yillik_plan_uret(program.duzey(9), haftalar)


@pytest.fixture(scope="module")
def ornek_sinav() -> sn.Sinav:
    havuz = [
        sn.Soru(
            id=i,
            kazanim_kodu=f"BİY.9.1.{(i % 7) + 1}",
            metin=f"Şöyle bir açık uçlu soru {i}: canlıların ortak özelliklerini açıklayınız.",
            rubrik="Tam cevap 10, eksik 5",
        )
        for i in range(1, 21)
    ]
    sinav, _ = sn.sinav_uret(
        ad="1. Yazılı Sınav",
        sube_adi="9-A",
        sinif=9,
        havuz=havuz,
        dagilim={"BİY.9.1": 100},
        soru_sayisi=6,
    )
    return sinav


def pdf_metni(baytlar: bytes) -> str:
    with pymupdf.open(stream=baytlar, filetype="pdf") as belge_nesnesi:
        return "\n".join(sayfa.get_text() for sayfa in belge_nesnesi)


def docx_metni(baytlar: bytes) -> str:
    with zipfile.ZipFile(io.BytesIO(baytlar)) as paket:
        return paket.read("word/document.xml").decode("utf-8")


# --- PDF ----------------------------------------------------------------


def test_pdf_turkce_karakterleri_korur() -> None:
    baytlar = pdf.html_pdfe(f"<p>{TURKCE}</p>")
    assert TURKCE in pdf_metni(baytlar)


def test_yillik_plan_pdfi_uretilir(plan_satirlari) -> None:
    html = belge.yillik_plan_meb(
        plan_satirlari,
        okul="Örnek Anadolu Lisesi",
        sube_adi="9-A",
        ogretim_yili="2026-2027",
        ogretmen="Mehmet Derin",
    )
    metin = pdf_metni(pdf.html_pdfe(html, yatay=True))
    assert "ÜNİTELENDİRİLMİŞ YILLIK DERS PLANI" in metin
    assert "BİY.9.1.1" in metin
    assert "Biyoloji Öğretmeni" in metin


def test_yillik_plan_pdfi_tum_kazanimlari_tasir(plan_satirlari, program: m.Mufredat) -> None:
    html = belge.yillik_plan_meb(
        plan_satirlari, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="MD"
    )
    metin = pdf_metni(pdf.html_pdfe(html, yatay=True))
    for cikti in program.duzey(9).ogrenme_ciktilari:
        assert cikti.kod in metin, f"{cikti.kod} PDF'e girmemiş"


def test_gunluk_plan_pdfi(program: m.Mufredat) -> None:
    tema = program.duzey(9).temalar[0]
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 9, 15),
        sube_adi="9-A",
        sinif=9,
        tema=tema,
        kazanimlar=list(tema.ogrenme_ciktilari[:1]),
        ders_saatleri=[1, 2],
    )
    metin = pdf_metni(pdf.html_pdfe(belge.gunluk_plan_belgesi(plan, okul="Okul", ogretmen="MD")))
    assert "GÜNLÜK DERS PLANI" in metin
    assert "Ders Akışı" in metin
    assert "80 dakika" in metin


def test_sinav_kagidi_ve_cevap_anahtari(ornek_sinav: sn.Sinav) -> None:
    kagit = pdf_metni(
        pdf.html_pdfe(belge.sinav_kagidi(ornek_sinav, "A", okul="Okul", ogretmen="MD"))
    )
    assert "1. Yazılı Sınav — A GRUBU" in kagit
    assert "Adı Soyadı" in kagit

    anahtar = pdf_metni(pdf.html_pdfe(belge.cevap_anahtari(ornek_sinav, okul="Okul"), yatay=True))
    assert "BELİRTKE TABLOSU" in anahtar
    assert "Dereceli Puanlama Anahtarı" in anahtar
    assert "B Grubu" in anahtar


def test_maarif_tema_tablosu_pdfi(program: m.Mufredat) -> None:
    tema = program.duzey(9).temalar[0]
    veri = [
        {
            "no": tema.no,
            "ad": tema.ad,
            "aciklama": tema.aciklama,
            "ders_saati": tema.ders_saati,
            "alan_becerileri": list(tema.alan_becerileri),
            "kavramsal_beceriler": list(tema.kavramsal_beceriler),
            "egilimler": list(tema.egilimler),
            "sosyal_duygusal_beceriler": list(tema.sosyal_duygusal_beceriler),
            "degerler": list(tema.degerler),
            "okuryazarlik_becerileri": list(tema.okuryazarlik_becerileri),
            "disiplinler_arasi": list(tema.disiplinler_arasi),
            "beceriler_arasi": list(tema.beceriler_arasi),
            "icerik_cercevesi": tema.icerik_cercevesi,
            "anahtar_kavramlar": list(tema.anahtar_kavramlar),
            "ogrenme_kanitlari": tema.ogrenme_kanitlari,
            "ogrenme_ciktilari": [
                {
                    "kod": c.kod,
                    "ifade": c.ifade,
                    "surec_bilesenleri": [
                        {"harf": b.harf, "ifade": b.ifade} for b in c.surec_bilesenleri
                    ],
                }
                for c in tema.ogrenme_ciktilari
            ],
        }
    ]
    metin = pdf_metni(
        pdf.html_pdfe(
            belge.yillik_plan_maarif(
                veri, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="MD"
            )
        )
    )
    assert "1. TEMA: YAŞAM" in metin
    assert "ALAN BECERİLERİ" in metin
    assert "FBAB1. Bilimsel Gözlem" in metin


# --- Word ---------------------------------------------------------------


def test_yillik_plan_docx(plan_satirlari) -> None:
    baytlar = word.yillik_plan_docx(
        plan_satirlari, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="Mehmet Derin"
    )
    xml = docx_metni(baytlar)
    assert "ÜNİTELENDİRİLMİŞ" in xml
    assert "BİY.9.1.1" in xml
    assert "Biyoloji Öğretmeni" in xml


def test_gunluk_plan_docx(program: m.Mufredat) -> None:
    tema = program.duzey(10).temalar[0]
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 10, 1),
        sube_adi="10-B",
        sinif=10,
        tema=tema,
        kazanimlar=list(tema.ogrenme_ciktilari[:1]),
        ders_saatleri=[3],
    )
    xml = docx_metni(word.gunluk_plan_docx(plan, okul="Okul", ogretmen="MD"))
    assert "GÜNLÜK DERS PLANI" in xml
    assert "10-B" in xml


# --- Excel --------------------------------------------------------------


def test_not_cizelgesi_xlsx() -> None:
    degerlendirmeler = [
        {"id": 1, "ad": "1. Yazılı", "donem": 1},
        {"id": 2, "ad": "Performans", "donem": 1},
    ]
    ogrenciler = [
        {
            "numara": "101",
            "ad_soyad": "Ayşe Yılmaz",
            "puanlar": {1: 80, 2: 90},
            "donem1": 85,
            "donem2": None,
            "yil_sonu": 85,
            "durum": "Geçti",
        }
    ]
    kitap = load_workbook(io.BytesIO(excel.not_cizelgesi_xlsx(ogrenciler, degerlendirmeler, sube_adi="9-A")))
    sayfa = kitap.active
    assert sayfa["B1"].value == "Adı Soyadı"
    assert sayfa["C1"].value == "1. Yazılı (1. dönem)"
    assert sayfa["B2"].value == "Ayşe Yılmaz"
    assert sayfa["C2"].value == 80


def test_excel_formul_enjeksiyonunu_metin_yapar() -> None:
    ogrenciler = [
        {
            "numara": "101",
            "ad_soyad": "=HYPERLINK(\"https://ornek.com\")",
            "puanlar": {},
            "donem1": None,
            "donem2": None,
            "yil_sonu": None,
            "durum": "",
        }
    ]
    kitap = load_workbook(
        io.BytesIO(excel.not_cizelgesi_xlsx(ogrenciler, [], sube_adi="9-A"))
    )
    hucre = kitap.active["B2"]
    assert hucre.data_type != "f"
    assert hucre.value.startswith("'=")


def test_devamsizlik_xlsx() -> None:
    kayitlar = [
        {
            "numara": "101",
            "ad_soyad": "Ayşe Yılmaz",
            "toplam_ders": 40,
            "yok_saat": 6,
            "izinli_saat": 2,
            "gec_saat": 1,
            "devam_orani": 85.0,
            "uyari": "Sınıra yaklaşıyor",
        }
    ]
    kitap = load_workbook(io.BytesIO(excel.devamsizlik_xlsx(kayitlar, sube_adi="9-A")))
    assert kitap.active["D2"].value == 6
    assert kitap.active["H2"].value == "Sınıra yaklaşıyor"


def test_yillik_plan_xlsx_ozet_sayfasi(plan_satirlari) -> None:
    kitap = load_workbook(
        io.BytesIO(excel.yillik_plan_xlsx(plan_satirlari, sube_adi="9-A", ogretim_yili="2026-2027"))
    )
    assert "Özet" in kitap.sheetnames
    ozet = kitap["Özet"]
    assert ozet["A2"].value == "2026-2027"
    assert ozet["E2"].value == 15  # 9. sınıfın kazanım sayısı


def test_kazanim_analizi_xlsx() -> None:
    ogrenciler = [
        {"numara": "101", "ad_soyad": "Ayşe Yılmaz", "kazanimlar": {"BİY.9.1.1": 80.0, "BİY.9.1.2": 40.0}}
    ]
    kitap = load_workbook(
        io.BytesIO(excel.kazanim_analizi_xlsx(ogrenciler, ["BİY.9.1.1", "BİY.9.1.2"], sube_adi="9-A"))
    )
    sayfa = kitap.active
    assert sayfa["C1"].value == "BİY.9.1.1"
    assert sayfa["E2"].value == 60.0


def _cizim_sag_kenari(baytlar: bytes) -> float:
    with pymupdf.open(stream=baytlar, filetype="pdf") as belge_nesnesi:
        cizimler = belge_nesnesi[0].get_drawings()
        return max(c["rect"].x1 for c in cizimler) if cizimler else 0.0


def test_tablolar_sayfa_disina_tasmaz(plan_satirlari, ornek_sinav: sn.Sinav) -> None:
    """Sütun genişliği verilirse Story tabloyu yazım alanının dışına itiyordu."""
    yatay_sinir = pymupdf.paper_rect("a4-l").width - 25
    dikey_sinir = pymupdf.paper_rect("a4").width - 25

    plan = pdf.html_pdfe(
        belge.yillik_plan_meb(
            plan_satirlari, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="MD"
        ),
        yatay=True,
    )
    assert _cizim_sag_kenari(plan) <= yatay_sinir

    anahtar = pdf.html_pdfe(belge.cevap_anahtari(ornek_sinav, okul="Okul"), yatay=True)
    assert _cizim_sag_kenari(anahtar) <= yatay_sinir

    kagit = pdf.html_pdfe(belge.sinav_kagidi(ornek_sinav, "A", okul="Okul", ogretmen="MD"))
    assert _cizim_sag_kenari(kagit) <= dikey_sinir


def test_baslik_hucrelerinde_harf_kaybolmaz(plan_satirlari) -> None:
    """Dar sütunda 'ALAN BECERİLERİ' → 'ALAN ECERİLERİ' olur gibi bir kırpma olmamalı."""
    metin = pdf_metni(
        pdf.html_pdfe(
            belge.yillik_plan_meb(
                plan_satirlari, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="MD"
            ),
            yatay=True,
        )
    )
    for baslik in ("Süreç Bileşenleri", "Yöntem ve", "Araç-Gereç", "Açıklama"):
        assert baslik in metin, f"{baslik} başlığı PDF'te bozulmuş"


def test_meb_planinda_yeni_sutunlar_var(plan_satirlari) -> None:
    """İdareye verilen planda beklenen iki sütun daha."""
    metin = pdf_metni(
        pdf.html_pdfe(
            belge.yillik_plan_meb(
                plan_satirlari, okul="Okul", sube_adi="9-A", ogretim_yili="2026-2027", ogretmen="MD"
            ),
            yatay=True,
        )
    )
    # Başlıklar dar sütunda satıra bölündüğü için kelime kelime aranır.
    for kelime in ("Derslerle", "İlişkilendirme", "Belirli", "Haftalar"):
        assert kelime in metin, f"{kelime} başlığı PDF'te yok"
    assert "Fizik" in metin, "disiplinler arası ilişki sütunu dolmalı"
