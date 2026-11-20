#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soru modeli aday değerlendirmesi ve temiz A/B kapısı için P0 testleri."""

import os
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from PIL import Image

import duzen_model as dm
import soru_model_egitim as sme


class _CanliSahteSurec:
    def poll(self):
        return None


class AdayModelDegerlendirmeTesti(unittest.TestCase):
    def _veri_hazirla(self, kok):
        kok = Path(kok)
        image = kok / "holdout.png"
        label = kok / "holdout.txt"
        best = kok / "best.pt"
        production = kok / "production.pt"
        Image.new("RGB", (100, 100), "white").save(image)
        label.write_text("1 0.5 0.5 1.0 1.0\n", encoding="utf-8")
        best.write_bytes(b"candidate-weights")
        production.write_bytes(b"production-weights")
        rapor = {
            "ok": True,
            "dataset_root": str(kok),
            "dataset_fingerprint": "a" * 64,
            "samples": {
                "holdout": [{
                    "image": image.name,
                    "label": label.name,
                }],
            },
        }
        return best, production, rapor

    def test_degerlendirme_gecici_aday_modeli_kullanir_ve_globals_doner(self):
        with tempfile.TemporaryDirectory() as kok:
            best, production, rapor = self._veri_hazirla(kok)
            production_manifest = str(production) + ".manifest.json"
            production_cache = os.path.join(kok, "production-cache")
            gorulen = {}
            oldurulen_yollar = []

            def oldur():
                oldurulen_yollar.append(dm.SORU_MODEL_YOLU)
                dm._SORU_ISCI = None

            def aday_dogrula(derin=False):
                self.assertFalse(derin)
                self.assertNotEqual(dm.SORU_MODEL_YOLU, str(production))
                self.assertNotEqual(dm.SORU_MODEL_YOLU, str(best))
                self.assertTrue(os.path.isfile(dm.SORU_MODEL_YOLU))
                self.assertTrue(os.path.isfile(dm.SORU_MODEL_MANIFEST_YOLU))
                return {"ok": True, "mesaj": "aday hazır"}

            def cikarim(_img, onbellek_kimlik=None):
                self.assertIsNone(onbellek_kimlik)
                gorulen["model_yolu"] = dm.SORU_MODEL_YOLU
                gorulen["model_baytlari"] = Path(
                    dm.SORU_MODEL_YOLU).read_bytes()
                gorulen["manifest_yolu"] = dm.SORU_MODEL_MANIFEST_YOLU
                gorulen["cache_dizini"] = dm.SORU_MODEL_CACHE_DIZIN
                gorulen["zorla"] = dm.SORU_MODEL_AKTIF_ZORLA
                dm._SORU_ISCI = (_CanliSahteSurec(), object())
                return [{
                    "sinif": "question_body",
                    "kutu": [0.0, 0.0, 100.0, 100.0],
                    "guven": 0.9,
                }]

            with mock.patch.object(sme, "manifest_dogrula",
                                   return_value=rapor), \
                    mock.patch.object(dm, "SORU_MODEL_YOLU",
                                      str(production)), \
                    mock.patch.object(dm, "SORU_MODEL_MANIFEST_YOLU",
                                      production_manifest), \
                    mock.patch.object(dm, "SORU_MODEL_CACHE_DIZIN",
                                      production_cache), \
                    mock.patch.object(dm, "SORU_MODEL_AKTIF_ZORLA", False), \
                    mock.patch.object(dm, "_SORU_BOZUK", True), \
                    mock.patch.object(dm, "_SORU_PROBE_SONUC", "eski-probe"), \
                    mock.patch.object(dm, "_SORU_MANIFEST_CACHE",
                                      "eski-manifest"), \
                    mock.patch.object(dm, "_SORU_SAYAC", 41), \
                    mock.patch.object(dm, "_SORU_ISCI", ("eski-isci",)), \
                    mock.patch.object(dm, "_soru_oldur",
                                      side_effect=oldur), \
                    mock.patch.object(dm, "soru_modeli_dogrula",
                                      side_effect=aday_dogrula), \
                    mock.patch.object(dm, "soru_bolgeleri_gorsel",
                                      side_effect=cikarim):
                sonuc = sme.degerlendir(str(Path(kok) / "manifest.json"),
                                       str(best))

                self.assertTrue(sonuc["ok"])
                self.assertEqual(1.0, sonuc["question_body"]["f1"])
                self.assertEqual(b"candidate-weights",
                                 gorulen["model_baytlari"])
                self.assertTrue(gorulen["zorla"])
                self.assertNotEqual(str(production), gorulen["model_yolu"])
                self.assertNotEqual(str(best), gorulen["model_yolu"])
                self.assertNotEqual(production_cache,
                                    gorulen["cache_dizini"])
                self.assertFalse(os.path.exists(gorulen["model_yolu"]))
                self.assertFalse(os.path.exists(gorulen["manifest_yolu"]))

                self.assertEqual(str(production), dm.SORU_MODEL_YOLU)
                self.assertEqual(production_manifest,
                                 dm.SORU_MODEL_MANIFEST_YOLU)
                self.assertEqual(production_cache,
                                 dm.SORU_MODEL_CACHE_DIZIN)
                self.assertFalse(dm.SORU_MODEL_AKTIF_ZORLA)
                self.assertTrue(dm._SORU_BOZUK)
                self.assertEqual("eski-probe", dm._SORU_PROBE_SONUC)
                self.assertEqual("eski-manifest", dm._SORU_MANIFEST_CACHE)
                self.assertEqual(41, dm._SORU_SAYAC)
                self.assertIsNone(dm._SORU_ISCI)

            self.assertEqual(str(production), oldurulen_yollar[0])
            self.assertNotEqual(str(production), oldurulen_yollar[-1])

    def test_cikarim_hatasi_yayin_kapisini_kapali_tutar(self):
        with tempfile.TemporaryDirectory() as kok:
            best, production, rapor = self._veri_hazirla(kok)

            def oldur():
                dm._SORU_ISCI = None

            def bozuk_cikarim(_img, onbellek_kimlik=None):
                dm._SORU_BOZUK = True
                dm._SORU_ISCI = None
                return []

            with mock.patch.object(sme, "manifest_dogrula",
                                   return_value=rapor), \
                    mock.patch.object(dm, "SORU_MODEL_YOLU",
                                      str(production)), \
                    mock.patch.object(dm, "SORU_MODEL_MANIFEST_YOLU",
                                      str(production) + ".manifest.json"), \
                    mock.patch.object(dm, "SORU_MODEL_CACHE_DIZIN",
                                      os.path.join(kok, "production-cache")), \
                    mock.patch.object(dm, "SORU_MODEL_AKTIF_ZORLA", None), \
                    mock.patch.object(dm, "_SORU_BOZUK", False), \
                    mock.patch.object(dm, "_SORU_PROBE_SONUC", None), \
                    mock.patch.object(dm, "_SORU_MANIFEST_CACHE", None), \
                    mock.patch.object(dm, "_SORU_SAYAC", 0), \
                    mock.patch.object(dm, "_SORU_ISCI", None), \
                    mock.patch.object(dm, "_soru_oldur",
                                      side_effect=oldur), \
                    mock.patch.object(dm, "soru_modeli_dogrula",
                                      return_value={"ok": True}), \
                    mock.patch.object(dm, "soru_bolgeleri_gorsel",
                                      side_effect=bozuk_cikarim):
                sonuc = sme.degerlendir(str(Path(kok) / "manifest.json"),
                                       str(best))

                self.assertFalse(sonuc["ok"])
                self.assertIn("çıkarım işçisi hata verdi", sonuc["hata"])
                self.assertEqual(str(production), dm.SORU_MODEL_YOLU)
                self.assertFalse(dm._SORU_BOZUK)
                self.assertIsNone(dm._SORU_ISCI)

    def test_degerlendirme_sha_kaynaktan_degil_olculen_kopyadan_alinir(self):
        with tempfile.TemporaryDirectory() as kok:
            best, production, rapor = self._veri_hazirla(kok)
            asil_copy = sme.shutil.copy2
            degisti = False

            def kopyalamadan_once_degistir(kaynak, hedef, *args, **kwargs):
                nonlocal degisti
                if os.path.abspath(kaynak) == os.path.abspath(best) \
                        and not degisti:
                    degisti = True
                    best.write_bytes(b"candidate-after-hash-window")
                return asil_copy(kaynak, hedef, *args, **kwargs)

            def oldur():
                dm._SORU_ISCI = None

            def cikarim(_img, onbellek_kimlik=None):
                dm._SORU_ISCI = (_CanliSahteSurec(), object())
                return [{
                    "sinif": "question_body",
                    "kutu": [0.0, 0.0, 100.0, 100.0],
                    "guven": 0.9,
                }]

            with mock.patch.object(sme, "manifest_dogrula",
                                   return_value=rapor), \
                    mock.patch.object(sme.shutil, "copy2",
                                      side_effect=kopyalamadan_once_degistir), \
                    mock.patch.object(dm, "SORU_MODEL_YOLU",
                                      str(production)), \
                    mock.patch.object(dm, "SORU_MODEL_MANIFEST_YOLU",
                                      str(production) + ".manifest.json"), \
                    mock.patch.object(dm, "SORU_MODEL_CACHE_DIZIN",
                                      os.path.join(kok, "production-cache")), \
                    mock.patch.object(dm, "SORU_MODEL_AKTIF_ZORLA", None), \
                    mock.patch.object(dm, "_SORU_BOZUK", False), \
                    mock.patch.object(dm, "_SORU_PROBE_SONUC", None), \
                    mock.patch.object(dm, "_SORU_MANIFEST_CACHE", None), \
                    mock.patch.object(dm, "_SORU_SAYAC", 0), \
                    mock.patch.object(dm, "_SORU_ISCI", None), \
                    mock.patch.object(dm, "_soru_oldur",
                                      side_effect=oldur), \
                    mock.patch.object(dm, "soru_modeli_dogrula",
                                      return_value={"ok": True}), \
                    mock.patch.object(dm, "soru_bolgeleri_gorsel",
                                      side_effect=cikarim):
                sonuc = sme.degerlendir(
                    str(Path(kok) / "manifest.json"), str(best))

            self.assertTrue(sonuc["ok"])
            self.assertTrue(degisti)
            self.assertEqual(
                sme._sha256_dosya(best),
                sonuc["candidate_weights_sha256"],
            )

    def test_kutu_eslesmesi_tahmin_sirasindan_bagimsizdir(self):
        gercek = [
            (0.0, 0.0, 10.0, 10.0),
            (7.0, 0.0, 17.0, 10.0),
        ]
        # geniş tahmin iki gerçeğe de ≥0.5 IoU ile uyuyor ama ilkine daha
        # yakın; dar tahmin yalnız ilk gerçekle eşleşebilir.
        tahminler = [
            (0.0, 0.0, 16.0, 10.0),
            (0.0, 0.0, 10.0, 10.0),
        ]
        self.assertEqual(
            (2, 0, 0),
            sme._kutu_eslesme_sayilari(tahminler, gercek, esik=0.5),
        )
        self.assertEqual(
            (2, 0, 0),
            sme._kutu_eslesme_sayilari(
                list(reversed(tahminler)), gercek, esik=0.5),
        )

    def test_kutu_eslesmesi_acgozlu_iou_tuzaginda_kardinaliteyi_korur(self):
        # IoU matrisi:
        #   T0→G0=.667, T0→G1=1.0
        #   T1→G0=.400, T1→G1=.600
        # En yüksek IoU'yu (T0,G1) açgözlü seçmek yalnız 1 TP bırakır. Doğru
        # maksimum eşleştirme T0→G0 + T1→G1 ile 2 TP'dir.
        gercek = [
            (0.0, 0.0, 2.0, 10.0),
            (0.0, 0.0, 3.0, 10.0),
        ]
        tahminler = [
            (0.0, 0.0, 3.0, 10.0),
            (0.0, 0.0, 5.0, 10.0),
        ]
        self.assertEqual(
            (2, 0, 0),
            sme._kutu_eslesme_sayilari(tahminler, gercek, esik=0.5),
        )
        self.assertEqual(
            (2, 0, 0),
            sme._kutu_eslesme_sayilari(
                list(reversed(tahminler)), gercek, esik=0.5),
        )

    def test_ayni_geometri_farkli_sinifta_reddedilir(self):
        with tempfile.TemporaryDirectory() as kok:
            etiket = Path(kok) / "cakisan.txt"
            etiket.write_text(
                "1 0.5 0.5 0.4 0.3\n"
                "3 0.5 0.5 0.4 0.3\n",
                encoding="utf-8",
            )
            hatalar = []
            sayilar = {sinif: 0 for sinif in sme.SINIFLAR}
            kutu = sme._yolo_etiket_dogrula(
                str(etiket), "ornek", hatalar, sayilar)
            self.assertEqual(1, kutu)
            self.assertTrue(any(
                "aynı kutu birden fazla sınıfta" in h for h in hatalar))

    def test_yayin_adayi_degerlendirilen_sha_ile_ayni_olmali(self):
        with tempfile.TemporaryDirectory() as kok:
            best = Path(kok) / "best.pt"
            best.write_bytes(b"aday")
            degerlendirme = {
                "ok": True,
                "question_body": {"f1": 1.0},
                "candidate_weights_sha256": "0" * 64,
                "dataset_fingerprint": "a" * 64,
            }
            with mock.patch.object(
                    sme,
                    "manifest_dogrula",
                    return_value={
                        "ok": True,
                        "dataset_fingerprint": "a" * 64,
                    },
            ), mock.patch.object(
                    sme, "_surumlu_model_yayinla") as yayin:
                sonuc = sme.yayinla(
                    str(best), str(Path(kok) / "manifest.json"),
                    "test", degerlendirme)
            self.assertFalse(sonuc["ok"])
            self.assertIn("SHA-256", sonuc["neden"])
            yayin.assert_not_called()


class EgitimOrkestratoruTesti(unittest.TestCase):
    class _SahteSurec:
        def __init__(self, satirlar, returncode):
            self.stdout = satirlar
            self.returncode = returncode

        def wait(self):
            return self.returncode

    def _ortam(self, kok):
        kok = Path(kok)
        base = kok / "base.pt"
        base.write_bytes(b"base")
        plan = {"command": ["python", "isci.py"], "environment": {}}
        return base, plan

    def test_nonzero_isci_eslesen_basari_jsonu_bile_kabul_edilmez(self):
        with tempfile.TemporaryDirectory() as kok:
            kok = Path(kok)
            (kok / "runs").mkdir()
            base, plan = self._ortam(kok)

            def popen(komut, **_kwargs):
                run_id = komut[komut.index("--run-id") + 1]
                (kok / "runs" / "sonuc.json").write_text(json.dumps({
                    "ok": True,
                    "run_id": run_id,
                    "started_at_ns": 10**30,
                    "best_path": "YANLIS",
                }), encoding="utf-8")
                return self._SahteSurec([
                    json.dumps({
                        "ok": False,
                        "run_id": run_id,
                        "hata": "beklenen işçi hatası",
                    }) + "\n",
                ], 2)

            with mock.patch.object(sme, "_doclayout_repo",
                                   return_value=str(kok)), \
                    mock.patch.object(dm, "MODEL_YOLU", str(base)), \
                    mock.patch.object(sme, "egitim_plani_hazirla",
                                      return_value=plan), \
                    mock.patch("subprocess.Popen", side_effect=popen):
                sonuc = sme.calistir("manifest.json", str(kok))

            self.assertFalse(sonuc["ok"])
            self.assertEqual(2, sonuc["returncode"])
            self.assertIn("beklenen işçi hatası", sonuc["hata"])
            self.assertNotIn("best_path", sonuc)

    def test_sifir_kodlu_isci_eski_sonuc_jsonu_kabul_edemez(self):
        with tempfile.TemporaryDirectory() as kok:
            kok = Path(kok)
            (kok / "runs").mkdir()
            base, plan = self._ortam(kok)
            (kok / "runs" / "sonuc.json").write_text(json.dumps({
                "ok": True,
                "run_id": "eski-kosu",
                "started_at_ns": 10**30,
                "best_path": "ESKI",
            }), encoding="utf-8")

            with mock.patch.object(sme, "_doclayout_repo",
                                   return_value=str(kok)), \
                    mock.patch.object(dm, "MODEL_YOLU", str(base)), \
                    mock.patch.object(sme, "egitim_plani_hazirla",
                                      return_value=plan), \
                    mock.patch(
                        "subprocess.Popen",
                        return_value=self._SahteSurec([], 0)):
                sonuc = sme.calistir("manifest.json", str(kok))

            self.assertFalse(sonuc["ok"])
            self.assertIn("bu eğitim koşusuna ait değil", sonuc["hata"])

    def test_sifir_kod_ve_eslesen_kosu_kimligi_basariyi_gecirir(self):
        with tempfile.TemporaryDirectory() as kok:
            kok = Path(kok)
            (kok / "runs").mkdir()
            base, plan = self._ortam(kok)

            def popen(komut, **_kwargs):
                run_id = komut[komut.index("--run-id") + 1]
                (kok / "runs" / "sonuc.json").write_text(json.dumps({
                    "ok": True,
                    "run_id": run_id,
                    "started_at_ns": __import__("time").time_ns(),
                    "best_path": "YENI",
                }), encoding="utf-8")
                return self._SahteSurec([], 0)

            with mock.patch.object(sme, "_doclayout_repo",
                                   return_value=str(kok)), \
                    mock.patch.object(dm, "MODEL_YOLU", str(base)), \
                    mock.patch.object(sme, "egitim_plani_hazirla",
                                      return_value=plan), \
                    mock.patch("subprocess.Popen", side_effect=popen):
                sonuc = sme.calistir("manifest.json", str(kok))

            self.assertTrue(sonuc["ok"])
            self.assertEqual("YENI", sonuc["best_path"])
            self.assertEqual(0, sonuc["returncode"])


if __name__ == "__main__":
    unittest.main()
