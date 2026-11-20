#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_form — üretici testleri: şablon↔PDF tutarlılığı (cv2 gerekmez)."""
import os
import tempfile
import unittest

import fitz
import numpy as np
from PIL import Image

import optik_form as of
import optik_sema as osm

DPI = 150
OLC = DPI / 72.0


def _render_gri(pdf_yolu, sayfa=0):
    doc = fitz.open(pdf_yolu)
    pix = doc[sayfa].get_pixmap(matrix=fitz.Matrix(OLC, OLC))
    img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
    doc.close()
    return np.asarray(img.convert("L"))


def _pencere(gri, x_pt, y_pt, yari=2):
    x, y = int(round(x_pt * OLC)), int(round(y_pt * OLC))
    return gri[max(0, y - yari):y + yari + 1, max(0, x - yari):x + yari + 1]


class FormUretTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dizin = tempfile.TemporaryDirectory()
        cls.yol = os.path.join(cls.dizin.name, "form.pdf")
        cls.sonuc = of.form_uret(on_ayar="lgs-sozel", yol=cls.yol)
        cls.sablon = cls.sonuc["sablon"]
        cls.gri = _render_gri(cls.yol)

    @classmethod
    def tearDownClass(cls):
        cls.dizin.cleanup()

    def test_ciktilar(self):
        self.assertTrue(os.path.isfile(self.yol))
        self.assertTrue(os.path.isfile(self.sonuc["sablon_yolu"]))
        yeniden = osm.sablon_oku(self.sonuc["sablon_yolu"])
        self.assertEqual(osm.sablon_dict(yeniden),
                         osm.sablon_dict(self.sablon))

    def test_sablon_gecerli(self):
        self.assertEqual(osm.dogrula(self.sablon), [])
        self.assertEqual(self.sablon.soru_sayisi(), 50)
        self.assertEqual(self.sablon.dersler(),
                         ["Türkçe", "T.C. İnkılap Tarihi",
                          "Din Kültürü", "İngilizce"])

    def test_isaretci_pdf_uyumu(self):
        """İşaretçi bordür hücresi PDF'te gerçekten siyah basılmış mı?"""
        for im in self.sablon.sayfalar[0].isaretciler:
            cx, cy = im.merkez
            hucre = im.boy / 6.0
            # sol-üst bordür hücresinin ortası her zaman siyah
            px = _pencere(self.gri, cx - im.boy / 2 + hucre / 2,
                          cy - im.boy / 2 + hucre / 2, yari=1)
            self.assertLess(int(px.mean()), 80,
                            f"işaretçi {im.id} bordürü siyah değil")

    def test_balon_pdf_uyumu(self):
        """Balon merkezi beyaz (boş), çemberin üstünde mürekkep var."""
        alan = self.sablon.alan_bul("turkce_s1")
        self.assertIsNotNone(alan)
        merkezler = osm.baloncuk_merkezleri(alan)
        _, _, x, y = merkezler[0]
        ic = _pencere(self.gri, x, y, yari=1)
        self.assertGreater(int(ic.mean()), 140, "balon içi beyaz değil")
        halka = _pencere(self.gri, x - alan.hucre.cap / 2, y, yari=1)
        self.assertLess(int(halka.min()), 140, "balon çemberi bulunamadı")

    def test_kose_kareleri_siyah(self):
        for kare in self.sablon.sayfalar[0].kose_kareleri:
            cx, cy = kare["merkez"]
            px = _pencere(self.gri, cx, cy, yari=1)
            self.assertLess(int(px.mean()), 80, "köşe karesi siyah değil")

    def test_qr_kaydi(self):
        qr = self.sablon.sayfalar[0].qr
        self.assertIsNotNone(qr)
        cozum = osm.qr_coz(qr["icerik"])
        self.assertEqual(cozum["sinav_id"], self.sonuc["sinav_id"])
        self.assertEqual(cozum["sayfa_no"], 1)

    def test_kimlik_alanlari(self):
        for ad in ("ad_soyad", "ogrenci_no", "kitapcik"):
            self.assertIsNotNone(self.sablon.alan_bul(ad), ad)
        self.assertEqual(self.sablon.alan_bul("ad_soyad").satir, 29)
        self.assertEqual(self.sablon.alan_bul("kitapcik").semboller,
                         ("A", "B"))


class CokSayfaTest(unittest.TestCase):
    def test_ayt_iki_sayfa(self):
        with tempfile.TemporaryDirectory() as dizin:
            yol = os.path.join(dizin, "ayt.pdf")
            sonuc = of.form_uret(on_ayar="ayt", yol=yol)
            self.assertEqual(sonuc["sayfa"], 2)
            sayfa2 = sonuc["sablon"].sayfalar[1]
            self.assertEqual([i.id for i in sayfa2.isaretciler],
                             [4, 5, 6, 7])
            self.assertEqual(osm.qr_coz(sayfa2.qr["icerik"])["sayfa_no"], 2)
            # sayfa 2'de kimlik alanları yok, yalnız cevap alanları
            tipler = {a.tip for a in sayfa2.alanlar}
            self.assertEqual(tipler, {"coktan_secmeli"})


class TanimTest(unittest.TestCase):
    def test_gecersiz_tanim(self):
        self.assertTrue(of.tanim_dogrula({"dersler": []}))
        self.assertTrue(of.tanim_dogrula(
            {"dersler": [{"ad": "X", "soru": 0, "secenek": 4}]}))
        self.assertTrue(of.tanim_dogrula(
            {"dersler": [{"ad": "X", "soru": 10, "secenek": 9}]}))
        self.assertTrue(of.tanim_dogrula(
            {"dersler": [{"ad": "X", "soru": 10, "secenek": 4}],
             "kitapcik": 9}))

    def test_bilinmeyen_on_ayar(self):
        with self.assertRaises(ValueError):
            of.tanim_hazirla(on_ayar="yok-boyle")

    def test_parametrik(self):
        with tempfile.TemporaryDirectory() as dizin:
            yol = os.path.join(dizin, "ozel.pdf")
            sonuc = of.form_uret(
                {"ad": "6A Fen Yazılısı", "kitapcik": 1, "tc": True,
                 "dersler": [{"ad": "Fen Bilimleri", "soru": 25,
                              "secenek": 4}]}, yol=yol)
            s = sonuc["sablon"]
            self.assertEqual(osm.dogrula(s), [])
            self.assertEqual(s.kitapcik_turleri, ("A",))
            self.assertIsNotNone(s.alan_bul("tc_kimlik"))
            self.assertEqual(s.soru_sayisi(), 25)

    def test_tr_upper(self):
        self.assertEqual(of._tr_upper("İngilizce"), "İNGİLİZCE")
        self.assertEqual(of._tr_upper("ınkılap"), "INKILAP")
        self.assertEqual(of._tr_upper("Din Kültürü"), "DİN KÜLTÜRÜ")


if __name__ == "__main__":
    unittest.main()
