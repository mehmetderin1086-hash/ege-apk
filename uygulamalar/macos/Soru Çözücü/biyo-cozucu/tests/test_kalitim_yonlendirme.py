"""Kalıtım sorusunun kural katmanına ULAŞMASI ve boşluğun görünürlüğü.

50 soruluk ölçüm koşusunda `kalitim_araci` sıfır kez çalışmıştı: 9 kalıtım
sorusunun 6'sı tespit kapısında eleniyordu, çünkü kapı yalnız nicel sözcük
("olasılık", "oran") arıyordu — oysa sorular yargı biçimindeydi.
"""

from __future__ import annotations

import pytest

from biyo_cozucu.kalitim.tespit import kalitim_adayi_mi

SIKLAR = {"A": "Yalnız I", "B": "I ve II", "C": "II ve III", "D": "I, II ve III"}


@pytest.mark.parametrize(
    "soru",
    [
        "Hemofili X kromozomu üzerindeki çekinik alelle kalıtılır. Buna göre "
        "verilenlerden hangileri doğrudur?",
        "Taşıyıcı anne ve sağlıklı babanın çocukları için hangisi kesinlikle "
        "doğrudur?",
        "Bu çaprazlamayla ilgili aşağıdakilerden hangisi söylenebilir?",
    ],
)
def test_yargi_bicimli_kalitim_sorusu_kural_katmanina_ulasir(soru):
    assert kalitim_adayi_mi(soru, SIKLAR)


@pytest.mark.parametrize(
    "soru",
    [
        "AaBb x AaBb çaprazlamasında beklenen fenotip oranı nedir?",
        "Bu çaprazlamada kaç farklı genotip oluşur?",
    ],
)
def test_nicel_sorular_gecmeye_devam_eder(soru):
    assert kalitim_adayi_mi(soru, SIKLAR)


@pytest.mark.parametrize(
    "soru",
    [
        "Mitokondrinin temel görevi nedir?",
        "Fotosentezde hangileri doğrudur?",
        "Aşağıdakilerden hangisi doğrudur?",
    ],
)
def test_kalitim_disi_sorular_gecmez(soru):
    """Kapıyı genişletmek her yargı sorusunu içeri almamalı: alan sözcüğü şart."""
    assert not kalitim_adayi_mi(soru, SIKLAR)


def test_baglam_kural_katmani_sonucunu_tasir():
    from biyo_cozucu.cozucu import _Baglam

    baglam = _Baglam(soru="s")
    assert baglam.kalitim_bagvurusu == ""
    baglam.kalitim_bagvurusu = "hesaplandi_baglanamadi"
    assert baglam.kalitim_bagvurusu == "hesaplandi_baglanamadi"
