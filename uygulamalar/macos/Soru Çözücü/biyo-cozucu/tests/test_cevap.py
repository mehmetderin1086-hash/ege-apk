"""Cevap kanonikleştirme testleri — özellikle sayısal şık eşleşmesi.

`test_cozucu.py` mevcut metinsel davranışı zaten sınıyor; burada `cevap`
modülüne taşınmayla gelen SAYISAL yol test ediliyor. Bu yol ölçülmüş bir
hatayı kapatıyor: model doğru cevabı "1/8" diye verdiğinde şık metni "8\\n1"
ile eşleşmiyor ve DOĞRU cevap "şıklarla eşleşmiyor" sayılıp cezalandırılıyordu.
"""

from __future__ import annotations

import pytest

from biyo_cozucu.cevap import cevap_eslesiyor, sik_harfi

# Gerçek soru: AabbNnRrhh → tüm genleri çekinik gamet olasılığı = (1/2)³ = 1/8
GERCEK_SORU = (
    "AabbNnRrhh genotipindeki bir canlının tüm genleri çekinik olan bir "
    "gamet oluşturma olasılığı kaçtır?"
)
GERCEK_SIKLAR = {"A": "2\n1", "B": "4\n1", "C": "8\n1", "D": "16\n1", "E": "32\n1"}


@pytest.mark.parametrize("ham", ["1/8", "0,125", "%12,5"])
def test_sayisal_cevap_yigin_sikka_eslesir(ham):
    """Model kesri düz yazınca yığın şıkla eşleşmeli."""
    assert sik_harfi(ham, GERCEK_SIKLAR, soru=GERCEK_SORU) == "C"


def test_sayisal_yol_metinsel_yoldan_sonra_gelir():
    """Harf cevabı hâlâ öncelikli — sayısal yol yalnız geri düşüş."""
    assert sik_harfi("C", GERCEK_SIKLAR, soru=GERCEK_SORU) == "C"
    assert sik_harfi("Cevap: B", GERCEK_SIKLAR, soru=GERCEK_SORU) == "B"


def test_soru_verilmezse_yigin_sirali_okunur():
    """`soru` yoksa yön kestirilemez; varsayılan sıralı olduğu için eşleşme olmaz.

    Bu bilinçli: kendinden emin yanlış eşleşme, eşleşmemekten zararlıdır.
    """
    assert sik_harfi("1/8", GERCEK_SIKLAR) == ""


def test_birden_cok_sik_ayni_degere_okunursa_bos_doner():
    siklar = {"A": "4\n1", "B": "8\n2", "C": "3\n1"}  # A ve B ikisi de 1/4
    assert sik_harfi("1/4", siklar, soru=GERCEK_SORU) == ""


def test_hic_eslesmezse_bos_doner():
    assert sik_harfi("7/9", GERCEK_SIKLAR, soru=GERCEK_SORU) == ""
    assert sik_harfi("", GERCEK_SIKLAR, soru=GERCEK_SORU) == ""


def test_sirali_yigin_kesir_sanilmaz():
    """(I) ve (II) soran soruda yığın sıralı okunur; "1/2" eşleşmemeli."""
    soru = "... hücresinin (I) ve yavru hücrelerin (II) kromozom sayısı kaçtır?"
    siklar = {"A": "20\n10", "B": "40\n20", "C": "20\n20"}
    assert sik_harfi("1/2", siklar, soru=soru) == ""
    # Sıralı çift olarak verilirse metinsel yol zaten yakalıyor: `sadelestir`
    # noktalamayı attığı için "40, 20" ile "40\n20" aynı diziye iniyor.
    assert sik_harfi("40, 20", siklar, soru=soru) == "B"


@pytest.mark.parametrize(
    "uretilen, beklenen, sonuc",
    [
        ("1/8", "0,125", True),
        ("%25", "1/4", True),
        ("3:1", "9:3", True),  # oran sadeleşerek eşleşir
        ("1/8", "1/16", False),
        ("C", "C", True),
        # `sadelestir` noktalamayı attığı için "1/2" ile "1:2" METİNSEL olarak
        # zaten eşleşiyor (ikisi de "1 2"). Bu, sayısal yoldan önce gelen ve
        # bu değişiklikten önce de var olan bir davranış — burada belgeleniyor.
        ("1/2", "1:2", True),
    ],
)
def test_cevap_eslesiyor_sayisal(uretilen, beklenen, sonuc):
    assert cevap_eslesiyor(uretilen, beklenen) is sonuc
