"""Yığın kesir okuma testleri.

Vakaların çoğu soru bankasından alınmış GERÇEK sorulardır; beklenen değer
biyolojik olarak elle hesaplanıp doğrulandı. Uydurma vakayla test etmek
burada işe yaramaz: kuralın kendisi veriden çıkarıldı, dolayısıyla veriye
karşı sınanmalı.
"""

from __future__ import annotations

from fractions import Fraction

import pytest

from biyo_cozucu import kesir

# --- yığın ayrıştırma ---


@pytest.mark.parametrize(
    "sik, beklenen",
    [
        ("8\n1", (8, 1)),
        ("16\n3", (16, 3)),
        (" 4 \n 1 ", (4, 1)),
        ("3\n1\n2", (3, 1, 2)),
        ("1", None),  # tek satır yığın değil
        ("Azalır\nArtar", None),  # sayısal değil
        ("50\n1\n2\nYaş (yıl)", None),  # karışık — grafik etiketi
        ("", None),
    ],
)
def test_sayisal_yigin(sik, beklenen):
    assert kesir.sayisal_yigin(sik) == beklenen


# --- yön kuralı ---


@pytest.mark.parametrize(
    "soru, n, beklenen",
    [
        # Gerçek: olasılık sorusu, iki satır → kesir
        ("AabbNnRrhh genotipindeki bir canlının tüm genleri çekinik olan bir "
         "gamet oluşturma olasılığı kaçtır?", 2, "kesir"),
        ("... hasta olma ihtimali kaçtır?", 2, "kesir"),
        # Gerçek: parantezli yuva işareti → sıralı (iki ayrı değer isteniyor)
        ("Yukarıda genotipi verilen hücrenin mayoz bölünme sonucu "
         "oluşturabileceği en az (I) ve en çok (II) gamet çeşidi kaçtır?", 2, "sirali"),
        ("... ekvatoriyal düzleme 20 tetratın dizildiği bir hayvan hücresinin (I) "
         "ve yavru hücrelerin (II) kromozom sayısı ...", 2, "sirali"),
        # Üç satır her zaman sıralı
        ("X, Y ve Z bölgeleri ile ilgili eşleştirilmesi hangisinde doğrudur?", 3, "sirali"),
        # Gerçek tuzak: "I. Aile" / "II. Aile" VARLIKLARI sıralar, cevabı bölmez.
        # Noktalı roma rakamı sıralı işareti sayılsaydı bu soru yanlış sınıflanırdı.
        ("Aşağıda iki farklı aileye ait bireylerden 0 kan grubunda olanlar koyu "
         "renkli verilmiştir. I. Aile II. Aile Birinci ailede ... olasılığı kaçtır?",
         2, "kesir"),
        # İpucu yoksa varsayılan sıralı (kendinden emin yanlış eşleşmeden kaçın)
        ("Aşağıdakilerden hangisi doğrudur?", 2, "sirali"),
        ("... sırasıyla kaçtır?", 2, "sirali"),
    ],
)
def test_yigin_yonu(soru, n, beklenen):
    assert kesir.yigin_yonu(soru, n) == beklenen


# --- yığından kesir + veto ---


def test_yigindan_kesir_alt_bolu_ust():
    assert kesir.yigindan_kesir((8, 1)) == Fraction(1, 8)
    assert kesir.yigindan_kesir((16, 3)) == Fraction(3, 16)


def test_yigindan_kesir_birden_buyukse_veto():
    """Olasılık 1'i aşamaz; aşıyorsa yığın sıralı okunmalıydı."""
    assert kesir.yigindan_kesir((2, 8)) is None
    assert kesir.yigindan_kesir((1, 5)) is None


def test_yigindan_kesir_paydasi_sifir():
    assert kesir.yigindan_kesir((0, 1)) is None


# --- gerçek sorular: uçtan uca ---


@pytest.mark.parametrize(
    "soru, sik, beklenen",
    [
        # (1/2)³ = 1/8 — Aa, Nn, Rr heterozigot; bb ve hh zaten çekinik
        ("AabbNnRrhh genotipindeki bir canlının tüm genleri çekinik olan bir "
         "gamet oluşturma olasılığı kaçtır?", "8\n1", Fraction(1, 8)),
        # SsKk × Sskk → siyah 3/4 × kısa 1/2 × dişi 1/2 = 3/16
        ("SsKk dişi fare ile Sskk erkek farenin siyah ve kısa kıllı dişi yavru "
         "olma olasılığı kaçtır?", "16\n3", Fraction(3, 16)),
        # Aa × Aa, art arda iki çocuk hasta = (1/4)² = 1/16
        ("Heterozigot anne ve babadan art arda doğan iki çocuğun hasta olma "
         "ihtimali kaçtır?", "16\n1", Fraction(1, 16)),
        # Kesinlik ucu: renk körü anne × kıllı kulaklı baba → oğulların TAMAMI
        ("Renk körü bir anne ile kıllı kulaklı bir babanın erkek çocuklarının hem "
         "renk körü hem de kıllı kulaklı olma ihtimali kaçtır?", "1", Fraction(1)),
        # Kesinlik ucu: dazlak olmayan babadan kız çocuğa D aleli geçemez
        ("Dazlak olmayan erkek ve kadının kız çocuklarının dazlak olma "
         "olasılığı kaçtır?", "0", Fraction(0)),
        # Sıralı: I = 40 kromozom, II = 20
        ("20 tetratın dizildiği hücrenin (I) ve yavru hücrelerin (II) kromozom "
         "sayısı hangisinde doğru verilmiştir?", "40\n20", (40, 20)),
    ],
)
def test_oku_gercek_sorular(soru, sik, beklenen):
    assert kesir.oku(sik, soru=soru) == beklenen


def test_yalin_tamsayi_olasilik_disinda_kesir_sayilmaz():
    """"16" bir sayım cevabıdır; olasılık sorulmuyorsa kesre çevrilmemeli."""
    assert kesir.oku("16", soru="Kaç çeşit gamet oluşur?") is None
    # 0/1 bile olasılık ipucu yoksa kesir değil
    assert kesir.oku("1", soru="Kaç tetrat oluşur?") is None


# --- tek satırlık biçimler ---


@pytest.mark.parametrize(
    "metin, beklenen",
    [
        ("1/8", Fraction(1, 8)),
        ("3 / 16", Fraction(3, 16)),
        ("%18,75", Fraction(3, 16)),
        ("18.75 %", Fraction(3, 16)),
        ("0,25", Fraction(1, 4)),
        ("16", None),  # yalın tam sayı kesir değil
        ("abc", None),
        ("1/0", None),
    ],
)
def test_kesir_oku(metin, beklenen):
    assert kesir.kesir_oku(metin) == beklenen


@pytest.mark.parametrize(
    "metin, beklenen",
    [
        ("3:1", (3, 1)),
        ("9 : 3 : 3 : 1", (9, 3, 3, 1)),
        ("2:4", (1, 2)),  # sadeleşir
        ("1 : 2 : 1", (1, 2, 1)),
        ("3", None),
    ],
)
def test_oran_oku(metin, beklenen):
    assert kesir.oran_oku(metin) == beklenen


# --- eşdeğerlik ---


def test_esdeger():
    assert kesir.esdeger(Fraction(1, 8), Fraction(2, 16))
    assert kesir.esdeger((9, 3, 3, 1), (18, 6, 6, 2))
    assert not kesir.esdeger(Fraction(1, 2), (1, 2))  # kesir ile oran aynı şey değil
    assert not kesir.esdeger(None, Fraction(1, 2))
    assert not kesir.esdeger(Fraction(1, 2), Fraction(1, 3))


def test_normalize():
    soru = "... olasılığı kaçtır?"
    assert kesir.normalize("8\n1", soru=soru) == "1/8"
    assert kesir.normalize("9 : 3 : 3 : 1") == "9, 3, 3, 1"
    assert kesir.normalize("Yalnız  III") == "Yalnız III"
