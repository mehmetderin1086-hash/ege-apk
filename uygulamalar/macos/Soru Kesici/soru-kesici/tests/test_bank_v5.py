#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soru bankası V5: şablonlar, tarih filtresi, blueprint kotalı örnekleme,
toplu düzenleme, mükerrer raporu (Faz D)."""

import os
import tempfile
import time
import unittest

from PIL import Image

import soru_bankasi as banka


def _soru(no, konu, zorluk, cevap="A", metin=None):
    return {"soru_no": no, "test_no": None, "test_sira": None,
            "sayfa": 1, "cevap": cevap, "konu": konu, "zorluk": zorluk,
            "metin": metin or f"{konu} sorusu {no} gövde metni yeterince uzun",
            "govde": metin or f"{konu} sorusu {no} gövde metni yeterince uzun",
            "siklar": {"A": "birinci", "B": "ikinci"}, "kaynak_kutu": [0, 0],
            "numara_px": None}


def _img(t=0):
    return Image.new("RGB", (60 + t, 40), (t % 255, 0, 0))


class BankaV5Testi(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory(prefix="banka_v5_")
        self.db = os.path.join(self.gecici.name, "banka.db")
        # Karışık konu/zorluk havuzu
        sorular, imgler = [], []
        n = 0
        for konu, zorluk, adet in [("Mitoz", "kolay", 6), ("Mitoz", "zor", 4),
                                   ("Fotosentez", "orta", 5),
                                   ("Fotosentez", "kolay", 3)]:
            for _ in range(adet):
                n += 1
                sorular.append(_soru(n, konu, zorluk))
                imgler.append(_img(n))
        banka.banka_ekle(sorular, imgler, kaynak="test.pdf", yol=self.db)

    def tearDown(self):
        self.gecici.cleanup()

    def test_v5_sema_surumu(self):
        conn = banka.baglan(self.db)
        try:
            self.assertEqual(5, conn.execute(
                "PRAGMA user_version").fetchone()[0])
            # tablo var
            self.assertTrue(conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table' "
                "AND name='sinav_sablonlari'").fetchone())
        finally:
            conn.close()

    def test_istatistik_konu_zorluk_caprazi(self):
        st = banka.banka_istatistik(yol=self.db)
        self.assertEqual(st["konu_zorluk"]["Mitoz"]["kolay"], 6)
        self.assertEqual(st["konu_zorluk"]["Mitoz"]["zor"], 4)
        self.assertEqual(st["konu_zorluk"]["Fotosentez"]["orta"], 5)

    def test_blueprint_kotali_secim(self):
        r = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "kolay", "adet": 3},
             {"konu": "Mitoz", "zorluk": "zor", "adet": 2}],
            tohum=42, yol=self.db)
        self.assertEqual(len(r["idler"]), 5)
        self.assertEqual(r["eksik_toplam"], 0)
        # hücreler arası tekilleşme: id kümesi ayrık
        self.assertEqual(len(set(r["idler"])), 5)

    def test_blueprint_eksik_kota_raporlar(self):
        r = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "zor", "adet": 10}],  # yalnız 4 var
            tohum=1, yol=self.db)
        self.assertEqual(r["hucreler"][0]["bulunan"], 4)
        self.assertEqual(r["hucreler"][0]["eksik"], 6)
        self.assertEqual(r["eksik_toplam"], 6)

    def test_blueprint_tohum_tekrarlanabilir(self):
        a = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "kolay", "adet": 3}],
            tohum=7, yol=self.db)["idler"]
        b = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "kolay", "adet": 3}],
            tohum=7, yol=self.db)["idler"]
        self.assertEqual(a, b)

    def test_blueprint_haric_idler(self):
        ilk = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "kolay", "adet": 6}],
            tohum=1, yol=self.db)["idler"]
        r = banka.banka_blueprint_sec(
            [{"konu": "Mitoz", "zorluk": "kolay", "adet": 1}],
            tohum=2, haric_idler=ilk, yol=self.db)
        self.assertEqual(r["hucreler"][0]["bulunan"], 0)  # hepsi hariç

    def test_toplu_guncelle(self):
        r0 = banka.banka_sorgula(konu="Mitoz", limit=100, yol=self.db)
        idler = [k["id"] for k in r0["kayitlar"]][:3]
        banka.banka_toplu_guncelle(idler, zorluk="cok_zor",
                                   etiket_ekle={"kazanim": "K1"}, yol=self.db)
        r1 = banka.banka_sorgula(zorluk="cok_zor", limit=100, yol=self.db)
        self.assertEqual(r1["toplam"], 3)
        self.assertEqual(r1["kayitlar"][0]["etiketler"].get("kazanim"), "K1")

    def test_mukerrer_rapor(self):
        # aynı ilk soruyu tekrar ver → mükerrer, yeni bir soru → yeni
        var = _soru(1, "Mitoz", "kolay")
        yeni = _soru(999, "YeniKonu", "orta")
        r = banka.banka_mukerrer_rapor([var, yeni], [_img(1), _img(200)],
                                       yol=self.db)
        self.assertEqual(r["mukerrer"], 1)
        self.assertEqual(r["yeni"], 1)

    def test_tarih_filtresi(self):
        # yarının tarihinden sonrası boş olmalı
        yarin = time.strftime("%Y-%m-%d",
                              time.localtime(time.time() + 86400))
        r = banka.banka_sorgula(tarih_bas=yarin, limit=100, yol=self.db)
        self.assertEqual(r["toplam"], 0)
        # 2000'den bugüne hepsi
        r2 = banka.banka_sorgula(tarih_bas="2000-01-01", limit=100,
                                 yol=self.db)
        self.assertEqual(r2["toplam"], 18)

    def test_sablon_crud(self):
        veri = {"surum": 1, "hucreler": [{"konu": "Mitoz", "adet": 5}]}
        r = banka.sablon_kaydet("11. Sınıf Deneme", veri, yol=self.db)
        sid = r["id"]
        liste = banka.sablon_liste(yol=self.db)
        self.assertEqual(len(liste), 1)
        self.assertEqual(liste[0]["ad"], "11. Sınıf Deneme")
        getir = banka.sablon_getir(sid, yol=self.db)
        self.assertEqual(getir["veri"]["hucreler"][0]["konu"], "Mitoz")
        banka.sablon_kaydet("Güncel", {"surum": 1}, sablon_id=sid, yol=self.db)
        self.assertEqual(banka.sablon_getir(sid, yol=self.db)["ad"], "Güncel")
        banka.sablon_sil(sid, yol=self.db)
        self.assertEqual(banka.sablon_liste(yol=self.db), [])


if __name__ == "__main__":
    unittest.main()
