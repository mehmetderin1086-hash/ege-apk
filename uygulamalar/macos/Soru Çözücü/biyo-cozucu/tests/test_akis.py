"""Akışlı üretim testleri.

Akış bir gösterim katmanıdır: `coz_akis()` ile `coz()` aynı girdide birebir
aynı çözümü üretmeli. Bu dosya o eşitliği ve akışın kendine özgü davranışlarını
(olay sırası, motorsuz yol, hata yolu) kilitler.
"""

from __future__ import annotations

import json

import pytest

from biyo_cozucu.cozucu import Ayarlar, Cozucu
from biyo_cozucu.hafiza.indeks import OrnekIndeksi
from biyo_cozucu.motor.temel import (
    AkanMotor,
    SahteMotor,
    akisa_dus,
)


def _yanit(adimlar, cevap, guven=0.9, **ek) -> str:
    veri = {"adimlar": adimlar, "cevap": cevap, "guven": guven, "uyari": ""}
    veri.update(ek)
    return json.dumps(veri, ensure_ascii=False)


def _cozucu(depo, gomlemci, motor, **ayar):
    return Cozucu(
        depo=depo,
        indeks=OrnekIndeksi.kur([], gomlemci),
        motor=motor,
        gomlemci=gomlemci,
        ayarlar=Ayarlar(**ayar),
    )


def _olaylari_topla(akis):
    parcalar, durumlar, cozum = [], [], None
    for ad, veri in akis:
        if ad == "parca":
            parcalar.append(veri)
        elif ad == "durum":
            durumlar.append(veri)
        elif ad == "bitti":
            cozum = veri
    return "".join(parcalar), durumlar, cozum


# --- motor katmanı ---


class _AkissizMotor:
    ad = "akissiz"

    def uret(self, mesajlar, *, sicaklik=0.2, azami_token=1536) -> str:
        return "tek parça yanıt"


def test_sahte_motor_akan_protokolu_karsilar():
    assert isinstance(SahteMotor("x"), AkanMotor)
    assert not isinstance(_AkissizMotor(), AkanMotor)


def test_akisa_dus_akissiz_motoru_tek_parca_verir():
    parcalar = list(akisa_dus(_AkissizMotor(), []))
    assert parcalar == ["tek parça yanıt"]


def test_sahte_motor_parca_boyuna_gore_dilimler():
    motor = SahteMotor("abcdefg", parca_boyu=3)
    assert list(motor.uret_akis([])) == ["abc", "def", "g"]


def test_akis_parcalari_birlestiginde_tam_yaniti_verir():
    tam = _yanit(["ilk adım", "ikinci adım"], "B")
    motor = SahteMotor(tam, parca_boyu=7)
    assert "".join(motor.uret_akis([])) == tam


# --- çözücü: akışlı ve akışsız eşitliği ---


@pytest.mark.parametrize("parca_boyu", [1, 5, 40, 0])
def test_akisli_ve_akissiz_ayni_cozumu_uretir(depo, sahte_gomlemci, parca_boyu):
    """Aynı ham yanıt, hangi yolla gelirse gelsin aynı Cozum'a çözülmeli."""
    ham = _yanit(["Mitoz interfazda başlar.", "Kromatitler ayrılır."], "B", guven=0.8)

    duz = _cozucu(depo, sahte_gomlemci, SahteMotor(ham), onbellek_aktif=False)
    beklenen = duz.coz("Mitoz nasıl işler?", secenekler={"A": "bir", "B": "iki"})

    akan = _cozucu(
        depo, sahte_gomlemci, SahteMotor(ham, parca_boyu=parca_boyu),
        onbellek_aktif=False,
    )
    _metin, _durumlar, gelen = _olaylari_topla(
        akan.coz_akis("Mitoz nasıl işler?", secenekler={"A": "bir", "B": "iki"})
    )

    assert gelen is not None
    assert gelen.adimlar == beklenen.adimlar
    assert gelen.cevap == beklenen.cevap
    assert gelen.guven == beklenen.guven
    assert gelen.cevap_turu == beklenen.cevap_turu
    assert gelen.incele == beklenen.incele
    assert gelen.uyarilar == beklenen.uyarilar


def test_akis_ham_metni_oldugu_gibi_iletir(depo, sahte_gomlemci):
    ham = _yanit(["adım"], "A")
    cozucu = _cozucu(
        depo, sahte_gomlemci, SahteMotor(ham, parca_boyu=4), onbellek_aktif=False
    )
    metin, _durumlar, cozum = _olaylari_topla(cozucu.coz_akis("Soru?"))
    assert metin == ham
    assert cozum is not None


def test_akis_olay_sirasi_ve_tek_bitti(depo, sahte_gomlemci):
    cozucu = _cozucu(
        depo, sahte_gomlemci, SahteMotor(_yanit(["a"], "A"), parca_boyu=3),
        onbellek_aktif=False,
    )
    adlar = [ad for ad, _ in cozucu.coz_akis("Soru?")]
    assert adlar[0] == "durum"
    assert adlar[-1] == "bitti"
    assert adlar.count("bitti") == 1, "bitti tam olarak bir kez gelmeli"
    assert "parca" in adlar


def test_akis_cozumu_depoya_kaydeder(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, SahteMotor(_yanit(["a"], "A")))
    _metin, _durumlar, cozum = _olaylari_topla(cozucu.coz_akis("Soru?"))
    assert cozum.id is not None
    geri, _satir = depo.cozum(cozum.id)
    assert geri.cevap == "A"


def test_akis_onbellekten_yanitlarsa_parca_uretmez(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, SahteMotor(_yanit(["a"], "B")))
    cozucu.coz("Soru?", secenekler={"A": "bir", "B": "iki"})

    metin, durumlar, cozum = _olaylari_topla(
        cozucu.coz_akis("Soru?", secenekler={"A": "bir", "B": "iki"})
    )
    assert cozum.uretim_yontemi == "onbellek"
    assert metin == "", "önbellek isabetinde model çalışmadığı için parça gelmemeli"
    assert any("önbellek" in d for d in durumlar)


def test_akis_motorsuz_calisir(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, None)
    _metin, _durumlar, cozum = _olaylari_topla(cozucu.coz_akis("Soru?"))
    assert cozum is not None
    assert cozum.incele, "model yokken çözüm her zaman incelemeye düşer"


def test_akis_motor_hatasinda_yerel_cozume_duser(depo, sahte_gomlemci):
    """Yanıtı tükenmiş sahte motor MotorHatasi atar; akış çökmemeli."""
    cozucu = _cozucu(depo, sahte_gomlemci, SahteMotor([]), onbellek_aktif=False)
    _metin, _durumlar, cozum = _olaylari_topla(cozucu.coz_akis("Soru?"))
    assert cozum is not None
    assert cozum.incele
    assert any("Model çalıştırılamadı" in u for u in cozum.uyarilar)


def test_akis_bos_soruyu_reddeder(depo, sahte_gomlemci):
    cozucu = _cozucu(depo, sahte_gomlemci, SahteMotor(_yanit(["a"], "A")))
    with pytest.raises(ValueError):
        list(cozucu.coz_akis("   "))


def test_akis_kor_degerlendirmede_onbellegi_atlar(depo, sahte_gomlemci):
    """haric_imzalar verildiğinde önbellek okunmamalı — sızıntı koruması."""
    from biyo_cozucu.metin import imza

    cozucu = _cozucu(depo, sahte_gomlemci, SahteMotor([_yanit(["ilk"], "A"), _yanit(["kör"], "B")]))
    cozucu.coz("Soru?")

    _metin, _durumlar, cozum = _olaylari_topla(
        cozucu.coz_akis("Soru?", kaydet=False, haric_imzalar={imza("baska soru")})
    )
    assert cozum.uretim_yontemi == "model", "kör koşuda önbellek kullanılmamalı"
