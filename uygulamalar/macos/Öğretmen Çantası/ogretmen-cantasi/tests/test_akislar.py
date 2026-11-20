"""Dosya yükleme, yedekleme ve komut satırı akışlarının testleri.

Bu yollar kullanıcının ilk gün karşılaştığı yollar: sınıf listesini yükleme,
ders programını yükleme, deneme sonucunu yükleme, yedek alma. Kırıldıklarında
program açılıyor ama kullanılamıyor oluyor.
"""

from __future__ import annotations

import io
import os
import re
from pathlib import Path

import pytest
from openpyxl import Workbook

from ogretmen_cantasi import ayarlar, cli, depo, servis
from ogretmen_cantasi.okuma import tablo as tablo_okuma
from ogretmen_cantasi.web import sunucu as web_sunucu


def excel_baytlari(satirlar: list[list]) -> bytes:
    kitap = Workbook()
    sayfa = kitap.active
    for satir in satirlar:
        sayfa.append(satir)
    tampon = io.BytesIO()
    kitap.save(tampon)
    return tampon.getvalue()


@pytest.fixture
def kurulu(istemci):
    istemci.post(
        "/kurulum/yil",
        data={
            "ad": "2026-2027",
            "d1_baslangic": "2026-09-14",
            "d1_bitis": "2027-01-16",
            "d2_baslangic": "2027-02-02",
            "d2_bitis": "2027-06-18",
        },
        follow_redirects=False,
    )
    istemci.post("/kurulum/sube", data={"ad": "9-A", "sinif": 9}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        return servis.subeleri_oku(baglanti, yil.id)[0]
    finally:
        baglanti.close()


# --- dosya yükleme akışları ---------------------------------------------


def test_ogrenci_listesi_excelden_yuklenir(istemci, kurulu) -> None:
    icerik = excel_baytlari(
        [
            ["T.C. Millî Eğitim Bakanlığı"],
            ["Sınıf: 9-A"],
            [],
            ["Okul No", "Adı Soyadı", "Cinsiyet"],
            [101, "Ayşe Yılmaz", "K"],
            [102, "Mehmet Kaya", "E"],
            [103, "Ali Demir", "E"],
        ]
    )
    yanit = istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={"dosya": ("9a.xlsx", icerik, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    paket = re.search(r'name="paket" value="([^"]+)"', yanit.text)
    assert paket
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/aktar",
        data={"paket": paket.group(1)},
        follow_redirects=False,
    )
    sayfa = istemci.get(f"/sube/{kurulu.id}").text
    assert "Ayşe Yılmaz" in sayfa
    assert "Ali Demir" in sayfa


def test_bozuk_dosya_akisi_kirmadan_uyari_verir(istemci, kurulu) -> None:
    yanit = istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={"dosya": ("liste.rtf", b"bu bir tablo degil", "application/rtf")},
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    assert "Tanınmayan dosya biçimi" in yanit.text


def test_ders_programi_dosyadan_yuklenip_subeleri_kurar(istemci, kurulu) -> None:
    icerik = excel_baytlari(
        [
            ["2026-2027 Haftalık Ders Programı"],
            ["Saat", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma"],
            ["1. ders", "9-A", "", "12-A", "11-C", ""],
            ["2. ders", "9-A", "", "12-A", "11-C", ""],
            ["3. ders", "", "10-B", "", "", "9-B"],
        ]
    )
    yanit = istemci.post(
        "/kurulum/program/yukle",
        files={"dosya": ("prog.xlsx", icerik, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        follow_redirects=True,
    )
    assert yanit.status_code == 200

    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        subeler = {s.ad: s for s in servis.subeleri_oku(baglanti, yil.id)}
        # Programda geçen ama daha önce tanımlanmamış şubeler de açılmalı.
        assert {"9-A", "9-B", "10-B", "11-C", "12-A"} <= set(subeler)
        assert servis.sube_ders_gunleri(baglanti, subeler["9-A"].id) == {1: 2}
        assert subeler["12-A"].sinif == 12
    finally:
        baglanti.close()


def test_deneme_dosyasi_isimleri_eslestirerek_yuklenir(istemci, kurulu) -> None:
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir",
        data={"metin": "101 Ayşe Yılmaz\n102 Mehmet Kaya"},
        follow_redirects=False,
    )
    icerik = excel_baytlari(
        [
            ["Deneme 1"],
            ["No", "Adı Soyadı", "Biyoloji", "Doğru", "Yanlış", "Boş"],
            [101, "AYŞE YILMAZ", "", 10, 4, 2],
            [102, "Mehmet Kaya", "", 8, 4, 1],
            [999, "Bilinmeyen Öğrenci", "", 5, 5, 3],
        ]
    )
    yanit = istemci.post(
        f"/denemeler/{kurulu.id}/yukle",
        data={"ad": "Deneme 1", "tarih": "2026-10-10", "yayin": "X Yayınları"},
        files={"dosya": ("deneme.xlsx", icerik, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")},
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    paket = re.search(r'name="paket" value="([^"]+)"', yanit.text)
    assert paket
    baglanti = web_sunucu._baglanti()
    try:
        eslesmeler = {
            o["ad_soyad"]: o["id"] for o in servis.ogrencileri_oku(baglanti, kurulu.id)
        }
    finally:
        baglanti.close()
    istemci.post(
        f"/denemeler/{kurulu.id}/aktar",
        data={
            "paket": paket.group(1),
            "eslesme_0": eslesmeler["Ayşe Yılmaz"],
            "eslesme_1": eslesmeler["Mehmet Kaya"],
            "eslesme_2": "",
        },
        follow_redirects=False,
    )
    sayfa = istemci.get(f"/denemeler/{kurulu.id}").text
    assert "Deneme 1" in sayfa
    assert "9.0" in sayfa  # 10 doğru, 4 yanlış → net 9
    # Sınıfta olmayan isim sessizce yutulmamalı.
    assert "Eşleşmeyen" in yanit.text


# --- tablo okuyucusunun diğer biçimleri ---------------------------------


def test_csv_okunur(tmp_path: Path) -> None:
    yol = tmp_path / "liste.csv"
    yol.write_text("No;Adı Soyadı\n101;Ayşe Yılmaz\n", encoding="utf-8")
    okunan = tablo_okuma.tabloyu_oku(yol)
    assert okunan.satirlar[1] == ["101", "Ayşe Yılmaz"]


def test_yapistirilan_metin_tablo_olur() -> None:
    okunan = tablo_okuma.tabloyu_oku(metin="No,Ad\n101,Ayşe Yılmaz\n")
    assert okunan.satirlar[1] == ["101", "Ayşe Yılmaz"]
    assert okunan.kaynak == "yapıştırılan metin"


def test_pdf_okunur(tmp_path: Path) -> None:
    import pymupdf

    belge = pymupdf.open()
    sayfa = belge.new_page()
    sayfa.insert_text((60, 90), "Pazartesi     9-A     9-A")
    yol = tmp_path / "prog.pdf"
    belge.save(yol)
    belge.close()

    okunan = tablo_okuma.tabloyu_oku(yol)
    assert any("Pazartesi" in h for satir in okunan.satirlar for h in satir)


def test_dosya_da_metin_de_verilmezse_hata() -> None:
    with pytest.raises(tablo_okuma.OkunamadiError, match="verilmedi"):
        tablo_okuma.tabloyu_oku()


# --- yedekleme -----------------------------------------------------------


def test_yedek_alinir_ve_eskiler_temizlenir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path))
    veritabani = ayarlar.veritabani_yolu()
    depo.baglan(veritabani).close()

    for sira in range(5):
        # Damga saniye çözünürlüklü; farklı ad garantisi için elle yazılıyor.
        hedef = ayarlar.yedek_dizini()
        hedef.mkdir(parents=True, exist_ok=True)
        (hedef / f"veri-2026010{sira}-000000.db").write_bytes(b"eski")

    yeni = depo.yedekle(sakla=3)
    assert yeni is not None and yeni.is_file()
    kalanlar = sorted(p.name for p in ayarlar.yedek_dizini().glob("veri-*.db"))
    assert len(kalanlar) == 3
    assert yeni.name in kalanlar, "en yeni yedek silinmemeli"


def test_veritabani_yoksa_yedek_yok(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path / "olmayan"))
    assert depo.yedekle() is None


# --- komut satırı --------------------------------------------------------


def test_cli_durum_bilgi_yazar(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path))
    monkeypatch.setattr("sys.argv", ["ogretmen-cantasi", "durum"])
    assert cli.main() == 0
    cikti = capsys.readouterr().out
    assert "Veritabanı" in cikti
    assert "ogrenci" in cikti


def test_cli_yedek_alir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path))
    depo.baglan().close()
    monkeypatch.setattr("sys.argv", ["ogretmen-cantasi", "yedek"])
    assert cli.main() == 0
    assert "Yedek:" in capsys.readouterr().out


# --- kötü girdiye dayanıklılık ------------------------------------------


def test_dosya_adiyla_veritabani_silinemez(istemci, kurulu, tmp_path: Path) -> None:
    """"../veri.db" adlı bir yükleme veritabanının üstüne yazıp siliyordu."""
    veritabani = tmp_path / "veri.db"
    onceki_boyut = veritabani.stat().st_size
    icerik = excel_baytlari([["No", "Adı Soyadı"], [101, "Ayşe Yılmaz"]])

    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={"dosya": ("../veri.db", icerik, "application/octet-stream")},
        follow_redirects=True,
    )
    assert veritabani.is_file(), "veritabanı silinmiş"
    assert veritabani.stat().st_size >= onceki_boyut
    # Uygulama hâlâ çalışmalı.
    assert istemci.get(f"/sube/{kurulu.id}").status_code == 200


def test_mutlak_yollu_dosya_adi_disari_yazmaz(istemci, kurulu, tmp_path: Path) -> None:
    hedef = tmp_path / "disarda.txt"
    icerik = excel_baytlari([["No", "Adı Soyadı"], [101, "Ayşe Yılmaz"]])
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={"dosya": (str(hedef), icerik, "application/octet-stream")},
        follow_redirects=True,
    )
    assert not hedef.exists()


def test_bozuk_excel_500_vermez(istemci, kurulu) -> None:
    yanit = istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={"dosya": ("liste.xlsx", b"bu gecerli bir xlsx degil", "application/vnd.ms-excel")},
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    assert "okunamadı" in yanit.text.casefold() or "biçim" in yanit.text.casefold()


def test_turkce_karakterli_sube_adiyla_indirme_calisir(istemci, kurulu) -> None:
    """Content-Disposition latin-1 kodlanıyor; "İ" ham hâlde 500 veriyordu."""
    istemci.post("/kurulum/sube", data={"ad": "9-İ", "sinif": 9}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        sube = next(s for s in servis.subeleri_oku(baglanti, yil.id) if s.ad == "9-İ")
    finally:
        baglanti.close()

    for adres in (
        f"/plan/{sube.id}/indir?bicim=pdf",
        f"/plan/{sube.id}/indir?bicim=xlsx",
        f"/notlar/{sube.id}/indir",
    ):
        yanit = istemci.get(adres)
        assert yanit.status_code == 200, adres


def test_gecersiz_not_degeri_mevcut_notu_silmez(istemci, kurulu) -> None:
    """"85x" yazınca kayıtlı 85 puan sessizce siliniyordu."""
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir",
        data={"metin": "101 Ayşe Yılmaz"},
        follow_redirects=False,
    )
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "1. Yazılı", "tur": "yazili", "donem": 1},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        d = servis.degerlendirmeleri_oku(baglanti, kurulu.id)[0]["id"]
        o = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    istemci.post(f"/notlar/{kurulu.id}/kaydet", data={f"n_{d}_{o}": "85"}, follow_redirects=False)
    yanit = istemci.post(
        f"/notlar/{kurulu.id}/kaydet", data={f"n_{d}_{o}": "85x"}, follow_redirects=True
    )
    assert "kabul edilmedi" in yanit.text

    satirlar, _ = servis.not_tablosu(web_sunucu._baglanti(), kurulu.id)
    assert satirlar[0]["puanlar"].get(d) == 85, "geçersiz girdi eski notu silmemeli"


def test_aralik_disi_not_kabul_edilmez(istemci, kurulu) -> None:
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir", data={"metin": "101 Ayşe Yılmaz"}, follow_redirects=False
    )
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "1. Yazılı", "tur": "yazili", "donem": 1},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        d = servis.degerlendirmeleri_oku(baglanti, kurulu.id)[0]["id"]
        o = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    istemci.post(f"/notlar/{kurulu.id}/kaydet", data={f"n_{d}_{o}": "850"}, follow_redirects=False)
    satirlar, _ = servis.not_tablosu(web_sunucu._baglanti(), kurulu.id)
    assert satirlar[0]["donem1"] is None, "850 puan kaydedilmemeli"


def test_bos_birakilan_not_silinir(istemci, kurulu) -> None:
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir", data={"metin": "101 Ayşe Yılmaz"}, follow_redirects=False
    )
    istemci.post(
        f"/notlar/{kurulu.id}/degerlendirme",
        data={"ad": "1. Yazılı", "tur": "yazili", "donem": 1},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        d = servis.degerlendirmeleri_oku(baglanti, kurulu.id)[0]["id"]
        o = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()
    istemci.post(f"/notlar/{kurulu.id}/kaydet", data={f"n_{d}_{o}": "85"}, follow_redirects=False)
    istemci.post(f"/notlar/{kurulu.id}/kaydet", data={f"n_{d}_{o}": ""}, follow_redirects=False)
    satirlar, _ = servis.not_tablosu(web_sunucu._baglanti(), kurulu.id)
    assert satirlar[0]["puanlar"] == {}


def test_silinen_ogrenci_yeniden_yuklenince_geri_gelir(istemci, kurulu) -> None:
    """Yanlışlıkla çıkarılan öğrenci listeyi yeniden yükleyince dönmeliydi.

    Ad, şablondaki örnek metinlerden farklı seçildi: "Ayşe Yılmaz" yapıştırma
    kutusunun yer tutucusunda geçtiği için testi yanlışlıkla geçiriyordu.
    """
    ad = "Nurhayat Özdemirci"
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir", data={"metin": f"101 {ad}"}, follow_redirects=False
    )
    baglanti = web_sunucu._baglanti()
    try:
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    istemci.post(f"/sube/{kurulu.id}/ogrenci/{ogrenci}/sil", follow_redirects=False)
    assert ad not in istemci.get(f"/sube/{kurulu.id}").text

    eklenen = istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir", data={"metin": f"101 {ad}"}, follow_redirects=True
    )
    assert "1 öğrenci eklendi" in eklenen.text
    assert ad in istemci.get(f"/sube/{kurulu.id}").text


def test_ondalik_virgullu_tema_yuzdesi_calisir(istemci, kurulu) -> None:
    for kazanim in ("BİY.9.1.1", "BİY.9.2.1"):
        istemci.post(
            "/sorular/ekle",
            data={"sinif": 9, "kazanim_kodu": kazanim, "metin": f"Soru {kazanim}", "rubrik": "Tam"},
            follow_redirects=False,
        )
    yanit = istemci.post(
        f"/sinavlar/{kurulu.id}/uret",
        data={"ad": "Yazılı", "soru_sayisi": 2, "t_BİY.9.1": "60,5", "t_BİY.9.2": "39,5"},
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    assert "Yazılı" in istemci.get(f"/sinavlar/{kurulu.id}").text


def test_sayi_olmayan_ayar_not_defterini_kapatmaz(istemci, kurulu) -> None:
    yanit = istemci.post(
        "/ayarlar", data={"donem_basina_yazili": "iki"}, follow_redirects=True
    )
    assert "kabul edilmeyenler" in yanit.text
    assert istemci.get(f"/notlar/{kurulu.id}").status_code == 200


def test_bozuk_donem_tarihleri_reddedilir(istemci) -> None:
    yanit = istemci.post(
        "/kurulum/yil",
        data={
            "ad": "2030-2031",
            "d1_baslangic": "2031-01-10",
            "d1_bitis": "2030-09-14",
            "d2_baslangic": "2031-02-02",
            "d2_bitis": "2031-06-18",
        },
        follow_redirects=True,
    )
    assert "sırayla artmalı" in yanit.text


def test_olmayan_sinav_kimligi_500_vermez(istemci, kurulu) -> None:
    assert istemci.get("/sinav/9999", follow_redirects=False).status_code == 303


def test_12_sinif_indirmeleri_500_vermez(istemci, kurulu) -> None:
    """12. sınıf 2018 programına tabi ve o dosya henüz yok."""
    istemci.post("/kurulum/sube", data={"ad": "12-A", "sinif": 12}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        oniki = next(s for s in servis.subeleri_oku(baglanti, yil.id) if s.ad == "12-A")
    finally:
        baglanti.close()

    for adres in (f"/plan/{oniki.id}/indir?bicim=pdf", f"/gunluk/{oniki.id}", f"/plan/{oniki.id}"):
        assert istemci.get(adres, follow_redirects=True).status_code == 200, adres
    assert istemci.post(f"/plan/{oniki.id}/uret", follow_redirects=True).status_code == 200


def test_sube_sinifi_degisince_mufredat_surumu_guncellenir(baglanti_yok=None) -> None:
    from ogretmen_cantasi import takvim as tk

    baglanti = depo.baglan(":memory:")
    try:
        ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
        yil = servis.ogretim_yili_kur(baglanti, ad, d1, d2)
        sube_id = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
        assert servis.sube_al(baglanti, sube_id).mufredat_surumu == "maarif_2024"
        servis.sube_ekle(baglanti, yil.id, "9-A", 12, ogretim_yili_adi=yil.ad)
        assert servis.sube_al(baglanti, sube_id).mufredat_surumu == "mfp_2018"
    finally:
        baglanti.close()


def test_izgarada_taninmayan_ad_programi_silmez(istemci, kurulu) -> None:
    """Tek yazım hatası bütün ders programını siliyordu."""
    istemci.post(
        "/kurulum/program/izgara",
        data={"h_1_1": "9-A", "h_1_2": "9-A", "h_4_5": "9-A"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 2, 4: 1}
    finally:
        baglanti.close()

    # Tüm hücreler yanlış yazıldı: program DEĞİŞMEMELİ.
    yanit = istemci.post(
        "/kurulum/program/izgara", data={"h_1_1": "9-AA"}, follow_redirects=True
    )
    assert "DEĞİŞTİRİLMEDİ" in yanit.text
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 2, 4: 1}
    finally:
        baglanti.close()


def test_izgarada_kismi_yazim_hatasi_uyari_verir(istemci, kurulu) -> None:
    yanit = istemci.post(
        "/kurulum/program/izgara",
        data={"h_1_1": "9-A", "h_1_2": "9-AA"},
        follow_redirects=True,
    )
    assert "tanınmadı" in yanit.text
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 1}
    finally:
        baglanti.close()


def test_izgaradan_cikarilan_sube_temizlenir(istemci, kurulu) -> None:
    istemci.post("/kurulum/sube", data={"ad": "10-B", "sinif": 10}, follow_redirects=False)
    istemci.post(
        "/kurulum/program/izgara",
        data={"h_1_1": "9-A", "h_2_1": "10-B"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        onb = next(s for s in servis.subeleri_oku(baglanti, yil.id) if s.ad == "10-B")
        assert servis.sube_ders_gunleri(baglanti, onb.id) == {2: 1}
    finally:
        baglanti.close()

    # 10-B ızgaradan kaldırıldı: onun programı da temizlenmeli.
    istemci.post("/kurulum/program/izgara", data={"h_1_1": "9-A"}, follow_redirects=False)
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, onb.id) == {}
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 1}
    finally:
        baglanti.close()


def test_sorunun_puanindan_fazlasi_kabul_edilmez(istemci, kurulu) -> None:
    """25 puanlık soruya 52 yazılınca kazanım analizi %208 raporluyordu."""
    from ogretmen_cantasi import servis_olcme as so

    for kazanim in ("BİY.9.1.1", "BİY.9.1.2", "BİY.9.1.3", "BİY.9.1.4"):
        istemci.post(
            "/sorular/ekle",
            data={"sinif": 9, "kazanim_kodu": kazanim, "metin": f"Soru {kazanim}", "rubrik": "Tam"},
            follow_redirects=False,
        )
    istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yapistir", data={"metin": "101 Ayşe Yılmaz"}, follow_redirects=False
    )
    istemci.post(
        f"/sinavlar/{kurulu.id}/uret",
        data={"ad": "Yazılı", "soru_sayisi": 4, "t_BİY.9.1": "100"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        sinav_id = so.sinavlari_oku(baglanti, kurulu.id)[0]["id"]
        sinav = so.sinavi_yukle(baglanti, sinav_id)
        ogrenci = servis.ogrencileri_oku(baglanti, kurulu.id)[0]["id"]
    finally:
        baglanti.close()

    soru = sinav.sorular[0]
    assert soru.puan == 25
    yanit = istemci.post(
        f"/sinav/{sinav_id}/puanla",
        data={f"p_{soru.id}_{ogrenci}": "52"},
        follow_redirects=True,
    )
    assert "kabul edilmedi" in yanit.text

    baglanti = web_sunucu._baglanti()
    try:
        analiz = so.sinav_kazanim_analizi(baglanti, sinav_id)
        assert not analiz["ogrenciler"], "aralık dışı puan kaydedilmemeli"
    finally:
        baglanti.close()

    # Sınırdaki değer kabul edilmeli.
    istemci.post(
        f"/sinav/{sinav_id}/puanla", data={f"p_{soru.id}_{ogrenci}": "25"}, follow_redirects=False
    )
    baglanti = web_sunucu._baglanti()
    try:
        analiz = so.sinav_kazanim_analizi(baglanti, sinav_id)
        assert analiz["sinif"][soru.kazanim_kodu].yuzde == 100.0
    finally:
        baglanti.close()


def test_izgara_gostermedigi_saatleri_silmez(istemci, kurulu) -> None:
    """İkili öğretimin 9-10. saatleri, ızgara kaydedilince siliniyordu."""
    baglanti = web_sunucu._baglanti()
    try:
        servis.ders_programi_yaz(
            baglanti, [(kurulu.id, 1, 1), (kurulu.id, 3, 2), (kurulu.id, 5, 9), (kurulu.id, 5, 10)]
        )
        assert sum(servis.sube_ders_gunleri(baglanti, kurulu.id).values()) == 4
    finally:
        baglanti.close()

    # Izgara artık 10 saat göstermeli; hiçbir şey değiştirmeden kaydet.
    sayfa = istemci.get("/kurulum").text
    assert "10. ders" in sayfa, "kayıtlı en yüksek saat ızgarada görünmeli"

    istemci.post(
        "/kurulum/program/izgara",
        data={"h_1_1": "9-A", "h_3_2": "9-A", "h_5_9": "9-A", "h_5_10": "9-A"},
        follow_redirects=False,
    )
    baglanti = web_sunucu._baglanti()
    try:
        assert sum(servis.sube_ders_gunleri(baglanti, kurulu.id).values()) == 4
    finally:
        baglanti.close()


def test_silme_araligi_sunucuda_hesaplanir(baglanti_yok=None) -> None:
    """Aralık istemciden gelmez; `ders_programi_yaz` dışındakine dokunmamalı."""
    from ogretmen_cantasi import takvim as tk

    baglanti = depo.baglan(":memory:")
    try:
        ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
        yil = servis.ogretim_yili_kur(baglanti, ad, d1, d2)
        sid = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
        servis.ders_programi_yaz(baglanti, [(sid, 1, 1), (sid, 5, 10)])
        assert servis.izgara_saat_sayisi(baglanti, yil.id) == 10

        # Dar bir aralıkla yazıldığında dışarıdaki saat korunmalı.
        servis.ders_programi_yaz(
            baglanti, [(sid, 1, 1)], temizlenecek_subeler=[sid], saat_araligi=(1, 8)
        )
        assert servis.sube_ders_gunleri(baglanti, sid) == {1: 1, 5: 1}
    finally:
        baglanti.close()


def test_izgara_alani_gelmeyen_istek_programi_silmez(istemci, kurulu) -> None:
    baglanti = web_sunucu._baglanti()
    try:
        servis.ders_programi_yaz(baglanti, [(kurulu.id, 1, 1), (kurulu.id, 1, 2)])
    finally:
        baglanti.close()

    yanit = istemci.post("/kurulum/program/izgara", data={}, follow_redirects=True)
    assert "değiştirilmedi" in yanit.text
    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 2}
    finally:
        baglanti.close()


def test_durdur_kayit_yoksa_yanlis_doner(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    monkeypatch.setattr(ayarlar, "gunluk_dizini", lambda: tmp_path)
    assert cli.sunucuyu_durdur() is False
    assert "kaydı yok" in capsys.readouterr().out


def test_durdur_olu_pidi_temizler(tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    monkeypatch.setattr(ayarlar, "gunluk_dizini", lambda: tmp_path)
    pid_dosyasi = tmp_path / "server.pid"
    pid_dosyasi.write_text("999999")  # var olmayan süreç
    assert cli.sunucuyu_durdur() is False
    assert not pid_dosyasi.exists(), "ölü pid dosyası temizlenmeli"
    assert "zaten kapalı" in capsys.readouterr().out


def test_durdur_bozuk_pid_dosyasini_temizler(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(ayarlar, "gunluk_dizini", lambda: tmp_path)
    (tmp_path / "server.pid").write_text("bu bir sayı değil")
    assert cli.sunucuyu_durdur() is False
    assert not (tmp_path / "server.pid").exists()


def test_dar_izgara_gonderimi_disaridaki_saati_silmez(istemci, kurulu) -> None:
    """Silme aralığı gönderilen formdan gelmeli, veritabanının hâlinden değil.

    Senaryo: öğretmen kurulum sayfasını 8 sütunken açık bırakır, bu arada
    okulun 10 saatlik programı yüklenir, sonra o eski sekmedeki ızgarayı
    kaydeder. Aralık veritabanından hesaplanırsa ızgaranın hiç görmediği
    10. saat siliniyordu.
    """
    baglanti = web_sunucu._baglanti()
    try:
        servis.ders_programi_yaz(baglanti, [(kurulu.id, 1, 1), (kurulu.id, 5, 10)])
        assert servis.izgara_saat_sayisi(baglanti, servis.aktif_yil(baglanti).id) == 10
    finally:
        baglanti.close()

    # Yalnız 8 sütunluk bir ızgara gönder (9. ve 10. saat hiç yok).
    dar_izgara = {f"h_{gun}_{saat}": "" for gun in range(1, 6) for saat in range(1, 9)}
    dar_izgara["h_1_1"] = "9-A"
    istemci.post("/kurulum/program/izgara", data=dar_izgara, follow_redirects=False)

    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 1, 5: 1}, (
            "ızgaranın göndermediği 10. ders silinmemeli"
        )
    finally:
        baglanti.close()


def test_genis_izgara_gonderimi_kendi_araliginda_temizler(istemci, kurulu) -> None:
    """10 sütunluk ızgara gönderildiğinde 10. saat temizlenebilmeli."""
    baglanti = web_sunucu._baglanti()
    try:
        servis.ders_programi_yaz(baglanti, [(kurulu.id, 1, 1), (kurulu.id, 5, 10)])
    finally:
        baglanti.close()

    genis = {f"h_{gun}_{saat}": "" for gun in range(1, 6) for saat in range(1, 11)}
    genis["h_1_1"] = "9-A"
    istemci.post("/kurulum/program/izgara", data=genis, follow_redirects=False)

    baglanti = web_sunucu._baglanti()
    try:
        assert servis.sube_ders_gunleri(baglanti, kurulu.id) == {1: 1}
    finally:
        baglanti.close()


def test_yedek_budamasi_ada_gore_degil_yasa_gore(tmp_path: Path, monkeypatch) -> None:
    """"gecis-oncesi" alfabetik olarak "veri"den önce gelir; budama ada göre
    sıralarsa az önce alınan geçiş yedeğini en eski sanıp siler."""
    monkeypatch.setenv("OGRETMEN_CANTASI_VERI", str(tmp_path))
    depo.baglan(tmp_path / "veri.db").close()

    yedek_dizin = ayarlar.yedek_dizini()
    yedek_dizin.mkdir(parents=True, exist_ok=True)
    eski_zaman = 1_600_000_000
    for sira in range(5):
        eski = yedek_dizin / f"veri-2026010{sira}-000000-000000.db"
        eski.write_bytes(b"eski")
        os.utime(eski, (eski_zaman + sira, eski_zaman + sira))

    yeni = depo.yedekle(tmp_path / "veri.db", sakla=3, etiket="gecis-oncesi")
    assert yeni is not None
    assert yeni.exists(), "yeni alınan geçiş yedeği budamada silinmemeli"
    kalanlar = sorted(y.name for y in yedek_dizin.glob("*.db"))
    assert len(kalanlar) == 3
    assert yeni.name in kalanlar


def test_onizleme_pasif_kaydin_geri_gelecegini_soyler(istemci, kurulu) -> None:
    """Numarası yeniden kullanılan pasif kayıt önizlemede "Yeni öğrenci" değil
    açık bir devralma uyarısı olarak görünmeli."""
    baglanti = web_sunucu._baglanti()
    try:
        servis.ogrenci_ekle(baglanti, kurulu.id, [("101", "Ayşe Yılmaz")])
        ayse = next(
            o for o in servis.ogrencileri_oku(baglanti, kurulu.id) if o["numara"] == "101"
        )
        servis.ogrenci_sil(baglanti, ayse["id"], sube_id=kurulu.id)
    finally:
        baglanti.close()

    icerik = excel_baytlari(
        [["Okul No", "Adı Soyadı"], [101, "Zeynep Şahin"]]
    )
    yanit = istemci.post(
        f"/sube/{kurulu.id}/ogrenci/yukle",
        files={
            "dosya": (
                "9a.xlsx",
                icerik,
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            )
        },
        follow_redirects=True,
    )
    assert yanit.status_code == 200
    assert "DİKKAT" in yanit.text
    assert "Ayşe Yılmaz" in yanit.text
    assert "geçmişini devralacak" in yanit.text
