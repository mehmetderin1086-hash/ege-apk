#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import ast
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import types
import unittest
import zipfile
from unittest import mock

from PIL import Image

import soru_model_colab_paketle as paket


class ColabPaketTesti(unittest.TestCase):
    @staticmethod
    @contextlib.contextmanager
    def _sahte_resmi_base(yol):
        with open(yol, "rb") as f:
            veri = f.read()
        with mock.patch.object(paket.duzen_model, "MODEL_YOLU", yol), \
                mock.patch.object(
                    paket, "RESMI_BASE_MODEL_SHA256",
                    hashlib.sha256(veri).hexdigest()), \
                mock.patch.object(
                    paket, "RESMI_BASE_MODEL_BOYUT", len(veri)):
            yield

    @staticmethod
    def _notebook_hucresi(hucre_id):
        yol = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "soru_model_colab.ipynb",
        )
        with open(yol, encoding="utf-8") as f:
            notebook = json.load(f)
        return next(
            "".join(hucre["source"])
            for hucre in notebook["cells"]
            if hucre.get("id") == hucre_id
        )

    @staticmethod
    def _kaynak_fingerprint(kok, manifest, samples):
        parcalar = []
        for split, ornekler in samples.items():
            for ornek in ornekler:
                with open(os.path.join(kok, *ornek["image"].split("/")), "rb") as f:
                    g_sha = hashlib.sha256(f.read()).hexdigest()
                with open(os.path.join(kok, *ornek["label"].split("/")), "rb") as f:
                    e_sha = hashlib.sha256(f.read()).hexdigest()
                parcalar.append(
                    f"{split}\0{ornek['image']}\0{g_sha}"
                    f"\0{ornek['label']}\0{e_sha}")
        return paket._kaynak_dataset_parmagi(manifest, parcalar)

    def test_arsiv_koku_traversal_reddedilir(self):
        for deger in ("../ql", "/ql", "ql/v4", ".", ""):
            with self.subTest(deger=deger), self.assertRaises(ValueError):
                paket._arsiv_koku_dogrula(deger)
        self.assertEqual("ql_v4-palme",
                         paket._arsiv_koku_dogrula("ql_v4-palme"))

    def test_turev_baytlar_ve_fingerprint_manifeste_kilitlenir(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "images", "train"))
            os.makedirs(os.path.join(d, "labels", "train"))
            img_rel = "images/train/a.png"
            lbl_rel = "labels/train/a.txt"
            Image.new("RGB", (128, 160), "white").save(
                os.path.join(d, img_rel))
            with open(os.path.join(d, lbl_rel), "w") as f:
                f.write("1 0.5 0.5 0.5 0.5\n")
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)

            ornek = {
                "image": img_rel,
                "label": lbl_rel,
                "document_sha256": "a" * 64,
                "page": 1,
                "publisher_group": "pub-a",
            }
            egitim_manifesti = {
                "schema_version":
                    "soru-kesici.question-layout-training/v1",
                "dataset_id": "test",
                "classes": [
                    "question_anchor", "question_body",
                    "shared_stimulus", "solution_or_answer",
                ],
                "root": ".",
                "splits": {"train": [ornek]},
            }
            samples = {"train": [ornek]}
            rapor = {
                "ok": True,
                "manifest": egitim_manifesti,
                "samples": samples,
                "dataset_fingerprint": self._kaynak_fingerprint(
                    d, egitim_manifesti, samples),
                "istatistik": {
                    "samples": {"train": 1},
                    "boxes": {"question_body": 1},
                    "documents": 1,
                    "publisher_groups": 1,
                },
            }
            cikti = os.path.join(d, "paket.zip")
            base = os.path.join(d, "base.pt")
            with open(base, "wb") as f:
                f.write(b"dogrulanmis-baslangic-agirligi")
            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    return_value=rapor), self._sahte_resmi_base(base):
                kod = paket.paketle(
                    d, cikti, arsiv_koku="ql_v4", jpeg_kalite=92)
            self.assertEqual(0, kod)

            with zipfile.ZipFile(cikti) as z:
                man = json.loads(z.read("ql_v4/manifest.json"))
                jpg = z.read("ql_v4/images/train/a.jpg")
                etiket = z.read("ql_v4/labels/train/a.txt")
                base_bayt = z.read("ql_v4/base/base.pt")
            kayit = man["splits"]["train"][0]
            self.assertEqual(hashlib.sha256(jpg).hexdigest(),
                             kayit["image_sha256"])
            self.assertEqual(hashlib.sha256(etiket).hexdigest(),
                             kayit["label_sha256"])
            with open(os.path.join(d, img_rel), "rb") as f:
                self.assertEqual(
                    hashlib.sha256(f.read()).hexdigest(),
                    kayit["source_encoded_image_sha256"],
                )
            self.assertEqual(
                kayit["label_sha256"],
                kayit["source_encoded_label_sha256"],
            )
            self.assertEqual(
                rapor["dataset_fingerprint"],
                man["source_dataset_fingerprint"])
            self.assertEqual(64, len(man["training_package_sha256"]))
            self.assertEqual(
                paket.PAKET_PARMAK_SURUMU,
                man["training_package_fingerprint_version"],
            )
            self.assertEqual(b"dogrulanmis-baslangic-agirligi", base_bayt)
            self.assertEqual(
                hashlib.sha256(base_bayt).hexdigest(),
                man["base_model"]["sha256"],
            )
            self.assertEqual("base/base.pt", man["base_model"]["path"])
            self.assertEqual(len(base_bayt), man["base_model"]["size"])
            self.assertEqual(
                "pinned-official-huggingface-revision",
                man["base_model"]["trust_root"]["kind"],
            )
            parmak = paket._paket_parmagi_baslat(man)
            paket._parmak_satiri(parmak, [
                "train", kayit["image"], kayit["label"],
                kayit["image_sha256"], kayit["label_sha256"],
                kayit["source_encoded_image_sha256"],
                kayit["source_encoded_label_sha256"],
            ])
            paket._parmak_satiri(parmak, [
                "base_model", man["base_model"]["path"],
                man["base_model"]["sha256"], man["base_model"]["size"],
            ])
            self.assertEqual(
                man["training_package_sha256"], parmak.hexdigest())

            with open(cikti + ".manifest.json") as f:
                yan = json.load(f)
            self.assertEqual(os.path.getsize(cikti), yan["archive_size"])
            with open(cikti, "rb") as f:
                zip_sha = hashlib.sha256(f.read()).hexdigest()
            self.assertEqual(zip_sha, yan["archive_sha256"])

    def test_baslangic_agirligi_yoksa_paket_uretilmez(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)
            rapor = {
                "ok": True,
                "manifest": {
                    "schema_version":
                        "soru-kesici.question-layout-training/v1",
                    "dataset_id": "test",
                    "classes": [
                        "question_anchor", "question_body",
                        "shared_stimulus", "solution_or_answer",
                    ],
                    "root": ".",
                    "splits": {},
                },
                "samples": {},
                "dataset_fingerprint": "b" * 64,
                "istatistik": {
                    "samples": {},
                    "boxes": {},
                    "documents": 0,
                    "publisher_groups": 0,
                },
            }
            cikti = os.path.join(d, "paket.zip")
            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    return_value=rapor), mock.patch.object(
                        paket.duzen_model, "MODEL_YOLU",
                        os.path.join(d, "yok.pt")):
                with self.assertRaisesRegex(
                        FileNotFoundError, "başlangıç ağırlığı"):
                    paket.paketle(d, cikti, arsiv_koku="ql_v4")
            self.assertFalse(os.path.exists(cikti))
            self.assertFalse(os.path.exists(cikti + ".tmp"))

    def test_doclayout_etiket_yolu_birebir_eslesmelidir(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "images", "train"))
            os.makedirs(os.path.join(d, "labels", "train"))
            Image.new("RGB", (64, 64), "white").save(
                os.path.join(d, "images", "train", "a.png"))
            with open(os.path.join(d, "labels", "train", "yanlis.txt"), "w") as f:
                f.write("1 0.5 0.5 0.5 0.5\n")
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)
            ornek = {
                "image": "images/train/a.png",
                "label": "labels/train/yanlis.txt",
                "document_sha256": "a" * 64,
                "page": 1,
                "publisher_group": "pub-a",
            }
            egitim_manifesti = {
                "schema_version":
                    "soru-kesici.question-layout-training/v1",
                "dataset_id": "test",
                "classes": [
                    "question_anchor", "question_body",
                    "shared_stimulus", "solution_or_answer",
                ],
                "root": ".",
                "splits": {"train": [ornek]},
            }
            samples = {"train": [ornek]}
            rapor = {
                "ok": True,
                "manifest": egitim_manifesti,
                "samples": samples,
                "dataset_fingerprint": self._kaynak_fingerprint(
                    d, egitim_manifesti, samples),
                "istatistik": {
                    "samples": {"train": 1},
                    "boxes": {"question_body": 1},
                    "documents": 1,
                    "publisher_groups": 1,
                },
            }
            base = os.path.join(d, "base.pt")
            with open(base, "wb") as f:
                f.write(b"resmi-test-base")
            cikti = os.path.join(d, "paket.zip")
            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    return_value=rapor), self._sahte_resmi_base(base):
                with self.assertRaisesRegex(ValueError, "image→label"):
                    paket.paketle(d, cikti, arsiv_koku="ql_v4")
            self.assertFalse(os.path.exists(cikti))
            self.assertFalse(os.path.exists(cikti + ".manifest.json"))

    def test_resmi_guven_kokune_uymayan_base_reddedilir(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)
            rapor = {
                "ok": True,
                "manifest": {
                    "schema_version":
                        "soru-kesici.question-layout-training/v1",
                    "dataset_id": "test",
                    "classes": [
                        "question_anchor", "question_body",
                        "shared_stimulus", "solution_or_answer",
                    ],
                    "root": ".",
                    "splits": {},
                },
                "samples": {},
                "dataset_fingerprint": "b" * 64,
                "istatistik": {
                    "samples": {}, "boxes": {}, "documents": 0,
                    "publisher_groups": 0,
                },
            }
            base = os.path.join(d, "base.pt")
            with open(base, "wb") as f:
                f.write(b"sahte")
            cikti = os.path.join(d, "paket.zip")
            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    return_value=rapor), mock.patch.object(
                        paket.duzen_model, "MODEL_YOLU", base):
                with self.assertRaisesRegex(ValueError, "resmi boyut"):
                    paket.paketle(d, cikti, arsiv_koku="ql_v4")
            self.assertFalse(os.path.exists(cikti))

    def test_kaynak_paketleme_sirasinda_degiserse_yayinlanmaz(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "images", "train"))
            os.makedirs(os.path.join(d, "labels", "train"))
            Image.new("RGB", (64, 64), "white").save(
                os.path.join(d, "images", "train", "a.png"))
            with open(os.path.join(d, "labels", "train", "a.txt"), "w") as f:
                f.write("1 0.5 0.5 0.5 0.5\n")
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)
            ornek = {
                "image": "images/train/a.png",
                "label": "labels/train/a.txt",
                "document_sha256": "a" * 64,
                "page": 1,
                "publisher_group": "pub-a",
            }
            egitim_manifesti = {
                "schema_version":
                    "soru-kesici.question-layout-training/v1",
                "dataset_id": "test",
                "classes": [
                    "question_anchor", "question_body",
                    "shared_stimulus", "solution_or_answer",
                ],
                "root": ".",
                "splits": {"train": [ornek]},
            }
            samples = {"train": [ornek]}
            rapor = {
                "ok": True,
                "manifest": egitim_manifesti,
                "samples": samples,
                "dataset_fingerprint": self._kaynak_fingerprint(
                    d, egitim_manifesti, samples),
                "istatistik": {
                    "samples": {"train": 1},
                    "boxes": {"question_body": 1},
                    "documents": 1,
                    "publisher_groups": 1,
                },
            }
            degismis = dict(rapor, dataset_fingerprint="c" * 64)
            base = os.path.join(d, "base.pt")
            with open(base, "wb") as f:
                f.write(b"resmi-test-base")
            cikti = os.path.join(d, "paket.zip")
            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    side_effect=[rapor, degismis]), self._sahte_resmi_base(base):
                with self.assertRaisesRegex(RuntimeError, "veri seti"):
                    paket.paketle(d, cikti, arsiv_koku="ql_v4")
            self.assertFalse(os.path.exists(cikti))
            self.assertFalse(os.path.exists(cikti + ".manifest.json"))

    def test_gorsel_a_b_a_degisiminde_b_jpeg_yayinlanmaz(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "images", "train"))
            os.makedirs(os.path.join(d, "labels", "train"))
            gorsel_yolu = os.path.join(d, "images", "train", "a.png")
            Image.new("RGB", (64, 64), "white").save(gorsel_yolu)
            siyah = io.BytesIO()
            Image.new("RGB", (64, 64), "black").save(siyah, "PNG")
            b_baytlari = siyah.getvalue()
            with open(os.path.join(d, "labels", "train", "a.txt"), "w") as f:
                f.write("1 0.5 0.5 0.5 0.5\n")
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump({"placeholder": True}, f)
            ornek = {
                "image": "images/train/a.png",
                "label": "labels/train/a.txt",
                "document_sha256": "a" * 64,
                "page": 1,
                "publisher_group": "pub-a",
            }
            egitim_manifesti = {
                "schema_version":
                    "soru-kesici.question-layout-training/v1",
                "dataset_id": "test",
                "classes": [
                    "question_anchor", "question_body",
                    "shared_stimulus", "solution_or_answer",
                ],
                "root": ".",
                "splits": {"train": [ornek]},
            }
            samples = {"train": [ornek]}
            rapor = {
                "ok": True,
                "manifest": egitim_manifesti,
                "samples": samples,
                "dataset_fingerprint": self._kaynak_fingerprint(
                    d, egitim_manifesti, samples),
                "istatistik": {
                    "samples": {"train": 1},
                    "boxes": {"question_body": 1},
                    "documents": 1,
                    "publisher_groups": 1,
                },
            }
            base = os.path.join(d, "base.pt")
            with open(base, "wb") as f:
                f.write(b"resmi-test-base")
            cikti = os.path.join(d, "paket.zip")
            gercek_oku = paket._sabit_dosya_oku

            def aba_oku(yol):
                if os.path.realpath(yol) == os.path.realpath(gorsel_yolu):
                    # Başlangıç/final manifest A'yı görürken paket okuyucusuna
                    # aradaki B snapshot'ını ver: eski tasarım bunu yayınlıyordu.
                    return b_baytlari
                return gercek_oku(yol)

            with mock.patch.object(
                    paket.soru_model_egitim, "manifest_dogrula",
                    return_value=rapor), self._sahte_resmi_base(base), \
                    mock.patch.object(
                        paket, "_sabit_dosya_oku", side_effect=aba_oku):
                with self.assertRaisesRegex(RuntimeError, "A-B-A"):
                    paket.paketle(d, cikti, arsiv_koku="ql_v4")
            self.assertFalse(os.path.exists(cikti))
            self.assertFalse(os.path.exists(cikti + ".manifest.json"))

    def test_cift_yayin_ikinci_replace_hatasinda_eskiyi_geri_alir(self):
        with tempfile.TemporaryDirectory() as d:
            cikti = os.path.join(d, "paket.zip")
            yan = cikti + ".manifest.json"
            yeni_zip = os.path.join(d, "yeni.zip")
            yeni_yan = os.path.join(d, "yeni.json")
            for yol, veri in (
                    (cikti, b"eski-zip"), (yan, b"eski-yan"),
                    (yeni_zip, b"yeni-zip"), (yeni_yan, b"yeni-yan")):
                with open(yol, "wb") as f:
                    f.write(veri)
            gercek_replace = os.replace

            def ikinci_adimda_cok(kaynak, hedef):
                if kaynak == yeni_yan and hedef == yan:
                    raise OSError("yan manifest replace arızası")
                return gercek_replace(kaynak, hedef)

            with mock.patch.object(
                    paket.os, "replace", side_effect=ikinci_adimda_cok):
                with self.assertRaisesRegex(OSError, "yan manifest"):
                    paket._cifti_yayinla(yeni_zip, yeni_yan, cikti)
            with open(cikti, "rb") as f:
                self.assertEqual(b"eski-zip", f.read())
            with open(yan, "rb") as f:
                self.assertEqual(b"eski-yan", f.read())

    def test_notebook_kod_hucreleri_parse_edilir_ve_guvenlik_baglari_var(self):
        yol = os.path.join(
            os.path.dirname(os.path.dirname(__file__)),
            "soru_model_colab.ipynb",
        )
        with open(yol, encoding="utf-8") as f:
            notebook = json.load(f)
        tum_kod = ""
        for hucre in notebook["cells"]:
            if hucre.get("cell_type") != "code":
                continue
            kaynak = "".join(hucre["source"])
            tum_kod += kaynak
            python_satirlari = [
                "pass" if satir.lstrip().startswith(("!", "%")) else satir
                for satir in kaynak.splitlines()
            ]
            ast.parse("\n".join(python_satirlari))
        for parca in (
                paket.RESMI_BASE_MODEL_SHA256,
                paket.PAKET_PARMAK_SURUMU,
                "ham == kanonik",
                "zipfile.ZipFile(staged)",
                "acik_dosya_sha256(staged)",
                "shutil.rmtree(ACMA_KOKU)",
                "parmak.hexdigest() == beklenen_paket_sha",
                "doclayout_etiket_yolu(o[\"image\"])",
                "os.path.commonpath",
                "huggingface-hub>=0.23,<2"):
            self.assertIn(parca, tum_kod)

    def test_notebook_kanonik_olmayan_zip_takma_adini_reddeder(self):
        kaynak = self._notebook_hucresi("hucre-03")
        with tempfile.TemporaryDirectory() as d:
            veri_koku = os.path.join(d, "datasets")
            kaynak = kaynak.replace(
                'VERI_KOKU = "/content/soru-kesici-datasets"',
                f"VERI_KOKU = {veri_koku!r}",
            )
            zip_yolu = os.path.join(d, "paket.zip")
            with zipfile.ZipFile(zip_yolu, "w") as z:
                z.writestr("ql_v4/manifest.json", "{}")
                z.writestr("ql_v4//manifest.json", "{\"alias\": true}")
            with open(zip_yolu, "rb") as f:
                zip_sha = hashlib.sha256(f.read()).hexdigest()
            drive = types.SimpleNamespace(mount=lambda _yol: None)
            google = types.ModuleType("google")
            colab = types.ModuleType("google.colab")
            colab.drive = drive
            ns = {
                "ZIP_YOLU": zip_yolu,
                "ZIP_SHA256": zip_sha,
                "PARCA_KALIBI": os.path.join(d, "parca.*"),
                "ARSIV_KOKU": "ql_v4",
            }
            with mock.patch.dict(sys.modules, {
                    "google": google, "google.colab": colab}):
                with self.assertRaisesRegex(
                        AssertionError, "kanonik olmayan ZIP"):
                    exec(compile(kaynak, "<notebook-hucre-03>", "exec"), ns)

    def test_notebook_eski_cikarma_agacini_yeniden_olusturur(self):
        kaynak = self._notebook_hucresi("hucre-03")
        with tempfile.TemporaryDirectory() as d:
            veri_koku = os.path.join(d, "datasets")
            kaynak = kaynak.replace(
                'VERI_KOKU = "/content/soru-kesici-datasets"',
                f"VERI_KOKU = {veri_koku!r}",
            )
            zip_yolu = os.path.join(d, "paket.zip")
            with zipfile.ZipFile(zip_yolu, "w") as z:
                z.writestr("ql_v4/manifest.json", "{\"fresh\": true}")
            with open(zip_yolu, "rb") as f:
                zip_sha = hashlib.sha256(f.read()).hexdigest()
            eski = os.path.join(veri_koku, zip_sha, "ql_v4")
            os.makedirs(eski)
            with open(os.path.join(eski, "manifest.json"), "w") as f:
                f.write("{\"tampered\": true}")
            with open(os.path.join(veri_koku, zip_sha, ".archive_sha256"), "w") as f:
                f.write(zip_sha)
            drive = types.SimpleNamespace(mount=lambda _yol: None)
            google = types.ModuleType("google")
            colab = types.ModuleType("google.colab")
            colab.drive = drive
            ns = {
                "ZIP_YOLU": zip_yolu,
                "ZIP_SHA256": zip_sha,
                "PARCA_KALIBI": os.path.join(d, "parca.*"),
                "ARSIV_KOKU": "ql_v4",
            }
            with mock.patch.dict(sys.modules, {
                    "google": google, "google.colab": colab}):
                exec(compile(kaynak, "<notebook-hucre-03>", "exec"), ns)
            with open(os.path.join(eski, "manifest.json")) as f:
                self.assertEqual({"fresh": True}, json.load(f))

    def test_notebook_hash_sonrasi_drive_yolu_swap_edilse_de_staged_fd_acilir(self):
        kaynak = self._notebook_hucresi("hucre-03")
        with tempfile.TemporaryDirectory() as d:
            veri_koku = os.path.join(d, "datasets")
            kaynak = kaynak.replace(
                'VERI_KOKU = "/content/soru-kesici-datasets"',
                f"VERI_KOKU = {veri_koku!r}",
            )
            zip_yolu = os.path.join(d, "drive-paket.zip")
            saldirgan_zip = os.path.join(d, "swap.zip")
            with zipfile.ZipFile(zip_yolu, "w") as z:
                z.writestr("ql_v4/manifest.json", "{\"original\": true}")
            with zipfile.ZipFile(saldirgan_zip, "w") as z:
                z.writestr("ql_v4/manifest.json", "{\"swapped\": true}")
            with open(zip_yolu, "rb") as f:
                zip_sha = hashlib.sha256(f.read()).hexdigest()
            drive = types.SimpleNamespace(mount=lambda _yol: None)
            google = types.ModuleType("google")
            colab = types.ModuleType("google.colab")
            colab.drive = drive
            ns = {
                "ZIP_YOLU": zip_yolu,
                "ZIP_SHA256": zip_sha,
                "PARCA_KALIBI": os.path.join(d, "parca.*"),
                "ARSIV_KOKU": "ql_v4",
            }
            gercek_zipfile = zipfile.ZipFile
            swap_yapildi = False

            def zip_ac(dosya, *args, **kwargs):
                nonlocal swap_yapildi
                if not swap_yapildi:
                    self.assertFalse(isinstance(dosya, (str, bytes, os.PathLike)))
                    os.replace(saldirgan_zip, zip_yolu)
                    swap_yapildi = True
                return gercek_zipfile(dosya, *args, **kwargs)

            with mock.patch.dict(sys.modules, {
                    "google": google, "google.colab": colab}), \
                    mock.patch.object(zipfile, "ZipFile", side_effect=zip_ac):
                exec(compile(kaynak, "<notebook-hucre-03>", "exec"), ns)
            self.assertTrue(swap_yapildi)
            manifest_yolu = os.path.join(
                veri_koku, zip_sha, "ql_v4", "manifest.json")
            with open(manifest_yolu) as f:
                self.assertEqual({"original": True}, json.load(f))


if __name__ == "__main__":
    unittest.main()
