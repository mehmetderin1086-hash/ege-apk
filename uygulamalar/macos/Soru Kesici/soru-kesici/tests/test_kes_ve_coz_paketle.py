#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Kes ve Coz v1 paketleyici sozlesmesi ve guvenlik regresyonlari."""

import io
import json
import os
import tempfile
import types
import unittest
import zipfile
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock

import fitz
from PIL import Image

import kes_ve_coz_paketle as kp


CANLI_BANKA_PDF = Path(
    "/Users/mehmetderin/Library/Application Support/soru-kesici/"
    "ciktilar/Banka Sınav.pdf")


class _Kapi:
    def to_dict(self):
        return {
            "kalite": "balanced", "izin": True,
            "bekleyen_sayfalar": [{"sayfa": 1}],
            "pipeline_hatalari": [], "algoritma_surumu": "3.4",
        }


class _Aday:
    devam_aday = False
    inceleme_durumu = "reddedildi"


class _Analiz:
    adaylar = (_Aday(),)


def _soru(*, review=False):
    return {
        "soru_no": 2 if review else 1,
        "sayfa": 1,
        "kaynak": "ornek.pdf",
        "metin": ("Hangisi dogrudur? A) Alfa B) Beta" if not review
                  else "Belirsiz soru A) Bir B) Iki"),
        "govde": "Belirsiz soru" if review else "Hangisi dogrudur?",
        "siklar": {"A": "Bir", "B": "Iki"} if review else {
            "A": "Alfa", "B": "Beta"},
        "cevap": None if review else "B",
        "algoritma_surumu": "3.4",
        "guven": 0.64 if review else 0.94,
        "inceleme_durumu": "incele" if review else "otomatik",
        "tespit_uyarilari": ["duzen_belirsiz"] if review else [],
        "inceleme_gerekcesi": ["guven_dusuk"] if review else [],
    }


def _cekirdek_yamalari(*, bozuk_gorsel=None):
    otomatik_gorsel = bozuk_gorsel or Image.new("RGB", (40, 30), "white")
    inceleme_gorsel = Image.new("RGB", (32, 24), "gray")

    def plan(*_args, **kwargs):
        if kwargs["kova"] == "incele":
            return [[(0, (20.0, 430.0, 510.0, 710.0))]], [{}], []
        return [[(0, (10.0, 80.0, 520.0, 360.0))]], [{}], []

    def kes(*_args, **kwargs):
        if kwargs["kova"] == "incele":
            return [inceleme_gorsel], [_soru(review=True)], []
        return [otomatik_gorsel], [_soru()], []

    return (
        mock.patch.object(kp.sk, "belge_hazirla",
                          return_value=([object()], [object()], "karisik", [])),
        mock.patch.object(kp.sk, "kalite_kapisi",
                          return_value=(_Kapi(), None, [_Analiz()])),
        mock.patch.object(kp.sk, "cevap_anahtari_bul",
                          return_value={"cevap": "B"}),
        mock.patch.object(kp.sk, "kirpma_plani_meta", side_effect=plan),
        mock.patch.object(kp.sk, "kirpma_seti", side_effect=kes),
        mock.patch.object(kp.sk, "belge_kapat"),
        mock.patch.object(kp.sk, "cozumleri_ilistir"),
    )


class KesVeCozPaketSozlesmesiTesti(unittest.TestCase):
    def test_manifest_iki_kovayi_ve_cevap_izolasyonunu_tasir(self):
        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_v1_") as dizin:
            girdi = Path(dizin) / "ornek.pdf"
            cikti = Path(dizin) / "paket.zip"
            _sentetik_pdf(girdi)
            olaylar = []
            yamalar = _cekirdek_yamalari()
            with yamalar[0] as hazirla, yamalar[1], yamalar[2], \
                    yamalar[3] as plan, yamalar[4] as kes, \
                    yamalar[5] as kapat, yamalar[6] as cozum_ilistir:
                ozet = kp.paketle(
                    str(girdi), str(cikti), dpi=144, emit=olaylar.append)

            self.assertEqual(2, ozet["questions"])
            self.assertEqual(1, ozet["automatic"])
            self.assertEqual(1, ozet["review"])
            hazirla.assert_called_once_with([str(girdi)], 144)
            kapat.assert_called_once()
            cozum_ilistir.assert_not_called()
            self.assertEqual(["cikti", "incele"],
                             [c.kwargs["kova"] for c in plan.call_args_list])
            self.assertEqual(["cikti", "incele"],
                             [c.kwargs["kova"] for c in kes.call_args_list])
            self.assertTrue(all(c.kwargs["cevap_disla"]
                                for c in plan.call_args_list))
            self.assertTrue(all(c.kwargs["cevap_disla"]
                                for c in kes.call_args_list))
            self.assertTrue(all(c.kwargs["cevap_bandi"] is False
                                for c in kes.call_args_list))

            with zipfile.ZipFile(cikti) as arsiv:
                adlar = set(arsiv.namelist())
                manifest = json.loads(arsiv.read("manifest.json"))
                self.assertEqual(kp.SCHEMA, manifest["schema_version"])
                self.assertEqual("Soru Kesici", manifest["source_app"])
                self.assertEqual("3.4", manifest["source_version"])
                self.assertFalse(
                    manifest["answer_policy"]["solution_images_included"])
                self.assertFalse(
                    manifest["answer_policy"]["answer_pages_included"])
                self.assertEqual(
                    ["reference_answer"],
                    manifest["answer_policy"]["withheld_from_model"])
                self.assertEqual(2, len(manifest["questions"]))
                self.assertEqual(1, manifest["quality"]["automatic_count"])
                self.assertEqual(1, manifest["quality"]["review_count"])
                self.assertEqual(
                    1, manifest["quality"]["rejected_candidate_count"])

                zorunlu = {
                    "external_id", "text", "choices", "image",
                    "source_document", "source_page", "source_box",
                    "cutter_version", "confidence", "quality_status",
                    "review_required", "warnings", "reference_answer",
                }
                otomatik, inceleme = manifest["questions"]
                self.assertTrue(zorunlu.issubset(otomatik))
                self.assertTrue(zorunlu.issubset(inceleme))
                self.assertEqual("B", otomatik["reference_answer"])
                self.assertFalse(otomatik["review_required"])
                self.assertEqual("automatic", otomatik["quality_status"])
                self.assertEqual(
                    [10.0, 80.0, 520.0, 360.0], otomatik["source_box"])
                self.assertTrue(inceleme["review_required"])
                self.assertEqual("review", inceleme["quality_status"])
                self.assertIn("duzen_belirsiz", inceleme["warnings"])
                self.assertIn("guven_dusuk", inceleme["warnings"])
                self.assertEqual(
                    {"manifest.json", otomatik["image"], inceleme["image"]},
                    adlar)
                self.assertTrue(arsiv.read(otomatik["image"]).startswith(
                    b"\x89PNG\r\n\x1a\n"))
                self.assertFalse(any("cozum" in ad.lower() for ad in adlar))
            self.assertEqual("completed", olaylar[-1]["event"])

    def test_hata_eski_ciktiyi_korur_ve_gecici_dosya_birakmaz(self):
        class _BozukGorsel:
            def save(self, *_args, **_kwargs):
                raise RuntimeError("png kodlama hatasi")

        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_atomik_") as dizin:
            girdi = Path(dizin) / "ornek.pdf"
            cikti = Path(dizin) / "paket.zip"
            _sentetik_pdf(girdi)
            cikti.write_bytes(b"ONCEKI-SAGLAM-PAKET")
            yamalar = _cekirdek_yamalari(bozuk_gorsel=_BozukGorsel())
            with yamalar[0], yamalar[1], yamalar[2], yamalar[3], \
                    yamalar[4], yamalar[5], yamalar[6]:
                with self.assertRaisesRegex(RuntimeError, "png kodlama"):
                    kp.paketle(str(girdi), str(cikti))
            self.assertEqual(b"ONCEKI-SAGLAM-PAKET", cikti.read_bytes())
            self.assertEqual([], list(Path(dizin).glob(".paket.zip.*.tmp")))

    def test_girdi_boyut_siniri_cekirdegi_baslatmadan_durdurur(self):
        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_limit_") as dizin:
            girdi = Path(dizin) / "buyuk.pdf"
            cikti = Path(dizin) / "paket.zip"
            with girdi.open("wb") as dosya:
                dosya.seek(1024 * 1024)
                dosya.write(b"x")
            with mock.patch.object(kp.sk, "belge_hazirla") as hazirla:
                with self.assertRaisesRegex(
                        kp.PaketlemeHatasi, "girdi boyutu siniri"):
                    kp.paketle(str(girdi), str(cikti), max_input_mb=1)
            hazirla.assert_not_called()
            self.assertFalse(cikti.exists())

    def test_pdf_sayfa_siniri_cekirdegi_baslatmadan_durdurur(self):
        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_page_limit_") \
                as dizin:
            girdi = Path(dizin) / "iki_sayfa.pdf"
            cikti = Path(dizin) / "paket.zip"
            belge = fitz.open()
            try:
                belge.new_page()
                belge.new_page()
                belge.save(str(girdi))
            finally:
                belge.close()
            with mock.patch.object(kp.sk, "belge_hazirla") as hazirla:
                with self.assertRaisesRegex(
                        kp.PaketlemeHatasi, "sayfa sayisi siniri"):
                    kp.paketle(str(girdi), str(cikti), max_pages=1)
            hazirla.assert_not_called()
            self.assertFalse(cikti.exists())

    def test_cli_hatasi_json_satiri_ve_basarisiz_kod_dondurur(self):
        hata = io.StringIO()
        with mock.patch.object(
                kp, "paketle", side_effect=kp.PaketlemeHatasi("beklenen")), \
                redirect_stderr(hata):
            kod = kp.main(["yok.pdf", "--output", "sonuc.zip"])
        self.assertEqual(1, kod)
        self.assertEqual(
            {"event": "error", "error": "beklenen"},
            json.loads(hata.getvalue()))

    def test_yuksek_kanitli_gomulu_soru_review_kurtarilir_ust_yonerge_atlanir(
            self):
        kanit = ("soru_numarasi", "uygun_geometri",
                 "gomulu_soru_gorseli")
        ust_yonerge = types.SimpleNamespace(
            devam_aday=False, inceleme_durumu="reddedildi",
            kanitlar=kanit, kalibre_guven=0.92, guven=0.35,
            numara=1, kutu=(10.0, 20.0, 510.0, 140.0),
            sayfa_rolu="konu", test_no=None,
            uyarilar=("soru_modeli_sinir_uyusmazligi",
                      "konu_sayfasinda_aday"))
        gercek_soru = types.SimpleNamespace(
            devam_aday=False, inceleme_durumu="reddedildi",
            kanitlar=kanit, kalibre_guven=0.88, guven=0.35,
            numara=2, kutu=(10.0, 160.0, 260.0, 600.0),
            sayfa_rolu="konu", test_no=None,
            uyarilar=("konu_sayfasinda_aday",))
        analiz = types.SimpleNamespace(
            sayfa_rolu="konu", adaylar=(ust_yonerge, gercek_soru))

        class _Sayfa:
            def kirp(self, _kutu):
                return Image.new("RGB", (500, 800), "white")

        ocr = {
            "metin": ("Hangileri doğrudur? B) İkinci C) Üçüncü "
                      "A) Birinci E) Beşinci D) Dördüncü")}
        olaylar = []
        with mock.patch.object(
                kp.sk, "_belge_sayfa_rolleri", return_value=(set(), None)), \
                mock.patch.object(kp.sk, "soru_metni_ocr",
                                  return_value=ocr) as ocr_cagrisi:
            gorseller, sorular, planlar, uyarilar, adet = \
                kp._ham_review_kurtar(
                    [_Sayfa()], "karisik", [analiz], Path("sinav.pdf"),
                    [], olaylar.append)

        self.assertEqual(1, adet)
        self.assertEqual(1, len(gorseller))
        self.assertEqual([], uyarilar)
        self.assertEqual([(0, gercek_soru.kutu)], planlar[0])
        self.assertEqual("Hangileri doğrudur?", sorular[0]["govde"])
        self.assertEqual({
            "A": "Birinci", "B": "İkinci", "C": "Üçüncü",
            "D": "Dördüncü", "E": "Beşinci"}, sorular[0]["siklar"])
        self.assertIn(
            "raw_rejected_candidate_recovered_for_review",
            sorular[0]["inceleme_gerekcesi"])
        ocr_cagrisi.assert_called_once()
        self.assertEqual(
            [(1, "skipped", 1), (2, "recovered", 1)],
            [(o["question_number"], o["status"], o["page"])
             for o in olaylar])

    def test_ham_kurtarma_cozum_ve_cevap_sayfasini_asla_almaz(self):
        aday = types.SimpleNamespace(
            devam_aday=False, inceleme_durumu="reddedildi",
            kanitlar=("soru_numarasi", "uygun_geometri",
                      "gomulu_soru_gorseli"),
            kalibre_guven=0.95, guven=0.35, numara=4,
            kutu=(10.0, 20.0, 510.0, 700.0), sayfa_rolu="çözüm",
            test_no=None, uyarilar=())
        analiz = types.SimpleNamespace(
            sayfa_rolu="çözüm", adaylar=(aday,))
        olaylar = []
        with mock.patch.object(
                kp.sk, "_belge_sayfa_rolleri", return_value=({0}, None)), \
                mock.patch.object(kp.sk, "soru_metni_ocr") as ocr:
            sonuc = kp._ham_review_kurtar(
                [object()], "cozumlu", [analiz], Path("cozum.pdf"), [],
                olaylar.append)
        self.assertEqual(([], [], [], [], 0), sonuc)
        ocr.assert_not_called()
        self.assertEqual("guvensiz_sayfa_rolu", olaylar[0]["reason"])


def _sentetik_pdf(yol):
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=595, height=842)
        sayfa.insert_text((38, 32), "USTBILGI", fontsize=11)
        satirlar = [
            (100, "1. Asagidakilerden hangisi birinci sorudur?"),
            (126, "A) Alfa"), (150, "B) Beta"), (174, "C) Gamma"),
            (198, "D) Delta"), (222, "E) Epsilon"),
            (430, "2. Asagidakilerden hangisi ikinci sorudur?"),
            (456, "A) Bir"), (480, "B) Iki"), (504, "C) Uc"),
            (528, "D) Dort"), (552, "E) Bes"),
        ]
        for y, metin in satirlar:
            sayfa.insert_text((42, y), metin, fontsize=12)
        anahtar = belge.new_page(width=595, height=842)
        anahtar.insert_text((42, 70), "CEVAP ANAHTARI", fontsize=16)
        anahtar.insert_text(
            (42, 110),
            "1-B   2-A   3-C   4-D   5-E   6-A   7-B   8-C",
            fontsize=12)
        belge.save(str(yol))
    finally:
        belge.close()


class GercekCekirdekPaketlemeTesti(unittest.TestCase):
    def test_metin_pdf_gercek_cekirdekle_paketlenir(self):
        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_gercek_") as dizin:
            girdi = Path(dizin) / "iki_soru.pdf"
            cikti = Path(dizin) / "iki_soru.zip"
            _sentetik_pdf(girdi)
            with mock.patch.object(kp.sk, "duzen_model", None), \
                    mock.patch.object(kp.sk, "PROFIL_CACHE_DIZIN", dizin):
                ozet = kp.paketle(str(girdi), str(cikti), dpi=144)
            self.assertEqual(2, ozet["questions"])
            with zipfile.ZipFile(cikti) as arsiv:
                manifest = json.loads(arsiv.read("manifest.json"))
                self.assertEqual(kp.SCHEMA, manifest["schema_version"])
                self.assertEqual(2, len(manifest["questions"]))
                self.assertEqual(
                    {"A", "B"},
                    {soru["reference_answer"]
                     for soru in manifest["questions"]})
                for soru in manifest["questions"]:
                    self.assertIn(soru["image"], arsiv.namelist())
                    self.assertEqual("iki_soru.pdf", soru["source_document"])
                    self.assertEqual(1, soru["source_page"])
                    self.assertEqual(4, len(soru["source_box"]))
                    self.assertNotIn("CEVAP ANAHTARI", soru["text"])

    @unittest.skipUnless(CANLI_BANKA_PDF.is_file(),
                         "canli Banka Sinav PDF'i bu makinede yok")
    def test_canli_banka_sinavinda_iki_soru_review_kovasina_kurtarilir(self):
        with tempfile.TemporaryDirectory(prefix="kes_ve_coz_canli_banka_") \
                as dizin:
            cikti = Path(dizin) / "banka.zip"
            cache = Path(dizin) / "profil-cache"
            with mock.patch.object(kp.sk, "PROFIL_CACHE_DIZIN", str(cache)):
                ozet = kp.paketle(
                    str(CANLI_BANKA_PDF), str(cikti), dpi=300)
            self.assertEqual(2, ozet["questions"])
            self.assertEqual(0, ozet["automatic"])
            self.assertEqual(2, ozet["review"])
            with zipfile.ZipFile(cikti) as arsiv:
                manifest = json.loads(arsiv.read("manifest.json"))
                kalite = manifest["quality"]
                self.assertEqual(2, kalite["recovered_to_review_count"])
                self.assertEqual(
                    1, kalite["unrecovered_rejected_candidate_count"])
                self.assertEqual(2, len(manifest["questions"]))
                self.assertEqual(
                    {"manifest.json"}
                    | {soru["image"] for soru in manifest["questions"]},
                    set(arsiv.namelist()))
                birlesik = " ".join(
                    soru["text"] for soru in manifest["questions"])
                self.assertNotIn("Soru kitapçığı", birlesik)
                self.assertIn("göl ekosisteminde", birlesik)
                self.assertIn("soyağacında", birlesik)
                for soru in manifest["questions"]:
                    self.assertTrue(soru["review_required"])
                    self.assertEqual("review", soru["quality_status"])
                    self.assertEqual(set("ABCDE"), set(soru["choices"]))
                    self.assertIsNone(soru["reference_answer"])
                    self.assertTrue(arsiv.read(soru["image"]).startswith(
                        b"\x89PNG\r\n\x1a\n"))


if __name__ == "__main__":
    unittest.main()
