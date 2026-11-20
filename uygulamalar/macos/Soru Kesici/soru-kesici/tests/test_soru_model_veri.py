#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sözde-etiket veri hattı birim testleri (Faz C2) — belge işleme gerektirmez.

YOLO normalizasyonu (sınır kırpma), saflık kuralı (kaçan-soru dışlama),
sınıf eşlemesi, yayınevi grubu.
"""

import unittest

import soru_model_veri as smv


class SahteAday:
    def __init__(self, kutu, durum="otomatik", guven=0.9, numara_kutu=None,
                 devam=False, rol="soru"):
        self.kutu = kutu
        self.inceleme_durumu = durum
        self.guven = guven
        self.kalibre_guven = guven
        self.numara_kutu = numara_kutu
        self.devam_aday = devam
        self.sayfa_rolu = rol


class SahteAnaliz:
    def __init__(self, adaylar, risk=(), pipeline=(), duzen=0.9,
                 rol="soru"):
        self.adaylar = tuple(adaylar)
        self.risk_nedenleri = tuple(risk)
        self.pipeline_hatalari = tuple(pipeline)
        self.duzen_guveni = duzen
        self.sayfa_rolu = rol


class SahteSayfa:
    genislik = 1000.0
    yukseklik = 1400.0


class YoloSatiriTesti(unittest.TestCase):
    def test_normal_kutu(self):
        s = smv._yolo_satiri(1, (0, 0, 500, 700), 1000, 1400)
        self.assertEqual(s, "1 0.250000 0.250000 0.500000 0.500000")

    def test_sinir_disi_kirpilir(self):
        # x1=1200 > G=1000 → kırpılır, kutu içeride kalır
        s = smv._yolo_satiri(1, (-50, 0, 1200, 700), 1000, 1400)
        p = s.split()
        cx, w = float(p[1]), float(p[3])
        self.assertLessEqual(cx + w / 2, 1.0 + 1e-6)
        self.assertGreaterEqual(cx - w / 2, -1e-6)

    def test_dejenere_kutu_none(self):
        self.assertIsNone(smv._yolo_satiri(1, (10, 10, 10, 10), 1000, 1400))


class SaflikKuraliTesti(unittest.TestCase):
    def test_temiz_sayfa_kabul(self):
        a = SahteAnaliz([SahteAday((0, 0, 100, 100), "otomatik", 0.9)])
        r = smv._sayfa_saf_mi(a, 0.85)
        self.assertNotEqual(r, False)
        kabul, _ = r
        self.assertEqual(len(kabul), 1)

    def test_kacan_soru_riski_dislar(self):
        a = SahteAnaliz([SahteAday((0, 0, 100, 100), "otomatik", 0.9)],
                        risk=("adaysiz_soru_sayfasi",))
        self.assertIs(smv._sayfa_saf_mi(a, 0.85), False)

    def test_yuksek_guven_yoksa_dislar(self):
        # yalnız incele (0.6) var → yüksek-güvenli çapa yok
        a = SahteAnaliz([SahteAday((0, 0, 100, 100), "incele", 0.6)])
        self.assertIs(smv._sayfa_saf_mi(a, 0.85), False)

    def test_incele_kutu_yuksekle_birlikte_kabul(self):
        # bir otomatik (yüksek) + bir incele → ikisi de etiketlenir
        a = SahteAnaliz([SahteAday((0, 0, 100, 100), "otomatik", 0.9),
                         SahteAday((0, 200, 100, 300), "incele", 0.6)])
        r = smv._sayfa_saf_mi(a, 0.85)
        self.assertNotEqual(r, False)
        kabul, _ = r
        self.assertEqual(len(kabul), 2)

    def test_reddedilen_kutu_etiketlenmez(self):
        a = SahteAnaliz([SahteAday((0, 0, 100, 100), "otomatik", 0.9),
                         SahteAday((0, 200, 100, 300), "reddedildi", 0.3)])
        kabul, _ = smv._sayfa_saf_mi(a, 0.85)
        self.assertEqual(len(kabul), 1)

    def test_pipeline_hatasi_dislar(self):
        a = SahteAnaliz([SahteAday((0, 0, 100, 100))],
                        pipeline=("ocr:hata",))
        self.assertIs(smv._sayfa_saf_mi(a, 0.85), False)


class SinifEslemesiTesti(unittest.TestCase):
    def test_body_ve_anchor(self):
        s = SahteSayfa()
        kabul = [SahteAday((0, 0, 500, 300), numara_kutu=(10, 10, 60, 40))]
        et = smv._sayfa_etiketleri(s, kabul, "coktan_secmeli")
        siniflar = sorted(satir.split()[0] for satir in et)
        self.assertIn("0", siniflar)   # question_anchor
        self.assertIn("1", siniflar)   # question_body

    def test_cozumlu_solution_sinifi(self):
        s = SahteSayfa()
        kabul = [SahteAday((0, 0, 500, 300), rol="çözüm")]
        et = smv._sayfa_etiketleri(s, kabul, "cozumlu")
        siniflar = [satir.split()[0] for satir in et]
        self.assertEqual(["3"], siniflar)  # yalnız solution_or_answer

    def test_cozumlu_belgedeki_soru_iki_sinifla_etiketlenmez(self):
        s = SahteSayfa()
        kabul = [SahteAday((0, 0, 500, 300), rol="soru")]
        et = smv._sayfa_etiketleri(s, kabul, "cozumlu")
        siniflar = [satir.split()[0] for satir in et]
        self.assertEqual(["1"], siniflar)


class YayineviGrubuTesti(unittest.TestCase):
    def test_bilinen_yayinevi_gruplanir(self):
        g1 = smv._yayinevi_grubu("Palme 11. Sınıf.pdf")
        g2 = smv._yayinevi_grubu("palme_biyoloji_2.pdf")
        self.assertEqual(g1, g2)   # ikisi de "palme" grubunda

    def test_farkli_yayinevi_ayri(self):
        self.assertNotEqual(smv._yayinevi_grubu("Palme.pdf"),
                            smv._yayinevi_grubu("Aydın.pdf"))


if __name__ == "__main__":
    unittest.main()
