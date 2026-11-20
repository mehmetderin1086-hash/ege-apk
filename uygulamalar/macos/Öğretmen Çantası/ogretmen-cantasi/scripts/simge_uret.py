"""Uygulama simgesini üretir (assets/ogretmen-cantasi-icon.png).

Simge depoya işlenir; bu betik yalnız yeniden üretmek gerektiğinde koşulur.
Çizim PyMuPDF ile yapılıyor — projede zaten kurulu, ek bağımlılık gerekmiyor.

Biçim: yuvarlatılmış kare zemin üzerine iki sarmal ve aralarındaki bağ
çizgileri (DNA). Biyoloji dersini tek bakışta anlatıyor ve küçük boyutlarda
(16 px) da ayırt edilebilecek kadar sade.
"""

from __future__ import annotations

import math
from pathlib import Path

import pymupdf

PROJE = Path(__file__).resolve().parents[1]
HEDEF = PROJE / "assets/ogretmen-cantasi-icon.png"
BOYUT = 1024

ZEMIN = (0.106, 0.361, 0.545)  # koyu mavi, arayüzdeki vurgu rengiyle akraba
SARMAL = (1.0, 1.0, 1.0)
BAG = (0.80, 0.90, 0.98)


def cizim() -> pymupdf.Document:
    belge = pymupdf.open()
    sayfa = belge.new_page(width=BOYUT, height=BOYUT)

    kenar = BOYUT * 0.055
    cerceve = pymupdf.Rect(kenar, kenar, BOYUT - kenar, BOYUT - kenar)
    sayfa.draw_rect(cerceve, color=None, fill=ZEMIN, radius=0.22)

    ust, alt = BOYUT * 0.20, BOYUT * 0.80
    orta = BOYUT / 2
    genlik = BOYUT * 0.17
    adim = 90

    def sarmal_noktalari(faz: float) -> list[pymupdf.Point]:
        noktalar = []
        for i in range(adim + 1):
            oran = i / adim
            y = ust + (alt - ust) * oran
            x = orta + genlik * math.sin(2 * math.pi * 1.6 * oran + faz)
            noktalar.append(pymupdf.Point(x, y))
        return noktalar

    sol, sag = sarmal_noktalari(0.0), sarmal_noktalari(math.pi)

    # Bağ çizgileri önce çizilir ki sarmallar üstte kalsın.
    for i in range(6, adim - 5, 12):
        sayfa.draw_line(sol[i], sag[i], color=BAG, width=BOYUT * 0.022)

    for sarmal in (sol, sag):
        cizici = sayfa.new_shape()
        cizici.draw_polyline(sarmal)
        cizici.finish(color=SARMAL, width=BOYUT * 0.045, closePath=False, lineCap=1, lineJoin=1)
        cizici.commit()

    return belge


def main() -> int:
    belge = cizim()
    HEDEF.parent.mkdir(parents=True, exist_ok=True)
    belge[0].get_pixmap(alpha=False).save(HEDEF)
    belge.close()
    print(f"Yazıldı: {HEDEF}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
