#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sayım-altını (Tier-1 golden) katmanı testleri.

Bu katmanın tek işi recall/precision'ı SAYI düzeyinde ölçmek: kutu koordinatı
kullanılmaz, dolayısıyla ucuzdur ve 10 belgelik korpusa yayılabilir.
"""

import json
import os
import tempfile
import unittest

import altin_sayim


class _SahteSayfa:
    genislik = 595.0
    yukseklik = 842.0
    raster = False


class _SahteAday:
    """sk.aday_otomatik_teslim'in baktığı alanları taşıyan asgari meta."""

    def __init__(self, durum="otomatik"):
        self.devam_aday = False
        self.inceleme_durumu = durum
        self.onay_durumu = None
        self.kutu = (0, 0, 1, 1)


def _veriler(kutu_sayilari, oto_sayilari=None):
    """dogrula.belge_isle çıktısının sayım için gereken kısmını taklit eder.

    oto_sayilari verilmezse teslim edilen her kutu 'otomatik' sayılır."""
    oto_sayilari = oto_sayilari if oto_sayilari is not None else kutu_sayilari
    if len(oto_sayilari) != len(kutu_sayilari):
        # zip sessizce kırpardı: test niyetlenenden az sayfa ölçüp yanlış
        # yeşil verirdi.
        raise ValueError("kutu_sayilari ile oto_sayilari uzunlukları farklı")
    return [
        (_SahteSayfa(), [(0, 595)], [(0, 0, 1, 1)] * n,
         [_SahteAday("otomatik")] * o + [_SahteAday("incele")] * (n - o))
        for n, o in zip(kutu_sayilari, oto_sayilari)
    ]


def _sayim(sayfa_sayimlari, ilk_sayfa=1):
    return {
        "schema_version": altin_sayim.SEMA_SURUMU,
        "document": {"id": "test", "source": "t.pdf",
                     "source_sha256": "a" * 64, "page_count": 99},
        "sampling": {},
        "verifier": "test",
        "method": "kor-sayim",
        "pages": [{"page": ilk_sayfa + i, "question_count": n,
                   "question_numbers": None, "role": "soru", "notes": ""}
                  for i, n in enumerate(sayfa_sayimlari)],
    }


class SayimDegerlendir(unittest.TestCase):

    def test_tam_isabet(self):
        r = altin_sayim.sayim_degerlendir(
            _sayim([4, 6, 5]), _veriler([4, 6, 5]), [1, 2, 3])
        self.assertEqual(r["count_recall"], 1.0)
        self.assertEqual(r["count_precision"], 1.0)
        self.assertEqual(r["page_exact_rate"], 1.0)
        self.assertEqual(r["worst_pages"], [])

    def test_kacirma_recall_dusurur(self):
        """Asıl hedef: kaçan soru anomali üretmese bile burada görünür."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([10, 6]), _veriler([5, 6]), [1, 2])
        self.assertEqual(r["under_count"], 5)
        self.assertEqual(r["over_count"], 0)
        self.assertAlmostEqual(r["count_recall"], 11 / 16)
        self.assertEqual(r["worst_pages"][0], {"page": 1, "gold": 10,
                                               "pred": 5, "pred_auto": 5})

    def test_otomatik_kovasi_ayri_olculur(self):
        """'incele' kutusu bulunmuştur (teslim recall'ü sayar) ama otomatik
        kovanın recall'ünü düşürür — SH-2 tam olarak bu ayrımı ister."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([10]), _veriler([10], oto_sayilari=[6]), [1])
        self.assertEqual(r["count_recall"], 1.0)
        self.assertAlmostEqual(r["count_recall_auto"], 0.6)
        self.assertEqual(r["pred_total_auto"], 6)
        self.assertEqual(r["count_precision_auto"], 1.0)

    def test_fazla_uretme_precision_dusurur(self):
        r = altin_sayim.sayim_degerlendir(
            _sayim([4]), _veriler([9]), [1])
        self.assertEqual(r["over_count"], 5)
        self.assertAlmostEqual(r["count_precision"], 4 / 9)
        self.assertEqual(r["count_recall"], 1.0)

    def test_otomatik_kova_precision_ayri_paydayla_olculur(self):
        """count_precision_auto kendi paydasını (pred_total_auto) kullanır.

        Fazla üretim otomatik kovada toplandığında teslim precision'ı geniş
        payda içinde seyrelip iyi görünür (0,78) ama 'sıfır hata' hedefinin
        tanımlı olduğu otomatik kovada aynı 4 fazla kutu precision'ı yarıya
        indirir. Tek bir precision sayısı bu farkı gizlerdi."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([4, 10]), _veriler([8, 10], oto_sayilari=[8, 0]), [1, 2])
        self.assertEqual(r["over_count"], 4)
        self.assertAlmostEqual(r["count_precision"], 1 - 4 / 18)
        self.assertAlmostEqual(r["count_precision_auto"], 0.5)
        self.assertEqual(r["pred_total_auto"], 8)
        # Teslim recall'ü kusursuz: kaçan soru yok, sorun yalnız kovalarda.
        self.assertEqual(r["count_recall"], 1.0)
        self.assertAlmostEqual(r["count_recall_auto"], 1 - 10 / 14)

    def test_sifir_sayfa_yalniz_altinda_soru_varken_isaretlenir(self):
        """zero_pages, kalite kapısının koşulsuz kırmızısını besler; bu yüzden
        yanlış pozitif üretmemeli. Altında da 0 soru olan (kapak/cevap
        anahtarı) sayfada motorun 0 kutu üretmesi DOĞRU davranıştır.

        DÜRÜSTLÜK NOTU: bugün bu davranış `sapmalar` listesinden geliyor
        (yalnız g != p sayfalar girer, dolayısıyla pred=0 ise gold>0 zaten
        zorunlu); `question_count > 0` koruması ulaşılamaz durumda. Bu test
        uygulamayı değil ÇIKTI ÖZELLİĞİNİ pinler — `sapmalar` tanımı
        genişletilirse (ör. tüm sayfalar) koruma canlanır ve test ısırır."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([3, 0, 4]), _veriler([0, 0, 0]), [1, 2, 3])
        self.assertEqual(r["zero_pages"], [1, 3])
        self.assertEqual(r["count_recall"], 0.0)

    def test_bos_altin_sifira_bolme_uretmez(self):
        """Kapak/cevap anahtarı gibi tümü 0 sayılan bir örneklemde paydalar
        sıfırdır. Koruma kalkarsa ZeroDivisionError tüm kalite koşumunu
        durdurur; oran tanımsızken 1.0 (ihlal yok) doğru varsayılandır."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([0, 0]), _veriler([0, 0]), [1, 2])
        self.assertEqual(r["count_recall"], 1.0)
        self.assertEqual(r["count_precision"], 1.0)
        self.assertEqual(r["count_recall_auto"], 1.0)
        self.assertEqual(r["count_precision_auto"], 1.0)
        self.assertEqual(r["page_exact_rate"], 1.0)
        self.assertEqual(r["zero_pages"], [])

    def test_worst_pages_mutlak_sapmaya_gore_siralanir(self):
        """Rapordaki 'sayim_sapmalari' kolonu bu sıralamayı gösterir: en
        büyük sapma başta olmalı, yönü (eksik/fazla) fark etmemeli.

        Sayılar bilerek seçildi: küçük FAZLA üretim (−2) ile büyük KAÇIRMA
        (+8) karşı karşıya. İşaretli sıralamaya düşülürse fazla üretim başa
        geçer ve asıl kayıp listenin dibine gömülür."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([10, 4]), _veriler([2, 6]), [1, 2])
        self.assertEqual([s["page"] for s in r["worst_pages"]], [1, 2])

    def test_snapshot_sozlesmesi_korunur(self):
        """kalite_kosusu._belge_kosusu bu alanları anahtar anahtar snapshot'a
        kopyalar; kosu() ayrıca beşini yuvarlar. Biri yeniden adlandırılırsa
        gerçek koşum KeyError ile patlar — sözleşmeyi burada pinliyoruz."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([4, 6]), _veriler([4, 6]), [1, 2])
        for alan in ("count_recall", "count_precision", "count_recall_auto",
                     "count_precision_auto", "page_exact_rate", "gold_total",
                     "pred_total", "zero_pages", "worst_pages"):
            self.assertIn(alan, r)
        self.assertEqual(r["pred_total"], 10)
        self.assertEqual(r["gold_total"], 10)

    def test_bosalan_sayfa_ayrica_raporlanir(self):
        r = altin_sayim.sayim_degerlendir(
            _sayim([3, 5]), _veriler([0, 5]), [1, 2])
        self.assertEqual(r["zero_pages"], [1])

    def test_ortusmeyen_sayfalar_hata(self):
        with self.assertRaises(ValueError):
            altin_sayim.sayim_degerlendir(
                _sayim([3], ilk_sayfa=50), _veriler([3]), [1])

    def test_kismi_ortusme_yalniz_ortak_sayfalari_olcer(self):
        r = altin_sayim.sayim_degerlendir(
            _sayim([3, 4, 5]), _veriler([3, 4]), [1, 2])
        self.assertEqual(r["pages"], 2)
        self.assertEqual(r["gold_total"], 7)
        self.assertEqual(r["gold_pages"], 3)
        self.assertAlmostEqual(r["pages_overlap_ratio"], 2 / 3, places=3)

    def test_ortusme_orani_yaniltici_mukemmelligi_gorunur_kilar(self):
        """Gerçek vaka: bir ikiz belgede max_sayfa farkı yüzünden 8 altın
        sayfasından yalnız 1'i (boş kapak) örtüştü; recall/precision/otomatik
        hepsi 1,000 çıktı ve belge kusursuz göründü. Oran raporlanmazsa bu
        sessiz kalır — kapı bu alana bakıp kırmızı veriyor."""
        r = altin_sayim.sayim_degerlendir(
            _sayim([0, 9, 9, 9, 9, 9, 9, 9]), _veriler([0]), [1])
        self.assertEqual(r["count_recall"], 1.0)      # yanıltıcı mükemmellik
        self.assertEqual(r["count_precision"], 1.0)
        self.assertAlmostEqual(r["pages_overlap_ratio"], 1 / 8)
        self.assertEqual(r["pages"], 1)
        self.assertEqual(r["gold_pages"], 8)


class SemaDogrulama(unittest.TestCase):

    def test_yanlis_sema_reddedilir(self):
        with tempfile.TemporaryDirectory() as d:
            yol = os.path.join(d, "x.json")
            with open(yol, "w", encoding="utf-8") as f:
                json.dump({"schema_version": "baska/v9"}, f)
            with self.assertRaises(ValueError):
                altin_sayim.sayim_yukle(yol)

    def test_gecerli_sema_yuklenir(self):
        with tempfile.TemporaryDirectory() as d:
            yol = os.path.join(d, "x.json")
            with open(yol, "w", encoding="utf-8") as f:
                json.dump(_sayim([2, 3]), f)
            veri = altin_sayim.sayim_yukle(yol)
            self.assertEqual(len(veri["pages"]), 2)

    def test_eksik_alan_reddedilir(self):
        with tempfile.TemporaryDirectory() as d:
            yol = os.path.join(d, "x.json")
            with open(yol, "w", encoding="utf-8") as f:
                json.dump({"schema_version": altin_sayim.SEMA_SURUMU,
                           "document": {}}, f)
            with self.assertRaises(ValueError):
                altin_sayim.sayim_yukle(yol)


if __name__ == "__main__":
    unittest.main()
