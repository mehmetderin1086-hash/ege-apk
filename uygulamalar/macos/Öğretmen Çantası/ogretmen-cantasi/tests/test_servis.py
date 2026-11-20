"""Servis katmanının testleri — gerçek (bellek içi) veritabanı üzerinde."""

from __future__ import annotations

from dataclasses import fields
from datetime import date

import pytest

from ogretmen_cantasi import depo, servis
from ogretmen_cantasi import notlar as nt
from ogretmen_cantasi import servis_olcme as so
from ogretmen_cantasi import takvim as tk
from ogretmen_cantasi.plan import yillik as yp


@pytest.fixture
def sube(baglanti, yil):
    sube_id = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    servis.ogrenci_ekle(
        baglanti,
        sube_id,
        [("101", "Ayşe Yılmaz"), ("102", "Mehmet Kaya"), ("103", "Ali Demir")],
    )
    return servis.sube_al(baglanti, sube_id)


# --- kurulum -------------------------------------------------------------


def test_sema_kurulur_ve_yinelenmez(baglanti) -> None:
    depo.sema_kur(baglanti)  # ikinci kez çağrılması hata vermemeli
    surum = baglanti.execute("SELECT MAX(surum) AS s FROM sema_surumu").fetchone()["s"]
    assert surum == len(depo.GECISLER)


def test_ogretim_yili_resmi_tatillerle_kurulur(baglanti, yil) -> None:
    assert servis.aktif_yil(baglanti).ad == "2026-2027"
    tatiller = servis.tatilleri_oku(baglanti, yil.id)
    adlar = {t.aciklama for _, t in tatiller}
    assert "Cumhuriyet Bayramı" in adlar


def test_yil_yoksa_acik_hata(baglanti) -> None:
    with pytest.raises(servis.Bulunamadi, match="kurulum"):
        servis.yili_zorunlu_al(baglanti)


def test_sube_mufredat_surumunu_yila_gore_secer(baglanti, yil) -> None:
    dokuz = servis.sube_al(baglanti, servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad))
    oniki = servis.sube_al(baglanti, servis.sube_ekle(baglanti, yil.id, "12-A", 12, ogretim_yili_adi=yil.ad))
    assert dokuz.mufredat_surumu == "maarif_2024"
    assert dokuz.haftalik_ders_saati == 2
    # 2026-2027'de 12. sınıf hâlâ 2018 programında; müfredat dosyası yok ama
    # şube yine de kurulabilmeli.
    assert oniki.mufredat_surumu == "mfp_2018"
    assert oniki.haftalik_ders_saati == 4


def test_ogrenci_yinelenmez(baglanti, sube) -> None:
    eklenen = servis.ogrenci_ekle(baglanti, sube.id, [("101", "Ayşe Yılmaz"), ("104", "Zeynep Şahin")])
    assert eklenen == 1
    assert len(servis.ogrencileri_oku(baglanti, sube.id)) == 4


def test_ogrenciler_numaraya_gore_siralanir(baglanti, sube) -> None:
    servis.ogrenci_ekle(baglanti, sube.id, [("9", "Zeki Ak")])
    numaralar = [o["numara"] for o in servis.ogrencileri_oku(baglanti, sube.id)]
    assert numaralar == ["9", "101", "102", "103"]


# --- ders programı ve plan ----------------------------------------------


def test_ders_programi_yazilir_ve_gunun_dersleri_bulunur(baglanti, yil, sube) -> None:
    servis.ders_programi_yaz(baglanti, [(sube.id, 1, 1), (sube.id, 1, 2), (sube.id, 3, 5)])
    assert servis.sube_ders_gunleri(baglanti, sube.id) == {1: 2, 3: 1}

    pazartesi = date(2026, 9, 14)
    assert pazartesi.isoweekday() == 1
    dersler = servis.gunun_dersleri(baglanti, yil.id, pazartesi)
    assert [d["ders_saati"] for d in dersler] == [1, 2]
    assert dersler[0]["sube_adi"] == "9-A"


def test_yillik_plan_uretilir_ve_geri_okunur(baglanti, yil, sube) -> None:
    servis.ders_programi_yaz(baglanti, [(sube.id, 2, 1), (sube.id, 2, 2)])
    uretilen = servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    okunan = servis.yillik_plan_oku(baglanti, sube)

    assert len(okunan) == len(uretilen)
    assert [s.kazanim_kodlari for s in okunan] == [s.kazanim_kodlari for s in uretilen]
    assert okunan[0].kazanim_ifadeleri[0], "kazanım ifadesi müfredattan doldurulmalı"


def test_plan_yeniden_uretilince_cogalmaz(baglanti, yil, sube) -> None:
    servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    ilk = len(servis.yillik_plan_oku(baglanti, sube))
    servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    assert len(servis.yillik_plan_oku(baglanti, sube)) == ilk
    gecmis = servis.plan_gecmisi(baglanti, sube.id)
    assert [p["revizyon"] for p in gecmis] == [2, 1]


def test_gunluk_plan_o_haftanin_kazanimindan_uretilir(baglanti, yil, sube) -> None:
    servis.ders_programi_yaz(baglanti, [(sube.id, 2, 3), (sube.id, 2, 4)])
    servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    plan = servis.gunluk_plan_uret(baglanti, yil, sube, date(2026, 9, 15), [3, 4])

    assert plan is not None
    assert plan.kazanim_kodlari
    assert plan.toplam_dakika == 80
    servis.gunluk_plan_kaydet(baglanti, sube.id, plan)
    kayit = baglanti.execute("SELECT * FROM gunluk_plan WHERE sube_id = ?", (sube.id,)).fetchone()
    assert kayit["kazanim_kodlari"] == ", ".join(plan.kazanim_kodlari)


# --- yoklama ve notlar ---------------------------------------------------


def test_yoklama_kaydedilir_ve_devamsizlik_hesaplanir(baglanti, sube) -> None:
    ogrenciler = servis.ogrencileri_oku(baglanti, sube.id)
    ilk = ogrenciler[0]["id"]
    servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), 1, {o["id"]: "var" for o in ogrenciler})
    servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 22), 1, {ilk: "yok"})

    kayitli = servis.gunun_yoklamasi(baglanti, sube.id, date(2026, 9, 15), 1)
    assert kayitli[ilk] == "var"

    tablo = {t["id"]: t for t in servis.devamsizlik_tablosu(baglanti, sube.id)}
    assert tablo[ilk]["yok_saat"] == 1
    assert tablo[ilk]["toplam_ders"] == 2


def test_ayni_ders_saatine_ikinci_yoklama_ustune_yazar(baglanti, sube) -> None:
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), 1, {ogrenci: "yok"})
    servis.yoklama_kaydet(baglanti, sube.id, date(2026, 9, 15), 1, {ogrenci: "var"})
    assert servis.gunun_yoklamasi(baglanti, sube.id, date(2026, 9, 15), 1)[ogrenci] == "var"


def test_not_tablosu_ve_karne(baglanti, sube) -> None:
    yazili = servis.degerlendirme_ekle(baglanti, sube.id, 1, nt.TUR_YAZILI, "1. Yazılı")
    performans = servis.degerlendirme_ekle(baglanti, sube.id, 1, nt.TUR_PERFORMANS, "Performans")
    ic = servis.degerlendirme_ekle(baglanti, sube.id, 1, nt.TUR_IC_TAKIP, "Derse katılım")

    ogrenciler = servis.ogrencileri_oku(baglanti, sube.id)
    ilk = ogrenciler[0]["id"]
    servis.not_yaz(baglanti, yazili, {ilk: 80})
    servis.not_yaz(baglanti, performans, {ilk: 60})
    servis.not_yaz(baglanti, ic, {ilk: 100})

    satirlar, degerlendirmeler = servis.not_tablosu(baglanti, sube.id)
    kayit = next(s for s in satirlar if s["id"] == ilk)
    assert len(degerlendirmeler) == 3
    assert kayit["donem1"] == 70.0, "iç takip resmî ortalamaya girmemeli"
    assert kayit["ic_takip"] == 100.0


def test_bos_not_silinir(baglanti, sube) -> None:
    yazili = servis.degerlendirme_ekle(baglanti, sube.id, 1, nt.TUR_YAZILI, "1. Yazılı")
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    servis.not_yaz(baglanti, yazili, {ogrenci: 80})
    servis.not_yaz(baglanti, yazili, {ogrenci: None})
    satirlar, _ = servis.not_tablosu(baglanti, sube.id)
    assert satirlar[0]["puanlar"] == {}


# --- soru havuzu ve sınav ------------------------------------------------


def havuz_doldur(baglanti, sinif: int = 9) -> None:
    for tema in (1, 2):
        for kazanim in range(1, 6):
            for n in range(3):
                so.soru_ekle(
                    baglanti,
                    mufredat_surumu="maarif_2024",
                    kazanim_kodu=f"BİY.{sinif}.{tema}.{kazanim}",
                    sinif=sinif,
                    metin=f"Soru {tema}-{kazanim}-{n}: açıklayınız.",
                    rubrik="Tam 10, eksik 5",
                )


def test_soru_havuzu_filtrelenir(baglanti) -> None:
    havuz_doldur(baglanti)
    assert len(so.sorulari_oku(baglanti, sinif=9)) == 30
    assert len(so.sorulari_oku(baglanti, kazanim_kodu="BİY.9.1")) == 15
    assert len(so.sorulari_oku(baglanti, arama="1-3")) == 3


def test_sinav_uretilir_kaydedilir_ve_geri_yuklenir(baglanti, sube) -> None:
    havuz_doldur(baglanti)
    sinav_id, sinav, uyarilar = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube.id,
        sube_adi=sube.ad,
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad="1. Yazılı",
        dagilim={"BİY.9.1": 60, "BİY.9.2": 40},
        soru_sayisi=10,
    )
    assert not uyarilar
    assert sinav.toplam_puan == 100.0

    yuklenen = so.sinavi_yukle(baglanti, sinav_id)
    assert [s.id for s in yuklenen.sorular] == [s.id for s in sinav.sorular]
    assert set(yuklenen.gruplar) == {"A", "B"}
    assert yuklenen.belirtke[0].soru_sayisi == 6


def test_soru_arsivlenince_sinav_anlik_goruntusu_ve_puan_korunur(
    baglanti, sube
) -> None:
    havuz_doldur(baglanti)
    sinav_id, sinav, _ = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube.id,
        sube_adi=sube.ad,
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad="Arşiv testi",
        dagilim={"BİY.9.1": 100},
        soru_sayisi=2,
    )
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    soru = sinav.sorular[0]
    so.soru_puani_yaz(baglanti, sinav_id, [(soru.id, ogrenci, soru.puan)])
    so.soru_arsivle(baglanti, soru.id)

    assert all(s["id"] != soru.id for s in so.sorulari_oku(baglanti, sinif=9))
    yuklenen = so.sinavi_yukle(baglanti, sinav_id)
    assert any(s.id == soru.id and s.metin == soru.metin for s in yuklenen.sorular)
    assert so.sinav_puanlari(baglanti, sinav_id)[
        (ogrenci, soru.id)
    ] == soru.puan


def test_sinav_kazanim_analizi(baglanti, sube) -> None:
    havuz_doldur(baglanti)
    sinav_id, sinav, _ = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube.id,
        sube_adi=sube.ad,
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad="1. Yazılı",
        dagilim={"BİY.9.1": 50, "BİY.9.2": 50},
        soru_sayisi=4,
    )
    ogrenci = servis.ogrencileri_oku(baglanti, sube.id)[0]["id"]
    # İlk soruya tam, diğerlerine sıfır puan.
    puanlar = [
        (soru.id, ogrenci, soru.puan if sira == 0 else 0.0)
        for sira, soru in enumerate(sinav.sorular)
    ]
    so.soru_puani_yaz(baglanti, sinav_id, puanlar)

    analiz = so.sinav_kazanim_analizi(baglanti, sinav_id)
    ilk_kod = sinav.sorular[0].kazanim_kodu
    assert analiz["sinif"][ilk_kod].yuzde == 100.0
    assert ilk_kod not in analiz["zayif"]
    assert analiz["ogrenciler"][ogrenci]["toplam"] == sinav.sorular[0].puan


# --- deneme ve materyal --------------------------------------------------


def test_deneme_kaydedilir_ve_gelisim_okunur(baglanti, sube) -> None:
    ogrenciler = servis.ogrencileri_oku(baglanti, sube.id)
    so.deneme_kaydet(
        baglanti,
        ad="Deneme 1",
        tarih="2026-10-10",
        yayin="X Yayınları",
        sonuclar=[(ogrenciler[0]["id"], 10, 4, 2, 9.0), (ogrenciler[1]["id"], 6, 8, 2, 4.0)],
    )
    so.deneme_kaydet(
        baglanti,
        ad="Deneme 2",
        tarih="2026-11-10",
        yayin="X Yayınları",
        sonuclar=[(ogrenciler[0]["id"], 12, 2, 2, 11.5)],
    )
    gelisim = so.deneme_gelisimi(baglanti, sube.id)
    assert [d["ad"] for d in gelisim["denemeler"]] == ["Deneme 1", "Deneme 2"]
    assert gelisim["denemeler"][0]["ortalama"] == 6.5
    assert len(gelisim["ogrenciler"][ogrenciler[0]["id"]]["netler"]) == 2


def test_materyal_kazanima_gore_filtrelenir(baglanti) -> None:
    so.materyal_ekle(baglanti, baslik="Fotosentez videosu", kazanim_kodu="BİY.10.1.3", sinif=10)
    so.materyal_ekle(baglanti, baslik="Sınıflandırma sunumu", kazanim_kodu="BİY.9.1.5", sinif=9)
    assert len(so.materyalleri_oku(baglanti, kazanim_kodu="BİY.9")) == 1
    assert len(so.materyalleri_oku(baglanti, sinif=10)) == 1


def test_ayarlar_okunur_ve_yazilir(baglanti) -> None:
    servis.ayarlari_yaz(baglanti, {servis.AYAR_OKUL: "Örnek Lisesi", "bilinmeyen": "x"})
    ayarlar = servis.ayarlari_oku(baglanti)
    assert ayarlar[servis.AYAR_OKUL] == "Örnek Lisesi"
    assert "bilinmeyen" not in ayarlar
    assert servis.not_kurallari(baglanti).donem_basina_yazili == 2


def test_var_olan_sube_guncellenince_dogru_kimlik_doner(baglanti, yil) -> None:
    """Upsert sonrası lastrowid güncellenen satırı göstermiyor.

    Ders programı yüklenirken var olan bir şube yeniden eklendiğinde, yanlış
    kimlik dönerse o şubenin ders saatleri BAŞKA bir şubeye yazılıyordu.
    """
    ilk = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    servis.sube_ekle(baglanti, yil.id, "10-B", 10, ogretim_yili_adi=yil.ad)
    # Araya başka bir ekleme girdikten SONRA var olan şubeyi yeniden ekle.
    tekrar = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    assert tekrar == ilk

    servis.ders_programi_yaz(baglanti, [(tekrar, 1, 1), (tekrar, 1, 2)])
    assert servis.sube_ders_gunleri(baglanti, ilk) == {1: 2}
    assert servis.sube_al(baglanti, tekrar).ad == "9-A"


def test_var_olan_ogretim_yili_guncellenince_dogru_kimlik_doner(baglanti) -> None:
    ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
    ilk = servis.ogretim_yili_kur(baglanti, ad, d1, d2)
    servis.sube_ekle(baglanti, ilk.id, "9-A", 9, ogretim_yili_adi=ad)
    tekrar = servis.ogretim_yili_kur(baglanti, ad, d1, d2)
    assert tekrar.id == ilk.id
    assert len(servis.subeleri_oku(baglanti, tekrar.id)) == 1


def test_plan_satirinin_tum_alanlari_veritabani_turunu_atlatir(baglanti, yil, sube) -> None:
    """Üretimde dolan bir alan veritabanına yazılmazsa sessizce boşalır.

    Bu tek örneği değil bir HATA SINIFINI koruyor: yeni bir alan eklenip
    şemaya/gidiş-dönüşe bağlanmadığında ekranda ve PDF'te her zaman boş
    çıkıyor, üstelik alanı tek tek doğrulayan testler geçmeye devam ediyor.
    """
    servis.ders_programi_yaz(baglanti, [(sube.id, 1, 1), (sube.id, 1, 2)])
    uretilen = servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
    okunan = servis.yillik_plan_oku(baglanti, sube)
    assert len(okunan) == len(uretilen)

    # Alan listesi ELLE SAYILMAZ, dataclass'tan türetilir: elle sayıldığında
    # yeni eklenen bir alan listeye girmediği için test onu koruyamıyordu
    # (`donem` tam bu şekilde kaçmıştı). Yalnız okuma sonrası hesaplanan
    # alanlar açıkça dışlanır; başka her alan otomatik kapsama girer.
    TURETILEN_ALANLAR = {
        "sira",  # okuma sırasına göre yeniden verilir
        "devam_kodlari",  # _devamlari_isaretle ile okuma sonrası hesaplanır
        "bilesen_haritasi",  # müfredattan yeniden kurulur
    }
    alanlar = [a.name for a in fields(yp.PlanSatiri) if a.name not in TURETILEN_ALANLAR]
    assert len(alanlar) >= 18, "alan listesi beklenmedik biçimde küçüldü"

    for once, sonra in zip(uretilen, okunan, strict=True):
        for alan in alanlar:
            assert getattr(sonra, alan) == getattr(once, alan), (
                f"{once.hafta_no}. hafta '{alan}' alanı gidiş-dönüşte değişti: "
                f"{getattr(once, alan)!r} → {getattr(sonra, alan)!r}"
            )

    # En az bir satırda bu alanların gerçekten DOLU olduğunu da doğrula;
    # hepsi boşken karşılaştırma anlamsız olurdu.
    assert any(s.disiplinler_arasi for s in okunan)
    assert any(s.belirli_gunler for s in okunan)
    assert any(s.kazanim_kodlari for s in okunan)
    # Dönem tek değere sabitlenmemeli: yıl iki dönemden oluşuyor.
    assert {s.donem for s in okunan} == {1, 2}


def test_dosya_ici_mukerrer_numara_reddedilir(baglanti, sube) -> None:
    """"101 Ayşe" + "101 Ali" iki öğrenci sanılıp tek kayda çöküyordu; ikinci
    satır ilkinin adını eziyor, sayaç yine 2 diyordu. Dosya reddedilmeli."""
    with pytest.raises(ValueError, match="birden çok satırda"):
        servis.ogrenci_ekle(
            baglanti, sube.id, [("201", "Ayşe Yılmaz"), ("201", "Ali Demir")]
        )
    assert all(
        o["numara"] != "201" for o in servis.ogrencileri_oku(baglanti, sube.id)
    ), "reddedilen dosyadan kayıt sızmamalı"
