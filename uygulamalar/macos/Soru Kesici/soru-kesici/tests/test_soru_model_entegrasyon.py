#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""question_layout_v3 tespit entegrasyonu testleri (Faz C1).

Sıfır-etki garantisi (model yokken []), _kutu_iou doğruluğu ve
monkeypatch'li sahte bölgelerle kanıt/puan yolları.
"""

import copy
import tempfile
import unittest
from unittest import mock

import duzen_model as dm
import soru_kes as sk


class SahteSayfa:
    def __init__(self, genislik=1000.0, yukseklik=1400.0):
        self.genislik = genislik
        self.yukseklik = yukseklik
        self.raster = False

    def gorsel(self):
        from PIL import Image
        return Image.new("RGB", (int(self.genislik), int(self.yukseklik)),
                         "white"), 1.0


class KutuIouTesti(unittest.TestCase):
    def test_ayni_kutu_bir(self):
        self.assertAlmostEqual(sk._kutu_iou((0, 0, 10, 10),
                                            (0, 0, 10, 10)), 1.0)

    def test_ayrik_kutu_sifir(self):
        self.assertEqual(sk._kutu_iou((0, 0, 10, 10), (20, 20, 30, 30)), 0.0)

    def test_yarim_ortusme(self):
        # (0,0,10,10) ve (5,0,15,10): kesişim 50, birleşim 150 → 1/3
        self.assertAlmostEqual(sk._kutu_iou((0, 0, 10, 10),
                                            (5, 0, 15, 10)), 1 / 3, places=5)


class SifirEtkiTesti(unittest.TestCase):
    def test_model_yoksa_bos(self):
        # Gerçek ortamda model yok → _soru_modeli_bolgeleri [] döner ve
        # sayfa nesnesinde önbelleklenir (ikinci çağrı da []).
        s = SahteSayfa()
        self.assertEqual(sk._soru_modeli_bolgeleri(s), [])
        self.assertEqual(sk._soru_modeli_bolgeleri(s), [])

    def test_sutun_ayraci_bos_bolgede_bos(self):
        s = SahteSayfa()
        s._v3_soru_model_bolgeleri = []
        self.assertEqual(sk._soru_modeli_sutun_ayraclari(s), [])


class ModelBolgeTekillestirmeTesti(unittest.TestCase):
    MODEL = {"model_id": "test-model", "model_version": "test-v1"}

    def test_ic_ice_global_ve_yerel_govde_tek_soru_sayilir(self):
        bolgeler = dm.kanonik_soru_bolgeleri([
            {"sinif": "question_body", "kutu": [100, 100, 500, 700],
             "guven": .68, "olcek": "global"},
            {"sinif": "question_body", "kutu": [130, 120, 470, 190],
             "guven": .59, "olcek": "yerel_1"},
        ], (1000, 1400), self.MODEL)

        govdeler = [b for b in bolgeler if b["sinif"] == "question_body"]
        self.assertEqual(1, len(govdeler))
        self.assertEqual([100.0, 100.0, 500.0, 700.0],
                         govdeler[0]["kutu"])

    def test_ayrik_iki_govde_iki_soru_olarak_kalir(self):
        bolgeler = dm.kanonik_soru_bolgeleri([
            {"sinif": "question_body", "kutu": [100, 100, 450, 500],
             "guven": .80, "olcek": "global"},
            {"sinif": "question_body", "kutu": [100, 650, 450, 1050],
             "guven": .76, "olcek": "global"},
        ], (1000, 1400), self.MODEL)

        self.assertEqual(
            2, sum(b["sinif"] == "question_body" for b in bolgeler))

    def test_global_toplayici_iki_ayrik_yerel_govdeyi_tek_soruya_indirmez(
            self):
        bolgeler = dm.kanonik_soru_bolgeleri([
            {"sinif": "question_body", "kutu": [100, 100, 500, 1000],
             "guven": .90, "olcek": "global"},
            {"sinif": "question_body", "kutu": [120, 120, 480, 450],
             "guven": .80, "olcek": "yerel_1"},
            {"sinif": "question_body", "kutu": [120, 550, 480, 900],
             "guven": .78, "olcek": "yerel_2"},
            {"sinif": "question_anchor", "kutu": [125, 105, 160, 140],
             "guven": .92, "olcek": "yerel_1"},
            {"sinif": "question_anchor", "kutu": [125, 535, 160, 570],
             "guven": .89, "olcek": "yerel_2"},
        ], (1000, 1400), self.MODEL)

        govdeler = [b for b in bolgeler if b["sinif"] == "question_body"]
        self.assertEqual(3, len(govdeler))
        parent = next(
            b for b in govdeler if b.get("iliski") == "aggregate_parent")
        yapraklar = [
            b for b in govdeler if b.get("iliski") == "instance_leaf"]
        self.assertEqual([100.0, 100.0, 500.0, 1000.0],
                         parent["kutu"])
        self.assertEqual(
            [[120.0, 120.0, 480.0, 450.0],
             [120.0, 550.0, 480.0, 900.0]],
            [b["kutu"] for b in yapraklar])
        self.assertEqual([b["id"] for b in yapraklar],
                         parent["child_ids"])
        self.assertTrue(all(b["parent_id"] == parent["id"]
                            for b in yapraklar))

        gorunumler = dm._soru_model_gorunumleri(bolgeler)
        layout_body_ids = {
            b["id"] for b in gorunumler["layout_view"]
            if b["sinif"] == "question_body"}
        instance_body_ids = {
            b["id"] for b in gorunumler["instance_view"]
            if b["sinif"] == "question_body"}
        self.assertEqual({parent["id"]}, layout_body_ids)
        self.assertEqual({b["id"] for b in yapraklar}, instance_body_ids)
        self.assertFalse(layout_body_ids & instance_body_ids)

    def test_iki_ayrik_yerel_parca_capa_sayisindan_bagimsiz_korunur(self):
        ortak = [
            {"sinif": "question_body", "kutu": [100, 100, 500, 1000],
             "guven": .90, "olcek": "global"},
            {"sinif": "question_body", "kutu": [120, 120, 480, 450],
             "guven": .80, "olcek": "yerel_1"},
            {"sinif": "question_body", "kutu": [120, 550, 480, 900],
             "guven": .78, "olcek": "yerel_2"},
        ]
        tek_capa = {
            "sinif": "question_anchor", "kutu": [125, 105, 160, 140],
            "guven": .92, "olcek": "yerel_1",
        }
        for capalar in ([], [tek_capa]):
            with self.subTest(capa_sayisi=len(capalar)):
                bolgeler = dm.kanonik_soru_bolgeleri(
                    ortak + capalar, (1000, 1400), self.MODEL)
                govdeler = [
                    b for b in bolgeler if b["sinif"] == "question_body"]
                self.assertEqual(3, len(govdeler))
                self.assertEqual(
                    1, sum(b.get("iliski") == "aggregate_parent"
                           for b in govdeler))
                self.assertEqual(
                    2, sum(b.get("iliski") == "instance_leaf"
                           for b in govdeler))

    def test_soguk_ve_cache_hiyerarsi_ve_gorunumleri_ayni_verir(self):
        from PIL import Image

        ham = [
            {"sinif": "question_anchor", "kutu": [50, 50, 90, 90],
             "guven": .70, "olcek": "global"},
            {"sinif": "question_body", "kutu": [100, 100, 500, 1000],
             "guven": .90, "olcek": "global"},
            {"sinif": "question_body", "kutu": [120, 120, 480, 450],
             "guven": .80, "olcek": "yerel_1"},
            {"sinif": "question_body", "kutu": [120, 550, 480, 900],
             "guven": .78, "olcek": "yerel_2"},
        ]
        cache = {}

        def cache_yaz(anahtar, bolgeler, _model_id):
            # Eski/haricen düzenlenmiş cache sıra ve ilişki metadata'sını
            # bozsa bile okuma yolu kanonik sonucu yeniden üretmelidir.
            cache[anahtar] = copy.deepcopy(list(reversed(bolgeler)))
            for bolge in cache[anahtar]:
                bolge["iliski"] = "stale"
                bolge["parent_id"] = "stale-parent"
                bolge["child_ids"] = ["stale-child"]

        with tempfile.TemporaryDirectory() as gecici, \
                mock.patch.object(dm, "SORU_MODEL_CACHE_DIZIN", gecici), \
                mock.patch.object(dm, "soru_modeli_kullanilabilir",
                                  return_value=True), \
                mock.patch.object(dm, "_soru_model_kimlik_bilgiden",
                                  return_value="test-key"), \
                mock.patch.object(dm, "_soru_cache_oku",
                                  side_effect=lambda key, _model_id=None:
                                  cache.get(key)), \
                mock.patch.object(dm, "_soru_cache_yaz",
                                  side_effect=cache_yaz), \
                mock.patch.object(dm, "_soru_istek", return_value={
                    "bolgeler": ham,
                    "model_bilgisi": self.MODEL,
                    "model_sha256": "a" * 64,
                }), \
                mock.patch.object(dm, "_soru_model_bilgisi",
                                  return_value=self.MODEL):
            gorsel = Image.new("RGB", (1000, 1400), "white")
            soguk = dm.soru_bolgeleri_gorsel(gorsel, "sayfa-1")
            soguk_gorunumler = dm._soru_model_gorunumleri(soguk)
            isabet = dm.soru_bolgeleri_gorsel(gorsel, "sayfa-1")
            isabet_gorunumler = dm._soru_model_gorunumleri(isabet)

        self.assertEqual(soguk, isabet)
        self.assertEqual(soguk_gorunumler, isabet_gorunumler)
        self.assertEqual(
            [(50.0, 50.0), (100.0, 100.0), (120.0, 120.0),
             (550.0, 120.0)],
            [(b["kutu"][1], b["kutu"][0]) for b in isabet])
        parent = next(
            b for b in isabet if b.get("iliski") == "aggregate_parent")
        yapraklar = [
            b for b in isabet if b.get("iliski") == "instance_leaf"]
        self.assertEqual([b["id"] for b in yapraklar],
                         parent["child_ids"])

    def test_parcali_ust_uste_govdeler_birlesme_kaniti_degil(self):
        parcali = [
            {"kutu": (40, 400, 240, 455), "guven": .71},
            {"kutu": (36, 412, 238, 695), "guven": .61},
        ]
        ayri = [
            {"kutu": (40, 100, 240, 300), "guven": .80},
            {"kutu": (40, 380, 240, 600), "guven": .76},
        ]
        self.assertFalse(sk._model_bolgeleri_ayrik_mi(
            parcali, 600.0, 800.0))
        self.assertTrue(sk._model_bolgeleri_ayrik_mi(
            ayri, 600.0, 800.0))

    def test_model_kapsanmasi_yonludur(self):
        model = (39, 400, 238, 452)
        mevcut = (32, 397, 269, 701)
        self.assertGreaterEqual(
            sk._kutu_kapsanma_orani(model, mevcut), .70)
        self.assertLess(
            sk._kutu_kapsanma_orani(mevcut, model), .70)


class SahteBolgeTesti(unittest.TestCase):
    """Sayfa nesnesine doğrudan sahte bölge yerleştirip yardımcıları test
    eder (duzen_model'e dokunmadan; önbellek alanı zaten okunuyor)."""

    def test_sutun_ayraci_iki_kume(self):
        s = SahteSayfa(genislik=1000.0, yukseklik=1400.0)
        # sol sütun (~x 100-400) ve sağ sütun (~x 600-900) body kutuları
        s._v3_soru_model_bolgeleri = [
            {"sinif": "question_body", "kutu": (100, y, 400, y + 80),
             "guven": 0.8} for y in (100, 300, 500)
        ] + [
            {"sinif": "question_body", "kutu": (600, y, 900, y + 80),
             "guven": 0.8} for y in (100, 300, 500)
        ]
        ayraclar = sk._soru_modeli_sutun_ayraclari(s)
        self.assertEqual(len(ayraclar), 1)
        self.assertTrue(400 <= ayraclar[0] <= 600)

    def test_dusuk_guven_elenir(self):
        s = SahteSayfa()
        s._v3_soru_model_bolgeleri = [
            {"sinif": "question_body", "kutu": (100, y, 400, y + 80),
             "guven": 0.2} for y in (100, 300, 500)]
        self.assertEqual(sk._soru_modeli_sutun_ayraclari(s), [])

    def test_guttera_clamplenen_ince_model_seridi_soru_olamaz(self):
        s = SahteSayfa(genislik=1000.0, yukseklik=1400.0)
        s._v3_soru_model_bolgeleri = [{
            "sinif": "question_body", "kutu": (470, 100, 500, 520),
            "guven": 0.9,
        }]
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (472, 110, 498, 140), False),
            *[(f"{h}) seçenek", (472, 180 + i * 45, 498,
                                  210 + i * 45), False)
              for i, h in enumerate("ABCDE")],
        ]
        sonuc = sk._soru_modeli_yedegi_uygula(
            s, satirlar, [], [(0.0, 500.0), (500.0, 1000.0)],
            "coktan_secmeli")
        self.assertEqual([], sonuc)

    def test_kucuk_mevcut_parca_tam_model_kurtarmasini_bastirmaz(self):
        s = SahteSayfa(genislik=600.0, yukseklik=1000.0)
        s._v3_soru_model_bolgeleri = [{
            "sinif": "question_body", "kutu": (40, 55, 540, 560),
            "guven": 0.88,
        }]
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (50, 70, 500, 95), False),
            *[(f"{h}) Seçenek", (60, 260 + i * 48, 260,
                                  285 + i * 48), False)
              for i, h in enumerate("ABCDE")],
        ]
        kucuk = sk.SoruKutu(
            (50, 65, 190, 125), 0, 1, False, frozenset(),
            "1. Aşağıdakilerden hangisi doğrudur?", True,
            numara_kutu=(50, 70, 500, 95))

        sonuc = sk._soru_modeli_yedegi_uygula(
            s, satirlar, [kucuk], [(0.0, 600.0)], "coktan_secmeli")

        self.assertEqual(2, len(sonuc))
        self.assertEqual((40, 55, 540, 560), sonuc[1].kutu)
        self.assertIn("soru_modeli_kurtardi", sonuc[1].risk_nedenleri)

    def test_iki_guclu_govde_tek_anchor_ile_de_birlesme_riskidir(self):
        s = SahteSayfa(genislik=600.0, yukseklik=1000.0)
        s._v3_soru_model_bolgeleri = [
            {"sinif": "question_body", "kutu": (45, 80, 520, 380),
             "guven": 0.82},
            {"sinif": "question_body", "kutu": (45, 500, 520, 850),
             "guven": 0.79},
            {"sinif": "question_anchor", "kutu": (48, 65, 85, 95),
             "guven": 0.91},
            # Şekil/metin içindeki girintili sahte anchor birleşme kanıtı
            # olamaz.
            {"sinif": "question_anchor", "kutu": (100, 500, 260, 530),
             "guven": 0.87},
        ]
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (50, 70, 500, 95), False),
            *[(f"{h}) Seçenek", (60, 700 + i * 35, 220,
                                  725 + i * 35), False)
              for i, h in enumerate("ABCDE")],
        ]
        aday = sk.SoruKutu(
            (40, 60, 530, 900), 0, 1, False, frozenset("ABCDE"),
            "E) Seçenek", True, numara_kutu=(50, 70, 500, 95))
        sonuc = sk._adaylari_zenginlestir(
            s, satirlar, [aday], "coktan_secmeli")[0]
        self.assertIn("soru_modeli_birlesme_riski",
                      sonuc.risk_nedenleri)

    def test_zayif_iki_govde_tek_anchor_ile_sert_risk_degildir(self):
        s = SahteSayfa(genislik=600.0, yukseklik=1000.0)
        s._v3_soru_model_bolgeleri = [
            {"sinif": "question_body", "kutu": (45, 80, 520, 380),
             "guven": 0.68},
            {"sinif": "question_body", "kutu": (45, 500, 520, 850),
             "guven": 0.66},
            {"sinif": "question_anchor", "kutu": (48, 65, 85, 95),
             "guven": 0.91},
        ]
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (50, 70, 500, 95), False),
            *[(f"{h}) Seçenek", (60, 700 + i * 35, 220,
                                  725 + i * 35), False)
              for i, h in enumerate("ABCDE")],
        ]
        aday = sk.SoruKutu(
            (40, 60, 530, 900), 0, 1, False, frozenset("ABCDE"),
            "E) Seçenek", True, numara_kutu=(50, 70, 500, 95))
        sonuc = sk._adaylari_zenginlestir(
            s, satirlar, [aday], "coktan_secmeli")[0]
        self.assertNotIn("soru_modeli_birlesme_riski",
                         sonuc.risk_nedenleri)

    def test_iki_govde_iki_anchor_birlesme_riskini_korur(self):
        s = SahteSayfa(genislik=600.0, yukseklik=1000.0)
        s._v3_soru_model_bolgeleri = [
            {"sinif": "question_body", "kutu": (45, 80, 520, 380),
             "guven": 0.82},
            {"sinif": "question_body", "kutu": (45, 500, 520, 850),
             "guven": 0.79},
            {"sinif": "question_anchor", "kutu": (48, 65, 85, 95),
             "guven": 0.91},
            {"sinif": "question_anchor", "kutu": (48, 500, 85, 530),
             "guven": 0.88},
        ]
        satirlar = [
            ("1. Aşağıdakilerden hangisi doğrudur?",
             (50, 70, 500, 95), False),
            *[(f"{h}) Seçenek", (60, 700 + i * 35, 220,
                                  725 + i * 35), False)
              for i, h in enumerate("ABCDE")],
        ]
        aday = sk.SoruKutu(
            (40, 60, 530, 900), 0, 1, False, frozenset("ABCDE"),
            "E) Seçenek", True, numara_kutu=(50, 70, 500, 95))
        sonuc = sk._adaylari_zenginlestir(
            s, satirlar, [aday], "coktan_secmeli")[0]
        self.assertIn("soru_modeli_birlesme_riski",
                      sonuc.risk_nedenleri)


if __name__ == "__main__":
    unittest.main()
