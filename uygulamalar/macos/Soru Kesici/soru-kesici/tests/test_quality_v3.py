#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3 nihai-cikti kalite semasi ve evaluator regresyonlari."""

import copy
import json
import os
import tempfile
import unittest

import dogrula
import soru_kes as sk
from tests.test_quality_v2 import _mukemmel_tahmin, _tek_soruluk_pdf


KALITE_KLASORU = os.path.join(os.path.dirname(__file__), "quality")
ALTIN_YOLU = os.path.join(KALITE_KLASORU, "synthetic_golden_v2.json")
V1_ALTIN_YOLU = os.path.join(KALITE_KLASORU, "synthetic_golden_v1.json")


def _parca(box, kind):
    return {"page": 1, "box": list(box), "kind": kind}


def _mukemmel_v2_tahmin():
    stim = [60, 80, 940, 190]
    q21 = [60, 210, 480, 650]
    q22 = [520, 210, 940, 650]
    return {
        "schema_version": dogrula.TAHMIN_SEMA_SURUMU_V2,
        "generator": {"algorithm_version": "test-v3", "quality_mode": "strict"},
        "documents": [{
            "id": "synthetic:final-cuts-v2",
            "source": "synthetic-final-cuts-v2.pdf",
            "source_hash": "synthetic",
            "final_output": {
                "quality_mode": "strict", "blocked": False,
                "written": True, "zip_written": True,
                "pending_review_count": 0, "question_count": 2,
                "png_count": 2, "metadata_count": 2,
            },
            "pages": [{
                "page": 1, "width": 1000, "height": 1400,
                "role": "soru", "role_confidence": 0.99,
                "layout_family": "2_sutun", "review_status": "temiz",
                "risk_reasons": [],
                "raw_proposals": [{
                    "id": "raw-q21-a", "box": [60, 210, 480, 430],
                    "type": "çoktan_seçmeli", "confidence": 0.75,
                    "status": "otomatik"
                }, {
                    "id": "raw-q21-b", "box": [60, 430, 480, 650],
                    "type": "çoktan_seçmeli", "confidence": 0.72,
                    "status": "otomatik"
                }, {
                    "id": "raw-q22", "parts": [_parca(stim, "shared_stimulus"),
                                                   _parca(q22, "question_body")],
                    "type": "kısa_cevap", "confidence": 0.81,
                    "status": "otomatik"
                }],
                "final_cuts": [{
                    "id": "cut-q21",
                    "parts": [_parca(stim, "shared_stimulus"),
                              _parca(q21, "question_body")],
                    "number": 21, "type": "çoktan_seçmeli",
                    "confidence": 0.90, "status": "otomatik",
                    "output": {"produced": True, "question_number": 21,
                               "part_count": 2,
                               "metadata": {"subject": "matematik"}}
                }, {
                    "id": "cut-q22",
                    "parts": [_parca(stim, "shared_stimulus"),
                              _parca(q22, "question_body")],
                    "number": 22, "type": "kısa_cevap",
                    "confidence": 0.60, "status": "onaylandı",
                    "output": {"produced": True, "question_number": 22,
                               "part_count": 2,
                               "metadata": {"subject": "matematik"}}
                }]
            }, {
                "page": 2, "width": 1000, "height": 1400,
                "role": "çözüm", "role_confidence": 0.98,
                "layout_family": "1_sutun", "review_status": "temiz",
                "risk_reasons": [], "raw_proposals": [], "final_cuts": []
            }]
        }]
    }


class V2SemaTesti(unittest.TestCase):
    def test_v2_fixture_ve_unicode_degerler_ascii_kanonige_doner(self):
        altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)
        self.assertEqual(dogrula.ALTIN_SEMA_SURUMU_V2,
                         altin["schema_version"])
        self.assertEqual("coktan_secmeli",
                         altin["documents"][0]["pages"][0]
                         ["questions"][0]["type"])
        self.assertEqual("cozum", altin["documents"][0]["pages"][1]["role"])
        self.assertEqual("sekil", altin["documents"][0]["pages"][0]
                         ["questions"][0]["required_regions"][0]["kind"])

        unicode_altin = copy.deepcopy(altin)
        unicode_altin["documents"][0]["pages"][1]["role"] = "çözüm"
        unicode_altin["documents"][0]["pages"][0]["questions"][0]["type"] = \
            "çoktan_seçmeli"
        dogrula._veri_setini_dogrula(unicode_altin, tahmin=False)
        self.assertEqual("cozum", unicode_altin["documents"][0]["pages"][1]
                         ["role"])
        self.assertEqual("coktan_secmeli", unicode_altin["documents"][0]
                         ["pages"][0]["questions"][0]["type"])

        tahmin = dogrula._veri_setini_dogrula(_mukemmel_v2_tahmin(),
                                               tahmin=True)
        self.assertEqual("kisa_cevapli", tahmin["documents"][0]["pages"][0]
                         ["final_cuts"][1]["type"])
        self.assertEqual("onaylandi", tahmin["documents"][0]["pages"][0]
                         ["final_cuts"][1]["status"])

    def test_v1_ve_v2_schema_dosyalari_birlikte_yuklenir(self):
        for ad in ("golden_schema_v1.json", "prediction_schema_v1.json",
                   "golden_schema_v2.json", "prediction_schema_v2.json"):
            with open(os.path.join(KALITE_KLASORU, ad), encoding="utf-8") as f:
                sema = json.load(f)
            self.assertEqual("https://json-schema.org/draft/2020-12/schema",
                             sema["$schema"])

    def test_v2_box_veya_parca_olmadan_soruyu_reddeder(self):
        tahmin = _mukemmel_v2_tahmin()
        del tahmin["documents"][0]["pages"][0]["final_cuts"][0]["parts"]
        with self.assertRaisesRegex(ValueError, "box veya dolu parts"):
            dogrula._veri_setini_dogrula(tahmin, tahmin=True)


class NihaiCiktiEvaluatorTesti(unittest.TestCase):
    def setUp(self):
        self.altin = dogrula.altin_veriyi_yukle(ALTIN_YOLU)

    def test_ham_teklif_ve_nihai_kesim_ayri_olculur(self):
        sonuc = dogrula.kalite_degerlendir(
            self.altin, _mukemmel_v2_tahmin())
        self.assertEqual(dogrula.KALITE_RAPORU_SURUMU_V2,
                         sonuc["schema_version"])
        self.assertEqual("final_cuts", sonuc["evaluation_target"])
        self.assertEqual(1.0, sonuc["final_cuts"]["precision"])
        self.assertEqual(1.0, sonuc["final_cuts"]["recall"])
        self.assertEqual(0, sonuc["split_merge_proxy"]["split_count"])
        self.assertEqual(1, sonuc["raw_proposals"]["split_count"])

    def test_zorunlu_bolgeler_ve_yasak_sizinti_olculur(self):
        sonuc = dogrula.kalite_degerlendir(
            self.altin, _mukemmel_v2_tahmin())
        self.assertEqual(4, sonuc["regions"]["required"]["count"])
        self.assertEqual(4, sonuc["regions"]["required"]["fully_covered"])
        self.assertEqual(1.0, sonuc["regions"]["required"]["area_coverage"])
        self.assertEqual(0, sonuc["regions"]["forbidden"]
                         ["regions_with_leakage"])

        sizan = _mukemmel_v2_tahmin()
        sizan["documents"][0]["pages"][0]["final_cuts"][0]["parts"][1]["box"][2] = 600
        sonuc = dogrula.kalite_degerlendir(self.altin, sizan)
        self.assertGreater(sonuc["regions"]["forbidden"]["leakage_rate"], 0)

    def test_ece_ve_nihai_metadata_sayilari_raporlanir(self):
        sonuc = dogrula.kalite_degerlendir(
            self.altin, _mukemmel_v2_tahmin())
        self.assertAlmostEqual(0.25,
                               sonuc["confidence_calibration"]["ece"])
        meta = sonuc["final_output_metadata"]
        self.assertEqual(1.0, meta["number_accuracy"])
        self.assertEqual(1.0, meta["part_count_accuracy"])
        self.assertEqual(1.0, meta["metadata_accuracy"])
        self.assertTrue(meta["question_count_matches"])

    def test_strict_bekleyen_incelemeyi_nihai_ciktida_yakalayip_bloku_onaylar(self):
        ihlal = _mukemmel_v2_tahmin()
        sayfa = ihlal["documents"][0]["pages"][0]
        sayfa["review_status"] = "bekliyor"
        sayfa["raw_proposals"][0]["status"] = "incele"
        ihlal["documents"][0]["final_output"]["pending_review_count"] = 1
        sonuc = dogrula.kalite_degerlendir(self.altin, ihlal)
        self.assertFalse(sonuc["strict_output"]["passes"])
        self.assertIn("bekleyen_incelemeye_ragmen_cikti_yazildi",
                      sonuc["strict_output"]["violations"])

        bloklu = copy.deepcopy(ihlal)
        bloklu["documents"][0]["pages"][0]["final_cuts"] = []
        cikti = bloklu["documents"][0]["final_output"]
        cikti.update({"blocked": True, "written": False, "zip_written": False,
                      "question_count": 0, "png_count": 0,
                      "metadata_count": 0})
        sonuc = dogrula.kalite_degerlendir(self.altin, bloklu)
        self.assertTrue(sonuc["strict_output"]["blocked_as_required"])
        self.assertTrue(sonuc["strict_output"]["passes"])
        self.assertEqual(2, sonuc["question_boxes"]["false_negative"])

    def test_v2_rapor_yaz_oku_ozeti(self):
        with tempfile.TemporaryDirectory(prefix="quality_v3_") as gecici:
            yol = os.path.join(gecici, "prediction-v2.json")
            dogrula.rapor_yaz(_mukemmel_v2_tahmin(), yol)
            rapor = dogrula.tahmin_raporunu_yukle(yol)
            ozet = dogrula.rapor_ozeti(rapor)
            self.assertEqual("soru-kesici.prediction-summary/v2",
                             ozet["schema_version"])
            self.assertEqual(2, ozet["question_count"])
            self.assertEqual(3, ozet["raw_proposal_count"])

    def test_v2_rapor_uretici_gercek_kirpma_seti_sayilarini_yazar(self):
        with tempfile.TemporaryDirectory(prefix="quality_v3_generator_") as gecici:
            pdf = os.path.join(gecici, "one-question.pdf")
            _tek_soruluk_pdf(pdf)
            rapor = dogrula.tahmin_raporu_olustur(
                pdf, dpi=144, max_sayfa=1, belge_kimligi="synthetic:v3",
                schema_version=dogrula.TAHMIN_SEMA_SURUMU_V2,
                quality_mode="strict")
            belge = rapor["documents"][0]
            final_adet = sum(len(s["final_cuts"]) for s in belge["pages"])
            self.assertEqual(final_adet, belge["final_output"]["png_count"])
            self.assertEqual(final_adet,
                             belge["final_output"]["metadata_count"])
            self.assertEqual(1, len(belge["pages"][0]["raw_proposals"]))

    def test_kenar_hatalari_mukemmel_kesimde_sifir(self):
        sonuc = dogrula.kalite_degerlendir(
            self.altin, _mukemmel_v2_tahmin())
        kenar = sonuc["kenar_hatalari"]
        self.assertEqual(2, kenar["n"])
        self.assertEqual("pt", kenar["birim"])
        for yon in dogrula.KENAR_YONLERI:
            self.assertEqual(2, kenar[yon]["n"], yon)
            for olcut in ("medyan", "p95", "ortalama", "maks_mutlak",
                          "medyan_yuzde", "p95_yuzde", "maks_mutlak_yuzde"):
                self.assertEqual(0.0, kenar[yon][olcut],
                                 f"{yon}.{olcut}")

    def test_kenar_hatalari_sistematik_ustten_trasi_ayirir(self):
        # Her kesim 14 pt asagidan basliyor: ust SISTEMATIK pozitif, diger
        # uc yon temiz. F1 tek sayisi bu ayrimi hic gostermiyordu.
        trasli = _mukemmel_v2_tahmin()
        for kesim in trasli["documents"][0]["pages"][0]["final_cuts"]:
            kesim["parts"][1]["box"][1] += 14
        kenar = dogrula.kalite_degerlendir(
            self.altin, trasli)["kenar_hatalari"]
        self.assertEqual(14.0, kenar["ust"]["medyan"])
        self.assertEqual(14.0, kenar["ust"]["maks_mutlak"])
        # 14 / 1400 = %1
        self.assertAlmostEqual(1.0, kenar["ust"]["medyan_yuzde"])
        self.assertEqual(0.0, kenar["alt"]["medyan"])
        self.assertEqual(0.0, kenar["sol"]["maks_mutlak"])
        self.assertEqual(0.0, kenar["sag"]["maks_mutlak"])

    def test_kenar_hatalari_tek_yonlu_tasmada_isareti_korur(self):
        # alta tasma (+) ile soldan genisleme (-) ayni koşumda: isaret
        # kaybolursa iki karsit hata tek "buyuk sapma" olarak gorunur.
        kayan = _mukemmel_v2_tahmin()
        for kesim in kayan["documents"][0]["pages"][0]["final_cuts"]:
            kesim["parts"][1]["box"][3] += 30    # alt: asagi tasti
            kesim["parts"][1]["box"][0] -= 12    # sol: sola genisledi
        kenar = dogrula.kalite_degerlendir(
            self.altin, kayan)["kenar_hatalari"]
        self.assertEqual(30.0, kenar["alt"]["medyan"])
        self.assertEqual(30.0, kenar["alt"]["ortalama"])
        self.assertEqual(-12.0, kenar["sol"]["medyan"])
        self.assertEqual(-12.0, kenar["sol"]["ortalama"])
        # p95 mutlak deger uzerinden; isaret yalniz medyan/ortalamada.
        self.assertEqual(12.0, kenar["sol"]["p95"])
        self.assertEqual(0.0, kenar["ust"]["medyan"])
        self.assertEqual(0.0, kenar["sag"]["medyan"])

    def test_kenar_hatalari_eslesme_yoksa_bos_doner(self):
        kacik = _mukemmel_v2_tahmin()
        for kesim in kacik["documents"][0]["pages"][0]["final_cuts"]:
            kesim["parts"] = [_parca([10, 1000, 60, 1350], "question_body")]
        sonuc = dogrula.kalite_degerlendir(self.altin, kacik)
        kenar = sonuc["kenar_hatalari"]
        self.assertEqual(0, sonuc["final_cuts"]["true_positive"])
        self.assertEqual(0, kenar["n"])
        for yon in dogrula.KENAR_YONLERI:
            self.assertEqual(0, kenar[yon]["n"], yon)
            self.assertEqual(0.0, kenar[yon]["medyan"], yon)
            self.assertEqual(0.0, kenar[yon]["p95"], yon)
            self.assertEqual(0.0, kenar[yon]["maks_mutlak"], yon)

    def test_kenar_hatalari_baska_sayfadaki_devam_parcasini_saymaz(self):
        # Devam parcasi baska sayfadadir; onun kenarini ana kutunun kenariyla
        # kiyaslamak anlamsiz buyuk sayilar uretirdi.
        devamli = _mukemmel_v2_tahmin()
        kesim = devamli["documents"][0]["pages"][0]["final_cuts"][0]
        kesim["parts"].append({"page": 2, "box": [60, 1300, 200, 1360],
                                "kind": "continuation"})
        kenar = dogrula.kalite_degerlendir(
            self.altin, devamli)["kenar_hatalari"]
        self.assertEqual(2, kenar["n"])
        for yon in dogrula.KENAR_YONLERI:
            self.assertEqual(0.0, kenar[yon]["maks_mutlak"], yon)

    def test_kanitsiz_kutu_orani_metriklerde_raporlanir(self):
        with tempfile.TemporaryDirectory(prefix="quality_v3_kanit_") as gecici:
            pdf = os.path.join(gecici, "one-question.pdf")
            _tek_soruluk_pdf(pdf)
            m = dogrula.metrikler(pdf, dpi=144, max_sayfa=1)
        self.assertIn("kanitsiz_kutu", m)
        self.assertLessEqual(m["kanitsiz_kutu"], m["toplam_kutu"])
        self.assertAlmostEqual(
            m["kanitsiz_kutu"] / max(m["toplam_kutu"], 1),
            m["kanitsiz_kutu_orani"])
        self.assertLessEqual(len(m["kanitsiz_sayfalar"]), 10)
        # Kanıtsız sayfa listesi yalnız gerçekten işlenen sayfalardan gelir.
        for no in m["kanitsiz_sayfalar"]:
            self.assertIn(no, m["ornek_no"])

    def test_kenar_hatalari_govde_sayfasi_uyusmazsa_cifti_atlar(self):
        # Altın gövdeyi 1. sayfada tutarken tahmin 2. sayfadaki parçayı
        # gövde sayıyor: kenar farkı iki AYRI sayfanın koordinatını
        # kıyaslar ve yüzlerce puntoluk sahte sapma üretir. Eşleşme
        # (IoU 1.0) korunsa bile bu çift teşhise girmemeli.
        altin = copy.deepcopy(self.altin)
        q21 = altin["documents"][0]["pages"][0]["questions"][0]
        q21["parts"].append({"page": 2, "box": [60, 700, 480, 1100],
                             "kind": "devam"})
        tahmin = _mukemmel_v2_tahmin()
        kesim = tahmin["documents"][0]["pages"][0]["final_cuts"][0]
        kesim["parts"][1]["kind"] = "continuation"
        kesim["parts"].append({"page": 2, "box": [60, 700, 480, 1100],
                               "kind": "question_body"})
        sonuc = dogrula.kalite_degerlendir(altin, tahmin)
        self.assertEqual(2, sonuc["final_cuts"]["true_positive"])
        kenar = sonuc["kenar_hatalari"]
        # Yalnız q22 çifti sayılır; q21 sayfa uyuşmazlığından atlanır.
        self.assertEqual(1, kenar["n"])
        for yon in dogrula.KENAR_YONLERI:
            self.assertEqual(1, kenar[yon]["n"], yon)
            self.assertEqual(0.0, kenar[yon]["maks_mutlak"], yon)

    def test_cli_konumsal_sozlesmeye_v2_secenekleri_eklenir(self):
        args = dogrula._arguman_ayristir([
            "kitap.pdf", "12", "--rapor-sema", "v2",
            "--kalite", "strict"])
        self.assertEqual("kitap.pdf", args.yol)
        self.assertEqual(12, args.max_sayfa)
        self.assertEqual("v2", args.rapor_sema)
        self.assertEqual("strict", args.kalite)


class _SahteAday:
    """`sk.aday_tespit_edildi`nin okuduğu üç alanı taşıyan asgari aday."""

    def __init__(self, *, devam_aday=False, inceleme_durumu="otomatik",
                 sinir_kanitlari=()):
        self.devam_aday = devam_aday
        self.inceleme_durumu = inceleme_durumu
        self.sinir_kanitlari = sinir_kanitlari


class _KanitAlanisizAday:
    """`sinir_kanitlari` alanı hiç olmayan eski aday nesnesi taklidi."""

    def __init__(self):
        self.devam_aday = False
        self.inceleme_durumu = "otomatik"


class KenarIstatistikTesti(unittest.TestCase):
    """Kenar teşhisinin istatistik çekirdeği: medyan/p95/gövde seçimi.

    Uçtan uca kalite koşumları bu üç davranışı yakalayamaz (fixture'daki
    iki kesimde medyan = ortalama, p95 = maksimum çıkar); doğrudan
    ölçülmezse bozuk bir uygulama sessizce yeşil kalır.
    """

    def test_medyan_ve_yuzdelik_kenar_durumlari(self):
        self.assertEqual(0.0, dogrula._medyan([]))
        self.assertEqual(5.0, dogrula._medyan([5]))
        # Girdi sıralanmamış olabilir; medyan ortalamaya (34.67) düşmemeli.
        self.assertEqual(3.0, dogrula._medyan([100, 1, 3]))
        self.assertEqual(2.0, dogrula._medyan([3, 1]))
        self.assertEqual(0.0, dogrula._yuzdelik([], 0.95))
        self.assertEqual(7.0, dogrula._yuzdelik([7], 0.95))
        # Aradeğerleme kanıtı: iki elemanda p95 maksimum (10.0) değildir.
        self.assertAlmostEqual(9.5, dogrula._yuzdelik([10, 0], 0.95))
        self.assertAlmostEqual(95.0, dogrula._yuzdelik(list(range(101)),
                                                       0.95))

    def test_kenar_yon_ozeti_medyani_ortalamaya_p95i_maksa_indirgemez(self):
        # Tek büyük sapma: "sistematik kayma" ile "seyrek kuyruk" ayrımı
        # ancak medyan != ortalama ve p95 != maksimum ise ölçülebilir.
        ozet = dogrula._kenar_yon_ozeti([(0.0, 0.0), (0.0, 0.0),
                                         (90.0, 9.0)])
        self.assertEqual(3, ozet["n"])
        self.assertEqual(0.0, ozet["medyan"])
        self.assertAlmostEqual(30.0, ozet["ortalama"])
        self.assertAlmostEqual(81.0, ozet["p95"])
        self.assertEqual(90.0, ozet["maks_mutlak"])
        self.assertEqual(0.0, ozet["medyan_yuzde"])
        self.assertAlmostEqual(3.0, ozet["ortalama_yuzde"])
        self.assertAlmostEqual(8.1, ozet["p95_yuzde"])

    def test_kenar_yon_ozeti_isareti_medyanda_tutar_p95te_atar(self):
        ozet = dogrula._kenar_yon_ozeti([(-40.0, -4.0), (-10.0, -1.0)])
        self.assertEqual(-25.0, ozet["medyan"])
        self.assertEqual(-25.0, ozet["ortalama"])
        self.assertAlmostEqual(38.5, ozet["p95"])
        self.assertEqual(40.0, ozet["maks_mutlak"])
        self.assertEqual(-2.5, ozet["medyan_yuzde"])
        self.assertAlmostEqual(3.85, ozet["p95_yuzde"])

    def test_kenar_govde_parcasi_govde_bulamazsa_none_doner(self):
        self.assertIsNone(dogrula._kenar_govde_parcasi({}))
        self.assertIsNone(dogrula._kenar_govde_parcasi({"parts": []}))
        # Tümü devam/ortak uyaran: rastgele bir parçayı gövde saymak
        # sessizce sahte kenar farkı üretirdi.
        self.assertIsNone(dogrula._kenar_govde_parcasi({"parts": [
            {"page": 1, "box": [0, 0, 1, 1], "kind": "ortak_uyaran"},
            {"page": 2, "box": [0, 0, 1, 1], "kind": "devam"}]}))
        # Altın tarafta `kind` yoksa tek parça gövdedir.
        kindsiz = {"page": 1, "box": [0, 0, 1, 1], "kind": None}
        self.assertIs(kindsiz,
                      dogrula._kenar_govde_parcasi({"parts": [kindsiz]}))
        # Gövde ilk sırada olmasa da kind'e göre seçilir.
        govde = {"page": 1, "box": [0, 0, 2, 2], "kind": "soru_govdesi"}
        self.assertIs(govde, dogrula._kenar_govde_parcasi({"parts": [
            {"page": 1, "box": [0, 0, 1, 1], "kind": "ortak_uyaran"},
            govde]}))

    def test_kenar_hatalari_v1_dalinda_da_uretilir(self):
        # V1 değerlendirmesi ayrı bir koddur; v2 testleri o dalı hiç
        # çalıştırmaz. İşaret sözleşmesi iki dalda AYNI olmak zorunda,
        # yoksa iki korpusun sayıları birbirinin tersi okunur.
        altin = dogrula.altin_veriyi_yukle(V1_ALTIN_YOLU)
        kenar = dogrula.kalite_degerlendir(
            altin, _mukemmel_tahmin(altin))["kenar_hatalari"]
        self.assertEqual(4, kenar["n"])
        for yon in dogrula.KENAR_YONLERI:
            self.assertEqual(0.0, kenar[yon]["maks_mutlak"], yon)

        kaydirilmis = _mukemmel_tahmin(altin)
        for belge in kaydirilmis["documents"]:
            for sayfa in belge["pages"]:
                for soru in sayfa["questions"]:
                    soru["box"][1] += 3
                    soru["box"][3] += 3
        kenar = dogrula.kalite_degerlendir(
            altin, kaydirilmis)["kenar_hatalari"]
        self.assertEqual(4, kenar["n"])
        self.assertEqual(3.0, kenar["ust"]["medyan"])
        self.assertEqual(3.0, kenar["alt"]["medyan"])
        self.assertEqual(0.0, kenar["sol"]["maks_mutlak"])
        self.assertEqual(0.0, kenar["sag"]["maks_mutlak"])

    def test_kanitsiz_kutu_say_yalniz_teslim_kumesini_sayar(self):
        # Reddedilen ve devam adayları hiç teslim edilmez; onları saymak
        # payda (`toplam_kutu`) ile tutmayan bir oran üretirdi.
        meta = [
            _SahteAday(),
            _SahteAday(sinir_kanitlari=("ust:blok",)),
            _SahteAday(inceleme_durumu="reddedildi"),
            _SahteAday(devam_aday=True),
            _SahteAday(inceleme_durumu="incele"),
        ]
        self.assertEqual(2, dogrula._kanitsiz_kutu_say(meta))
        self.assertEqual(0, dogrula._kanitsiz_kutu_say([]))
        # Alanı hiç olmayan nesne de kanıtsız sayılır (getattr varsayılanı).
        self.assertEqual(1, dogrula._kanitsiz_kutu_say([_KanitAlanisizAday()]))


if __name__ == "__main__":
    unittest.main()


class IncelaKovasiTesti(unittest.TestCase):
    """'Sıfır hata' = otomatik kovada kusursuz + emin olunamayan AYRI klasörde.

    Eskiden strict/balanced kipte 'incele' kutuları çıktıya HİÇ yazılmıyordu:
    sessiz kayıp. Artık aynı koşumun tümleyen kovası üretilebiliyor ve
    her kesim gerekçesiyle birlikte 'İncele/' altına yazılıyor.
    """

    @staticmethod
    def _meta(durum, onay="otomatik"):
        return sk.SoruKutu(
            kutu=(10.0, 10.0, 100.0, 60.0), bant_idx=0, numara=1,
            devam_aday=False, sik_harfler=frozenset(), son_metin="",
            govde_var=True, inceleme_durumu=durum, onay_durumu=onay)

    def test_kovalar_ayrik_ve_tamamlayici(self):
        """Bir aday ya çıktıya ya incele'ye gider; ikisine birden ya da
        hiçbirine gitmez. Aksi halde ya mükerrer kesim ya sessiz kayıp olur."""
        cikti = sk._kova_secici("balanced", "cikti")
        incele = sk._kova_secici("balanced", "incele")
        for durum in ("otomatik", "incele", "reddedildi"):
            m = self._meta(durum)
            self.assertFalse(cikti(m) and incele(m), f"{durum}: ikisinde de")
            if durum == "reddedildi":
                self.assertFalse(cikti(m) or incele(m))
            else:
                self.assertTrue(cikti(m) or incele(m), f"{durum}: hiçbirinde")

    def test_incele_kovasi_sadece_incele_alir(self):
        incele = sk._kova_secici("balanced", "incele")
        self.assertTrue(incele(self._meta("incele")))
        self.assertFalse(incele(self._meta("otomatik")))
        self.assertFalse(incele(self._meta("reddedildi")))

    def test_onaylanan_aday_ciktiya_gider_inceleye_degil(self):
        m = self._meta("incele", onay="onaylandi")
        self.assertTrue(sk._kova_secici("balanced", "cikti")(m))
        self.assertFalse(sk._kova_secici("balanced", "incele")(m))

    def test_legacy_kipinde_incele_kovasi_bostur(self):
        """legacy her şeyi ana çıktıya yazar; tümleyen boş olmalı, yoksa
        aynı kesim iki kez üretilirdi."""
        incele = sk._kova_secici("legacy", "incele")
        for durum in ("otomatik", "incele"):
            self.assertFalse(incele(self._meta(durum)))

    def test_gerekce_uyarisiz_kutuda_da_uretilir(self):
        """Ölçüldü: incele kutularının 28/49'u hiçbir uyarı taşımıyordu.
        Gerekçesiz bir 'İncele/' klasörü kullanıcıyı sayfayı baştan
        incelemeye zorlar."""
        m = self._meta("incele")._replace(uyarilar=(), kanitlar=("soru_numarasi",))
        g = sk.aday_inceleme_gerekcesi(m)
        self.assertTrue(g)
        self.assertTrue(any("kanit_yetersiz" in x for x in g))

    def test_gerekce_varolan_uyarilari_korur(self):
        m = self._meta("incele")._replace(uyarilar=("sutun_uzlasmazligi",))
        self.assertEqual(("sutun_uzlasmazligi",), sk.aday_inceleme_gerekcesi(m))

    def test_bilinmeyen_kova_hata(self):
        with self.assertRaises(ValueError):
            sk._kova_secici("balanced", "baska")
