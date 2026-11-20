"""Sınav takvimi ve devamsızlık eşiğinin testleri.

Takvim uyarıları yalnız takvim gerçeklerinden üretilmeli: tatil çakışması ve
aynı güne yığılma. Devamsızlıkta "gün" karşılığı şubenin gerçek ders
programından türetilir — 2 saatlik günde 2 saat yok yazılan öğrenci 2 değil
1 gün devamsız sayılmalı.
"""

from __future__ import annotations

from datetime import date

import pytest

from ogretmen_cantasi import servis
from ogretmen_cantasi import takvim as tk


@pytest.fixture
def sube(baglanti, yil):
    sube_id = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    servis.ogrenci_ekle(baglanti, sube_id, [("101", "Ayşe Yılmaz")])
    return servis.sube_al(baglanti, sube_id)


def test_takvim_tarihli_degerlendirmeleri_listeler(baglanti, yil, sube) -> None:
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "1. Yazılı", tarih="2026-10-20")
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "performans", "Sunum")  # tarihsiz
    takvim = servis.sinav_takvimi(baglanti, yil)
    assert [g["ad"] for g in takvim["girisler"]] == ["1. Yazılı"]
    assert takvim["uyarilar"] == []


def test_takvim_tatil_ve_ayni_gun_cakismasini_uyarir(baglanti, yil, sube) -> None:
    servis.tatil_ekle(
        baglanti,
        yil.id,
        [tk.TatilGunu(tarih=date(2026, 10, 29), tur="resmi", aciklama="Cumhuriyet Bayramı")],
    )
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "1. Yazılı", tarih="2026-10-29")
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "performans", "Sunum", tarih="2026-11-03")
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "2. Yazılı", tarih="2026-11-03")

    takvim = servis.sinav_takvimi(baglanti, yil)
    assert len(takvim["uyarilar"]) == 2
    assert any("tatil" in u and "Cumhuriyet" in u for u in takvim["uyarilar"])
    assert any("aynı gün 2 değerlendirme" in u for u in takvim["uyarilar"])
    # Tatil bilgisi satırda da işaretli olmalı.
    tatilli = next(g for g in takvim["girisler"] if g["tarih"] == "2026-10-29")
    assert tatilli["tatil"] == "Cumhuriyet Bayramı"


def test_resmi_olmayan_degerlendirme_takvime_girmez(baglanti, yil, sube) -> None:
    servis.degerlendirme_ekle(
        baglanti, sube.id, 1, "ic_takip", "İç takip", tarih="2026-10-20"
    )
    assert servis.sinav_takvimi(baglanti, yil)["girisler"] == []


def test_devamsizlik_gunu_ders_programindan_hesaplanir(baglanti, yil, sube) -> None:
    # Salı 2 saat ders: aynı gün 2 saat "yok" = 1 gün devamsızlık.
    servis.ders_programi_yaz(baglanti, [(sube.id, 2, 3), (sube.id, 2, 4)])
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    for saat in (3, 4):
        servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), saat, {ogrenci: "yok"})

    kayit = servis.devamsizlik_tablosu(baglanti, sube.id)[0]
    assert kayit["yok_saat"] == 2
    assert kayit["yok_gun"] == 1.0
    assert kayit["uyari"] == ""  # varsayılan sınır 10 gün


def test_devamsizlik_esigi_ayardan_okunur(baglanti, yil, sube) -> None:
    servis.ders_programi_yaz(baglanti, [(sube.id, 2, 3), (sube.id, 2, 4)])
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    for saat in (3, 4):
        servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), saat, {ogrenci: "yok"})

    assert servis.ayarlari_yaz(baglanti, {servis.AYAR_DEVAMSIZLIK_SINIRI: "1"}) == []
    kayit = servis.devamsizlik_tablosu(baglanti, sube.id)[0]
    assert kayit["sinir"] == 1
    assert "Sınır aşıldı" in kayit["uyari"]

    # Aralık dışı değer kabul edilmemeli ve mevcut ayarı bozmamalı.
    uyarilar = servis.ayarlari_yaz(baglanti, {servis.AYAR_DEVAMSIZLIK_SINIRI: "0"})
    assert uyarilar
    assert servis.devamsizlik_tablosu(baglanti, sube.id)[0]["sinir"] == 1


def test_bozuk_tarih_takvimi_dusurmez(baglanti, yil, sube) -> None:
    """Serbest metin tarih alanına giren bozuk değer sayfayı 500'letmemeli."""
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "1. Yazılı", tarih="20.10.2026")
    takvim = servis.sinav_takvimi(baglanti, yil)
    assert len(takvim["girisler"]) == 1
    assert any("tarih biçimi tanınmadı" in u for u in takvim["uyarilar"])


def test_belirli_gun_sinav_icin_tatil_sayilmaz(baglanti, yil, sube) -> None:
    """Öğretmenler Günü gibi belirli günlerde ders yapılır; yazılıya tatil
    uyarısı üretilmemeli."""
    servis.tatil_ekle(
        baglanti,
        yil.id,
        [tk.TatilGunu(tarih=date(2026, 11, 24), tur=tk.TUR_BELIRLI, aciklama="Öğretmenler Günü")],
    )
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "1. Yazılı", tarih="2026-11-24")
    takvim = servis.sinav_takvimi(baglanti, yil)
    assert takvim["uyarilar"] == []
    assert takvim["girisler"][0]["tatil"] == ""


def test_ayni_sinav_iki_kaynaktan_tek_satir_gorunur(baglanti, yil, sube) -> None:
    """Not defterinde tanımlı yazılıyla aynı ad/tarih/şubeyle üretilen sınav
    kâğıdı aynı yazılıdır; çift satır ve sahte çakışma uyarısı olmamalı."""
    servis.degerlendirme_ekle(baglanti, sube.id, 1, "yazili", "1. Yazılı", tarih="2026-10-20")
    baglanti.execute(
        "INSERT INTO sinav (sube_id, ad, tarih, olusturma) VALUES (?,?,?,?)",
        (sube.id, "1. Yazılı", "2026-10-20", "2026-10-01T09:00:00"),
    )
    takvim = servis.sinav_takvimi(baglanti, yil)
    assert len(takvim["girisler"]) == 1
    assert takvim["uyarilar"] == []


def test_yok_gun_o_gunun_programina_oranlanir(baglanti, yil, sube) -> None:
    """Pazartesi 1, Salı 3 saatlik programda her iki günün tamamını kaçırmak
    birer gündür; haftalık ortalamayla 0,5/1,5 çıkıyordu."""
    servis.ders_programi_yaz(
        baglanti, [(sube.id, 1, 1), (sube.id, 2, 3), (sube.id, 2, 4), (sube.id, 2, 5)]
    )
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 14), 1, {ogrenci: "yok"})
    for saat in (3, 4, 5):
        servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), saat, {ogrenci: "yok"})

    kayit = servis.devamsizlik_tablosu(baglanti, sube.id)[0]
    assert kayit["yok_gun"] == 2.0
