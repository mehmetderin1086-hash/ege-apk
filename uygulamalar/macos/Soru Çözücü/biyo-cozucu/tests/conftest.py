"""Ortak test fixture'ları — hepsi çevrimdışı ve deterministik."""

from __future__ import annotations

import atexit
import hashlib
import os
import tempfile
from pathlib import Path

# Test modülleri ``biyo_cozucu.cozucu``yu koleksiyon aşamasında içe aktarıyor
# ve veri kökünü o anda sabitliyor. Ortamı fixture içinde değiştirmek artık
# çok geç olur; gerçek ``~/.biyo-cozucu/biyo.db`` dosyası açılabilir. Bu kök
# bütün proje modüllerinden ÖNCE hazırlanır, süreç sonunda otomatik temizlenir.
_TEST_ALANI = tempfile.TemporaryDirectory(prefix="biyo-cozucu-test-")
atexit.register(_TEST_ALANI.cleanup)
_TEST_KOK = Path(_TEST_ALANI.name)
os.environ["BIYO_VERI"] = str(_TEST_KOK / "veri")
os.environ["EASYOCR_MODULE_PATH"] = str(_TEST_KOK / "easyocr")
os.environ["HF_HOME"] = str(_TEST_KOK / "huggingface")
os.environ["HF_HUB_OFFLINE"] = "1"
os.environ["TRANSFORMERS_OFFLINE"] = "1"

import numpy as np  # noqa: E402 - izolasyon uygulama importlarından önce kurulmalı
import pytest  # noqa: E402 - aynı neden

from biyo_cozucu.depo import Depo  # noqa: E402 - aynı neden
from biyo_cozucu.hafiza.indeks import terimler  # noqa: E402 - aynı neden
from biyo_cozucu.modeller import Ornek  # noqa: E402 - aynı neden


class SahteGomlemci:
    """Karma tabanlı deterministik gömlemci.

    Gerçek modelin yerine geçmez ama sözcük örtüşmesini benzerliğe çevirir:
    aynı terimleri paylaşan metinler yüksek kosinüs değeri alır. Bu sayede
    erişim testleri anlamlı kalırken hiçbir model indirilmez.
    """

    model_adi = "sahte-gomlemci"
    boyut = 64

    def gom(self, metinler: list[str], *, sorgu: bool = False) -> np.ndarray:
        vektorler = np.zeros((len(metinler), self.boyut), dtype=np.float32)
        for i, metin in enumerate(metinler):
            for terim in terimler(metin):
                # md5 burada güvenlik için değil, terimden kovaya deterministik
                # ve süreçler arası kararlı eşleme için kullanılıyor
                # (`hash()` PYTHONHASHSEED ile değişir ve testi kırılgan yapar).
                kova = int(
                    hashlib.md5(terim.encode(), usedforsecurity=False).hexdigest()[:8], 16
                ) % self.boyut
                vektorler[i, kova] += 1.0
        normlar = np.clip(np.linalg.norm(vektorler, axis=1, keepdims=True), 1e-9, None)
        return vektorler / normlar


@pytest.fixture
def sahte_gomlemci() -> SahteGomlemci:
    return SahteGomlemci()


@pytest.fixture
def ornekler() -> list[Ornek]:
    return [
        Ornek(
            id=1,
            soru="Mitoz bölünme sonucu oluşan hücrelerin kromozom sayısı neden ana hücreyle aynıdır?",
            cozum=(
                "Mitozdan önce interfazda DNA kendini eşler.\n"
                "Kardeş kromatitler anafazda zıt kutuplara çekilir.\n"
                "Her yeni hücreye kromozomların bir takımı düşer."
            ),
            cevap="DNA eşlendiği için kromozom sayısı korunur",
            cevap_turu="acik_uclu",
            konu="hücre bölünmesi",
            cozum_turu="mekanizma_aciklama",
        ),
        Ornek(
            id=2,
            soru=(
                "Aa genotipli iki bireyin çaprazlanmasında çekinik fenotipli birey "
                "oluşma olasılığı kaçtır?"
            ),
            cozum=(
                "Aa x Aa çaprazlamasında açılım 1AA : 2Aa : 1aa olur.\n"
                "Çekinik fenotip yalnız aa genotipinde görülür.\n"
                "Bu da 4 bireyden 1'i, yani 1/4 olasılıktır."
            ),
            cevap="1/4",
            cevap_turu="kisa_cevap",
            konu="kalıtım",
            cozum_turu="kalitim_hesabi",
        ),
        Ornek(
            id=3,
            soru=(
                "Fotosentez hızının ışık şiddetine bağlı grafiğinde belirli bir "
                "noktadan sonra hızın sabitlenmesinin nedeni nedir?"
            ),
            cozum=(
                "Grafikte hız önce ışıkla doğru orantılı artar.\n"
                "Belirli bir noktadan sonra ışık sınırlayıcı faktör olmaktan çıkar.\n"
                "Karbondioksit veya sıcaklık gibi başka bir faktör sınırlayıcı olur."
            ),
            cevap="Başka bir faktör sınırlayıcı hale gelir",
            cevap_turu="acik_uclu",
            konu="fotosentez",
            cozum_turu="grafik_yorumlama",
        ),
        Ornek(
            id=4,
            soru=(
                "Bir hücrede 2n=8 kromozom varsa mayoz sonucu oluşan hücrelerde "
                "kaç kromozom bulunur?\nA) 2\nB) 4\nC) 8\nD) 16"
            ),
            secenekler={"A": "2", "B": "4", "C": "8", "D": "16"},
            cozum=(
                "Mayoz kromozom sayısını yarıya indirir.\n"
                "2n=8 olan hücrede n=4 olur.\n"
                "A, C ve D seçenekleri yarıya inme kuralına uymadığı için elenir."
            ),
            cevap="B",
            cevap_turu="coktan_secmeli",
            konu="hücre bölünmesi",
            cozum_turu="hesaplama",
        ),
        Ornek(
            id=5,
            soru="Enzimlerin çalışmasında optimum sıcaklık aşıldığında ne olur?",
            cozum=(
                "Yüksek sıcaklık protein yapısındaki bağları bozar.\n"
                "Enzimin aktif bölgesi şeklini kaybeder, denatürasyon olur.\n"
                "Substrat bağlanamadığı için tepkime hızı düşer."
            ),
            cevap="Denatüre olur ve tepkime hızı düşer",
            cevap_turu="acik_uclu",
            konu="enzimler",
            cozum_turu="mekanizma_aciklama",
        ),
    ]


@pytest.fixture
def depo(tmp_path) -> Depo:
    return Depo(tmp_path / "test.db")


@pytest.fixture
def dolu_depo(depo, ornekler) -> Depo:
    for ornek in ornekler:
        depo.ornek_ekle(ornek)
    return depo
