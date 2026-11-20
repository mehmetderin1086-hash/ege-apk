import os
import tempfile
import unittest

import soru_kes_web as web


class WebYuklemeGuvenligiTesti(unittest.TestCase):
    def setUp(self):
        self._onceki_gecici = web.DURUM.get("gecici_klasor")
        self._gecici = tempfile.TemporaryDirectory(prefix="soru_kesici_web_test_")
        web.DURUM["gecici_klasor"] = self._gecici.name

    def tearDown(self):
        web.DURUM["gecici_klasor"] = self._onceki_gecici
        self._gecici.cleanup()

    def test_desteklenmeyen_uzantilar_reddedilir(self):
        for ad in ("zararli.exe", "uzantisiz"):
            with self.subTest(ad=ad):
                with self.assertRaises(ValueError):
                    web.yukleme_kaydet(ad, b"icerik")

    def test_docx_yukleme_katmaninda_kabul_edilir(self):
        yol = web.yukleme_kaydet("sinav.docx", b"docx-icerigi")
        self.assertEqual("sinav.docx", os.path.basename(yol))
        with open(yol, "rb") as dosya:
            self.assertEqual(b"docx-icerigi", dosya.read())

    def test_dizin_bilesenleri_atilir_ve_ayni_ad_ezilmez(self):
        ilk = web.yukleme_kaydet("../../kitap.pdf", b"birinci")
        ikinci = web.yukleme_kaydet("../../kitap.pdf", b"ikinci")

        self.assertEqual(self._gecici.name, os.path.dirname(ilk))
        self.assertEqual(self._gecici.name, os.path.dirname(ikinci))
        self.assertEqual("kitap.pdf", os.path.basename(ilk))
        self.assertEqual("kitap_1.pdf", os.path.basename(ikinci))
        self.assertNotEqual(ilk, ikinci)
        with open(ilk, "rb") as dosya:
            self.assertEqual(b"birinci", dosya.read())
        with open(ikinci, "rb") as dosya:
            self.assertEqual(b"ikinci", dosya.read())


class WebSecimSemantigiTesti(unittest.TestCase):
    def test_null_tumu_bos_liste_hicbirini_secer(self):
        self.assertIsNone(web._kimlikten_secim(None))
        self.assertEqual(set(), web._kimlikten_secim([]))


if __name__ == "__main__":
    unittest.main()
