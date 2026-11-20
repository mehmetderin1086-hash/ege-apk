#!/usr/bin/env python3
"""araclar/kabul_karsilastir.py sınaması (P3.10-kabul). Telefona, ağa ya da Xcode'a dokunmaz.
    /usr/bin/python3 -I araclar/testler/test_kabul_karsilastir.py
Fikstürler geçici dizine yazılır.
"""

import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

# -I çalışma dizinini sys.path'ten çıkarır: araclar/ elle eklenir.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import kabul_karsilastir as kk  # noqa: E402


class KabulKarsilastirTestleri(unittest.TestCase):
    def setUp(self):
        self._gecici = tempfile.TemporaryDirectory(prefix="kabul-test-")
        self.kok = Path(self._gecici.name)
        self.onceki = self.kok / "20261020-1000"
        self.yeni = self.kok / "20261020-1100"
        self.onceki.mkdir()
        self.yeni.mkdir()

    def tearDown(self):
        self._gecici.cleanup()

    def yaz(self, dizin, ad, nesne):
        (dizin / ("asistan-" + ad + ".json")).write_text(json.dumps(nesne, ensure_ascii=False), encoding="utf-8")

    def kos(self, onceki=None):
        cikti = io.StringIO()
        kod = kk.calistir(str(self.onceki) if onceki is None else onceki, str(self.yeni), cikis=cikti)
        return kod, cikti.getvalue()

    def hiz(self, ilk, toplam=2.0, bitti=True):
        return {"tamamlandi": True, "kosu": "x", "kosuBitti": True, "surum": "t",
                "turlar": [{"ad": "otomatik-selam", "ilkSn": ilk, "toplamSn": toplam, "bitti": bitti, "hata": ""}]}

    # Süre kuralı

    def test_yuzde_yirmi_besten_fazla_gerileme_sayilir(self):
        self.yaz(self.onceki, "hiz-kabul", self.hiz(1.0))
        self.yaz(self.yeni, "hiz-kabul", self.hiz(1.25))
        kod, cikti = self.kos()
        self.assertEqual(kod, 1, cikti)
        self.assertIn("GERİLEME", cikti)
        self.assertIn("turlar[ad=otomatik-selam].ilkSn", cikti)

    def test_yuzde_onbes_gerileme_sayilmaz(self):
        self.yaz(self.onceki, "hiz-kabul", self.hiz(1.0))
        self.yaz(self.yeni, "hiz-kabul", self.hiz(1.15))
        kod, cikti = self.kos()
        self.assertEqual(kod, 0, cikti)
        self.assertNotIn("GERİLEME", cikti)

    def test_mutlak_esik_altindaki_artis_sayilmaz(self):
        self.yaz(self.onceki, "hiz-kabul", self.hiz(0.10))
        self.yaz(self.yeni, "hiz-kabul", self.hiz(0.20))
        kod, cikti = self.kos()
        self.assertEqual(kod, 0, cikti)

    def test_milisaniye_esigi(self):
        self.yaz(self.onceki, "ses-akis-sinama", {"sonUretimMs": 500, "hata": ""})
        self.yaz(self.yeni, "ses-akis-sinama", {"sonUretimMs": 650, "hata": ""})
        self.assertEqual(self.kos()[0], 0, "%30 ama 150 ms < 200 ms mutlak eşik")
        self.yaz(self.yeni, "ses-akis-sinama", {"sonUretimMs": 800, "hata": ""})
        self.assertEqual(self.kos()[0], 1, "%60 ve 300 ms")

    def test_olculmedi_degeri_karsilastirilmaz(self):
        self.yaz(self.onceki, "ses-akis-sinama", {"ilkSesSn": -1, "hata": ""})
        self.yaz(self.yeni, "ses-akis-sinama", {"ilkSesSn": 3.0, "hata": ""})
        self.assertEqual(self.kos()[0], 0)

    # Boolean ve hata

    def test_boolean_true_false_gerileme(self):
        self.yaz(self.onceki, "arsiv-sinama", {"tamamlandi": True, "zipIcerikDogru": True})
        self.yaz(self.yeni, "arsiv-sinama", {"tamamlandi": True, "zipIcerikDogru": False})
        kod, cikti = self.kos()
        self.assertEqual(kod, 1, cikti)
        self.assertIn("zipIcerikDogru", cikti)

    def test_ic_ice_bitti_false_gerileme(self):
        self.yaz(self.onceki, "hiz-kabul", self.hiz(1.0, bitti=True))
        self.yaz(self.yeni, "hiz-kabul", self.hiz(1.0, bitti=False))
        self.assertEqual(self.kos()[0], 1)

    def test_hata_dolu_basarisiz(self):
        self.yaz(self.yeni, "ofis-sinama", {"tamamlandi": False, "hata": "DOCX yazılamadı"})
        kod, cikti = self.kos()
        self.assertEqual(kod, 1)
        self.assertIn("DOCX yazılamadı", cikti)

    def test_ic_ice_hata_bos_dan_doluya_gerileme(self):
        onceki, yeni = self.hiz(1.0), self.hiz(1.0)
        yeni["turlar"][0]["hata"] = "429"
        self.yaz(self.onceki, "hiz-kabul", onceki)
        self.yaz(self.yeni, "hiz-kabul", yeni)
        self.assertEqual(self.kos()[0], 1)

    def test_ic_ice_bitmemis_tur_ust_duzey_tamamlandi_olsa_da_basarisiz(self):
        self.yaz(self.yeni, "hiz-kabul", self.hiz(1.0, bitti=False))
        kod, cikti = self.kos(onceki="-")
        self.assertEqual(kod, 1, cikti)
        self.assertIn("bitmedi: turlar[ad=otomatik-selam].bitti", cikti)

    def test_ic_ice_dolu_hata_onceki_tur_olmadan_da_basarisiz(self):
        yeni = self.hiz(1.0)
        yeni["turlar"][0]["hata"] = "429"
        self.yaz(self.yeni, "hiz-kabul", yeni)
        kod, cikti = self.kos(onceki="-")
        self.assertEqual(kod, 1, cikti)
        self.assertIn("iç hata", cikti)

    def test_ic_ice_temiz_tur_gecer(self):
        self.yaz(self.yeni, "hiz-kabul", self.hiz(1.0))
        self.assertEqual(self.kos(onceki="-")[0], 0)

    # Önceki tur

    def test_onceki_tur_yokken_temiz_tur_gecer(self):
        self.yaz(self.yeni, "ofis-sinama", {"tamamlandi": True, "hata": ""})
        self.assertEqual(self.kos(onceki="-")[0], 0)
        self.assertEqual(self.kos(onceki="")[0], 0)
        self.assertEqual(self.kos(onceki=str(self.kok / "yok"))[0], 0)

    def test_onceki_tur_yokken_basarisizlik_yine_yakalanir(self):
        self.yaz(self.yeni, "ofis-sinama", {"tamamlandi": False})
        self.assertEqual(self.kos(onceki="-")[0], 1)

    def test_yeni_metrik_ve_yeni_dosya_gerileme_sayilmaz(self):
        self.yaz(self.onceki, "ofis-sinama", {"tamamlandi": True})
        self.yaz(self.yeni, "ofis-sinama", {"tamamlandi": True, "toplamSn": 9.0})
        self.yaz(self.yeni, "arsiv-sinama", {"tamamlandi": True, "zipIcerikDogru": True})
        kod, cikti = self.kos()
        self.assertEqual(kod, 0, cikti)
        self.assertIn("yeni", cikti)

    def test_turlar_ad_ile_siradan_bagimsiz_eslenir(self):
        onceki = {"tamamlandi": True, "turlar": [{"ad": "a", "ilkSn": 1.0}, {"ad": "b", "ilkSn": 5.0}]}
        yeni = {"tamamlandi": True, "turlar": [{"ad": "b", "ilkSn": 5.0}, {"ad": "a", "ilkSn": 1.0}]}
        self.yaz(self.onceki, "hiz-kabul", onceki)
        self.yaz(self.yeni, "hiz-kabul", yeni)
        kod, cikti = self.kos()
        self.assertEqual(kod, 0, cikti)
        duz = kk.duzlestir(yeni)
        self.assertEqual(duz["turlar[ad=a].ilkSn"], 1.0)
        self.assertEqual(duz["turlar[ad=b].ilkSn"], 5.0)

    def test_kimliksiz_dizi_indeksle_eslenir_ve_tekrarlar_ayrilir(self):
        duz = kk.duzlestir({"s": [{"x": 1}, {"ad": "a", "x": 2}, {"ad": "a", "x": 3}]})
        self.assertEqual(duz["s[0].x"], 1)
        self.assertEqual(duz["s[ad=a].x"], 2)
        self.assertEqual(duz["s[ad=a#2].x"], 3)

    # Biçimler ve dışlananlar

    def test_sinama_bicimi_asama_tamamlandi_basarili(self):
        self.yaz(self.yeni, "sinama", {"asama": "tamamlandi", "zamanAsimi": False, "hata": "", "sureSaniye": 20})
        self.assertEqual(self.kos(onceki="-")[0], 0)

    def test_sinama_bicimi_zaman_asimi_basarisiz(self):
        self.yaz(self.yeni, "sinama", {"asama": "tamamlandi", "zamanAsimi": True, "hata": ""})
        self.assertEqual(self.kos(onceki="-")[0], 1)

    def test_sinama_bicimi_ara_asama_basarisiz(self):
        self.yaz(self.yeni, "sinama", {"asama": "baglanti_hatasi"})
        self.assertEqual(self.kos(onceki="-")[0], 1)

    def test_betik_zaman_asimi_isareti_basarisiz(self):
        self.yaz(self.yeni, "hiz-kabul", {"kabulZamanAsimi": True, "kabulKosu": "x"})
        kod, cikti = self.kos(onceki="-")
        self.assertEqual(kod, 1)
        self.assertIn("zaman aşımı", cikti)

    def test_kosu_surum_zaman_karsilastirilmaz(self):
        self.yaz(self.onceki, "sinama", {"asama": "tamamlandi", "zaman": "a", "kosu": "1", "surum": "x", "kosuBitti": True})
        self.yaz(self.yeni, "sinama", {"asama": "tamamlandi", "zaman": "b", "kosu": "2", "surum": "y", "kosuBitti": True})
        kod, cikti = self.kos()
        self.assertEqual(kod, 0, cikti)
        self.assertNotIn("kosuBitti", cikti)

    # Altyapı

    def test_bozuk_json_altyapi_kodu(self):
        (self.yeni / "asistan-hiz-kabul.json").write_text("{bozuk", encoding="utf-8")
        kod, cikti = self.kos()
        self.assertEqual(kod, 2)
        self.assertIn("Altyapı", cikti)

    def test_rapor_yoksa_altyapi_kodu(self):
        self.assertEqual(self.kos()[0], 2)

    def test_yeni_tur_dizini_yoksa_altyapi_kodu(self):
        self.assertEqual(kk.calistir("-", str(self.kok / "yok"), cikis=io.StringIO()), 2)

    def test_onceki_bozuk_json_karsilastirmayi_atlar(self):
        (self.onceki / "asistan-ofis-sinama.json").write_text("{", encoding="utf-8")
        self.yaz(self.yeni, "ofis-sinama", {"tamamlandi": True})
        self.assertEqual(self.kos()[0], 0)

    def test_komut_satiri_arguman_sayisi(self):
        eski_stderr = sys.stderr
        sys.stderr = io.StringIO()
        try:
            self.assertEqual(kk.main(["kabul_karsilastir.py"]), 2)
        finally:
            sys.stderr = eski_stderr


if __name__ == "__main__":
    unittest.main()
