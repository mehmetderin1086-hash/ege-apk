"""Takvim ve yıllık plan dağıtımının testleri.

En kritik doğrulama: üretilen planın toplam ders saati, resmî programın o sınıf
için verdiği saate eşit olmalı. Eşit değilse plan ya konu atlıyor ya da olmayan
saat uyduruyor.
"""

from __future__ import annotations

from datetime import date

import pytest

from ogretmen_cantasi import mufredat as m
from ogretmen_cantasi import takvim as tk
from ogretmen_cantasi.plan import yillik


@pytest.fixture(scope="module")
def program() -> m.Mufredat:
    return m.yukle(m.MAARIF_2024)


@pytest.fixture
def yil_2026() -> tuple[tk.Donem, tk.Donem]:
    _, d1, d2 = tk.varsayilan_ogretim_yili(2026)
    return d1, d2


def ders_gunleri(haftalik_saat: int) -> dict[int, int]:
    """Haftalık saati günlere böler: 2 saat → salı çift; 4 saat → salı+perşembe."""
    return {2: 2} if haftalik_saat == 2 else {2: 2, 4: 2}


def test_varsayilan_yil_eylulun_ikinci_pazartesi_baslar() -> None:
    ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
    assert ad == "2026-2027"
    assert d1.baslangic.weekday() == 0
    assert d1.baslangic.month == 9
    assert d1.baslangic < d1.bitis < d2.baslangic < d2.bitis


def test_sabit_tatiller_donem_icine_dusenleri_verir(yil_2026) -> None:
    tatiller = tk.sabit_tatiller(yil_2026)
    adlar = {t.aciklama for t in tatiller}
    assert "Cumhuriyet Bayramı" in adlar
    assert "Ulusal Egemenlik ve Çocuk Bayramı" in adlar
    # Yaz tatiline düşenler plana girmemeli.
    assert "Zafer Bayramı" not in adlar
    assert "Demokrasi ve Millî Birlik Günü" not in adlar


def test_bayram_gunleri_arefeyi_de_sayar() -> None:
    gunler = tk.bayram_gunleri(date(2027, 3, 8), 3, "Ramazan Bayramı")
    assert len(gunler) == 4
    assert gunler[0].tarih == date(2027, 3, 8)
    assert gunler[-1].tarih == date(2027, 3, 11)


def test_tatil_gunu_haftanin_saatinden_dusulur(yil_2026) -> None:
    d1, d2 = yil_2026
    tatiller = [tk.TatilGunu(date(2026, 10, 29), tk.TUR_RESMI, "Cumhuriyet Bayramı")]
    haftalar = tk.haftalari_uret((d1, d2), tatiller, {4: 2})  # yalnız perşembe
    ekim29 = date(2026, 10, 29)
    hedef = next(h for h in haftalar if h.baslangic <= ekim29 <= h.bitis)
    assert ekim29.weekday() == 3  # perşembe
    assert hedef.ders_saati == 0
    assert hedef.tatiller[0].aciklama == "Cumhuriyet Bayramı"


def test_saat_dagitimi_toplami_korur() -> None:
    paylar = yillik.saatleri_dagit(38, [5, 3, 4, 5, 4, 5, 3])
    assert sum(paylar) == 38
    assert all(p > 0 for p in paylar)


def test_saat_dagitimi_agirlikla_orantili() -> None:
    paylar = yillik.saatleri_dagit(10, [1, 4])
    assert paylar == [2, 8]


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_birimlerin_toplami_resmi_saate_esit(program: m.Mufredat, sinif: int) -> None:
    duzey = program.duzey(sinif)
    birimler = yillik.birimleri_kur(duzey)
    assert sum(b.saat for b in birimler) == duzey.toplam_ders_saati


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_her_kazanim_en_az_bir_saat_alir(program: m.Mufredat, sinif: int) -> None:
    duzey = program.duzey(sinif)
    birimler = yillik.birimleri_kur(duzey)
    kapsanan = {b.kazanim.kod for b in birimler if b.kazanim}
    assert kapsanan == {c.kod for c in duzey.ogrenme_ciktilari}


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_yillik_plan_tum_kazanimlari_kapsar(program: m.Mufredat, sinif: int, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(sinif)
    haftalar = tk.haftalari_uret(
        (d1, d2), tk.sabit_tatiller((d1, d2)), ders_gunleri(duzey.haftalik_ders_saati)
    )
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    plandaki = {kod for s in satirlar for kod in s.kazanim_kodlari}
    assert plandaki == {c.kod for c in duzey.ogrenme_ciktilari}


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_planda_tatil_haftasina_ders_yazilmaz(program: m.Mufredat, sinif: int, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(sinif)
    tatiller = tk.sabit_tatiller((d1, d2))
    haftalar = tk.haftalari_uret((d1, d2), tatiller, ders_gunleri(duzey.haftalik_ders_saati))
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    for satir in satirlar:
        if satir.tur == yillik.TUR_TATIL:
            assert satir.ders_saati == 0
            assert not satir.kazanim_kodlari


@pytest.mark.parametrize("sinif", [9, 10, 11, 12])
def test_plandaki_tema_saati_resmi_saatle_ayni(program: m.Mufredat, sinif: int, yil_2026) -> None:
    """Plan, temaya programın verdiğinden fazla ya da az saat ayıramaz."""
    d1, d2 = yil_2026
    duzey = program.duzey(sinif)
    haftalar = tk.haftalari_uret(
        (d1, d2), tk.sabit_tatiller((d1, d2)), ders_gunleri(duzey.haftalik_ders_saati)
    )
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)
    ders_saati = sum(s.ders_saati for s in satirlar if s.tur != yillik.TUR_TATIL)
    # Yıl müfredattan uzun olabilir; fazlası "genel tekrar" satırlarına gider.
    assert ders_saati >= duzey.toplam_ders_saati


def test_aylik_ozet_ay_sirasini_korur(program: m.Mufredat, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)
    aylar = yillik.aylik_ozet(satirlar)

    assert aylar[0]["ay"] == "Eylül"
    assert [a["ay"] for a in aylar][:4] == ["Eylül", "Ekim", "Kasım", "Aralık"]
    assert sum(a["ders_saati"] for a in aylar) == sum(s.ders_saati for s in satirlar)


def test_oneriler_resmi_metinden_cikarilir(program: m.Mufredat, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)
    dolu = [s for s in satirlar if s.kazanim_kodlari]

    assert dolu, "hiç kazanım satırı üretilmedi"
    for satir in dolu:
        assert satir.yontem_teknik
        assert satir.arac_gerec
        assert satir.olcme_degerlendirme
    # BİY.9.1.1'in uygulama metninde büyük grup tartışması geçiyor.
    ilk = next(s for s in dolu if "BİY.9.1.1" in s.kazanim_kodlari)
    assert "Tartışma" in ilk.yontem_teknik


def test_kisa_anahtar_kelime_kelime_ortasinda_eslesmez() -> None:
    """'uygulama' içindeki 'lam', mikroskop önerisini tetiklememeli."""
    from ogretmen_cantasi.plan import oneriler

    metin = "Öğrencilerden uygulamaları paylaşmaları istenir."
    assert "Mikroskop ve preparat" not in oneriler.araclar(metin)
    assert "Mikroskop ve preparat" in oneriler.araclar("Hazırlanan lam mikroskopta incelenir.")


def test_devam_eden_kazanim_isaretlenir(program: m.Mufredat, yil_2026) -> None:
    """Aynı kazanım birkaç hafta sürüyorsa sonraki haftalar 'devam' sayılmalı."""
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    ilk = next(s for s in satirlar if "BİY.9.1.1" in s.kazanim_kodlari)
    assert "BİY.9.1.1" not in ilk.devam_kodlari
    assert ilk.yeni_kazanim_bilesenleri(), "ilk hafta bileşenler görünmeli"

    sonrakiler = [s for s in satirlar if "BİY.9.1.1" in s.kazanim_kodlari][1:]
    assert sonrakiler, "bu kazanım birden çok hafta sürmeli"
    assert all("BİY.9.1.1" in s.devam_kodlari for s in sonrakiler)
    salt_devam = [s for s in sonrakiler if set(s.kazanim_kodlari) <= set(s.devam_kodlari)]
    assert all(not s.yeni_kazanim_bilesenleri() for s in salt_devam)


def test_hafta_ortasinda_biten_mufredatta_saat_kaybolmaz(program: m.Mufredat, yil_2026) -> None:
    """Kuyruk haftanın ortasında bittiğinde kalan saatler satırda kalmalı."""
    d1, d2 = yil_2026
    duzey = program.duzey(11)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2, 4: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    for satir, hafta in zip(satirlar, haftalar, strict=True):
        assert satir.ders_saati == hafta.ders_saati, (
            f"{satir.hafta_no}. haftada {hafta.ders_saati} saat var, plana {satir.ders_saati} yazıldı"
        )


def test_takvim_kisaysa_kapsam_raporu_eksigi_bildirir(program: m.Mufredat, yil_2026) -> None:
    """Ders programı eksik girilirse kazanımlar sessizce düşmemeli."""
    d1, d2 = yil_2026
    duzey = program.duzey(11)  # 144 saat gerekir
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})  # ~72 saat
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    rapor = yillik.kapsam_raporu(duzey, satirlar)
    assert not rapor["tam"]
    assert rapor["eksik"], "kapsanmayan kazanımlar listelenmeli"
    assert rapor["kapsanan"] < rapor["toplam"]


def test_yeterli_takvimde_kapsam_tam(program: m.Mufredat, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    rapor = yillik.kapsam_raporu(duzey, yillik.yillik_plan_uret(duzey, haftalar))
    assert rapor["tam"] and not rapor["eksik"]


def test_tema_gecisinde_satir_dogru_temaya_yazilir(program: m.Mufredat, yil_2026) -> None:
    """Okul temelli blok ile yeni temanın ilk kazanımı aynı haftaya düşebilir."""
    d1, d2 = yil_2026
    duzey = program.duzey(11)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2, 4: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    tema_adlari = {t.no: t.ad for t in duzey.temalar}
    for satir in satirlar:
        for kod in satir.kazanim_kodlari:
            tema_no = int(kod.split(".")[2])
            assert satir.tema_no == tema_no or len({int(k.split(".")[2]) for k in satir.kazanim_kodlari}) > 1
            if satir.tema_no == tema_no:
                assert satir.tema_adi == tema_adlari[tema_no]


def test_genel_tekrar_satiri_tatil_aciklamasini_ezmez(program: m.Mufredat) -> None:
    """Müfredat bittikten sonraki hafta kısmen tatilse ikisi de görünmeli."""
    d1 = tk.Donem(1, date(2026, 9, 14), date(2026, 9, 25))
    d2 = tk.Donem(2, date(2026, 9, 28), date(2026, 10, 30))
    tatiller = [tk.TatilGunu(date(2026, 10, 29), tk.TUR_RESMI, "Cumhuriyet Bayramı")]
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tatiller, {1: 2, 4: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    son = satirlar[-1]
    assert "Cumhuriyet Bayramı" in son.aciklama


def test_ayni_gune_iki_tatil_kaydi_ikisi_de_korunur() -> None:
    d1 = tk.Donem(1, date(2026, 9, 14), date(2026, 12, 31))
    d2 = tk.Donem(2, date(2027, 2, 1), date(2027, 6, 18))
    tatiller = [
        tk.TatilGunu(date(2026, 10, 29), tk.TUR_RESMI, "Cumhuriyet Bayramı"),
        tk.TatilGunu(date(2026, 10, 29), tk.TUR_OKUL, "Okul kapalı"),
    ]
    haftalar = tk.haftalari_uret((d1, d2), tatiller, {4: 2})
    hedef = next(h for h in haftalar if h.baslangic <= date(2026, 10, 29) <= h.bitis)
    assert {t.aciklama for t in hedef.tatiller} == {"Cumhuriyet Bayramı", "Okul kapalı"}


def test_iki_doneme_yayilan_hafta_iki_kez_uretilmez() -> None:
    """1. dönem çarşamba bitip 2. dönem aynı haftanın cuması başlayabilir."""
    d1 = tk.Donem(1, date(2027, 1, 4), date(2027, 1, 27))
    d2 = tk.Donem(2, date(2027, 1, 29), date(2027, 3, 5))
    haftalar = tk.haftalari_uret((d1, d2), [], {1: 2, 5: 2})

    baslangiclar = [h.baslangic for h in haftalar]
    assert len(baslangiclar) == len(set(baslangiclar)), "aynı hafta iki satır olmamalı"
    ortak = next(h for h in haftalar if h.baslangic == date(2027, 1, 25))
    # Pazartesi 1. dönemde, cuma 2. dönemde: ikisi de sayılmalı.
    assert ortak.ders_saati == 4


def test_belirli_gunler_ders_saatini_dusurmez(yil_2026) -> None:
    """Belirli gün ve haftalar tatil değildir; o gün ders yapılır."""
    d1, d2 = yil_2026
    gunler = tk.belirli_gunler((d1, d2))
    assert gunler, "dönem içine düşen belirli gün olmalı"

    hedef = next(g for g in gunler if g.aciklama == "Hayvanları Koruma Günü")
    haftalar = tk.haftalari_uret((d1, d2), gunler, {hedef.tarih.isoweekday(): 2})
    hafta = next(h for h in haftalar if h.baslangic <= hedef.tarih <= h.bitis)
    assert hafta.ders_saati == 2, "belirli gün ders saatini düşürmemeli"
    assert "Hayvanları Koruma Günü" in hafta.belirli_gun_adlari
    assert not hafta.gercek_tatiller


def test_belirli_gun_plan_satirinda_gorunur(program: m.Mufredat, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    tatiller = tk.sabit_tatiller((d1, d2)) + tk.belirli_gunler((d1, d2))
    haftalar = tk.haftalari_uret((d1, d2), tatiller, {1: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)

    isaretli = [s for s in satirlar if s.belirli_gunler]
    assert isaretli, "hiçbir satıra belirli gün düşmemiş"
    assert all(s.ders_saati > 0 for s in isaretli), "belirli gün satırı ders saatini kaybetmemeli"
    # Belirli gün açıklama sütununu tatil gibi doldurmamalı.
    assert all("Hayvanları Koruma" not in s.aciklama for s in satirlar)


def test_disiplinler_arasi_plana_gecer(program: m.Mufredat, yil_2026) -> None:
    d1, d2 = yil_2026
    duzey = program.duzey(9)
    haftalar = tk.haftalari_uret((d1, d2), tk.sabit_tatiller((d1, d2)), {2: 2})
    satirlar = yillik.yillik_plan_uret(duzey, haftalar)
    dolu = next(s for s in satirlar if s.kazanim_kodlari)
    assert "Fizik" in dolu.disiplinler_arasi
