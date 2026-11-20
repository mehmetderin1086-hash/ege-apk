#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Windows OCR yedek yolu (easyocr_satirlar) — koordinat dönüşümü sabitlemesi.

vision_satirlar yalnız macOS'ta çalışır; Windows'ta RasterSayfa.satirlar()
Vision'ı hiç denemeden ocr_ensemble.motor_satirlar(img, "easyocr") çıktısını
aynı OCRSatiri sözleşmesine (vision_satirlar'ın metali=True dönüşüyle
birebir) çevirir. motor_satirlar zaten PİKSEL uzayında [(metin, kutu_px),
...] döner; bu testler o piksel kutunun sessizce yeniden ölçeklenmediğini
(normalize sanılmadığını), motorun el sıkışmayla (_probe_al) fiilen aktif
olduğu doğrulanmadan sonuca güvenilmediğini ve "işçi yok/motor yüklenemedi"
durumunda zarif düşüşün (RuntimeError → RasterSayfa.satirlar()'ın ocr_hata
dalı) korunduğunu sabitler."""

import unittest
from unittest import mock

from PIL import Image

import ocr_ensemble as oe
import soru_kes as sk


class EasyocrSatirlariTesti(unittest.TestCase):
    def setUp(self):
        self.img = Image.new("RGB", (800, 1000), "white")
        # ISCI_PY/ISCI_BETIK "kurulu" testlerinde gerçek dosya olsun diye
        # ocr_ensemble.py'nin kendisine işaret eder (var olduğu garanti).
        self._kurulu = (mock.patch.object(oe, "ISCI_PY", oe.__file__),
                        mock.patch.object(oe, "ISCI_BETIK", oe.__file__))
        # El sıkışma: işçi ayakta ve easyocr motoru yüklü sanılsın.
        self._aktif_probe = mock.patch.object(
            oe, "_probe_al",
            return_value={"motorlar": {"easyocr": True}, "cihaz": "cpu"})

    def test_piksel_kutu_yeniden_olceklenmez(self):
        """motor_satirlar'ın pikselde döndürdüğü kutu, _ocr_satiri_dictten'in
        normalize-sanma ihtimaline karşı DEĞİŞMEDEN OCRSatiri'ye geçmeli."""
        ham = [("12. Hücre nedir?", (50.0, 100.0, 300.0, 130.0)),
               ("A) Zar", (50.0, 140.0, 200.0, 165.0))]
        with self._kurulu[0], self._kurulu[1], self._aktif_probe, \
             mock.patch.object(oe, "motor_satirlar", return_value=ham):
            satirlar = sk.easyocr_satirlar(self.img, duzelt=False)
        self.assertEqual(len(satirlar), 2)
        self.assertEqual(satirlar[0].metin, "12. Hücre nedir?")
        self.assertEqual(satirlar[0].kutu, (50.0, 100.0, 300.0, 130.0))
        self.assertEqual(satirlar[1].kutu, (50.0, 140.0, 200.0, 165.0))
        self.assertEqual(satirlar[0].kaynak, "easyocr")
        self.assertAlmostEqual(satirlar[0].guven,
                               oe.MOTOR_AGIRLIK["easyocr"])

    def test_numara_onek_kutusu_hesaplanir(self):
        """Vision yolunda olduğu gibi çapa (soru no) önek kutusu türetilir —
        ML birleştirme/zincir tespiti bu alana bağımlı, kaybolmamalı."""
        ham = [("12. Hücre nedir?", (50.0, 100.0, 300.0, 130.0))]
        with self._kurulu[0], self._kurulu[1], self._aktif_probe, \
             mock.patch.object(oe, "motor_satirlar", return_value=ham):
            satirlar = sk.easyocr_satirlar(self.img, duzelt=False)
        self.assertIsNotNone(satirlar[0].numara_on_eki_kutu)

    def test_bos_metin_elenir(self):
        ham = [("   ", (0.0, 0.0, 10.0, 10.0)),
               ("gerçek satır", (0.0, 20.0, 100.0, 40.0))]
        with self._kurulu[0], self._kurulu[1], self._aktif_probe, \
             mock.patch.object(oe, "motor_satirlar", return_value=ham):
            satirlar = sk.easyocr_satirlar(self.img, duzelt=False)
        self.assertEqual([s.metin for s in satirlar], ["gerçek satır"])

    def test_isci_kurulu_degilse_runtime_error(self):
        with mock.patch.object(oe, "ISCI_PY", "/yok/olan/python"), \
             mock.patch.object(oe, "ISCI_BETIK", "/yok/olan/ocr_isci.py"):
            with self.assertRaisesRegex(RuntimeError, "kurulu değil"):
                sk.easyocr_satirlar(self.img)

    def test_motor_yuklenemediyse_runtime_error(self):
        """İşçi dosyaları var ama el sıkışma easyocr'ı 'yok' bildiriyorsa
        (paket eksik/yüklenemedi) sessiz boş sonuç yerine açık hata verilir —
        aksi hâlde gerçek bir arıza 'sayfada metin yok' ile karışıp cache'e
        yazılırdı."""
        with self._kurulu[0], self._kurulu[1], \
             mock.patch.object(oe, "_probe_al",
                               return_value={"motorlar": {"easyocr": False}}):
            with self.assertRaisesRegex(RuntimeError, "yüklenemedi"):
                sk.easyocr_satirlar(self.img)


if __name__ == "__main__":
    unittest.main()
