"""Günlük ders planı üretiminin testleri."""

from __future__ import annotations

from datetime import date

import pytest

from ogretmen_cantasi import mufredat as m
from ogretmen_cantasi.plan import gunluk


@pytest.fixture(scope="module")
def tema() -> m.Tema:
    return m.yukle(m.MAARIF_2024).duzey(9).temalar[0]


def test_cumlelere_bol_kisaltmayi_bolmez() -> None:
    metin = "Örnekler paylaşılır (aşı, PZR vb.). Öğrencilerden liste istenir (BİY.9.1.1)."
    assert len(gunluk.cumlelere_bol(metin)) == 2


def test_etiketsiz_cumle_en_son_koda_baglanir() -> None:
    metin = (
        "Genel bir giriş cümlesi. "
        "Bu cümle birinci kazanıma aittir (BİY.9.1.1). "
        "Bu da onun devamıdır. "
        "Bu ise ikinci kazanıma aittir (BİY.9.1.2)."
    )
    birinci = gunluk.kazanima_ait_metin(metin, ["BİY.9.1.1"])
    assert "birinci kazanıma" in birinci
    assert "devamıdır" in birinci
    assert "ikinci kazanıma" not in birinci
    assert "Genel bir giriş" in birinci


def test_kazanimi_gecmeyen_metin_bos_doner() -> None:
    metin = "Bu cümle başka kazanıma aittir (BİY.9.1.5)."
    assert gunluk.kazanima_ait_metin(metin, ["BİY.9.1.3"]) == ""


def test_kodsuz_metin_oldugu_gibi_doner() -> None:
    metin = "Hiç kod içermeyen genel bir paragraf. İkinci cümlesi."
    assert gunluk.kazanima_ait_metin(metin, ["BİY.9.1.3"]) == metin


def test_dakika_dagitimi_toplami_korur() -> None:
    dakikalar = gunluk.dakikalari_dagit(80, [0.12, 0.13, 0.35, 0.25, 0.10, 0.05])
    assert sum(dakikalar) == 80
    assert all(d >= 5 for d in dakikalar)


def test_tek_saatlik_derste_de_toplam_korunur() -> None:
    assert sum(gunluk.dakikalari_dagit(40, [0.12, 0.13, 0.35, 0.25, 0.10, 0.05])) == 40


def test_plan_bolumleri_ve_suresi(tema: m.Tema) -> None:
    kazanimlar = [c for c in tema.ogrenme_ciktilari if c.kod == "BİY.9.1.1"]
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 9, 15),
        sube_adi="9-A",
        sinif=9,
        tema=tema,
        kazanimlar=kazanimlar,
        ders_saatleri=[1, 2],
    )
    assert plan.toplam_dakika == 80
    assert plan.bolumler[0].ad == "Dikkat Çekme ve Ön Değerlendirme"
    assert plan.bolumler[2].metin, "işleniş bölümü boş kalmamalı"
    assert plan.kazanim_kodlari == ["BİY.9.1.1"]
    assert plan.surec_bilesenleri


def test_islenis_ve_etkinlik_ayni_metni_tekrarlamaz(tema: m.Tema) -> None:
    kazanimlar = [c for c in tema.ogrenme_ciktilari if c.kod == "BİY.9.1.1"]
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 9, 15),
        sube_adi="9-A",
        sinif=9,
        tema=tema,
        kazanimlar=kazanimlar,
        ders_saatleri=[1, 2],
    )
    islenis = next(b for b in plan.bolumler if b.ad == "İşleniş")
    etkinlik = next(b for b in plan.bolumler if b.ad == "Etkinlik")
    assert islenis.metin != etkinlik.metin


def test_kopru_kurma_ilgisiz_kazanimin_metnini_almaz(tema: m.Tema) -> None:
    """Köprü kurma paragrafında BİY.9.1.3 hiç geçmiyor; bölüm boş kalmalı."""
    kazanimlar = [c for c in tema.ogrenme_ciktilari if c.kod == "BİY.9.1.3"]
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 10, 20),
        sube_adi="9-A",
        sinif=9,
        tema=tema,
        kazanimlar=kazanimlar,
        ders_saatleri=[3, 4],
    )
    kopru = next(b for b in plan.bolumler if b.ad.startswith("Derse Giriş"))
    assert "sınıflandırmayla" not in kopru.metin


def test_sozluge_cevrilebilir(tema: m.Tema) -> None:
    plan = gunluk.gunluk_plan_uret(
        tarih=date(2026, 9, 15),
        sube_adi="9-A",
        sinif=9,
        tema=tema,
        kazanimlar=list(tema.ogrenme_ciktilari[:1]),
        ders_saatleri=[1],
    )
    veri = plan.sozluge()
    assert veri["sube_adi"] == "9-A"
    assert len(veri["bolumler"]) == len(gunluk.BOLUM_TANIMLARI)
