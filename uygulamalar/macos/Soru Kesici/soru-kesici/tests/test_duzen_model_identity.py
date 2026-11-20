#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import hashlib
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import duzen_isci
import duzen_model as dm
from PIL import Image


class _Stdin:
    def __init__(self):
        self.yazilan = []

    def write(self, deger):
        self.yazilan.append(deger)

    def flush(self):
        return None


class _Proc:
    def __init__(self):
        self.stdin = _Stdin()

    def poll(self):
        return None


class _Kuyruk:
    def __init__(self, yanit):
        self.yanit = yanit

    def get(self, timeout=None):
        return self.yanit


class ModelKopyasiTesti(unittest.TestCase):
    def test_ozel_kopya_sha_eslesmeden_kabul_edilmez(self):
        with tempfile.TemporaryDirectory() as d:
            kaynak = os.path.join(d, "model.pt")
            hedef = os.path.join(d, "kopya.pt")
            with open(kaynak, "wb") as f:
                f.write(b"model-baytlari")
            with self.assertRaisesRegex(RuntimeError, "SHA-256 uyuşmuyor"):
                duzen_isci._modeli_ozel_kopyaya_al(
                    kaynak, "0" * 64, hedef)

    def test_ozel_kopya_bayt_ve_sha_kilitlidir(self):
        with tempfile.TemporaryDirectory() as d:
            kaynak = os.path.join(d, "model.pt")
            hedef = os.path.join(d, "kopya.pt")
            veri = b"model-baytlari"
            with open(kaynak, "wb") as f:
                f.write(veri)
            ozet = hashlib.sha256(veri).hexdigest()
            self.assertEqual(
                ozet,
                duzen_isci._modeli_ozel_kopyaya_al(
                    kaynak, ozet, hedef),
            )
            with open(hedef, "rb") as f:
                self.assertEqual(veri, f.read())


class CalisanModelKimligiTesti(unittest.TestCase):
    def setUp(self):
        dm._soru_oldur()
        dm._SORU_ISCI = None
        dm._SORU_ISCI_KIMLIK = None
        dm._SORU_BOZUK = False
        dm._SORU_PROBE_SONUC = None
        dm._SORU_MANIFEST_CACHE = None
        dm._SORU_DURUM_KIMLIK = None
        dm._SORU_SAYAC = 0
        dm._SORU_GOZLENEN_KIMLIKLER.clear()

    def tearDown(self):
        dm._SORU_ISCI = None
        dm._SORU_ISCI_KIMLIK = None
        dm._SORU_BOZUK = False
        dm._SORU_PROBE_SONUC = None
        dm._SORU_MANIFEST_CACHE = None
        dm._SORU_DURUM_KIMLIK = None
        dm._SORU_SAYAC = 0
        dm._SORU_GOZLENEN_KIMLIKLER.clear()

    def test_model_sha_degismisse_eski_isci_yeniden_baslatilir(self):
        yeni_sha = "a" * 64
        proc = _Proc()
        kuyruk = _Kuyruk({
            "id": 1,
            "model_sha256": yeni_sha,
            "bolgeler": [{"sinif": "question_body"}],
        })
        dm._SORU_ISCI = (_Proc(), _Kuyruk(None))
        dm._SORU_ISCI_KIMLIK = "b" * 64
        olduruldu = []

        def oldur():
            olduruldu.append(True)
            dm._SORU_ISCI = None
            dm._SORU_ISCI_KIMLIK = None

        def baslat():
            dm._SORU_ISCI = (proc, kuyruk)
            dm._SORU_ISCI_KIMLIK = yeni_sha

        with mock.patch.object(
                dm,
                "_soru_model_bilgisi",
                return_value={"ok": True, "weights_sha256": yeni_sha},
        ), mock.patch.object(
                dm,
                "_soru_oldur",
                side_effect=oldur,
        ), mock.patch.object(
                dm,
                "_soru_isci_baslat",
                side_effect=baslat,
        ):
            sonuc = dm._soru_istek("/tmp/ornek.png")
        self.assertTrue(olduruldu)
        self.assertEqual(
            [{"sinif": "question_body"}], sonuc["bolgeler"])
        self.assertEqual(yeni_sha, sonuc["model_sha256"])
        self.assertEqual(yeni_sha, dm._SORU_ISCI_KIMLIK)
        self.assertEqual({yeni_sha}, dm._SORU_GOZLENEN_KIMLIKLER)

    def test_isci_yaniti_farkli_sha_tasirsa_fail_closed(self):
        beklenen = "a" * 64
        dm._SORU_ISCI = (
            _Proc(),
            _Kuyruk({
                "id": 1,
                "model_sha256": "b" * 64,
                "bolgeler": [],
            }),
        )
        dm._SORU_ISCI_KIMLIK = beklenen
        with mock.patch.object(
                dm,
                "_soru_model_bilgisi",
                return_value={"ok": True, "weights_sha256": beklenen},
        ):
            self.assertIsNone(dm._soru_istek("/tmp/ornek.png"))
        self.assertTrue(dm._SORU_BOZUK)
        self.assertIsNone(dm._SORU_ISCI)

    def test_pointer_sonradan_degisse_cikti_donmus_kimlikle_etiketlenir(self):
        a = {
            "ok": True,
            "model_id": "model-A",
            "model_version": "A",
            "weights_sha256": "a" * 64,
            "training_dataset_sha256": "1" * 64,
        }
        b = {
            "ok": True,
            "model_id": "model-B",
            "model_version": "B",
            "weights_sha256": "b" * 64,
            "training_dataset_sha256": "2" * 64,
        }
        pointer_degisti = {"deger": False}
        cache_yazilari = []

        def bilgi():
            return b if pointer_degisti["deger"] else a

        def istek(_png):
            pointer_degisti["deger"] = True
            return {
                "bolgeler": [{
                    "sinif": "question_body",
                    "kutu": [0, 0, 50, 50],
                    "guven": .9,
                }],
                "model_bilgisi": dict(a),
                "model_sha256": a["weights_sha256"],
            }

        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(dm, "SORU_MODEL_CACHE_DIZIN", d), \
                mock.patch.object(dm, "soru_modeli_kullanilabilir",
                                  return_value=True), \
                mock.patch.object(dm, "_soru_model_bilgisi",
                                  side_effect=bilgi) as bilgi_mock, \
                mock.patch.object(dm, "_soru_cache_oku",
                                  return_value=None), \
                mock.patch.object(dm, "_soru_cache_yaz",
                                  side_effect=lambda *x: cache_yazilari.append(x)), \
                mock.patch.object(dm, "_soru_istek", side_effect=istek):
            sonuc = dm.soru_bolgeleri_gorsel(
                Image.new("RGB", (100, 100), "white"), "sayfa")

        self.assertEqual(1, bilgi_mock.call_count)
        self.assertEqual("model-A", sonuc[0]["model_id"])
        self.assertEqual("A", sonuc[0]["model_surumu"])
        self.assertEqual("model-A", cache_yazilari[0][2])
        self.assertEqual(
            dm._soru_model_kimlik_bilgiden("sayfa", a),
            cache_yazilari[0][0],
        )

    def test_yeni_model_kimligi_onceki_bozuk_durumu_temizler(self):
        dm._SORU_BOZUK = True
        dm._SORU_PROBE_SONUC = False
        dm._SORU_DURUM_KIMLIK = "b" * 64
        with mock.patch.object(
                dm,
                "_soru_model_bilgisi",
                return_value={"ok": True, "weights_sha256": "a" * 64},
        ), mock.patch.object(
                dm,
                "soru_modeli_aktif_mi",
                return_value=True,
        ), mock.patch.object(dm, "_soru_oldur"):
            self.assertTrue(dm.soru_modeli_kullanilabilir())
        self.assertFalse(dm._SORU_BOZUK)
        self.assertTrue(dm._SORU_PROBE_SONUC)
        self.assertEqual("a" * 64, dm._SORU_DURUM_KIMLIK)


class DonmusSurumYollariTesti(unittest.TestCase):
    def test_active_symlink_bir_kez_cozulur_ve_sonradan_degismez(self):
        with tempfile.TemporaryDirectory() as d:
            a = Path(d) / "a"
            b = Path(d) / "b"
            a.mkdir()
            b.mkdir()
            for dizin, bayt in ((a, b"A"), (b, b"B")):
                (dizin / "model.pt").write_bytes(bayt)
                (dizin / "model.pt.manifest.json").write_text(
                    "{}", encoding="utf-8")
            aktif = Path(d) / "active"
            aktif.symlink_to(a, target_is_directory=True)
            onceki = (
                dm.SORU_MODEL_YOLU,
                dm.SORU_MODEL_MANIFEST_YOLU,
                dm._SORU_MODEL_OTOMATIK_YOLLAR,
            )
            try:
                aktif_model = str(aktif / "model.pt")
                aktif_manifest = aktif_model + ".manifest.json"
                dm.SORU_MODEL_YOLU = aktif_model
                dm.SORU_MODEL_MANIFEST_YOLU = aktif_manifest
                dm._SORU_MODEL_OTOMATIK_YOLLAR = (
                    aktif_model, aktif_manifest)
                with mock.patch.object(
                        dm, "SORU_MODEL_AKTIF_BAGLANTI", str(aktif)):
                    model, manifest = dm.soru_model_yollarini_dondur()
                    aktif.unlink()
                    aktif.symlink_to(b, target_is_directory=True)
                self.assertEqual(b"A", Path(model).read_bytes())
                self.assertEqual(a.resolve(), Path(model).parent)
                self.assertEqual(a.resolve(), Path(manifest).parent)
            finally:
                dm.SORU_MODEL_YOLU = onceki[0]
                dm.SORU_MODEL_MANIFEST_YOLU = onceki[1]
                dm._SORU_MODEL_OTOMATIK_YOLLAR = onceki[2]


if __name__ == "__main__":
    unittest.main()
