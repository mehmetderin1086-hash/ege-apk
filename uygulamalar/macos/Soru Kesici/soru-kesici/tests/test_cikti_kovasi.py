# -*- coding: utf-8 -*-
"""Çıktı yazımının sessiz kayıp/bulaşma sınırları."""
import json
import os
import tempfile
import unittest
import zipfile
from unittest import mock

from PIL import Image

import kalite_kosusu
import soru_kes as sk


def _kirpim(renk="white"):
    return Image.new("RGB", (20, 30), renk)


class ZipYaziminaHedefKlasoruTesti(unittest.TestCase):
    def test_var_olmayan_klasor_cokme_yerine_olusturulur(self):
        with tempfile.TemporaryDirectory() as kok:
            hedef = os.path.join(kok, "yok", "daha-yok", "cikti.zip")
            adet = sk.zip_yaz([_kirpim()], hedef)
            self.assertEqual(1, adet)
            self.assertTrue(os.path.isfile(hedef))
            with zipfile.ZipFile(hedef) as paket:
                self.assertEqual(["soru_01.png"], paket.namelist())


class KlasorKovasiTemizligiTesti(unittest.TestCase):
    def _koleksiyon_yaz(self, kok, adet, sorular=None):
        hedef = os.path.join(kok, "cikti.zip")
        sk.zip_yaz(
            [_kirpim() for _ in range(adet)], hedef, klasor=True,
            sorular=sorular)
        return os.path.join(kok, "cikti")

    def test_ikinci_kosum_daha_az_soru_uretirse_eski_kirpimlar_kalmaz(self):
        with tempfile.TemporaryDirectory() as kok:
            klasor = self._koleksiyon_yaz(kok, 5)
            self.assertEqual(5, len(
                [a for a in os.listdir(klasor) if a.endswith(".png")]))

            self._koleksiyon_yaz(kok, 2)
            pngler = sorted(a for a in os.listdir(klasor) if a.endswith(".png"))
            self.assertEqual(["soru_01.png", "soru_02.png"], pngler)

    def test_incele_kovasindaki_eski_kirpimlar_da_temizlenir(self):
        with tempfile.TemporaryDirectory() as kok:
            hedef = os.path.join(kok, "cikti.zip")
            sk.zip_yaz([_kirpim()], hedef, klasor=True,
                       incele=[_kirpim(), _kirpim(), _kirpim()])
            incele = os.path.join(kok, "cikti", sk.INCELE_KLASORU)
            self.assertEqual(3, len(os.listdir(incele)))

            sk.zip_yaz([_kirpim()], hedef, klasor=True, incele=[_kirpim()])
            self.assertEqual(["incele_01.png"], sorted(os.listdir(incele)))

    def test_kunye_ile_klasor_icerigi_ayrismaz(self):
        sorular_bes = [
            {"test_no": None, "soru_no": i, "sayfa": 1} for i in range(1, 6)]
        sorular_iki = [
            {"test_no": None, "soru_no": i, "sayfa": 1} for i in range(1, 3)]
        with tempfile.TemporaryDirectory() as kok:
            klasor = self._koleksiyon_yaz(kok, 5, sorular=sorular_bes)
            self._koleksiyon_yaz(kok, 2, sorular=sorular_iki)
            with open(os.path.join(klasor, "sorular.json"), encoding="utf-8") as f:
                kunye = json.load(f)
            diskteki = {a for a in os.listdir(klasor) if a.endswith(".png")}
            self.assertEqual({k["dosya"] for k in kunye}, diskteki)

    def test_yabanci_dosyaya_dokunulmaz(self):
        with tempfile.TemporaryDirectory() as kok:
            klasor = self._koleksiyon_yaz(kok, 2)
            yabanci = os.path.join(klasor, "notlarim.txt")
            with open(yabanci, "w", encoding="utf-8") as f:
                f.write("elle yazılmış")
            alt = os.path.join(klasor, "kendi-klasorum")
            os.makedirs(alt)

            self._koleksiyon_yaz(kok, 1)

            self.assertTrue(os.path.isfile(yabanci))
            self.assertTrue(os.path.isdir(alt))


class KorpusDogrulamaTesti(unittest.TestCase):
    def test_eksik_belge_kosumdan_once_adiyla_bildirilir(self):
        koleksiyon = [
            {"ad": "var-olmayan", "yol": "hicbir/yerde/olmayan.pdf"},
        ]
        with self.assertRaises(kalite_kosusu.KorpusEksik) as tutamac:
            kalite_kosusu._korpusu_dogrula(koleksiyon)
        self.assertIn("var-olmayan", str(tutamac.exception))
        self.assertIn("SORU_KESICI_KORPUS", str(tutamac.exception))

    def test_icloud_tahliyesi_ayri_gerekceyle_bildirilir(self):
        """Tahliye edilmiş dosya VAR görünür; kapı bunu erken ve doğru demeli."""
        sahte_stat = type("S", (), {
            "st_flags": 0x40000000, "st_size": 1024, "st_blocks": 0})()
        with mock.patch.object(kalite_kosusu.os, "stat", return_value=sahte_stat):
            with self.assertRaises(kalite_kosusu.KorpusEksik) as tutamac:
                kalite_kosusu._korpusu_dogrula(
                    [{"ad": "tahliye", "yol": "/bir/kitap.pdf"}])
        mesaj = str(tutamac.exception)
        self.assertIn("iCloud", mesaj)
        self.assertIn("ASKIDA KALIR", mesaj)

    def test_blocks_sifir_da_tahliye_sayilir(self):
        sahte_stat = type("S", (), {
            "st_flags": 0, "st_size": 5_000_000, "st_blocks": 0})()
        with mock.patch.object(kalite_kosusu.os, "stat", return_value=sahte_stat):
            tamam, gerekce = kalite_kosusu._belge_erisilebilir_mi("/bir/kitap.pdf")
        self.assertFalse(tamam)
        self.assertIn("iCloud", gerekce)

    def test_saglam_dosya_gecer(self):
        tamam, gerekce = kalite_kosusu._belge_erisilebilir_mi(
            os.path.join(os.path.dirname(os.path.dirname(
                os.path.abspath(__file__))), "soru_kes.py"))
        self.assertTrue(tamam, gerekce)

    def test_ev_dizinine_goreli_korpus_yolu_cozulur(self):
        # Korpusun bir bölümü `Desktop/…` gibi ev-göreli yazılmış; repo
        # taşındığında yalnız repo kökünü denemek bunları kaybettiriyordu.
        with tempfile.NamedTemporaryFile(
                dir=os.path.expanduser("~"), suffix=".pdf") as gecici:
            goreli = os.path.basename(gecici.name)
            self.assertEqual(
                gecici.name, kalite_kosusu._tam_yol(goreli))

    def test_ortam_degiskeni_korpus_kokunu_gecersiz_kilar(self):
        with tempfile.TemporaryDirectory() as kok:
            ad = "kitap.pdf"
            with open(os.path.join(kok, ad), "w", encoding="utf-8") as f:
                f.write("x")
            onceki = os.environ.get("SORU_KESICI_KORPUS")
            os.environ["SORU_KESICI_KORPUS"] = kok
            try:
                self.assertEqual(
                    os.path.join(kok, ad), kalite_kosusu._tam_yol(ad))
            finally:
                if onceki is None:
                    del os.environ["SORU_KESICI_KORPUS"]
                else:
                    os.environ["SORU_KESICI_KORPUS"] = onceki



class _SahteSayfa:
    def __init__(self, satirlar=()):
        self.genislik = 600.0
        self.yukseklik = 800.0
        self._satirlar = list(satirlar)

    def satirlar(self):
        return self._satirlar


class TeslimAyrismasiTesti(unittest.TestCase):
    """Kapı, ölçtüğü kümeyle teslim ettiği kümeyi ayırt edebilmeli."""

    def _veriler(self, kutu_sayilari):
        return [
            (_SahteSayfa(), [(0.0, 600.0)], [object()] * n, [])
            for n in kutu_sayilari
        ]

    def _kosturr(self, kutu_sayilari, dislanacak, soru_sayfalari=None,
                 cevap_sayfasi=()):
        import soru_kes as sk
        eski_rol = sk._belge_sayfa_rolleri
        eski_cevap = sk._cevap_sayfasi_mi
        sk._belge_sayfa_rolleri = (
            lambda sayfalar, kalite="legacy", *, fmt: (
                set(dislanacak), soru_sayfalari))
        sayac = {"i": -1}

        def _cevap(_satirlar):
            sayac["i"] += 1
            return sayac["i"] in cevap_sayfasi

        sk._cevap_sayfasi_mi = _cevap
        try:
            return kalite_kosusu._teslim_ayrismasi(
                self._veriler(kutu_sayilari), "karisik")
        finally:
            sk._belge_sayfa_rolleri = eski_rol
            sk._cevap_sayfasi_mi = eski_cevap

    def test_vetolu_sayfanin_kutulari_teslimden_dusulur(self):
        sonuc = self._kosturr([10, 7, 5], dislanacak={1})
        self.assertEqual(22, sonuc["olculen_kutu"])
        self.assertEqual(15, sonuc["teslim_kutu"])
        self.assertEqual(7, sonuc["kayip_kutu"])
        self.assertEqual([1], sonuc["veto_sayfa"])

    def test_soru_sayfasi_listesi_disindakiler_de_vetolanir(self):
        sonuc = self._kosturr([4, 4, 4], dislanacak=set(), soru_sayfalari={0})
        self.assertEqual(4, sonuc["teslim_kutu"])
        self.assertEqual([1, 2], sonuc["veto_sayfa"])

    def test_cevap_anahtari_sayfasi_teslim_edilmez(self):
        sonuc = self._kosturr([6, 6], dislanacak=set(), cevap_sayfasi={1})
        self.assertEqual(6, sonuc["teslim_kutu"])
        self.assertEqual([1], sonuc["veto_sayfa"])

    def test_ayrisma_yoksa_kayip_sifirdir(self):
        sonuc = self._kosturr([3, 3], dislanacak=set())
        self.assertEqual(0, sonuc["kayip_kutu"])
        self.assertEqual([], sonuc["veto_sayfa"])

    def test_veto_hesabi_patlarsa_kosum_dusmez(self):
        import soru_kes as sk
        eski = sk._belge_sayfa_rolleri

        def _patla(*a, **k):
            raise RuntimeError("veto hesaplanamadı")

        sk._belge_sayfa_rolleri = _patla
        try:
            sonuc = kalite_kosusu._teslim_ayrismasi(
                self._veriler([1]), "karisik")
        finally:
            sk._belge_sayfa_rolleri = eski
        self.assertIn("hata", sonuc)
        self.assertIn("veto hesaplanamadı", sonuc["hata"])


class DislananSayfaGorunurlugu(unittest.TestCase):
    """Veto edilen sayfa üçüncü bir sonuç olarak dışarı taşınmalı.

    "Bu sayfada soru bulunamadı" ile "bu sayfa bilerek dışlandı" dışarıdan
    ayırt edilemiyordu; ikisi de sessiz sıfırdı.
    """

    def test_plan_raporu_dislanan_sayfalari_bildirir(self):
        rapor = {}
        cagrilan = {}

        def _sahte_roller(sayfalar, kalite="legacy", *, fmt):
            cagrilan["fmt"] = fmt
            return {1}, None

        eski_rol = sk._belge_sayfa_rolleri
        eski_cevap = sk._cevap_sayfasi_mi
        eski_tespit = sk.sorulari_tespit_meta
        eski_bolum = sk.test_bolumleri
        sk._belge_sayfa_rolleri = _sahte_roller
        sk._cevap_sayfasi_mi = lambda _s: False
        sk.sorulari_tespit_meta = lambda s, fmt: ([], [(0.0, 600.0)], fmt)
        sk.test_bolumleri = lambda sayfalar, meta, atla=None: (meta, [])
        try:
            sk.kirpma_plani_meta(
                [_SahteSayfa(), _SahteSayfa(), _SahteSayfa()],
                "karisik", cevap_disla=True, rapor=rapor)
        finally:
            sk._belge_sayfa_rolleri = eski_rol
            sk._cevap_sayfasi_mi = eski_cevap
            sk.sorulari_tespit_meta = eski_tespit
            sk.test_bolumleri = eski_bolum
        self.assertEqual([1], rapor["dislanan_sayfalar"])

    def test_rapor_verilmezse_eski_davranis_korunur(self):
        # Altı çağrı yeri raporu geçmiyor; hiçbiri bozulmamalı.
        eski_rol = sk._belge_sayfa_rolleri
        eski_tespit = sk.sorulari_tespit_meta
        eski_bolum = sk.test_bolumleri
        sk._belge_sayfa_rolleri = lambda s, k="legacy", *, fmt: (set(), None)
        sk.sorulari_tespit_meta = lambda s, fmt: ([], [(0.0, 600.0)], fmt)
        sk.test_bolumleri = lambda sayfalar, meta, atla=None: (meta, [])
        try:
            sonuc = sk.kirpma_plani_meta([_SahteSayfa()], "karisik")
        finally:
            sk._belge_sayfa_rolleri = eski_rol
            sk.sorulari_tespit_meta = eski_tespit
            sk.test_bolumleri = eski_bolum
        self.assertEqual(3, len(sonuc))

if __name__ == "__main__":
    unittest.main()
