"""V3 yerel DOCX→PDF girdi katmanı regresyon testleri."""

import hashlib
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

import fitz

import docx_girdi as dg


def _gecerli_pdf_baytlari():
    belge = fitz.open()
    try:
        belge.new_page()
        return belge.tobytes()
    finally:
        belge.close()


GECERLI_PDF = _gecerli_pdf_baytlari()


def _docx_yaz(yol, metin="soru"):
    """Dönüştürücü mock'u için asgari, yapısal olarak geçerli DOCX paketi."""
    with zipfile.ZipFile(str(yol), "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("[Content_Types].xml", "<Types/>")
        paket.writestr(
            "word/document.xml",
            ("<w:document xmlns:w='urn:test'><w:body><w:p><w:r><w:t>"
             + metin
             + "</w:t></w:r></w:p></w:body></w:document>"))


class DocxGirdiV3Testi(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory(
            prefix="soru_kesici_docx_v3_test_")
        self.kok = Path(self.gecici.name)
        self.kaynak = self.kok / "Özgün Sınav.docx"
        self.cache = self.kok / "cache"
        _docx_yaz(self.kaynak)

    def tearDown(self):
        self.gecici.cleanup()

    @staticmethod
    def _basarili_donusum(komut, **_kwargs):
        cikti = Path(komut[komut.index("--outdir") + 1])
        (cikti / "girdi.pdf").write_bytes(GECERLI_PDF)
        return subprocess.CompletedProcess(komut, 0, "convert edildi", "")

    def test_kaynak_metadata_korunur_ve_ikinci_cagri_cache_kullanir(self):
        with mock.patch.object(dg, "soffice_bul", return_value="/sahte/soffice"), \
                mock.patch.object(
                    dg, "_soffice_surumu", return_value="LibreOffice 25.2"), \
                mock.patch.object(
                    dg.subprocess, "run", side_effect=self._basarili_donusum
                ) as calistir:
            ilk = dg.docx_pdf_hazirla(str(self.kaynak), str(self.cache))
            ikinci = dg.docx_pdf_hazirla(str(self.kaynak), str(self.cache))

        beklenen_sha = hashlib.sha256(self.kaynak.read_bytes()).hexdigest()
        self.assertEqual(os.path.abspath(str(self.kaynak)), ilk.kaynak_yolu)
        self.assertEqual("Özgün Sınav.docx", ilk.kaynak_adi)
        self.assertEqual(beklenen_sha, ilk.kaynak_sha256)
        self.assertTrue(ilk.onbellek_anahtari.startswith(beklenen_sha + "-"))
        self.assertEqual(self.kaynak.stat().st_size, ilk.kaynak_boyutu)
        self.assertEqual("LibreOffice 25.2", ilk.donusturucu_surumu)
        self.assertEqual(dg.DOCX_DONUSUM_SURUMU, ilk.donusum_surumu)
        self.assertFalse(ilk.onbellekten)
        self.assertTrue(ikinci.onbellekten)
        self.assertEqual(ilk.pdf_yolu, ikinci.pdf_yolu)
        self.assertEqual(ilk.onbellek_anahtari, ikinci.onbellek_anahtari)
        self.assertEqual(GECERLI_PDF, Path(ilk.pdf_yolu).read_bytes())
        self.assertEqual(1, calistir.call_count)
        self.assertEqual("Özgün Sınav.docx", ilk.sozluk()["kaynak_adi"])

        komut = calistir.call_args.args[0]
        self.assertIn("--headless", komut)
        self.assertIn("pdf:writer_pdf_Export", komut)
        self.assertTrue(any(
            parca.startswith("-env:UserInstallation=file://")
            for parca in komut))

    def test_donusturucu_surumu_cache_anahtarini_degistirir(self):
        with mock.patch.object(dg, "soffice_bul", return_value="/sahte/soffice"), \
                mock.patch.object(dg.subprocess, "run",
                                  side_effect=self._basarili_donusum):
            with mock.patch.object(
                    dg, "_soffice_surumu", return_value="LibreOffice 24.8"):
                eski = dg.docx_pdf_hazirla(
                    str(self.kaynak), str(self.cache))
            with mock.patch.object(
                    dg, "_soffice_surumu", return_value="LibreOffice 25.2"):
                yeni = dg.docx_pdf_hazirla(
                    str(self.kaynak), str(self.cache))

        self.assertEqual(eski.kaynak_sha256, yeni.kaynak_sha256)
        self.assertNotEqual(eski.onbellek_anahtari, yeni.onbellek_anahtari)
        self.assertNotEqual(eski.pdf_yolu, yeni.pdf_yolu)

    def test_bos_ve_bozuk_docx_donusturucuden_once_reddedilir(self):
        bos = self.kok / "bos.docx"
        bos.write_bytes(b"")
        bozuk = self.kok / "bozuk.docx"
        bozuk.write_bytes(b"bu bir ZIP paketi degil")
        eksik = self.kok / "eksik.docx"
        with zipfile.ZipFile(str(eksik), "w") as paket:
            paket.writestr("word/document.xml", "<w:document/>")
        gecersiz_xml = self.kok / "gecersiz-xml.docx"
        with zipfile.ZipFile(str(gecersiz_xml), "w") as paket:
            paket.writestr("[Content_Types].xml", "<Types/>")
            paket.writestr("word/document.xml", "<w:document>")

        with mock.patch.object(dg, "soffice_bul") as bul:
            with self.assertRaisesRegex(dg.DocxGirdiHatasi, "boş"):
                dg.docx_pdf_hazirla(str(bos), str(self.cache))
            with self.assertRaisesRegex(
                    dg.DocxGirdiHatasi, "bozuk veya geçersiz"):
                dg.docx_pdf_hazirla(str(bozuk), str(self.cache))
            with self.assertRaisesRegex(
                    dg.DocxGirdiHatasi, "zorunlu içerik eksik"):
                dg.docx_pdf_hazirla(str(eksik), str(self.cache))
            with self.assertRaisesRegex(
                    dg.DocxGirdiHatasi, "geçersiz XML"):
                dg.docx_pdf_hazirla(str(gecersiz_xml), str(self.cache))
            bul.assert_not_called()

    def test_soffice_yokken_acik_kurulum_hatasi_verir(self):
        olmayan = self.kok / "LibreOffice-yok" / "soffice"
        with mock.patch.dict(os.environ, {dg.SOFFICE_ENV: ""}), \
                mock.patch.object(dg.shutil, "which", return_value=None), \
                mock.patch.object(dg, "SOFFICE_MAC_YOLU", str(olmayan)):
            with self.assertRaisesRegex(
                    dg.SofficeBulunamadiHatasi,
                    "LibreOffice.*kurun.*SORU_KESICI_SOFFICE"):
                dg.docx_pdf_hazirla(str(self.kaynak), str(self.cache))

    def test_donusturucu_hatasi_sessiz_fallback_yapmaz(self):
        basarisiz = subprocess.CompletedProcess(
            ["soffice"], 2, "", "Error: source file could not be loaded")
        with mock.patch.object(dg, "soffice_bul", return_value="/sahte/soffice"), \
                mock.patch.object(
                    dg, "_soffice_surumu", return_value="LibreOffice 25.2"), \
                mock.patch.object(dg.subprocess, "run", return_value=basarisiz):
            with self.assertRaisesRegex(
                    dg.DocxDonusumHatasi,
                    "PDF'ye dönüştürülemedi.*source file could not be loaded"):
                dg.docx_pdf_hazirla(str(self.kaynak), str(self.cache))

    def test_sifir_koduyla_ciksa_da_pdf_uretmediyse_hata_verir(self):
        yalanci_basarili = subprocess.CompletedProcess(
            ["soffice"], 0, "convert edildi", "")
        with mock.patch.object(dg, "soffice_bul", return_value="/sahte/soffice"), \
                mock.patch.object(
                    dg, "_soffice_surumu", return_value="LibreOffice 25.2"), \
                mock.patch.object(
                    dg.subprocess, "run", return_value=yalanci_basarili):
            with self.assertRaisesRegex(
                    dg.DocxDonusumHatasi, "geçerli bir PDF üretmedi"):
                dg.docx_pdf_hazirla(str(self.kaynak), str(self.cache))

    def test_ortam_degiskeni_path_ve_mac_adaylarindan_once_gelir(self):
        sahte = self.kok / "ozel-soffice"
        sahte.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        sahte.chmod(0o700)
        with mock.patch.dict(os.environ, {dg.SOFFICE_ENV: str(sahte)}), \
                mock.patch.object(dg.shutil, "which",
                                  return_value="/baska/soffice"):
            self.assertEqual(str(sahte.resolve()), dg.soffice_bul())

    def test_ortam_yokken_once_path_sonra_macos_uygulamasi_aranir(self):
        path_soffice = self.kok / "path-soffice"
        mac_soffice = self.kok / "mac-soffice"
        for aday in (path_soffice, mac_soffice):
            aday.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            aday.chmod(0o700)
        with mock.patch.dict(os.environ, {dg.SOFFICE_ENV: ""}), \
                mock.patch.object(dg.shutil, "which",
                                  return_value=str(path_soffice)), \
                mock.patch.object(dg, "SOFFICE_MAC_YOLU", str(mac_soffice)):
            self.assertEqual(str(path_soffice.resolve()), dg.soffice_bul())
        with mock.patch.dict(os.environ, {dg.SOFFICE_ENV: ""}), \
                mock.patch.object(dg.shutil, "which", return_value=None), \
                mock.patch.object(dg, "SOFFICE_MAC_YOLU", str(mac_soffice)):
            self.assertEqual(str(mac_soffice.resolve()), dg.soffice_bul())

    def test_hatalı_ortam_degiskeni_sessizce_path_surumune_gecmez(self):
        olmayan = self.kok / "olmayan-soffice"
        with mock.patch.dict(os.environ, {dg.SOFFICE_ENV: str(olmayan)}), \
                mock.patch.object(dg.shutil, "which",
                                  return_value="/baska/soffice"):
            with self.assertRaisesRegex(
                    dg.SofficeBulunamadiHatasi, dg.SOFFICE_ENV):
                dg.soffice_bul()


if __name__ == "__main__":
    unittest.main()
