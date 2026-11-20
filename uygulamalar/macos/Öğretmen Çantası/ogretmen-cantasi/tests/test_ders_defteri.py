"""Ders defteri ve plan gerçekleşme raporunun testleri.

Defter, yıllık planın (niyet) karşısına gerçekleşeni koyar. Buradaki asıl
tehlike sessiz yanlış sayım: kayma raporu yanlış "yolunda" derse öğretmen
telafiyi kaçırır, yanlış "geride" derse plana güvenilmez olur.
"""

from __future__ import annotations

from datetime import date

import pytest

from ogretmen_cantasi import servis
from ogretmen_cantasi.plan import yillik as yp


@pytest.fixture
def sube(baglanti, yil):
    sube_id = servis.sube_ekle(baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
    return servis.sube_al(baglanti, sube_id)


def _satir(hafta_no: int, baslangic: str, bitis: str, kodlar: list[str]) -> yp.PlanSatiri:
    return yp.PlanSatiri(
        sira=hafta_no,
        hafta_no=hafta_no,
        donem=1,
        ay="Eylül",
        baslangic=baslangic,
        bitis=bitis,
        ders_saati=2,
        tur=yp.TUR_TEMA,
        tema_no=1,
        tema_adi="Yaşam",
        kazanim_kodlari=kodlar,
    )


# --- kayıt ---------------------------------------------------------------


def test_ders_kaydi_ayni_gune_ust_uste_yazilir(baglanti, sube) -> None:
    gun = date(2026, 9, 15)
    servis.ders_kaydi_yaz(
        baglanti, sube.id, gun, ders_saatleri=[3, 4], kazanim_kodlari=["BİY.9.1.1"]
    )
    servis.ders_kaydi_yaz(
        baglanti,
        sube.id,
        gun,
        ders_saatleri=[3, 4],
        kazanim_kodlari=["BİY.9.1.1", "BİY.9.1.2"],
        durum="ertelendi",
        aciklama="Laboratuvar doluydu",
    )
    kayitlar = servis.ders_kayitlari(baglanti, sube.id)
    assert len(kayitlar) == 1
    assert kayitlar[0]["kazanim_kodlari"] == "BİY.9.1.1, BİY.9.1.2"
    assert kayitlar[0]["durum"] == "ertelendi"
    assert kayitlar[0]["aciklama"] == "Laboratuvar doluydu"


def test_bos_kod_listesi_mevcut_kodlari_silmez(baglanti, sube) -> None:
    """Yarım form gönderimi var olan kaydın kazanımlarını sessizce yutmamalı."""
    gun = date(2026, 9, 15)
    servis.ders_kaydi_yaz(
        baglanti, sube.id, gun, ders_saatleri=[3], kazanim_kodlari=["BİY.9.1.1"]
    )
    servis.ders_kaydi_yaz(baglanti, sube.id, gun, ders_saatleri=[3], kazanim_kodlari=[])
    kayit = servis.gunun_ders_kaydi(baglanti, sube.id, gun)
    assert kayit["kazanim_kodlari"] == "BİY.9.1.1"


def test_bilinmeyen_durum_reddedilir(baglanti, sube) -> None:
    with pytest.raises(ValueError):
        servis.ders_kaydi_yaz(
            baglanti,
            sube.id,
            date(2026, 9, 15),
            ders_saatleri=[3],
            kazanim_kodlari=["BİY.9.1.1"],
            durum="iptal",
        )


def test_ders_kaydi_silinir(baglanti, sube) -> None:
    gun = date(2026, 9, 15)
    servis.ders_kaydi_yaz(
        baglanti, sube.id, gun, ders_saatleri=[3], kazanim_kodlari=["BİY.9.1.1"]
    )
    servis.ders_kaydi_sil(baglanti, sube.id, gun)
    assert servis.gunun_ders_kaydi(baglanti, sube.id, gun) is None


# --- gerçekleşme raporu --------------------------------------------------


def _kayit_yaz(baglanti, sube_id: int, gun: date, kodlar: list[str], durum: str = "islendi"):
    servis.ders_kaydi_yaz(
        baglanti, sube_id, gun, ders_saatleri=[1], kazanim_kodlari=kodlar, durum=durum
    )


def test_gerceklesme_tam_kismi_ve_islenmemis_ayirt_edilir(baglanti, sube) -> None:
    satirlar = [
        _satir(1, "2026-09-14", "2026-09-18", ["BİY.9.1.1"]),
        _satir(2, "2026-09-21", "2026-09-25", ["BİY.9.1.2", "BİY.9.1.3"]),
        _satir(3, "2026-09-28", "2026-10-02", ["BİY.9.1.4"]),
    ]
    _kayit_yaz(baglanti, sube.id, date(2026, 9, 15), ["BİY.9.1.1"])
    _kayit_yaz(baglanti, sube.id, date(2026, 9, 22), ["BİY.9.1.2"])

    rapor = servis.gerceklesme_raporu(
        satirlar, servis.ders_kayitlari(baglanti, sube.id), date(2026, 10, 5)
    )
    durumlar = {h["hafta_no"]: h["durum"] for h in rapor["haftalar"]}
    assert durumlar == {1: "tam", 2: "kismi", 3: "yok"}
    assert rapor["geride_hafta"] == 2
    assert rapor["gecmis_hafta"] == 3
    assert rapor["islenmemis"] == ["BİY.9.1.3", "BİY.9.1.4"]


def test_ertelenen_kayit_islendi_sayilmaz(baglanti, sube) -> None:
    satirlar = [_satir(1, "2026-09-14", "2026-09-18", ["BİY.9.1.1"])]
    _kayit_yaz(baglanti, sube.id, date(2026, 9, 15), ["BİY.9.1.1"], durum="ertelendi")
    rapor = servis.gerceklesme_raporu(
        satirlar, servis.ders_kayitlari(baglanti, sube.id), date(2026, 9, 25)
    )
    assert rapor["haftalar"][0]["durum"] == "yok"
    assert rapor["islenmemis"] == ["BİY.9.1.1"]


def test_gelecek_haftalar_geride_sayilmaz(baglanti, sube) -> None:
    satirlar = [
        _satir(1, "2026-09-14", "2026-09-18", ["BİY.9.1.1"]),
        _satir(2, "2026-09-21", "2026-09-25", ["BİY.9.1.2"]),
    ]
    _kayit_yaz(baglanti, sube.id, date(2026, 9, 15), ["BİY.9.1.1"])
    rapor = servis.gerceklesme_raporu(
        satirlar, servis.ders_kayitlari(baglanti, sube.id), date(2026, 9, 16)
    )
    assert rapor["geride_hafta"] == 0
    assert rapor["islenmemis"] == []
    assert rapor["haftalar"][1]["gecmis"] is False


def test_kazanim_eslesmesi_kod_sinirina_saygili(baglanti, sube) -> None:
    """BİY.9.1.1 işlendi diye BİY.9.1.10 işlenmiş sayılmamalı (startswith tuzağı)."""
    satirlar = [_satir(1, "2026-09-14", "2026-09-18", ["BİY.9.1.10"])]
    _kayit_yaz(baglanti, sube.id, date(2026, 9, 15), ["BİY.9.1.1"])
    rapor = servis.gerceklesme_raporu(
        satirlar, servis.ders_kayitlari(baglanti, sube.id), date(2026, 9, 25)
    )
    assert rapor["haftalar"][0]["durum"] == "yok"
    assert rapor["islenmemis"] == ["BİY.9.1.10"]


def test_tatil_ve_okul_temelli_satirlar_rapora_girmez(baglanti, sube) -> None:
    tatil = yp.PlanSatiri(
        sira=1,
        hafta_no=1,
        donem=1,
        ay="Kasım",
        baslangic="2026-11-16",
        bitis="2026-11-20",
        ders_saati=0,
        tur=yp.TUR_TATIL,
    )
    rapor = servis.gerceklesme_raporu(
        [tatil], servis.ders_kayitlari(baglanti, sube.id), date(2026, 12, 1)
    )
    assert rapor["haftalar"] == []
    assert rapor["geride_hafta"] == 0


def test_ayni_gunun_ayrik_bloklari_birbirini_ezmez(baglanti, sube) -> None:
    """1-2 ve 5-6. saat blokları ayrı kayıtlardır; ikincisi ilkini silmemeli."""
    gun = date(2026, 9, 15)
    servis.ders_kaydi_yaz(
        baglanti, sube.id, gun, ders_saatleri=[1, 2], kazanim_kodlari=["BİY.9.1.1"]
    )
    servis.ders_kaydi_yaz(
        baglanti,
        sube.id,
        gun,
        ders_saatleri=[5, 6],
        kazanim_kodlari=["BİY.9.1.2"],
        durum="ertelendi",
    )
    kayitlar = servis.gunun_ders_kayitlari(baglanti, sube.id, gun)
    assert len(kayitlar) == 2
    ilk = servis.gunun_ders_kaydi(baglanti, sube.id, gun, ders_saatleri=[1, 2])
    assert ilk["kazanim_kodlari"] == "BİY.9.1.1"
    assert ilk["durum"] == "islendi"


def test_gelecek_tarihli_kayit_gecmis_haftayi_tamamlamaz(baglanti, sube) -> None:
    satirlar = [_satir(1, "2026-09-14", "2026-09-18", ["BİY.9.1.1"])]
    _kayit_yaz(baglanti, sube.id, date(2026, 10, 10), ["BİY.9.1.1"])
    rapor = servis.gerceklesme_raporu(
        satirlar, servis.ders_kayitlari(baglanti, sube.id), date(2026, 9, 25)
    )
    assert rapor["haftalar"][0]["durum"] == "yok"
    assert rapor["islenmemis"] == ["BİY.9.1.1"]
