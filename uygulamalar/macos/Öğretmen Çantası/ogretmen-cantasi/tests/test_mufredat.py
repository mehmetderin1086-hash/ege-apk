"""Müfredat verisinin resmî belgeyle örtüştüğünü sabitleyen testler.

Bu dosya bir "veri kapısıdır": programın ürettiği her plan bu JSON'a dayanıyor,
dolayısıyla verideki sessiz bir kayıp bütün çıktıları bozar. Sayılar resmî
PDF'in 10-11. sayfalarındaki tema/süre tablolarından alınmıştır.
"""

from __future__ import annotations

import pytest

from ogretmen_cantasi import mufredat as m

# (sınıf, haftalık saat, tema saatleri, okul temelli planlama, toplam, çıktı sayısı)
BEKLENEN = [
    (9, 2, (38, 30), 4, 72, 15),
    (10, 2, (34, 34), 4, 72, 19),
    (11, 4, (69, 69), 6, 144, 22),
    (12, 4, (69, 69), 6, 144, 22),
]

TEMA_ADLARI = {
    9: ("YAŞAM", "ORGANİZASYON"),
    10: ("ENERJİ", "EKOLOJİ"),
    11: ("TEPKİ", "HOMEOSTAZİ"),
    12: ("ÜREME", "GEN"),
}


@pytest.fixture(scope="module")
def program() -> m.Mufredat:
    return m.yukle(m.MAARIF_2024)


def test_dort_sinif_duzeyi(program: m.Mufredat) -> None:
    assert sorted(program.siniflar) == [9, 10, 11, 12]


@pytest.mark.parametrize(("sinif", "haftalik", "tema_saatleri", "okul", "toplam", "cikti"), BEKLENEN)
def test_sinif_saatleri(
    program: m.Mufredat,
    sinif: int,
    haftalik: int,
    tema_saatleri: tuple[int, ...],
    okul: int,
    toplam: int,
    cikti: int,
) -> None:
    duzey = program.duzey(sinif)
    assert duzey.haftalik_ders_saati == haftalik
    assert tuple(t.ders_saati for t in duzey.temalar) == tema_saatleri
    assert duzey.okul_temelli_planlama_saati == okul
    assert duzey.toplam_ders_saati == toplam
    assert sum(tema_saatleri) + okul == toplam
    assert len(duzey.ogrenme_ciktilari) == cikti


@pytest.mark.parametrize(("sinif", "adlar"), TEMA_ADLARI.items())
def test_tema_adlari(program: m.Mufredat, sinif: int, adlar: tuple[str, str]) -> None:
    assert tuple(t.ad for t in program.duzey(sinif).temalar) == adlar


def test_toplam_ogrenme_ciktisi(program: m.Mufredat) -> None:
    toplam = sum(len(d.ogrenme_ciktilari) for d in program.siniflar.values())
    assert toplam == 78


def test_her_ciktinin_govdesi_dolu(program: m.Mufredat) -> None:
    for duzey in program.siniflar.values():
        for cikti in duzey.ogrenme_ciktilari:
            assert cikti.ifade, f"{cikti.kod} ifadesi boş"
            assert cikti.surec_bilesenleri, f"{cikti.kod} süreç bileşeni yok"
            assert all(b.ifade for b in cikti.surec_bilesenleri), f"{cikti.kod} boş bileşen"


def test_kod_bicimi_ve_sirasi(program: m.Mufredat) -> None:
    for duzey in program.siniflar.values():
        for tema in duzey.temalar:
            beklenen = [
                f"BİY.{duzey.sinif}.{tema.no}.{i}"
                for i in range(1, len(tema.ogrenme_ciktilari) + 1)
            ]
            assert [c.kod for c in tema.ogrenme_ciktilari] == beklenen


def test_her_temanin_metin_alanlari_dolu(program: m.Mufredat) -> None:
    alanlar = (
        "aciklama",
        "icerik_cercevesi",
        "ogrenme_kanitlari",
        "temel_kabuller",
        "on_degerlendirme",
        "kopru_kurma",
        "zenginlestirme",
        "destekleme",
    )
    for duzey in program.siniflar.values():
        for tema in duzey.temalar:
            for alan in alanlar:
                assert getattr(tema, alan).strip(), f"{duzey.sinif}/{tema.ad}: {alan} boş"
            assert tema.anahtar_kavramlar
            assert tema.alan_becerileri


def test_her_kazanimin_ogretme_uygulamasi_var(program: m.Mufredat) -> None:
    for duzey in program.siniflar.values():
        for tema in duzey.temalar:
            for cikti in tema.ogrenme_ciktilari:
                assert tema.uygulama(cikti.kod).strip(), f"{cikti.kod}: uygulama metni yok"


def test_ornek_kazanim_belgeyle_birebir(program: m.Mufredat) -> None:
    """PDF s.15'ten elle kopyalanmış bir kazanım — ayrıştırma kaymasının kanaryası."""
    cikti = program.cikti("BİY.9.1.5")
    assert cikti.ifade == "Canlıları sınıflandırabilme"
    assert [b.harf for b in cikti.surec_bilesenleri] == ["a", "b", "c", "ç"]
    assert cikti.surec_bilesenleri[0].ifade == (
        "Canlıları sınıflandırmak için kullanacağı nitelikleri belirler."
    )
    assert cikti.tema_adi == "YAŞAM"
    assert cikti.sinif == 9


def test_surum_secimi_12_sinifi_2018e_yollar() -> None:
    assert m.surum_sec("2026-2027", 11) == m.MAARIF_2024
    assert m.surum_sec("2026-2027", 12) == m.MFP_2018
    assert m.surum_sec("2027-2028", 12) == m.MAARIF_2024


def test_eksik_surum_acik_hata_verir() -> None:
    with pytest.raises(m.MufredatYok, match="mufredat_mfp_2018"):
        m.yukle(m.MFP_2018)
