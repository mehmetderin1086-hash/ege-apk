"""Cevap türü çıkarımı ve türe göre biçim denetimi.

Program eskiden yalnız "şık var mı" diye bakıyordu: doğru/yanlış, boşluk
doldurma, eşleştirme ve sıralama soruları sessizce açık uçlu sayılıyor,
modele yanlış biçim talimatı gidiyor ve cevap hiç denetlenmiyordu.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.istemler import CEVAP_BICIMLERI, cevap_bicimi, cozum_mesajlari
from biyo_cozucu.modeller import CEVAP_TURLERI, CEVAP_TURU_ADLARI
from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.soru_turu import bosluk_sayisi, cevap_turunu_cikar

# --- tür çıkarımı ---


@pytest.mark.parametrize(
    "soru,beklenen",
    [
        ("Aşağıdaki ifade doğru mu yanlış mı?", "dogru_yanlis"),
        ("Mitoz bölünmede kromozom sayısı değişir. (D/Y)", "dogru_yanlis"),
        ("Aşağıdaki ifadelerin doğru olanlarını işaretleyiniz.", "dogru_yanlis"),
        ("Fotosentez …… organelinde gerçekleşir.", "bosluk_doldurma"),
        ("Boşlukları doldurunuz: hücre zarı ___ yapıdadır.", "bosluk_doldurma"),
        ("Organelleri görevleriyle eşleştiriniz.", "eslestirme"),
        ("Verilenleri uygun şekilde eşleştirme yapınız.", "eslestirme"),
        ("Mitoz evrelerini sırasıyla sıralayınız.", "siralama"),
        ("Olayları doğru sıralama ile yazınız.", "siralama"),
        ("Bir glikozdan kaç ATP üretilir?", "kisa_cevap"),
        ("Kloroplastın adını yazınız.", "kisa_cevap"),
        ("Fotosentez nasıl gerçekleşir açıklayınız?", "acik_uclu"),
        ("Mitoz ve mayozu karşılaştırınız.", "acik_uclu"),
    ],
)
def test_soru_metninden_tur_cikarilir(soru, beklenen):
    assert cevap_turunu_cikar(soru) == beklenen


def test_siklar_coktan_secmeli_yapar():
    assert cevap_turunu_cikar(
        "Hangisi doğrudur?", {"A": "bir", "B": "iki"}
    ) == "coktan_secmeli"


def test_dogru_yanlis_siklari_coktan_secmeli_sayilmaz():
    """Şıkları yalnız Doğru/Yanlış olan soru çoktan seçmeli değildir."""
    assert cevap_turunu_cikar(
        "Mitozda kromozom sayısı korunur.", {"A": "Doğru", "B": "Yanlış"}
    ) == "dogru_yanlis"
    assert cevap_turunu_cikar(
        "İfade doğru mudur?", {"D": "D", "Y": "Y"}
    ) == "dogru_yanlis"


def test_aciklama_isteyen_kac_sorusu_kisa_cevap_sayilmaz():
    """"Kaç ATP üretilir, açıklayınız" bir kısa cevap sorusu değildir."""
    assert cevap_turunu_cikar(
        "Bir glikozdan kaç ATP üretilir, açıklayınız?"
    ) == "acik_uclu"


def test_bosluk_sayisi_dogru_sayilir():
    assert bosluk_sayisi("…… organelinde …… gerçekleşir") == 2
    assert bosluk_sayisi("___ ve ___ ve ___") == 3
    assert bosluk_sayisi("boşluk yok") == 0


# --- istem biçimi ---


def test_her_tur_icin_bicim_talimati_var():
    for tur in CEVAP_TURLERI:
        assert tur in CEVAP_BICIMLERI, f"{tur} için biçim talimatı yok"
        assert CEVAP_BICIMLERI[tur].strip()


def test_her_turun_gorunur_adi_var():
    for tur in CEVAP_TURLERI:
        assert CEVAP_TURU_ADLARI.get(tur), f"{tur} için görünür ad yok"


def test_bicim_talimati_isteme_giriyor():
    mesajlar = cozum_mesajlari(
        "Mitoz evrelerini sıralayınız?", [], cevap_turu="siralama"
    )
    son = mesajlar[-1]["content"]
    assert "[CEVAP BİÇİMİ]" in son
    assert cevap_bicimi("siralama") in son


def test_tur_verilmezse_bicim_talimati_eklenmez():
    mesajlar = cozum_mesajlari("Soru?", [])
    assert "[CEVAP BİÇİMİ]" not in mesajlar[-1]["content"]


# --- türe göre cevap denetimi ---


def _cozucu(depo, gomlemci, yanit):
    return Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur([], gomlemci),
        motor=SahteMotor(yanit),
        gomlemci=gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False),
    )


def _yanit(cevap, adimlar=("adım bir", "adım iki"), guven=0.9):
    return json.dumps(
        {"adimlar": list(adimlar), "cevap": cevap, "guven": guven, "uyari": ""},
        ensure_ascii=False,
    )


@pytest.mark.parametrize(
    "ham,beklenen",
    [("D", "Doğru"), ("d", "Doğru"), ("Doğru", "Doğru"),
     ("Y", "Yanlış"), ("yanlış", "Yanlış"), ("Yanlış.", "Yanlış")],
)
def test_dogru_yanlis_cevabi_normallestirilir(depo, sahte_gomlemci, ham, beklenen):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit(ham))
    cozum = cozucu.coz("Mitozda kromozom sayısı korunur. (D/Y)")
    assert cozum.cevap_turu == "dogru_yanlis"
    assert cozum.cevap == beklenen
    assert not any("değil" in u for u in cozum.uyarilar)


def test_dogru_yanlis_disi_cevap_uyari_uretir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("Kısmen doğrudur çünkü"))
    cozum = cozucu.coz("Mitozda kromozom sayısı korunur. (D/Y)")
    assert any("Doğru' ya da 'Yanlış" in u for u in cozum.uyarilar)
    assert cozum.guven <= 0.35


def test_bosluk_sayisi_uyusmazsa_uyarir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("kloroplast"))
    cozum = cozucu.coz("Fotosentez …… organelinin …… bölümünde gerçekleşir.")
    assert cozum.cevap_turu == "bosluk_doldurma"
    assert any("2 boşluk" in u for u in cozum.uyarilar)
    assert cozum.guven <= 0.4


def test_bosluk_cevabi_dogru_sayidaysa_uyarmaz(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("kloroplast, tilakoit"))
    cozum = cozucu.coz("Fotosentez …… organelinin …… bölümünde gerçekleşir.")
    assert cozum.cevap == "kloroplast, tilakoit"
    assert not any("boşluk" in u for u in cozum.uyarilar)


def test_eslestirme_cevabi_kanonik_hale_gelir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("I - C, II – a, III/B"))
    cozum = cozucu.coz("Organelleri görevleriyle eşleştiriniz.")
    assert cozum.cevap_turu == "eslestirme"
    assert cozum.cevap == "I-c, II-a, III-b"


def test_eslestirme_bicimsiz_cevabi_uyarir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("Mitokondri solunum yapar"))
    cozum = cozucu.coz("Organelleri görevleriyle eşleştiriniz.")
    assert any("eşleştirme çifti" in u for u in cozum.uyarilar)


def test_siralama_cevabi_ogelere_ayrilir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("III > I > IV > II"))
    cozum = cozucu.coz("Mitoz evrelerini sırasıyla sıralayınız.")
    assert cozum.cevap_turu == "siralama"
    assert cozum.cevap == "III, I, IV, II"


def test_siralama_tek_ogeli_cevabi_uyarir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("Profaz"))
    cozum = cozucu.coz("Mitoz evrelerini sırasıyla sıralayınız.")
    assert any("en az iki öğe" in u for u in cozum.uyarilar)


def test_kisa_cevaba_paragraf_donerse_uyarir(depo, sahte_gomlemci):
    uzun = " ".join(["sözcük"] * 20)
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit(uzun))
    cozum = cozucu.coz("Bir glikozdan kaç ATP üretilir?")
    assert cozum.cevap_turu == "kisa_cevap"
    assert any("uzun bir açıklama" in u for u in cozum.uyarilar)


def test_elle_verilen_tur_cikarimi_ezer(depo, sahte_gomlemci):
    """Öğretmen türü seçtiyse metin ipuçları onu geçersiz kılmamalı."""
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("Uzun bir açıklama cümlesi."))
    cozum = cozucu.coz("Bir glikozdan kaç ATP üretilir?", cevap_turu="acik_uclu")
    assert cozum.cevap_turu == "acik_uclu"
    assert not any("uzun bir açıklama" in u for u in cozum.uyarilar)


def test_coktan_secmeli_davranisi_korunuyor(depo, sahte_gomlemci):
    """Yeni türler eklendi diye eski yol bozulmamalı."""
    cozucu = _cozucu(depo, sahte_gomlemci, _yanit("B)"))
    cozum = cozucu.coz("Hangisi doğrudur?", secenekler={"A": "bir", "B": "iki"})
    assert cozum.cevap_turu == "coktan_secmeli"
    assert cozum.cevap == "B"
