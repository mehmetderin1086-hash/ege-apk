#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ql_v4 birleştiricinin sentetik, dosya-sistemi düzeyi testleri."""

import errno
import hashlib
import json
import os
import tempfile
import unittest
from unittest import mock

from PIL import Image

import soru_model_v4_birlestir as v4


class _VeriSeti:
    def __init__(self, kok, dataset_id):
        self.kok = kok
        self.dataset_id = dataset_id
        self.ornekler = []
        os.makedirs(os.path.join(kok, "images"), exist_ok=True)
        os.makedirs(os.path.join(kok, "labels"), exist_ok=True)

    def ekle(
            self,
            grup,
            renk,
            etiket,
            uzanti="png",
            provenance=None,
            document_sha256=None,
            page=1):
        sira = len(self.ornekler)
        image_rel = f"images/ornek-{sira}.{uzanti}"
        label_rel = f"labels/ornek-{sira}.txt"
        image_yolu = os.path.join(self.kok, *image_rel.split("/"))
        label_yolu = os.path.join(self.kok, *label_rel.split("/"))
        goruntu = Image.new("RGB", (8, 6), renk)
        bicim = {"png": "PNG", "bmp": "BMP", "jpg": "JPEG"}[uzanti]
        goruntu.save(image_yolu, bicim)
        with open(label_yolu, "w", encoding="utf-8") as dosya:
            dosya.write(etiket)
        belge_sha = document_sha256 or hashlib.sha256(
            f"{self.dataset_id}:{grup}:{sira}".encode()).hexdigest()
        ornek = {
            "image": image_rel,
            "label": label_rel,
            "document_sha256": belge_sha,
            "page": page,
            "publisher_group": grup,
        }
        if provenance is not None:
            ornek["provenance"] = provenance
        self.ornekler.append(ornek)
        return image_yolu, label_yolu

    def yaz(self):
        manifest = {
            "schema_version": v4.SEMA_SURUMU,
            "dataset_id": self.dataset_id,
            "classes": list(v4.SINIFLAR),
            "root": ".",
            "splits": {
                "train": self.ornekler,
                "validation": [],
                "calibration": [],
                "holdout": [],
            },
        }
        yol = os.path.join(self.kok, "manifest.json")
        with open(yol, "w", encoding="utf-8") as dosya:
            json.dump(manifest, dosya)
        return yol


class SoruModelV4BirlestirTesti(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory()
        self.kok = self.gecici.name

    def tearDown(self):
        self.gecici.cleanup()

    def _veri_setleri(self):
        temel = _VeriSeti(os.path.join(self.kok, "ql_v3"), "ql-v3-test")
        palme = _VeriSeti(
            os.path.join(self.kok, "palme"), "palme-supplement-test")
        return temel, palme

    def _manifest_oku(self, yol):
        with open(yol, encoding="utf-8") as dosya:
            return json.load(dosya)

    def test_govde_cozum_cifti_class3e_donusur_ve_palme_train(self):
        temel, palme = self._veri_setleri()
        ortak_etiket = (
            "1 0.5 0.5 0.4 0.4\n"
            "3 0.500000 0.500000 0.4000 0.4000\n"
        )
        _, temel_label = temel.ekle(
            "pub-bagli", (230, 20, 20), ortak_etiket, "png")
        temel.ekle("pub-val", (20, 230, 20),
                   "0 0.2 0.2 0.1 0.1\n")
        temel.ekle("pub-cal", (20, 20, 230),
                   "1 0.3 0.3 0.2 0.2\n")
        temel.ekle("pub-hold", (230, 230, 20),
                   "2 0.5 0.5 0.4 0.4\n")
        palme_image, palme_label = palme.ekle(
            "pub-palme",
            (230, 20, 20),
            "3 0.500000 0.500000 0.400000 0.400000\n",
            "bmp",
            provenance={
                "book_id": "book-opaque-1",
                "page_index": 0,
                "image_sha256": "0" * 64,
                "label_sha256": "1" * 64,
                "source_path": "/Users/secret/palme.pdf",
                "url": "https://example.invalid/private",
            },
        )
        palme.ornekler[-1].update({
            "annotation_origin": "verified_crop_alignment",
            "alignment_score": 0.91,
            "image_sha256": v4._dosya_sha256(palme_image),
            "label_sha256": v4._dosya_sha256(palme_label),
        })
        sonuc = v4.birlestir(
            temel.yaz(), palme.yaz(), os.path.join(self.kok, "ql_v4"))
        manifest = self._manifest_oku(sonuc["manifest_yolu"])

        self.assertEqual(tuple(manifest["classes"]), v4.SINIFLAR)
        self.assertTrue(all(manifest["splits"][s] for s in v4.SPLITLER))
        self.assertEqual(sum(
            len(manifest["splits"][s]) for s in v4.SPLITLER), 4)
        palme_ornekleri = [
            ornek
            for ornek in manifest["splits"]["train"]
            if ornek["publisher_group"] == "pub-palme"
        ]
        self.assertEqual(len(palme_ornekleri), 1)
        palme_ornegi = palme_ornekleri[0]
        label_yolu = os.path.join(
            sonuc["cikti"], *palme_ornegi["label"].split("/"))
        with open(label_yolu, encoding="utf-8") as dosya:
            self.assertEqual(dosya.read(), "3 0.5 0.5 0.4 0.4\n")
        self.assertEqual(
            len(palme_ornegi["provenance"]["sources"]), 2)
        palme_kaynagi = next(
            kaynak
            for kaynak in palme_ornegi["provenance"]["sources"]
            if kaynak["role"] == "palme_supplement"
        )
        metadata = palme_kaynagi["metadata"]
        self.assertEqual(metadata["book_id"], "book-opaque-1")
        self.assertEqual(
            metadata["annotation_origin"], "verified_crop_alignment")
        self.assertEqual(metadata["alignment_score"], 0.91)
        self.assertEqual(
            metadata["image_sha256"], v4._dosya_sha256(palme_image))
        self.assertEqual(
            metadata["label_sha256"], v4._dosya_sha256(palme_label))
        self.assertNotIn("source_path", metadata)
        self.assertNotIn("url", metadata)

        cikti_image = os.path.join(
            sonuc["cikti"], *palme_ornegi["image"].split("/"))
        self.assertEqual(
            os.stat(palme_image).st_ino, os.stat(cikti_image).st_ino)
        self.assertEqual(
            palme_ornegi["image_sha256"], v4._dosya_sha256(cikti_image))
        with open(palme_label, encoding="utf-8") as dosya:
            self.assertEqual(
                dosya.read(),
                "3 0.500000 0.500000 0.400000 0.400000\n",
            )
        with open(temel_label, encoding="utf-8") as dosya:
            self.assertEqual(dosya.read(), ortak_etiket)
        bileşen = next(
            oge for oge in
            manifest["merge"]["publisher_group_components"]
            if "pub-palme" in oge["groups"]
        )
        self.assertEqual(
            set(bileşen["groups"]), {"pub-palme", "pub-bagli"})
        self.assertEqual(bileşen["split"], "train")
        self.assertTrue(bileşen["forced_train"])
        self.assertEqual(
            manifest["merge"]["stats"]
            ["body_solution_samples_reclassified"], 1)
        self.assertEqual(
            manifest["merge"]["stats"]
            ["body_rows_reclassified_to_solution"], 1)
        self.assertEqual(
            manifest["merge"]["stats"]
            ["equivalent_duplicate_samples_removed"], 1)
        # Hardlink kaynağı daha sonra değişirse standart eğitim doğrulayıcısı
        # manifestteki encoded image SHA sayesinde stale çıktıyı reddeder.
        Image.new("RGB", (8, 6), (1, 2, 3)).save(palme_image, "BMP")
        import soru_model_egitim
        rapor = soru_model_egitim.manifest_dogrula(
            sonuc["manifest_yolu"])
        self.assertFalse(rapor["ok"])
        self.assertTrue(any(
            "image_sha256" in hata for hata in rapor["hatalar"]))

    def test_celisik_rgb_tekrarinin_tum_grubu_atilir(self):
        temel, palme = self._veri_setleri()
        temel.ekle("pub-celisik", (200, 10, 180),
                   "1 0.5 0.5 0.4 0.4\n")
        for sira, renk in enumerate((
                (10, 40, 70), (30, 80, 110),
                (50, 120, 150), (70, 160, 190))):
            temel.ekle(
                f"pub-{sira}", renk, "0 0.2 0.2 0.1 0.1\n")
        palme.ekle("pub-palme", (200, 10, 180),
                   "2 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (15, 25, 35),
                   "1 0.5 0.5 0.4 0.4\n")
        carpisan_image = os.path.join(
            temel.kok, *temel.ornekler[0]["image"].split("/"))
        carpisan_sha = v4._rgb_piksel_sha256(carpisan_image)

        sonuc = v4.birlestir(
            temel.yaz(), palme.yaz(), os.path.join(self.kok, "ql_v4"))
        manifest = self._manifest_oku(sonuc["manifest_yolu"])
        tum = [
            ornek for split in v4.SPLITLER
            for ornek in manifest["splits"][split]
        ]
        self.assertNotIn(carpisan_sha, {
            ornek["pixel_sha256"] for ornek in tum
        })
        self.assertEqual(len(tum), 5)
        self.assertEqual(
            manifest["merge"]["stats"]
            ["ambiguous_duplicate_groups_removed"], 1)
        self.assertEqual(
            manifest["merge"]["stats"]["ambiguous_samples_removed"], 2)
        self.assertTrue(any(
            ornek["publisher_group"] == "pub-palme"
            for ornek in manifest["splits"]["train"]
        ))

    def test_palme_ekinin_tumu_celisikse_cikti_uretmez(self):
        temel, palme = self._veri_setleri()
        carpisan_renk = (210, 25, 170)
        temel.ekle("pub-celisik", carpisan_renk,
                   "1 0.5 0.5 0.4 0.4\n")
        for sira, renk in enumerate((
                (10, 40, 70), (30, 80, 110),
                (50, 120, 150), (70, 160, 190))):
            temel.ekle(
                f"pub-{sira}", renk, "0 0.2 0.2 0.1 0.1\n")
        palme.ekle("pub-palme", carpisan_renk,
                   "2 0.5 0.5 0.4 0.4\n")
        cikti = os.path.join(self.kok, "ql_v4")

        with self.assertRaisesRegex(
                v4.BirlestirmeHatasi, "bütün sayfaları"):
            v4.birlestir(temel.yaz(), palme.yaz(), cikti)
        self.assertFalse(os.path.exists(cikti))

    def test_verified_mantiksal_sayfayi_degistirir_diagnostic_bastirir(self):
        temel, palme = self._veri_setleri()
        ortak_belge = hashlib.sha256(b"ortak-kitap").hexdigest()
        diagnostic_belge = hashlib.sha256(b"diagnostic-kitap").hexdigest()
        temel.ekle(
            "pub-eski",
            (210, 10, 10),
            "2 0.5 0.5 0.4 0.4\n",
            document_sha256=ortak_belge,
            page=7,
        )
        temel.ekle(
            "pub-diagnostic-eski",
            (10, 210, 10),
            "1 0.5 0.5 0.4 0.4\n",
            document_sha256=diagnostic_belge,
            page=9,
        )
        temel.ekle("pub-val", (10, 10, 210),
                   "0 0.2 0.2 0.1 0.1\n")
        temel.ekle("pub-cal", (210, 210, 10),
                   "1 0.3 0.3 0.2 0.2\n")
        temel.ekle("pub-hold", (10, 210, 210),
                   "2 0.4 0.4 0.2 0.2\n")
        palme.ekle(
            "pub-palme",
            (120, 30, 220),
            "1 0.5 0.5 0.4 0.4\n",
            provenance={
                "annotation_origin": "verified_crop_alignment",
                "source_profile": "palme11-standard-2018",
                "crop_dpi": 180,
                "render_dpi": 130,
                "alignment_score": 0.92,
                "alignment_remote_gap": 0.17,
            },
            document_sha256=ortak_belge,
            page=7,
        )
        palme_manifest = palme.yaz()
        diagnostic_manifest = os.path.join(
            palme.kok, "diagnostic_manifest.json")
        with open(diagnostic_manifest, "w", encoding="utf-8") as dosya:
            json.dump({
                "schema_version": v4.TANISAL_SEMA_SURUMU,
                "dataset_id": palme.dataset_id + "-diagnostic",
                "classes": list(v4.SINIFLAR),
                "root": ".",
                "partition": "diagnostic_holdout",
                "samples": [{
                    "document_sha256": diagnostic_belge,
                    "page": 9,
                    "publisher_group": "pub-palme",
                }],
            }, dosya)

        sonuc = v4.birlestir(
            temel.yaz(),
            palme_manifest,
            os.path.join(self.kok, "ql_v4"),
            palme_diagnostic_manifest=diagnostic_manifest,
        )
        manifest = self._manifest_oku(sonuc["manifest_yolu"])
        tum = [
            ornek for split in v4.SPLITLER
            for ornek in manifest["splits"][split]
        ]
        ortak = [
            ornek for ornek in tum
            if (ornek["document_sha256"], ornek["page"])
            == (ortak_belge, 7)
        ]
        self.assertEqual(len(ortak), 1)
        self.assertEqual(
            ortak[0]["provenance"]["representative_role"],
            "palme_supplement",
        )
        self.assertEqual(
            [kaynak["role"]
             for kaynak in ortak[0]["provenance"]["sources"]],
            ["palme_supplement"],
        )
        metadata = ortak[0]["provenance"]["sources"][0]["metadata"]
        self.assertEqual(metadata["source_profile"],
                         "palme11-standard-2018")
        self.assertEqual(metadata["crop_dpi"], 180)
        self.assertEqual(metadata["render_dpi"], 130)
        self.assertEqual(metadata["alignment_remote_gap"], 0.17)
        self.assertNotIn(
            (diagnostic_belge, 9),
            {(o["document_sha256"], o["page"]) for o in tum},
        )
        istatistik = manifest["merge"]["stats"]
        self.assertEqual(istatistik["verified_pages_replacing_ql_v3"], 1)
        self.assertEqual(
            istatistik["ql_v3_samples_replaced_by_verified"], 1)
        self.assertEqual(istatistik["diagnostic_pages_declared"], 1)
        self.assertEqual(istatistik["diagnostic_pages_matched_in_inputs"], 1)
        self.assertEqual(
            istatistik["diagnostic_ql_v3_samples_suppressed"], 1)
        self.assertIn(
            "palme_diagnostics",
            manifest["merge"]["source_manifests"],
        )

    def test_iki_verified_ayni_mantiksal_sayfada_celisirse_fail_closed(self):
        temel, palme = self._veri_setleri()
        palme_iki = _VeriSeti(
            os.path.join(self.kok, "palme-iki"),
            "palme-supplement-test-iki",
        )
        for sira in range(4):
            temel.ekle(
                f"pub-{sira}",
                (10 + sira * 20, 30, 40),
                "1 0.5 0.5 0.4 0.4\n",
            )
        belge = hashlib.sha256(b"verified-conflict").hexdigest()
        palme.ekle(
            "pub-palme", (200, 10, 10),
            "1 0.5 0.5 0.4 0.4\n",
            document_sha256=belge, page=5,
        )
        palme_iki.ekle(
            "pub-palme-iki", (10, 200, 10),
            "2 0.5 0.5 0.4 0.4\n",
            document_sha256=belge, page=5,
        )
        cikti = os.path.join(self.kok, "ql_v4")
        with self.assertRaisesRegex(
                v4.BirlestirmeHatasi, "doğrulanmış supplement"):
            v4.birlestir(
                temel.yaz(),
                [palme.yaz(), palme_iki.yaz()],
                cikti,
            )
        self.assertFalse(os.path.exists(cikti))

    def test_iki_supplement_ve_diagnostic_birlikte_korunur(self):
        temel = _VeriSeti(
            os.path.join(self.kok, "ql_v3"), "ql-v3-test")
        ayt = _VeriSeti(
            os.path.join(self.kok, "palme-ayt"), "palme-ayt-verified-test")
        palme11 = _VeriSeti(
            os.path.join(self.kok, "palme11"), "palme11-verified-test")
        diag_ayt_belge = hashlib.sha256(b"ayt-diagnostic").hexdigest()
        diag_11_belge = hashlib.sha256(b"palme11-diagnostic").hexdigest()
        temel.ekle(
            "pub-eski-ayt", (10, 20, 30),
            "1 0.5 0.5 0.4 0.4\n",
            document_sha256=diag_ayt_belge, page=9,
        )
        temel.ekle(
            "pub-eski-11", (40, 50, 60),
            "1 0.5 0.5 0.4 0.4\n",
            document_sha256=diag_11_belge, page=10,
        )
        temel.ekle("pub-val", (70, 80, 90),
                   "0 0.2 0.2 0.1 0.1\n")
        temel.ekle("pub-cal", (100, 110, 120),
                   "1 0.3 0.3 0.2 0.2\n")
        temel.ekle("pub-hold", (130, 140, 150),
                   "2 0.4 0.4 0.2 0.2\n")
        ayt.ekle(
            "pub-palme-ayt", (160, 170, 180),
            "1 0.5 0.5 0.4 0.4\n",
        )
        palme11.ekle(
            "pub-palme11", (190, 200, 210),
            "1 0.5 0.5 0.4 0.4\n",
        )

        def diagnostic_yaz(veri_seti, grup, belge, page):
            yol = os.path.join(
                veri_seti.kok, "diagnostic_manifest.json")
            with open(yol, "w", encoding="utf-8") as dosya:
                json.dump({
                    "schema_version": v4.TANISAL_SEMA_SURUMU,
                    "dataset_id": veri_seti.dataset_id + "-diagnostic",
                    "classes": list(v4.SINIFLAR),
                    "root": ".",
                    "partition": "diagnostic_holdout",
                    "samples": [{
                        "document_sha256": belge,
                        "page": page,
                        "publisher_group": grup,
                    }],
                }, dosya)
            return yol

        ayt_diagnostic = diagnostic_yaz(
            ayt, "pub-palme-ayt", diag_ayt_belge, 9)
        palme11_diagnostic = diagnostic_yaz(
            palme11, "pub-palme11", diag_11_belge, 10)
        sonuc = v4.birlestir(
            temel.yaz(),
            [ayt.yaz(), palme11.yaz()],
            os.path.join(self.kok, "ql_v4"),
            palme_diagnostic_manifest=[
                ayt_diagnostic,
                palme11_diagnostic,
            ],
        )
        manifest = self._manifest_oku(sonuc["manifest_yolu"])
        train_gruplari = {
            ornek["publisher_group"]
            for ornek in manifest["splits"]["train"]
        }
        self.assertIn("pub-palme-ayt", train_gruplari)
        self.assertIn("pub-palme11", train_gruplari)
        tum_anahtarlar = {
            (ornek["document_sha256"], ornek["page"])
            for split in v4.SPLITLER
            for ornek in manifest["splits"][split]
        }
        self.assertNotIn((diag_ayt_belge, 9), tum_anahtarlar)
        self.assertNotIn((diag_11_belge, 10), tum_anahtarlar)
        self.assertEqual(
            manifest["merge"]["stats"]
            ["diagnostic_ql_v3_samples_suppressed"],
            2,
        )
        self.assertEqual(
            len(manifest["merge"]["verified_supplements"]), 2)
        self.assertEqual(
            len(manifest["merge"]["source_manifests"]
                ["palme_supplements"]),
            2,
        )
        self.assertEqual(
            len(manifest["merge"]["source_manifests"]
                ["palme_diagnostics"]),
            2,
        )
        bileşenler = manifest["merge"]["publisher_group_components"]
        for grup in ("pub-palme-ayt", "pub-palme11"):
            bileşen = next(
                b for b in bileşenler if grup in b["groups"])
            self.assertEqual(bileşen["split"], "train")
            self.assertIn(
                "verified_palme_supplement_train",
                bileşen["forced_split_reasons"],
            )

    def test_nadir_sinif_splitleri_zorlanir_ve_destek_raporlanir(self):
        temel, palme = self._veri_setleri()
        girdiler = (
            ("pub-b89ade", (210, 10, 10),
             "2 0.3 0.3 0.2 0.2\n3 0.7 0.7 0.2 0.2\n"),
            ("pub-17ba07", (10, 210, 10),
             "2 0.3 0.3 0.2 0.2\n"),
            ("pub-26be78", (10, 10, 210),
             "3 0.3 0.3 0.2 0.2\n"),
            ("pub-8bf958", (210, 210, 10),
             "2 0.3 0.3 0.2 0.2\n"),
            ("pub-974342", (210, 10, 210),
             "3 0.3 0.3 0.2 0.2\n"),
            ("pub-calibration", (10, 210, 210),
             "0 0.3 0.3 0.2 0.2\n"),
        )
        for grup, renk, etiket in girdiler:
            temel.ekle(grup, renk, etiket)
        palme.ekle(
            "pub-palme", (130, 90, 40),
            "1 0.5 0.5 0.4 0.4\n",
        )

        sonuc = v4.birlestir(
            temel.yaz(), palme.yaz(), os.path.join(self.kok, "ql_v4"))
        manifest = self._manifest_oku(sonuc["manifest_yolu"])
        grup_split = {
            ornek["publisher_group"]: split
            for split in v4.SPLITLER
            for ornek in manifest["splits"][split]
        }
        self.assertEqual(grup_split["pub-b89ade"], "train")
        self.assertEqual(grup_split["pub-17ba07"], "validation")
        self.assertEqual(grup_split["pub-26be78"], "validation")
        self.assertEqual(grup_split["pub-8bf958"], "holdout")
        self.assertEqual(grup_split["pub-974342"], "holdout")
        self.assertEqual(grup_split["pub-calibration"], "calibration")
        destek = manifest["merge"]["class_support"]
        for sinif in ("shared_stimulus", "solution_or_answer"):
            self.assertGreater(destek[sinif]["sample_counts"]["train"], 0)
            self.assertGreater(
                destek[sinif]["sample_counts"]["validation"], 0)
            self.assertGreater(destek[sinif]["sample_counts"]["holdout"], 0)
            self.assertFalse(destek[sinif]["calibration_supported"])
        self.assertTrue(
            manifest["merge"]["publication_gate"]
            ["rare_class_coverage_ok"]
        )
        bileşenler = {
            tuple(b["groups"]): b
            for b in manifest["merge"]["publisher_group_components"]
        }
        self.assertIn(
            "solution_or_answer_holdout_support",
            bileşenler[("pub-974342",)]["forced_split_reasons"],
        )
        self.assertIn("ratio_deviation", manifest["merge"])

    def test_bagli_zorunlu_split_cakismasi_fail_closed(self):
        temel, palme = self._veri_setleri()
        ortak_belge = hashlib.sha256(b"forced-component").hexdigest()
        temel.ekle(
            "pub-17ba07", (10, 20, 30),
            "2 0.5 0.5 0.4 0.4\n",
            document_sha256=ortak_belge, page=1,
        )
        temel.ekle(
            "pub-8bf958", (40, 50, 60),
            "2 0.5 0.5 0.4 0.4\n",
            document_sha256=ortak_belge, page=2,
        )
        for sira in range(3):
            temel.ekle(
                f"pub-extra-{sira}",
                (70 + sira * 20, 80, 90),
                "1 0.5 0.5 0.4 0.4\n",
            )
        palme.ekle(
            "pub-palme", (200, 210, 220),
            "1 0.5 0.5 0.4 0.4\n",
        )
        cikti = os.path.join(self.kok, "ql_v4")
        with self.assertRaisesRegex(
                v4.BirlestirmeHatasi, "çelişkili zorunlu split"):
            v4.birlestir(temel.yaz(), palme.yaz(), cikti)
        self.assertFalse(os.path.exists(cikti))

    def test_guvensiz_goreli_yol_reddedilir(self):
        temel, palme = self._veri_setleri()
        for sira in range(4):
            temel.ekle(
                f"pub-{sira}", (sira * 20, 20, 20),
                "1 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (240, 20, 20),
                   "1 0.5 0.5 0.4 0.4\n")
        temel_manifest = temel.yaz()
        manifest = self._manifest_oku(temel_manifest)
        manifest["splits"]["train"][0]["image"] = "../disari.png"
        with open(temel_manifest, "w", encoding="utf-8") as dosya:
            json.dump(manifest, dosya)
        cikti = os.path.join(self.kok, "ql_v4")
        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "üst dizin"):
            v4.birlestir(temel_manifest, palme.yaz(), cikti)
        self.assertFalse(os.path.exists(cikti))

    def test_cikti_kaynak_veri_kokunun_icine_yazilamaz(self):
        temel, palme = self._veri_setleri()
        for sira in range(4):
            temel.ekle(
                f"pub-{sira}", (sira * 20, 30, 40),
                "1 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (240, 30, 40),
                   "1 0.5 0.5 0.4 0.4\n")
        cikti = os.path.join(temel.kok, "ql_v4")

        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "tamamen ayrı"):
            v4.birlestir(temel.yaz(), palme.yaz(), cikti)
        self.assertFalse(os.path.exists(cikti))

    def test_dort_sinif_sozlesmesi_uyusmazsa_reddedilir(self):
        temel, palme = self._veri_setleri()
        temel.ekle("pub-a", (10, 20, 30),
                   "1 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (40, 50, 60),
                   "1 0.5 0.5 0.4 0.4\n")
        temel_manifest = temel.yaz()
        manifest = self._manifest_oku(temel_manifest)
        manifest["classes"] = list(reversed(manifest["classes"]))
        with open(temel_manifest, "w", encoding="utf-8") as dosya:
            json.dump(manifest, dosya)

        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "4 sınıflı"):
            v4.birlestir(
                temel_manifest,
                palme.yaz(),
                os.path.join(self.kok, "ql_v4"),
            )

    def test_hardlink_exdev_olursa_kopyaya_duser(self):
        kaynak = os.path.join(self.kok, "kaynak.bin")
        hedef = os.path.join(self.kok, "yeni", "hedef.bin")
        with open(kaynak, "wb") as dosya:
            dosya.write(b"ornek")
        hata = OSError(errno.EXDEV, "cross-device link")
        with mock.patch.object(v4.os, "link", side_effect=hata):
            kip = v4._bagla_veya_kopyala(kaynak, hedef)
        self.assertEqual(kip, "copy")
        with open(hedef, "rb") as dosya:
            self.assertEqual(dosya.read(), b"ornek")

    def test_final_audit_capraz_split_rgb_tekrarini_reddeder(self):
        audit = os.path.join(self.kok, "audit")
        os.makedirs(os.path.join(audit, "images"))
        image_rel = "images/ortak.png"
        image_yolu = os.path.join(audit, *image_rel.split("/"))
        Image.new("RGB", (8, 6), (12, 34, 56)).save(image_yolu, "PNG")
        piksel_sha = v4._rgb_piksel_sha256(image_yolu)
        ortak = {
            "image": image_rel,
            "publisher_group": "pub-a",
            "pixel_sha256": piksel_sha,
        }
        manifest = {
            "splits": {
                "train": [ortak],
                "validation": [dict(ortak, publisher_group="pub-b")],
                "calibration": [],
                "holdout": [],
            },
        }
        manifest_yolu = os.path.join(audit, "manifest.json")
        with open(manifest_yolu, "w", encoding="utf-8") as dosya:
            json.dump(manifest, dosya)

        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "çapraz-split"):
            v4._cikis_tekrarlarini_dogrula(manifest_yolu)

    def test_sayfa_agirlikli_split_hedefe_yaklasir_ve_deterministiktir(self):
        # Gerçek ql_v3'e benzeyen, eşit olmayan yayınevi sayfa ağırlıkları.
        agirliklar = [
            567, 451, 249, 238, 231, 222, 192, 136, 136, 134, 108,
            66, 61, 56, 54, 52, 51, 40, 36, 31, 4, 1,
        ]
        kok_ornekleri = {
            "pub-palme": [None] * 224,
            **{
                f"pub-{sira:02d}": [None] * agirlik
                for sira, agirlik in enumerate(agirliklar)
            },
        }
        bileşenler = {kok: {kok} for kok in kok_ornekleri}
        atama, sayilar = v4._splitleri_ata(
            kok_ornekleri, bileşenler, {"pub-palme": "train"})
        ters_atama, ters_sayilar = v4._splitleri_ata(
            dict(reversed(list(kok_ornekleri.items()))),
            bileşenler,
            {"pub-palme": "train"},
        )

        self.assertEqual(atama, ters_atama)
        self.assertEqual(sayilar, ters_sayilar)
        self.assertEqual(atama["pub-palme"], "train")
        toplam = sum(sayilar.values())
        for split, hedef in v4.SPLIT_HEDEFLERI.items():
            self.assertLess(abs(sayilar[split] / toplam - hedef), 0.01)

    def test_dort_bilesen_yoksa_bos_split_uretmez(self):
        temel, palme = self._veri_setleri()
        temel.ekle("pub-a", (10, 20, 30),
                   "1 0.5 0.5 0.4 0.4\n")
        temel.ekle("pub-b", (40, 50, 60),
                   "1 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (70, 80, 90),
                   "1 0.5 0.5 0.4 0.4\n")
        cikti = os.path.join(self.kok, "ql_v4")
        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "en az 4"):
            v4.birlestir(temel.yaz(), palme.yaz(), cikti)
        self.assertFalse(os.path.exists(cikti))

    def test_var_olan_ciktiya_dokunmaz(self):
        temel, palme = self._veri_setleri()
        for sira in range(4):
            temel.ekle(
                f"pub-{sira}", (sira * 30, 10, 10),
                "1 0.5 0.5 0.4 0.4\n")
        palme.ekle("pub-palme", (250, 10, 10),
                   "1 0.5 0.5 0.4 0.4\n")
        cikti = os.path.join(self.kok, "ql_v4")
        os.makedirs(cikti)
        isaret = os.path.join(cikti, "kullanici.txt")
        with open(isaret, "w", encoding="utf-8") as dosya:
            dosya.write("koru")
        with self.assertRaisesRegex(v4.BirlestirmeHatasi, "zaten var"):
            v4.birlestir(temel.yaz(), palme.yaz(), cikti)
        with open(isaret, encoding="utf-8") as dosya:
            self.assertEqual(dosya.read(), "koru")


if __name__ == "__main__":
    unittest.main()
