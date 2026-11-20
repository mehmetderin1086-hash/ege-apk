#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_sema — şablon şeması birim testleri (cv2 gerekmez)."""
import hashlib
import os
import tempfile
import unittest

import optik_sema as osm

# ARUCO_BITLER bir defalık cv2.aruco.generateImageMarker çıkarımından gelir;
# bu özet o çıkarımı kilitler (yanlışlıkla değişirse üretilen formlar
# okunamaz hale gelir).
ARUCO_OZET = "0dbf1181c4631c10baf82b2e09a3e02df9201176"


def _ornek_sablon():
    hucre = osm.Hucre(cap=10.0, ilk_merkez=(60.0, 520.0),
                      x_adim=16.0, y_adim=14.0)
    alan = osm.Alan(tip="coktan_secmeli", ad="matematik_s1",
                    kutu=(40.0, 500.0, 170.0, 800.0), satir=20, sutun=4,
                    semboller=("A", "B", "C", "D"), hucre=hucre,
                    ders="Matematik", soru_baslangic=1, soru_sayisi=20)
    kitapcik = osm.Alan(tip="kitapcik", ad="kitapcik",
                        kutu=(440.0, 120.0, 560.0, 140.0), satir=1, sutun=2,
                        semboller=("A", "B"),
                        hucre=osm.Hucre(10.0, (450.0, 130.0), 20.0, 14.0))
    ogr_no = osm.Alan(tip="rakam_grid", ad="ogrenci_no",
                      etiket="ÖĞRENCİ NO",
                      kutu=(320.0, 120.0, 420.0, 280.0), satir=10, sutun=5,
                      semboller=osm.RAKAMLAR,
                      hucre=osm.Hucre(9.0, (330.0, 130.0), 19.0, 14.0))
    sayfa = osm.SablonSayfa(
        sayfa_no=1,
        isaretciler=[osm.Isaretci(i, osm.KOSELER[i % 4],
                                  (26.0 + i, 26.0 + i), 24.0)
                     for i in osm.sayfa_isaretci_idleri(1)],
        qr={"kutu": [500.0, 44.0, 552.0, 96.0],
            "icerik": osm.qr_icerik("abc12345", 1)},
        alanlar=[alan, kitapcik, ogr_no])
    return osm.Sablon(sinav_id="abc12345", ad="Deneme",
                      kitapcik_turleri=("A", "B"),
                      puan_kurali={"yanlis_boler": 4}, sayfalar=[sayfa])


class ArucoTest(unittest.TestCase):
    def test_bit_butunlugu(self):
        self.assertEqual(len(osm.ARUCO_BITLER), 48)
        duz = []
        for mid in range(48):
            bitler = osm.ARUCO_BITLER[mid]
            self.assertEqual(len(bitler), 16, f"id {mid}")
            self.assertTrue(all(b in (0, 1) for b in bitler), f"id {mid}")
            duz.extend(bitler)
        ozet = hashlib.sha1(bytes(duz)).hexdigest()
        self.assertEqual(ozet, ARUCO_OZET)

    def test_desenler_benzersiz(self):
        # 4 dönüş varyantı dahil hiçbir desen çakışmamalı (köşe kimliği
        # dönüşten bağımsız çözülebilmeli)
        gorulen = {}
        for mid, bitler in osm.ARUCO_BITLER.items():
            m = [list(bitler[i * 4:(i + 1) * 4]) for i in range(4)]
            for donus in range(4):
                anahtar = tuple(v for satir in m for v in satir)
                self.assertNotIn(anahtar, gorulen,
                                 f"id {mid} dönüş {donus} çakışıyor: "
                                 f"{gorulen.get(anahtar)}")
                gorulen[anahtar] = (mid, donus)
                m = [list(r) for r in zip(*m[::-1])]  # 90° döndür


class KimlikTest(unittest.TestCase):
    def test_sayfa_isaretcileri(self):
        self.assertEqual(osm.sayfa_isaretci_idleri(1), [0, 1, 2, 3])
        self.assertEqual(osm.sayfa_isaretci_idleri(3), [8, 9, 10, 11])
        with self.assertRaises(ValueError):
            osm.sayfa_isaretci_idleri(0)
        with self.assertRaises(ValueError):
            osm.sayfa_isaretci_idleri(osm.AZAMI_SAYFA + 1)

    def test_isaretci_sayfasi(self):
        self.assertEqual(osm.isaretci_sayfasi(0), (1, "sol_ust"))
        self.assertEqual(osm.isaretci_sayfasi(6), (2, "sag_alt"))
        self.assertIsNone(osm.isaretci_sayfasi(-1))
        self.assertIsNone(osm.isaretci_sayfasi(4 * osm.AZAMI_SAYFA))

    def test_qr_gidis_donus(self):
        icerik = osm.qr_icerik("abc12345", 2)
        self.assertEqual(osm.qr_coz(icerik),
                         {"sinav_id": "abc12345", "sayfa_no": 2})
        self.assertIsNone(osm.qr_coz("bozuk"))
        self.assertIsNone(osm.qr_coz("SKO1|x"))
        self.assertIsNone(osm.qr_coz("SKO1||3"))
        self.assertIsNone(osm.qr_coz("SKO2|abc|1"))


class GeometriTest(unittest.TestCase):
    def test_baloncuk_merkezleri(self):
        alan = _ornek_sablon().sayfalar[0].alanlar[0]
        merkezler = osm.baloncuk_merkezleri(alan)
        self.assertEqual(len(merkezler), 20 * 4)
        self.assertEqual(merkezler[0], (0, 0, 60.0, 520.0))
        r, c, x, y = merkezler[-1]
        self.assertEqual((r, c), (19, 3))
        self.assertAlmostEqual(x, 60.0 + 3 * 16.0)
        self.assertAlmostEqual(y, 520.0 + 19 * 14.0)

    def test_hucre_sembol(self):
        s = _ornek_sablon()
        cvp = s.sayfalar[0].alanlar[0]
        self.assertEqual(osm.hucre_sembol(cvp, 5, 2), "C")
        ogr = s.alan_bul("ogrenci_no")
        self.assertEqual(osm.hucre_sembol(ogr, 7, 4), "7")

    def test_sablon_yardimcilari(self):
        s = _ornek_sablon()
        self.assertEqual(s.soru_sayisi(), 20)
        self.assertEqual(s.dersler(), ["Matematik"])
        self.assertIsNotNone(s.alan_bul("kitapcik"))
        self.assertIsNone(s.alan_bul("yok"))


class SerilestirmeTest(unittest.TestCase):
    def test_gidis_donus(self):
        s = _ornek_sablon()
        d = osm.sablon_dict(s)
        self.assertEqual(d["surum"], osm.SEMA_SURUMU)
        s2 = osm.sablon_kur(d)
        self.assertEqual(osm.sablon_dict(s2), d)
        self.assertEqual(s2.sayfalar[0].alanlar[0].semboller,
                         ("A", "B", "C", "D"))

    def test_dosya_gidis_donus(self):
        s = _ornek_sablon()
        with tempfile.TemporaryDirectory() as dizin:
            yol = os.path.join(dizin, "sablon.json")
            osm.sablon_yaz(s, yol)
            s2 = osm.sablon_oku(yol)
        self.assertEqual(osm.sablon_dict(s2), osm.sablon_dict(s))

    def test_surum_uyumsuz(self):
        d = osm.sablon_dict(_ornek_sablon())
        d["surum"] = "baska/v9"
        with self.assertRaises(ValueError):
            osm.sablon_kur(d)


class DogrulamaTest(unittest.TestCase):
    def test_gecerli(self):
        self.assertEqual(osm.dogrula(_ornek_sablon()), [])

    def test_yanlis_isaretci(self):
        s = _ornek_sablon()
        s.sayfalar[0].isaretciler[0].id = 7
        self.assertTrue(any("işaretçi kimlikleri" in h
                            for h in osm.dogrula(s)))

    def test_ad_tekrari(self):
        s = _ornek_sablon()
        s.sayfalar[0].alanlar[1].ad = "matematik_s1"
        self.assertTrue(any("ad tekrarı" in h for h in osm.dogrula(s)))

    def test_soru_tekrari(self):
        s = _ornek_sablon()
        ek = osm.Alan(tip="coktan_secmeli", ad="matematik_s2",
                      kutu=(180.0, 500.0, 310.0, 800.0), satir=5, sutun=4,
                      semboller=("A", "B", "C", "D"),
                      hucre=osm.Hucre(10.0, (200.0, 520.0), 16.0, 14.0),
                      ders="Matematik", soru_baslangic=20, soru_sayisi=5)
        s.sayfalar[0].alanlar.append(ek)
        self.assertTrue(any("soru 20 tekrarı" in h for h in osm.dogrula(s)))

    def test_balon_kutu_disi(self):
        s = _ornek_sablon()
        s.sayfalar[0].alanlar[0].hucre.x_adim = 200.0
        self.assertTrue(any("kutu dışında" in h for h in osm.dogrula(s)))

    def test_qr_uyumsuz(self):
        s = _ornek_sablon()
        s.sayfalar[0].qr["icerik"] = osm.qr_icerik("baskasi", 1)
        self.assertTrue(any("qr içeriği" in h for h in osm.dogrula(s)))


if __name__ == "__main__":
    unittest.main()
