#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Raster girdi normalizasyonu ve taranmış PDF DPI regresyon testleri."""

import os
import tempfile
import unittest
from unittest import mock

import fitz
from PIL import Image, features

import soru_kes as sk


class RasterFormatTestleri(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory()

    def tearDown(self):
        sk._raster_lru_temizle()
        self.gecici.cleanup()

    def yol(self, ad):
        return os.path.join(self.gecici.name, ad)

    def test_rgba_png_saydamligi_beyaza_kompozit_edilir(self):
        yol = self.yol("saydam.png")
        img = Image.new("RGBA", (4, 3), (20, 40, 60, 0))
        img.putpixel((1, 1), (0, 0, 0, 255))
        img.save(yol)

        sayfalar, doc = sk.sayfalari_yukle(yol, 300)
        self.assertIsNone(doc)
        self.assertEqual(len(sayfalar), 1)
        yuklu = sayfalar[0]._img()
        self.assertEqual(yuklu.mode, "RGB")
        self.assertEqual(yuklu.getpixel((0, 0)), (255, 255, 255))
        self.assertEqual(yuklu.getpixel((1, 1)), (0, 0, 0))

    def test_palet_png_transparency_beyaza_kompozit_edilir(self):
        yol = self.yol("palet.png")
        img = Image.new("P", (2, 1))
        palet = [0, 0, 0, 0, 0, 0] + [0, 0, 0] * 254
        img.putpalette(palet)
        img.putdata([0, 1])
        img.save(yol, transparency=0)

        sayfa = sk.sayfalari_yukle(yol, 300)[0][0]
        self.assertEqual(list(sayfa._img().getdata()),
                         [(255, 255, 255), (0, 0, 0)])

    def test_exif_yonu_yukleme_ve_kirpma_boyutuna_uygulanir(self):
        yol = self.yol("yonlu.jpg")
        img = Image.new("RGB", (2, 3), "white")
        exif = Image.Exif()
        exif[274] = 6  # 90 derece saat yönü
        img.save(yol, quality=100, subsampling=0, exif=exif)

        sayfa = sk.sayfalari_yukle(yol, 300)[0][0]
        self.assertEqual((sayfa.genislik, sayfa.yukseklik), (3, 2))
        self.assertEqual(sayfa._img().size, (3, 2))

    def test_cok_kareli_tiff_her_kareyi_sayfa_yapar(self):
        yol = self.yol("kitap.tiff")
        kareler = [Image.new("RGB", (5, 4), renk)
                   for renk in ("red", "green", "blue")]
        kareler[0].save(yol, save_all=True, append_images=kareler[1:])

        sayfalar, doc = sk.sayfalari_yukle(yol, 300)
        self.assertIsNone(doc)
        self.assertEqual(len(sayfalar), 3)
        self.assertEqual([s._kare_no for s in sayfalar], [0, 1, 2])
        self.assertEqual([s._img().getpixel((0, 0)) for s in sayfalar],
                         [(255, 0, 0), (0, 128, 0), (0, 0, 255)])
        self.assertEqual(len({s.kimlik for s in sayfalar}), 3)

    def test_animated_gif_her_kareyi_sayfa_yapar(self):
        yol = self.yol("kitap.gif")
        kareler = [Image.new("RGB", (6, 4), renk)
                   for renk in ("white", "black")]
        kareler[0].save(yol, save_all=True, append_images=kareler[1:],
                        duration=100, loop=0)

        sayfalar, _ = sk.sayfalari_yukle(yol, 300)
        self.assertEqual(len(sayfalar), 2)
        self.assertEqual(sayfalar[0]._img().getpixel((0, 0)),
                         (255, 255, 255))
        self.assertEqual(sayfalar[1]._img().getpixel((0, 0)), (0, 0, 0))

    @unittest.skipUnless(features.check("webp_anim"),
                         "Pillow animated WebP desteği yok")
    def test_animated_webp_her_kareyi_sayfa_yapar(self):
        yol = self.yol("kitap.webp")
        kareler = [Image.new("RGB", (6, 4), renk)
                   for renk in ("red", "blue")]
        kareler[0].save(yol, "WEBP", save_all=True,
                        append_images=kareler[1:], duration=100, loop=0,
                        lossless=True)

        sayfalar, _ = sk.sayfalari_yukle(yol, 300)
        self.assertEqual(len(sayfalar), 2)
        self.assertEqual(sayfalar[0]._img().getpixel((0, 0)), (255, 0, 0))
        self.assertEqual(sayfalar[1]._img().getpixel((0, 0)), (0, 0, 255))

    def test_taranmis_pdf_layout_200_cikti_istenen_dpi(self):
        yol = self.yol("tarama.pdf")
        doc = fitz.open()
        page = doc.new_page(width=144, height=144)
        page.draw_rect(fitz.Rect(20, 20, 124, 124), color=(0, 0, 0),
                       width=1)
        doc.save(yol)
        doc.close()

        sayfa144, acik144 = sk.sayfalari_yukle(yol, 144)
        sayfa288, acik288 = sk.sayfalari_yukle(yol, 288)
        try:
            s144, s288 = sayfa144[0], sayfa288[0]
            self.assertTrue(s144.raster)
            # OCR/layout uzayı iki yüklemede de sabit 200 DPI.
            self.assertEqual((s144.genislik, s144.yukseklik), (400, 400))
            self.assertEqual((s288.genislik, s288.yukseklik), (400, 400))

            # 200 layout pikseli = 72 punto. Çıktı 144/288 DPI'da 144/288 px.
            kutu = (100, 100, 300, 300)
            self.assertIsNone(s144._img_cache)
            self.assertIsNone(s288._img_cache)
            kirp144 = s144.kirp(kutu)
            kirp288 = s288.kirp(kutu)
            self.assertEqual(kirp144.size, (144, 144))
            self.assertEqual(kirp288.size, (288, 288))
            # Kırpma tam 200-DPI sayfayı LRU'ya render etmeden doğrudan clip'tir.
            self.assertIsNone(s144._img_cache)
            self.assertIsNone(s288._img_cache)
            self.assertAlmostEqual(s144.kirpma_olcegi, 144 / 200)
            self.assertAlmostEqual(s288.kirpma_olcegi, 288 / 200)
        finally:
            sk.belge_kapat(acik144)
            sk.belge_kapat(acik288)

    def test_ocr_altyapisi_tamamen_cokerse_acik_hata_verilir(self):
        yol = self.yol("ocr-hatasi.png")
        Image.new("RGB", (320, 240), "white").save(yol)
        with mock.patch.object(sk, "vision_satirlar",
                               side_effect=RuntimeError("Vision kullanılamıyor")):
            with self.assertRaisesRegex(RuntimeError, "OCR başlatılamadı"):
                sk.belge_hazirla([yol])


if __name__ == "__main__":
    unittest.main()
