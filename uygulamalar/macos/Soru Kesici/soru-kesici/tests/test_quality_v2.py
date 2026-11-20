#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V2 altin veri, rapor ve kalite evaluator regresyonlari."""

import copy
import hashlib
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout

import fitz

import dogrula


KALITE_KLASORU = os.path.join(os.path.dirname(__file__), "quality")
ALTIN_YOLU = os.path.join(KALITE_KLASORU, "synthetic_golden_v1.json")


def _mukemmel_tahmin(altin):
    guvenler = [0.91, 0.70, 0.40, None]
    guven_sira = 0
    belgeler = []
    for belge in altin["documents"]:
        sayfalar = []
        for sayfa in belge["pages"]:
            sorular = []
            for soru in sayfa["questions"]:
                guven = guvenler[guven_sira]
                guven_sira += 1
                sorular.append({
                    "id": f"pred-{soru['id']}",
                    "box": list(soru["box"]),
                    "type": soru["type"],
                    "confidence": guven,
                    "status": dogrula._guven_kovasi(guven),
                    "evidence": ["synthetic"],
                    "warnings": [],
                })
            sayfalar.append({
                "page": sayfa["page"],
                "width": sayfa["width"],
                "height": sayfa["height"],
                "role": sayfa["role"],
                "role_confidence": 1.0,
                "layout_family": "synthetic",
                "questions": sorular,
            })
        belgeler.append({
            "id": belge["id"],
            "source": belge["source"],
            "source_hash": "synthetic",
            "pages": sayfalar,
        })
    return {
        "schema_version": dogrula.TAHMIN_SEMA_SURUMU,
        "generator": {"algorithm_version": "test"},
        "documents": belgeler,
    }


def _tek_soruluk_pdf(yol):
    belge = fitz.open()
    try:
        sayfa = belge.new_page(width=595, height=842)
        satirlar = [
            (90, "1. Asagidakilerden hangisi dogrudur?"),
            (118, "A) Bir"),
            (146, "B) Iki"),
            (174, "C) Uc"),
            (202, "D) Dort"),
            (230, "E) Bes"),
        ]
        for y, metin in satirlar:
            sayfa.insert_text((45, y), metin, fontsize=12)
        belge.save(yol)
    finally:
        belge.close()


def _sha256(yol):
    with open(yol, "rb") as dosya:
        return hashlib.sha256(dosya.read()).hexdigest()


class AltinVeriSozlesmesiTesti(unittest.TestCase):
    def test_surumlendirilmis_sentetik_fixture_yuklenir(self):
        altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)
        self.assertEqual(dogrula.ALTIN_SEMA_SURUMU,
                         altin["schema_version"])
        self.assertEqual("synthetic", altin["dataset"]["kind"])
        self.assertEqual(5, len(altin["documents"][0]["pages"]))

        for ad in ("golden_schema_v1.json", "prediction_schema_v1.json"):
            with open(os.path.join(KALITE_KLASORU, ad), encoding="utf-8") as f:
                sema = json.load(f)
            self.assertEqual("https://json-schema.org/draft/2020-12/schema",
                             sema["$schema"])

    def test_bilinmeyen_surumu_ve_sayfa_disina_tasan_kutuyu_reddeder(self):
        altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)
        bozuk = copy.deepcopy(altin)
        bozuk["schema_version"] = "soru-kesici.golden/v99"
        with self.assertRaisesRegex(ValueError, "schema_version"):
            dogrula._veri_setini_dogrula(bozuk, tahmin=False)

        bozuk = copy.deepcopy(altin)
        bozuk["documents"][0]["pages"][2]["questions"][0]["box"][2] = 1001
        with self.assertRaisesRegex(ValueError, "genisligini asiyor"):
            dogrula._veri_setini_dogrula(bozuk, tahmin=False)


class KaliteEvaluatorTesti(unittest.TestCase):
    def setUp(self):
        self.altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)

    def test_mukemmel_tahminde_tum_ana_metrikler_birdir(self):
        sonuc = dogrula.kalite_degerlendir(
            self.altin, _mukemmel_tahmin(self.altin))
        self.assertEqual(1.0, sonuc["page_role"]["accuracy"])
        self.assertEqual(1.0, sonuc["question_boxes"]["precision"])
        self.assertEqual(1.0, sonuc["question_boxes"]["recall"])
        self.assertEqual(1.0, sonuc["question_boxes"]["mean_matched_iou"])
        self.assertEqual(1.0, sonuc["question_type"]["accuracy"])
        self.assertEqual(0, sonuc["split_merge_proxy"]["split_count"])
        self.assertEqual(0, sonuc["split_merge_proxy"]["merge_count"])
        self.assertEqual(1, sonuc["confidence_buckets"]["otomatik"]["count"])
        self.assertEqual(1, sonuc["confidence_buckets"]["incele"]["count"])
        self.assertEqual(1, sonuc["confidence_buckets"]["reddedildi"]["count"])
        self.assertEqual(1, sonuc["confidence_buckets"]["bilinmiyor"]["count"])

    def test_eslestirme_greedy_tuzaginda_iki_tp_korur(self):
        altin = [
            {"id": "g1", "box": [0, 0, 100, 100]},
            {"id": "g2", "box": [20, 0, 120, 100]},
        ]
        tahmin = [
            {"id": "p1", "box": [10, 0, 110, 100]},
            {"id": "p2", "box": [0, 0, 60, 100]},
        ]
        self.assertEqual(2, len(dogrula._kutu_eslestir(altin, tahmin, 0.5)))

    def test_farkli_koordinat_olcegi_normalize_edilir(self):
        tahmin = _mukemmel_tahmin(self.altin)
        sayfa3 = tahmin["documents"][0]["pages"][2]
        sayfa3["width"] /= 2
        sayfa3["height"] /= 2
        for soru in sayfa3["questions"]:
            soru["box"] = [v / 2 for v in soru["box"]]
        sonuc = dogrula.kalite_degerlendir(self.altin, tahmin)
        self.assertEqual(1.0, sonuc["question_boxes"]["recall"])
        self.assertEqual(1.0, sonuc["question_boxes"]["mean_matched_iou"])

    def test_ignore_region_icindeki_tahmin_skoru_etkilemez(self):
        tahmin = _mukemmel_tahmin(self.altin)
        tahmin["documents"][0]["pages"][1]["questions"].append({
            "id": "ignored-header",
            "box": [100, 110, 200, 200],
            "type": "bilinmiyor",
            "confidence": 0.99,
        })
        sonuc = dogrula.kalite_degerlendir(self.altin, tahmin)
        self.assertEqual(1.0, sonuc["question_boxes"]["precision"])
        self.assertEqual(1, sonuc["false_positives"]["ignored_region_predictions"])

    def test_bolunme_ve_birlesme_proxyleri_ayri_ayri_olculur(self):
        boluk = _mukemmel_tahmin(self.altin)
        sayfa3 = boluk["documents"][0]["pages"][2]
        q1 = sayfa3["questions"][0]
        ust = dict(q1, id="split-a", box=[70, 90, 480, 350])
        alt = dict(q1, id="split-b", box=[70, 350, 480, 610])
        sayfa3["questions"] = [ust, alt, sayfa3["questions"][1]]
        boluk_sonuc = dogrula.kalite_degerlendir(self.altin, boluk)
        self.assertEqual(1, boluk_sonuc["split_merge_proxy"]["split_count"])
        self.assertEqual(0, boluk_sonuc["split_merge_proxy"]["merge_count"])

        birlesik = _mukemmel_tahmin(self.altin)
        sayfa3 = birlesik["documents"][0]["pages"][2]
        sayfa3["questions"] = [{
            "id": "merged-q1-q2",
            "box": [70, 90, 930, 660],
            "type": "karma",
            "confidence": 0.95,
            "status": "otomatik",
            "evidence": ["synthetic-merge"],
            "warnings": ["tam-satir"],
        }]
        birlesik_sonuc = dogrula.kalite_degerlendir(self.altin, birlesik)
        self.assertEqual(0, birlesik_sonuc["split_merge_proxy"]["split_count"])
        self.assertEqual(1, birlesik_sonuc["split_merge_proxy"]["merge_count"])

    def test_konu_sayfasi_yanlis_pozitifi_ve_rol_hatasi_raporlanir(self):
        tahmin = _mukemmel_tahmin(self.altin)
        sayfalar = tahmin["documents"][0]["pages"]
        sayfalar[1]["questions"].append({
            "id": "topic-fp",
            "box": [20, 20, 55, 55],
            "type": "bilinmiyor",
            "confidence": 0.92,
            "status": "otomatik",
            "evidence": ["number-only"],
            "warnings": ["topic-page"],
        })
        sayfalar[4]["role"] = "soru"
        sonuc = dogrula.kalite_degerlendir(self.altin, tahmin)
        self.assertEqual(4 / 5, sonuc["page_role"]["accuracy"])
        self.assertEqual(4 / 5, sonuc["question_boxes"]["precision"])
        self.assertEqual(1, sonuc["false_positives"]["by_gold_page_role"]["konu"])
        self.assertEqual(1, sonuc["false_positives"]["excluded_pages_with_predictions"])
        self.assertAlmostEqual(1 / 3,
                               sonuc["false_positives"]["excluded_page_rate"])
        self.assertEqual(1, sonuc["confidence_buckets"]["otomatik"]["false_positive"])


class RaporVeCliTesti(unittest.TestCase):
    def test_tahmin_raporu_kaynak_pdfyi_degistirmeden_yazilip_okunur(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_quality_") as gecici:
            pdf = os.path.join(gecici, "synthetic-quality.pdf")
            rapor_yolu = os.path.join(gecici, "prediction.json")
            _tek_soruluk_pdf(pdf)
            once = _sha256(pdf)
            rapor = dogrula.tahmin_raporu_olustur(
                pdf, dpi=144, max_sayfa=1,
                belge_kimligi="synthetic:generated-pdf")
            dogrula.rapor_yaz(rapor, rapor_yolu)
            sonra = _sha256(pdf)
            self.assertEqual(once, sonra)
            yuklenen = dogrula.tahmin_raporunu_yukle(rapor_yolu)
            self.assertEqual("synthetic:generated-pdf",
                             yuklenen["documents"][0]["id"])
            self.assertEqual(1, len(yuklenen["documents"][0]["pages"]))

    def test_cli_raporu_kaynak_acmadan_okur_ve_altinla_degerlendirir(self):
        altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)
        with tempfile.TemporaryDirectory(prefix="soru_kesici_cli_") as gecici:
            rapor_yolu = os.path.join(gecici, "prediction.json")
            dogrula.rapor_yaz(_mukemmel_tahmin(altin), rapor_yolu)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                sonuc = dogrula.main([
                    "--rapor-oku", rapor_yolu, "--altin", ALTIN_YOLU])
            self.assertEqual(1.0, sonuc["question_boxes"]["f1"])
            self.assertEqual(dogrula.KALITE_RAPORU_SURUMU,
                             json.loads(stdout.getvalue())["schema_version"])

    def test_cli_metrik_ve_tahmin_raporunu_tek_cagrida_yazar(self):
        with tempfile.TemporaryDirectory(prefix="soru_kesici_cli_write_") as gecici:
            pdf = os.path.join(gecici, "synthetic-cli.pdf")
            rapor_yolu = os.path.join(gecici, "prediction.json")
            _tek_soruluk_pdf(pdf)
            stdout = io.StringIO()
            with redirect_stdout(stdout):
                sonuc = dogrula.main([
                    pdf, "1", "--dpi", "144", "--rapor-yaz", rapor_yolu,
                    "--belge-kimligi", "synthetic:cli-write"])
            self.assertEqual(os.path.abspath(rapor_yolu), sonuc["rapor"])
            self.assertEqual(144, dogrula.tahmin_raporunu_yukle(
                rapor_yolu)["generator"]["dpi"])
            self.assertEqual("synthetic-cli.pdf",
                             json.loads(stdout.getvalue())["dosya"])

    def test_eski_konumsal_cli_sozlesmesi_korunur(self):
        args = dogrula._arguman_ayristir([
            "kitap.pdf", "12", "--kontakt", "kontakt.png",
            "--aralik", "5", "8"])
        self.assertEqual("kitap.pdf", args.yol)
        self.assertEqual(12, args.max_sayfa)
        self.assertEqual([5, 8], args.aralik)
        self.assertEqual("kontakt.png", args.kontakt)


if __name__ == "__main__":
    unittest.main()
