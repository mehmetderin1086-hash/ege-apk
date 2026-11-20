#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cevap bandı + çözüm iliştirme birim testleri (Faz A).

cevap_bandi_ekle: boyut/beyaz-bant doğrulaması; cozumleri_ilistir:
eşleşen/eşleşmeyen/çakışan senaryolar; yazi_tipi: font zinciri.
"""

import unittest

from PIL import Image

import soru_kes as sk
import yazi_tipi


def _img(w=300, h=200, renk="white"):
    return Image.new("RGB", (w, h), renk)


def _kayit(soru_no, rol="soru", kaynak="a.pdf", test_sira=None):
    return {"soru_no": soru_no, "sayfa_rolu": rol, "kaynak": kaynak,
            "test_sira": test_sira, "cevap": None}


class CevapBandiTesti(unittest.TestCase):
    def test_bant_yukseklik_ekler(self):
        img = _img(300, 200)
        yeni = sk.cevap_bandi_ekle(img, "B")
        self.assertEqual(yeni.width, 300)
        bant = yeni.height - 200
        self.assertGreaterEqual(bant, 26)
        self.assertLessEqual(bant, 64)

    def test_bant_genislige_oranli_ve_sinirli(self):
        kucuk = sk.cevap_bandi_ekle(_img(100, 50), "A")
        buyuk = sk.cevap_bandi_ekle(_img(4000, 50), "A")
        self.assertEqual(kucuk.height - 50, 26)    # alt sınır
        self.assertEqual(buyuk.height - 50, 64)    # üst sınır

    def test_bant_icerik_cizer(self):
        # bant bölgesinde salt-beyaz olmayan pikseller olmalı (metin+çizgi)
        yeni = sk.cevap_bandi_ekle(_img(400, 100), "E")
        bant = yeni.crop((0, 100, 400, yeni.height))
        renkler = bant.getcolors(maxcolors=100000)
        self.assertGreater(len(renkler), 1)

    def test_ust_bolge_degismez(self):
        img = _img(200, 80, renk=(200, 10, 10))
        yeni = sk.cevap_bandi_ekle(img, "C")
        self.assertEqual(yeni.getpixel((100, 40)), (200, 10, 10))


class YaziTipiTesti(unittest.TestCase):
    def test_pil_font_doner(self):
        font = yazi_tipi.pil_font(14)
        self.assertIsNotNone(font)

    def test_sinav_pdf_ayni_zinciri_kullanir(self):
        import sinav_pdf
        self.assertIs(sinav_pdf._FONT_ADAYLARI, yazi_tipi.TTF_ADAYLARI)
        self.assertEqual(sinav_pdf._font_bul(), yazi_tipi.ttf_yolu())


class CozumIlistirTesti(unittest.TestCase):
    def test_eslesen_cozum_ilisir_ve_dusulur(self):
        kirpmalar = [_img(300, 200), _img(280, 150)]
        sorular = [_kayit(5), _kayit(5, rol="çözüm")]
        k2, s2, uyar = sk.cozumleri_ilistir(kirpmalar, sorular)
        self.assertEqual(len(k2), 1)
        self.assertEqual(len(s2), 1)
        self.assertTrue(s2[0].get("cozum_ilistirildi"))
        self.assertGreater(k2[0].height, 200)      # soru + ayraç + çözüm
        self.assertEqual(uyar, [])

    def test_eslesmeyen_cozum_kalir(self):
        kirpmalar = [_img(), _img()]
        sorular = [_kayit(1), _kayit(9, rol="çözüm")]
        k2, s2, uyar = sk.cozumleri_ilistir(kirpmalar, sorular)
        self.assertEqual(len(s2), 2)
        self.assertEqual(len(uyar), 1)

    def test_cakisan_numara_ilistirilmez(self):
        # aynı soru_no iki soruda → belirsiz, iliştirme yapılmaz
        kirpmalar = [_img(), _img(), _img()]
        sorular = [_kayit(3, test_sira=1), _kayit(3, test_sira=2),
                   _kayit(3, rol="çözüm")]
        k2, s2, uyar = sk.cozumleri_ilistir(kirpmalar, sorular)
        self.assertEqual(len(s2), 3)
        self.assertEqual(len(uyar), 1)
        self.assertFalse(any(so.get("cozum_ilistirildi") for so in s2))

    def test_test_sira_esiyle_dogru_hedef(self):
        # çözümün test_sira'sı soruyla eşleşiyorsa çakışma yoktur
        kirpmalar = [_img(), _img(), _img()]
        sorular = [_kayit(3, test_sira=1), _kayit(3, test_sira=2),
                   _kayit(3, rol="çözüm", test_sira=2)]
        k2, s2, uyar = sk.cozumleri_ilistir(kirpmalar, sorular)
        self.assertEqual(len(s2), 2)
        ilistirilen = [so for so in s2 if so.get("cozum_ilistirildi")]
        self.assertEqual(len(ilistirilen), 1)
        self.assertEqual(ilistirilen[0]["test_sira"], 2)


class KirpmaSetiParametreTesti(unittest.TestCase):
    def test_yeni_parametreler_varsayilanli(self):
        import inspect
        imza = inspect.signature(sk.kirpma_seti)
        self.assertIs(imza.parameters["cevap_bandi"].default, False)
        self.assertIsNone(imza.parameters["cevap_duzeltmeler"].default)


if __name__ == "__main__":
    unittest.main()
