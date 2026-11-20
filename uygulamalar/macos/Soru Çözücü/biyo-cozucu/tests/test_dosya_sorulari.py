"""Çöz ekranındaki resim/PDF/metin yükleme hazırlığının çevrimdışı testleri."""

from __future__ import annotations

import io

import pytest

pytest.importorskip("PIL")

from PIL import Image

from biyo_cozucu.webapp.dosya_sorulari import (
    SoruDosyasiHatasi,
    dosya_sorularini_hazirla,
    gorsel_imzasi_gecerli_mi,
)


def _png() -> bytes:
    tampon = io.BytesIO()
    Image.new("RGB", (160, 100), "white").save(tampon, format="PNG")
    return tampon.getvalue()


def _pdf() -> bytes:
    tampon = io.BytesIO()
    Image.new("RGB", (320, 240), "white").save(tampon, format="PDF")
    return tampon.getvalue()


def test_resim_normalize_edilip_cozulebilir_soruya_donusur(tmp_path):
    sorular = dosya_sorularini_hazirla(
        tmp_path, [("soru.png", _png())], soru_notu="Grafiği de yorumla."
    )
    assert len(sorular) == 1
    assert sorular[0].baslik == "soru.png"
    assert "Grafiği de yorumla" in sorular[0].soru
    assert gorsel_imzasi_gecerli_mi(tmp_path, sorular[0].gorsel)


def test_pdf_her_sayfayi_gorsel_soruya_donusturur(tmp_path):
    sorular = dosya_sorularini_hazirla(tmp_path, [("deneme.pdf", _pdf())])
    assert len(sorular) == 1
    assert sorular[0].baslik == "deneme.pdf · Sayfa 1"
    assert sorular[0].kaynak_turu == "pdf"
    assert gorsel_imzasi_gecerli_mi(tmp_path, sorular[0].gorsel)


def test_metin_dosyasi_numarali_sorulari_ayirir(tmp_path):
    metin = (
        "1. Mitozun canlılar için önemi nedir?\n"
        "A) Büyüme ve onarım\nB) Gamet oluşumu\n"
        "2. Ribozomun temel görevi hangisidir?\n"
        "A) Protein sentezi\nB) ATP sentezi\n"
    ).encode()
    sorular = dosya_sorularini_hazirla(tmp_path, [("sorular.txt", metin)])
    assert len(sorular) == 2
    assert "Mitozun" in sorular[0].soru
    assert "A) Büyüme" in sorular[0].secenekler
    assert "Ribozomun" in sorular[1].soru


def test_desteklenmeyen_dosya_anlamli_hata_verir(tmp_path):
    with pytest.raises(SoruDosyasiHatasi, match="desteklenmeyen"):
        dosya_sorularini_hazirla(tmp_path, [("soru.exe", b"x")])


def test_yol_bilesenleri_dosya_adindan_atilir(tmp_path):
    sorular = dosya_sorularini_hazirla(tmp_path, [("../../soru.png", _png())])
    assert sorular[0].baslik == "soru.png"
