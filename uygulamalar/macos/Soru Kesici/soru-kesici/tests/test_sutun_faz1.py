"""Faz 1 (sütun-taşma) hedef-davranış testleri — TDD hazırlığı.

Bu dosya `kalite/faz1_plan_2026-07-21.md` (A1*/A2* bölümleri) ve kanıt
bağlamı `kalite/sutun_teshis_2026-07-21.md`'de tarif edilen düzeltmelerin
HEDEF davranışını kodlar. Sentetik sayfa fixture idiomu
`tests/test_detection_pipeline.py`'deki (özellikle
`test_iki_sutundan_tam_genislige_gecen_raster_sayfa`, satır ~234) sahte
sayfa sınıfıyla aynıdır: `raster`, `genislik`, `yukseklik`, `satirlar()`,
`resim_kutulari()`.

Not (2026-07-21, ilerleyen düzenleme): A1* düzeltmesi (soru_kes.py'de
`SATIR_ICI_SORU_BASLANGICI` deseni + `_v3_duzen_bolgeleri` tabanlı
tam-genişlik kontrolü) bu dosya yazılırken paralel bir çalışmayla
uygulandı; bu yüzden A1 hedef testleri (1, 2) artık İŞARETSİZ (bugün
YEŞİL).

Not (2026-07-21, ikinci güncelleme): A2* (konsensüs/soy tekilleştirme
katmanı) da uygulanıp kabul edildi (ygslys 67→3, aydin 33→25 anomali).
A2 hedef testleri (5, 6) artık İŞARETSİZ — `@unittest.expectedFailure`
kaldırıldı, ikisi de bugün YEŞİL. Tüm dosya artık düz yeşil (7/7).
"""
import unittest
from unittest import mock

import soru_kes as sk


# --------------------------------------------------------------------------
# A1* — _aday_bant_araligi guard (soru_kes.py:3299-3320 civarı)
# Kaynak: faz1_plan Adım 1; sutun_teshis (b) "aydin kök nedeni".
# --------------------------------------------------------------------------

class _A1SahteRasterSayfaKarisimi:
    """aydin s31/s55 örüntüsünün minimal kopyası: 2 sütunlu raster sayfa,
    numara "3."/"1." solda kendi satırında, gutter'ı geçen BİRLEŞİK OCR
    satırı karşı bantta soru-başlangıcı kalıbıyla ("6. Aşağıdak…" gibi)
    devam ediyor. `sayfa_sutun_kalibrasyonu` mock'lanarak `bolgesel_gecis`
    ve `bantlar` doğrudan kontrol edilir — böylece `_aday_bant_araligi`'nin
    (gelecekteki) `duzen_bolgeleri_uret` tabanlı kontrolü, testin enjekte
    ettiği kalibrasyonla TUTARLI kalır (hem bugünkü `sayfa_sutunlari`
    çağrısı hem ileride eklenecek tam-genişlik-bölge sorgusu aynı mock'tan
    beslenir)."""

    G = 2117.0
    Y = 2905.0
    GUTTER = 1064.3

    @classmethod
    def uret(cls, numara_metni, merged_metin, merged_x1=1913.0):
        G, Y = cls.G, cls.Y

        class SahteRaster:
            raster = True
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                return [
                    (numara_metni, (48.6, 2316.9, 172.4, 2366.0), False),
                    (merged_metin, (167.9, 2290.0, merged_x1, 2366.0), False),
                    ("A) Bir", (60, 2400, 300, 2430), False),
                    ("B) Iki", (60, 2430, 300, 2460), False),
                    ("C) Uc", (60, 2460, 300, 2490), False),
                    ("D) Dort", (60, 2490, 300, 2520), False),
                    ("E) Bes", (60, 2520, 300, 2550), False),
                    ("A) Alfa", (1100, 2400, 1900, 2430), False),
                    ("B) Beta", (1100, 2430, 1900, 2460), False),
                    ("C) Gamma", (1100, 2460, 1900, 2490), False),
                    ("D) Delta", (1100, 2490, 1900, 2520), False),
                    ("E) Epsilon", (1100, 2520, 1900, 2550), False),
                ]

            def resim_kutulari(self):
                return []

        return SahteRaster()

    @classmethod
    def kalibrasyon(cls, bolgesel_gecis):
        return sk.SutunKalibrasyonu(
            bantlar=((0.0, cls.GUTTER), (cls.GUTTER, cls.G)),
            guven=0.9, ayraclar=(cls.GUTTER,),
            bolgesel_gecis=bolgesel_gecis)


class A1HedefTestleri(unittest.TestCase):
    """A1* hedefleri — düzeltme öncesi BAŞARISIZ, düzeltme sonrası YEŞİL
    olması beklenirdi. 2026-07-21 güncellemesi: A1* düzeltmesi bu testler
    yazılırken paralel olarak uygulandı; ikisi de artık bugün YEŞİL —
    bu yüzden `expectedFailure` işareti YOK (team-lead talimatı)."""

    def test_gutter_asan_birlesik_satir_tek_bantta_kalmali(self):
        """Faz1 plan Adım 1 / Aday 2 (aydin s31, sutun_teshis (b)).

        Numara "3." solda kendi satırında; Apple Vision'ın birleştirdiği
        varsayılan OCR satırı ("...yıkıl, 6. Aşağıdakilerden") gutter'ı
        (x=1064.3) geçiyor ve karşı bant tarafı soru-başlangıcı kalıbında
        ("6." + büyük harfle başlayan sözcük). Sayfada doğrulanmış
        tam-genişlik bölgesi YOK (`bolgesel_gecis=False`). Hedef: kutu 3
        tek banda (sol sütuna) sığmalı, gutter'ı geçen tam-genişlik kutu
        ÜRETİLMEMELİ.
        """
        sayfa = _A1SahteRasterSayfaKarisimi.uret(
            "• 3.",
            "ATP' deki yuksek enerjili fosfat baglarinin yikil, "
            "6. Asagidakilerden")
        kal = _A1SahteRasterSayfaKarisimi.kalibrasyon(bolgesel_gecis=False)
        with mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                                return_value=kal), \
                mock.patch.object(sk, "_ml_sekil_kutulari", return_value=[]):
            meta, _, _ = sk.sorulari_tespit_meta(sayfa, "acik_uclu")
        gercek = [m for m in meta if not m.devam_aday]
        soru3 = next(m for m in gercek if m.numara == 3)
        self.assertAlmostEqual(soru3.kutu[0], 0.0, delta=1.0,
            msg="soru 3 kutusu sol sutunun disina tasmamali")
        self.assertAlmostEqual(
            soru3.kutu[2], _A1SahteRasterSayfaKarisimi.GUTTER, delta=1.0,
            msg="soru 3 kutusu gutter'i gecip 6. sorunun bandina "
                "genislememeli (birlesik OCR satiri kirilmali)")

    def test_satir_ortasinda_farkli_varyasyonlu_numara_da_tek_bantta_kalmali(
            self):
        """Faz1 plan Adım 1 / Aday 2 (aydin s55 örüntüsü, sutun_teshis (b)).

        s55 numara=1 ("... sınıflandırma yapılırken O 5. Aşağıdaki...")
        örüntüsünün varyasyonu: numara satır BAŞINDA değil, tek karakterlik
        bir gürültü jetonundan ("O") sonra satırın ortasında geçiyor ve
        virgülle değil doğrudan cümle-arasıyla bağlanıyor. Yine sayfada
        doğrulanmış tam-genişlik bölgesi YOK. Hedef: aynı şekilde tek bant.
        """
        sayfa = _A1SahteRasterSayfaKarisimi.uret(
            "• 1.",
            "Hucrede kromozom sayisinin siniflandirma yapilirken "
            "O 5. Asagidaki")
        kal = _A1SahteRasterSayfaKarisimi.kalibrasyon(bolgesel_gecis=False)
        with mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                                return_value=kal), \
                mock.patch.object(sk, "_ml_sekil_kutulari", return_value=[]):
            meta, _, _ = sk.sorulari_tespit_meta(sayfa, "acik_uclu")
        gercek = [m for m in meta if not m.devam_aday]
        soru1 = next(m for m in gercek if m.numara == 1)
        self.assertAlmostEqual(soru1.kutu[0], 0.0, delta=1.0)
        self.assertAlmostEqual(
            soru1.kutu[2], _A1SahteRasterSayfaKarisimi.GUTTER, delta=1.0,
            msg="varyasyonlu satir-ortasi numara da birlesik satiri "
                "tam-genislige tasimamali")


class A1NobetciTestleri(unittest.TestCase):
    """A1* nöbetçileri — bugün de, düzeltmeden sonra da YEŞİL kalmalı
    (davranış sabiti). İşaretsiz."""

    def test_zararsiz_satir_ortasi_numaralar_tek_basina_gecis_kaniti_degil(self):
        """Satır içi sayı, doğrulanmış bölge yokken sütun geçişi yaptıramaz.

        "6. kromozomda", "Şekil 6." ve "1., 3. ve 6. önermeler" gerçek bir
        yeni-soru jetonu değildir; fakat bu, satırın komşu sütuna açılmasını
        da haklı çıkarmaz. V3.2 ile geçiş kararı sözcük kalıbına değil,
        yerelleştirilmiş ``capraz_soru_satiri`` bölgesine bağlıdır.
        """
        varyasyonlar = [
            "ATP' deki 6. kromozomda gorulen degisim ile fosfat baglari "
            "yikilir",
            "Sekildeki hucre bolunmesi Sekil 6. da gosterilmistir "
            "aciklayiniz",
            "Kromozom sayisi 1., 3. ve 6. onermeler dogrultusunda "
            "incelenir",
        ]
        kal = _A1SahteRasterSayfaKarisimi.kalibrasyon(bolgesel_gecis=False)
        for metin in varyasyonlar:
            with self.subTest(metin=metin):
                sayfa = _A1SahteRasterSayfaKarisimi.uret("• 3.", metin)
                with mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                                        return_value=kal), \
                        mock.patch.object(sk, "_ml_sekil_kutulari",
                                          return_value=[]):
                    meta, _, _ = sk.sorulari_tespit_meta(sayfa, "acik_uclu")
                gercek = [m for m in meta if not m.devam_aday]
                soru3 = next(m for m in gercek if m.numara == 3)
                self.assertAlmostEqual(soru3.kutu[0], 0.0, delta=1.0)
                self.assertAlmostEqual(
                    soru3.kutu[2],
                    _A1SahteRasterSayfaKarisimi.GUTTER, delta=1.0,
                    msg=f"dogrulanmamis sutun gecisi engellenmeli: {metin!r}")

    def test_ayni_ydeki_yan_yana_sorular_birlesmez(self):
        """Ayrı OCR satırları aynı hizada olsa da iki sütun tek kutu olamaz."""
        G, Y, gutter = 1200.0, 1600.0, 600.0

        class YanYana:
            raster = True
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                return [
                    ("1.", (50, 100, 75, 125), False),
                    ("Aşağıdakilerden hangisi doğrudur?",
                     (85, 100, 585, 130), False),
                    ("2.", (610, 100, 635, 125), False),
                    ("Aşağıdakilerden hangisi yanlıştır?",
                     (645, 100, 1120, 130), False),
                    *[(f"{h}) Sol {h}", (80, 170 + i * 40, 360,
                                         195 + i * 40), False)
                      for i, h in enumerate("ABCDE")],
                    *[(f"{h}) Sağ {h}", (640, 170 + i * 40, 940,
                                         195 + i * 40), False)
                      for i, h in enumerate("ABCDE")],
                ]

            def resim_kutulari(self):
                return []

        sayfa = YanYana()
        kal = sk.SutunKalibrasyonu(
            bantlar=((0.0, gutter), (gutter, G)), guven=0.95,
            ayraclar=(gutter,), bolgesel_gecis=False)
        with mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                               return_value=kal), \
                mock.patch.object(sk, "_ml_sekil_kutulari", return_value=[]):
            meta, _, _ = sk.sorulari_tespit_meta(
                sayfa, "coktan_secmeli")
        gercek = [m for m in meta if not m.devam_aday]
        self.assertEqual([1, 2], [m.numara for m in gercek])
        self.assertLessEqual(gercek[0].kutu[2], gutter)
        self.assertGreaterEqual(gercek[1].kutu[0], gutter)

    def test_dogrulanmis_tam_genislik_gecisi_tek_banda_sikismaz(self):
        """tests/test_detection_pipeline.py:234'teki meşru tam-genişlik
        senaryosunun eşdeğeri (faz1_plan Adım 1 regresyon kapısı): sayfada
        GERÇEKTEN doğrulanmış (bolgesel_gecis=True + `duzen_bolgeleri_uret`
        çıktısında `capraz_soru_satiri` yöntemli tam-genişlik `DuzenBolgesi`)
        bir geçiş varsa, gutter'ı aşan soru kutusu tam genişlik KALMALI.
        """
        G, Y, gutter = 2000.0, 2600.0, 1000.0
        bantlar = ((0.0, gutter), (gutter, G))

        class SahteRasterTamGenislik:
            raster = True
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                return [
                    ("6- ) 30 PUAN asagida kloroplastin",
                     (90, 1050, 640, 1084), False),
                    ("sekli verilmistir; numarali yerleri doldurunuz.",
                     (660, 1050, 1430, 1088), False),
                    ("1 2 3 4 5 6 7 8 9 10 11",
                     (180, 1150, 1420, 1700), False),
                ]

            def resim_kutulari(self):
                return []

        sayfa = SahteRasterTamGenislik()
        kal = sk.SutunKalibrasyonu(bantlar=bantlar, guven=0.9,
                                    ayraclar=(gutter,), bolgesel_gecis=True)
        # Once duzen_bolgeleri_uret'in gercekten capraz_soru_satiri
        # bolgesi urettigini dogrula (test kurgusunun kendisi gecerli mi).
        bolgeler = sk.duzen_bolgeleri_uret(sayfa, kal)
        self.assertTrue(
            any(b.yontem == "capraz_soru_satiri" for b in bolgeler),
            "test kurgusu gecerli bir tam-genislik gecisi uretmeli")
        sayfa._v3_duzen_bolgeleri = tuple(b.to_dict() for b in bolgeler)

        with mock.patch.object(sk, "sayfa_sutun_kalibrasyonu",
                                return_value=kal), \
                mock.patch.object(sk, "_ml_sekil_kutulari", return_value=[]):
            meta, _, _ = sk.sorulari_tespit_meta(sayfa, "acik_uclu")
        gercek = [m for m in meta if not m.devam_aday]
        soru6 = next(m for m in gercek if m.numara == 6)
        self.assertAlmostEqual(soru6.kutu[0], 0.0, delta=1.0)
        self.assertAlmostEqual(soru6.kutu[2], G, delta=1.0,
            msg="dogrulanmis tam-genislik gecisi tek banda sikistirilmamali")


# --------------------------------------------------------------------------
# A2* — sayfa_sutun_kalibrasyonu konsensüs/soy katmanı
# (soru_kes.py:1792 civarı _sayfa_sutunlari_v21 soy, :2298-2321 güçlü +
# too-close filtresi). Kaynak: faz1_plan Adım 2; sutun_teshis (c)/(e) Aday 1.
# --------------------------------------------------------------------------

class A2HedefTestleri(unittest.TestCase):
    """A2* hedefleri. A2* ile yeşile döndü (2026-07-21) — konsensüs/soy
    katmanı düzeltmesi uygulandı ve kabul edildi (ygslys 67→3, aydin
    33→25); `@unittest.expectedFailure` işaretleri bu yüzden kaldırıldı."""

    def test_yakin_ayrac_catismasinda_gorsel_gutter_secilmeli(self):
        """Faz1 plan Adım 2 / Aday 1 (ygslys s16 örüntüsü, sutun_teshis (c)/(e)).

        Sentetik yoğun 3-sütunlu raster sayfa (ygslys'in 4-sütun örüntüsünün
        minimal kopyası, 2. ve 3. sütun arası boşluk odaklı). Numara
        sütunları x≈205, 825, 1557 → `_numara_bant` sınırı iki numaranın TAM
        ORTASINA (825,1557 → 1191) koyuyor çünkü sütun 2'nin gövde metni
        sütun 3'ün numara kenarına taşıp "örtüşme" sayılıyor (gerçek
        ygslys'te 1190.9). Bağımsız GÖRSEL kanıt (coklu_projeksiyon +
        bolgesel_seam, mock'lanmış) gerçek gutter'ı 1485'te buluyor —
        numara-midpoint (1191) birden çok soru ilk-satırını keserken görsel
        gutter (1485) kesmiyor. G*0.12 içinde çakıştıkları için bugünkü
        "yüksek-destekliyi tut" filtresi numara-midpoint'i (v21+ocr_capalari
        = 0.70) görsel gutter'a (coklu+bolgesel ≈ 0.58) tercih ediyor — YANLIŞ
        seçim. Hedef: kalibrasyon GÖRSEL gutter'ı (1485) seçmeli.

        A2* ile yeşile döndü (2026-07-21).
        """
        G, Y = 2900.0, 3800.0

        class YogunRasterUcSutun:
            raster = True
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                out = []
                kolonlar = {205: [1, 9], 825: [2, 10], 1557: [3, 11]}
                for x, numlar in kolonlar.items():
                    for i, n in enumerate(numlar):
                        y = 300 + i * 2200
                        out.append((f"{n}. Asagidaki sorunun ilk satiri",
                                    (x, y, x + 24, y + 28), False))
                # sutun 2 (825) govdesi sutun 3'un (1557) numara kenarina
                # tasiyor -> _numara_bant icerik-kenar yontemi ortusuyor,
                # saf numara-ortasina (1191) duser (gercek ygslys orunutusu).
                out.append(("Bu sorunun govde metni oldukca genis bir "
                            "alana yayiliyor", (825, 500, 1650, 528), False))
                out.append(("Bu sorunun govde metni oldukca genis bir "
                            "alana yayiliyor",
                            (825, 2400, 1650, 2428), False))
                return out

            def resim_kutulari(self):
                return []

        sayfa = YogunRasterUcSutun()
        gorsel_gutter = 1485.0

        def sahte_v21(s):
            gecerli = sk._numara_sutunlari(s)
            return sk._numara_bant(s, gecerli, s.genislik)

        with mock.patch.object(sk, "_sayfa_sutunlari_v21",
                                side_effect=sahte_v21), \
                mock.patch.object(sk, "_coklu_projeksiyon_ayraclari",
                                   return_value=[(gorsel_gutter, 1.0)]), \
                mock.patch.object(sk, "_bolgesel_projeksiyon_ayraclari",
                                   return_value=([(gorsel_gutter, 1.0)],
                                                 False)), \
                mock.patch.object(sk, "_ml_sutun_ayraclari",
                                   return_value=[]), \
                mock.patch.object(sk, "_soru_modeli_sutun_ayraclari",
                                   return_value=[]), \
                mock.patch.object(sk, "_egiklik_tahmini",
                                   return_value=(0.0, 1.0)):
            kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)

        self.assertTrue(
            any(abs(x - gorsel_gutter) < 15 for x in kal.ayraclar),
            f"gorsel gutter (~{gorsel_gutter}) secilmeliydi: {kal.ayraclar}")
        self.assertFalse(
            any(abs(x - 1191.0) < 15 for x in kal.ayraclar),
            f"numara-midpoint (~1191) yanlislikla secilmemeliydi: "
            f"{kal.ayraclar}")

    def test_soy_tekillestirme_numara_yedegi_tek_basina_guclu_sayilmamali(
            self):
        """Faz1 plan Adım 2 (soy işareti, sutun_teshis (c) son paragraf).

        `_sayfa_sutunlari_v21`'in GERÇEKTEN `_numara_bant` yedeğinden
        geldiği (raster görsel projeksiyon sütunları ayıramadığı — burada
        `sutun_bantlari` tek bant döndürecek şekilde kısılmış) minimal
        2-sütunlu kurguda, v21_geometri ile ocr_capalari İKİSİ DE aynı
        numara-türevi ayracı (550) işaret ediyor. Bunlar bağımsız kanıt
        DEĞİL (aynı kaynak: numara x-ortalaması) ama bugün 2 ayrı "yöntem"
        sayılıp güçlü (0.70) çıkıyor; bağımsız GÖRSEL kanıtı (730, tek
        başına coklu+bolgesel≈0.58) G*0.12 içindeyken bastırıyor. Hedef:
        v21+ocr_capalari çifti TEK kanıt ailesi sayılmalı, böylece bağımsız
        görsel kanıt kazanmalı.

        A2* ile yeşile döndü (2026-07-21).
        """
        G, Y = 2000.0, 3000.0

        class YogunRasterIki:
            raster = True
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                out = []
                kolonlar = {200: [1, 9], 900: [2, 10]}
                for x, numlar in kolonlar.items():
                    for i, n in enumerate(numlar):
                        y = 300 + i * 2000
                        out.append((f"{n}. Asagidaki sorunun ilk satiri",
                                    (x, y, x + 24, y + 28), False))
                out.append(("Bu sorunun govde metni oldukca genis bir "
                            "alana yayiliyor", (200, 500, 950, 528), False))
                out.append(("Bu sorunun govde metni oldukca genis bir "
                            "alana yayiliyor",
                            (200, 2300, 950, 2328), False))
                return out

            def resim_kutulari(self):
                return []

        sayfa = YogunRasterIki()
        gorsel_gutter = 730.0

        with mock.patch.object(sk, "sutun_bantlari",
                                return_value=[(0.0, G)]), \
                mock.patch.object(sk, "_coklu_projeksiyon_ayraclari",
                                   return_value=[(gorsel_gutter, 1.0)]), \
                mock.patch.object(sk, "_bolgesel_projeksiyon_ayraclari",
                                   return_value=([(gorsel_gutter, 1.0)],
                                                 False)), \
                mock.patch.object(sk, "_ml_sutun_ayraclari",
                                   return_value=[]), \
                mock.patch.object(sk, "_soru_modeli_sutun_ayraclari",
                                   return_value=[]), \
                mock.patch.object(sk, "_egiklik_tahmini",
                                   return_value=(0.0, 1.0)):
            # On-kosul: v21 GERCEKTEN _numara_bant yedeginden geliyor mu?
            gecerli = sk._numara_sutunlari(sayfa)
            beklenen_yedek = sk._numara_bant(sayfa, gecerli, G)
            v21 = sk._sayfa_sutunlari_v21(sayfa)
            self.assertEqual(
                list(v21), list(beklenen_yedek),
                "on-kosul: v21 gercekten numara-bant yedeginden gelmeli")

            kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)

        self.assertTrue(
            any(abs(x - gorsel_gutter) < 15 for x in kal.ayraclar),
            f"bagimsiz gorsel kanit (~{gorsel_gutter}) kazanmali: "
            f"{kal.ayraclar}")
        self.assertFalse(
            any(abs(x - 550.0) < 15 for x in kal.ayraclar),
            f"numara-yedegi tek basina (v21+ocr_capalari ikilisi) guclu "
            f"sayilip kazanmamali: {kal.ayraclar}")


class A2NobetciTestleri(unittest.TestCase):
    """A2* nöbetçisi — bugün de, düzeltmeden sonra da YEŞİL kalmalı
    (12meb BİT-ÖZDEŞ kalmalı, faz1_plan Adım 2 regresyon nöbetçisi).
    İşaretsiz."""

    def test_temiz_iki_sutun_metin_sayfasinda_gorsel_gutter_degismez(self):
        """Faz1 plan Adım 2 regresyon nöbetçisi + sutun_teshis 'Karşılaştırma
        — 12meb' bölümü: metin PDF'de (raster=False) görsel projeksiyon
        gutter'ı net buluyor; numara sütunları zayıf/ayrık kanıt. Herhangi
        bir A2* değişikliği bu TEMİZ senaryoda seçimi DEĞİŞTİRMEMELİ —
        sonuç bugün de, düzeltmeden sonra da aynı (görsel gutter) kalmalı.
        """
        G, Y = 600.0, 800.0

        class TemizMetinSayfa:
            raster = False
            belge_no = 0
            genislik = G
            yukseklik = Y

            def satirlar(self):
                out = []
                sol = [
                    "1. Bu sorunun ilk satiridir ve metni epeyce",
                    "uzun devam etmektedir boylece",
                    "A) Bir", "B) Iki", "C) Uc", "D) Dort", "E) Bes",
                    "3. Ucuncu sorunun ilk satiridir",
                    "A) Alfa", "B) Beta", "C) Gama", "D) Delta", "E) Epsilon",
                ]
                sag = [
                    "2. Ikinci sorunun ilk satiridir ve metni epeyce",
                    "uzun devam etmektedir boylece",
                    "A) Bir", "B) Iki", "C) Uc", "D) Dort", "E) Bes",
                    "4. Dorduncu sorunun ilk satiridir",
                    "A) Alfa", "B) Beta", "C) Gama", "D) Delta", "E) Epsilon",
                ]
                y = 40
                for s in sol:
                    out.append((s, (40, y, 258, y + 18), False))
                    y += 28
                y = 40
                for s in sag:
                    out.append((s, (342, y, 560, y + 18), False))
                    y += 28
                return out

            def resim_kutulari(self):
                return []

        sayfa = TemizMetinSayfa()
        # Beklenen deger: SAF gorsel projeksiyondan bagimsizca turetilir
        # (sabit bir "magic number" degil) -- boylece nobetci yalnizca
        # "secim gorsel gutter ile ayni mi" sorusunu test eder.
        gorsel_bantlar = sk.sutun_bantlari(sayfa)
        beklenen_gutter = sk._bant_ayraclari(gorsel_bantlar, G)[0]

        kal = sk.sayfa_sutun_kalibrasyonu(sayfa, yenile=True)

        self.assertEqual(2, len(kal.bantlar))
        self.assertEqual(1, len(kal.ayraclar))
        self.assertAlmostEqual(kal.ayraclar[0], beklenen_gutter, delta=1.0,
            msg="temiz iki-sutun sayfada secim gorsel gutter'dan sapmamali")


if __name__ == "__main__":
    unittest.main()
