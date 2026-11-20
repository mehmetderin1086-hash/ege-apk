#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Palme 11 crop-alignment veri üreticisinin sentetik güvenlik testleri."""

import csv
import hashlib
import io
import json
import os
import tempfile
import unittest
import zipfile

from PIL import Image, ImageDraw

import soru_model_palme11_veri as p11


try:
    import cv2  # noqa: F401
    import numpy  # noqa: F401
except ImportError:
    OPENCV_VAR = False
else:
    OPENCV_VAR = True


def _sha256(yol):
    ozet = hashlib.sha256()
    with open(yol, "rb") as dosya:
        for parca in iter(lambda: dosya.read(1 << 20), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _png_bayt(gorsel):
    tampon = io.BytesIO()
    gorsel.save(tampon, "PNG")
    return tampon.getvalue()


def _sentetik_crop(tohum):
    crop = Image.new("RGB", (160, 120), "white")
    ciz = ImageDraw.Draw(crop)
    ciz.rectangle((5, 5, 25, 25), fill=(242, 105, 5))
    for sira in range(8):
        y = 36 + sira * 9
        x1 = 45 + ((tohum * 17 + sira * 23) % 100)
        ciz.line((12, y, x1, y), fill=(20 + sira * 8,) * 3, width=2)
    ciz.rectangle(
        (105, 15 + tohum, 145, 31 + tohum),
        outline=(40, 70, 110),
        width=2,
    )
    return crop


class Palme11VeriTesti(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory()
        self.kok = self.gecici.name

    def tearDown(self):
        self.gecici.cleanup()

    def _standart_zip(self, ad, uyeler):
        yol = os.path.join(self.kok, ad)
        with zipfile.ZipFile(yol, "w", zipfile.ZIP_STORED) as arsiv:
            for uye, gorsel in uyeler:
                arsiv.writestr(uye, _png_bayt(gorsel))
        return yol

    def _profil(self, kimlik, book_id, zip_yolu, crop_sayisi, **ek):
        return p11.Palme11Profili(
            kimlik=kimlik,
            book_id=book_id,
            dosya_turu=ek.get("dosya_turu", "standard"),
            crop_dpi=ek.get("crop_dpi", 100),
            pdf_sha256=ek.get("pdf_sha256"),
            pdf_bayt=ek.get("pdf_bayt"),
            pdf_sayfa=ek.get("pdf_sayfa"),
            zip_sha256=_sha256(zip_yolu),
            zip_bayt=os.path.getsize(zip_yolu),
            crop_sayisi=crop_sayisi,
            metadata_hashleri=ek.get("metadata_hashleri", ()),
        )

    def test_zip_traversal_fail_closed(self):
        zip_yolu = os.path.join(self.kok, "kotu.zip")
        with zipfile.ZipFile(zip_yolu, "w") as arsiv:
            arsiv.writestr("../u01_mini01_q01_p001.png", b"not-a-png")
        profil = self._profil("test", "book-test", zip_yolu, 1)
        with self.assertRaisesRegex(
                p11.Palme11VeriHatasi, "yol geçişi"):
            p11.zip_denetle(zip_yolu, profil)

    def test_fen_csv_png_kimligi_ve_metadata_hashleri_dogrulanir(self):
        crop = _sentetik_crop(1)
        png_rel = "questions_png/U01_MS01_Q01_p001.png"
        png_uye = "Palme11_1057_Soru_PNG/" + png_rel
        alanlar = list(p11._FEN_CSV_ALANLARI)
        tampon = io.StringIO()
        yazici = csv.DictWriter(tampon, fieldnames=alanlar)
        yazici.writeheader()
        yazici.writerow({
            "id": "U01_MS01_Q01",
            "ünite": "1",
            "ünite_adı": "Sinir Sistemi",
            "sınav_türü": "mini",
            "sınav_no": "1",
            "soru_no": "1",
            "kaynak_sayfa": "1",
            "konu": "örnek",
            "cevap": "A",
            "png": png_rel,
        })
        csv_bayt = tampon.getvalue().encode("utf-8")
        readme_bayt = b"# Sentetik test\n"
        zip_yolu = os.path.join(self.kok, "fen.zip")
        with zipfile.ZipFile(zip_yolu, "w", zipfile.ZIP_STORED) as arsiv:
            arsiv.writestr("Palme11_1057_Soru_PNG/", b"")
            arsiv.writestr(
                "Palme11_1057_Soru_PNG/questions_png/", b"")
            arsiv.writestr(png_uye, _png_bayt(crop))
            arsiv.writestr(p11._FEN_MANIFEST, csv_bayt)
            arsiv.writestr(p11._FEN_README, readme_bayt)
        metadata = (
            (p11._FEN_MANIFEST, hashlib.sha256(csv_bayt).hexdigest()),
            (p11._FEN_README, hashlib.sha256(readme_bayt).hexdigest()),
        )
        profil = self._profil(
            "fen-test",
            "book-fen-test",
            zip_yolu,
            1,
            dosya_turu="fen",
            metadata_hashleri=metadata,
        )

        rapor = p11.zip_denetle(zip_yolu, profil)
        self.assertEqual(rapor["crop_count"], 1)
        self.assertEqual(rapor["member_count"], 5)
        self.assertEqual(rapor["csv"]["rows"], 1)
        self.assertEqual(rapor["csv"]["empty_fields"], 0)
        self.assertEqual(
            rapor["metadata_sha256"][p11._FEN_MANIFEST],
            hashlib.sha256(csv_bayt).hexdigest(),
        )

    def _sahte_pdfinfo(self, sayfa=2):
        """PATH'e pdfinfo biçiminde çıktı veren bir vekil koyar.

        Proje poppler'ı bilinçli olarak bağımlılık yapmıyor (bkz. README);
        testi poppler varlığına bağlamak onu çoğu makinede kırmızı bırakırdı.
        Sınanması gereken şey zaten poppler'ın kendisi değil, bizim çağrı ve
        `Pages:` ayrıştırma yolumuz — vekil tam onu koşturur.
        """
        kutu = os.path.join(self.kok, "sahte-bin")
        os.makedirs(kutu, exist_ok=True)
        vekil = os.path.join(kutu, "pdfinfo")
        with open(vekil, "w", encoding="utf-8") as dosya:
            dosya.write(
                "#!/bin/sh\n"
                'printf "Title:          deneme\\n"\n'
                'printf "Pages:          %d\\n"\n' % sayfa
            )
        os.chmod(vekil, 0o755)
        onceki = os.environ.get("PATH", "")
        os.environ["PATH"] = kutu + os.pathsep + onceki
        self.addCleanup(os.environ.__setitem__, "PATH", onceki)

    def test_pdfinfo_sayfa_sayisini_pypdf_olmadan_dogrular(self):
        self._sahte_pdfinfo(sayfa=2)
        pdf_yolu = os.path.join(self.kok, "iki-sayfa.pdf")
        ilk = Image.new("RGB", (80, 100), "white")
        ikinci = Image.new("RGB", (80, 100), (240, 240, 240))
        ilk.save(pdf_yolu, "PDF", save_all=True, append_images=[ikinci])
        sahte_zip = os.path.join(self.kok, "bos.zip")
        with zipfile.ZipFile(sahte_zip, "w"):
            pass
        profil = p11.Palme11Profili(
            kimlik="pdfinfo-test",
            book_id="book-pdfinfo-test",
            dosya_turu="standard",
            crop_dpi=100,
            pdf_sha256=_sha256(pdf_yolu),
            pdf_bayt=os.path.getsize(pdf_yolu),
            pdf_sayfa=2,
            zip_sha256=_sha256(sahte_zip),
            zip_bayt=os.path.getsize(sahte_zip),
            crop_sayisi=0,
        )
        rapor = p11._pdf_kimligini_dogrula(
            p11.Palme11Kaynagi(profil, pdf_yolu, sahte_zip))
        self.assertEqual(rapor["pages"], 2)

    @unittest.skipUnless(OPENCV_VAR, "OpenCV/numpy yok")
    def test_govde_kutusu_kenar_cizgisini_yoksayip_son_boslugu_kirpar(self):
        crop = Image.new("RGB", (200, 180), "white")
        ciz = ImageDraw.Draw(crop)
        ciz.line((199, 0, 199, 179), fill=(0, 170, 170), width=1)
        ciz.rectangle((8, 5, 25, 24), fill=(242, 105, 5))
        ciz.line((35, 14, 160, 14), fill="black", width=3)
        ciz.line((20, 70, 150, 70), fill="black", width=2)
        kutu = p11.govde_icerik_kutusu((50, 80, 250, 260), crop)
        self.assertEqual(kutu[:3], (50, 80, 250))
        self.assertLess(kutu[3], 180)
        self.assertGreaterEqual(kutu[3], 150)

    @unittest.skipUnless(OPENCV_VAR, "OpenCV/numpy yok")
    def test_train_ve_unit12_diagnostic_atomik_uretilir(self):
        train_crop = _sentetik_crop(2)
        diagnostic_crop = _sentetik_crop(5)
        zip_yolu = self._standart_zip("standart.zip", (
            (
                "unit_01_sinir/png/u01_mini01_q01_p001.png",
                train_crop,
            ),
            (
                "unit_12_komunite/png/u12_test01_q01_p002.png",
                diagnostic_crop,
            ),
        ))
        pdf_yolu = os.path.join(self.kok, "kaynak.pdf")
        with open(pdf_yolu, "wb") as dosya:
            dosya.write(b"sentetik-pdf-kimligi")
        profil = self._profil(
            "standard-test",
            "book-standard-test",
            zip_yolu,
            2,
            crop_dpi=100,
            pdf_sha256=_sha256(pdf_yolu),
            pdf_bayt=os.path.getsize(pdf_yolu),
        )
        sayfalar = {}
        for sayfa, crop, yer in (
                (1, train_crop, (45, 70)),
                (2, diagnostic_crop, (185, 250))):
            gorsel = Image.new("RGB", (420, 540), "white")
            gorsel.paste(crop, yer)
            sayfalar[sayfa] = gorsel

        def renderer(_pdf, sayfa, dpi):
            self.assertEqual(dpi, 100)
            return sayfalar[sayfa].copy()

        cikti = os.path.join(self.kok, "cikti")
        sonuc = p11.palme11_veri_seti_uret(
            [p11.Palme11Kaynagi(profil, pdf_yolu, zip_yolu)],
            cikti,
            dpi=100,
            min_skor=0.90,
            min_uzak_fark=0.20,
            renderer=renderer,
        )
        self.assertTrue(sonuc["ok"])
        self.assertEqual(sonuc["summary"]["train_pages"], 1)
        self.assertEqual(
            sonuc["summary"]["diagnostic_holdout_pages"], 1)
        self.assertEqual(sonuc["summary"]["question_count"], 2)
        with open(sonuc["manifest"], encoding="utf-8") as dosya:
            manifest = json.load(dosya)
        with open(sonuc["diagnostic_manifest"],
                  encoding="utf-8") as dosya:
            diagnostic = json.load(dosya)
        self.assertEqual(len(manifest["splits"]["train"]), 1)
        self.assertFalse(manifest["splits"]["holdout"])
        self.assertEqual(len(diagnostic["samples"]), 1)
        self.assertEqual(diagnostic["samples"][0]["page"], 2)
        self.assertEqual(
            diagnostic["samples"][0]["annotation_origin"],
            p11.ETIKET_KAYNAGI,
        )
        self.assertGreaterEqual(
            manifest["splits"]["train"][0]["alignment_score"], 0.90)
        self.assertGreaterEqual(
            manifest["splits"]["train"][0]["alignment_remote_gap"], 0.20)
        self.assertEqual(
            manifest["splits"]["train"][0]["source_profile"],
            "standard-test",
        )
        self.assertEqual(
            manifest["splits"]["train"][0]["source_archive_sha256"],
            _sha256(zip_yolu),
        )
        self.assertTrue(os.path.isfile(sonuc["report"]))

    @unittest.skipUnless(OPENCV_VAR, "OpenCV/numpy yok")
    def test_eslesme_kapisi_hatasinda_kismi_cikti_birakmaz(self):
        crop = _sentetik_crop(7)
        zip_yolu = self._standart_zip("standart.zip", (
            (
                "unit_01_sinir/png/u01_mini01_q01_p001.png",
                crop,
            ),
        ))
        pdf_yolu = os.path.join(self.kok, "kaynak.pdf")
        with open(pdf_yolu, "wb") as dosya:
            dosya.write(b"sentetik-pdf")
        profil = self._profil(
            "standard-test",
            "book-standard-test",
            zip_yolu,
            1,
            pdf_sha256=_sha256(pdf_yolu),
            pdf_bayt=os.path.getsize(pdf_yolu),
        )
        bos_sayfa = Image.new("RGB", (420, 540), "white")
        cikti = os.path.join(self.kok, "cikti")
        with self.assertRaisesRegex(
                p11.Palme11VeriHatasi, "eşleşme skoru düşük"):
            p11.palme11_veri_seti_uret(
                [p11.Palme11Kaynagi(profil, pdf_yolu, zip_yolu)],
                cikti,
                dpi=100,
                min_skor=0.90,
                min_uzak_fark=0.20,
                renderer=lambda _pdf, _sayfa, _dpi: bos_sayfa,
            )
        self.assertFalse(os.path.lexists(cikti))


if __name__ == "__main__":
    unittest.main()
