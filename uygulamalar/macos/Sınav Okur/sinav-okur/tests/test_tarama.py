"""İşaretçisiz yazılıların PDF/görüntü sayfası okuma testleri."""

import numpy as np
import pytest

cv2 = pytest.importorskip("cv2")

def test_ayri_gorseller_tek_ogrencinin_sayfalari_olarak_birlesir(tmp_path):
    from sinav_okur.tarama import dosyalar_sayfalari

    bir = tmp_path / "sayfa1.png"
    iki = tmp_path / "sayfa2.png"
    cv2.imwrite(str(bir), np.full((120, 90, 3), 240, np.uint8))
    cv2.imwrite(str(iki), np.full((140, 100, 3), 220, np.uint8))

    sayfalar = dosyalar_sayfalari([bir, iki], dpi=200)

    assert len(sayfalar) == 2
    assert sayfalar[0].shape[:2] == (120, 90)
    assert sayfalar[1].shape[:2] == (140, 100)


@pytest.mark.parametrize("uzanti", [".bmp", ".webp"])
def test_ek_goruntu_bicimleri_okunur(tmp_path, uzanti):
    from sinav_okur.tarama import dosya_sayfalari

    yol = tmp_path / f"kagit{uzanti}"
    assert cv2.imwrite(str(yol), np.full((160, 110, 3), 235, np.uint8))

    sayfalar = dosya_sayfalari(yol, dpi=200, azami_sayfa=4)

    assert len(sayfalar) == 1
    assert sayfalar[0].shape[:2] == (160, 110)


def test_bozuk_pdf_acik_hatayla_reddedilir(tmp_path):
    from sinav_okur.tarama import dosya_sayfalari

    yol = tmp_path / "bozuk.pdf"
    yol.write_bytes(b"bu bir pdf degil")

    with pytest.raises(ValueError, match="PDF açılamadı"):
        dosya_sayfalari(yol, dpi=200, azami_sayfa=4)


def test_iphone_heic_fotografi_yerel_okunur(tmp_path):
    import subprocess
    from pathlib import Path

    from sinav_okur.tarama import dosya_sayfalari

    sips = Path("/usr/bin/sips")
    if not sips.is_file():
        pytest.skip("macOS sips bulunamadı")
    png = tmp_path / "kaynak.png"
    heic = tmp_path / "kagit.heic"
    assert cv2.imwrite(str(png), np.full((180, 120, 3), 225, np.uint8))
    donusum = subprocess.run(
        [
            str(sips),
            "-s",
            "format",
            "heic",
            str(png),
            "--out",
            str(heic),
        ],
        capture_output=True,
    )
    if donusum.returncode != 0:
        pytest.skip("Bu macOS sürümü HEIC test dosyası üretemedi")

    sayfalar = dosya_sayfalari(heic, dpi=200, azami_sayfa=4)

    assert len(sayfalar) == 1
    assert sayfalar[0].shape[:2] == (180, 120)


def test_cok_sayfali_tiff_tek_yuklemede_acilir(tmp_path):
    from PIL import Image

    from sinav_okur.tarama import dosya_sayfalari

    yol = tmp_path / "on-arka.tiff"
    on = Image.fromarray(np.full((130, 90, 3), 230, np.uint8))
    arka = Image.fromarray(np.full((150, 100, 3), 210, np.uint8))
    on.save(yol, save_all=True, append_images=[arka])

    sayfalar = dosya_sayfalari(yol, dpi=200, azami_sayfa=4)

    assert [sayfa.shape[:2] for sayfa in sayfalar] == [(130, 90), (150, 100)]
