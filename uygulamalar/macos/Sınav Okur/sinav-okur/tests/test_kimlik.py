import cv2
import numpy as np

from sinav_okur.htr import YapayTaniyici
from sinav_okur.kimlik import kimlik_bilgisi_oku


def test_kagit_ust_bilgisinden_ad_soyad_numara_sinif_sube_cikarir():
    sayfa = np.full((1000, 700, 3), 255, np.uint8)
    okuma = YapayTaniyici(
        "BEYKOZ CUMHURİYET ANADOLU LİSESİ 9. SINIFLAR SINAVI\n"
        "Adı Soyadı: Ece Kara\n"
        "Sınıfı / No: 9/A 122\n"
        "Tarih: 24.07.2026",
        0.94,
    )

    kimlik = kimlik_bilgisi_oku([sayfa], okuma, 300)

    assert kimlik["ad"] == "Ece"
    assert kimlik["soyad"] == "Kara"
    assert kimlik["numara"] == "122"
    assert kimlik["sinif"] == "9"
    assert kimlik["sube"] == "A"
    assert "okul" in kimlik["ek_alanlar"]
    assert kimlik["incele"] is True  # tek OCR görüşü öğretmen doğrulaması ister
