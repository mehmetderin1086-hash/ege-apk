"""Quiz üretecinin sınıfta kullanılabilir çıktı verdiğinin sınırları."""

from __future__ import annotations

import pytest

from bioprof.studio.artifacts import (
    StudioEngine,
    StudioEvidence,
    _belirgin_terim,
    _bosluk_doldurma,
    _coktan_secmeli_secenekler,
    _zorluk,
)

METINLER = [
    "Fotosentez kloroplast organelinde gerçekleşir ve glukoz üretir.",
    "Mitokondri hücresel solunumla ATP sentezler.",
    "Ribozom protein sentezinden sorumlu organeldir.",
    "Lizozom hücre içi sindirimi gerçekleştiren organeldir.",
    "İnsan somatik hücresinde 23 kromozom çifti bulunur ve bu sayı türe özgüdür.",
]


def _kanitlar(adet: int = 5) -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label=f"S{i}",
            text=METINLER[i % len(METINLER)],
            source_title="Campbell Biyoloji",
            citation_id=f"c{i}",
            section=f"Bölüm {i}",
        )
        for i in range(1, adet + 1)
    ]


@pytest.fixture
def quiz():
    motor = StudioEngine()
    markdown, veri, uyarilar = motor._quiz("Hücre Sınavı", _kanitlar())
    return markdown, veri["questions"], uyarilar


class TestSoruCesitliligi:
    def test_sorular_birbirinin_ayni_degil(self, quiz):
        _markdown, sorular, _ = quiz
        metinler = [soru["question"] for soru in sorular]
        assert len(set(metinler)) == len(metinler)

    def test_birden_fazla_soru_bicimi_uretilir(self, quiz):
        _markdown, sorular, _ = quiz
        assert len({soru["type"] for soru in sorular}) >= 2

    def test_her_soru_kaynagini_tasir(self, quiz):
        _markdown, sorular, _ = quiz
        assert all(soru["citation"] and soru["citation_id"] for soru in sorular)

    def test_her_soru_zorluk_tasir(self, quiz):
        _markdown, sorular, _ = quiz
        assert all(soru["difficulty"] in {"kolay", "orta", "zor"} for soru in sorular)


class TestCoktanSecmeli:
    def test_celdiriciler_uydurulmaz_kardes_kanitlardan_gelir(self):
        kanitlar = _kanitlar()
        sonuc = _coktan_secmeli_secenekler(METINLER[0], kanitlar[1:])
        assert sonuc is not None
        harfler, dogru = sonuc
        kaynak_cumleleri = {" ".join(k.text.split()) for k in kanitlar}
        for secenek in harfler.values():
            assert any(secenek.rstrip("…") in cumle for cumle in kaynak_cumleleri)
        assert dogru in harfler.values()

    def test_yeterli_kardes_yoksa_uretilmez(self):
        assert _coktan_secmeli_secenekler(METINLER[0], _kanitlar(1)[:1]) is None

    def test_markdown_secenekleri_gosterir(self, quiz):
        markdown, sorular, _ = quiz
        if any(soru["type"] == "multiple_choice" for soru in sorular):
            assert "   A)" in markdown


class TestBoslukDoldurma:
    def test_belirgin_terim_bosaltilir(self):
        sonuc = _bosluk_doldurma("Fotosentez kloroplast organelinde gerçekleşir.")
        assert sonuc is not None
        govde, terim = sonuc
        assert "______" in govde
        assert terim not in govde

    def test_terim_yoksa_uretilmez(self):
        assert _bosluk_doldurma("Bu bir ve de ki") is None

    def test_dolgu_sozcugu_secilmez(self):
        assert _belirgin_terim("Bu bir olarak ile için") == ""


class TestZorluk:
    def test_kisa_cumle_kolay(self):
        assert _zorluk("Ribozom protein üretir.") == "kolay"

    def test_sayili_cumle_en_az_orta(self):
        assert _zorluk("Hücrede 23 çift bulunur.") in {"orta", "zor"}

    def test_uzun_cumle_zor(self):
        assert _zorluk(" ".join(["sözcük"] * 30)) == "zor"


class TestCevapAnahtari:
    def test_anahtar_her_soru_icin_satir_uretir(self, quiz):
        markdown, sorular, _ = quiz
        anahtar = markdown.split("## Cevap anahtarı", 1)[1]
        for soru in sorular:
            assert f"**{soru['id']}.**" in anahtar
