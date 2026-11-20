import os
import unittest
from unittest import mock

import soru_kes as sk


class SahteSayfa:
    raster = False
    belge_no = 0
    dpi = 144

    def __init__(self, metinler, genislik=600, yukseklik=800):
        self.genislik = genislik
        self.yukseklik = yukseklik
        self._sat = []
        for i, oge in enumerate(metinler):
            if isinstance(oge, tuple):
                metin, x, y = oge
            else:
                metin, x, y = oge, 45, 45 + i * 25
            self._sat.append((metin, (x, y, min(genislik - 35,
                                                x + max(40, len(metin) * 5)),
                                       y + 15), False))

    def satirlar(self):
        return self._sat

    def resim_kutulari(self):
        return []


class BelgeProfiliV2Testi(unittest.TestCase):
    def test_cebirsel_secenekler_cevap_anahtari_sanilmaz(self):
        soru = SahteSayfa([
            ("287. Aşağıdakilerden hangisi doğrudur?", 45, 70),
            ("A) a + 2b + 3c + 4d", 55, 130),
            ("B) a + 2b + 2c + 2d", 55, 160),
            ("C) a + 2b + 2c + 3d", 55, 190),
            ("D) a + 2b + 4c + 2d", 55, 220),
            ("E) 2a + 2b + 2c + 2d", 55, 250),
        ])
        anahtar = SahteSayfa([
            "1-A 2-B 3-C 4-D",
            "5-E 6-A 7-B 8-C",
            "9-D 10-E 11-A 12-B",
        ])
        self.assertFalse(sk._cevap_sayfasi_mi(soru.satirlar()))
        self.assertEqual(
            "soru", sk._sayfa_rolu_belirle(soru.satirlar())[0])
        self.assertTrue(sk._cevap_sayfasi_mi(anahtar.satirlar()))

    def test_kitapcik_etiketli_cevap_izgarasi_korunur(self):
        anahtar = SahteSayfa([
            "CEVAP ANAHTARI",
            "A) 1-B 2-C 3-D 4-E 5-A 6-B",
            "B) 7-C 8-D 9-E 10-A 11-B 12-C",
            "C) 13-D 14-E 15-A 16-B 17-C 18-D",
            "D) 19-E 20-A 21-B 22-C 23-D 24-E",
        ])
        cift, izgara, benzersiz, baskin = sk._cevap_cesitliligi(
            anahtar.satirlar())
        self.assertEqual((24, 4, 5), (cift, izgara, benzersiz))
        self.assertLessEqual(baskin, 0.70)
        self.assertTrue(sk._cevap_sayfasi_mi(anahtar.satirlar()))

    def test_tek_hucreli_test_anahtari_da_cevap_sayfasidir(self):
        anahtar = SahteSayfa([
            ("TYT TARAMA TESTI-1", 45, 35),
            *[(f"{i}. {'ABCDE'[(i - 1) % 5]}", 55, 65 + i * 18)
              for i in range(1, 16)],
        ])
        cift, izgara, benzersiz, _ = sk._cevap_cesitliligi(
            anahtar.satirlar())
        self.assertEqual((15, 0, 5), (cift, izgara, benzersiz))
        self.assertTrue(sk._cevap_sayfasi_mi(anahtar.satirlar()))
        self.assertEqual(
            [{"test_no": 1,
              "cevaplar": {i: "ABCDE"[(i - 1) % 5]
                            for i in range(1, 16)}}],
            sk.cevap_anahtari_bul([anahtar]),
        )

    def test_ust_sag_kosucu_baslik_soldaki_ilk_sorudan_once_islenir(self):
        sayfa = SahteSayfa([
            ("TYT TARAMA TESTİ-1", 350, 10),
        ], genislik=600, yukseklik=800)
        sorular = [
            sk.SoruKutu((40, 80, 280, 180), 0, 1, False,
                        frozenset("ABCDE"), "E) Beş", True),
            sk.SoruKutu((320, 80, 560, 180), 1, 2, False,
                        frozenset("ABCDE"), "E) Beş", True),
        ]
        meta, testler = sk.test_bolumleri(
            [sayfa], [(sorular, [(0.0, 300.0), (300.0, 600.0)],
                                "coktan_secmeli")]
        )
        etiketli = meta[0][0]
        self.assertEqual([1, 1], [s.test_no for s in etiketli])
        self.assertEqual([1, 1], [s.test_sira for s in etiketli])
        self.assertEqual(1, len(testler))
        self.assertEqual(2, testler[0]["adet"])

    def test_sayfa_rolleri_kapak_konu_soru_cozum_olarak_ayrilir(self):
        kapak = SahteSayfa(["11. Sınıf Biyoloji Soru Bankası", "Yayınları"])
        konu = SahteSayfa([
            "KONU ANLATIMI", "Hücre canlıların temel yapı birimidir ve uzun bir açıklamadır.",
            "Organeller hücre içinde farklı görevler üstlenir ve birlikte çalışır.",
            "1. Mitokondri: Enerji dönüşümünde görevli organeldir.",
        ])
        soru = SahteSayfa([
            ("TEST 1", 45, 45),
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 90),
            ("A) Bir", 55, 120), ("B) İki", 55, 145),
            ("C) Üç", 55, 170), ("D) Dört", 55, 195), ("E) Beş", 55, 220),
            ("2. Aşağıdakilerden hangisi yanlıştır?", 45, 350),
            ("A) Alfa", 55, 380), ("B) Beta", 55, 405),
            ("C) Gama", 55, 430), ("D) Delta", 55, 455), ("E) Epsilon", 55, 480),
        ])
        cozum = SahteSayfa(["ÇÖZÜMLER", "Çözüm: Doğru cevap A seçeneğidir."])
        sayfalar = [kapak, konu, soru, cozum]
        profil = sk.belge_profili_uret(
            sayfalar, fmt="karisik", girdiler=None,
            tum_satirlar=[s.satirlar() for s in sayfalar], onbellek=False)
        self.assertEqual(["kapak", "konu", "soru", "çözüm"],
                         [r["rol"] for r in profil.sayfa_rolleri])
        self.assertEqual(4, profil.sayfa_sayisi)
        self.assertEqual(sk.KALIBRASYON_SURUMU, profil.algoritma_surumu)
        self.assertEqual(profil.to_dict(),
                         sk.BelgeProfili.from_dict(profil.to_dict()).to_dict())

    def test_analiz_adaylara_tur_guven_ve_durum_ekler(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 80),
            ("A) Bir", 55, 115), ("B) İki", 55, 140),
            ("C) Üç", 55, 165), ("D) Dört", 55, 190), ("E) Beş", 55, 215),
            ("2. Aşağıdaki sonucu kısaca açıklayınız.", 45, 360),
            ("........................................", 55, 405),
            ("........................................", 55, 430),
        ])
        with mock.patch.dict(os.environ, {"SORU_KESICI_GEMINI_VISION": "0"}), \
                mock.patch.object(sk, "sayfa_sutunlari",
                                  return_value=[(0.0, 600.0)]):
            profil, analizler = sk.belge_analiz_et(
                [sayfa], fmt="karisik", tum_satirlar=[sayfa.satirlar()],
                onbellek=False)
        adaylar = [a for a in analizler[0].adaylar if not a.devam_aday]
        self.assertEqual(2, len(adaylar))
        self.assertEqual("çoktan_seçmeli", adaylar[0].soru_turu)
        self.assertIn(adaylar[1].soru_turu, ("açık_uçlu", "kısa_cevap"))
        self.assertTrue(all(0 <= a.guven <= 1 for a in adaylar))
        self.assertTrue(all(a.inceleme_durumu in
                            ("otomatik", "incele", "reddedildi") for a in adaylar))
        self.assertIs(sayfa._v2_belge_profili, profil)
        self.assertIs(sayfa._v2_sayfa_analizi, analizler[0])


class KaliteKapisiV2Testi(unittest.TestCase):
    def test_yuksek_guvenli_yontem_uyusmazligi_yalniz_uyaridir(self):
        yuksek = sk.SutunKalibrasyonu(
            bantlar=((0.0, 300.0), (300.0, 600.0)), guven=.82,
            uyarilar=("sutun_yontemleri_uyusmuyor",))
        dusuk = sk.SutunKalibrasyonu(
            bantlar=yuksek.bantlar, guven=.68,
            uyarilar=yuksek.uyarilar)
        gecis = sk.SutunKalibrasyonu(
            bantlar=yuksek.bantlar, guven=.82,
            uyarilar=("bolgesel_sutun_gecisi",))

        self.assertNotIn(
            "sutun_yontemleri_uyusmuyor",
            sk._sutun_uyarisi_sayfa_riskleri(yuksek))
        self.assertIn(
            "sutun_yontemleri_uyusmuyor",
            sk._sutun_uyarisi_sayfa_riskleri(dusuk))
        self.assertIn(
            "bolgesel_sutun_gecisi",
            sk._sutun_uyarisi_sayfa_riskleri(gecis))

    def test_coklu_olcek_projeksiyon_ayraci_kararli_bulur(self):
        sayfa = SahteSayfa([])
        profil = [0.42] * 46 + [0.0] * 9 + [0.39] * 45
        with mock.patch.object(sk, "dikey_projeksiyon",
                               return_value=(profil, 6.0)):
            ayraclar = sk._coklu_projeksiyon_ayraclari(sayfa)
        self.assertEqual(1, len(ayraclar))
        self.assertAlmostEqual(300.0, ayraclar[0][0], delta=20)
        self.assertGreaterEqual(ayraclar[0][1], 0.5)

    def test_dort_yontem_uzlasinca_sutun_guveni_yuksek_olur(self):
        sayfa = SahteSayfa([])
        kumeler = [[(45, 90), (45, 420)], [(315, 95), (315, 425)]]
        with mock.patch.object(sk, "_sayfa_sutunlari_v21",
                               return_value=[(0, 300), (300, 600)]), \
                mock.patch.object(sk, "_coklu_projeksiyon_ayraclari",
                                  return_value=[(302, 1.0)]), \
                mock.patch.object(sk, "_bolgesel_projeksiyon_ayraclari",
                                  return_value=([(298, 1.0)], False)), \
                mock.patch.object(sk, "_numara_sutunlari",
                                  return_value=kumeler), \
                mock.patch.object(sk, "_numara_bant",
                                  return_value=[(0, 301), (301, 600)]), \
                mock.patch.object(sk, "_egiklik_tahmini",
                                  return_value=(0.0, 1.0)):
            kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)
        self.assertEqual(2, len(kal.bantlar))
        self.assertGreaterEqual(kal.guven, 0.82)
        self.assertIn("coklu_projeksiyon", kal.kanitlar)
        self.assertIn("ocr_capalari", kal.kanitlar)

    def test_guclu_uzlasma_desteksiz_eski_ayraci_degistirir(self):
        sayfa = SahteSayfa([])
        kumeler = [[(45, 90), (45, 420)], [(315, 95), (315, 425)]]
        with mock.patch.object(sk, "_sayfa_sutunlari_v21",
                               return_value=[(0, 200), (200, 600)]), \
                mock.patch.object(sk, "_coklu_projeksiyon_ayraclari",
                                  return_value=[(300, 1.0)]), \
                mock.patch.object(sk, "_bolgesel_projeksiyon_ayraclari",
                                  return_value=([(302, 1.0)], False)), \
                mock.patch.object(sk, "_numara_sutunlari",
                                  return_value=kumeler), \
                mock.patch.object(sk, "_numara_bant",
                                  return_value=[(0, 298), (298, 600)]), \
                mock.patch.object(sk, "_egiklik_tahmini",
                                  return_value=(0.0, 1.0)):
            kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)
        self.assertEqual(2, len(kal.bantlar))
        self.assertAlmostEqual(300, kal.ayraclar[0], delta=8)
        self.assertNotAlmostEqual(200, kal.ayraclar[0], delta=20)

    def test_kenar_numara_seridi_sahte_sutun_olamaz(self):
        sayfa = SahteSayfa([])
        kumeler = [[(45, 90), (45, 420)], [(315, 95), (315, 425)]]
        with mock.patch.object(sk, "_sayfa_sutunlari_v21",
                               return_value=[(0, 300), (300, 600)]), \
                mock.patch.object(sk, "_coklu_projeksiyon_ayraclari",
                                  return_value=[(55, 1.0), (300, 1.0)]), \
                mock.patch.object(sk, "_bolgesel_projeksiyon_ayraclari",
                                  return_value=([(54, 1.0), (302, 1.0)], False)), \
                mock.patch.object(sk, "_numara_sutunlari",
                                  return_value=kumeler), \
                mock.patch.object(sk, "_numara_bant",
                                  return_value=[(0, 300), (300, 600)]), \
                mock.patch.object(sk, "_egiklik_tahmini",
                                  return_value=(0.0, 1.0)):
            kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)
        self.assertEqual(2, len(kal.bantlar))
        self.assertEqual(1, len(kal.ayraclar))
        self.assertAlmostEqual(300, kal.ayraclar[0], delta=8)

    def test_dusuk_duzen_guveni_otomatik_kabulu_durdurur(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 80),
            ("A) Bir", 55, 115), ("B) İki", 55, 140),
            ("C) Üç", 55, 165), ("D) Dört", 55, 190),
            ("E) Beş", 55, 215),
        ])
        sayfa._v22_sutun_kalibrasyonu = sk.SutunKalibrasyonu(
            bantlar=((0.0, 600.0),), guven=0.48,
            uyarilar=("dusuk_sutun_guveni",))
        aday = sk.SoruKutu((40, 70, 560, 245), 0, 1, False,
                            frozenset("ABCDE"), "E) Beş", True)
        sonuc = sk._adaylari_zenginlestir(
            sayfa, sayfa.satirlar(), [aday], "coktan_secmeli",
            sayfa_rolu="soru")[0]
        self.assertIn("dusuk_duzen_guveni", sonuc.uyarilar)
        self.assertNotEqual("otomatik", sonuc.inceleme_durumu)

    def test_her_sutunda_tek_uzun_soru_sag_sorunun_basini_kesmez(self):
        sayfa = SahteSayfa([
            ("39. Bu parçadan hareketle hangisi söylenemez?", 48, 330),
            ("A) Bir", 65, 380), ("B) İki", 65, 410),
            ("C) Üç", 65, 440), ("D) Dört", 65, 470), ("E) Beş", 65, 500),
            ("40. Bu parçanın anlatımında hangisi ağır basmaktadır?", 285, 85),
            ("A) Açıklama", 305, 130), ("B) Örnekleme", 305, 160),
            ("C) Benzetme", 305, 190), ("D) Tartışma", 305, 220),
            ("E) Tanımlama", 305, 250),
        ])
        bantlar = sk.sayfa_sutunlari(sayfa)
        self.assertEqual(2, len(bantlar))
        self.assertLessEqual(bantlar[1][0], 285)
        meta, _, _ = sk.sorulari_tespit_meta(sayfa, "coktan_secmeli")
        sag = next(m for m in meta if m.numara == 40)
        self.assertLessEqual(sag.kutu[0], 285)

    def test_sutun_ayracini_asan_son_sozcuk_sagdan_kesilmez(self):
        sayfa = SahteSayfa([
            ("1. Basamaklardan hangileri bulunur mu acaba??", 36, 80),
            ("A) Yalnız I", 55, 130), ("B) Yalnız II", 55, 160),
            ("C) I ve II", 55, 190), ("D) I ve III", 55, 220),
            ("E) II ve III", 55, 250),
        ])
        with mock.patch.object(
                sk, "sayfa_sutunlari",
                return_value=[(0.0, 244.0), (244.0, 600.0)]):
            meta, _, _ = sk.sorulari_tespit_meta(
                sayfa, "coktan_secmeli")
        soru = next(m for m in meta if m.numara == 1)
        govde_sag = sayfa.satirlar()[0][1][2]
        self.assertGreater(govde_sag, 244.0)  # regresyonun ön koşulu
        self.assertGreaterEqual(soru.kutu[2], govde_sag)

    def test_sag_sutunun_emniyet_payi_okuma_sirasini_sola_tasimaz(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 35, 80),
            ("A) Bir", 55, 125), ("B) İki", 55, 150),
            ("C) Üç", 55, 175), ("D) Dört", 55, 200),
            ("E) Beş", 55, 225),
            ("2. Aşağıdakilerden hangisi yanlıştır?", 287, 80),
            ("A) Alfa", 307, 125), ("B) Beta", 307, 150),
            ("C) Gama", 307, 175), ("D) Delta", 307, 200),
            ("E) Epsilon", 307, 225),
        ])
        with mock.patch.object(
                sk, "sayfa_sutunlari",
                return_value=[(0.0, 286.0), (286.0, 600.0)]):
            meta, _, _ = sk.sorulari_tespit_meta(
                sayfa, "coktan_secmeli")
        sorular = [m for m in meta if not m.devam_aday]
        self.assertEqual([1, 2], [m.numara for m in sorular])
        self.assertEqual([0, 1], [m.bant_idx for m in sorular])
        self.assertLess(sorular[1].kutu[0], 286.0)  # emniyet payı gerçekten var

    def test_temiz_taramada_gorsel_ayirici_numara_ortasindan_ustundur(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 90),
            ("2. Aşağıdakilerden hangisi yanlıştır?", 45, 420),
            ("3. Aşağıdakilerden hangisi doğrudur?", 315, 95),
            ("4. Aşağıdakilerden hangisi yanlıştır?", 315, 425),
        ])
        sayfa.raster = True
        kumeler = [[(45, 90), (45, 420)], [(315, 95), (315, 425)]]
        with mock.patch.object(sk, "_numara_sutunlari", return_value=kumeler), \
                mock.patch.object(sk, "sutun_bantlari", return_value=[
                    (0.0, 35.0), (35.0, 300.0), (300.0, 600.0)]):
            bantlar = sk.sayfa_sutunlari(sayfa)
        self.assertEqual(2, len(bantlar))
        self.assertAlmostEqual(300.0, bantlar[0][1])
        self.assertAlmostEqual(300.0, bantlar[1][0])

    def test_ocr_numarayi_kacirsa_da_ikinci_secenekli_blok_kurtarilir(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 70),
            ("A) Bir", 55, 115), ("B) İki", 55, 145),
            ("C) Üç", 55, 175), ("D) Dört", 55, 205), ("E) Beş", 55, 235),
            # Renkli '2.' OCR tarafından okunmamış kabul ediliyor.
            ("Aşağıdakilerden hangisi yanlıştır?", 45, 390),
            ("A) Alfa", 55, 435), ("B) Beta", 55, 465),
            ("C) Gama", 55, 495), ("D) Delta", 55, 525),
            ("E) Epsilon", 55, 555),
        ])
        with mock.patch.object(sk, "sayfa_sutunlari",
                               return_value=[(0.0, 600.0)]):
            meta, _, _ = sk.sorulari_tespit_meta(
                sayfa, "coktan_secmeli")
        gorunen = [m for m in meta if not m.devam_aday]
        self.assertEqual(2, len(gorunen))
        self.assertEqual(1, gorunen[0].numara)
        self.assertIsNone(gorunen[1].numara)
        self.assertEqual(frozenset("ABCDE"), gorunen[1].sik_harfler)

    def test_sekil_etiketleri_soruyu_govdesinden_ayirmaz(self):
        sayfa = SahteSayfa([
            ("1. A, B ve C noktaları aşağıdaki şekilde gösterilmiştir.",
             45, 70),
            ("C . . . 40 km", 90, 110),
            ("B . . . 94 km", 90, 135),
            ("A . . . 106 km", 90, 160),
            # Büyük, metinsiz şekil boşluğundan sonraki gerçek soru cümlesi.
            ("Buna göre, iki uzaklığın farkı kaçtır?", 55, 365),
            ("A) 6", 55, 400), ("B) 8", 120, 400),
            ("C) 10", 185, 400), ("D) 12", 250, 400),
            ("E) 14", 315, 400),
            ("2. Aşağıdakilerden hangisi doğrudur?", 45, 560),
            ("A) Bir", 55, 600), ("B) İki", 120, 600),
            ("C) Üç", 185, 600), ("D) Dört", 250, 600),
            ("E) Beş", 315, 600),
        ])
        with mock.patch.object(sk, "sayfa_sutunlari",
                               return_value=[(0.0, 600.0)]):
            meta, _, _ = sk.sorulari_tespit_meta(
                sayfa, "coktan_secmeli")
        gorunen = [m for m in meta if not m.devam_aday]
        self.assertEqual([1, 2], [m.numara for m in gorunen])
        self.assertFalse(any(m.numara is None for m in gorunen))
        self.assertGreaterEqual(gorunen[0].kutu[3], 415)

    def test_kaynak_damgasindan_sonraki_konu_listesi_kesime_girmez(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 70),
            ("A) Bir", 55, 110), ("B) İki", 55, 135),
            ("C) Üç", 55, 160), ("D) Dört", 55, 185),
            ("E) Beş", 55, 210),
            ("2025-TYT", 220, 240),
            ("Mantık", 60, 520),
            ("• Önermeler ve Bileşik Önermeler", 70, 550),
            ("• Koşullu Önerme", 85, 580),
        ])
        aday = sk.SoruKutu(
            (35.0, 60.0, 300.0, 730.0), 0, 1, False,
            frozenset("ABCDE"), "• Koşullu Önerme", True)
        sonuc = sk._pdf_metin_kutularini_sikilastir(
            sayfa, [aday], sayfa.satirlar(), "coktan_secmeli")
        self.assertEqual(1, len(sonuc))
        self.assertLess(sonuc[0].kutu[3], 300)
        self.assertEqual("2025-TYT", sonuc[0].son_metin)

    def test_girintili_icerik_numarasi_birlesme_uyarisi_degildir(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 80),
            ("2. üründe kullanılan miktar iki katına çıkar.", 90, 280),
            ("A) Bir", 55, 350), ("B) İki", 120, 350),
            ("C) Üç", 185, 350), ("D) Dört", 250, 350),
            ("E) Beş", 315, 350),
        ])
        sayfa._v3_soru_model_bolgeleri = []
        aday = sk.SoruKutu(
            (35.0, 70.0, 560.0, 410.0), 0, 1, False,
            frozenset("ABCDE"), "E) Beş", True,
            numara_kutu=sayfa.satirlar()[0][1])
        sonuc = sk._adaylari_zenginlestir(
            sayfa, sayfa.satirlar(), [aday], "coktan_secmeli")[0]
        self.assertNotIn("coklu_numara_icerik", sonuc.risk_nedenleri)

    def test_ayni_hizadaki_iki_soru_capasi_birlesme_uyarisini_korur(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 45, 80),
            ("2. Aşağıdakilerden hangisi yanlıştır?", 45, 300),
            ("A) Bir", 55, 350), ("B) İki", 120, 350),
            ("C) Üç", 185, 350), ("D) Dört", 250, 350),
            ("E) Beş", 315, 350),
        ])
        sayfa._v3_soru_model_bolgeleri = []
        aday = sk.SoruKutu(
            (35.0, 70.0, 560.0, 410.0), 0, 1, False,
            frozenset("ABCDE"), "E) Beş", True,
            numara_kutu=sayfa.satirlar()[0][1])
        sonuc = sk._adaylari_zenginlestir(
            sayfa, sayfa.satirlar(), [aday], "coktan_secmeli")[0]
        self.assertIn("coklu_numara_icerik", sonuc.risk_nedenleri)

    def test_tam_sayfa_kesimi_otomatik_kabul_edilmez(self):
        sayfa = SahteSayfa([
            ("1. Aşağıdakilerden hangisi doğrudur?", 30, 50),
            ("A) Bir", 40, 100), ("B) İki", 40, 130),
            ("C) Üç", 40, 160), ("D) Dört", 40, 190), ("E) Beş", 40, 220),
        ])
        aday = sk.SoruKutu((0, 0, 600, 790), 0, 1, False,
                            frozenset("ABCDE"), "E) Beş", True)
        sonuc = sk._adaylari_zenginlestir(
            sayfa, sayfa.satirlar(), [aday], "coktan_secmeli",
            sayfa_rolu="soru")[0]
        self.assertIn("tam_sayfaya_yakin", sonuc.uyarilar)
        self.assertNotEqual("otomatik", sonuc.inceleme_durumu)

    def test_konu_maddesi_soru_olarak_reddedilir(self):
        sayfa = SahteSayfa([
            "KONU ANLATIMI", "1. Mitokondri: Enerji üretiminde görev alır.",
            "Bu yapı hücrenin metabolik etkinliklerine katkı sağlar.",
        ])
        aday = sk.SoruKutu((40, 60, 540, 190), 0, 1, False,
                            frozenset(), "açıklama", False)
        sonuc = sk._adaylari_zenginlestir(
            sayfa, sayfa.satirlar(), [aday], "karisik",
            sayfa_rolu="konu")[0]
        self.assertEqual("reddedildi", sonuc.inceleme_durumu)
        self.assertIn("konu_sayfasinda_aday", sonuc.uyarilar)


if __name__ == "__main__":
    unittest.main()
