"""Boş VLM yanıtı ve görsel soyağacı için uçtan uca çözücü testleri."""

from __future__ import annotations

import json

from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.motor.temel import SahteGorselMotor


class _GorselDeposu:
    def oku(self, _imza: str) -> bytes:
        return b"sahte-gorsel-baytlari"


def _yanit(cevap: str, guven: float = 0.9) -> str:
    return json.dumps(
        {
            "adimlar": ["Görsel verisi okundu.", "Biyoloji kuralı uygulandı."],
            "cevap": cevap,
            "guven": guven,
            "konu": "ekoloji",
            "cozum_turu": "grafik_yorumlama",
            "uyari": "",
        },
        ensure_ascii=False,
    )


def _cozucu(depo, gomlemci, motor, ornekler=()):
    return Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur(list(ornekler), gomlemci),
        motor=motor,
        gomlemci=gomlemci,
        ayarlar=Ayarlar(onbellek_aktif=False, kalitim_araci=False),
        gorsel_deposu=_GorselDeposu(),
    )


def test_bos_gorsel_yanit_kisa_istemle_kurtarilir_ve_incelemeye_duser(
    depo, ornekler, sahte_gomlemci
):
    motor = SahteGorselMotor(["", _yanit("E")])
    cozucu = _cozucu(depo, sahte_gomlemci, motor, ornekler)

    cozum = cozucu.coz(
        "Trofik düzey grafiğine göre hangileri yapılamaz?",
        secenekler={"A": "Yalnız I", "E": "II ve III"},
        gorsel="imza",
        kaydet=False,
    )

    assert cozum.cevap == "E"
    assert cozum.guven <= 0.35
    assert cozum.incele
    assert len(motor.gorseller) == 2
    assert any("kısa bir istemle" in uyari for uyari in cozum.uyarilar)
    # Kurtarma isteminde uzun RAG diyalogları yoktur.
    assert not any(
        "[REFERANS ÇÖZÜM" in mesaj["content"]
        for mesaj in motor.cagrilar[1]
    )


def test_kisa_istem_de_bossa_cevap_uydurulmaz(depo, sahte_gomlemci):
    motor = SahteGorselMotor(["", ""])
    cozucu = _cozucu(depo, sahte_gomlemci, motor)

    cozum = cozucu.coz(
        "Grafikte hangisi doğrudur?",
        secenekler={"A": "bir", "B": "iki"},
        gorsel="imza",
        kaydet=False,
    )

    assert cozum.cevap == ""
    assert cozum.incele
    assert any("Nihai cevap boş" in uyari for uyari in cozum.uyarilar)


def test_soyagacinda_vlm_yalniz_aileyi_okur_python_a_sikkini_bulur(
    depo, sahte_gomlemci
):
    okuma = (
        "En alttaki çocuk bir hasta dişi ve hemen üstündeki anne ve "
        "babanın her ikisi de sağlıklıdır."
    )
    motor = SahteGorselMotor(okuma)
    cozucu = _cozucu(depo, sahte_gomlemci, motor)
    soru = (
        "Aşağıdaki soyağacında bir hastalığın kalıtımı verilmiştir. "
        "I. Otozomal çekinik olarak kalıtılmaktadır. "
        "II. Otozomal baskın olarak kalıtılmaktadır. "
        "III. X kromozomundaki çekinik bir alelle kalıtılmaktadır. "
        "ifadelerinden hangileri doğru olabilir?"
    )
    siklar = {
        "A": "Yalnız I",
        "B": "Yalnız III",
        "C": "I ve lI",
        "D": "I ve III",
        "E": "II ve III",
    }

    cozum = cozucu.coz(soru, secenekler=siklar, gorsel="imza", kaydet=False)

    assert cozum.cevap == "A"
    assert cozum.uretim_yontemi == "soyagaci_araci"
    assert cozum.incele, "görsel sembol okuması her zaman doğrulanmalı"
    assert len(motor.gorseller) == 1
    assert "otozomal" not in motor.cagrilar[0][0]["content"].casefold()
    assert any("babanın da hasta" in adim for adim in cozum.adimlar)


def test_soyagaci_okunamazsa_serbest_model_cevabi_yuksek_guvenle_gecmez(
    depo, sahte_gomlemci
):
    motor = SahteGorselMotor(["BELİRSİZ", _yanit("D", guven=0.99)])
    cozucu = _cozucu(depo, sahte_gomlemci, motor)
    soru = (
        "Soyağacında I. otozomal çekinik, II. otozomal baskın ve "
        "III. X kromozomundaki çekinik kalıtımlardan hangileri doğru olabilir?"
    )
    siklar = {"A": "Yalnız I", "D": "I ve III", "E": "II ve III"}

    cozum = cozucu.coz(soru, secenekler=siklar, gorsel="imza", kaydet=False)

    assert cozum.cevap == "D"
    assert cozum.guven <= 0.35
    assert cozum.incele
    assert any("tek anlamlı doğrulanamadı" in u for u in cozum.uyarilar)


def test_akisli_gorsel_yol_da_bos_yaniti_kurtarir(depo, sahte_gomlemci):
    motor = SahteGorselMotor(["", _yanit("B")])
    cozucu = _cozucu(depo, sahte_gomlemci, motor)

    olaylar = list(
        cozucu.coz_akis(
            "Grafikte hangisi doğrudur?",
            secenekler={"A": "bir", "B": "iki"},
            gorsel="imza",
            kaydet=False,
        )
    )
    cozum = next(veri for ad, veri in olaylar if ad == "bitti")

    assert cozum.cevap == "B"
    assert cozum.incele
    assert any(
        ad == "durum" and "kısa istemle" in str(veri) for ad, veri in olaylar
    )
