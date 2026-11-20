#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_kayit — SQLite kalıcılık testleri (geçici dizinde)."""
import os
import tempfile
import unittest

import optik_kayit as okt
import optik_sema as osm


def _sablon(sinav_id="kayit123"):
    alan = osm.Alan(tip="coktan_secmeli", ad="mat_s1",
                    kutu=(200, 100, 320, 400), satir=5, sutun=4,
                    semboller=("A", "B", "C", "D"),
                    hucre=osm.Hucre(10.0, (220, 110), 16.0, 14.0),
                    ders="Matematik", soru_baslangic=1, soru_sayisi=5)
    sayfa = osm.SablonSayfa(
        sayfa_no=1,
        isaretciler=[osm.Isaretci(i, osm.KOSELER[i % 4], (26, 26), 24.0)
                     for i in osm.sayfa_isaretci_idleri(1)],
        alanlar=[alan])
    return osm.Sablon(sinav_id=sinav_id, ad="Kayıt Testi",
                      kitapcik_turleri=("A",), sayfalar=[sayfa])


def _kagit(ogrenci="123", durum="okundu"):
    return {"kaynak": "tarama.jpg", "kaynak_sayfa": 1, "sayfa_no": 1,
            "qr": "SKO1|kayit123|1", "durum": durum,
            "ogrenci_no": ogrenci, "ad_soyad": "ALİ VELİ",
            "tc_kimlik": None, "kitapcik": "A",
            "cevaplar": {"Matematik": {
                "1": {"hukum": "tek", "sembol": "A", "guven": 0.9,
                      "adaylar": ["A"], "iptal": []},
                "2": {"hukum": "belirsiz", "sembol": None, "guven": 0.1,
                      "adaylar": [], "iptal": []}}},
            "sorunlar": [], "kayit": {"yontem": "aruco"},
            "olcumler": [{"alan": "mat_s1", "satir": 0, "sutun": 0,
                          "doluluk": 1.0, "parlaklik": 0.2,
                          "erozyon_dayanimi": 0.5}],
            "warp_png": None}


class KayitTest(unittest.TestCase):
    def setUp(self):
        self.dizin = tempfile.TemporaryDirectory()
        self.yol = self.dizin.name
        self.conn = okt.baglan(self.yol)

    def tearDown(self):
        self.conn.close()
        self.dizin.cleanup()

    def test_sinav_gidis_donus(self):
        s = _sablon()
        okt.sinav_ekle(self.conn, s, {"yanlis_boler": 3})
        liste = okt.sinav_listesi(self.conn)
        self.assertEqual(len(liste), 1)
        self.assertEqual(liste[0]["id"], "kayit123")
        geri = okt.sinav_al(self.conn, "kayit123")
        self.assertEqual(osm.sablon_dict(geri["sablon"]),
                         osm.sablon_dict(s))
        self.assertEqual(geri["ayarlar"], {"yanlis_boler": 3})
        self.assertIsNone(okt.sinav_al(self.conn, "yok"))

    def test_anahtarlar(self):
        okt.sinav_ekle(self.conn, _sablon())
        okt.anahtar_koy(self.conn, "kayit123", "A",
                        {"Matematik": {"1": "A", "2": "B"}})
        okt.anahtar_koy(self.conn, "kayit123", "B",
                        {"Matematik": {"1": "B", "2": "A"}})
        a = okt.anahtarlar(self.conn, "kayit123")
        self.assertEqual(sorted(a), ["A", "B"])
        self.assertEqual(a["A"]["Matematik"]["1"], "A")
        # üzerine yazma
        okt.anahtar_koy(self.conn, "kayit123", "A",
                        {"Matematik": {"1": "C"}})
        self.assertEqual(okt.anahtarlar(self.conn, "kayit123")
                         ["A"]["Matematik"]["1"], "C")

    def test_kagit_dongusu(self):
        okt.sinav_ekle(self.conn, _sablon())
        kid = okt.kagit_ekle(self.conn, "kayit123", _kagit(), self.yol)
        k = okt.kagit_al(self.conn, kid)
        self.assertEqual(k["ogrenci_no"], "123")
        self.assertEqual(k["cevaplar"]["Matematik"]["1"]["sembol"], "A")
        self.assertEqual(len(okt.kagitlar(self.conn, "kayit123")), 1)
        self.assertEqual(okt.kagit_olcumleri(self.conn, kid)[0]["alan"],
                         "mat_s1")

    def test_duzeltme_bindirme(self):
        okt.sinav_ekle(self.conn, _sablon())
        kid = okt.kagit_ekle(self.conn, "kayit123",
                             _kagit(durum="incelenecek"), self.yol)
        okt.kagit_duzelt(self.conn, kid,
                         {"cevaplar": {"Matematik": {"2": "C"}},
                          "ogrenci_no": "999"})
        k = okt.kagit_al(self.conn, kid)
        self.assertEqual(k["durum"], "okundu")        # düzeltme kuyruğu kapatır
        self.assertEqual(k["ogrenci_no"], "999")
        self.assertEqual(k["cevaplar"]["Matematik"]["2"]["sembol"], "C")
        self.assertTrue(k["cevaplar"]["Matematik"]["2"].get("duzeltildi"))
        # okunan 1. soru dokunulmadan kalır
        self.assertEqual(k["cevaplar"]["Matematik"]["1"]["sembol"], "A")

    def test_durum_filtresi_ve_silme(self):
        okt.sinav_ekle(self.conn, _sablon())
        okt.kagit_ekle(self.conn, "kayit123", _kagit(), self.yol)
        k2 = okt.kagit_ekle(self.conn, "kayit123",
                            _kagit(ogrenci="456", durum="incelenecek"),
                            self.yol)
        self.assertEqual(len(okt.kagitlar(self.conn, "kayit123",
                                          durum="incelenecek")), 1)
        okt.kagit_sil(self.conn, k2)
        self.assertEqual(len(okt.kagitlar(self.conn, "kayit123")), 1)
        okt.sinav_sil(self.conn, "kayit123", self.yol)
        self.assertEqual(okt.sinav_listesi(self.conn), [])
        self.assertEqual(okt.kagitlar(self.conn, "kayit123"), [])


if __name__ == "__main__":
    unittest.main()
