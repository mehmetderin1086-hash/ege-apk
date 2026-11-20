import io
import json
import unittest
import zipfile
from unittest.mock import patch

import soru_kes_web as web


class OgretmenApiV1Test(unittest.TestCase):
    @patch("soru_bankasi.banka_gorsel", return_value=b"\x89PNG\r\n\x1a\n")
    @patch("soru_bankasi.banka_kayit")
    def test_soru_paketi_surumlu_manifest_tasir(self, kayit, _gorsel):
        kayit.return_value = {
            "id": 7,
            "icerik_hash": "abc",
            "metin": "Hücre zarını açıklayınız.",
            "govde": "",
            "etiketler": {"sinif": "9", "kazanim": "BİY.9.1.1"},
            "zorluk": "orta",
            "kaynak": "kitap.pdf",
            "sayfa": 12,
            "inceleme_durumu": "onayli",
        }
        icerik = web._soru_paketi([7])
        with zipfile.ZipFile(io.BytesIO(icerik)) as paket:
            manifest = json.loads(paket.read("manifest.json"))
            self.assertEqual(manifest["protocol_version"], "v1")
            self.assertEqual(manifest["source_app"], "soru-kesici")
            self.assertEqual(manifest["questions"][0]["external_id"], "bank:7:abc")
            self.assertIn("images/7.png", paket.namelist())


if __name__ == "__main__":
    unittest.main()
