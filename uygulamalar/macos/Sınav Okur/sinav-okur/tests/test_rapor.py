"""excel_dokum: not dökümü Excel çıktısının yapısı ve dayanıklılığı."""
import pytest

pytest.importorskip("openpyxl")
from openpyxl import load_workbook

from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.rapor import excel_dokum
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu


def _kagit(sinav, ogrenci_ad, puan_orani=1.0):
    kutular = []
    for soru in sinav.sorular:
        kutular.append(
            KutuSonucu(
                soru_no=soru.no,
                tanima=TanimaSonucu(
                    metin="cevap", guven=0.9,
                    uzlasma_guveni=0.9, bagimsiz_motor_sayisi=2,
                ),
                puan=PuanSonucu(
                    puan=round(soru.puan * puan_orani, 2),
                    max_puan=soru.puan,
                    guven=0.9,
                ),
            )
        )
    return KagitSonucu(
        sinav_kimlik=sinav.kimlik,
        islenen_sayfalar=[1],
        kutular=kutular,
    )


def test_excel_sayfalari_ve_basliklar(depo, ornek_sinav, tmp_path):
    depo.sinav_kaydet(ornek_sinav)
    depo.kagit_kaydet(_kagit(ornek_sinav, "Ayşe"), ogrenci_ad="Ayşe")
    depo.kagit_kaydet(_kagit(ornek_sinav, "Mehmet", 0.5), ogrenci_ad="Mehmet")

    yol = excel_dokum(depo, ornek_sinav.kimlik, tmp_path / "rapor.xlsx")
    wb = load_workbook(yol)
    assert wb.sheetnames == [
        "Notlar", "Soru Analizi", "İnceleme Kuyruğu", "Program Gerekçeleri",
        "Dağılım", "Kazanımlar", "Psikometri", "İtirazlar",
    ]
    ws = wb["Notlar"]
    basliklar = [h.value for h in ws[1]]
    assert basliklar[:5] == ["Ad", "Soyad", "Numara", "Sınıf", "Şube"]
    # Her soru için "S{no} ({puan})" sütunu
    for soru in ornek_sinav.sorular:
        assert f"S{soru.no} ({soru.puan:g})" in basliklar
    assert "Toplam" in basliklar and "%" in basliklar


def test_excel_ogrenci_satiri_toplam_ve_yuzde(depo, ornek_sinav, tmp_path):
    depo.sinav_kaydet(ornek_sinav)
    depo.kagit_kaydet(_kagit(ornek_sinav, "Ayşe"), ogrenci_ad="Ayşe")

    yol = excel_dokum(depo, ornek_sinav.kimlik, tmp_path / "rapor.xlsx")
    ws = load_workbook(yol)["Notlar"]
    satir = [h.value for h in ws[2]]
    assert satir[0] == "Ayşe"
    # Tam puanlı kâğıt → %100
    assert satir[-1] == 100.0
    assert satir[-3] == round(ornek_sinav.toplam_puan, 2)


def test_excel_kagitsiz_sinav_coker_mez(depo, ornek_sinav, tmp_path):
    depo.sinav_kaydet(ornek_sinav)
    yol = excel_dokum(depo, ornek_sinav.kimlik, tmp_path / "bos.xlsx")
    wb = load_workbook(yol)
    ws = wb["Notlar"]
    # Yalnız başlık satırı olmalı
    assert ws.max_row == 1


def test_excel_program_gerekceleri_kutu_basina(depo, ornek_sinav, tmp_path):
    depo.sinav_kaydet(ornek_sinav)
    depo.kagit_kaydet(_kagit(ornek_sinav, "Ayşe"), ogrenci_ad="Ayşe")
    yol = excel_dokum(depo, ornek_sinav.kimlik, tmp_path / "rapor.xlsx")
    wg = load_workbook(yol)["Program Gerekçeleri"]
    # Başlık + her soru için bir satır
    assert wg.max_row == 1 + len(ornek_sinav.sorular)


def test_psikometri_sayfasi_yetersiz_ornekte_sayi_uydurmaz(
    depo, ornek_sinav, tmp_path
):
    """İki kâğıtla güvenilirlik katsayısı yazmak yanlış güven üretir."""
    depo.sinav_kaydet(ornek_sinav)
    depo.kagit_kaydet(_kagit(ornek_sinav, "Ayşe"), ogrenci_ad="Ayşe")
    depo.kagit_kaydet(_kagit(ornek_sinav, "Mehmet", 0.5), ogrenci_ad="Mehmet")

    yol = excel_dokum(depo, ornek_sinav.kimlik, tmp_path / "rapor.xlsx")
    ws = load_workbook(yol)["Psikometri"]

    satirlar = {r[0].value: (r[1].value, r[2].value) for r in ws.iter_rows(min_row=2)}
    deger, yorum = satirlar["Güvenilirlik (Cronbach α)"]
    assert deger is None
    assert "Yetersiz örneklem" in yorum
