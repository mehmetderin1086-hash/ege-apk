#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Optik okuma altın testleri — uçtan uca: form üret → sentetik doldur →
işçiyle oku → hüküm doğrula.

.venv-ml (cv2) kuruluysa koşar; değilse atlanır. Senaryolar:
temiz 200 dpi tarama, telefon fotoğrafı (perspektif + ışık gradyanı +
JPEG), %98.5 fotokopi ölçeği @150 dpi, 3 işaretçi (biri kapalı),
silik işaret, X ile iptal + yeniden işaretleme, çift işaret.
"""
import json
import os
import subprocess
import tempfile
import time
import unittest

import optik_sema as osm

PROJE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ISCI_PY = os.path.join(PROJE, ".venv-ml", "bin", "python")
ISCI_BETIK = os.path.join(PROJE, "optik_isci.py")


def _isci_var():
    if not (os.path.isfile(ISCI_PY) and os.path.isfile(ISCI_BETIK)):
        return False
    try:
        s = subprocess.run([ISCI_PY, ISCI_BETIK, "--probe"],
                           capture_output=True, text=True, timeout=90)
        ilk = (s.stdout or "").strip().splitlines()
        return bool(ilk and json.loads(ilk[0]).get("ok"))
    except Exception:  # noqa: BLE001
        return False


ISCI_HAZIR = _isci_var()

# Beklenen cevaplar: soru → şık indeksi ('ABCD'), None = boş
CEVAPLAR = {1: 0, 2: 1, 3: 2, 4: 3, 5: 0, 6: 1, 7: 2, 8: 3,
            9: 0, 10: 1, 11: 2, 12: 3, 13: 0, 14: 1, 15: 2}
# 16-20 boş; 6 silik doldurulur; 9'da A'ya X çekilip C yeniden işaretlenir
SILIK = {6}
IPTAL_VE_YENIDEN = {9: (0, 2)}      # (iptal edilen şık, gerçek şık)
OGRENCI_NO = "34125"
KITAPCIK = 0                        # A


@unittest.skipUnless(ISCI_HAZIR, "optik işçisi (.venv-ml + cv2) kurulu değil")
class GoldenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import optik_form as of
        cls.dizin = tempfile.TemporaryDirectory()
        yol = os.path.join(cls.dizin.name, "golden.pdf")
        cls.sonuc = of.form_uret(on_ayar="yazili-20", yol=yol,
                                 tanim={"kitapcik": 2})
        cls.sablon = cls.sonuc["sablon"]
        cls.sablon_yolu = cls.sonuc["sablon_yolu"]
        cls.taban = cls._doldurulmus(dpi=200)

    @classmethod
    def tearDownClass(cls):
        import optik_oku
        optik_oku.kapat()
        cls.dizin.cleanup()

    # ----------------------------------------------------------- yardımcılar

    @classmethod
    def _doldurulmus(cls, dpi=200):
        """Formu render edip bilinen cevapları sentetik doldurur (PIL)."""
        import fitz
        from PIL import Image, ImageDraw
        ol = dpi / 72.0
        doc = fitz.open(cls.sonuc["pdf"])
        pix = doc[0].get_pixmap(matrix=fitz.Matrix(ol, ol))
        img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
        doc.close()
        ciz = ImageDraw.Draw(img)

        def balon(alan, r, c, stil="dolu"):
            hedef = next((m for m in osm.baloncuk_merkezleri(alan)
                          if m[0] == r and m[1] == c), None)
            _, _, x, y = hedef
            x, y = x * ol, y * ol
            yari = alan.hucre.cap / 2 * ol
            if stil == "dolu":
                ciz.ellipse([x - yari * .85, y - yari * .85,
                             x + yari * .85, y + yari * .85],
                            fill=(45, 45, 45))
            elif stil == "silik":
                ciz.ellipse([x - yari * .6, y - yari * .6,
                             x + yari * .6, y + yari * .6],
                            fill=(150, 150, 150))
            elif stil == "iptal":
                w = max(2, int(yari * .3))
                ciz.line([x - yari, y - yari, x + yari, y + yari],
                         fill=(60, 60, 60), width=w)
                ciz.line([x - yari, y + yari, x + yari, y - yari],
                         fill=(60, 60, 60), width=w)

        for _, alan in cls.sablon.cevap_alanlari():
            for no, sik in CEVAPLAR.items():
                r = no - alan.soru_baslangic
                if not 0 <= r < alan.soru_sayisi:
                    continue
                if no in IPTAL_VE_YENIDEN:
                    iptal, yeni = IPTAL_VE_YENIDEN[no]
                    balon(alan, r, iptal, "iptal")
                    balon(alan, r, yeni, "dolu")
                else:
                    balon(alan, r, sik, "silik" if no in SILIK else "dolu")
        ogr = cls.sablon.alan_bul("ogrenci_no")
        for c, h in enumerate(OGRENCI_NO):
            balon(ogr, int(h), c)
        balon(cls.sablon.alan_bul("kitapcik"), 0, KITAPCIK)
        return img

    def _oku(self, img, kalite=None, ad="t.png"):
        import optik_oku as ook
        yol = os.path.join(self.dizin.name, ad)
        if kalite:
            img.save(yol, quality=kalite)
        else:
            img.save(yol)
        yanit = ook.isci_istek({"png": yol, "sablon": self.sablon_yolu,
                                "warp_png": None})
        hukumler = ook.hukum_ver(yanit["olcumler"], self.sablon,
                                 yanit["sayfa_no"])
        kagit = ook.kagit_birlestir(hukumler, self.sablon,
                                    yanit["sayfa_no"],
                                    yanit.get("kayit"), yanit.get("qr"))
        return yanit, kagit

    def _cevaplari_dogrula(self, kagit):
        sorular = kagit["cevaplar"][""]
        for no, sik in CEVAPLAR.items():
            g = sorular[str(no)]
            if no in IPTAL_VE_YENIDEN:
                beklenen = "ABCD"[IPTAL_VE_YENIDEN[no][1]]
            else:
                beklenen = "ABCD"[sik]
            self.assertEqual(g["hukum"], "tek",
                             f"soru {no}: {g}")
            self.assertEqual(g["sembol"], beklenen, f"soru {no}")
        for no in range(16, 21):
            self.assertEqual(sorular[str(no)]["hukum"], "bos",
                             f"soru {no} boş olmalı")
        self.assertEqual(kagit["ogrenci_no"], OGRENCI_NO)
        self.assertEqual(kagit["kitapcik"], "ABCD"[KITAPCIK])

    # ------------------------------------------------------------- senaryolar

    def test_01_temiz_tarama(self):
        bas = time.time()
        yanit, kagit = self._oku(self.taban, ad="temiz.png")
        sure = time.time() - bas
        self.assertEqual(yanit["sayfa_no"], 1)
        self.assertIn("aruco", yanit["kayit"]["yontem"])
        self.assertEqual(yanit["kayit"]["isaretci_sayisi"], 4)
        self.assertLess(yanit["kayit"]["yeniden_yansitma_px"], 2.0)
        self.assertEqual(osm.qr_coz(yanit["qr"])["sinav_id"],
                         self.sablon.sinav_id)
        self._cevaplari_dogrula(kagit)
        self.assertEqual(kagit["durum"], "okundu", kagit["sorunlar"])
        # sıcak işçide sayfa başına süre makul kalmalı
        self.assertLess(sure, 10.0)

    def test_02_telefon_fotografi(self):
        import numpy as np
        from PIL import Image
        img = self.taban
        w, h = img.size
        pay = 80
        tuval = Image.new("RGB", (w + 2 * pay, h + 2 * pay), (70, 62, 55))
        tuval.paste(img, (pay, pay))
        W, H = tuval.size
        hedef = [(pay + 50, pay + 35), (W - pay + 20, pay + 62),
                 (W - pay - 38, H - pay - 12), (pay + 18, H - pay - 48)]
        kaynak = [(0, 0), (W, 0), (W, H), (0, H)]
        A, B = [], []
        for (x, y), (u, v) in zip(hedef, kaynak):
            A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); B.append(u)
            A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); B.append(v)
        kats = np.linalg.solve(np.asarray(A, float), np.asarray(B, float))
        foto = tuval.transform((W, H), Image.PERSPECTIVE,
                               data=tuple(kats), resample=Image.BICUBIC,
                               fillcolor=(70, 62, 55))
        arr = np.asarray(foto).astype(np.float32)
        gy = np.linspace(0.74, 1.05, arr.shape[0])[:, None]
        gx = np.linspace(1.06, 0.84, arr.shape[1])[None, :]
        foto = Image.fromarray(
            np.clip(arr * (gy * gx)[..., None], 0, 255).astype(np.uint8))
        yanit, kagit = self._oku(foto, kalite=82, ad="foto.jpg")
        self.assertIn("aruco", yanit["kayit"]["yontem"])
        self._cevaplari_dogrula(kagit)

    def test_03_fotokopi_150dpi(self):
        from PIL import Image
        img = self._doldurulmus(dpi=150)
        w, h = img.size
        kucuk = img.resize((int(w * 0.985), int(h * 0.985)),
                           Image.LANCZOS)
        tuval = Image.new("RGB", (w, h), (255, 255, 255))
        tuval.paste(kucuk, ((w - kucuk.width) // 2,
                            (h - kucuk.height) // 2))
        yanit, kagit = self._oku(tuval, ad="fotokopi.png")
        self.assertIn("aruco", yanit["kayit"]["yontem"])
        self._cevaplari_dogrula(kagit)

    def test_04_uc_isaretci(self):
        from PIL import Image, ImageDraw
        img = self.taban.copy()
        ciz = ImageDraw.Draw(img)
        ciz.rectangle([img.width - 150, img.height - 150,
                       img.width, img.height], fill=(255, 255, 255))
        yanit, kagit = self._oku(img, ad="3isaretci.png")
        self.assertIn("aruco", yanit["kayit"]["yontem"])
        self.assertEqual(yanit["kayit"]["isaretci_sayisi"], 3)
        self._cevaplari_dogrula(kagit)

    def test_05_cift_isaret_kuyruga(self):
        from PIL import ImageDraw
        img = self.taban.copy()
        ciz = ImageDraw.Draw(img)
        alan = next(a for _, a in self.sablon.cevap_alanlari()
                    if a.soru_baslangic <= 17
                    < a.soru_baslangic + a.soru_sayisi)
        ol = 200 / 72.0
        r = 17 - alan.soru_baslangic
        for c in (0, 2):
            hedef = next(m for m in osm.baloncuk_merkezleri(alan)
                         if m[0] == r and m[1] == c)
            x, y = hedef[2] * ol, hedef[3] * ol
            yari = alan.hucre.cap / 2 * ol * .85
            ciz.ellipse([x - yari, y - yari, x + yari, y + yari],
                        fill=(45, 45, 45))
        yanit, kagit = self._oku(img, ad="cift.png")
        g = kagit["cevaplar"][""]["17"]
        self.assertEqual(g["hukum"], "coklu")
        self.assertEqual(sorted(g["adaylar"]), ["A", "C"])
        self.assertEqual(kagit["durum"], "incelenecek")


if __name__ == "__main__":
    unittest.main()
