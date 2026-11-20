#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import duzen_model as dm
import soru_model_egitim as sme


def _sha(veri):
    return hashlib.sha256(veri).hexdigest()


def _degerlendirme(aday_sha, veri_sha):
    sonuc = {
        "ok": True,
        "candidate_weights_sha256": aday_sha,
        "dataset_fingerprint": veri_sha,
        "holdout_sample_count": 4,
        "recommended_conf": 0.25,
    }
    for sinif in sme.SINIFLAR:
        sonuc[sinif] = {
            "precision": 0.9,
            "recall": 0.9,
            "f1": 0.9,
            "tp": 9,
            "fp": 1,
            "fn": 1,
            "support": 10,
        }
    return sonuc


def _baglilik_dosyalari(kok, aday_sha, aday_boyut, veri_sha):
    paket_sha = "b" * 64
    arsiv_sha = "c" * 64
    base_sha = "d" * 64
    sonuc = {
        "ok": True,
        "resume": False,
        "run_id": "palme-v4-test",
        "best_sha256": aday_sha,
        "best_size": aday_boyut,
        "source_dataset_fingerprint": veri_sha,
        "training_package_sha256": paket_sha,
        "archive_sha256": arsiv_sha,
        "base_model_sha256": base_sha,
        "started_at_ns": 1,
        "finished_at_ns": 2,
        "config": {"epochs": 1},
    }
    paket = {
        "package_schema_version":
            "soru-kesici.question-layout-colab-package/v1",
        "classes": list(sme.SINIFLAR),
        "source_dataset_fingerprint": veri_sha,
        "training_package_sha256": paket_sha,
        "archive_sha256": arsiv_sha,
        "base_model": {
            "sha256": base_sha,
            "size": 123,
            "path": "base/base.pt",
        },
    }
    sonuc_yolu = os.path.join(kok, "sonuc.json")
    paket_yolu = os.path.join(kok, "paket.manifest.json")
    Path(sonuc_yolu).write_text(
        json.dumps(sonuc), encoding="utf-8")
    Path(paket_yolu).write_text(
        json.dumps(paket), encoding="utf-8")
    return sonuc_yolu, paket_yolu


class SinifKapisiTesti(unittest.TestCase):
    def test_dort_sinif_raporu_zorunludur(self):
        deg = _degerlendirme("a" * 64, "b" * 64)
        del deg["question_anchor"]
        self.assertTrue(any(
            "question_anchor" in b
            for b in sme._sinif_kalite_bulgulari(deg)
        ))

    def test_holdout_destegi_olmayan_sinifta_fp_reddedilir(self):
        deg = _degerlendirme("a" * 64, "b" * 64)
        deg["solution_or_answer"].update({
            "support": 0,
            "tp": 0,
            "fn": 0,
            "fp": 2,
            "f1": 0.0,
            "recall": 0.0,
        })
        bulgular = sme._sinif_kalite_bulgulari(deg)
        self.assertTrue(any(
            "solution_or_answer" in b and "yanlış pozitif" in b
            for b in bulgular
        ))

    def test_holdout_destegi_sifir_sinif_fp_olmasa_da_reddedilir(self):
        deg = _degerlendirme("a" * 64, "b" * 64)
        deg["shared_stimulus"].update({
            "support": 0,
            "tp": 0,
            "fn": 0,
            "fp": 0,
            "precision": 1.0,
            "recall": 1.0,
            "f1": 1.0,
        })
        bulgular = sme._sinif_kalite_bulgulari(deg)
        self.assertTrue(any(
            "shared_stimulus" in b and "kapısı ölçülemedi" in b
            for b in bulgular
        ))

    def test_sinif_bazi_minimum_destek_esiginin_alti_red_ustu_gecer(self):
        esikler = {
            "question_anchor": 10,
            "question_body": 10,
            "shared_stimulus": 3,
            "solution_or_answer": 10,
        }
        for sinif, esik in esikler.items():
            with self.subTest(sinif=sinif, durum="alti"):
                deg = _degerlendirme("a" * 64, "b" * 64)
                deg[sinif]["support"] = esik - 1
                bulgular = sme._sinif_kalite_bulgulari(deg)
                self.assertTrue(any(
                    sinif in b and f"< {esik}" in b for b in bulgular))
            with self.subTest(sinif=sinif, durum="esik"):
                deg = _degerlendirme("a" * 64, "b" * 64)
                deg[sinif]["support"] = esik
                bulgular = sme._sinif_kalite_bulgulari(deg)
                self.assertFalse(any(
                    sinif in b and "holdout desteği" in b for b in bulgular))

    def test_minimum_destek_esikleri_testte_enjekte_edilebilir(self):
        deg = _degerlendirme("a" * 64, "b" * 64)
        deg["shared_stimulus"]["support"] = 1
        esikler = {sinif: 1 for sinif in sme.SINIFLAR}
        self.assertEqual(
            [], sme._sinif_kalite_bulgulari(
                deg, minimum_destek=esikler))


class EgitimBagliligiTesti(unittest.TestCase):
    def test_sonuc_paket_ve_aday_tum_hashlerle_baglanir(self):
        with tempfile.TemporaryDirectory() as d:
            veri_sha = "a" * 64
            sonuc, paket = _baglilik_dosyalari(
                d, "e" * 64, 42, veri_sha)
            bag = sme._egitim_bagliligini_dogrula(
                sonuc, paket, "e" * 64, 42, veri_sha)
            self.assertEqual("palme-v4-test", bag["run_id"])
            self.assertEqual("b" * 64, bag["training_package_sha256"])
            self.assertFalse(bag["resume"])

    def test_farkli_paket_sha_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            veri_sha = "a" * 64
            sonuc, paket = _baglilik_dosyalari(
                d, "e" * 64, 42, veri_sha)
            veri = json.loads(Path(paket).read_text(encoding="utf-8"))
            veri["training_package_sha256"] = "f" * 64
            Path(paket).write_text(json.dumps(veri), encoding="utf-8")
            with self.assertRaisesRegex(
                    ValueError, "training_package_sha256"):
                sme._egitim_bagliligini_dogrula(
                    sonuc, paket, "e" * 64, 42, veri_sha)

    def test_resume_sonucu_yayinlanamaz(self):
        with tempfile.TemporaryDirectory() as d:
            veri_sha = "a" * 64
            sonuc, paket = _baglilik_dosyalari(
                d, "e" * 64, 42, veri_sha)
            veri = json.loads(Path(sonuc).read_text(encoding="utf-8"))
            veri["resume"] = True
            Path(sonuc).write_text(json.dumps(veri), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "resume=False"):
                sme._egitim_bagliligini_dogrula(
                    sonuc, paket, "e" * 64, 42, veri_sha)


class DegismezAdayVeAtomikPointerTesti(unittest.TestCase):
    def test_kaynak_sonradan_degisse_degerlendirilmis_staging_yayinlanir(self):
        with tempfile.TemporaryDirectory() as d:
            eski = b"DEGERLENDIRILEN"
            best = os.path.join(d, "best.pt")
            Path(best).write_bytes(eski)
            aday_sha = _sha(eski)
            veri_sha = "a" * 64
            sonuc, paket = _baglilik_dosyalari(
                d, aday_sha, len(eski), veri_sha)
            deg = _degerlendirme(aday_sha, veri_sha)
            asil_copy = sme.shutil.copy2
            gorulen = {}

            def copy_ve_kaynagi_degistir(kaynak, hedef):
                sonuc_copy = asil_copy(kaynak, hedef)
                if os.path.abspath(kaynak) == os.path.abspath(best):
                    Path(best).write_bytes(b"DEGERLENDIRILMEMIS")
                return sonuc_copy

            def sahte_yayin(staged, *_args):
                gorulen["yol"] = staged
                gorulen["bayt"] = Path(staged).read_bytes()
                return {
                    "model_yolu": "/aktif/model.pt",
                    "manifest_yolu": "/aktif/model.pt.manifest.json",
                    "model_id": "v4:test",
                }

            with mock.patch.object(
                    sme,
                    "manifest_dogrula",
                    return_value={
                        "ok": True,
                        "dataset_fingerprint": veri_sha,
                    },
            ), mock.patch.object(
                    sme.shutil,
                    "copy2",
                    side_effect=copy_ve_kaynagi_degistir,
            ), mock.patch.object(
                    sme,
                    "_surumlu_model_yayinla",
                    side_effect=sahte_yayin,
            ):
                yayin = sme.yayinla(
                    best,
                    os.path.join(d, "manifest.json"),
                    "v4-test",
                    deg,
                    egitim_sonucu_yolu=sonuc,
                    paket_manifest_yolu=paket,
                )
            self.assertTrue(yayin["ok"])
            self.assertEqual(eski, gorulen["bayt"])
            self.assertEqual(b"DEGERLENDIRILMEMIS", Path(best).read_bytes())
            self.assertFalse(os.path.exists(gorulen["yol"]))

    def test_model_manifest_cifti_tek_aktif_symlink_altinda_yayinlanir(self):
        with tempfile.TemporaryDirectory() as d:
            model_dizini = os.path.join(d, "modeller")
            surumler = os.path.join(model_dizini, "surumler")
            aktif = os.path.join(model_dizini, "aktif")
            best = os.path.join(d, "best.pt")
            Path(best).write_bytes(b"model-v4")
            aday_sha = _sha(b"model-v4")
            onceki_yollar = (
                dm.SORU_MODEL_YOLU,
                dm.SORU_MODEL_MANIFEST_YOLU,
                dm._SORU_MODEL_OTOMATIK_YOLLAR,
            )
            try:
                with mock.patch.object(
                        dm, "SORU_MODEL_SURUMLER_DIZINI", surumler
                ), mock.patch.object(
                        dm, "SORU_MODEL_AKTIF_BAGLANTI", aktif
                ), mock.patch.object(dm, "kapat"):
                    sonuc = sme._surumlu_model_yayinla(
                        best,
                        "a" * 64,
                        "v4-test",
                        {"purpose": "test"},
                        aday_sha,
                    )
                self.assertTrue(os.path.islink(aktif))
                self.assertEqual(
                    b"model-v4",
                    Path(sonuc["model_yolu"]).read_bytes(),
                )
                manifest = json.loads(Path(
                    sonuc["manifest_yolu"]).read_text(encoding="utf-8"))
                self.assertEqual(aday_sha, manifest["weights_sha256"])
                self.assertEqual(
                    os.path.dirname(sonuc["model_yolu"]),
                    os.path.dirname(sonuc["manifest_yolu"]),
                )
            finally:
                dm.SORU_MODEL_YOLU = onceki_yollar[0]
                dm.SORU_MODEL_MANIFEST_YOLU = onceki_yollar[1]
                dm._SORU_MODEL_OTOMATIK_YOLLAR = onceki_yollar[2]

    def test_manifest_dogrulamasindan_sonra_model_degisse_yayinlanmaz(self):
        with tempfile.TemporaryDirectory() as d:
            model_dizini = os.path.join(d, "modeller")
            surumler = os.path.join(model_dizini, "surumler")
            aktif = os.path.join(model_dizini, "aktif")
            best = os.path.join(d, "best.pt")
            Path(best).write_bytes(b"model-v4")
            aday_sha = _sha(b"model-v4")
            asil_dogrula = dm.soru_modeli_dogrula
            degistirildi = False

            def dogrula_ve_degistir(*args, **kwargs):
                nonlocal degistirildi
                sonuc = asil_dogrula(*args, **kwargs)
                model_yolu = kwargs.get("model_yolu")
                if sonuc.get("ok") and model_yolu and not degistirildi:
                    Path(model_yolu).write_bytes(b"model-v4-tampered")
                    degistirildi = True
                return sonuc

            with mock.patch.object(
                    dm, "SORU_MODEL_SURUMLER_DIZINI", surumler
            ), mock.patch.object(
                    dm, "SORU_MODEL_AKTIF_BAGLANTI", aktif
            ), mock.patch.object(
                    dm, "soru_modeli_dogrula",
                    side_effect=dogrula_ve_degistir,
            ), mock.patch.object(dm, "kapat"):
                with self.assertRaisesRegex(
                        RuntimeError, "doğrulamasından sonra değişti"):
                    sme._surumlu_model_yayinla(
                        best,
                        "a" * 64,
                        "v4-test",
                        {"purpose": "test"},
                        aday_sha,
                    )
            self.assertTrue(degistirildi)
            self.assertFalse(os.path.lexists(aktif))

    def test_staging_manifest_sha_beklenen_adayla_ayni_olmali(self):
        with tempfile.TemporaryDirectory() as d:
            model_dizini = os.path.join(d, "modeller")
            surumler = os.path.join(model_dizini, "surumler")
            aktif = os.path.join(model_dizini, "aktif")
            best = os.path.join(d, "best.pt")
            Path(best).write_bytes(b"model-v4")
            aday_sha = _sha(b"model-v4")
            asil_manifest_yaz = sme.model_manifesti_yaz

            def yanlis_ozet_dondur(*args, **kwargs):
                manifest = asil_manifest_yaz(*args, **kwargs)
                return {**manifest, "weights_sha256": "f" * 64}

            with mock.patch.object(
                    dm, "SORU_MODEL_SURUMLER_DIZINI", surumler
            ), mock.patch.object(
                    dm, "SORU_MODEL_AKTIF_BAGLANTI", aktif
            ), mock.patch.object(
                    sme, "model_manifesti_yaz",
                    side_effect=yanlis_ozet_dondur,
            ), mock.patch.object(dm, "kapat"):
                with self.assertRaisesRegex(
                        RuntimeError, "manifesti beklenen aday"):
                    sme._surumlu_model_yayinla(
                        best,
                        "a" * 64,
                        "v4-test",
                        {"purpose": "test"},
                        aday_sha,
                    )
            self.assertFalse(os.path.lexists(aktif))

    def test_aktif_dogrulama_hatasinda_pointer_eski_surume_doner(self):
        with tempfile.TemporaryDirectory() as d:
            model_dizini = os.path.join(d, "modeller")
            surumler = os.path.join(model_dizini, "surumler")
            aktif = os.path.join(model_dizini, "aktif")
            eski = os.path.join(d, "eski.pt")
            yeni = os.path.join(d, "yeni.pt")
            Path(eski).write_bytes(b"eski-model")
            Path(yeni).write_bytes(b"yeni-model")
            onceki_yollar = (
                dm.SORU_MODEL_YOLU,
                dm.SORU_MODEL_MANIFEST_YOLU,
                dm._SORU_MODEL_OTOMATIK_YOLLAR,
            )
            try:
                with mock.patch.object(
                        dm, "SORU_MODEL_SURUMLER_DIZINI", surumler
                ), mock.patch.object(
                        dm, "SORU_MODEL_AKTIF_BAGLANTI", aktif
                ), mock.patch.object(dm, "kapat"):
                    sme._surumlu_model_yayinla(
                        eski, "a" * 64, "eski",
                        {"purpose": "test"}, _sha(b"eski-model"))
                    eski_hedef = os.readlink(aktif)
                    asil_dogrula = dm.soru_modeli_dogrula
                    cagrilar = 0

                    def ikinci_kontrolde_hata(*args, **kwargs):
                        nonlocal cagrilar
                        cagrilar += 1
                        if cagrilar == 2:
                            return {"ok": False, "mesaj": "beklenen"}
                        return asil_dogrula(*args, **kwargs)

                    with mock.patch.object(
                            dm, "soru_modeli_dogrula",
                            side_effect=ikinci_kontrolde_hata):
                        with self.assertRaisesRegex(
                                RuntimeError, "aktif sürüm"):
                            sme._surumlu_model_yayinla(
                                yeni, "a" * 64, "yeni",
                                {"purpose": "test"},
                                _sha(b"yeni-model"))
                self.assertEqual(eski_hedef, os.readlink(aktif))
                self.assertEqual(
                    b"eski-model",
                    Path(os.path.join(aktif, "model.pt")).read_bytes(),
                )
            finally:
                dm.SORU_MODEL_YOLU = onceki_yollar[0]
                dm.SORU_MODEL_MANIFEST_YOLU = onceki_yollar[1]
                dm._SORU_MODEL_OTOMATIK_YOLLAR = onceki_yollar[2]


if __name__ == "__main__":
    unittest.main()
