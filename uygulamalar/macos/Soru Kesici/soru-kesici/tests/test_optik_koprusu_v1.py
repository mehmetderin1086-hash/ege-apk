#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_koprusu — sınav→optik köprüsü: kitapçık permütasyonu↔anahtar
eşleşmesi, kazanım çevirisi, DB kaydı (cv2 gerekmez)."""
import os
import tempfile
import unittest
from unittest import mock

import optik_analiz as oan
import optik_kayit as okt
import optik_koprusu as okp


def _meta(cevaplar="ABCDABCDAB", konular=None):
    """sinav_pdf_uret biçiminde soru meta listesi."""
    return [{"soru_no": i + 1, "test_sira": 1, "cevap": c,
             "konu": (konular or {}).get(i + 1), "numara_px": None}
            for i, c in enumerate(cevaplar)]


class YardimciTest(unittest.TestCase):
    def test_secenek_sayisi(self):
        self.assertEqual(okp.secenek_sayisi(_meta("ABCD")), 4)
        self.assertEqual(okp.secenek_sayisi(_meta("ABE")), 5)
        self.assertEqual(okp.secenek_sayisi(_meta("")), 4)

    def test_kazanim_haritasi(self):
        harita = okp.kazanim_haritasi(
            _meta("ABC", konular={1: "Kesirler", 3: "Oran"}))
        self.assertEqual(harita, {"": {"1": "Kesirler", "3": "Oran"}})
        self.assertEqual(okp.kazanim_haritasi(_meta("ABC")), {})


class AnahtarTest(unittest.TestCase):
    def test_a_kitapcigi_kimlik(self):
        meta = _meta("ABCDABCDAB")
        anahtarlar, sira = okp.anahtarlar_ve_sira(meta, 2, tohum=7)
        self.assertEqual(anahtarlar["A"][""],
                         {str(i + 1): c for i, c in enumerate("ABCDABCDAB")})
        self.assertEqual(sira["A"], list(range(1, 11)))

    def test_b_kitapcigi_permutasyonla_eslesir(self):
        """B anahtarı, sinav_pdf'in AYNI tohumla ürettiği kitapçık
        sırasındaki soruların cevaplarıyla birebir aynı olmalı —
        kapalı döngünün özü."""
        import sinav_pdf
        meta = _meta("ABCDABCDAB")
        anahtarlar, kitapcik_sira = okp.anahtarlar_ve_sira(meta, 2, tohum=7)
        beklenen_sira = sinav_pdf._grup_ici_karistir(meta, 7, 1)
        self.assertEqual(kitapcik_sira["B"],
                         [j + 1 for j in beklenen_sira])
        for i, j in enumerate(beklenen_sira):
            self.assertEqual(anahtarlar["B"][""][str(i + 1)],
                             meta[j]["cevap"], f"B kitapçığı soru {i + 1}")
        # permütasyon gerçekten karıştırmış olmalı (tohum 7, 10 soru)
        self.assertNotEqual(kitapcik_sira["B"], kitapcik_sira["A"])

    def test_cevapsiz_meta(self):
        anahtarlar, _ = okp.anahtarlar_ve_sira(
            [{"cevap": None, "test_sira": 1} for _ in range(3)], 1, None)
        self.assertEqual(set(anahtarlar["A"][""].values()), {""})


class SinavdanOptikTest(unittest.TestCase):
    def setUp(self):
        self.dizin = tempfile.TemporaryDirectory()
        self.p = mock.patch.object(okt, "VARSAYILAN_DIZIN",
                                   os.path.join(self.dizin.name, "optik"))
        self.p.start()

    def tearDown(self):
        self.p.stop()
        self.dizin.cleanup()

    def test_uret_ve_kaydet(self):
        meta = _meta("ABCDABCDAB", konular={1: "Kesirler", 2: "Kesirler",
                                            5: "Oran"})
        ayarlar = {"baslik": "Köprü Testi", "kurum": "Test Okulu",
                   "kitapcik": 2, "tohum": 7}
        yol = os.path.join(self.dizin.name, "sinav_optik.pdf")
        sonuc = okp.sinavdan_optik(meta, ayarlar, yol)
        self.assertTrue(os.path.isfile(sonuc["pdf"]))
        self.assertEqual(sonuc["soru"], 10)
        self.assertEqual(sonuc["anahtarli_soru"], 10)
        self.assertEqual(sonuc["kazanimli_soru"], 3)
        self.assertEqual(sonuc["uyarilar"], [])
        # DB'ye yazıldı mı?
        conn = okt.baglan()
        sinav = okt.sinav_al(conn, sonuc["sinav_id"])
        anahtarlar = okt.anahtarlar(conn, sonuc["sinav_id"])
        conn.close()
        self.assertIsNotNone(sinav)
        self.assertEqual(sinav["sablon"].soru_sayisi(), 10)
        self.assertEqual(sorted(anahtarlar), ["A", "B"])
        self.assertEqual(sinav["kazanimlar"][""]["1"], "Kesirler")
        self.assertEqual(sinav["ayarlar"]["kitapcik_sira"]["A"],
                         list(range(1, 11)))
        self.assertEqual(sinav["ayarlar"]["kaynak"], "sinav_pdf")

    def test_uyarilar(self):
        meta = [{"cevap": None, "test_sira": 1, "konu": None}
                for _ in range(5)]
        sonuc = okp.sinavdan_optik(
            meta, {"baslik": "X", "yeniden_numarala": False},
            os.path.join(self.dizin.name, "u.pdf"), kaydet=False)
        self.assertEqual(sonuc["anahtarli_soru"], 0)
        self.assertEqual(len(sonuc["uyarilar"]), 2)

    def test_bos_meta_hata(self):
        with self.assertRaises(ValueError):
            okp.sinavdan_optik([], {}, "x.pdf", kaydet=False)


class KazanimCeviriTest(unittest.TestCase):
    def test_b_kitapcigi_kazanimi_kanonik_numaradan_bulur(self):
        """B kitapçığındaki öğrencinin form-1. sorusu kanonik X. soruya
        denk gelir; kazanım X'in konusundan sayılmalı."""
        meta = _meta("ABCDABCDAB",
                     konular={i: f"K{i}" for i in range(1, 11)})
        anahtarlar, kitapcik_sira = okp.anahtarlar_ve_sira(meta, 2, tohum=7)
        kazanimlar = okp.kazanim_haritasi(meta)
        kanonik_1 = kitapcik_sira["B"][0]        # B form-1 → kanonik no
        dogru_cevap = anahtarlar["B"][""]["1"]
        kagit = {"id": 1, "ogrenci_no": "9", "ad_soyad": None,
                 "kitapcik": "B", "durum": "okundu", "sayfa_no": 1,
                 "cevaplar": {"": {"1": {
                     "hukum": "tek", "sembol": dogru_cevap, "guven": 1.0,
                     "adaylar": [dogru_cevap], "iptal": []}}},
                 "sorunlar": []}
        sonuclar = oan.puanla([kagit], anahtarlar)
        self.assertEqual(sonuclar[0]["toplam"]["dogru"], 1)
        ka = oan.kazanim_analizi(sonuclar, kazanimlar,
                                 kitapcik_sira=kitapcik_sira)
        self.assertEqual(len(ka["kazanimlar"]), 1)
        kayit = ka["kazanimlar"][0]
        self.assertEqual(kayit["kazanim"], f"K{kanonik_1}")
        self.assertEqual(kayit["dogru"], 1)
        self.assertEqual(kayit["sorular"], [str(kanonik_1)])

    def test_ceviri_yoksa_dogrudan_numara(self):
        kazanimlar = {"": {"1": "K1"}}
        kagit = {"id": 1, "ogrenci_no": "9", "ad_soyad": None,
                 "kitapcik": None, "durum": "okundu", "sayfa_no": 1,
                 "cevaplar": {"": {"1": {"hukum": "tek", "sembol": "A",
                                        "guven": 1.0, "adaylar": ["A"],
                                        "iptal": []}}},
                 "sorunlar": []}
        sonuclar = oan.puanla([kagit], {"A": {"": {"1": "A"}}})
        ka = oan.kazanim_analizi(sonuclar, kazanimlar)
        self.assertEqual(ka["kazanimlar"][0]["kazanim"], "K1")


if __name__ == "__main__":
    unittest.main()
