"""Karma motorun yönlendirme kuralları.

Sınanan tek şey: hangi sorunun hangi modele gittiği. Modellerin ne cevap
verdiği burada önemsiz — o, değerlendirme koşusunun işi.
"""

from __future__ import annotations

import pytest

from biyo_cozucu.motor import motor_yukle
from biyo_cozucu.motor.karma_motor import KarmaMotor
from biyo_cozucu.motor.temel import AkanMotor, GorselMotor, SahteGorselMotor, SahteMotor

MESAJ = [{"role": "user", "content": "Mitoz nedir?"}]


def _karma() -> tuple[KarmaMotor, SahteMotor, SahteGorselMotor]:
    metin = SahteMotor(["METIN"])
    gorsel = SahteGorselMotor(["GORSEL"])
    return KarmaMotor(metin=metin, gorsel=gorsel), metin, gorsel


def test_gorselsiz_soru_metin_modeline_gider():
    karma, metin, gorsel = _karma()
    assert karma.uret(MESAJ) == "METIN"
    assert len(metin.cagrilar) == 1
    assert not gorsel.cagrilar


def test_gorselli_soru_gorsel_modele_gider():
    karma, metin, gorsel = _karma()
    assert karma.gorselle_uret(MESAJ, b"PNG") == "GORSEL"
    assert gorsel.gorseller == [b"PNG"]
    assert not metin.cagrilar


def test_bos_gorselle_cagri_metin_modeline_duser():
    """Boş görüntü için görsel modeli yüklemek, metin modelini boşuna
    bellekten düşürürdü."""
    karma, metin, gorsel = _karma()
    assert karma.gorselle_uret(MESAJ, b"") == "METIN"
    assert len(metin.cagrilar) == 1
    assert not gorsel.gorseller


def test_protokollere_uyuyor():
    """Çözücü motoru `isinstance` ile yokluyor; uymazsa görüntü sessizce atılır."""
    karma, _, _ = _karma()
    assert isinstance(karma, GorselMotor)
    assert isinstance(karma, AkanMotor)


def test_akis_metin_yolundan_gecer():
    karma, _metin, gorsel = _karma()
    assert "".join(karma.uret_akis(MESAJ)) == "METIN"
    assert not gorsel.cagrilar


def test_ad_iki_modeli_de_gosteriyor():
    """Koşu raporunda hangi ikilinin ölçüldüğü ayırt edilebilmeli."""
    karma, _, _ = _karma()
    assert "sahte" in karma.ad and "sahte-gorsel" in karma.ad


@pytest.mark.parametrize("takma_ad", ["karma", "hibrit"])
def test_motor_yukle_karma_tanir(takma_ad, monkeypatch):
    """Alt motorlar tembel kurulmalı: `motor_yukle` gerçek modeli indirmemeli."""
    import biyo_cozucu.motor.karma_motor as km

    monkeypatch.setattr(
        km.KarmaMotor, "__init__",
        lambda self, metin=None, gorsel=None, **k: setattr(self, "ad", "sahte-karma"),
    )
    assert motor_yukle(takma_ad).ad == "sahte-karma"


def test_gorsel_motor_hata_verirse_metin_modeline_duser():
    """Görsel model yoksa/üretemezse soru HİÇ çözülmemeli değil, metinle çözülmeli.

    Hatayı yukarı bırakmak çözücüyü `_motorsuz_cozum`a düşürüyordu: ölçümde
    görselli 16 soruda 11/16 → 4/16.
    """
    from biyo_cozucu.motor.temel import MotorHatasi

    class _Kirik(SahteGorselMotor):
        def gorselle_uret(self, mesajlar, gorsel, *, sicaklik=0.2, azami_token=1536):
            raise MotorHatasi("mlx-vlm kurulu değil.")

    metin = SahteMotor(["METIN"])
    karma = KarmaMotor(metin=metin, gorsel=_Kirik(["hiç"]))
    assert karma.gorselle_uret(MESAJ, b"PNG") == "METIN"
    assert len(metin.cagrilar) == 1
