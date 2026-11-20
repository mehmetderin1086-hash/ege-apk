#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Palme AYT exact-crop veri üreticisi için odaklı sentetik testler."""

import hashlib
import importlib.util
import io
import json
import os
import stat
import tempfile
import unittest
import zipfile

from PIL import Image, ImageDraw

import soru_model_palme_veri as palme


CV2_VAR = importlib.util.find_spec("cv2") is not None


def _jpeg_bayt(gorsel):
    tampon = io.BytesIO()
    gorsel.save(tampon, "JPEG", quality=95, subsampling=0)
    return tampon.getvalue()


def _sentetik_crop(genislik=180, yukseklik=120, tohum=1):
    gorsel = Image.new("RGB", (genislik, yukseklik), "white")
    ciz = ImageDraw.Draw(gorsel)
    # OpenCV HSV uzayında H≈90: turkuaz soru numarası çapası.
    ciz.rectangle((5, 7, 15, 22), fill=(0, 180, 180))
    ciz.rectangle((18, 19, 21, 22), fill=(0, 180, 180))
    ciz.rectangle((28, 8, genislik - 8, 11), fill=(20, 20, 20))
    for i in range(5):
        y = 30 + i * 13
        x1 = 20 + ((tohum * 17 + i * 23) % 70)
        ciz.line((28, y, min(genislik - 8, x1 + 75), y),
                 fill=(25 + i * 10, 25, 25), width=2)
    ciz.rectangle(
        (genislik - 48, yukseklik - 35, genislik - 12, yukseklik - 9),
        outline=(40 + tohum * 7, 70, 110),
        width=3,
    )
    return gorsel


def _sayfa_uret(yerlesimler, boyut=(500, 500)):
    sayfa = Image.new("RGB", boyut, (235, 235, 232))
    for crop, (x, y) in yerlesimler:
        sayfa.paste(crop, (x, y))
    return sayfa


def _zip_yaz(yol, uyeler):
    with zipfile.ZipFile(yol, "w", compression=zipfile.ZIP_DEFLATED) as arsiv:
        for ad, veri in uyeler:
            arsiv.writestr(ad, veri)


class AdlandirmaTesti(unittest.TestCase):
    def test_gecerli_ad_cozulur(self):
        self.assertEqual(
            (21, 2, 4, 177),
            palme.crop_adini_coz(
                "Soru_Fotograflari/Unite_21/Test_02/"
                "U21-T02-S04_Sayfa_177.jpg"
            ),
        )

    def test_baska_jpeg_adi_kabul_edilmez(self):
        self.assertIsNone(palme.crop_adini_coz("soru-4.jpg"))


class ZipGuvenligiTesti(unittest.TestCase):
    def test_yol_gecisi_reddedilir(self):
        with tempfile.TemporaryDirectory() as gecici:
            yol = os.path.join(gecici, "kotu.zip")
            _zip_yaz(
                yol,
                [("../U12-T01-S01_Sayfa_001.jpg", b"x")],
            )
            with self.assertRaisesRegex(palme.PalmeVeriHatasi, "geçiş"):
                palme.zip_denetle(yol)

    def test_sembolik_bag_reddedilir(self):
        with tempfile.TemporaryDirectory() as gecici:
            yol = os.path.join(gecici, "bag.zip")
            bilgi = zipfile.ZipInfo(
                "U12-T01-S01_Sayfa_001.jpg"
            )
            bilgi.create_system = 3
            bilgi.external_attr = (stat.S_IFLNK | 0o777) << 16
            with zipfile.ZipFile(yol, "w") as arsiv:
                arsiv.writestr(bilgi, b"hedef")
            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "sembolik",
            ):
                palme.zip_denetle(yol)

    def test_uye_ve_toplam_boyut_siniri(self):
        with tempfile.TemporaryDirectory() as gecici:
            yol = os.path.join(gecici, "sinir.zip")
            _zip_yaz(
                yol,
                [
                    ("not1.txt", b"12345"),
                    ("not2.txt", b"67890"),
                    ("U12-T01-S01_Sayfa_001.jpg", b"x"),
                ],
            )
            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "üye sınırını",
            ):
                palme.zip_denetle(yol, max_uye=2)
            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "toplam açılmış",
            ):
                palme.zip_denetle(yol, max_toplam_bayt=5)

    def test_tanimsiz_jpeg_sessizce_atlanmaz(self):
        with tempfile.TemporaryDirectory() as gecici:
            yol = os.path.join(gecici, "yanlis-ad.zip")
            _zip_yaz(yol, [("rastgele.jpg", b"x")])
            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "Ad sözleşmesine",
            ):
                palme.zip_denetle(yol)


@unittest.skipUnless(CV2_VAR, "OpenCV bu Python ortamında kurulu değil")
class EslemeVeVeriSetiTesti(unittest.TestCase):
    def test_turkuaz_capa_sol_ustten_deterministik_cikar(self):
        crop = _sentetik_crop()
        self.assertEqual(
            (4, 6, 23, 24),
            palme.turkuaz_capa_kutusu(crop),
        )

    def test_train_ve_tam_sayfa_tanisali_ayirir(self):
        with tempfile.TemporaryDirectory() as gecici:
            pdf = os.path.join(gecici, "kaynak.pdf")
            with open(pdf, "wb") as hedef:
                hedef.write(b"sentetik-pdf-kimligi")
            zip_yolu = os.path.join(gecici, "crop.zip")
            cikti = os.path.join(gecici, "veri")

            crop12 = _sentetik_crop(tohum=1)
            crop25 = _sentetik_crop(tohum=2)
            crop26 = _sentetik_crop(tohum=3)
            sayfa1 = _sayfa_uret([(crop12, (40, 55))])
            # Aynı sayfadaki U25 de, U26 nedeniyle bütünüyle tanısala gider.
            sayfa2 = _sayfa_uret([
                (crop25, (35, 45)),
                (crop26, (275, 260)),
            ])
            _zip_yaz(
                zip_yolu,
                [
                    (
                        "Soru_Fotograflari/Unite_12/Test_01/"
                        "U12-T01-S01_Sayfa_001.jpg",
                        _jpeg_bayt(crop12),
                    ),
                    (
                        "Soru_Fotograflari/Unite_25/Test_02/"
                        "U25-T02-S03_Sayfa_002.jpg",
                        _jpeg_bayt(crop25),
                    ),
                    (
                        "Soru_Fotograflari/Unite_26/Test_01/"
                        "U26-T01-S01_Sayfa_002.jpg",
                        _jpeg_bayt(crop26),
                    ),
                    ("Soru_Fotograflari/README.txt", b"sentetik"),
                ],
            )
            sayfalar = {1: sayfa1, 2: sayfa2}
            cagrilar = []

            def renderer(_pdf, sayfa, dpi):
                cagrilar.append((sayfa, dpi))
                return sayfalar[sayfa].copy()

            sonuc = palme.palme_veri_seti_uret(
                pdf,
                zip_yolu,
                cikti,
                renderer=renderer,
                min_skor=0.60,
            )

            self.assertTrue(sonuc["ok"])
            self.assertEqual([(1, 130), (2, 130)], cagrilar)
            with open(sonuc["manifest"], encoding="utf-8") as kaynak:
                manifest = json.load(kaynak)
            with open(
                sonuc["diagnostic_manifest"],
                encoding="utf-8",
            ) as kaynak:
                tanisal = json.load(kaynak)
            with open(sonuc["report"], encoding="utf-8") as kaynak:
                rapor = json.load(kaynak)

            self.assertEqual(list(palme.SINIFLAR), manifest["classes"])
            self.assertEqual(1, len(manifest["splits"]["train"]))
            self.assertEqual([], manifest["splits"]["holdout"])
            self.assertEqual(1, manifest["splits"]["train"][0]["page"])
            self.assertEqual(
                "verified_crop_alignment",
                manifest["splits"]["train"][0]["annotation_origin"],
            )
            self.assertEqual(1, len(tanisal["samples"]))
            self.assertEqual(2, tanisal["samples"][0]["page"])
            self.assertEqual(
                hashlib.sha256(b"sentetik-pdf-kimligi").hexdigest(),
                tanisal["samples"][0]["document_sha256"],
            )
            self.assertEqual(
                {"train_pages": 1, "diagnostic_holdout_pages": 1,
                 "question_count": 3, "train_questions": 1,
                 "diagnostic_holdout_questions": 2},
                rapor["summary"],
            )
            sayfa2_rapor = next(p for p in rapor["pages"] if p["page"] == 2)
            self.assertEqual("diagnostic_holdout",
                             sayfa2_rapor["partition"])
            self.assertEqual([25, 26], sayfa2_rapor["units"])
            self.assertEqual(
                [40, 55, 220, 175],
                rapor["pages"][0]["questions"][0]["body_box"],
            )

            train_label = os.path.join(
                cikti,
                manifest["splits"]["train"][0]["label"],
            )
            tanisal_label = os.path.join(
                cikti,
                tanisal["samples"][0]["label"],
            )
            with open(train_label, encoding="utf-8") as kaynak:
                train_satir = kaynak.read().splitlines()
            with open(tanisal_label, encoding="utf-8") as kaynak:
                tanisal_satir = kaynak.read().splitlines()
            self.assertEqual(["0", "1"],
                             [s.split()[0] for s in train_satir])
            self.assertEqual(["0", "1", "0", "1"],
                             [s.split()[0] for s in tanisal_satir])

    def test_dusuk_skor_kismi_cikti_birakmaz(self):
        with tempfile.TemporaryDirectory() as gecici:
            pdf = os.path.join(gecici, "kaynak.pdf")
            with open(pdf, "wb") as hedef:
                hedef.write(b"pdf")
            zip_yolu = os.path.join(gecici, "crop.zip")
            cikti = os.path.join(gecici, "veri")
            crop = _sentetik_crop()
            _zip_yaz(
                zip_yolu,
                [("U12-T01-S01_Sayfa_001.jpg", _jpeg_bayt(crop))],
            )
            ilgisiz = Image.new("RGB", (500, 500), (120, 130, 140))
            ciz = ImageDraw.Draw(ilgisiz)
            ciz.ellipse((200, 200, 310, 330), fill=(240, 20, 30))

            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "eşleşme skoru düşük",
            ):
                palme.palme_veri_seti_uret(
                    pdf,
                    zip_yolu,
                    cikti,
                    renderer=lambda *_: ilgisiz.copy(),
                    min_skor=0.95,
                )
            self.assertFalse(os.path.exists(cikti))

    def test_ayni_yere_eslesen_iki_soru_reddedilir(self):
        with tempfile.TemporaryDirectory() as gecici:
            pdf = os.path.join(gecici, "kaynak.pdf")
            with open(pdf, "wb") as hedef:
                hedef.write(b"pdf")
            zip_yolu = os.path.join(gecici, "crop.zip")
            cikti = os.path.join(gecici, "veri")
            crop = _sentetik_crop()
            jpeg = _jpeg_bayt(crop)
            _zip_yaz(
                zip_yolu,
                [
                    ("U12-T01-S01_Sayfa_001.jpg", jpeg),
                    ("U12-T01-S02_Sayfa_001.jpg", jpeg),
                ],
            )
            sayfa = _sayfa_uret([(crop, (80, 90))])
            with self.assertRaisesRegex(
                palme.PalmeVeriHatasi,
                "yinelenen/örtüşen",
            ):
                palme.palme_veri_seti_uret(
                    pdf,
                    zip_yolu,
                    cikti,
                    renderer=lambda *_: sayfa.copy(),
                    min_skor=0.60,
                )
            self.assertFalse(os.path.exists(cikti))


if __name__ == "__main__":
    unittest.main()
