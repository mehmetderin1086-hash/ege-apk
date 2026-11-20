#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Belirli sayfaları kırmızı soru kutularıyla render eder (görsel denetim)."""
import sys
import soru_kes as sk


def main():
    yol = sys.argv[1]
    sayfa_no = [int(x) for x in sys.argv[2].split(",")]  # 1-tabanlı
    cikti_on = sys.argv[3]
    sayfalar, acik, fmt, _sx = sk.belge_hazirla([yol], 300)
    try:
        for no in sayfa_no:
            s = sayfalar[no - 1]
            kutular = sk.sorulari_tespit(s, fmt)
            gorsel = sk.onizleme_gorseli(s, kutular)
            yol_c = "%s_s%02d.png" % (cikti_on, no)
            gorsel.save(yol_c)
            print("%s  kutu=%d" % (yol_c, len(kutular)))
    finally:
        sk.belge_kapat(acik)


if __name__ == "__main__":
    main()
