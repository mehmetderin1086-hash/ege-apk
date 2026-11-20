#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import subprocess
import tempfile
import unittest
from unittest import mock

import duzen_model as dm
import kalite_kosusu as kk


class _SahteProc:
    def poll(self):
        return None


def _korpus(ad="ornek", kaynak_sha=None):
    return [{
        "ad": ad,
        "kaynak_sha256": kaynak_sha or "1" * 64,
        "kaynak_boyut": 4,
        "meta_sha256": "2" * 64,
        "altin_sha256": "3" * 64,
        "sayim_altin_sha256": "4" * 64,
        "anlik_sha256": "5" * 64,
        "kapi_esikleri_sha256": "6" * 64,
    }]


def _gecerli_meta(*, ad="ornek", kapsam=None, sert=False, regresyon=False):
    korpus = _korpus(ad)
    return {
        "kapali": {
            "regresyon": False,
            "sert": sert,
            "sari_bulgu": False,
            "model": None,
            "soru_model_istek_sayisi": 0,
            "soru_model_isci_canli": False,
            "soru_model_isci_sha256": None,
            "soru_model_gozlenen_sha256": [],
            "korpus_kimlikleri": korpus,
            "kapsam": kapsam,
        },
        "acik": {
            "regresyon": regresyon,
            "sert": sert,
            "sari_bulgu": False,
            "model": {
                "ok": True,
                "weights_sha256": "a" * 64,
            },
            "soru_model_istek_sayisi": 1,
            "soru_model_isci_canli": True,
            "soru_model_isci_sha256": "a" * 64,
            "soru_model_gozlenen_sha256": ["a" * 64],
            "korpus_kimlikleri": korpus,
            "kapsam": kapsam,
        },
    }


class IkiliAltSurecTesti(unittest.TestCase):
    def tearDown(self):
        dm._SORU_ISCI = None
        dm._SORU_BOZUK = False
        dm._SORU_PROBE_SONUC = None
        dm._SORU_MANIFEST_CACHE = None
        dm._SORU_SAYAC = 0
        dm._SORU_ISCI_KIMLIK = None
        dm._SORU_GOZLENEN_KIMLIKLER.clear()
        dm.SORU_MODEL_AKTIF_ZORLA = None

    def test_acik_kol_gercek_isci_istegi_yoksa_reddedilir(self):
        with tempfile.TemporaryDirectory() as gecici:
            cikti = os.path.join(gecici, "kol.json")
            with mock.patch.object(
                    dm,
                    "soru_modeli_dogrula",
                    return_value={
                        "ok": True,
                        "model_id": "m",
                        "weights_sha256": "a" * 64,
                    },
            ), mock.patch.object(
                    dm,
                    "soru_model_yollarini_dondur",
                    return_value=(
                        dm.SORU_MODEL_YOLU,
                        dm.SORU_MODEL_MANIFEST_YOLU,
                    ),
            ), mock.patch.object(
                    kk,
                    "kosu",
                    return_value=([{"ad": "ornek"}], False),
            ), mock.patch.object(
                    kk,
                    "_korpus_kimlikleri",
                    return_value=_korpus(),
            ), mock.patch.object(
                    dm,
                    "_soru_oldur",
            ), mock.patch.object(dm, "kapat"):
                dm._SORU_ISCI = None
                with self.assertRaisesRegex(
                        RuntimeError, "gerçekten kullanmadı"):
                    kk._ikili_kol_calistir("acik", ["ornek"], cikti)
            self.assertFalse(os.path.exists(cikti))

    def test_acik_kol_probe_istek_ve_canli_isciyi_kayda_alir(self):
        def sahte_kosu(_secili, altin=False, kapsam=None):
            self.assertTrue(altin)
            self.assertEqual("C", kapsam)
            dm._SORU_SAYAC = 3
            dm._SORU_ISCI = (_SahteProc(), object())
            dm._SORU_ISCI_KIMLIK = "a" * 64
            dm._SORU_GOZLENEN_KIMLIKLER.add("a" * 64)
            return ([{
                "ad": "ornek",
                "durum": "ok",
                "f1": 0.9,
                "count_recall_auto": 0.8,
                "page_exact_rate": 0.7,
            }], False)

        with tempfile.TemporaryDirectory() as gecici:
            cikti = os.path.join(gecici, "kol.json")
            with mock.patch.object(
                    dm,
                    "soru_modeli_dogrula",
                    return_value={
                        "ok": True,
                        "model_id": "m",
                        "weights_sha256": "a" * 64,
                    },
            ), mock.patch.object(
                    dm,
                    "soru_model_yollarini_dondur",
                    return_value=(
                        dm.SORU_MODEL_YOLU,
                        dm.SORU_MODEL_MANIFEST_YOLU,
                    ),
            ), mock.patch.object(
                    kk,
                    "kosu",
                    side_effect=sahte_kosu,
            ), mock.patch.object(
                    kk,
                    "_korpus_kimlikleri",
                    return_value=_korpus(),
            ), mock.patch.object(
                    dm,
                    "_soru_oldur",
            ), mock.patch.object(dm, "kapat"):
                sonuc = kk._ikili_kol_calistir(
                    "acik", ["ornek"], cikti, kapsam="C")
            self.assertEqual(3, sonuc["soru_model_istek_sayisi"])
            self.assertTrue(sonuc["soru_model_isci_canli"])
            self.assertEqual("a" * 64, sonuc["soru_model_isci_sha256"])
            self.assertEqual(
                ["a" * 64], sonuc["soru_model_gozlenen_sha256"])
            with open(cikti, encoding="utf-8") as f:
                self.assertEqual("m", json.load(f)["model"]["model_id"])

    def test_acik_kol_baslangic_sha_disinda_isciyi_reddeder(self):
        def sahte_kosu(_secili, altin=False, kapsam=None):
            dm._SORU_SAYAC = 2
            dm._SORU_ISCI = (_SahteProc(), object())
            dm._SORU_ISCI_KIMLIK = "b" * 64
            dm._SORU_GOZLENEN_KIMLIKLER.update(
                {"a" * 64, "b" * 64})
            return ([{"ad": "ornek"}], False)

        with tempfile.TemporaryDirectory() as gecici:
            with mock.patch.object(
                    dm, "soru_model_yollarini_dondur",
                    return_value=(
                        dm.SORU_MODEL_YOLU,
                        dm.SORU_MODEL_MANIFEST_YOLU,
                    )), mock.patch.object(
                    dm, "soru_modeli_dogrula",
                    return_value={
                        "ok": True,
                        "model_id": "A",
                        "weights_sha256": "a" * 64,
                    }), mock.patch.object(
                    kk, "kosu", side_effect=sahte_kosu), \
                    mock.patch.object(
                        kk, "_korpus_kimlikleri",
                        return_value=_korpus()), \
                    mock.patch.object(dm, "_soru_oldur"), \
                    mock.patch.object(dm, "kapat"):
                with self.assertRaisesRegex(
                        RuntimeError, "gözlenen_sha"):
                    kk._ikili_kol_calistir(
                        "acik", ["ornek"],
                        os.path.join(gecici, "kol.json"))

    def test_C_kapsaminda_sari_bulgu_mutlak_regresyondur(self):
        satirlar = [{
            "ad": "ornek",
            "durum": "dikkat",
            "bulgular": [{
                "kod": "sinirda",
                "seviye": "sari",
                "detay": "yayında kabul edilmez",
            }],
        }]
        with tempfile.TemporaryDirectory() as gecici, \
                mock.patch.object(
                    kk, "_korpus_kimlikleri", return_value=_korpus()), \
                mock.patch.object(
                    kk, "kosu", return_value=(satirlar, False)), \
                mock.patch.object(dm, "_soru_oldur"), \
                mock.patch.object(dm, "kapat"):
            sonuc = kk._ikili_kol_calistir(
                "kapali",
                ["ornek"],
                os.path.join(gecici, "kol.json"),
                kapsam="C",
            )
        self.assertTrue(sonuc["sert"])
        self.assertTrue(sonuc["sari_bulgu"])
        self.assertTrue(sonuc["regresyon"])

    def test_kol_sirasinda_ayni_adli_kaynak_degistirilirse_reddedilir(self):
        once = _korpus(kaynak_sha="1" * 64)
        sonra = _korpus(kaynak_sha="7" * 64)
        with tempfile.TemporaryDirectory() as gecici, \
                mock.patch.object(
                    kk, "_korpus_kimlikleri", side_effect=(once, sonra)), \
                mock.patch.object(
                    kk, "kosu",
                    return_value=([{"ad": "ornek", "durum": "ok"}], False)), \
                mock.patch.object(dm, "_soru_oldur"), \
                mock.patch.object(dm, "kapat"):
            with self.assertRaisesRegex(
                    RuntimeError, "korpus koşu sırasında değişti"):
                kk._ikili_kol_calistir(
                    "kapali",
                    ["ornek"],
                    os.path.join(gecici, "kol.json"),
                )

    def test_iki_kol_ayri_env_ile_alt_surecte_kosar(self):
        cagrilar = []

        def sahte_run(komut, **kwargs):
            durum = komut[komut.index("--ikili-kol") + 1]
            cikti = komut[komut.index("--ikili-cikti") + 1]
            cagrilar.append((
                durum,
                kwargs["env"]["SORU_KESICI_SORU_MODELI"],
                tuple(komut),
            ))
            satir = {
                "ad": "ornek",
                "durum": "ok",
                "anomali": 0,
                "f1": 0.9,
                "count_recall_auto": 0.8,
                "page_exact_rate": 0.7,
            }
            veri = {
                "durum": durum,
                "regresyon": False,
                "sert": "--sert" in komut,
                "sari_bulgu": False,
                "model": (
                    {
                        "ok": True,
                        "model_id": "m",
                        "weights_sha256": "a" * 64,
                    }
                    if durum == "acik" else None
                ),
                "soru_model_istek_sayisi": 2 if durum == "acik" else 0,
                "soru_model_isci_canli": durum == "acik",
                "soru_model_isci_sha256":
                    "a" * 64 if durum == "acik" else None,
                "soru_model_gozlenen_sha256":
                    ["a" * 64] if durum == "acik" else [],
                "kapsam": (
                    komut[komut.index("--kapsam") + 1]
                    if "--kapsam" in komut else None
                ),
                "korpus_kimlikleri": _korpus(),
                "satirlar": [satir],
            }
            with open(cikti, "w", encoding="utf-8") as f:
                json.dump(veri, f)
            return subprocess.CompletedProcess(komut, 0, "", "")

        with mock.patch.object(
                kk, "_korpus_kimlikleri", return_value=_korpus()), \
                mock.patch.object(
                    kk.subprocess, "run", side_effect=sahte_run):
            sonuc = kk._ikili_kosu(["ornek"], kapsam="C")
        self.assertEqual(
            [("kapali", "0"), ("acik", "1")],
            [(durum, env) for durum, env, _ in cagrilar],
        )
        self.assertTrue(all(
            "--sadece" in komut for _, _, komut in cagrilar))
        self.assertTrue(all(
            komut[komut.index("--kapsam") + 1] == "C"
            for _, _, komut in cagrilar))
        self.assertTrue(all(
            "--sert" in komut for _, _, komut in cagrilar))
        self.assertEqual("C", sonuc["_meta"]["kollar"]["kapali"]["kapsam"])
        self.assertEqual("C", sonuc["_meta"]["kollar"]["acik"]["kapsam"])
        self.assertTrue(sonuc["_meta"]["ok"])
        self.assertIn("count_recall_auto", sonuc["acik"]["ornek"])
        self.assertIn("page_exact_rate", sonuc["acik"]["ornek"])

    def test_iki_kol_arasinda_korpus_degistirilirse_devam_etmez(self):
        once = _korpus(kaynak_sha="1" * 64)
        sonra = _korpus(kaynak_sha="7" * 64)
        cagrilar = []

        def sahte_run(komut, **_kwargs):
            cagrilar.append(komut)
            cikti = komut[komut.index("--ikili-cikti") + 1]
            with open(cikti, "w", encoding="utf-8") as f:
                json.dump({"korpus_kimlikleri": once}, f)
            return subprocess.CompletedProcess(komut, 0, "", "")

        with mock.patch.object(
                kk, "_korpus_kimlikleri", side_effect=(once, sonra)), \
                mock.patch.object(
                    kk.subprocess, "run", side_effect=sahte_run):
            with self.assertRaisesRegex(
                    RuntimeError, "korpus süreçler arasında değişti"):
                kk._ikili_kosu(["ornek"])
        self.assertEqual(1, len(cagrilar))


class KorpusKimligiTesti(unittest.TestCase):
    def test_ayni_dosya_adi_degisen_bayt_altin_ve_metadata_ile_baglanir(self):
        with tempfile.TemporaryDirectory() as gecici:
            kaynak = os.path.join(gecici, "kitap.pdf")
            altin = os.path.join(gecici, "altin.json")
            anlik = os.path.join(gecici, "anlik.json")
            koleksiyon = os.path.join(gecici, "koleksiyon.json")
            oge = {
                "ad": "kitap",
                "yol": kaynak,
                "altin": altin,
                "anlik": anlik,
                "dpi": 300,
            }

            def yaz(yol, veri, ikili=False):
                kip = "wb" if ikili else "w"
                kwargs = {} if ikili else {"encoding": "utf-8"}
                with open(yol, kip, **kwargs) as f:
                    if ikili:
                        f.write(veri)
                    else:
                        json.dump(veri, f)

            yaz(kaynak, b"AAAA", ikili=True)
            yaz(altin, {"kutu": 1})
            yaz(anlik, {"anomali_sayisi": 0})
            yaz(koleksiyon, [oge])
            ilk = kk._korpus_kimlikleri(
                ["kitap"], koleksiyon_yolu=koleksiyon)

            yaz(kaynak, b"BBBB", ikili=True)
            kaynak_degisti = kk._korpus_kimlikleri(
                ["kitap"], koleksiyon_yolu=koleksiyon)
            self.assertEqual("kitap", ilk[0]["ad"])
            self.assertNotEqual(
                ilk[0]["kaynak_sha256"],
                kaynak_degisti[0]["kaynak_sha256"],
            )

            yaz(altin, {"kutu": 2})
            altin_degisti = kk._korpus_kimlikleri(
                ["kitap"], koleksiyon_yolu=koleksiyon)
            self.assertNotEqual(
                kaynak_degisti[0]["altin_sha256"],
                altin_degisti[0]["altin_sha256"],
            )

            oge["dpi"] = 200
            yaz(koleksiyon, [oge])
            meta_degisti = kk._korpus_kimlikleri(
                ["kitap"], koleksiyon_yolu=koleksiyon)
            self.assertNotEqual(
                altin_degisti[0]["meta_sha256"],
                meta_degisti[0]["meta_sha256"],
            )


class IkiliKaliteKapisiTesti(unittest.TestCase):
    def test_count_recall_auto_ve_page_exact_gerilemesi_kirmizidir(self):
        tablo = {
            "kapali": {
                "ornek": {
                    "durum": "ok",
                    "anomali": 0,
                    "count_recall_auto": 0.9,
                    "page_exact_rate": 0.8,
                },
            },
            "acik": {
                "ornek": {
                    "durum": "ok",
                    "anomali": 0,
                    "count_recall_auto": 0.7,
                    "page_exact_rate": 0.6,
                },
            },
        }
        meta = _gecerli_meta()
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("count_recall_auto-gerilemesi", kodlar)
        self.assertIn("page_exact_rate-gerilemesi", kodlar)

    def test_model_kullanimi_kanitlanamazsa_fail_closed(self):
        tablo = {
            "kapali": {"x": {"f1": 0.8}},
            "acik": {"x": {"f1": 0.8}},
        }
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, {})}
        self.assertIn("acik-kol-model-kaniti-yok", kodlar)

    def test_acik_kol_mutlak_regresyonu_esit_kollarda_da_reddedilir(self):
        tablo = {
            "kapali": {"x": {"durum": "REGRESYON", "f1": 0.8}},
            "acik": {"x": {"durum": "REGRESYON", "f1": 0.8}},
        }
        meta = _gecerli_meta(ad="x", regresyon=True)
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("acik-kol-mutlak-regresyon", kodlar)

    def test_iki_kolun_belge_kumesi_birebir_ayni_olmali(self):
        tablo = {
            "kapali": {"x": {"f1": 0.8}, "y": {"f1": 0.8}},
            "acik": {"x": {"f1": 0.8}},
        }
        meta = _gecerli_meta(ad="x")
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("belge-kumesi-uyusmaz", kodlar)

    def test_acik_regresyon_kaniti_yoksa_veya_bool_degilse_fail_closed(self):
        tablo = {
            "kapali": {"ornek": {"f1": 0.8}},
            "acik": {"ornek": {"f1": 0.8}},
        }
        degerler = (None, 0, "false", [], {})
        for deger in degerler:
            with self.subTest(deger=deger):
                meta = _gecerli_meta()
                meta["acik"]["regresyon"] = deger
                kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
                self.assertIn(
                    "acik-kol-regresyon-kaniti-gecersiz", kodlar)
        meta = _gecerli_meta()
        del meta["acik"]["regresyon"]
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("acik-kol-regresyon-kaniti-gecersiz", kodlar)

    def test_model_istek_sayaci_bool_ile_taklit_edilemez(self):
        tablo = {
            "kapali": {"ornek": {"f1": 0.8}},
            "acik": {"ornek": {"f1": 0.8}},
        }
        meta = _gecerli_meta()
        meta["acik"]["soru_model_istek_sayisi"] = True
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("acik-kol-model-kaniti-yok", kodlar)

    def test_ayni_mantiksal_ad_farkli_kaynak_sha_ile_karsilastirilamaz(self):
        tablo = {
            "kapali": {"ornek": {"f1": 0.8}},
            "acik": {"ornek": {"f1": 0.8}},
        }
        meta = _gecerli_meta()
        meta = json.loads(json.dumps(meta))
        meta["acik"]["korpus_kimlikleri"][0]["kaynak_sha256"] = "7" * 64
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn("korpus-kimligi-uyusmaz", kodlar)

    def test_ayni_kaynak_farkli_altin_veya_metadata_ile_karsilastirilamaz(self):
        tablo = {
            "kapali": {"ornek": {"f1": 0.8}},
            "acik": {"ornek": {"f1": 0.8}},
        }
        for alan in ("altin_sha256", "meta_sha256"):
            with self.subTest(alan=alan):
                meta = json.loads(json.dumps(_gecerli_meta()))
                meta["acik"]["korpus_kimlikleri"][0][alan] = "7" * 64
                kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
                self.assertIn("korpus-kimligi-uyusmaz", kodlar)

    def test_C_kolunda_sari_bulgu_regresyon_olmadiysa_kanit_tutarsizdir(self):
        tablo = {
            "kapali": {"ornek": {"f1": 0.8}},
            "acik": {"ornek": {"f1": 0.8}},
        }
        meta = _gecerli_meta(kapsam="C", sert=True)
        meta["acik"]["sari_bulgu"] = True
        kodlar = {b["kod"] for b in kk._ikili_kapi(tablo, meta)}
        self.assertIn(
            "acik-kol-sert-regresyon-kaniti-tutarsiz", kodlar)


if __name__ == "__main__":
    unittest.main()
