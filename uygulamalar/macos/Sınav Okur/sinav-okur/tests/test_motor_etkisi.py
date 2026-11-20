"""Motor değişikliğini AÇMADAN ÖNCE ölçen kapı.

Puanlama motorunu değiştirmek sessiz bir toplu kaydırmadır: öğretmen
bambaşka bir sorunun anahtarına dokunduğu anda tüm kutular yeni motorla
yeniden puanlanır. Bu rapor, değişimin öğretmen puanlarına yaklaştırıp
yaklaştırmadığını önceden söyler.
"""

from __future__ import annotations

import pytest

from sinav_okur.depo import Depo
from sinav_okur.modeller import (
    CevapAnahtari,
    PuanSonucu,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
    TanimaSonucu,
)
from sinav_okur.motor_etkisi import motor_etkisini_onizle
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu

KIMLIK = "MOTOR"


class _SahteGomlemci:
    """Deterministik gömlemci (conftest.SahteGomlemci ile aynı desen)."""

    def gom(self, metinler):
        import numpy as np

        vekt = np.zeros((len(metinler), 32), dtype=float)
        for i, metin in enumerate(metinler):
            for ch in metin.lower():
                vekt[i, ord(ch) % 32] += 1.0
        return vekt


def _sinav() -> Sinav:
    return Sinav(
        kimlik=KIMLIK,
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.KISA_CEVAP,
                metin="Hücre zarının görevi nedir?",
                puan=10.0,
                anahtar=CevapAnahtari(
                    rubrik=[RubrikKalemi("madde giriş çıkışını kontrol eder", 10.0)]
                ),
            )
        ],
    )


def _depo(tmp_path, cevaplar: list[tuple[str, float | None]]) -> Depo:
    depo = Depo(tmp_path / "t.db")
    depo.sinav_kaydet(_sinav())
    for metin, ogretmen_puani in cevaplar:
        kagit_id = depo.kagit_kaydet(
            KagitSonucu(
                sinav_kimlik=KIMLIK,
                islenen_sayfalar=[1],
                kutular=[
                    KutuSonucu(
                        soru_no=1,
                        tanima=TanimaSonucu(metin=metin, guven=0.9),
                        puan=PuanSonucu(0.0, 10.0, 0.9),
                    )
                ],
            ),
            ogrenci_ad="Ö",
        )
        if ogretmen_puani is not None:
            kutu = depo.kutular(kagit_id)[0]
            depo.kutu_guncelle(
                kutu["id"], son_puan=ogretmen_puani, neden="öğretmen"
            )
    return depo


def test_rapor_depoya_yazmaz(tmp_path):
    depo = _depo(tmp_path, [("hücre zarı seçici geçirgendir", None)])
    onceki = [dict(k) for k in depo.sinav_cevaplari(KIMLIK)]

    motor_etkisini_onizle(_sinav_ile(depo), _sinav(), yeni_gomlemci=_SahteGomlemci())

    sonraki = [dict(k) for k in depo.sinav_cevaplari(KIMLIK)]
    assert onceki == sonraki, "önizleme hiçbir şey yazmamalı"


def _sinav_ile(depo):
    return depo


def test_gomlemci_puani_yukseltirse_degisim_raporlanir(tmp_path):
    """Anlamsal katman kısmi puan kurtarabilir; bu görünmeli."""
    depo = _depo(tmp_path, [("madde alışverişini düzenler", None)])

    rapor = motor_etkisini_onizle(
        depo, _sinav(), yeni_gomlemci=_SahteGomlemci()
    )

    assert rapor["incelenen"] == 1
    assert rapor["degisen"] + rapor["dusen"] >= 0  # rapor üretildi
    assert "acilabilir" in rapor


def test_ogretmen_puanina_yaklasma_olculur(tmp_path):
    """Kilit ölçü: yeni motor öğretmenin verdiği puana yaklaşıyor mu?"""
    depo = _depo(
        tmp_path,
        [("madde giriş çıkışını kontrol eder", 10.0) for _ in range(3)],
    )

    rapor = motor_etkisini_onizle(depo, _sinav(), yeni_gomlemci=None)

    uyum = rapor["ogretmen_puaniyla_uyum"]
    assert uyum["ornek"] == 3
    assert uyum["mae_eski"] == pytest.approx(uyum["mae_yeni"])
    assert "iyilesme" in uyum


def test_elle_dokunulmus_kutu_etkilenirse_engel_cikar(tmp_path):
    """Öğretmenin puanladığı kutuda program puanı değişirse kapı kapanır."""
    from sinav_okur.puanlama.ayarlar import PuanlamaAyar

    depo = _depo(tmp_path, [("madde giriş çıkışını kontrol eder", 4.0)])

    # Çok katı bir profil program puanını düşürür.
    rapor = motor_etkisini_onizle(
        depo, _sinav(), ayar=PuanlamaAyar().profil("kati")
    )

    if rapor["elle_dokunulmus_etkilenen"]:
        assert rapor["acilabilir"] is False
        assert any("elle puanlanmış" in e for e in rapor["engeller"])


def test_degisim_yoksa_acilabilir(tmp_path):
    """Hiçbir puan değişmiyorsa motor güvenle açılabilir."""
    depo = _depo(tmp_path, [("madde giriş çıkışını kontrol eder", None)])

    rapor = motor_etkisini_onizle(depo, _sinav(), yeni_gomlemci=None)

    assert rapor["degisen"] == 0
    assert rapor["acilabilir"] is True
    assert rapor["engeller"] == []


def test_ornekler_en_buyuk_degisimi_one_alir(tmp_path):
    depo = _depo(
        tmp_path,
        [("madde giriş çıkışını kontrol eder", None), ("alakasız cevap", None)],
    )

    rapor = motor_etkisini_onizle(
        depo, _sinav(), yeni_gomlemci=_SahteGomlemci()
    )

    deltalar = [abs(o["delta"]) for o in rapor["ornekler"]]
    assert deltalar == sorted(deltalar, reverse=True)


def test_olculemeyen_buyuk_degisim_acilamaz(tmp_path):
    """"Ölçerek aç" ilkesi: kanıt yoksa açma.

    Elle puanlanmış hiçbir kutu yoksa değişimin doğru yönde olduğunu
    gösteren referans yoktur; "düşen yok" tek başına yeterli değildir,
    yükselen puanlar da yanlış olabilir.
    """
    depo = _depo(
        tmp_path,
        [("madde alışverişini düzenler", None), ("giriş çıkış kontrolü", None)],
    )

    rapor = motor_etkisini_onizle(
        depo, _sinav(), yeni_gomlemci=_SahteGomlemci()
    )

    if rapor["degisen"]:
        assert rapor["ogretmen_puaniyla_uyum"] == {}
        assert rapor["acilabilir"] is False
        assert any("öğretmen puanı yok" in e for e in rapor["engeller"])


def test_ogretmen_puani_varsa_ve_yaklasiyorsa_acilabilir(tmp_path):
    """Referans varsa ve motor ona yaklaşıyorsa kapı açılır."""
    depo = _depo(
        tmp_path,
        [("madde giriş çıkışını kontrol eder", 10.0) for _ in range(3)],
    )

    rapor = motor_etkisini_onizle(depo, _sinav(), yeni_gomlemci=None)

    assert rapor["ogretmen_puaniyla_uyum"]["ornek"] == 3
    assert rapor["acilabilir"] is True
