import unittest
from unittest import mock

import soru_kes_web as web


class _Sayfa:
    genislik = 600
    yukseklik = 800
    dpi = 72
    raster = False


class _Profil:
    def to_dict(self):
        return {"algoritma_surumu": "v2-test", "duzen_aileleri": ["tek_sutun"]}


class _Aday:
    def __init__(self, kutu, guven, durum, tur="coktan_secmeli"):
        self.veri = {"kutu": kutu, "guven": guven,
                     "inceleme_durumu": durum, "soru_turu": tur,
                     "kanitlar": ["numara"], "uyarilar": []}

    def to_dict(self):
        return dict(self.veri)


class _Analiz:
    def __init__(self, adaylar, rol="soru"):
        self.adaylar = adaylar
        self.rol = rol

    def to_dict(self):
        return {"sayfa_rolu": self.rol,
                "adaylar": [a.to_dict() for a in self.adaylar]}


class WebV2Testi(unittest.TestCase):
    def setUp(self):
        self.onceki = dict(web.DURUM)
        web.DURUM.update({
            "sayfalar": [_Sayfa()], "profil": None, "analizler": [],
            "kutu_onbellek": {}, "kutu_meta": {}, "inceleme_onaylari": set(),
            "sayfa_inceleme_kararlari": {}, "sayfa_karar_yedekleri": {},
            "kalite_modu": "strict", "girdiler": ["test.pdf"],
            "kalibrasyon_hatasi": None, "duzenlendi": set(), "fmt": "karisik",
            "sutun_xler": [0.0], "ozet": None, "ozet_kirli": True,
        })

    def tearDown(self):
        web.DURUM.clear()
        web.DURUM.update(self.onceki)

    def _v2_yukle(self):
        analiz = _Analiz([
            _Aday([10, 20, 280, 220], .91, "otomatik"),
            _Aday([10, 230, 280, 430], .68, "incele", "acik_uclu"),
            _Aday([310, 20, 590, 400], .31, "reddedildi", "kisa_cevap"),
        ])
        self.assertTrue(web._v2_sonuclarini_sakla(_Profil(), [analiz]))

    def test_v2_kutular_guven_ve_durum_metasiyla_doner(self):
        self._v2_yukle()

        sonuc = web._oku_kutular(0)

        self.assertTrue(sonuc["v2"])
        self.assertEqual(3, len(sonuc["kutular"]))
        self.assertEqual(["otomatik", "incele", "reddedildi"],
                         [m["inceleme_durumu"] for m in sonuc["kutu_meta"]])
        self.assertAlmostEqual(.68, sonuc["kutu_meta"][1]["guven"])
        self.assertEqual("soru", sonuc["sayfa_rolu"])

    def test_devam_adayi_bagimsiz_kutu_olarak_gosterilmez(self):
        aday = _Aday([10, 20, 280, 220], .70, "incele")
        aday.veri["devam_aday"] = True
        web._v2_sonuclarini_sakla(_Profil(), [_Analiz([aday])])
        self.assertEqual([], web._oku_kutular(0)["kutular"])

    def test_v3_cekirdek_kimlik_ve_kalibre_alanlari_korunur(self):
        aday = _Aday([10, 20, 280, 220], .77, "incele")
        aday.veri.update({"karar_kimligi": "v3_kararli_test",
                          "kalibre_guven": .64,
                          "onay_durumu": "bekliyor",
                          "kaynak_yontemler": ["vision_ocr"],
                          "risk_nedenleri": ["yeni_duzen"]})
        web._v2_sonuclarini_sakla(_Profil(), [_Analiz([aday])])

        meta = web._kutu_metalari(0)[0]
        self.assertEqual("v3_kararli_test", meta["kararli_kimlik"])
        self.assertAlmostEqual(.64, meta["guven"])
        self.assertIn("vision_ocr", meta["kaynak_yontemler"])
        self.assertIn("yeni_duzen", meta["risk_nedenleri"])

    def test_inceleme_onayi_bekleyen_listesinden_cikarir(self):
        self._v2_yukle()
        once = web._inceleme_listesi()
        self.assertEqual(2, once["adet"])
        self.assertEqual([0], once["sayfalar"])

        cevap = web._inceleme_onayla(0, 1, True)
        sonra = web._inceleme_listesi()

        self.assertTrue(cevap["onayli"])
        self.assertEqual(1, sonra["adet"])
        self.assertTrue(web._kutu_metalari(0)[1]["onayli"])

    def test_aday_turevli_sayfa_riski_kutu_onayiyla_temizlenir(self):
        aday = _Aday([10, 20, 280, 220], .68, "incele")
        analiz = {
            "sayfa_rolu": "soru", "rol_guveni": .93,
            "duzen_guveni": .91, "inceleme_gerekli": True,
            "onay_durumu": "bekliyor",
            "risk_nedenleri": ["dusuk_aday_guveni"],
            "adaylar": [aday.to_dict()],
        }
        web._v2_sonuclarini_sakla(_Profil(), [analiz])
        self.assertEqual([0], web._inceleme_listesi()["sayfalar"])

        web._inceleme_onayla(0, 0, True)

        self.assertEqual([], web._inceleme_listesi()["sayfalar"])
        self.assertTrue(web._kalite_kapisi_raporu()["ok"])

    def test_bagimsiz_sayfa_riski_kutu_onayindan_sonra_kalir(self):
        aday = _Aday([10, 20, 280, 220], .68, "incele")
        analiz = {
            "sayfa_rolu": "soru", "rol_guveni": .93,
            "duzen_guveni": .91, "inceleme_gerekli": True,
            "onay_durumu": "bekliyor",
            "risk_nedenleri": ["dusuk_aday_guveni", "yeni_duzen"],
            "adaylar": [aday.to_dict()],
        }
        web._v2_sonuclarini_sakla(_Profil(), [analiz])

        web._inceleme_onayla(0, 0, True)

        kayit = web._inceleme_listesi()["sayfa_kayitlari"][0]
        self.assertIn("yeni_duzen", kayit["risk_nedenleri"])
        self.assertFalse(web._kalite_kapisi_raporu()["ok"])

    def test_reddedilen_aday_onay_yerine_elle_duzeltme_ister(self):
        self._v2_yukle()
        with self.assertRaisesRegex(ValueError, "elle düzeltin"):
            web._inceleme_onayla(0, 2, True)

    def test_banka_kapisi_onaysiz_incele_ve_reddedileni_eler(self):
        self._v2_yukle()
        web.DURUM.update({
            "ozet_kirli": False,
            "ozet": {"kimlik_liste": ["oto", "incele", "red"],
                     "kimlik_parca": {"oto": [[0, 0]], "incele": [[0, 1]],
                                       "red": [[0, 2]]}},
        })

        secim, atlanan = web._bankaya_secim_filtresi(None)
        self.assertEqual(["oto"], secim)
        self.assertEqual(2, atlanan)

        web._inceleme_onayla(0, 1, True)
        secim, atlanan = web._bankaya_secim_filtresi(None)
        self.assertEqual(["oto", "incele"], secim)
        self.assertEqual(1, atlanan)

    def test_v2_hatasi_legacy_motoru_engellemez(self):
        web.DURUM.update({"girdiler": ["kitap.pdf"]})
        with mock.patch.object(web.sk, "belge_analiz_et",
                               side_effect=RuntimeError("model yok"), create=True):
            self.assertFalse(web._v2_analiz_et())

        self.assertEqual([], web.DURUM["analizler"])
        self.assertIn("model yok", web.DURUM["kalibrasyon_hatasi"])

    def test_kullanici_duzeltmesi_ayni_duzen_ailesine_yayilir(self):
        web.DURUM.update({
            "sayfalar": [_Sayfa(), _Sayfa(), _Sayfa()],
            "profil": {},
            "analizler": [
                {"duzen_ailesi": "2_sutun"},
                {"duzen_ailesi": "2_sutun"},
                {"duzen_ailesi": "1_sutun"},
            ],
            "kutu_onbellek": {
                0: [(20, 20, 280, 200), (320, 20, 580, 200)],
                1: [(0, 30, 350, 210), (250, 30, 600, 210)],
                2: [(0, 30, 600, 210)],
            },
            "kutu_meta": {1: [
                {"kanitlar": ["numara"]}, {"kanitlar": ["numara"]}
            ]},
            "duzenlendi": {0},
        })
        yayilan = web._profil_duzeltmesini_yay(
            0, [(20, 20, 280, 200), (320, 20, 580, 200)])
        self.assertEqual(1, yayilan)
        self.assertEqual((20, 30, 280, 210),
                         web.DURUM["kutu_onbellek"][1][0])
        self.assertEqual((320, 30, 580, 210),
                         web.DURUM["kutu_onbellek"][1][1])
        self.assertIn("2_sutun",
                      web.DURUM["profil"]["kullanici_duzeltmeleri"])
        self.assertIn("kullanici_duzen_kumesi",
                      web.DURUM["kutu_meta"][1][0]["kanitlar"])
        self.assertEqual("incele",
                         web.DURUM["kutu_meta"][1][0]["inceleme_durumu"])
        self.assertIn("benzer_sayfaya_yayilim_onay_bekliyor",
                      web.DURUM["kutu_meta"][1][0]["uyarilar"])

    def test_snapshot_yalniz_degisen_ve_eklenen_kutuyu_onaylar(self):
        self._v2_yukle()
        once = web._kutu_metalari(0)

        web.kutulari_guncelle(0, [
            {"kutu": [10, 20, 280, 220],
             "kararli_kimlik": once[0]["kararli_kimlik"]},
            {"kutu": [14, 230, 284, 430],
             "kararli_kimlik": once[1]["kararli_kimlik"]},
            {"kutu": [10, 450, 280, 650]},
        ])

        sonra = web._kutu_metalari(0)
        self.assertEqual(3, len(sonra))
        self.assertAlmostEqual(.91, sonra[0]["guven"])
        self.assertFalse(sonra[0]["onayli"])
        self.assertEqual(once[0]["kararli_kimlik"],
                         sonra[0]["kararli_kimlik"])
        self.assertAlmostEqual(.68, sonra[1]["guven"])
        self.assertTrue(sonra[1]["onayli"])
        self.assertIn("kullanici_duzeltmesi", sonra[1]["kanitlar"])
        self.assertEqual(0.0, sonra[2]["guven"])
        self.assertTrue(sonra[2]["onayli"])
        self.assertEqual("incele", sonra[2]["inceleme_durumu"])

    def test_sifir_adayli_riskli_sayfa_kuyrukta_ve_katida_engellidir(self):
        analiz = {"sayfa_rolu": "soru", "rol_guveni": .93,
                  "duzen_guveni": .91, "adaylar": [],
                  "uyarilar": ["soru_sayfasinda_aday_yok"]}
        web._v2_sonuclarini_sakla(_Profil(), [analiz])

        inceleme = web._inceleme_listesi()
        self.assertEqual([], inceleme["adaylar"])
        self.assertEqual([0], inceleme["sayfalar"])
        self.assertEqual(1, inceleme["bekleyen_sayfa"])
        self.assertIn("soru_sinyali_var_aday_yok",
                      inceleme["sayfa_kayitlari"][0]["risk_nedenleri"])
        self.assertFalse(web._kalite_kapisi_raporu()["ok"])

        web._sayfa_inceleme_karari(0, "onayli")
        self.assertEqual([], web._inceleme_listesi()["sayfalar"])
        self.assertTrue(web._kalite_kapisi_raporu()["ok"])

    def test_sayfa_riski_rol_duzen_egiklik_gecis_ood_ve_hatayi_aciklar(self):
        analiz = {"sayfa_rolu": "soru", "rol_guveni": .41,
                  "duzen_guveni": .52, "egiklik_derece": 1.7,
                  "bolgesel_gecis": True, "dagilim_disi": True,
                  "pipeline_hatasi": "model çalışmadı", "adaylar": [],
                  "sutun_kanitlari": ["gorsel_projeksiyon"]}
        web._v2_sonuclarini_sakla(_Profil(), [analiz])

        kayit = web._inceleme_listesi()["sayfa_kayitlari"][0]
        nedenler = set(kayit["risk_nedenleri"])
        self.assertTrue({"analiz_veya_pipeline_hatasi", "dusuk_rol_guveni",
                         "dusuk_duzen_guveni", "egik_kaynak",
                         "bolgesel_duzen_gecisi", "dagilim_disi_duzen"}
                        .issubset(nedenler))
        self.assertIn("gorsel_projeksiyon", kayit["kanitlar"])
        self.assertTrue(any("model çalışmadı" in u for u in kayit["uyarilar"]))

    def test_soru_yok_karari_kutulari_dislar_ve_geri_alinca_getirir(self):
        self._v2_yukle()
        once = web._kutular(0)

        sonuc = web._sayfa_inceleme_karari(0, "soru_yok")
        self.assertEqual("soru_yok", sonuc["karar"])
        self.assertEqual([], web._kutular(0))
        self.assertTrue(web._kalite_kapisi_raporu()["ok"])

        web._sayfa_inceleme_karari(0, "bekliyor")
        self.assertEqual(once, web._kutular(0))
        self.assertFalse(web._kalite_kapisi_raporu()["ok"])

    def test_sayfa_onayi_gorunen_reddedilen_kutuyu_da_plana_sabitler(self):
        self._v2_yukle()
        web._sayfa_inceleme_karari(0, "onayli")

        self.assertEqual(web._kutular(0), web._kutu_atama()[0])
        self.assertEqual(3, len(web._kutu_atama()[0]))
        self.assertTrue(web._kalite_kapisi_raporu()["ok"])

    def test_kati_kapi_kesim_ve_metin_exportundan_once_ayni_hata_verir(self):
        self._v2_yukle()
        with mock.patch.object(web.sk, "kirpma_seti") as kirp:
            with self.assertRaises(web.KaliteKapisiHatasi) as kes_hata:
                web._kes_ortak(None)
            kirp.assert_not_called()
        with self.assertRaises(web.KaliteKapisiHatasi) as export_hata:
            web.disa_aktar_kaydet("csv", None)
        self.assertEqual(kes_hata.exception.rapor,
                         export_hata.exception.rapor)

    def test_kesim_metasinda_elle_atama_diger_guvenleri_yuze_cevirmez(self):
        self._v2_yukle()
        web._sayfa_inceleme_karari(0, "onayli")
        ham_sorular = [{"kaynak_kutu": [0, 0]},
                       {"kaynak_kutu": [0, 1]}]
        with mock.patch.object(
                web.sk, "kirpma_seti",
                return_value=([], ham_sorular, [])):
            _, sorular = web._kes_ortak(None)

        self.assertAlmostEqual(.91, sorular[0]["guven"])
        self.assertAlmostEqual(.68, sorular[1]["guven"])
        self.assertEqual("onaylandi", sorular[0]["onay_durumu"])
        self.assertEqual("onaylandi", sorular[1]["onay_durumu"])

    def test_legacy_banka_secimi_aynen_korunur(self):
        secim = ["s1", "s2"]
        self.assertEqual((secim, 0), web._bankaya_secim_filtresi(secim))
        self.assertEqual((None, 0), web._bankaya_secim_filtresi(None))

    def test_arayuz_v2_uclarini_ve_rozetleri_icerir(self):
        self.assertIn("/kalibrasyon", web.SAYFA)
        self.assertIn("/inceleme", web.SAYFA)
        self.assertIn("/inceleme-sayfa", web.SAYFA)
        self.assertIn("kararli_kimlik", web.SAYFA)
        self.assertIn("Sayfa doğru", web.SAYFA)
        self.assertIn("Soru yok", web.SAYFA)
        self.assertIn("Otomatik Kalibrasyon", web.SAYFA)
        self.assertIn("Reddedildi", web.SAYFA)
        self.assertIn("gemini_vision_aktif", web.SAYFA)
        self.assertIn("gizlilik ve API ücreti", web.SAYFA)


if __name__ == "__main__":
    unittest.main()
