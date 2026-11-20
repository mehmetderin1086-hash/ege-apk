#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — ortak Türkçe TrueType yardımcıları.

fitz (sinav_pdf, belge_disa) ve PIL (cevap bandı) aynı font zincirini
paylaşır: base-14 "helv" ş/ğ/İ içermediğinden sistem TTF'i şarttır.
"""

import os
from functools import lru_cache

# Çeşitli macOS kurulumlarında en az biri bulunsun diye geniş tutuldu.
TTF_ADAYLARI = [
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/Library/Fonts/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
    "/System/Library/Fonts/Supplemental/Verdana.ttf",
    "/System/Library/Fonts/Supplemental/Tahoma.ttf",
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    "/Library/Fonts/Arial Unicode.ttf",
]

_WINDIR = os.environ.get("WINDIR")
if _WINDIR:
    _WIN_FONTS = os.path.join(_WINDIR, "Fonts")
    TTF_ADAYLARI += [
        os.path.join(_WIN_FONTS, "arial.ttf"),
        os.path.join(_WIN_FONTS, "calibri.ttf"),
        os.path.join(_WIN_FONTS, "segoeui.ttf"),
    ]


def ttf_yolu():
    """Türkçe destekli sistem TrueType yolu | None (→ çağıran yedeğine düşer)."""
    for yol in TTF_ADAYLARI:
        if os.path.exists(yol) and yol.endswith(".ttf"):
            return yol
    return None


@lru_cache(maxsize=16)
def pil_font(boyut):
    """PIL ImageFont (Türkçe glifli). TTF yoksa bitmap varsayılana düşer —
    Türkçe glifler bozulabilir ama çizim asla patlamaz (sinav_pdf'in
    'helv' yedeğiyle aynı felsefe)."""
    from PIL import ImageFont
    yol = ttf_yolu()
    if yol:
        try:
            return ImageFont.truetype(yol, int(boyut))
        except OSError:
            pass
    return ImageFont.load_default()
