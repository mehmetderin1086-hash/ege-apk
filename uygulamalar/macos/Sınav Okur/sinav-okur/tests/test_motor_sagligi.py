"""OCR motor sağlığı oturumlar arası hatırlanmalı.

Ölçüldü: paddle sayfa OCR süresinin %76'sını hiç sonuç üretmeden yakıyordu
(343 sn / 454 sn) ve süreç ömrüyle sınırlı devre kesici yüzünden her
yeniden başlatmada aynı bedel yeniden ödeniyordu.
"""

from __future__ import annotations

from sinav_okur.ocr import (
    SAGLIK_ASGARI_ISTEK,
    _saglik_kaydet,
    devre_kesiciyi_sifirla,
    motor_sagligi_oku,
    motor_saglikli_mi,
)


def test_surekli_basarisiz_motor_elenir():
    for _ in range(SAGLIK_ASGARI_ISTEK):
        _saglik_kaydet("paddle", False)

    assert motor_saglikli_mi("paddle") is False


def test_basarili_motor_saglikli_kalir():
    for _ in range(SAGLIK_ASGARI_ISTEK + 2):
        _saglik_kaydet("vision", True)

    assert motor_saglikli_mi("vision") is True


def test_az_ornekte_motor_elenmez():
    """Tek bir hata motoru elemez; yeterli kanıt birikmeli."""
    _saglik_kaydet("surya", False)

    assert motor_saglikli_mi("surya") is True


def test_yarim_yariya_hata_elemez():
    """Eşik 'çoğunlukla başarısız'; ara sıra hata veren motor kalır."""
    _saglik_kaydet("easyocr", False)
    _saglik_kaydet("easyocr", True)
    _saglik_kaydet("easyocr", True)
    _saglik_kaydet("easyocr", True)

    assert motor_saglikli_mi("easyocr") is True


def test_sifirlama_elenen_motoru_geri_getirir():
    for _ in range(SAGLIK_ASGARI_ISTEK):
        _saglik_kaydet("paddle", False)
    assert motor_saglikli_mi("paddle") is False

    devre_kesiciyi_sifirla(saglik_da=True)

    assert motor_sagligi_oku() == {}
    assert motor_saglikli_mi("paddle") is True


def test_bilinmeyen_motor_saglikli_sayilir():
    assert motor_saglikli_mi("hic-calismamis-motor") is True
