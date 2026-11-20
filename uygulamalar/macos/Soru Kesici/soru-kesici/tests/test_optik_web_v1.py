#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""soru_kes_web optik işleyicileri — rota dumanı (okuma motoru GEREKMEZ).

Geçici DB/çıktı dizinleriyle sunucu fonksiyonları doğrudan çağrılır
(test_web_v2.py deseni; HTTP katmanı sarmalanmaz)."""
import os
import tempfile
import unittest
from unittest import mock

import optik_kayit as okt
import soru_kes_web as web


def _kagit(no="123", durum="okundu"):
    return {"kaynak": "t.png", "kaynak_sayfa": 1, "sayfa_no": 1,
            "qr": None, "durum": durum, "ogrenci_no": no,
            "ad_soyad": None, "tc_kimlik": None, "kitapcik": "A",
            "cevaplar": {"": {"1": {"hukum": "tek", "sembol": "A",
                                    "guven": .9, "adaylar": ["A"],
                                    "iptal": []},
                              "2": {"hukum": "coklu", "sembol": None,
                                    "guven": .2, "adaylar": ["B", "C"],
                                    "iptal": []}}},
            "sorunlar": [], "kayit": {"yontem": "aruco",
                                      "yerel_kaymalar": {}},
            "olcumler": [], "warp_png": None}


class OptikWebTesti(unittest.TestCase):
    def setUp(self):
        self.dizin = tempfile.TemporaryDirectory()
        self.p1 = mock.patch.object(okt, "VARSAYILAN_DIZIN",
                                    os.path.join(self.dizin.name, "optik"))
        self.p2 = mock.patch.object(web, "CIKTI_DIZIN",
                                    os.path.join(self.dizin.name, "cikti"))
        self.p1.start()
        self.p2.start()

    def tearDown(self):
        self.p1.stop()
        self.p2.stop()
        self.dizin.cleanup()

    def _sinav_kur(self):
        veri = web.optik_uret_islemi({"on_ayar": "yazili-20",
                                      "ad": "Web Test", "kitapcik": 1})
        return veri["sinav_id"]

    def test_durum_ve_on_ayarlar(self):
        d = web.optik_durum_verisi()
        self.assertIn("ok", d)
        self.assertGreaterEqual(len(d["on_ayarlar"]), 7)

    def test_uret_ve_listele(self):
        sid = self._sinav_kur()
        liste = web.optik_sinavlar_verisi()["sinavlar"]
        self.assertEqual(liste[0]["id"], sid)
        self.assertEqual(liste[0]["ad"], "Web Test")

    def test_anahtar_sonuc_akisi(self):
        sid = self._sinav_kur()
        conn = okt.baglan()
        okt.kagit_ekle(conn, sid, _kagit())
        conn.close()
        r = web.optik_anahtar_islemi(
            {"sinav": sid, "kitapcik": "A",
             "cevaplar": {"": {"1": "A", "2": "B"}}})
        self.assertEqual(r["soru"], 2)
        v = web.optik_sonuclar_verisi(sid)
        self.assertEqual(v["anahtarli"], ["A"])
        s = v["sonuclar"][0]
        self.assertEqual(s["ogrenci_no"], "123")
        self.assertEqual(s["dogru"], 1)      # 2. soru çoklu → yanlış
        self.assertEqual(s["yanlis"], 1)

    def test_kagit_detay_ve_duzeltme(self):
        sid = self._sinav_kur()
        conn = okt.baglan()
        kid = okt.kagit_ekle(conn, sid, _kagit(durum="incelenecek"))
        conn.close()
        detay = web.optik_kagit_detay(kid)
        self.assertEqual(detay["kagit"]["durum"], "incelenecek")
        self.assertTrue(detay["gruplar"])
        ilk = detay["gruplar"][0]
        self.assertEqual(ilk["no"], "1")
        self.assertTrue(any(b["isaretli"] for b in ilk["balonlar"]))
        web.optik_duzelt_islemi({"kagit": kid, "ders": "", "soru": "2",
                                 "sembol": "B"})
        detay2 = web.optik_kagit_detay(kid)
        self.assertEqual(detay2["kagit"]["durum"], "okundu")
        g2 = next(g for g in detay2["gruplar"] if g["no"] == "2")
        self.assertEqual(g2["sembol"], "B")
        self.assertTrue(g2["duzeltildi"])

    def test_kazanim_ve_analiz(self):
        sid = self._sinav_kur()
        conn = okt.baglan()
        okt.kagit_ekle(conn, sid, _kagit())
        okt.kagit_ekle(conn, sid, _kagit(no="456"))
        conn.close()
        web.optik_anahtar_islemi(
            {"sinav": sid, "kitapcik": "A",
             "cevaplar": {"": {"1": "A", "2": "B"}}})
        r = web.optik_kazanim_islemi(
            {"sinav": sid, "csv": "ders;soru;kazanim\n;1;Kesirler\n"})
        self.assertEqual(r["soru"], 1)
        analiz = web.optik_analiz_verisi(sid)
        self.assertEqual(analiz["test"]["katilimci"], 2)
        self.assertTrue(analiz["sorular"])
        self.assertTrue(analiz.get("kazanim"))

    def test_disa_csv(self):
        sid = self._sinav_kur()
        conn = okt.baglan()
        okt.kagit_ekle(conn, sid, _kagit())
        conn.close()
        r = web.optik_disa_islemi({"sinav": sid, "tur": "csv"})
        self.assertIn("jeton", r)
        self.assertTrue(r["ad"].endswith(".csv"))

    def test_hatali_girisler(self):
        self.assertIn("hata", web.optik_tara_islemi({"sinav": "yok",
                                                     "yollar": []}))
        self.assertIn("hata", web.optik_anahtar_islemi({"sinav": "yok"}))
        self.assertIn("hata",
                      web.optik_kazanim_islemi({"sinav": "x", "csv": ""}))


if __name__ == "__main__":
    unittest.main()
