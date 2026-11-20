#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import types
import unittest
from unittest import mock

import soru_model_egitim_isci as isci


class EgitimIsciGuvenligiTesti(unittest.TestCase):
    def _sahte_egitim(self, d, davranis, *, resume=False):
        base = os.path.join(d, "base.pt")
        data = os.path.join(d, "data.yaml")
        with open(base, "wb") as f:
            f.write(b"base")
        with open(data, "w") as f:
            f.write("train: train.txt\n")

        olusturulan = []

        class SahteModel:
            def __init__(self, yol):
                olusturulan.append(yol)
                self.yol = yol

            def add_callback(self, *_args):
                pass

            def train(self, **_kwargs):
                if not os.path.isfile(self.yol):
                    raise RuntimeError(
                        "doğrulanmış geçici checkpoint eğitimden önce silindi")
                return davranis()

        sahte_torch = types.ModuleType("torch")
        sahte_torch.load = lambda *_a, **_k: None
        sahte_torch.backends = types.SimpleNamespace(
            mps=types.SimpleNamespace(is_available=lambda: False))
        sahte_doclayout = types.ModuleType("doclayout_yolo")
        sahte_doclayout.YOLOv10 = SahteModel

        argv = [
            "soru_model_egitim_isci.py",
            "--doclayout-repo", d,
            "--model", base,
            "--data", data,
            "--output", d,
            "--device", "cpu",
            "--run-id", "test-run",
        ]
        if resume:
            argv.append("--resume")
        cikti = io.StringIO()
        with mock.patch.object(sys, "argv", argv), \
                mock.patch.dict(sys.modules, {
                    "torch": sahte_torch,
                    "doclayout_yolo": sahte_doclayout,
                }), mock.patch.object(
                    isci, "RESMI_BASE_MODEL_SHA256",
                    hashlib.sha256(b"base").hexdigest()), \
                mock.patch.object(
                    isci, "RESMI_BASE_MODEL_BOYUT", 4), \
                contextlib.redirect_stdout(cikti):
            kod = isci.main()
        json_satirlari = [
            json.loads(satir)
            for satir in cikti.getvalue().splitlines()
            if satir.startswith("{")
        ]
        self.assertTrue(json_satirlari, cikti.getvalue())
        return kod, json_satirlari[-1], olusturulan

    @staticmethod
    def _checkpoint_yaz(d, *, best=None, last=None):
        agirlik_dizini = os.path.dirname(isci._best_yolu(d))
        os.makedirs(agirlik_dizini, exist_ok=True)
        if best is not None:
            with open(isci._best_yolu(d), "wb") as f:
                f.write(best)
        if last is not None:
            with open(isci._last_yolu(d), "wb") as f:
                f.write(last)

    def test_resume_yokken_eski_best_basari_sayilmaz(self):
        with tempfile.TemporaryDirectory() as d:
            best = isci._best_yolu(d)
            os.makedirs(os.path.dirname(best))
            with open(best, "wb") as f:
                f.write(b"eski")
            argv = [
                "soru_model_egitim_isci.py",
                "--doclayout-repo", "/yok",
                "--model", "/yok/base.pt",
                "--data", "/yok/data.yaml",
                "--output", d,
            ]
            cikti = io.StringIO()
            with mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(cikti):
                kod = isci.main()
            self.assertEqual(2, kod)
            sonuc = json.loads(cikti.getvalue())
            self.assertFalse(sonuc["ok"])
            self.assertIn("eski best.pt", sonuc["hata"])
            self.assertEqual(best, sonuc["best_path"])

    def test_resume_basarili_donse_bile_checkpoint_ilerlemelidir(self):
        with tempfile.TemporaryDirectory() as d:
            self._checkpoint_yaz(d, best=b"eski-best", last=b"eski-last")
            kod, sonuc, olusturulan = self._sahte_egitim(
                d, lambda: None, resume=True)
            self.assertEqual(1, kod)
            self.assertFalse(sonuc["ok"])
            self.assertFalse(sonuc["checkpoint_progressed"])
            self.assertIn("ilerlemedi", sonuc["hata"])
            self.assertEqual(1, len(olusturulan))
            self.assertNotEqual(isci._last_yolu(d), olusturulan[0])
            self.assertEqual(
                "dogrulanmis-model.pt", os.path.basename(olusturulan[0]))
            self.assertFalse(os.path.exists(olusturulan[0]))

    def test_resume_last_ilerlerse_eski_best_gecerli_kalabilir(self):
        with tempfile.TemporaryDirectory() as d:
            self._checkpoint_yaz(d, best=b"eski-best", last=b"eski-last")

            def ilerlet():
                self._checkpoint_yaz(d, last=b"yeni-last")

            kod, sonuc, _ = self._sahte_egitim(d, ilerlet, resume=True)
            self.assertEqual(0, kod)
            self.assertTrue(sonuc["ok"])
            self.assertTrue(sonuc["checkpoint_progressed"])
            self.assertFalse(sonuc["best_changed"])
            self.assertEqual("test-run", sonuc["run_id"])

    def test_checkpoint_yazan_egitim_istisnasi_fail_closed_kalir(self):
        with tempfile.TemporaryDirectory() as d:
            def yarim_egitim():
                self._checkpoint_yaz(
                    d, best=b"yarim-best", last=b"yarim-last")
                raise RuntimeError("OOM")

            kod, sonuc, _ = self._sahte_egitim(d, yarim_egitim)
            self.assertEqual(1, kod)
            self.assertFalse(sonuc["ok"])
            self.assertTrue(sonuc["checkpoint_progressed"])
            self.assertIn("RuntimeError: OOM", sonuc["hata"])

    def test_temiz_kosu_best_ve_last_uretirse_basarili(self):
        with tempfile.TemporaryDirectory() as d:
            def tamamla():
                self._checkpoint_yaz(
                    d, best=b"yeni-best", last=b"yeni-last")

            kod, sonuc, olusturulan = self._sahte_egitim(d, tamamla)
            self.assertEqual(0, kod)
            self.assertTrue(sonuc["ok"])
            self.assertTrue(sonuc["checkpoint_progressed"])
            self.assertTrue(sonuc["best_changed"])
            self.assertEqual(1, len(olusturulan))
            self.assertNotEqual(os.path.join(d, "base.pt"), olusturulan[0])
            self.assertEqual(
                "dogrulanmis-model.pt", os.path.basename(olusturulan[0]))
            self.assertFalse(os.path.exists(olusturulan[0]))

    def test_resmi_guven_kokune_uymayan_base_yuklenmez(self):
        with tempfile.TemporaryDirectory() as d:
            base = os.path.join(d, "base.pt")
            data = os.path.join(d, "data.yaml")
            with open(base, "wb") as f:
                f.write(b"sahte")
            with open(data, "w") as f:
                f.write("train: train.txt\n")
            argv = [
                "soru_model_egitim_isci.py",
                "--doclayout-repo", d,
                "--model", base,
                "--data", data,
                "--output", d,
                "--device", "cpu",
            ]
            cikti = io.StringIO()
            with mock.patch.object(sys, "argv", argv), \
                    contextlib.redirect_stdout(cikti):
                kod = isci.main()
            self.assertEqual(2, kod)
            sonuc = json.loads(cikti.getvalue())
            self.assertFalse(sonuc["ok"])
            self.assertIn("resmi boyut", sonuc["hata"])


if __name__ == "__main__":
    unittest.main()
