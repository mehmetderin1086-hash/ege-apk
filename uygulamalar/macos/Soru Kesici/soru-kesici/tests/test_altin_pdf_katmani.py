#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PDF metin katmanından bağımsız altın veri çıkarma regresyonları."""

import ast
import contextlib
import io
import json
import os
import tempfile
import types
import unittest

import fitz

import altin_pdf_katmani as apk

KOK = os.path.dirname(os.path.abspath(apk.__file__))
YENI_ALTINLAR = (
    "tyt2", "aytsay", "aytea", "tytbiyo",
    "cikmistyt", "cikmisayt", "ykstyt2026", "yksayt2026",
)

# Motorla aynı ölçüde bağımsız kalması gereken modüller. ``dogrula`` da
# listede çünkü o modül ``soru_kes``i import ediyor: üreticiye bağlanırsa
# altın veri motorun kendi çıktısına dolaylı olarak bağımlı hâle gelir.
YASAKLI_BAGIMLILIKLAR = {"soru_kes", "dogrula"}


def _sahte_satir(x0, y0, x1, y1, metin):
    return {"box": (x0, y0, x1, y1), "metin": metin}


def _sahte_capa(y0, *, sutun=0, numara=1):
    return {
        "deneme": 1, "konu": "turkce", "numara": numara, "page": 1,
        "column": sutun, "word_box": [36.0, y0, 46.0, y0 + 13.0],
    }


def _sahte_soru(**degis):
    soru = {
        "id": "d1-turkce-q1",
        "number": 1,
        "box": [31.0, 76.0, 275.0, 300.0],
        "type": "coktan_secmeli",
        "final_output": {"question_number": 1, "part_count": 1},
        "required_regions": [
            {"page": 1, "box": [36.0, 80.0, 240.0, 93.0], "kind": "metin"},
        ],
        "forbidden_regions": [
            {"page": 1, "box": [36.0, 310.0, 240.0, 323.0],
             "kind": "komsu_soru"},
        ],
    }
    soru.update(degis)
    return soru


def _sahte_altin(sorular=None, *, sayfalar=None):
    """``_ciktiyi_denetle`` için asgari geçerli golden-v2 belgesi."""
    if sayfalar is None:
        sayfalar = [{
            "page": 1, "width": 552.756, "height": 779.528,
            "role": "soru",
            "questions": [_sahte_soru()] if sorular is None else sorular,
        }]
    return {
        "schema_version": apk.SEMA_SURUMU,
        "dataset": {"id": "test", "kind": "annotated", "split": "holdout"},
        "documents": [{
            "id": "sha256:0", "source": "t.pdf", "source_sha256": "0",
            "pages": sayfalar,
        }],
    }


class AltinPdfKatmaniTesti(unittest.TestCase):
    def test_turkce_buyuk_i_normalizasyonu(self):
        self.assertIn(
            "sosyal bilimler testi",
            apk._ascii("SOSYAL BİLİMLER TESTİ"))
        self.assertIn(
            "asagidaki parcaya gore",
            apk._ascii("Aşağıdaki parçaya göre"))
        self.assertFalse(apk._cevap_anahtari_sayfasi(
            apk._ascii("Cevap anahtarına bakınız. SOSYAL BİLİMLER TESTİ")))
        self.assertTrue(apk._cevap_anahtari_sayfasi(apk._ascii(
            "CEVAP ANAHTARI TÜRKÇE TESTİ SOSYAL BİLİMLER TESTİ "
            "TEMEL MATEMATİK TESTİ FEN BİLİMLERİ TESTİ")))

    def test_soru_capasi_ve_govde_sonunu_ayirir(self):
        with tempfile.TemporaryDirectory(prefix="altin_pdf_") as gecici:
            yol = os.path.join(gecici, "iki-soru.pdf")
            doc = fitz.open()
            page = doc.new_page(width=552.756, height=779.528)
            page.insert_text((36, 48), "YKS DENEMELERI 1. DENEME")
            page.insert_text((300, 48), "TYT - TURKCE TESTI")
            page.insert_text((36, 90), "1. Birinci soru metni")
            page.insert_text((60, 120), "A) Secenek")
            # PDF'de görünmeyen/dekoratif çizimler soru gövdesinin altını
            # yapay olarak uzatmamalı.
            page.draw_rect(fitz.Rect(50, 165, 250, 210))
            page.insert_text((36, 230), "2. Ikinci soru metni")
            page.insert_text((60, 260), "A) Secenek")
            doc.save(yol)
            doc.close()

            with fitz.open(yol) as acik:
                page = acik[0]
                bolum = apk._konu_ve_deneme(page)
                self.assertEqual((1, "turkce"), bolum)
                capalar = apk._fiziksel_capalar(page, 1, bolum)
                self.assertEqual([1, 2], [c["numara"] for c in capalar])
                kutu = apk._govde_kutusu(
                    page, capalar[0], capalar, apk._gorsel_kutular(page))
                self.assertLess(kutu[3], 150)
                self.assertLess(kutu[3], capalar[1]["word_box"][1])

    def test_beklenmeyen_yinelenen_capayi_reddeder(self):
        ortak = {
            "deneme": 1, "konu": "turkce", "numara": 1,
            "column": 0, "word_box": [36, 80, 44, 92],
        }
        a = dict(ortak, page=1)
        b = dict(ortak, page=3)
        with self.assertRaisesRegex(ValueError, "tek bağımsız çapa"):
            apk._capalari_sec([a, b], [1])


class BagimsizlikTesti(unittest.TestCase):
    """Altın veri motordan bağımsız üretilmelidir."""

    def test_motor_ve_olcum_modullerini_import_etmez(self):
        # sys.modules'e bakmak yanıltıcı olur: test koşumunda başka modüller
        # soru_kes'i zaten yüklemiş olabilir. Kaynak metnindeki import
        # düğümlerini taramak deterministiktir.
        with open(apk.__file__, encoding="utf-8") as dosya:
            kaynak = dosya.read()
        bulunan = set()
        for dugum in ast.walk(ast.parse(kaynak)):
            if isinstance(dugum, ast.Import):
                bulunan.update(ad.name.split(".")[0] for ad in dugum.names)
            elif isinstance(dugum, ast.ImportFrom) and dugum.module:
                bulunan.add(dugum.module.split(".")[0])
        self.assertEqual(
            set(), bulunan & YASAKLI_BAGIMLILIKLAR,
            "altin_pdf_katmani motor/ölçüm modüllerine bağlanmamalı")


class BolgeUretimiTesti(unittest.TestCase):
    def test_sekil_gorseli_gerekli_bolge_olur(self):
        govde = [31.0, 76.0, 275.0, 300.0]
        satirlar = [
            _sahte_satir(36.0, 80.0, 240.0, 93.0, "1. Soru metni"),
            _sahte_satir(55.0, 250.0, 200.0, 263.0, "A) bir"),
            _sahte_satir(55.0, 268.0, 200.0, 281.0, "B) iki"),
            _sahte_satir(55.0, 286.0, 200.0, 299.0, "C) uc"),
        ]
        figurler = [
            (60.0, 110.0, 200.0, 220.0),   # gerçek şekil
            (60.0, 110.0, 70.0, 118.0),    # kenarı küçük, elenir
            (60.0, 400.0, 200.0, 500.0),   # gövdenin dışında, elenir
        ]
        gerekli, _yasak = apk._bolgeleri_uret(
            7, _sahte_capa(80.0), govde, satirlar, [_sahte_capa(80.0)],
            figurler)
        sekiller = [b for b in gerekli if b["kind"] == "sekil"]
        self.assertEqual(1, len(sekiller))
        self.assertEqual([60.0, 110.0, 200.0, 220.0], sekiller[0]["box"])
        self.assertEqual(7, sekiller[0]["page"])

    def test_sik_blogu_ve_ilk_satir_gerekli_bolge_olur(self):
        govde = [31.0, 76.0, 275.0, 300.0]
        satirlar = [
            _sahte_satir(36.0, 80.0, 46.0, 93.0, "1.\t"),
            _sahte_satir(55.0, 80.0, 240.0, 93.0, "Soru metninin ilk satiri"),
            _sahte_satir(55.0, 100.0, 240.0, 113.0, "ikinci satir"),
            # Şıklar tek satırda yan yana; işaret satır başında olmayabilir.
            _sahte_satir(55.0, 250.0, 260.0, 263.0,
                         "A) 12    B) 14    C) 16    D) 18    E) 20"),
        ]
        gerekli, _yasak = apk._bolgeleri_uret(
            3, _sahte_capa(80.0), govde, satirlar, [_sahte_capa(80.0)], [])
        turler = {b["kind"]: b["box"] for b in gerekli}
        self.assertEqual([36.0, 80.0, 240.0, 93.0], turler["metin"])
        self.assertEqual([55.0, 250.0, 260.0, 263.0], turler["secenek"])

    def test_komsu_capa_satirlari_yasak_bolge_olur(self):
        govde = [31.0, 76.0, 275.0, 196.0]
        onceki = _sahte_capa(20.0, numara=1)
        capa = _sahte_capa(80.0, numara=2)
        sonraki = _sahte_capa(200.0, numara=3)
        satirlar = [
            _sahte_satir(36.0, 20.0, 240.0, 33.0, "1. Onceki soru"),
            _sahte_satir(55.0, 50.0, 240.0, 63.0, "onceki sorunun son satiri"),
            _sahte_satir(36.0, 80.0, 240.0, 93.0, "2. Bu soru"),
            _sahte_satir(55.0, 150.0, 240.0, 163.0, "A) bir  B) iki  C) uc"),
            _sahte_satir(36.0, 200.0, 240.0, 213.0, "3. Sonraki soru"),
        ]
        _gerekli, yasak = apk._bolgeleri_uret(
            5, capa, govde, satirlar, [onceki, capa, sonraki], [])
        self.assertEqual(["komsu_soru", "komsu_soru"],
                         [b["kind"] for b in yasak])
        # Sonraki sorunun ilk satırı: üst kenarından pay kadar kırpılır.
        self.assertEqual([36.0, 202.0, 240.0, 213.0], yasak[0]["box"])
        # Önceki sorunun son satırı: alt kenarından pay kadar kırpılır.
        self.assertEqual([55.0, 50.0, 240.0, 61.0], yasak[1]["box"])
        for bolge in yasak:
            self.assertIsNone(apk._kesisim(bolge["box"], govde))

    def test_yasak_bolge_ortak_uyaranla_kesisirse_atilir(self):
        # Ortak uyaranlı soruda önceki soru metni uyaran kutusunun içinde
        # kalabilir; orası kesime meşru biçimde girer, sızıntı değildir.
        govde = [31.0, 76.0, 275.0, 196.0]
        onceki = _sahte_capa(20.0, numara=1)
        capa = _sahte_capa(80.0, numara=2)
        satirlar = [
            _sahte_satir(36.0, 20.0, 240.0, 33.0, "1. Onceki soru"),
            _sahte_satir(55.0, 50.0, 240.0, 63.0, "onceki sorunun son satiri"),
            _sahte_satir(36.0, 80.0, 240.0, 93.0, "2. Bu soru"),
        ]
        _gerekli, yasak = apk._bolgeleri_uret(
            5, capa, govde, satirlar, [onceki, capa], [],
            [(31.0, 10.0, 275.0, 70.0), govde])
        self.assertEqual([], yasak)

    def test_gerekli_bolge_govdeye_kirpilir(self):
        # Değişmez: altın kesimin kendisi her zaman tam puan almalı. Satır
        # kutusu gövdenin üstüne birkaç punto taşarsa bölge kırpılmazsa
        # kusursuz bir kesim bile "eksik kapsama" görünür.
        govde = [31.0, 76.0, 275.0, 300.0]
        satirlar = [
            _sahte_satir(36.0, 70.0, 240.0, 90.0, "1. Soru metni"),
            _sahte_satir(55.0, 250.0, 260.0, 310.0, "A) bir B) iki C) uc"),
        ]
        gerekli, _yasak = apk._bolgeleri_uret(
            2, _sahte_capa(80.0), govde, satirlar, [_sahte_capa(80.0)], [])
        turler = {b["kind"]: b["box"] for b in gerekli}
        self.assertEqual(76.0, turler["metin"][1])
        self.assertEqual(300.0, turler["secenek"][3])

    def test_govdeyi_yarilayan_sekil_gerekli_bolge_olmaz(self):
        # Kümenin ezici çoğunluğu gövde dışındaysa şekil komşuya aittir;
        # bu soruya zorunlu kılınırsa kesim asla tam puan alamaz.
        govde = [31.0, 76.0, 275.0, 300.0]
        satirlar = [_sahte_satir(36.0, 80.0, 240.0, 93.0, "1. Soru")]
        gerekli, _yasak = apk._bolgeleri_uret(
            2, _sahte_capa(80.0), govde, satirlar, [_sahte_capa(80.0)],
            [(60.0, 250.0, 200.0, 400.0)])
        self.assertEqual([], [b for b in gerekli if b["kind"] == "sekil"])

    def test_tekrarlayan_dizgi_susu_sekil_sayilmaz(self):
        # Bu korpusta ``get_drawings`` her sayfada aynı koordinatlarda
        # görünmez InDesign süsleri döndürüyor; elenmezse hemen her soruya
        # sahte bir "şekil" bölgesi eklenir.
        sus = fitz.Rect(60.0, 110.0, 200.0, 220.0)
        gercek = fitz.Rect(60.0, 400.0, 200.0, 500.0)
        sayfalar = {no: [fitz.Rect(sus)] for no in range(1, 13)}
        sayfalar[7].append(gercek)

        dekor = apk._dekor_kutulari(sayfalar)
        self.assertIn(apk._kutu_anahtari(
            (sus.x0, sus.y0, sus.x1, sus.y1)), dekor)
        self.assertNotIn(apk._kutu_anahtari(
            (gercek.x0, gercek.y0, gercek.x1, gercek.y1)), dekor)
        self.assertEqual(
            [(60.0, 400.0, 200.0, 500.0)],
            apk._figur_kumeleri(sayfalar[7], dekor))

        # 10 sayfanın altında tekrar sayımı güvenilir değil: süzgeç kapalı.
        az = {no: [fitz.Rect(sus)] for no in range(1, 10)}
        self.assertEqual(set(), apk._dekor_kutulari(az))

    def test_ayirac_ve_sayfa_cizgisi_gorsel_gurultudur(self):
        self.assertTrue(apk._gorsel_gurultu((278.0, 60.0, 279.5, 700.0)))
        self.assertTrue(apk._gorsel_gurultu((20.0, 60.0, 530.0, 62.0)))
        self.assertFalse(apk._gorsel_gurultu((60.0, 110.0, 200.0, 220.0)))


class CiktiDenetimiTesti(unittest.TestCase):
    """``dogrula`` yerine geçen bağımsız denetim gerçekten kapı olmalı."""

    def test_gecerli_belgeyi_kabul_eder(self):
        apk._ciktiyi_denetle(_sahte_altin())

    def test_sema_surumunu_zorunlu_kilar(self):
        altin = _sahte_altin()
        altin["schema_version"] = "soru-kesici.golden/v1"
        with self.assertRaisesRegex(ValueError, "schema_version"):
            apk._ciktiyi_denetle(altin)

    def test_yinelenen_soru_kimligini_reddeder(self):
        altin = _sahte_altin([_sahte_soru(), _sahte_soru()])
        with self.assertRaisesRegex(ValueError, "Yinelenen soru kimliği"):
            apk._ciktiyi_denetle(altin)

    def test_govdeden_tasan_gerekli_bolgeyi_reddeder(self):
        altin = _sahte_altin([_sahte_soru(required_regions=[
            {"page": 1, "box": [36.0, 80.0, 240.0, 320.0], "kind": "metin"},
        ])])
        with self.assertRaisesRegex(ValueError, "gövdenin dışına"):
            apk._ciktiyi_denetle(altin)

    def test_govdeye_giren_yasak_bolgeyi_reddeder(self):
        altin = _sahte_altin([_sahte_soru(forbidden_regions=[
            {"page": 1, "box": [36.0, 290.0, 240.0, 323.0],
             "kind": "komsu_soru"},
        ])])
        with self.assertRaisesRegex(ValueError, "gövdeyle kesişiyor"):
            apk._ciktiyi_denetle(altin)

    def test_gecersiz_bolge_turunu_reddeder(self):
        altin = _sahte_altin([_sahte_soru(required_regions=[
            {"page": 1, "box": [36.0, 80.0, 240.0, 93.0], "kind": "figure"},
        ])])
        with self.assertRaisesRegex(ValueError, "geçersiz tür"):
            apk._ciktiyi_denetle(altin)

    def test_bilinmeyen_ortak_uyaran_referansini_reddeder(self):
        altin = _sahte_altin([_sahte_soru(shared_stimulus_id="yok")])
        with self.assertRaisesRegex(ValueError, "ortak uyaran bulunamadı"):
            apk._ciktiyi_denetle(altin)

    def test_parca_kendi_sayfasinin_sinirlariyla_denetlenir(self):
        # Uyaran parçası başka sayfada; o sayfa daha darsa taşma orada
        # yakalanmalı, gövde sayfasının boyutuyla değil.
        soru = _sahte_soru(parts=[
            {"page": 2, "box": [31.0, 40.0, 300.0, 120.0],
             "kind": "ortak_uyaran"},
            {"page": 1, "box": [31.0, 76.0, 275.0, 300.0],
             "kind": "soru_govdesi"},
        ])
        soru.pop("box")
        altin = _sahte_altin(sayfalar=[
            {"page": 1, "width": 552.756, "height": 779.528,
             "role": "soru", "questions": [soru]},
            {"page": 2, "width": 280.0, "height": 779.528,
             "role": "soru", "questions": []},
        ])
        with self.assertRaisesRegex(ValueError, "sayfa sınırları"):
            apk._ciktiyi_denetle(altin)

    def test_belgede_olmayan_parca_sayfasini_reddeder(self):
        soru = _sahte_soru(parts=[
            {"page": 9, "box": [31.0, 40.0, 275.0, 120.0],
             "kind": "ortak_uyaran"},
            {"page": 1, "box": [31.0, 76.0, 275.0, 300.0],
             "kind": "soru_govdesi"},
        ])
        soru.pop("box")
        with self.assertRaisesRegex(ValueError, "belgede olmayan sayfa"):
            apk._ciktiyi_denetle(_sahte_altin([soru]))

    def test_iki_parcaya_bolunen_gerekli_bolge_kabul_edilir(self):
        # Kapsama parça parça değil, parçaların BİRLEŞİMİ üzerinden
        # ölçülmeli; ``dogrula`` da böyle hesaplıyor. Tek tek bakılırsa
        # sınırda duran meşru bir bölge yanlışlıkla reddedilir.
        soru = _sahte_soru(parts=[
            {"page": 1, "box": [31.0, 76.0, 275.0, 200.0],
             "kind": "soru_govdesi"},
            {"page": 1, "box": [31.0, 200.0, 275.0, 300.0],
             "kind": "devam"},
        ], required_regions=[
            {"page": 1, "box": [40.0, 150.0, 200.0, 250.0], "kind": "metin"},
        ])
        soru.pop("box")
        apk._ciktiyi_denetle(_sahte_altin([soru]))

    def test_birlesim_alani_cift_saymaz(self):
        self.assertEqual(
            100.0,
            apk._birlesim_alani([(0.0, 0.0, 10.0, 10.0),
                                 (0.0, 0.0, 10.0, 10.0)]))
        self.assertEqual(
            175.0,
            apk._birlesim_alani([(0.0, 0.0, 10.0, 10.0),
                                 (5.0, 5.0, 15.0, 15.0)]))
        self.assertEqual(0.0, apk._birlesim_alani([]))


class ProfilCozumlemeTesti(unittest.TestCase):
    """Profil katmanı bugünkü davranışı bozmadan genelleşmeli."""

    def test_profil_verilmezse_gomulu_varsayilan_kullanilir(self):
        self.assertIs(apk.VARSAYILAN_PROFIL, apk.profil_coz(None))
        self.assertIs(apk.VARSAYILAN_PROFIL, apk.profil_coz(""))

    def test_dosyadaki_varsayilan_profil_gomuluyle_ayni(self):
        # DEĞİŞMEZ: JSON'daki ``mebi-tyt-deneme`` ile modülün gömülü
        # varsayılanı ayrışırsa, dosyayı düzenleyen biri "aynı" sandığı
        # profille tyt-1 altınını sessizce değiştirebilir.
        json_profil = apk.profil_coz("mebi-tyt-deneme")
        gomulu = apk.VARSAYILAN_PROFIL
        self.assertEqual(gomulu.sutunlar, json_profil.sutunlar)
        self.assertEqual(gomulu.capa_hizasi, json_profil.capa_hizasi)
        self.assertEqual(gomulu.capa_toleransi, json_profil.capa_toleransi)
        self.assertEqual(gomulu.numara_azami_hane,
                         json_profil.numara_azami_hane)
        self.assertEqual(gomulu.kenar_paylari, json_profil.kenar_paylari)
        self.assertEqual(gomulu.bolum_kipi, json_profil.bolum_kipi)
        self.assertEqual(gomulu.konular, json_profil.konular)
        self.assertEqual(gomulu.deneme_deseni.pattern,
                         json_profil.deneme_deseni.pattern)
        self.assertEqual(gomulu.aralik_deseni.pattern,
                         json_profil.aralik_deseni.pattern)

    def test_kenar_paylari_tyt1_sayfasinda_mutlak_degerleri_verir(self):
        # 68 / 730 / 733 bugünkü altının ölçüldüğü sınırlar; orana çevirme
        # bunları birebir geri vermezse taban kayar.
        doc = fitz.open()
        try:
            page = doc.new_page(
                width=552.7559814453125,
                height=apk.VARSAYILAN_SAYFA_YUKSEKLIGI)
            self.assertEqual(
                (68.0, 730.0, 733.0), apk.VARSAYILAN_PROFIL.y_sinirlari(page))
        finally:
            doc.close()

    def test_kenar_paylari_sayfa_boyutuyla_olceklenir(self):
        doc = fitz.open()
        try:
            page = doc.new_page(
                width=300.0, height=apk.VARSAYILAN_SAYFA_YUKSEKLIGI * 2)
            ust, alt, govde = apk.VARSAYILAN_PROFIL.y_sinirlari(page)
            self.assertAlmostEqual(136.0, ust, places=6)
            self.assertAlmostEqual(1460.0, alt, places=6)
            self.assertAlmostEqual(1466.0, govde, places=6)
        finally:
            doc.close()

    def test_dosyadaki_profiller_yuklenir(self):
        profiller = apk.profilleri_yukle()
        self.assertLessEqual(
            {"mebi-tyt-deneme", "mebi-2col", "osym-2026"}, set(profiller))
        self.assertEqual("dizi", profiller["mebi-2col"].bolum_kipi)
        self.assertEqual("x1", profiller["osym-2026"].capa_hizasi)
        self.assertFalse(profiller["osym-2026"].beklenen_adetler)
        self.assertTrue(apk.VARSAYILAN_PROFIL.beklenen_adetler)

    def test_bilinmeyen_profil_reddedilir(self):
        with self.assertRaisesRegex(ValueError, "bilinmeyen profil"):
            apk.profil_coz("yok-boyle-bir-profil")

    def test_gecersiz_profil_ayari_reddedilir(self):
        with self.assertRaisesRegex(ValueError, "bolum_kipi"):
            apk.Profil("t", sutunlar=apk.SUTUNLAR, bolum_kipi="karma")
        with self.assertRaisesRegex(ValueError, "capa_hizasi"):
            apk.Profil("t", sutunlar=apk.SUTUNLAR, capa_hizasi="orta",
                       bolum_kipi="dizi")
        with self.assertRaisesRegex(ValueError, "konular"):
            apk.Profil("t", sutunlar=apk.SUTUNLAR, bolum_kipi="konu")

    def test_sagdan_hizali_capa_yonerge_maddesini_eler(self):
        # ÖSYM 2026'da soru numaraları x1=56,9'da biter, test yönergesinin
        # "1."/"2." maddeleri x1=54,4'te. Sol kenara bakılırsa ikisi de aynı
        # bantta görünür; ayıran tek şey sağ kenardır.
        profil = apk.profil_coz("osym-2026")
        self.assertEqual(0, apk._sutun_no(49.4, 56.9, profil))
        self.assertEqual(0, apk._sutun_no(44.4, 56.9, profil))
        self.assertIsNone(apk._sutun_no(46.9, 54.4, profil))
        self.assertEqual(1, apk._sutun_no(319.3, 331.8, profil))
        self.assertEqual(1, apk._sutun_no(322.3, 329.8, profil))


class SerbestKipTesti(unittest.TestCase):
    """Adet bilgisi olmayan kitapta zincir doğrulanır, adet dayatılmaz."""

    @staticmethod
    def _capa(numara, *, page=1, y0=80.0, sutun=0, bolum=1, konu=""):
        return {
            "deneme": bolum, "konu": konu, "numara": numara, "page": page,
            "column": sutun, "word_box": [36.0, y0, 48.0, y0 + 13.0],
        }

    def test_kati_kip_eksik_soruyu_hata_sayar(self):
        capalar = [self._capa(1, konu="turkce", bolum=1)]
        with self.assertRaisesRegex(ValueError, "tek bağımsız çapa"):
            apk._capalari_sec(capalar, [1])

    def test_serbest_kip_eksik_soruyu_hata_saymaz(self):
        capalar = [self._capa(1, konu="turkce", bolum=1)]
        rapor = {}
        secilen, yinelenen = apk._capalari_sec(
            capalar, [1], serbest=True, rapor=rapor)
        self.assertEqual(1, len(secilen))
        self.assertEqual([], yinelenen)
        self.assertEqual([], rapor["cozulmeyen"])

    def test_serbest_kip_cozulemeyen_tekrari_raporlar(self):
        profil = apk.profil_coz("mebi-2col")
        capalar = [self._capa(5, page=1, y0=100.0),
                   self._capa(5, page=4, y0=400.0)]
        rapor = {}
        secilen, yinelenen = apk._capalari_sec(
            capalar, [1], profil, serbest=True, rapor=rapor)
        self.assertEqual([1], [c["page"] for c in secilen])
        self.assertEqual([4], [c["page"] for c in yinelenen])
        self.assertEqual(1, len(rapor["cozulmeyen"]))
        self.assertEqual(5, rapor["cozulmeyen"][0]["numara"])

    def test_zincir_eksik_numarayi_bildirir(self):
        profil = apk.profil_coz("mebi-2col")
        capalar = [self._capa(n, y0=80.0 + 20 * n) for n in (1, 2, 4)]
        rapor = {}
        apk._capalari_sec(capalar, [1], profil, serbest=True, rapor=rapor)
        self.assertEqual(1, len(rapor["zincir"]))
        self.assertEqual([3], rapor["zincir"][0]["eksik"])
        self.assertFalse(rapor["zincir"][0]["birden_baslamiyor"])

    def test_zincir_birden_baslamayan_bolumu_bildirir(self):
        profil = apk.profil_coz("mebi-2col")
        capalar = [self._capa(n, y0=80.0 + 20 * n) for n in (4, 5)]
        rapor = {}
        apk._capalari_sec(capalar, [1], profil, serbest=True, rapor=rapor)
        self.assertTrue(rapor["zincir"][0]["birden_baslamiyor"])

    def test_numara_dususu_yeni_bolum_baslatir(self):
        capalar = [
            self._capa(1, page=1, y0=100.0), self._capa(2, page=1, y0=300.0),
            self._capa(1, page=2, y0=100.0), self._capa(2, page=2, y0=300.0),
        ]
        apk._bolumlere_ayir(capalar)
        self.assertEqual([1, 1, 2, 2], [c["deneme"] for c in capalar])
        self.assertEqual(
            {"b1-q1", "b1-q2", "b2-q1", "b2-q2"},
            {apk._soru_kimligi(c["deneme"], c["konu"], c["numara"])
             for c in capalar})

    def test_ayni_numara_yeni_bolum_saymaz(self):
        # Sayfa devrinde aynı numaranın iki kez basılması bilinen bir dizgi
        # durumu; bölüm sınırı sanılırsa kitap ikiye bölünür.
        capalar = [
            self._capa(7, page=1, y0=600.0), self._capa(7, page=2, y0=90.0),
            self._capa(8, page=2, y0=300.0),
        ]
        apk._bolumlere_ayir(capalar)
        self.assertEqual([1, 1, 1], [c["deneme"] for c in capalar])

    def test_uzak_sayfadaki_ayni_numara_yeni_bolum_baslatir(self):
        # Ölçüm büyük belgede sayfaları seyrek örnekliyor; o zaman iki ayrı
        # testin aynı numarası uzak sayfalarda yan yana gelir. Komşuluk
        # kontrolü olmazsa gerçek bir soru "yinelenen baskı" sanılıp düşer.
        capalar = [
            self._capa(36, page=301, y0=443.6),
            self._capa(36, page=311, y0=79.0),
        ]
        apk._bolumlere_ayir(capalar)
        self.assertEqual([1, 2], [c["deneme"] for c in capalar])
        rapor = {}
        secilen, yinelenen = apk._capalari_sec(
            capalar, [1], apk.profil_coz("mebi-2col"), serbest=True,
            rapor=rapor)
        self.assertEqual(2, len(secilen))
        self.assertEqual([], yinelenen)
        self.assertEqual([], rapor["cozulmeyen"])

    def test_sayfa_listesi_virgulle_verilebilir(self):
        # Örneklenen sayfa kümesi bitişik değil; altın tam o kümeyi
        # kapsayamazsa ölçüm altınla hizalanmaz.
        self.assertEqual(
            [1, 9, 17, 18, 19],
            apk._aralik("1,9,17-19", alt=1, ust=400, ad="sayfalar"))
        self.assertEqual(
            [13, 14, 15],
            apk._aralik("13-15", alt=1, ust=400, ad="sayfalar"))
        with self.assertRaisesRegex(ValueError, "aralığında olmalı"):
            apk._aralik("1,500", alt=1, ust=400, ad="sayfalar")
        with self.assertRaisesRegex(ValueError, "bekleniyor"):
            apk._aralik("1,a", alt=1, ust=400, ad="sayfalar")

    def test_okuma_sirasi_sutun_sutun_ilerler(self):
        sag = self._capa(3, page=1, y0=90.0, sutun=1)
        sol_alt = self._capa(2, page=1, y0=400.0, sutun=0)
        sol_ust = self._capa(1, page=1, y0=90.0, sutun=0)
        sirali = apk._bolumlere_ayir([sag, sol_alt, sol_ust])
        self.assertEqual([1, 2, 3], [c["numara"] for c in sirali])
        self.assertEqual([1, 1, 1], [c["deneme"] for c in sirali])


class CapaTuretmeTesti(unittest.TestCase):
    def _pdf(self, gecici):
        yol = os.path.join(gecici, "iki-sutun.pdf")
        doc = fitz.open()
        for _sayfa in range(4):
            page = doc.new_page(width=552.756, height=779.528)
            for i in range(5):
                y = 100 + i * 120
                page.insert_text((36, y), f"{i + 1}. Sol sutun sorusu")
                page.insert_text((287.7, y), f"{i + 6}. Sag sutun sorusu")
        doc.save(yol)
        doc.close()
        return yol

    def test_capalar_histogramdan_turetilir(self):
        profil = apk.Profil(
            "turetilen", sutunlar=None, bolum_kipi="dizi",
            capa_toleransi=4.0,
            sutun_turetme={"asgari_adet": 5, "sol_payi": 5.0,
                           "genislik": 244.0})
        with tempfile.TemporaryDirectory(prefix="altin_turet_") as gecici:
            yol = self._pdf(gecici)
            with fitz.open(yol) as doc:
                gunluk = io.StringIO()
                with contextlib.redirect_stderr(gunluk):
                    sutunlar = apk._capalari_turet(doc, [1, 2, 3, 4], profil)
        self.assertEqual(2, len(sutunlar))
        self.assertAlmostEqual(36.0, sutunlar[0]["capa"], places=1)
        self.assertAlmostEqual(287.7, sutunlar[1]["capa"], places=1)
        self.assertAlmostEqual(31.0, sutunlar[0]["x0"], places=1)
        # İnsan doğrulayabilsin diye türetilen çapalar stderr'e basılır.
        self.assertIn("türetilen sütun çapaları", gunluk.getvalue())

    def test_capa_turetilemezse_hata_verir(self):
        profil = apk.Profil(
            "turetilen", sutunlar=None, bolum_kipi="dizi",
            sutun_turetme={"asgari_adet": 500})
        with tempfile.TemporaryDirectory(prefix="altin_turet_") as gecici:
            yol = self._pdf(gecici)
            with fitz.open(yol) as doc:
                with self.assertRaisesRegex(ValueError, "türetilemedi"):
                    apk._capalari_turet(doc, [1], profil)


class AtlanacakSayfaTesti(unittest.TestCase):
    def test_yonerge_sayfasinda_capa_aranmaz(self):
        profil = apk.profil_coz("mebi-2col")
        with tempfile.TemporaryDirectory(prefix="altin_atla_") as gecici:
            yol = os.path.join(gecici, "aciklama.pdf")
            doc = fitz.open()
            page = doc.new_page(width=552.756, height=779.528)
            page.insert_text((36, 90), "ACIKLAMA")
            page.insert_text(
                (287.7, 200), "1. Bu kitapcikta 125 soru bulunmaktadir.")
            doc.save(yol)
            doc.close()
            with fitz.open(yol) as acik:
                sayfa = acik[0]
                self.assertTrue(apk._sayfa_atlanir(sayfa, profil))
                self.assertFalse(
                    apk._sayfa_atlanir(sayfa, apk.VARSAYILAN_PROFIL))


class YeniAltinlarTesti(unittest.TestCase):
    """Profille üretilen altınlar da bağımsız denetimden geçmeli."""

    def test_uretilen_altinlar_denetimden_gecer(self):
        bulunan = 0
        for ad in YENI_ALTINLAR:
            yol = os.path.join(KOK, "kalite", "altin", f"{ad}.json")
            if not os.path.exists(yol):
                continue
            bulunan += 1
            with open(yol, encoding="utf-8") as kaynak:
                altin = json.load(kaynak)
            with self.subTest(altin=ad):
                apk._ciktiyi_denetle(altin)
                sorular = [
                    soru for belge in altin["documents"]
                    for sayfa in belge["pages"] for soru in sayfa["questions"]
                ]
                self.assertGreater(len(sorular), 0)
                # Bölge üretimi yeni kitaplarda da çalışmalı: her sorunun en
                # az bir gerekli bölgesi olmalı, yoksa kesim kalitesi yalnız
                # IoU ile ölçülür ve içerik kaybı görünmez.
                self.assertTrue(all(
                    soru.get("required_regions") for soru in sorular))
        self.assertGreater(bulunan, 0, "yeni altın dosyası bulunamadı")


if __name__ == "__main__":
    unittest.main()


class FiligranFiltresiTesti(unittest.TestCase):
    """Filigran glifleri altın kutusunu şişiriyordu.

    Ölçülen gerçek vaka (yks_tyt_2026 s3): sayfayı çapraz kesen ÖSYM
    damgasının tek bir 'Y' harfi, bbox 189×189 pt, merkezi sol sütuna düşüyor
    ve _govde_kutusu onu içerik sanıp soru kutusunu 46 pt aşağı uzatıyordu.
    Altın bozuluyor, motor haksız yere cezalandırılıyordu: ölçülen F1@0,75
    0,4800 idi, filtreyle 0,6240'a çıktı — motor kodunda tek satır değişmeden.
    """

    class _Sayfa:
        rect = types.SimpleNamespace(height=864.6, width=595.3)

    SUTUN = {"x0": 39.4, "x1": 316.5}

    def test_dev_glif_filigran_sayilir(self):
        self.assertTrue(apk._filigran_kelimesi_mi(
            207.4, 273.5, 396.4, 462.5, self._Sayfa, self.SUTUN))

    def test_normal_dizgi_satiri_gecer(self):
        """Gövde metni ne sayfa yüksekliğinin %5'ini ne de sütun genişliğini
        aşar; filtre onları elememeli."""
        self.assertFalse(apk._filigran_kelimesi_mi(
            55.0, 148.7, 260.0, 157.7, self._Sayfa, self.SUTUN))

    def test_sutundan_genis_kelime_filigran_sayilir(self):
        """İkinci ölçüt tek başına da yeter: normal yükseklikte ama sütundan
        geniş bir 'kelime' dizgi olamaz."""
        self.assertTrue(apk._filigran_kelimesi_mi(
            20.0, 400.0, 400.0, 412.0, self._Sayfa, self.SUTUN))
