"""Dosya okuyucularının testleri — gerçek dosya biçimleri elde olmadığı için
yaygın yerleşimler örneklenerek sınanır."""

from __future__ import annotations

from pathlib import Path

import pytest
from openpyxl import Workbook

from ogretmen_cantasi.okuma import deneme, ders_programi, ogrenci_listesi, tablo


def excel_yaz(yol: Path, satirlar: list[list]) -> Path:
    kitap = Workbook()
    sayfa = kitap.active
    for satir in satirlar:
        sayfa.append(satir)
    kitap.save(yol)
    return yol


# --- tablo okuma --------------------------------------------------------


def test_excel_okunur(tmp_path: Path) -> None:
    yol = excel_yaz(tmp_path / "liste.xlsx", [["No", "Adı Soyadı"], [1, "Ayşe Yılmaz"]])
    okunan = tablo.tabloyu_oku(yol)
    assert okunan.satirlar[0] == ["No", "Adı Soyadı"]
    assert okunan.satirlar[1] == ["1", "Ayşe Yılmaz"]


def test_windows_turkce_csv_ve_eokul_basliklari_okunur(tmp_path: Path) -> None:
    yol = tmp_path / "eokul.csv"
    yol.write_bytes(
        "Öğrenci No;Adı Soyadı\r\n101;Çağrı Şen\r\n".encode("cp1254")
    )
    sonuc = ogrenci_listesi.listeyi_coz(tablo.tabloyu_oku(yol))
    assert [(o.numara, o.ad_soyad) for o in sonuc.ogrenciler] == [
        ("101", "Çağrı Şen")
    ]


def test_bilinmeyen_bicim_acik_hata(tmp_path: Path) -> None:
    yol = tmp_path / "dosya.docx"
    yol.write_text("x")
    with pytest.raises(tablo.OkunamadiError, match="Tanınmayan dosya biçimi"):
        tablo.tabloyu_oku(yol)


def test_bos_dosya_hata_verir(tmp_path: Path) -> None:
    yol = excel_yaz(tmp_path / "bos.xlsx", [])
    with pytest.raises(tablo.OkunamadiError, match="boş"):
        tablo.tabloyu_oku(yol)


# --- öğrenci listesi ----------------------------------------------------


def test_eokul_listesi_okunur(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "9a.xlsx",
        [
            ["T.C. Millî Eğitim Bakanlığı"],
            ["Sınıf: 9-A"],
            [],
            ["Okul No", "Adı Soyadı", "Cinsiyet"],
            [101, "Ayşe Yılmaz", "K"],
            [102, "Mehmet Kaya", "E"],
        ],
    )
    sonuc = ogrenci_listesi.listeyi_coz(tablo.tabloyu_oku(yol))
    assert sonuc.sube_adi == "9-A"
    assert [o.numara for o in sonuc.ogrenciler] == ["101", "102"]
    assert sonuc.ogrenciler[0].ad_soyad == "Ayşe Yılmaz"


def test_baslik_yoksa_sutunlar_tahmin_edilir(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "ham.xlsx",
        [[1, "Ayşe Yılmaz"], [2, "Mehmet Kaya"], [3, "Ali Demir"]],
    )
    sonuc = ogrenci_listesi.listeyi_coz(tablo.tabloyu_oku(yol))
    assert len(sonuc.ogrenciler) == 3
    assert any("tahmin" in u for u in sonuc.uyarilar)


def test_yinelenen_satir_bir_kez_alinir(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "yin.xlsx",
        [["No", "Adı Soyadı"], [1, "Ayşe Yılmaz"], [1, "Ayşe Yılmaz"]],
    )
    sonuc = ogrenci_listesi.listeyi_coz(tablo.tabloyu_oku(yol))
    assert len(sonuc.ogrenciler) == 1


def test_yapistirilan_metin_cozulur() -> None:
    sonuc = ogrenci_listesi.metinden_coz("101 Ayşe Yılmaz\n102. Mehmet Kaya\nAli Demir")
    assert [o.numara for o in sonuc.ogrenciler] == ["101", "102", ""]
    assert sonuc.ogrenciler[2].ad_soyad == "Ali Demir"


# --- ders programı ------------------------------------------------------


def test_gunler_sutunda_program(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "prog.xlsx",
        [
            ["2026-2027 Haftalık Ders Programı"],
            ["Saat", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma"],
            ["1. ders", "9-A", "", "12-A", "11-C", ""],
            ["2. ders", "9-A", "", "12-A", "11-C", ""],
            ["3. ders", "", "10-B", "", "", "9-B"],
        ],
    )
    sonuc = ders_programi.ders_programi_coz(tablo.tabloyu_oku(yol))
    assert sonuc.subeler == ["10-B", "11-C", "12-A", "9-A", "9-B"]
    assert sonuc.haftalik_saat("9-A") == 2
    assert sonuc.sube_ders_gunleri("9-A") == {1: 2}
    assert sonuc.sube_ders_gunleri("11-C") == {4: 2}


def test_gunler_satirda_program(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "devrik.xlsx",
        [
            ["Pazartesi", "9-A", "9-A", "", "11/C"],
            ["Salı", "", "10 B", "10 B", ""],
        ],
    )
    sonuc = ders_programi.ders_programi_coz(tablo.tabloyu_oku(yol))
    assert sonuc.haftalik_saat("9-A") == 2
    assert sonuc.haftalik_saat("11-C") == 1
    assert sonuc.haftalik_saat("10-B") == 2


def test_taninmayan_program_uyari_verir(tmp_path: Path) -> None:
    yol = excel_yaz(tmp_path / "karisik.xlsx", [["bir", "iki"], ["üç", "dört"]])
    sonuc = ders_programi.ders_programi_coz(tablo.tabloyu_oku(yol))
    assert not sonuc.hucreler
    assert "elle işaretleyebilirsiniz" in sonuc.uyarilar[0]


@pytest.mark.parametrize(
    ("yazim", "beklenen"),
    [("9-A", "9-A"), ("11/C", "11-C"), ("10 B", "10-B"), ("12A", "12-A"), ("Fizik", "")],
)
def test_sube_yazimlari(yazim: str, beklenen: str) -> None:
    assert ders_programi.sube_ayikla(yazim) == beklenen


# --- deneme sonuçları ---------------------------------------------------


def test_net_hesabi_dortte_bir_goturur() -> None:
    assert deneme.net_hesapla(10, 4) == 9.0
    assert deneme.net_hesapla(0, 8) == 0.0


def test_deneme_dosyasi_biyoloji_sutunlarini_secer(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "deneme.xlsx",
        [
            ["Deneme 1"],
            ["No", "Adı Soyadı", "Fizik D", "Fizik Y", "Biyoloji", "Doğru", "Yanlış", "Boş"],
            [101, "Ayşe Yılmaz", 5, 2, "", 10, 2, 1],
            [102, "Mehmet Kaya", 3, 4, "", 8, 4, 1],
        ],
    )
    sonuc = deneme.denemeyi_coz(tablo.tabloyu_oku(yol))
    assert len(sonuc.satirlar) == 2
    assert sonuc.satirlar[0].dogru == 10
    assert sonuc.satirlar[0].net == 9.5


def test_hazir_net_sutunu_kullanilir(tmp_path: Path) -> None:
    yol = excel_yaz(
        tmp_path / "net.xlsx",
        [["Adı Soyadı", "Doğru", "Yanlış", "Net"], ["Ayşe Yılmaz", 10, 4, "8,75"]],
    )
    sonuc = deneme.denemeyi_coz(tablo.tabloyu_oku(yol))
    assert sonuc.satirlar[0].net == 8.75


def test_basliksiz_deneme_dosyasi_uyari_verir(tmp_path: Path) -> None:
    yol = excel_yaz(tmp_path / "ham.xlsx", [["Ayşe", 1, 2], ["Mehmet", 3, 4]])
    sonuc = deneme.denemeyi_coz(tablo.tabloyu_oku(yol))
    assert not sonuc.satirlar
    assert sonuc.uyarilar


def test_uc_harfli_adaylar_ekli_basliklarla_eslesir() -> None:
    """"Boş Sayısı" başlığı 4 harf eşiğinde bulunamıyor ve boş sessizce 0
    yazılıyordu; üç harfli "boş"/"net" içerme hakkını korumalı, tek harfli
    "y" ise "Adı Soyadı"yı hâlâ ele geçirememeli."""
    basliklar = ["Öğrenci No", "Adı Soyadı", "Doğru Sayısı", "Yanlış Sayısı", "Boş Sayısı", "Net Sayısı"]
    assert tablo.sutun_bul(basliklar, ("boş", "bos")) == 4
    assert tablo.sutun_bul(basliklar, ("net",)) == 5
    assert tablo.sutun_bul(basliklar, ("y",)) == -1
