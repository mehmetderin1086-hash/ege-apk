#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_oku — eşik/hüküm mantığı testleri (cv2 GEREKMEZ, sahte ölçümler)."""
import unittest

import optik_oku as ook
import optik_sema as osm

DOLU = {"doluluk": 1.0, "parlaklik": 0.15, "erozyon_dayanimi": 0.55}
BOS = {"doluluk": 0.10, "parlaklik": 0.88, "erozyon_dayanimi": 0.0}
SILIK = {"doluluk": 0.48, "parlaklik": 0.55, "erozyon_dayanimi": 0.35}
IPTAL_X = {"doluluk": 0.42, "parlaklik": 0.50, "erozyon_dayanimi": 0.08}


def _sablon():
    cvp = osm.Alan(tip="coktan_secmeli", ad="mat_s1",
                   kutu=(200, 100, 320, 400), satir=10, sutun=4,
                   semboller=("A", "B", "C", "D"),
                   hucre=osm.Hucre(10.0, (220, 110), 16.0, 14.0),
                   ders="Matematik", soru_baslangic=1, soru_sayisi=10)
    kit = osm.Alan(tip="kitapcik", ad="kitapcik",
                   kutu=(360, 76, 430, 96), satir=1, sutun=2,
                   semboller=("A", "B"),
                   hucre=osm.Hucre(10.0, (370, 86), 18.0, 14.0))
    ogr = osm.Alan(tip="rakam_grid", ad="ogrenci_no",
                   kutu=(40, 100, 120, 240), satir=10, sutun=3,
                   semboller=osm.RAKAMLAR,
                   hucre=osm.Hucre(9.0, (50, 110), 15.0, 13.0))
    sayfa = osm.SablonSayfa(
        sayfa_no=1,
        isaretciler=[osm.Isaretci(i, osm.KOSELER[i % 4], (26, 26), 24.0)
                     for i in osm.sayfa_isaretci_idleri(1)],
        alanlar=[cvp, kit, ogr])
    return osm.Sablon(sinav_id="test1234", ad="Test",
                      kitapcik_turleri=("A", "B"), sayfalar=[sayfa])


def _olcumler(cevaplar, kitapcik=0, ogrenci="123", ozel=None):
    """cevaplar: soru başına işaretli sütun listesi (None=boş).
    ozel: {(alan,satir,sutun): olcum} geçersiz kılmaları."""
    olc = []
    for r in range(10):
        secim = cevaplar[r] if r < len(cevaplar) else None
        secili = set(secim if isinstance(secim, (list, tuple))
                     else [] if secim is None else [secim])
        for c in range(4):
            o = dict(DOLU if c in secili else BOS)
            olc.append(dict(o, alan="mat_s1", satir=r, sutun=c))
    for c in range(2):
        olc.append(dict(DOLU if c == kitapcik else BOS,
                        alan="kitapcik", satir=0, sutun=c))
    for c in range(3):
        hedef = int(ogrenci[c]) if c < len(ogrenci) else None
        for r in range(10):
            olc.append(dict(DOLU if r == hedef else BOS,
                            alan="ogrenci_no", satir=r, sutun=c))
    for (alan, r, c), deger in (ozel or {}).items():
        for o in olc:
            if (o["alan"], o["satir"], o["sutun"]) == (alan, r, c):
                o.update(deger)
    return olc


KAYIT_IYI = {"yontem": "aruco", "isaretci_sayisi": 4,
             "yeniden_yansitma_px": 0.2, "yerel_kaymalar": {}}


class EsikTest(unittest.TestCase):
    def test_bimodal(self):
        skorlar = [0.12] * 30 + [0.94] * 10
        esik, sicrama = ook._sicrama_esigi(skorlar)
        self.assertGreater(esik, 0.3)
        self.assertLess(esik, 0.9)
        self.assertGreater(sicrama, 0.5)

    def test_tamamen_bos(self):
        esik, sicrama = ook._sicrama_esigi([0.10, 0.12, 0.14] * 20)
        self.assertEqual(sicrama, 0.0)
        self.assertGreater(esik, 0.14)

    def test_silik_ilk_sicramada_yakalanir(self):
        # boşlar ~0.12, silik 0.45, dolular 0.94 → İLK sıçrama 0.12→0.45
        skorlar = [0.12] * 30 + [0.45] + [0.94] * 9
        esik, _ = ook._sicrama_esigi(skorlar)
        self.assertLess(esik, 0.45)

    def test_aykiri_bos_taban_korur(self):
        # tek aşırı-açık boş (0.02) eşiği çökertmesin
        skorlar = [0.02] + [0.25] * 30 + [0.9] * 5
        esik, _ = ook._sicrama_esigi(skorlar)
        self.assertGreaterEqual(esik, ook.TABAN_ESIK)


class HukumTest(unittest.TestCase):
    def setUp(self):
        self.sablon = _sablon()

    def _hukum(self, olc):
        return ook.hukum_ver(olc, self.sablon, 1)

    def test_temiz_okuma(self):
        h = self._hukum(_olcumler([0, 1, 2, 3, 0, 1, 2, 3, None, None]))
        cevap = h["mat_s1"]
        self.assertEqual([g["hukum"] for g in cevap],
                         ["tek"] * 8 + ["bos", "bos"])
        self.assertEqual([g["sembol"] for g in cevap[:4]],
                         ["A", "B", "C", "D"])
        self.assertTrue(all(g["guven"] > 0.5 for g in cevap))

    def test_coklu_isaret(self):
        h = self._hukum(_olcumler([[0, 2], 1, None]))
        self.assertEqual(h["mat_s1"][0]["hukum"], "coklu")
        self.assertEqual(h["mat_s1"][0]["adaylar"], ["A", "C"])
        self.assertIsNone(h["mat_s1"][0]["sembol"])

    def test_silik_isaret_dolu_sayilir(self):
        h = self._hukum(_olcumler([0, 1], ozel={("mat_s1", 2, 3): SILIK}))
        self.assertEqual(h["mat_s1"][2]["hukum"], "tek")
        self.assertEqual(h["mat_s1"][2]["sembol"], "D")

    def test_iptal_x_gecersiz(self):
        # 3. soruda X ile iptal + başka şık gerçekten dolu → tek (dolu şık)
        h = self._hukum(_olcumler([0, 1, 1],
                                  ozel={("mat_s1", 2, 0): IPTAL_X}))
        g = h["mat_s1"][2]
        self.assertEqual(g["hukum"], "tek")
        self.assertEqual(g["sembol"], "B")
        self.assertEqual(g["iptal"], ["A"])

    def test_tamamen_bos_sayfa(self):
        h = self._hukum(_olcumler([None] * 10, kitapcik=None,
                                  ogrenci=""))
        self.assertTrue(all(g["hukum"] == "bos" for g in h["mat_s1"]))

    def test_grid_sutun_hukmu(self):
        h = self._hukum(_olcumler([0], ogrenci="507"))
        self.assertEqual([g["sembol"] for g in h["ogrenci_no"]],
                         ["5", "0", "7"])


class KagitBirlestirTest(unittest.TestCase):
    def setUp(self):
        self.sablon = _sablon()

    def _kagit(self, olc, kayit=KAYIT_IYI):
        h = ook.hukum_ver(olc, self.sablon, 1)
        return ook.kagit_birlestir(h, self.sablon, 1, kayit,
                                   qr="SKO1|test1234|1")

    def test_temiz_kagit(self):
        k = self._kagit(_olcumler([0, 1, 2, 3], kitapcik=1,
                                  ogrenci="042"))
        self.assertEqual(k["durum"], "okundu")
        self.assertEqual(k["ogrenci_no"], "042")
        self.assertEqual(k["kitapcik"], "B")
        self.assertEqual(k["cevaplar"]["Matematik"]["1"]["sembol"], "A")
        self.assertEqual(k["cevaplar"]["Matematik"]["5"]["hukum"], "bos")

    def test_coklu_inceleme_kuyruguna(self):
        k = self._kagit(_olcumler([[0, 1], 2]))
        self.assertEqual(k["durum"], "incelenecek")
        self.assertTrue(any("belirsiz/çoklu" in s for s in k["sorunlar"]))

    def test_kitapcik_eksik(self):
        k = self._kagit(_olcumler([0, 1], kitapcik=None))
        self.assertEqual(k["durum"], "incelenecek")
        self.assertTrue(any("kitapçık" in s.lower() for s in k["sorunlar"]))

    def test_zayif_kayit(self):
        kayit = dict(KAYIT_IYI, yontem="olcek")
        k = self._kagit(_olcumler([0, 1], kitapcik=0), kayit=kayit)
        self.assertEqual(k["durum"], "incelenecek")

    def test_ogrenci_no_kisa_normal(self):
        # kısa numara (boş sütunlar) sorun DEĞİLDİR
        k = self._kagit(_olcumler([0], ogrenci="4", kitapcik=0))
        self.assertEqual(k["ogrenci_no"], "4")
        self.assertFalse(any("öğrenci no" in s for s in k["sorunlar"]))

    def test_ogrenci_no_bos_supheli(self):
        k = self._kagit(_olcumler([0], ogrenci="", kitapcik=0))
        self.assertTrue(any("öğrenci no" in s for s in k["sorunlar"]))


if __name__ == "__main__":
    unittest.main()
