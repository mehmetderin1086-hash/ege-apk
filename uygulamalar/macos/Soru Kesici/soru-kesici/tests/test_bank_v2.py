#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soru bankası V4 şeması ve salt-okunur karşılaştırma API'leri."""

import os
import sqlite3
import tempfile
import unittest

from PIL import Image

import soru_bankasi as banka


class BankaV4Testi(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory(prefix="soru_bankasi_v4_")
        self.db = os.path.join(self.gecici.name, "banka.db")

    def tearDown(self):
        self.gecici.cleanup()

    def _v3_veritabani_uret(self):
        conn = sqlite3.connect(self.db)
        try:
            banka._goc_v1(conn)
            banka._goc_v2(conn)
            banka._goc_v3(conn)
            conn.execute("PRAGMA user_version = 3")
            conn.execute(
                """INSERT INTO sorular
                   (icerik_hash, gorsel_yol, gorsel_hash, kaynak, soru_no,
                    sayfa, konu, baslik, zorluk, metin, govde, siklar_json,
                    kaynak_kutu, numara_px, eklenme, eklenme_ts)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                ("t:eski", "media/es/eski.png", "ahash", "eski.pdf", 7,
                 12, "Biyoloji", "Hücre", "orta", "Eski soru metni",
                 "Eski soru gövdesi", "{}", "[1, 2, 3, 4]", "[5, 6]",
                 "2026-07-17 10:00:00", 1234.5),
            )
            conn.commit()
        finally:
            conn.close()

    def test_v3_v4_gocu_satiri_korur_yedekler_ve_idempotenttir(self):
        self._v3_veritabani_uret()

        conn = banka.baglan(self.db)
        try:
            # V5 (sinav_sablonlari) sonrası şema sürümü ilerledi; V4 alanları
            # aynen korunur (aşağıdaki sütun denetimi bunu garanti eder).
            self.assertEqual(banka.SEMA_SURUM, conn.execute(
                "PRAGMA user_version").fetchone()[0])
            sutunlar = {r[1]: r[2] for r in conn.execute(
                "PRAGMA table_info(sorular)")}
            self.assertEqual(
                {
                    "kaynak_hash": "TEXT",
                    "algoritma_surumu": "TEXT",
                    "soru_turu": "TEXT",
                    "sayfa_rolu": "TEXT",
                    "guven": "REAL",
                    "inceleme_durumu": "TEXT",
                },
                {ad: sutunlar[ad] for ad in (
                    "kaynak_hash", "algoritma_surumu", "soru_turu",
                    "sayfa_rolu", "guven", "inceleme_durumu")},
            )
            satir = conn.execute(
                "SELECT * FROM sorular WHERE icerik_hash='t:eski'"
            ).fetchone()
            self.assertIsNotNone(satir)
            self.assertEqual("Eski soru gövdesi", satir["govde"])
            self.assertEqual("Biyoloji", satir["konu"])
            for ad in ("kaynak_hash", "algoritma_surumu", "soru_turu",
                       "sayfa_rolu", "guven", "inceleme_durumu"):
                self.assertIsNone(satir[ad])
        finally:
            conn.close()

        yedekler = banka._v4_yedek_adlari(self.db)
        self.assertEqual(1, len(yedekler))
        yedek = sqlite3.connect(yedekler[0])
        try:
            self.assertEqual(3, yedek.execute(
                "PRAGMA user_version").fetchone()[0])
            self.assertEqual(
                ("t:eski", "Eski soru gövdesi"),
                yedek.execute(
                    "SELECT icerik_hash, govde FROM sorular").fetchone(),
            )
        finally:
            yedek.close()

        # Hem bağlantıyı yeniden açmak hem göç fonksiyonunu tekrar çağırmak
        # satır veya yedek çoğaltmamalı.
        conn = banka.baglan(self.db)
        try:
            banka._goc_v4(conn)
            conn.commit()
            self.assertEqual(1, conn.execute(
                "SELECT COUNT(*) FROM sorular").fetchone()[0])
        finally:
            conn.close()
        self.assertEqual(1, len(banka._v4_yedek_adlari(self.db)))

    def test_v4_alanlari_ekleme_sorgu_ve_disari_aktarimda_korunur(self):
        resim = Image.new("RGB", (96, 64), "white")
        meta = {
            "kaynak": "meta-kaynak.pdf",
            "soru_no": 3,
            "sayfa": 8,
            "metin": "Fotosentez hızını etkileyen etmen hangisidir?",
            "govde": "Fotosentez hızını etkileyen etmen hangisidir?",
            "siklar": {"A": "Işık", "B": "Ses"},
            "soru_turu": "coktan_secmeli",
            "sayfa_rolu": "soru",
            "guven": 0.91,
            "inceleme_durumu": "otomatik",
        }
        sonuc = banka.banka_ekle(
            [meta], [resim], kaynak="kitap.pdf", kaynak_hash="sha256:kitap",
            algoritma_surumu="v2.0", yol=self.db)
        self.assertEqual({"eklenen": 1, "atlanan": 0},
                         {k: sonuc[k] for k in ("eklenen", "atlanan")})
        sid = sonuc["idler"][0]

        kayit = banka.banka_kayit(sid, yol=self.db)
        self.assertEqual("kitap.pdf", kayit["kaynak"])
        self.assertEqual("sha256:kitap", kayit["kaynak_hash"])
        self.assertEqual("v2.0", kayit["algoritma_surumu"])
        self.assertEqual("coktan_secmeli", kayit["soru_turu"])
        self.assertEqual("soru", kayit["sayfa_rolu"])
        self.assertAlmostEqual(0.91, kayit["guven"])
        self.assertEqual("otomatik", kayit["inceleme_durumu"])

        sorgu = banka.banka_sorgula(
            kaynak_hash="sha256:kitap", algoritma_surumu="v2.0",
            soru_turu="coktan_secmeli", sayfa_rolu="soru",
            inceleme_durumu="otomatik", guven_min=0.90, guven_max=0.92,
            yol=self.db)
        self.assertEqual(1, sorgu["toplam"])
        self.assertEqual(sid, sorgu["kayitlar"][0]["id"])

        kirpmalar, disari_meta = banka.banka_getir([sid], yol=self.db)
        try:
            self.assertEqual(1, len(kirpmalar))
            for alan in ("kaynak_hash", "algoritma_surumu", "soru_turu",
                         "sayfa_rolu", "guven", "inceleme_durumu"):
                self.assertEqual(kayit[alan], disari_meta[0][alan])
        finally:
            for kirpma in kirpmalar:
                kirpma.close()

        filtreler = banka.banka_filtreler(yol=self.db)
        self.assertEqual(["coktan_secmeli"], filtreler["soru_turleri"])
        self.assertEqual(["soru"], filtreler["sayfa_rolleri"])
        self.assertEqual(["otomatik"], filtreler["inceleme_durumlari"])
        self.assertEqual(["v2.0"], filtreler["algoritma_surumleri"])

    def test_kaynak_goruntusu_ve_ozeti_kayitlari_degistirmez(self):
        resimler = [Image.new("RGB", (80, 50), renk)
                    for renk in ("white", "ivory")]
        metalar = [
            {
                "metin": "Birinci karşılaştırma sorusunun yeterince uzun metni",
                "kaynak": "kitap.pdf", "soru_no": 1,
                "algoritma_surumu": "v2.0", "soru_turu": "kisa_cevapli",
                "sayfa_rolu": "soru", "guven": 0.84,
                "inceleme_durumu": "otomatik",
            },
            {
                "metin": "İkinci karşılaştırma sorusunun yeterince uzun metni",
                "kaynak": "kitap.pdf", "soru_no": 2,
                "algoritma_surumu": "v2.0", "soru_turu": "acik_uclu",
                "sayfa_rolu": "karma", "guven": 0.61,
                "inceleme_durumu": "incele",
            },
        ]
        banka.banka_ekle(
            metalar, resimler, kaynak_hash="sha256:ortak", yol=self.db)

        conn = banka.baglan(self.db)
        try:
            once = [tuple(r) for r in conn.execute(
                "SELECT * FROM sorular ORDER BY id").fetchall()]
        finally:
            conn.close()

        goruntu = banka.banka_kaynak_kayitlari(
            kaynak="kitap.pdf", kaynak_hash="sha256:ortak",
            algoritma_surumu="v2.0", yol=self.db)
        self.assertEqual(2, goruntu["toplam"])
        self.assertEqual([1, 2], [k["soru_no"] for k in goruntu["kayitlar"]])

        ozet = banka.banka_kaynak_ozeti(
            kaynak_hash="sha256:ortak", yol=self.db)
        self.assertEqual(2, ozet["toplam"])
        self.assertEqual({"v2.0": 2}, ozet["algoritma_surumleri"])
        self.assertEqual({"otomatik": 1, "incele": 1},
                         ozet["inceleme_durumlari"])
        self.assertEqual(2, ozet["guven"]["bilinen"])
        self.assertAlmostEqual(0.725, ozet["guven"]["ortalama"])

        with self.assertRaisesRegex(ValueError, "kaynak"):
            banka.banka_kaynak_kayitlari(yol=self.db)

        conn = banka.baglan(self.db)
        try:
            sonra = [tuple(r) for r in conn.execute(
                "SELECT * FROM sorular ORDER BY id").fetchall()]
        finally:
            conn.close()
        self.assertEqual(once, sonra)

    def test_yeniden_isleme_ayri_tabloda_sahnelenir(self):
        eski = Image.new("RGB", (80, 50), "white")
        banka.banka_ekle([
            {"metin": "Eski TYT sorusu yeterince uzun", "kaynak": "tyt.pdf"}
        ], [eski], yol=self.db)
        adaylar = [
            {"sayfa": 4, "soru_no": 1, "kutu": [10, 20, 200, 300],
             "soru_turu": "çoktan_seçmeli", "sayfa_rolu": "soru",
             "guven": 0.93, "inceleme_durumu": "otomatik"},
            {"sayfa": 4, "soru_no": 2, "kutu": [210, 20, 400, 300],
             "soru_turu": "çoktan_seçmeli", "sayfa_rolu": "soru",
             "guven": 0.72, "inceleme_durumu": "incele"},
        ]
        sonuc = banka.banka_yeniden_isleme_sahnele(
            "tyt.pdf", adaylar, kaynak_hash="sha256:tyt",
            algoritma_surumu="2.1", yol=self.db)
        self.assertEqual(1, sonuc["eski_toplam"])
        self.assertEqual(2, sonuc["yeni_toplam"])
        self.assertEqual({"otomatik": 1, "incele": 1},
                         sonuc["inceleme_durumlari"])
        son = banka.banka_yeniden_isleme_son(
            kaynak="tyt.pdf", yol=self.db)
        self.assertEqual(sonuc["id"], son["id"])
        self.assertEqual("onay_bekliyor", son["durum"])
        conn = banka.baglan(self.db)
        try:
            self.assertEqual(1, conn.execute(
                "SELECT COUNT(*) FROM sorular").fetchone()[0])
            self.assertEqual(2, conn.execute(
                "SELECT COUNT(*) FROM yeniden_isleme_adaylari"
            ).fetchone()[0])
        finally:
            conn.close()


if __name__ == "__main__":
    unittest.main()
