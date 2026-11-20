#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OCR hakemliği saf-mantık testleri (Faz B) — motor GEREKTİRMEZ.

satir_hizala, kelime_oyla (marj muhafazakârlığı + çapa istisnası),
tetikleyici seçimi, mod/imza, hizli-mod no-op.
"""

import dataclasses
import unittest

import ocr_ensemble as oe


@dataclasses.dataclass(frozen=True)
class SahteSatir:
    metin: str
    kutu: tuple
    guven: float = 1.0
    adaylar: tuple = ()
    kaynak: str = "vision"


class HizalaTesti(unittest.TestCase):
    def test_dikey_ortusme_esigi(self):
        ana = (0, 100, 200, 130)
        adaylar = [("A", (0, 100, 200, 130), 0.9),    # tam örtüşme
                   ("B", (0, 400, 200, 430), 0.9)]     # uzak
        es = oe.satir_hizala(ana, adaylar)
        self.assertEqual([m for m, _ in es], ["A"])

    def test_yatay_kesismeyen_elenir(self):
        ana = (0, 100, 100, 130)
        adaylar = [("X", (300, 100, 400, 130), 0.9)]
        self.assertEqual(oe.satir_hizala(ana, adaylar), [])


class KelimeOylaTesti(unittest.TestCase):
    def setUp(self):
        self.ag = dict(oe.MOTOR_AGIRLIK)

    def test_marj_altinda_vision_korunur(self):
        # tek zayıf hakem Vision'ı MARJ kadar aşamaz → değişmez
        kazanan, _, degisti = oe.kelime_oyla(
            "hücre", 0.9, [("tesseract", "hucre", 0.6)], self.ag)
        self.assertEqual(kazanan, "hücre")
        self.assertFalse(degisti)

    def test_guclu_cogunluk_vision_ezer(self):
        kazanan, _, degisti = oe.kelime_oyla(
            "hucre", 0.55,
            [("rapidocr", "hücre", 0.95), ("tesseract", "hücre", 0.93),
             ("easyocr", "hücre", 0.9)], self.ag)
        self.assertEqual(kazanan, "hücre")
        self.assertTrue(degisti)

    def test_capa_iki_motor_ayni_numarayi_kazandirir(self):
        kazanan, _, degisti = oe.kelime_oyla(
            "l2.", 0.7, [("rapidocr", "12.", 0.9), ("tesseract", "12.", 0.88)],
            self.ag, capa=True)
        self.assertEqual(kazanan, "12.")
        self.assertTrue(degisti)

    def test_sozluk_bonusu(self):
        # sözlükteki kelime eşit güvende öne geçer
        kazanan, _, degisti = oe.kelime_oyla(
            "boluume", 0.5, [("rapidocr", "bölünme", 0.7)], self.ag,
            sozluk={"bölünme"})
        self.assertEqual(kazanan, "bölünme")
        self.assertTrue(degisti)


class TetikleyiciTesti(unittest.TestCase):
    def test_dusuk_guven_tetikler(self):
        s = SahteSatir("fotosentez", (0, 0, 100, 20), guven=0.6)
        self.assertTrue(oe._tetikleyici(s, "dengeli", set()))

    def test_yuksek_guven_tetiklemez(self):
        s = SahteSatir("fotosentez", (0, 0, 100, 20), guven=0.97)
        self.assertFalse(oe._tetikleyici(s, "dengeli", set()))

    def test_capa_dusuk_guven_tetikler(self):
        s = SahteSatir("12.", (0, 0, 40, 20), guven=0.85)
        self.assertTrue(oe._tetikleyici(s, "dengeli", set()))

    def test_supheli_karakter_tetikler(self):
        s = SahteSatir("hücre qxw", (0, 0, 100, 20), guven=0.99)
        self.assertTrue(oe._tetikleyici(s, "dengeli", set()))


class ModTesti(unittest.TestCase):
    def tearDown(self):
        oe.MOD_ZORLA = None

    def test_mod_zorla_onceligi(self):
        oe.MOD_ZORLA = "tam"
        self.assertEqual(oe.mod_al(), "tam")

    def test_hizli_mod_hakemlik_no_op(self):
        oe.MOD_ZORLA = "hizli"
        meta = [SahteSatir("a", (0, 0, 10, 10), 0.5)]
        yeni, kayit = oe.hakemlik(None, meta, kimlik="x")
        self.assertIs(yeni, meta)
        self.assertEqual(kayit["mod"], "hizli")

    def test_hizli_mod_imza_bos(self):
        oe.MOD_ZORLA = "hizli"
        self.assertEqual(oe.motor_imzasi(), "")


class BelgeSozluguTesti(unittest.TestCase):
    def test_yuksek_guven_token_toplar(self):
        meta = [SahteSatir("Fotosentez olayı", (0, 0, 200, 20), 0.97),
                SahteSatir("düşük satır", (0, 30, 200, 50), 0.5)]
        soz = oe._belge_sozlugu(meta)
        self.assertIn("fotosentez", soz)
        self.assertNotIn("düşük", soz)


if __name__ == "__main__":
    unittest.main()
