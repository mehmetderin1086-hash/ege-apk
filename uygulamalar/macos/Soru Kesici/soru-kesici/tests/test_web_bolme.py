import threading
import unittest

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


class KutuBolmeTesti(unittest.TestCase):
    """kutulari_guncelle üzerinden, istemcinin ✂ Böl işleminin ürettiği
    [üst(kimlikli), alt(kimliksiz)] snapshot'ının sunucuda doğru yorumlandığını
    doğrular (soru_kes_web.py Faz 5.3 — istemci-taraflı bölme, sunucu değişikliği
    yok; sözleşme zaten kutulari_guncelle'nin kimlik-diff mantığıdır)."""

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

    def _tek_kutulu_sayfa_kur(self):
        """Sayfa 0'a tek, birleşik iki-soruluk bir kutu (yükseklik 400) yükler
        ve kararlı kimliğini döndürür."""
        analiz = _Analiz([_Aday([10, 20, 280, 420], .91, "otomatik")])
        self.assertTrue(web._v2_sonuclarini_sakla(_Profil(), [analiz]))
        return web._kutu_metalari(0)[0]["kararli_kimlik"]

    def test_dogru_sirada_bolme_ust_yariyi_korur_alt_yariyi_yeni_kutu_sayar(self):
        kimlik = self._tek_kutulu_sayfa_kur()

        sonuc = web.kutulari_guncelle(0, [
            {"kutu": [10, 20, 280, 220], "kararli_kimlik": kimlik},   # üst: kimlikli, ÖNCE
            {"kutu": [10, 220, 280, 420], "kararli_kimlik": None},    # alt: kimliksiz, SONRA
        ])

        self.assertEqual(2, len(sonuc))
        # y-sıralı: üst (y0=20) alt'tan (y0=220) önce döner
        self.assertLess(sonuc[0][1], sonuc[1][1])
        for beklenen, gercek in zip([[10, 20, 280, 220], [10, 220, 280, 420]], sonuc):
            for b, g in zip(beklenen, gercek):
                self.assertAlmostEqual(b, g, delta=0.5)

        meta = web._kutu_metalari(0)
        self.assertEqual(kimlik, meta[0]["kararli_kimlik"],
                          "üst yarı eski kararlı kimliği taşımalı")
        self.assertNotEqual(kimlik, meta[1]["kararli_kimlik"],
                             "alt yarı yeni bir kimlik almalı")
        self.assertIn("kullanici_ekledi", meta[1]["uyarilar"])
        # Faz 5.3 tasarımı: her iki yarı da geometri değişimi/yeni kutu olarak
        # oto-onaylanır (kutulari_guncelle'nin degisti=True akışı).
        self.assertTrue(meta[0]["onayli"])
        self.assertTrue(meta[1]["onayli"])
        self.assertIn("kutu:" + kimlik, web.DURUM["inceleme_onaylari"])
        self.assertIn("kutu:" + meta[1]["kararli_kimlik"],
                       web.DURUM["inceleme_onaylari"])

    def test_ters_sirada_bolme_kimligi_alt_yariya_kaptirir(self):
        """Bilinen sınır / regresyon kancası: istemci üst(kimlikli)/alt(kimliksiz)
        sırasına uymazsa, kimliksiz alt yarının IoU-yedek eşlemesi (>=0.35) eski
        kutuyu üst yarıdan ÖNCE tüketir; üst yarı böylece kimliğini kaybedip yeni
        kutu sayılır, kimlik YANLIŞ geometriye (alt yarıya) yapışır. Bu test
        mevcut (istenmeyen ama bilinen) davranışı belgeler — sözleşme ileride
        değişirse bu test kırılıp alarm verir."""
        kimlik = self._tek_kutulu_sayfa_kur()

        sonuc = web.kutulari_guncelle(0, [
            {"kutu": [10, 220, 280, 420], "kararli_kimlik": None},    # alt: kimliksiz, ÖNCE (yanlış sıra)
            {"kutu": [10, 20, 280, 220], "kararli_kimlik": kimlik},   # üst: kimlikli, SONRA
        ])

        self.assertEqual(2, len(sonuc))
        self.assertLess(sonuc[0][1], sonuc[1][1])   # y-sıralama yine de üst/alt olarak döner

        meta = web._kutu_metalari(0)
        # Geometrik olarak üst (y0=20) hâlâ meta[0], alt (y0=220) meta[1] — ama
        # kimlik YANLIŞ tarafa yapışmış: eski kimlik artık ALT'ta (meta[1]).
        self.assertNotEqual(kimlik, meta[0]["kararli_kimlik"],
                             "bilinen sınır: üst yarı kimliğini kaybeder")
        self.assertEqual(kimlik, meta[1]["kararli_kimlik"],
                          "bilinen sınır: eski kimlik yanlışlıkla alt yarıya geçer")


class TopluOnayTemelTesti(unittest.TestCase):
    """istemcideki topluOnayla() yeni bir uç nokta EKLEMEZ; sayfadaki her
    'incele' kutusu için var olan /inceleme (``_inceleme_onayla``) uç
    noktasına Promise.all ile PARALEL istek atar (bkz. soru_kes_web.py Faz
    5.5). Bu testler o var olan sözleşmenin bir döngüyle çağrılınca doğru
    davrandığını doğrular — sunucu tarafında yeni kod yok, yalnız kullanım
    deseni; eşzamanlılık güvenliği için bkz. TopluOnayEszamanliTesti."""

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

    def test_sayfadaki_tum_incele_kutulari_tek_tek_onaylanabilir(self):
        analiz = _Analiz([
            _Aday([10, 20, 280, 120], .40, "incele"),
            _Aday([10, 130, 280, 230], .35, "incele"),
            _Aday([10, 240, 280, 340], .97, "otomatik"),
        ])
        self.assertTrue(web._v2_sonuclarini_sakla(_Profil(), [analiz]))

        meta = web._kutu_metalari(0)
        adaylar = [i for i, m in enumerate(meta)
                   if m["inceleme_durumu"] == "incele" and not m["onayli"]]
        self.assertEqual([0, 1], adaylar,
                          "topluOnayla'nın istemci filtresiyle aynı küme")

        for i in adaylar:
            sonuc = web._inceleme_onayla(0, i, True)
            self.assertTrue(sonuc["ok"])

        meta_sonra = web._kutu_metalari(0)
        self.assertTrue(meta_sonra[0]["onayli"])
        self.assertTrue(meta_sonra[1]["onayli"])
        # otomatik kutu zaten filtreye girmemişti, davranışı değişmemeli
        self.assertEqual("otomatik", meta_sonra[2]["inceleme_durumu"])
        self.assertFalse(meta_sonra[2].get("onayli"))

        # geri al senaryosu: aynı listeye onay=false uygulanınca hepsi geri döner
        for i in adaylar:
            web._inceleme_onayla(0, i, False)
        meta_geri = web._kutu_metalari(0)
        self.assertFalse(meta_geri[0]["onayli"])
        self.assertFalse(meta_geri[1]["onayli"])

    def test_reddedilen_kutu_topluOnayla_filtresine_hic_girmemeli(self):
        analiz = _Analiz([_Aday([10, 20, 280, 120], .05, "reddedildi")])
        self.assertTrue(web._v2_sonuclarini_sakla(_Profil(), [analiz]))
        meta = web._kutu_metalari(0)
        adaylar = [i for i, m in enumerate(meta)
                   if m["inceleme_durumu"] == "incele" and not m["onayli"]]
        self.assertEqual([], adaylar,
                          "reddedilen kutu istemci filtresine hiç girmemeli")
        with self.assertRaises(ValueError):
            web._inceleme_onayla(0, 0, True)


class TopluOnayEszamanliTesti(unittest.TestCase):
    """İnceleme bulgusu: istemci topluOnayla() sırayla değil Promise.all ile
    PARALEL istek atar. Bu test, sunucudaki _inceleme_onayla'nın KILIT altında
    çalıştığı için eşzamanlı çağrılarda veri kaybı (lost update) olmadığını —
    yani gerçek tarayıcı davranışının sunucu tarafında güvenli olduğunu —
    doğrular."""

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

    def test_ayni_sayfada_paralel_onaylar_veri_kaybetmez(self):
        analiz = _Analiz([
            _Aday([10, 20, 280, 100], .40, "incele"),
            _Aday([10, 110, 280, 190], .35, "incele"),
            _Aday([10, 200, 280, 280], .30, "incele"),
        ])
        self.assertTrue(web._v2_sonuclarini_sakla(_Profil(), [analiz]))

        hatalar = []

        def onayla(i):
            try:
                web._inceleme_onayla(0, i, True)
            except Exception as e:  # noqa: BLE001 — testte yakala, ayrı raporla
                hatalar.append(e)

        iplikler = [threading.Thread(target=onayla, args=(i,)) for i in range(3)]
        for t in iplikler:
            t.start()
        for t in iplikler:
            t.join()

        self.assertEqual([], hatalar)
        meta = web._kutu_metalari(0)
        self.assertTrue(all(m["onayli"] for m in meta),
                         "eşzamanlı çağrılardan hiçbiri kaybolmamalı")
        self.assertEqual(3, len({m["kararli_kimlik"] for m in meta}),
                          "her kutu ayrı kimlikle onaylanmış olmalı")


class WebJsFonksiyonVarligiTesti(unittest.TestCase):
    """'Buton var ama fonksiyon yok' regresyonunu önler (Faz 5.5/5.6): HTML
    şablonunda onclick ile referans verilen JS fonksiyonlarının gerçekten
    TANIMLANDIĞINI doğrular — yalnız çağrı değil, ``function ad(`` tanımı."""

    def test_toplu_onay_ve_galeri_ve_toast_fonksiyonlari_tanimli(self):
        for cagri in ('onclick="topluOnayla()"', 'onclick="galeriAc()"',
                      'onclick="galeriKapat()"'):
            self.assertIn(cagri, web.SAYFA, f"{cagri} HTML'de referans veriyor")
        for tanim in ("function topluOnayla(", "function galeriAc(",
                      "function galeriKapat(", "function galeriCikar(",
                      "function galeriIzgaraCiz(", "function toastGoster("):
            self.assertIn(tanim, web.SAYFA, f"{tanim} tanımlı olmalı")

    def test_toast_ve_galeri_dom_iskeleti_mevcut(self):
        for parca in ('id="toastAlan"', 'id="galeriIzgara"',
                      'id="galeriOverlay"', 'id="topluOnayBtn"'):
            self.assertIn(parca, web.SAYFA)


class IncelemeReviewDuzeltmeleriTesti(unittest.TestCase):
    """İnceleme bulguları (#1-#8) düzeltmelerinin JS şablonunda GERÇEKTEN
    mevcut olduğunu doğrulayan hafif regresyon testleri — 'düzeltildi sanıldı
    ama satır hiç eklenmedi' hatasına karşı."""

    def test_klavye_guard_textarea_ve_offsetparent_tabanli(self):
        # bulgu #1: Optik textarea'sında kısayolların yutulmaması
        self.assertIn("e.target.tagName==='TEXTAREA'", web.SAYFA)
        self.assertIn("function gorunurMu(", web.SAYFA)
        self.assertIn("gorunurMu('sahne')", web.SAYFA)
        self.assertIn("gorunurMu('duzenKart')", web.SAYFA)

    def test_n_o_klavye_gezinimi_tanimli(self):
        # bulgu #8: N/O kısayolları .ipuc metninde vaat ediliyordu ama yoktu
        self.assertIn("function incelemeSonrakineGit(", web.SAYFA)
        self.assertIn("function incelemeOdaktakiOnayla(", web.SAYFA)
        self.assertIn("incelemeSonrakineGit()", web.SAYFA)
        self.assertIn("incelemeOdaktakiOnayla()", web.SAYFA)

    def test_undo_yiginlari_basarisiz_adimda_tutarli_kalir(self):
        # bulgu #3: geriAl/yinele artık başarısız uygulamada yığın değiştirmiyor
        self.assertIn("function undoAdimUygula(", web.SAYFA)

    def test_onay_geri_yinele_kaydetsimdi_kosulsuz_bekler_ve_hata_kontrol_eder(self):
        # bulgu #2
        self.assertIn("async function onayGeriYinele(kayit,onay){\n  if(!(await kaydetSimdi())) return false;",
                       web.SAYFA)
        self.assertIn("hatalilar=sonuclar.filter(r=>r&&r.hata)", web.SAYFA)

    def test_toplu_onayla_kaydetsimdi_ile_baslar(self):
        # bulgu #4 (ilk turda düzeltildi) + bulgu #2/son tur (adaylar artık kaydetSimdi
        # SONRASINDA hesaplanıyor — sunucunun y-sıralı yanıtı kutu_no'ları kaydırmış olabilir)
        self.assertIn(
            "async function topluOnayla(){\n"
            "  // ÖNCE flush",
            web.SAYFA)
        self.assertIn(
            "if(!(await kaydetSimdi())) return;\n  const adaylar=incelemeAdaylari();\n"
            "  if(!adaylar.length) return;",
            web.SAYFA)

    def test_ince_kutu_bolme_korumasi_tanimli(self):
        # bulgu #6
        self.assertIn("MIN_BOL_YUKSEKLIK", web.SAYFA)
        self.assertIn("bölünemeyecek kadar ince", web.SAYFA)

    def test_galeri_kimligi_olay_delegasyonuyla_okunur(self):
        # bulgu #7 (son tur): inline onclick="galeriCikar('...')" yerine dataset + delegasyon —
        # htmlKacir'lı kimlik inline JS string bağlamında güvenilir değildi (&#39; geri çözülür)
        self.assertIn('data-kimlik="${htmlKacir(kml)}"', web.SAYFA)
        self.assertNotIn("onclick=\"galeriCikar(", web.SAYFA)
        self.assertIn("$('galeriIzgara').addEventListener('click',", web.SAYFA)
        self.assertIn("kart.dataset.kimlik", web.SAYFA)


class IncelemeReviewSonTurTesti(unittest.TestCase):
    """Kapanış incelemesinin 2 yeni orta + 3 küçük bulgusu (bkz. son review turu)
    için JS şablonundaki fiili düzeltmeleri doğrulayan regresyon testleri."""

    def test_undo_yinele_esZamanlilik_kilidi_tanimli(self):
        # bulgu #1: Cmd+Z basılı tutma (tuş tekrarı) artık geriAl/yinele'yi eşzamanlı
        # tetikleyip yığını bozamıyor
        self.assertIn("let undoMesgul=false;", web.SAYFA)
        self.assertIn("async function geriAl(){\n  if(undoMesgul) return;", web.SAYFA)
        self.assertIn("async function yinele(){\n  if(undoMesgul) return;", web.SAYFA)
        # pop'tan önce tepe kaydın hâlâ aynı olduğu doğrulanıyor (ekstra güvence katmanı)
        self.assertIn("if(geriYigin[geriYigin.length-1]===k){ geriYigin.pop();", web.SAYFA)
        self.assertIn("if(ileriYigin[ileriYigin.length-1]===k){ ileriYigin.pop();", web.SAYFA)

    def test_incelemeSonrakineGit_throttle_ve_baslangica_donus(self):
        # bulgu #4: N'e art arda basma throttle'ı + hiçbir yerde aday yoksa başlangıç sayfasına dönüş
        self.assertIn("let gezinmeMesgul=false;", web.SAYFA)
        self.assertIn("async function incelemeSonrakineGit(){\n  if(gezinmeMesgul) return;", web.SAYFA)
        self.assertIn("baslangicSayfa", web.SAYFA)

    def test_onay_geri_yinele_kismi_hatada_false_doner(self):
        # bulgu #5: kısmi hata artık "başarı" sayılıp yığından sessizce düşürülmüyor
        self.assertIn(
            "toastGoster(`${liste.length-hatalilar.length} kutu ${onay?'onayı yinelendi':"
            "'onayı geri alındı'} · `+\n        `${hatalilar.length} hata: ${hatalilar[0].hata}`,'hata');\n"
            "      return false;",
            web.SAYFA)

    def test_incelemeOnayla_da_kaydetsimdi_bekler(self):
        # bulgu #5: O kısayolu / badge tıklaması da #2 ile aynı sınıf hataya karşı korunuyor
        self.assertIn(
            "async function incelemeOnayla(i,onay){\n"
            "  if(!(await kaydetSimdi())) return;",
            web.SAYFA)


if __name__ == "__main__":
    unittest.main()
