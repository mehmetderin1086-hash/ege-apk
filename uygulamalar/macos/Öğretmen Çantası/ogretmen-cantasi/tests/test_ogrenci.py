"""Öğrenci gelişim sayfası ve veli raporunun testleri.

Rapor dört ayrı modülün (not, yoklama, deneme, sınav) verisini birleştirir;
buradaki testler birleştirmenin veri uydurmadığını ve sınav sırasının
korunduğunu sabitler.
"""

from __future__ import annotations

from datetime import date

import pymupdf
import pytest

from ogretmen_cantasi import servis
from ogretmen_cantasi import servis_olcme as so
from ogretmen_cantasi.web import sunucu as web_sunucu


@pytest.fixture
def sube(baglanti, yil):
    sube_id = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    servis.ogrenci_ekle(baglanti, sube_id, [("101", "Ayşe Yılmaz"), ("102", "Mehmet Kaya")])
    return servis.sube_al(baglanti, sube_id)


def _tek_kazanimli_sinav(baglanti, sube, ad: str, tarih: str):
    """Havuzda tek kazanım bırakarak sınavın kazanım kodunu belirli kılar."""
    if not so.sorulari_oku(baglanti, sinif=9):
        for n in range(3):
            so.soru_ekle(
                baglanti,
                mufredat_surumu="maarif_2024",
                kazanim_kodu="BİY.9.1.1",
                sinif=9,
                metin=f"Soru {n}: hücre zarını açıklayınız.",
                rubrik="Tam 10",
            )
    sinav_id, sinav, _ = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube.id,
        sube_adi=sube.ad,
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad=ad,
        dagilim={"BİY.9.1": 100},
        soru_sayisi=1,
        tarih=tarih,
    )
    return sinav_id, sinav


def test_kazanim_profili_sinav_sirasiyla_birikir(baglanti, sube) -> None:
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]

    id1, sinav1 = _tek_kazanimli_sinav(baglanti, sube, "1. Yazılı", "2026-10-01")
    so.soru_puani_yaz(baglanti, id1, [(sinav1.sorular[0].id, ogrenci, 0.0)])
    id2, sinav2 = _tek_kazanimli_sinav(baglanti, sube, "2. Yazılı", "2026-11-01")
    so.soru_puani_yaz(
        baglanti, id2, [(sinav2.sorular[0].id, ogrenci, sinav2.sorular[0].puan)]
    )

    profil = so.ogrenci_kazanim_profili(baglanti, ogrenci)
    gecmis = profil["gecmis"]["BİY.9.1.1"]
    assert [g["sinav"] for g in gecmis] == ["1. Yazılı", "2. Yazılı"]
    assert gecmis[0]["yuzde"] == 0.0
    assert gecmis[1]["yuzde"] == 100.0
    # Özet, en son sınavdaki durumu göstermeli — ortalamayı değil.
    assert profil["son"]["BİY.9.1.1"]["yuzde"] == 100.0
    assert profil["son"]["BİY.9.1.1"]["durum"] == "iyi"


def test_puani_olmayan_ogrencinin_profili_bos(baglanti, sube) -> None:
    ogrenciler = servis.ogrencileri_oku(baglanti, sube.id)
    id1, sinav1 = _tek_kazanimli_sinav(baglanti, sube, "1. Yazılı", "2026-10-01")
    so.soru_puani_yaz(
        baglanti, id1, [(sinav1.sorular[0].id, ogrenciler[0]["id"], 5.0)]
    )
    profil = so.ogrenci_kazanim_profili(baglanti, ogrenciler[1]["id"])
    assert profil["gecmis"] == {}
    assert profil["son"] == {}


def test_deneme_netleri_tarih_sirali(baglanti, sube) -> None:
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    so.deneme_kaydet(
        baglanti, ad="TYT-2", tarih="2026-11-10", yayin="X", sonuclar=[(ogrenci, 15, 4, 1, 14.0)]
    )
    so.deneme_kaydet(
        baglanti, ad="TYT-1", tarih="2026-10-10", yayin="X", sonuclar=[(ogrenci, 10, 8, 2, 8.0)]
    )
    netler = so.ogrenci_deneme_netleri(baglanti, ogrenci)
    assert [n["ad"] for n in netler] == ["TYT-1", "TYT-2"]
    assert netler[0]["net"] == 8.0


# --- web ------------------------------------------------------------------


@pytest.fixture
def web_ogrenci(istemci):
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
        sube = servis.subeleri_oku(baglanti, yil.id)[0]
        servis.ogrenci_ekle(baglanti, sube.id, [("101", "Ayşe Yılmaz")])
        ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
        # Bir not, bir yoklama, bir deneme — rapor üç modülü de göstersin.
        d_id = servis.degerlendirme_ekle(
            baglanti, sube.id, donem=1, tur="yazili", ad="1. Yazılı"
        )
        servis.not_yaz(baglanti, d_id, {ogrenci: 85.0})
        servis.yoklama_kaydet(
            baglanti, sube.id, date(2026, 9, 15), 3, {ogrenci: "yok"}
        )
        so.deneme_kaydet(
            baglanti, ad="TYT-1", tarih="2026-10-10", yayin="X", sonuclar=[(ogrenci, 10, 8, 2, 8.0)]
        )
    finally:
        baglanti.close()
    return ogrenci


def test_ogrenci_sayfasi_verileri_birlestirir(istemci, web_ogrenci) -> None:
    yanit = istemci.get(f"/ogrenci/{web_ogrenci}")
    assert yanit.status_code == 200
    assert "Ayşe Yılmaz" in yanit.text
    assert "1. Yazılı" in yanit.text
    assert "TYT-1" in yanit.text
    assert "saat gelmedi" in yanit.text


def test_ogrenci_raporu_pdf_turkce_metin_tasir(istemci, web_ogrenci) -> None:
    yanit = istemci.get(f"/ogrenci/{web_ogrenci}/rapor")
    assert yanit.status_code == 200
    assert yanit.content.startswith(b"%PDF")
    with pymupdf.open(stream=yanit.content, filetype="pdf") as belge_dosyasi:
        metin = "".join(sayfa.get_text() for sayfa in belge_dosyasi)
    # Türkçe karakterler geri okunabilmeli — bozuk yazı tipi de geçerli PDF üretir.
    assert "Ayşe Yılmaz" in metin
    assert "Gelişim Raporu" in metin
    assert "Devamsızlık" in metin


def test_olmayan_ogrenci_404(istemci, web_ogrenci) -> None:
    assert istemci.get("/ogrenci/99999").status_code == 404


def test_yoklamasiz_ogrencinin_raporu_500_vermez(istemci, web_ogrenci) -> None:
    """Yoklaması hiç alınmamış öğrencide devam_orani None gelir; PDF biçimleme
    bunu 500'e çevirmemeli, bölüm hiç basılmamalı."""
    baglanti = web_sunucu._baglanti()
    try:
        yil = servis.aktif_yil(baglanti)
        sube = servis.subeleri_oku(baglanti, yil.id)[0]
        servis.ogrenci_ekle(baglanti, sube.id, [("102", "Veli Öz")])
        yeni = next(
            o for o in servis.ogrencileri_oku(baglanti, sube.id) if o["numara"] == "102"
        )
    finally:
        baglanti.close()
    yanit = istemci.get(f"/ogrenci/{yeni['id']}/rapor")
    assert yanit.status_code == 200
    assert yanit.content.startswith(b"%PDF")
    with pymupdf.open(stream=yanit.content, filetype="pdf") as belge_dosyasi:
        metin = "".join(sayfa.get_text() for sayfa in belge_dosyasi)
    assert "Veli Öz" in metin
    assert "Devamsızlık" not in metin
