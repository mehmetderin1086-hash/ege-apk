#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kalite kapısı kayma nöbetçisi (kalite_kosusu._kayma_degerlendir).

Motivasyon (gerçek vaka): 'cozumyazili' belgesinde toplam kutu 27 → 18
düşerken anomali sayısı iki koşumda da 0 kaldı; kapı yalnız anomaliye
baktığı için REGRESYON YEŞİL geçti. Bu testler o sınıfın bir daha sessiz
geçmemesini garanti eder — ve nöbetçinin yanlış alarm üretmemesini.
"""

import copy
import json
import os
import tempfile
import unittest
from unittest import mock

import kalite_kosusu as kk


def _m(**kw):
    """Varsayılan olarak ÖZDEŞ iki koşum üretir; testler tek alan oynatır."""
    temel = {
        "kaynak_sha256": "a" * 64,
        "format": "coktan_secmeli",
        "duzen_model": True,
        "sayfa": 6,
        "toplam_kutu": 27,
        "sayfa_soru": [6, 4, 4, 1, 5, 7],
        "ham_aday": 40,
        "reddedilen_kutu": 2,
        "incele_kutu": 5,
        "anomali_sayisi": 0,
        "anomali_turleri": {},
    }
    temel.update(kw)
    return temel


def _kodlar(bulgular, seviye=None):
    return {b["kod"] for b in bulgular
            if seviye is None or b["seviye"] == seviye}


def _sayim_kodlari(bulgular):
    """Yalnız sayım kaynaklı kodlar — 'tam olarak şunlar çıkmalı' demek için.

    assertIn tek başına yetmez: eşitliği de gerileme sayan bir kıyas (b <= a)
    tüm ölçütlerde bulgu üretirdi ve assertIn yine yeşil kalırdı."""
    return {b["kod"] for b in bulgular if b["kod"].startswith("sayim-")}


def _sayim(**kw):
    """Snapshot'a gömülen sayım bloğunun (bkz. _belge_kosusu) taklidi."""
    temel = {"count_recall": 1.0, "count_precision": 1.0,
             "count_recall_auto": 1.0, "count_precision_auto": 1.0,
             "page_exact_rate": 1.0, "gold_total": 40, "pred_total": 40,
             "zero_pages": []}
    temel.update(kw)
    return temel


class KaymaNobetcisi(unittest.TestCase):

    def test_gercek_cozumyazili_kaybi_kirmizi(self):
        """27 → 18 kutu, anomali 0 → 0: eski kapının kaçırdığı asıl vaka."""
        onceki = _m()
        simdi = _m(toplam_kutu=18, sayfa_soru=[2, 2, 6, 1, 2, 5])
        bulgular = kk._kayma_degerlendir(simdi, onceki)
        self.assertIn("kutu-dusus", _kodlar(bulgular, "kirmizi"))

    def test_ozdes_kosum_temiz(self):
        self.assertEqual(kk._kayma_degerlendir(_m(), _m()), [])

    def test_kucuk_oynama_alarm_uretmez(self):
        """%5 içindeki ya da 3'ten küçük fark güvenlik payıdır."""
        bulgular = kk._kayma_degerlendir(_m(toplam_kutu=26), _m())
        self.assertEqual(_kodlar(bulgular, "kirmizi"), set())

    def test_aday_dususu_dedektor_gerilemesi(self):
        bulgular = kk._kayma_degerlendir(
            _m(ham_aday=30, toplam_kutu=20), _m())
        self.assertIn("aday-dusus", _kodlar(bulgular, "kirmizi"))

    def test_filtre_kaymasi_sari_kalir(self):
        """Aday sabit, reddedilen arttı → precision değişimi olabilir: sarı."""
        bulgular = kk._kayma_degerlendir(
            _m(toplam_kutu=26, reddedilen_kutu=3), _m())
        self.assertIn("filtre-kaymasi", _kodlar(bulgular, "sari"))
        self.assertEqual(_kodlar(bulgular, "kirmizi"), set())

    def test_sayfa_sifirlanmasi_kirmizi(self):
        bulgular = kk._kayma_degerlendir(
            _m(sayfa_soru=[6, 0, 4, 1, 5, 7], toplam_kutu=21), _m())
        self.assertIn("sayfa-sifirlandi", _kodlar(bulgular, "kirmizi"))

    def test_anomali_turu_artisi_toplam_sabitken_yakalanir(self):
        onceki = _m(anomali_sayisi=2, anomali_turleri={"minik": 2})
        simdi = _m(anomali_sayisi=2, anomali_turleri={"minik": 1,
                                                      "birlesme": 1})
        bulgular = kk._kayma_degerlendir(simdi, onceki)
        self.assertIn("anomali-tur-artis", _kodlar(bulgular, "kirmizi"))

    def test_kaynak_degisirse_karsilastirma_yapilmaz(self):
        """Farklı PDF/örneklem → kıyas geçersiz; yanlış alarm üretilmez."""
        bulgular = kk._kayma_degerlendir(
            _m(kaynak_sha256="b" * 64, toplam_kutu=5), _m())
        self.assertEqual(_kodlar(bulgular), {"anlik-gecersiz"})

    def test_ml_durumu_degisirse_karsilastirma_yapilmaz(self):
        bulgular = kk._kayma_degerlendir(
            _m(duzen_model=False, toplam_kutu=5), _m())
        self.assertEqual(_kodlar(bulgular), {"anlik-gecersiz"})

    def test_eski_snapshot_alansizken_cokmez(self):
        """Yeni alanları olmayan eski once_*.json geriye dönük çalışmalı."""
        eski = {"toplam_kutu": 27, "anomali_sayisi": 0,
                "sayfa_soru": [6, 4, 4, 1, 5, 7], "sayfa": 6}
        bulgular = kk._kayma_degerlendir(_m(toplam_kutu=18,
                                            sayfa_soru=[2, 2, 6, 1, 2, 5]),
                                         eski)
        self.assertIn("kutu-dusus", _kodlar(bulgular, "kirmizi"))

    def test_snapshot_yoksa_bulgu_yok(self):
        self.assertEqual(kk._kayma_degerlendir(_m(), None), [])

    def test_asiri_artis_sari(self):
        bulgular = kk._kayma_degerlendir(_m(toplam_kutu=40), _m())
        self.assertIn("kutu-artis", _kodlar(bulgular, "sari"))


class SayimKaymaNobetcisi(unittest.TestCase):
    """Snapshot'a gömülen sayım bloğunun iki koşum arası kıyası.

    Kutu sayısına bakan kurallar (kutu-dusus, sayfa-sifirlandi) toplam SABİT
    kalırken bozulan bir dağılımı göremez: motor bir sayfada bir soru kaçırıp
    başka sayfada bir fazla üretirse toplam değişmez ama recall düşer. Bu
    sinyal eşik dosyasından da bağımsızdır — taban hiç tanımlı olmasa bile
    gerileme kırmızı olur."""

    def test_count_recall_dususu_kutu_sabitken_kirmizi(self):
        """Asıl değer bu: toplam kutu, aday ve anomali aynı kalırken hangi
        sayfada kaç soru bulunduğu bozulabilir."""
        onceki = _m(sayim=_sayim(count_recall=1.0))
        simdi = _m(sayim=_sayim(count_recall=0.9))
        bulgular = kk._kayma_degerlendir(simdi, onceki)
        self.assertIn("sayim-dusus-count_recall", _kodlar(bulgular, "kirmizi"))
        # Sabit kalan üç ölçüt bulgu ÜRETMEMELİ (yanlış alarm kapısı).
        self.assertEqual(_sayim_kodlari(bulgular),
                         {"sayim-dusus-count_recall"})
        # Kutu sayısı hiç oynamadı: eski kurallar bu vakada sessiz.
        self.assertNotIn("kutu-dusus", _kodlar(bulgular))

    def test_otomatik_kova_gerilemesi_teslim_sabitken_kirmizi(self):
        """Bir kutunun 'otomatik'ten 'incele'ye düşmesi teslim recall'ünü
        değiştirmez ama insan iş yükünü artırır — sessiz kalite kaybıdır."""
        onceki = _m(sayim=_sayim(count_recall_auto=0.9))
        simdi = _m(sayim=_sayim(count_recall_auto=0.7))
        bulgular = kk._kayma_degerlendir(simdi, onceki)
        self.assertIn("sayim-dusus-count_recall_auto",
                      _kodlar(bulgular, "kirmizi"))
        self.assertEqual(_sayim_kodlari(bulgular),
                         {"sayim-dusus-count_recall_auto"})

    def test_precision_ve_sayfa_isabeti_de_nobette(self):
        """Nöbet dört ölçütü de kapsar. Yalnız recall izlenseydi motorun
        fazla kutu üretmeye başlaması (precision düşüşü) ya da soruların
        sayfalar arasına kayması (page_exact_rate düşüşü) sessiz kalırdı."""
        onceki = _m(sayim=_sayim())
        for olcut in ("count_precision", "page_exact_rate"):
            with self.subTest(olcut=olcut):
                bulgular = kk._kayma_degerlendir(
                    _m(sayim=_sayim(**{olcut: 0.80})), onceki)
                self.assertEqual(_sayim_kodlari(bulgular),
                                 {f"sayim-dusus-{olcut}"})
                self.assertEqual(_kodlar(bulgular, "kirmizi"),
                                 {f"sayim-dusus-{olcut}"})

    def test_sayim_yukselirse_bulgu_yok(self):
        """Nöbetçi tek yönlüdür: iyileşme kırmızı üretirse kapı kullanılamaz
        hale gelir (her ilerleme bloklanır)."""
        onceki = _m(sayim=_sayim(count_recall=0.80, count_precision=0.90,
                                 count_recall_auto=0.50,
                                 page_exact_rate=0.60))
        simdi = _m(sayim=_sayim(count_recall=0.95, count_precision=0.99,
                                count_recall_auto=0.75,
                                page_exact_rate=0.80))
        self.assertEqual(kk._kayma_degerlendir(simdi, onceki), [])

    def test_eski_snapshotta_sayim_yoksa_atlanir(self):
        """Faz 0 öncesi yazılmış once_*.json dosyalarında 'sayim' bloğu yok;
        kural patlamadan ve yanlış alarm üretmeden atlanmalı."""
        onceki = _m()  # 'sayim' anahtarı hiç yok
        simdi = _m(sayim=_sayim(count_recall=0.10))
        bulgular = kk._kayma_degerlendir(simdi, onceki)
        self.assertEqual(_sayim_kodlari(bulgular), set())

    def test_yeni_kosumda_sayim_yoksa_atlanir(self):
        """Ters yön: sayım-altını dosyası silinir ya da belge koleksiyondan
        çıkarılırsa yeni koşumda 'sayim' bloğu olmaz — eski snapshot'ta
        varken kıyas yapılamaz. Kural çökmeden atlamalı; aksi halde tek bir
        eksik altın dosyası tüm kalite koşumunu AttributeError ile durdurur."""
        onceki = _m(sayim=_sayim(count_recall=0.95))
        self.assertEqual(kk._kayma_degerlendir(_m(), onceki), [])


class AltinKapisi(unittest.TestCase):
    """Altın verili belgede kalite tabanının altına düşüş kırmızı olmalı.

    Gerçek vaka: bir motor değişikliği korpusta anomali artışı üretmeden altın
    veride F1'i 0,975 → 0,966'ya indirdi (41 yanlış-pozitif) ve koşum yeşil
    verdi; düşüş ancak elle fark edildi."""

    ESIK = {"varsayilan": {"gerileme_toleransi": 0.005},
            "belgeler": {"tyt1": {"f1_min": 0.970, "precision_min": 0.970,
                                  "recall_min": 0.970, "f1_siki_min": 0.950}}}

    def test_f1_dususu_kirmizi(self):
        b = kk._altin_kapisi("tyt1", {"f1": 0.966, "precision": 0.947,
                                      "recall": 0.985, "f1_siki": 0.937},
                             self.ESIK)
        self.assertTrue(any(x["seviye"] == "kirmizi" and x["kod"].startswith("altin-f1")
                            for x in b))

    def test_taban_ustu_temiz(self):
        b = kk._altin_kapisi("tyt1", {"f1": 0.975, "precision": 0.975,
                                      "recall": 0.975, "f1_siki": 0.958},
                             self.ESIK)
        self.assertEqual([x for x in b if x["seviye"] == "kirmizi"], [])

    def test_ratchet_onerisi_bilgi(self):
        b = kk._altin_kapisi("tyt1", {"f1": 0.990, "precision": 0.99,
                                      "recall": 0.99, "f1_siki": 0.97},
                             self.ESIK)
        self.assertIn("altin-taban-yukseltilebilir", {x["kod"] for x in b})

    def test_esiksiz_belge_bulgusuz(self):
        self.assertEqual(kk._altin_kapisi("baska", {"f1": 0.1}, self.ESIK), [])

    def test_siki_iou_tabani_ayri_denetlenir(self):
        b = kk._altin_kapisi("tyt1", {"f1": 0.975, "precision": 0.975,
                                      "recall": 0.975, "f1_siki": 0.90},
                             self.ESIK)
        self.assertIn("altin-f1_siki", {x["kod"] for x in b})


class AltinKapisiSayimTabani(unittest.TestCase):
    """Kapı eşiklerinin count_* kolu (kapi_esikleri.json sürüm 2).

    Kutu-altını yalnız tek bir ÖSYM PDF'inde var; korpusun geri kalanında
    recall/precision'ı gören TEK taban bu kolda. Bulgu kodunun 'altin-' değil
    'sayim-' önekiyle çıkması önemli: rapor okuyan insan hangi altın
    katmanının bozulduğunu koddan anlamalı."""

    ESIK = {"varsayilan": {"gerileme_toleransi": 0.005},
            "belgeler": {"12meb": {"count_recall_min": 0.90,
                                   "count_precision_min": 1.0,
                                   "count_recall_auto_min": 0.45,
                                   "page_exact_min": 0.66}}}

    def _satir(self, **kw):
        temel = {"count_recall": 0.95, "count_precision": 1.0,
                 "count_recall_auto": 0.45, "page_exact_rate": 0.70}
        temel.update(kw)
        return temel

    def test_count_recall_taban_alti_kirmizi(self):
        b = kk._altin_kapisi("12meb", self._satir(count_recall=0.85),
                             self.ESIK)
        kirmizi = {x["kod"] for x in b if x["seviye"] == "kirmizi"}
        self.assertIn("sayim-count_recall", kirmizi)
        # Önek denetimi: sayım tabanı ihlali 'altin-' koduyla raporlanmamalı.
        self.assertFalse(any(k.startswith("altin-") for k in kirmizi))

    def test_taban_ustu_temiz(self):
        b = kk._altin_kapisi("12meb", self._satir(), self.ESIK)
        self.assertEqual([x for x in b if x["seviye"] == "kirmizi"], [])

    def test_her_sayim_tabani_ayri_denetlenir(self):
        """Dört sayım tabanının HEPSİ kapıda olmalı. Biri unutulursa o ölçüt
        eşik dosyasında yazılı görünür ama hiçbir zaman uygulanmaz — en
        tehlikeli sessiz delik budur (taban var sanılır, yoktur)."""
        alt_deger = {"count_recall": 0.10, "count_precision": 0.10,
                     "count_recall_auto": 0.10, "page_exact_rate": 0.10}
        for olcut, deger in alt_deger.items():
            with self.subTest(olcut=olcut):
                b = kk._altin_kapisi("12meb", self._satir(**{olcut: deger}),
                                     self.ESIK)
                kirmizi = [x for x in b if x["seviye"] == "kirmizi"]
                self.assertTrue(
                    any(x["kod"].endswith(olcut.replace("_rate", ""))
                        for x in kirmizi),
                    f"{olcut} tabanı uygulanmadı: {kirmizi}")

    def test_ratchet_count_recall_icin_bilgi_ve_yan_etkisiz(self):
        """Ratchet ÖNERİR, yazmaz: eşik dosyasına otomatik yazım olsaydı taban
        insan onayı olmadan yükselir ve gerileme sessizce yeni norm olurdu."""
        esik = copy.deepcopy(self.ESIK)
        b = kk._altin_kapisi("12meb", self._satir(count_recall=0.99), esik)
        oneriler = [x for x in b if x["kod"] == "altin-taban-yukseltilebilir"]
        self.assertTrue(any(x["detay"].startswith("count_recall_min")
                            for x in oneriler))
        self.assertTrue(all(x["seviye"] == "bilgi" for x in oneriler))
        self.assertEqual([x for x in b if x["seviye"] == "kirmizi"], [])
        # Yan etki yok: girdi sözlüğü (dolayısıyla kapi_esikleri.json'a
        # yazılacak içerik) hiç değişmemeli.
        self.assertEqual(esik, self.ESIK)


class KosuSayimSinyalleri(unittest.TestCase):
    """kosu() içindeki sayım sinyalleri — motoru koşmadan.

    _belge_kosusu sahtelenir: gerçek PDF açmak bu testleri saniyelerden
    dakikalara çıkarır ve sinyalin kendisini değil motoru ölçer."""

    # Yol GERÇEKTEN var olmalı: kosu() korpusu koşumdan önce doğruluyor.
    # Dosyanın içeriği önemsiz, _belge_kosusu zaten sahtelenmiş durumda.
    OGE = {"ad": "sahte", "yol": "kalite/koleksiyon.json"}

    def _kosu(self, m, sayim):
        with mock.patch.object(kk, "_koleksiyon_oku",
                               return_value=[self.OGE]), \
             mock.patch.object(kk, "_esikleri_oku",
                               return_value={"varsayilan": {},
                                             "belgeler": {}}), \
             mock.patch.object(kk, "_anlik_oku", return_value=None), \
             mock.patch.object(kk, "_belge_kosusu",
                               return_value=(m, None, sayim)) as sahte:
            satirlar, regresyon = kk.kosu()
        self.assertTrue(sahte.called, "kosu() _belge_kosusu'nu çağırmadı")
        self.assertEqual(len(satirlar), 1)
        return satirlar[0], regresyon

    def test_sifir_sayfa_kosulsuz_kirmizi(self):
        """Altında soru olan bir sayfada motorun HİÇ kutu üretmemesi eşikten
        bağımsız yapısal kayıptır; toplam metrik iyi görünse bile kırmızı."""
        satir, regresyon = self._kosu(
            _m(), dict(_sayim(count_recall=0.98), zero_pages=[7, 12],
                       worst_pages=[]))
        self.assertEqual(satir["durum"], "REGRESYON")
        self.assertTrue(regresyon)
        self.assertIn("sayim-sifir-sayfa",
                      _kodlar(satir["bulgular"], "kirmizi"))
        self.assertEqual(satir["zero_pages"], [7, 12])

    def test_sifir_sayfa_yokken_temiz(self):
        satir, regresyon = self._kosu(
            _m(), dict(_sayim(), worst_pages=[]))
        self.assertFalse(regresyon)
        self.assertEqual(satir["durum"], "ok")
        self.assertEqual(satir["count_recall"], 1.0)

    def test_sayim_degerlendirme_hatasi_kirmizi(self):
        """Sayım değerlendirmesinin patlaması, sayım kapısının tamamen devre
        dışı kalabileceği tek delik — sessiz geçmemeli."""
        satir, regresyon = self._kosu(_m(), {"hata": "sayfalar örtüşmüyor"})
        self.assertTrue(regresyon)
        self.assertIn("sayim-degerlendirme-hatasi",
                      _kodlar(satir["bulgular"], "kirmizi"))


class SayimKosusuDosya(unittest.TestCase):

    def test_altin_dosyasi_yoksa_none(self):
        """Korpusun çoğunda sayım-altını henüz yok; _sayim_kosusu bu belgeleri
        sessizce atlamalı (patlarsa tüm koşum durur)."""
        self.assertIsNone(
            kk._sayim_kosusu("boyle_bir_belge_yok_xyz", [], []))

    def test_degerlendirme_patlarsa_hata_sozlugu_doner(self):
        """Gerçek bir sayım-altını dosyasıyla hata yolu: koşum verisi altınla
        örtüşmezse (örneklem değişmiş) ValueError yükselir. _sayim_kosusu bunu
        {'hata': ...} sözlüğüne çevirmeli — kosu() bu sözlüğü kırmızı bulguya
        dönüştürüyor (bkz. KosuSayimSinyalleri). İstisna dışarı sızsaydı tüm
        koşum durur, sessizce yutulsaydı sayım kapısı devre dışı kalırdı."""
        ad = "12meb"
        if not os.path.exists(os.path.join(kk.KOK, "kalite", "altin_sayim",
                                           f"{ad}.json")):
            self.skipTest(f"{ad} sayım-altını yok")
        sonuc = kk._sayim_kosusu(ad, [], [])
        self.assertIn("hata", sonuc)
        self.assertIn("örtüşmüyor", sonuc["hata"])


class KapsamKatmanlari(unittest.TestCase):
    """Korpus 44 belgeye çıktı; hepsini her değişiklikte koşmak ~20 dk.
    Katmanlar bu yüzden var ve iç içe olmak ZORUNDA: B, A'yı kapsamazsa
    kapı katmanında yakalanan bir regresyon tam koşumda görünmez."""

    def _sahte(self):
        return [
            {"ad": "a1", "kapsam": "A"}, {"ad": "a2", "kapsam": "A"},
            {"ad": "b1", "kapsam": "B"}, {"ad": "c1", "kapsam": "C"},
            {"ad": "eski"},  # kapsam alanı olmayan kayıt
        ]

    def _oku(self, kapsam):
        with tempfile.NamedTemporaryFile("w", suffix=".json",
                                         delete=False, encoding="utf-8") as f:
            json.dump(self._sahte(), f)
            yol = f.name
        try:
            return [o["ad"] for o in kk._koleksiyon_oku(yol, kapsam=kapsam)]
        finally:
            os.unlink(yol)

    def test_katmanlar_ic_ice(self):
        a, b, c = self._oku("A"), self._oku("B"), self._oku("C")
        self.assertEqual(set(a), {"a1", "a2", "eski"})
        self.assertTrue(set(a) < set(b), "B, A'yı kapsamalı")
        self.assertTrue(set(b) < set(c), "C, B'yi kapsamalı")
        self.assertIn("c1", c)
        self.assertNotIn("c1", b)

    def test_kapsamsiz_kayit_kapi_katmaninda(self):
        """Alanı olmayan eski kayıtlar sessizce DÜŞMEMELİ; en sıkı katmana
        (A) düşerler, böylece geriye uyum bir belgeyi ölçüm dışı bırakmaz."""
        self.assertIn("eski", self._oku("A"))

    def test_aile_ozeti_regresyonu_aileye_atar(self):
        """Aile satırı olmadan 44 belgelik tabloda 'hangi kitap türüne zarar
        verdim' sorusu gözle yanıtlanamaz."""
        satirlar = [
            {"ad": "x", "aile": "cozum", "durum": "REGRESYON", "anomali": 1,
             "toplam_kutu": 10, "incele_kuyrugu": 2, "count_recall": 0.6},
            {"ad": "y", "aile": "cozum", "durum": "ok", "anomali": 0,
             "toplam_kutu": 20, "incele_kuyrugu": 1, "count_recall": 1.0},
            {"ad": "z", "aile": "osym", "durum": "ok", "anomali": 0,
             "toplam_kutu": 5, "incele_kuyrugu": 0, "f1": 0.99},
        ]
        ozet = kk._aile_ozeti(satirlar)
        self.assertEqual(ozet["cozum"]["belge"], 2)
        self.assertEqual(ozet["cozum"]["regresyon"], 1)
        self.assertEqual(ozet["cozum"]["kutu"], 30)
        self.assertAlmostEqual(ozet["cozum"]["sayR"], 0.8)
        # Ölçütü olmayan aile None kalır; 0.0 yazmak "mükemmel sıfır" gibi
        # okunur ve ortalamayı da bozar.
        self.assertIsNone(ozet["osym"]["sayR"])
        self.assertAlmostEqual(ozet["osym"]["f1"], 0.99)


if __name__ == "__main__":
    unittest.main()
