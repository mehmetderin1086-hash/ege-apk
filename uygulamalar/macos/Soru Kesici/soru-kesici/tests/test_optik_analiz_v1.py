#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""optik_analiz — puanlama ve madde analizi (elle hesaplanmış fikstürler)."""
import os
import tempfile
import unittest

import optik_analiz as oan


def _cevap(sembol, hukum=None):
    if sembol is None:
        return {"hukum": hukum or "bos", "sembol": None, "guven": 0.9,
                "adaylar": [], "iptal": []}
    return {"hukum": hukum or "tek", "sembol": sembol, "guven": 0.9,
            "adaylar": [sembol], "iptal": []}


def _kagit(no, cevaplar, kitapcik="A", durum="okundu", kid=None,
           ders="Matematik"):
    return {"id": kid or int(no), "ogrenci_no": no, "ad_soyad": f"ÖĞR {no}",
            "kitapcik": kitapcik, "durum": durum, "sayfa_no": 1,
            "cevaplar": {ders: {str(i + 1): c
                                for i, c in enumerate(cevaplar)}},
            "sorunlar": []}


ANAHTAR = {"A": {"Matematik": {"1": "A", "2": "B", "3": "C", "4": "D",
                               "5": "A"}}}


class PuanlamaTest(unittest.TestCase):
    def test_net_hesabi_bolen4(self):
        # 3D 1Y 1B → net = 3 − 1/4 = 2.75
        k = _kagit("11", [_cevap("A"), _cevap("B"), _cevap("C"),
                          _cevap("A"), _cevap(None)])
        s = oan.puanla([k], ANAHTAR, {"yanlis_boler": 4})[0]
        d = s["dersler"]["Matematik"]
        self.assertEqual((d["dogru"], d["yanlis"], d["bos"]), (3, 1, 1))
        self.assertAlmostEqual(d["net"], 2.75)
        self.assertEqual(s["toplam"]["yuzde"], 60.0)

    def test_net_hesabi_bolen3_ve_cezasiz(self):
        k = _kagit("11", [_cevap("A"), _cevap("A"), _cevap("A"),
                          _cevap("A"), _cevap("A")])  # 2D 3Y
        net3 = oan.puanla([k], ANAHTAR,
                          {"yanlis_boler": 3})[0]["toplam"]["net"]
        net0 = oan.puanla([k], ANAHTAR,
                          {"yanlis_boler": 0})[0]["toplam"]["net"]
        self.assertAlmostEqual(net3, 2 - 3 / 3)
        self.assertAlmostEqual(net0, 2.0)

    def test_coklu_yanlis_belirsiz_bos(self):
        k = _kagit("11", [_cevap(None, "coklu"), _cevap(None, "belirsiz"),
                          _cevap("C"), _cevap(None), _cevap(None)])
        d = oan.puanla([k], ANAHTAR)[0]["dersler"]["Matematik"]
        self.assertEqual(d["sorular"]["1"]["sonuc"], "yanlis")
        self.assertEqual(d["sorular"]["2"]["sonuc"], "bos")
        self.assertEqual(d["dogru"], 1)

    def test_coklu_dogru_anahtar_ve_iptal(self):
        anahtar = {"A": {"Matematik": {"1": "AB", "2": "", "3": "C",
                                       "4": "D", "5": "A"}}}
        k = _kagit("11", [_cevap("B"), _cevap("D"), _cevap("C"),
                          _cevap("D"), _cevap("A")])
        d = oan.puanla([k], anahtar)[0]["dersler"]["Matematik"]
        self.assertEqual(d["sorular"]["1"]["sonuc"], "dogru")   # B ∈ AB
        self.assertEqual(d["sorular"]["2"]["sonuc"], "iptal")   # anahtar boş
        self.assertEqual(d["soru"], 4)                          # iptal dışı
        self.assertEqual(d["dogru"], 4)

    def test_kitapcik_anahtari_secimi(self):
        anahtarlar = {"A": ANAHTAR["A"],
                      "B": {"Matematik": {"1": "B", "2": "A", "3": "D",
                                          "4": "C", "5": "B"}}}
        cevaplar = [_cevap("B"), _cevap("A"), _cevap("D"), _cevap("C"),
                    _cevap("B")]
        sB = oan.puanla([_kagit("11", cevaplar, kitapcik="B")],
                        anahtarlar)[0]
        sA = oan.puanla([_kagit("12", cevaplar, kitapcik="A")],
                        anahtarlar)[0]
        self.assertEqual(sB["toplam"]["dogru"], 5)
        self.assertEqual(sA["toplam"]["dogru"], 0)

    def test_anahtar_yok(self):
        s = oan.puanla([_kagit("11", [_cevap("A")], kitapcik="C")],
                       {"A": {}, "B": {}})[0]
        self.assertTrue(any("anahtarı yok" in p for p in s["sorunlar"]))

    def test_cok_sayfa_birlesir(self):
        k1 = _kagit("11", [_cevap("A"), _cevap("B")], kid=1)
        k2 = {"id": 2, "ogrenci_no": "11", "ad_soyad": None,
              "kitapcik": None, "durum": "okundu", "sayfa_no": 2,
              "cevaplar": {"Fen": {"1": _cevap("C")}}, "sorunlar": []}
        gruplar = oan.ogrencileri_grupla([k1, k2])
        self.assertEqual(len(gruplar), 1)
        self.assertEqual(sorted(gruplar[0]["cevaplar"]),
                         ["Fen", "Matematik"])
        self.assertEqual(gruplar[0]["kagit_idler"], [1, 2])

    def test_siralama(self):
        iyi = _kagit("1", [_cevap(c) for c in "ABCDA"])
        orta = _kagit("2", [_cevap(c) for c in "ABCDD"])
        sonuclar = oan.puanla([orta, iyi], ANAHTAR, {"yanlis_boler": 4})
        self.assertEqual([s["ogrenci_no"] for s in sonuclar], ["1", "2"])
        self.assertEqual(sonuclar[0]["sira"], 1)


class MaddeAnaliziTest(unittest.TestCase):
    def _sonuclar(self):
        # s1: q1✓ q2✓ | s2: q1✓ q2✗ | s3: q1✗ q2✗  (2 soruluk anahtar)
        anahtar = {"A": {"Matematik": {"1": "A", "2": "B"}}}
        kagitlar = [
            _kagit("1", [_cevap("A"), _cevap("B")]),
            _kagit("2", [_cevap("A"), _cevap("C")]),
            _kagit("3", [_cevap("B"), _cevap("C")]),
        ]
        return oan.puanla(kagitlar, anahtar), anahtar

    def test_kr20_elle(self):
        sonuclar, anahtar = self._sonuclar()
        analiz = oan.madde_analizi(sonuclar, anahtar)
        # p1=2/3, p2=1/3; Σpq=4/9; toplamlar [2,1,0] pop.var=2/3
        # KR20 = 2·(1 − (4/9)/(2/3)) = 0.667
        self.assertAlmostEqual(analiz["test"]["kr20"], 0.667, places=3)
        self.assertEqual(analiz["test"]["katilimci"], 3)

    def test_p_ve_ayirt(self):
        sonuclar, anahtar = self._sonuclar()
        sorular = {q["soru"]: q
                   for q in oan.madde_analizi(sonuclar,
                                              anahtar)["sorular"]}
        self.assertAlmostEqual(sorular["1"]["p"], 0.667, places=3)
        self.assertAlmostEqual(sorular["2"]["p"], 0.333, places=3)
        # üst-alt dilim=1: q1 üst ✓ alt ✗ → 1.0
        self.assertAlmostEqual(sorular["1"]["ayirt_edicilik"], 1.0)
        self.assertGreater(sorular["1"]["nokta_ciftserili"], 0)

    def test_dagilim_ve_uyari(self):
        anahtar = {"A": {"Matematik": {"1": "A"}}}
        # herkes yanlış B → negatif korelasyon değil ama p=0
        kagitlar = [_kagit(str(i), [_cevap("B")]) for i in range(3)]
        analiz = oan.madde_analizi(oan.puanla(kagitlar, anahtar), anahtar)
        q = analiz["sorular"][0]
        self.assertEqual(q["dagilim"], {"B": 3})
        self.assertTrue(any("ayırt" in u for u in q["uyarilar"]))


class KazanimTest(unittest.TestCase):
    def test_kazanim_analizi(self):
        anahtar = {"A": {"Matematik": {"1": "A", "2": "B", "3": "C"}}}
        kazanimlar = {"Matematik": {"1": "Kesirler", "2": "Kesirler",
                                    "3": "Oran"}}
        kagitlar = [
            _kagit("1", [_cevap("A"), _cevap("B"), _cevap("D")]),
            _kagit("2", [_cevap("A"), _cevap("C"), _cevap(None)]),
        ]
        ka = oan.kazanim_analizi(oan.puanla(kagitlar, anahtar), kazanimlar)
        kesir = next(k for k in ka["kazanimlar"]
                     if k["kazanim"] == "Kesirler")
        self.assertEqual(kesir["dogru"], 3)          # 2×q1 + 1×q2
        self.assertEqual(kesir["yanlis"], 1)
        self.assertEqual(kesir["sorular"], ["1", "2"])
        self.assertIn("1", ka["ogrenciler"])
        ogr1_kesir = next(k for k in ka["ogrenciler"]["1"]
                          if k["kazanim"] == "Kesirler")
        self.assertEqual(ogr1_kesir["dogru"], 2)

    def test_kazanim_csv(self):
        with tempfile.TemporaryDirectory() as dizin:
            yol = os.path.join(dizin, "k.csv")
            with open(yol, "w", encoding="utf-8") as f:
                f.write("ders;soru;kazanim\n"
                        "Matematik;1;Kesirler\n"
                        "Matematik;2;Oran\n")
            k = oan.kazanim_csv_oku(yol)
        self.assertEqual(k["Matematik"]["1"], "Kesirler")
        self.assertEqual(k["Matematik"]["2"], "Oran")


class DisaTest(unittest.TestCase):
    def setUp(self):
        self.kagitlar = [
            _kagit("101", [_cevap("A"), _cevap("B"), _cevap("C"),
                           _cevap(None), _cevap("B")]),
            _kagit("102", [_cevap("A"), _cevap("A"), _cevap("C"),
                           _cevap("D"), _cevap("A")]),
        ]
        self.sonuclar = oan.puanla(self.kagitlar, ANAHTAR,
                                   {"yanlis_boler": 4})
        self.dizin = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.dizin.cleanup()

    def test_csv(self):
        yol = oan.disa_csv(self.sonuclar,
                           os.path.join(self.dizin.name, "s.csv"))
        with open(yol, encoding="utf-8-sig") as f:
            satirlar = f.read().splitlines()
        self.assertEqual(len(satirlar), 3)
        self.assertIn("Matematik Net", satirlar[0])
        self.assertIn("102", satirlar[1])          # 102 daha yüksek net

    def test_txt_sabit_genislik(self):
        yol = oan.disa_txt(self.sonuclar,
                           os.path.join(self.dizin.name, "s.txt"))
        with open(yol, encoding="utf-8") as f:
            satirlar = f.read().splitlines()
        self.assertEqual(len(satirlar), 2)
        # no(10) + ad(25) + kitapçık(1) + 5 cevap = 41
        self.assertTrue(all(len(s) == 41 for s in satirlar))
        self.assertTrue(satirlar[0].startswith("102       "))
        self.assertTrue(satirlar[0].endswith("AACDA"))

    def test_eokul(self):
        yol = oan.disa_eokul(self.sonuclar,
                             os.path.join(self.dizin.name, "e.csv"))
        with open(yol, encoding="utf-8-sig") as f:
            icerik = f.read()
        self.assertIn("102;80", icerik.replace(",0", ""))

    def test_karne_pdf(self):
        import fitz
        yol = oan.karne_pdf(self.sonuclar,
                            os.path.join(self.dizin.name, "karne.pdf"),
                            sinav_ad="Deneme")
        doc = fitz.open(yol)
        self.assertEqual(len(doc), 2)
        metin = doc[0].get_text().replace("\xa0", " ")
        doc.close()
        self.assertIn("Sonuç Karnesi", metin)
        self.assertIn("TOPLAM", metin)


if __name__ == "__main__":
    unittest.main()
