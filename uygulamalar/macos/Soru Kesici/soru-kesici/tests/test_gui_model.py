#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""KutuModeli / GeriAlYigini birim testleri (tkinter penceresi gerekmez).

Editörün model katmanı web DURUM sözleşmesinin süreç-içi eşleniğidir;
buradaki kurallar (clamp, min 8×8 eleme, sütun-y sıralaması, kutu_atama,
reddedilmiş→incele terfisi) kesim doğruluğunun temelidir.
"""

import unittest

from gui_kutu_editor import KutuModeli, GeriAlYigini, _aday_ayikla


class SahteSayfa:
    def __init__(self, genislik=600.0, yukseklik=800.0):
        self.genislik = genislik
        self.yukseklik = yukseklik


class SahteAnaliz:
    def __init__(self, adaylar):
        self.adaylar = adaylar


def _aday(kutu, guven=0.9, durum="otomatik", devam=False, numara=None):
    return {"kutu": list(kutu), "guven": guven, "kalibre_guven": guven,
            "inceleme_durumu": durum, "devam_aday": devam,
            "numara": numara, "kanitlar": [], "uyarilar": []}


def _model(analizler=None, sutun_xler=(0.0, 300.0)):
    m = KutuModeli()
    m.belge_ata([SahteSayfa(), SahteSayfa()], "karisik",
                list(sutun_xler), analizler)
    return m


class AdayAyiklaTesti(unittest.TestCase):
    def test_devam_aday_elenir(self):
        self.assertIsNone(_aday_ayikla(_aday((0, 0, 50, 50), devam=True)))

    def test_gecersiz_durum_otomatige_duser(self):
        _, meta = _aday_ayikla(_aday((0, 0, 50, 50), durum="tuhaf"))
        self.assertEqual(meta["inceleme_durumu"], "otomatik")

    def test_guven_kalibre_guvenden_ve_kirpilir(self):
        aday = _aday((0, 0, 50, 50))
        aday["kalibre_guven"] = 1.7
        _, meta = _aday_ayikla(aday)
        self.assertEqual(meta["guven"], 1.0)


class KutuModeliTesti(unittest.TestCase):
    def test_belge_ata_doldurur(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100)),
                                 _aday((10, 120, 100, 200), devam=True)]),
                    SahteAnaliz([])])
        self.assertTrue(m.analiz_var)
        self.assertEqual(len(m.kutular(0)), 1)   # devam adayı elendi
        self.assertEqual(m.kutular(1), [])
        self.assertEqual(m.toplam_soru(), 1)

    def test_degistir_clamp_ve_min_eleme(self):
        m = _model([SahteAnaliz([]), SahteAnaliz([])])
        yeni = m.kutulari_degistir(0, [
            ((-20.0, -5.0, 100.0, 900.0), None, True),   # taşan: kırpılır
            ((10.0, 10.0, 14.0, 300.0), None, True),     # 4 px en: elenir
        ])
        self.assertEqual(yeni, [(0.0, 0.0, 100.0, 800.0)])

    def test_degistir_ters_koseler_duzeltilir(self):
        m = _model([SahteAnaliz([]), SahteAnaliz([])])
        yeni = m.kutulari_degistir(0, [((100.0, 200.0, 20.0, 40.0),
                                        None, True)])
        self.assertEqual(yeni, [(20.0, 40.0, 100.0, 200.0)])

    def test_sutun_y_siralamasi(self):
        # sütunlar x=0 ve x=300'de: sağ-üst kutu, sol-alt kutudan SONRA gelir
        m = _model([SahteAnaliz([]), SahteAnaliz([])])
        yeni = m.kutulari_degistir(0, [
            ((310.0, 10.0, 500.0, 100.0), None, True),   # sağ sütun, üst
            ((10.0, 400.0, 200.0, 500.0), None, True),   # sol sütun, alt
            ((10.0, 10.0, 200.0, 100.0), None, True),    # sol sütun, üst
        ])
        self.assertEqual(yeni, [(10.0, 10.0, 200.0, 100.0),
                                (10.0, 400.0, 200.0, 500.0),
                                (310.0, 10.0, 500.0, 100.0)])

    def test_yeni_kutu_meta_ve_duzeltme_kaniti(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100))]),
                    SahteAnaliz([])])
        eski_meta = m.metalar(0)[0]
        m.kutulari_degistir(0, [
            ((10.0, 10.0, 100.0, 100.0), eski_meta, False),
            ((10.0, 300.0, 100.0, 400.0), None, True)])
        metalar = m.metalar(0)
        self.assertEqual(metalar[0].get("kanitlar"), [])  # dokunulmadı
        self.assertEqual(metalar[1]["inceleme_durumu"], "incele")
        self.assertIn("kullanici_ekledi", metalar[1]["kanitlar"])

    def test_degisen_kutu_kaniti_ve_reddedilmis_terfisi(self):
        m = _model([SahteAnaliz([
            _aday((10, 10, 100, 100), durum="reddedildi")]), SahteAnaliz([])])
        meta = m.metalar(0)[0]
        m.kutulari_degistir(0, [((10.0, 10.0, 120.0, 100.0), meta, True)])
        yeni_meta = m.metalar(0)[0]
        self.assertIn("kullanici_duzeltmesi", yeni_meta["kanitlar"])
        self.assertEqual(yeni_meta["inceleme_durumu"], "incele")

    def test_kutu_atama_yalniz_duzenlenen_sayfalar(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100))]),
                    SahteAnaliz([_aday((10, 10, 100, 100))])])
        self.assertIsNone(m.kutu_atama())        # düzenleme yok
        m.kutulari_degistir(1, [((10.0, 10.0, 100.0, 150.0), None, True)])
        atama = m.kutu_atama()
        self.assertEqual(sorted(atama), [1])
        self.assertEqual(atama[1], [(10.0, 10.0, 100.0, 150.0)])

    def test_ayni_plan_duzenlendi_saymaz(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100))]),
                    SahteAnaliz([])])
        ogeler = [(k, None, False) for k in m.kutular(0)]
        m.kutulari_degistir(0, ogeler)
        self.assertIsNone(m.kutu_atama())

    def test_sifirla(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100))]),
                    SahteAnaliz([])])
        m.kutulari_degistir(0, [((10.0, 10.0, 100.0, 150.0), None, True)])
        self.assertIsNotNone(m.kutu_atama())
        m.sifirla(0)
        self.assertIsNone(m.kutu_atama())
        self.assertNotIn(0, m.kutu_onbellek)

    def test_anlik_yukle_geri_getirir(self):
        m = _model([SahteAnaliz([_aday((10, 10, 100, 100))]),
                    SahteAnaliz([])])
        once = m.anlik(0)
        m.kutulari_degistir(0, [((20.0, 20.0, 90.0, 90.0), None, True)])
        m.anlik_yukle(0, once)
        self.assertEqual(m.kutular(0), [(10.0, 10.0, 100.0, 100.0)])
        self.assertIsNone(m.kutu_atama())


class GeriAlYiginiTesti(unittest.TestCase):
    def test_geri_al_yinele_akisi(self):
        y = GeriAlYigini(sinir=3)
        y.push(0, "a0", "a1")
        y.push(1, "b0", "b1")
        self.assertEqual(y.geri_al(), (1, "b0"))
        self.assertEqual(y.yinele(), (1, "b1"))
        self.assertEqual(y.geri_al(), (1, "b0"))
        self.assertEqual(y.geri_al(), (0, "a0"))
        self.assertIsNone(y.geri_al())

    def test_yeni_push_yineleyi_temizler(self):
        y = GeriAlYigini()
        y.push(0, "a0", "a1")
        y.geri_al()
        y.push(0, "c0", "c1")
        self.assertIsNone(y.yinele())

    def test_sinir(self):
        y = GeriAlYigini(sinir=2)
        for i in range(5):
            y.push(i, f"o{i}", f"s{i}")
        self.assertEqual(y.geri_al()[0], 4)
        self.assertEqual(y.geri_al()[0], 3)
        self.assertIsNone(y.geri_al())


if __name__ == "__main__":
    unittest.main()
