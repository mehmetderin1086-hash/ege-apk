"""veri/fontlar: font cmap'inden Türkçe karakter kapsamı denetimi.

fontTools zaten çekirdek bağımlılık; test mini TTF'leri FontBuilder ile üretir.
"""
import pytest

pytest.importorskip("fontTools")
from fontTools.fontBuilder import FontBuilder

from sinav_okur.veri.fontlar import (
    ZORUNLU_KARAKTERLER,
    eksik_karakterler,
    fontlari_dogrula,
    turkce_uygun_mu,
)


def _mini_ttf(yol, karakterler):
    """Verilen karakter kümesini cmap'ine koyan asgari geçerli TTF üretir."""
    glyph_order = [".notdef"] + [f"g{ord(ch)}" for ch in karakterler]
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap({ord(ch): f"g{ord(ch)}" for ch in karakterler})
    from fontTools.ttLib.tables._g_l_y_f import Glyph

    glyfs = {ad: Glyph() for ad in glyph_order}
    fb.setupGlyf(glyfs)
    fb.setupHorizontalMetrics({ad: (500, 0) for ad in glyph_order})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "Test", "styleName": "Regular"})
    fb.setupOS2()
    fb.setupPost()
    fb.save(str(yol))


def test_tam_kapsamli_font_uygun(tmp_path):
    yol = tmp_path / "tam.ttf"
    _mini_ttf(yol, ZORUNLU_KARAKTERLER)
    assert eksik_karakterler(yol) == []
    assert turkce_uygun_mu(yol) is True


def test_eksik_karakterli_font_yakalanir(tmp_path):
    yol = tmp_path / "eksik.ttf"
    # ğ ve İ hariç her şey
    kapsam = ZORUNLU_KARAKTERLER.replace("ğ", "").replace("İ", "")
    _mini_ttf(yol, kapsam)
    eksik = eksik_karakterler(yol)
    assert "ğ" in eksik and "İ" in eksik
    assert turkce_uygun_mu(yol) is False


def test_fontlari_dogrula_dizin_tarar(tmp_path):
    _mini_ttf(tmp_path / "tam.ttf", ZORUNLU_KARAKTERLER)
    _mini_ttf(tmp_path / "eksik.ttf", ZORUNLU_KARAKTERLER.replace("ş", ""))
    rapor = fontlari_dogrula(tmp_path)
    assert len(rapor) == 2
    assert rapor[str(tmp_path / "tam.ttf")] == []
    assert "ş" in rapor[str(tmp_path / "eksik.ttf")]
