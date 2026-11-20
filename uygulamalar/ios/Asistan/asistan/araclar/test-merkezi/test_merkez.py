import unittest
from unittest.mock import patch
import merkez

class RaporTestleri(unittest.TestCase):
    def test_bos_test_basari_degil(self):
        self.assertEqual(merkez.katman_durumu([0], [{}], True), 'Doğrulanamadı')
        self.assertEqual(merkez.katman_durumu([0,0], [{'passedTests':0},{'passedTests':9}], True), 'Doğrulanamadı')
    def test_atlananlar_gecenlerden_ayri(self):
        self.assertEqual(merkez.katman_durumu([0], [{'passedTests':8,'skippedTests':2}], True), 'Kısmen geçti')
    def test_alt_hata_cikis_kodundan_bagimsiz(self):
        self.assertEqual(merkez.katman_durumu([0], [{'passedTests':8,'failedTests':1}], True), 'Başarısız')
        self.assertEqual(merkez.katman_durumu([65], [{'passedTests':8}], True), 'Başarısız')
    def test_xcresult_sayilarini_ayri_okur(self):
        with patch('merkez.subprocess.check_output', return_value=b'{"passedTests":4,"failedTests":0,"skippedTests":3,"totalTestCount":7}'):
            sonuc=merkez.test_sayilari('Test session results:\n\t/tmp/sonuc.xcresult\n')
            self.assertEqual(sonuc['passedTests'],4)
            self.assertEqual(sonuc['skippedTests'],3)
    def test_python_sayisi(self):
        self.assertEqual(merkez.test_sayilari('Ran 98 tests in 4.0s\n\nOK\n')['passedTests'],98)
    def test_her_katman_komutu_var(self):
        for ad in merkez.ASAMALAR:
            self.assertTrue(merkez.komutlar(ad))
if __name__=='__main__': unittest.main()
