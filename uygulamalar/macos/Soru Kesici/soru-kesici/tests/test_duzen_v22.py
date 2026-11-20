import os
import tempfile
import unittest

from PIL import Image

import duzen_isci


class _Kutu:
    def __init__(self, xyxy, sinif=0, guven=.8):
        self.xyxy = [xyxy]
        self.cls = sinif
        self.conf = guven


class _Sonuc:
    names = {0: "plain text"}

    def __init__(self, kutular):
        self.boxes = [_Kutu(k) for k in kutular]


class _Model:
    def __init__(self):
        self.cagri = 0

    def predict(self, _girdi, **_):
        self.cagri += 1
        # Global görüş belirsiz (<6 gövde); iki yerel görüş ayrı bölgeler bulur.
        if self.cagri == 1:
            return [_Sonuc([(100, 100, 500, 250)])]
        return [_Sonuc([(120, 120, 620, 300), (120, 500, 620, 680)])]


class _Ayar:
    imgsz = 1024
    conf = .2


class DuzenIsciV22Testi(unittest.TestCase):
    def test_belirsiz_buyuk_sayfa_globalden_yerele_ikinci_gecis_yapar(self):
        fd, yol = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        try:
            Image.new("RGB", (1600, 2400), "white").save(yol)
            model = _Model()
            bolgeler = duzen_isci._tahmin(model, yol, _Ayar(), "cpu")
        finally:
            os.unlink(yol)
        self.assertEqual(3, model.cagri)
        self.assertTrue(any(str(b.get("olcek")).startswith("yerel_")
                            for b in bolgeler))
        self.assertTrue(all(len(b["kutu"]) == 4 for b in bolgeler))


if __name__ == "__main__":
    unittest.main()
