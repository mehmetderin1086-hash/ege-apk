"""Cevap kutusu içinde satır bölütleme (yatay projeksiyon profili).

Kutular dar ve tek sütun olduğu için projeksiyon profili güçlü bir taban
çizgisidir; alçalan/çıkan (descender/ascender) bitişmeleri için aşırı uzun
bantlar profil vadisinden ikiye bölünür.
"""

from __future__ import annotations

import cv2
import numpy as np

def _mm2px(mm: float, dpi: int) -> float:
    return mm * dpi / 25.4


def _ikilestir(kirp: np.ndarray) -> np.ndarray:
    gri = cv2.cvtColor(kirp, cv2.COLOR_BGR2GRAY) if kirp.ndim == 3 else kirp
    ikili = cv2.adaptiveThreshold(
        gri, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 15
    )
    # tek piksellik gürültüyü at
    return cv2.morphologyEx(ikili, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))


def _bantlari_bul(profil: np.ndarray, esik: float) -> list[tuple[int, int]]:
    murekkepli = profil > esik
    bantlar, basla = [], None
    for i, dolu in enumerate(murekkepli):
        if dolu and basla is None:
            basla = i
        elif not dolu and basla is not None:
            bantlar.append((basla, i))
            basla = None
    if basla is not None:
        bantlar.append((basla, len(murekkepli)))
    return bantlar


def _birlestir(bantlar: list[tuple[int, int]], min_aralik: int) -> list[tuple[int, int]]:
    if not bantlar:
        return []
    sonuc = [bantlar[0]]
    for b0, b1 in bantlar[1:]:
        s0, s1 = sonuc[-1]
        if b0 - s1 < min_aralik:
            sonuc[-1] = (s0, b1)
        else:
            sonuc.append((b0, b1))
    return sonuc


def _uzun_bandi_bol(
    profil: np.ndarray, bant: tuple[int, int], azami_h: int
) -> list[tuple[int, int]]:
    """Aşırı uzun bandı en derin profil vadisinden ikiye böler (özyinelemeli)."""
    b0, b1 = bant
    if b1 - b0 <= azami_h:
        return [bant]
    ic = profil[b0:b1]
    kenar = max(1, (b1 - b0) // 5)  # vadiyi bandın ortalarında ara
    orta = ic[kenar:-kenar]
    if orta.size == 0 or orta.min() > 0.4 * ic.mean():
        return [bant]  # belirgin vadi yok; bölme
    vadi = b0 + kenar + int(np.argmin(orta))
    return _uzun_bandi_bol(profil, (b0, vadi), azami_h) + _uzun_bandi_bol(
        profil, (vadi + 1, b1), azami_h
    )


def satirlara_bol(kirp: np.ndarray, dpi: int = 300) -> list[np.ndarray]:
    """Kutu kırpıntısını satır görüntülerine böler; boş kutuda [] döner."""
    if kirp.size == 0:
        return []
    ikili = _ikilestir(kirp)
    h, w = ikili.shape

    profil = ikili.sum(axis=1).astype(np.float64) / 255.0
    pencere = max(3, round(_mm2px(1.0, dpi)))
    profil = np.convolve(profil, np.ones(pencere) / pencere, mode="same")

    esik = max(2.0, 0.004 * w)
    bantlar = _birlestir(
        _bantlari_bul(profil, esik), min_aralik=round(_mm2px(1.3, dpi))
    )

    azami_h = round(_mm2px(13.0, dpi))
    bolunmus: list[tuple[int, int]] = []
    for bant in bantlar:
        bolunmus.extend(_uzun_bandi_bol(profil, bant, azami_h))

    min_h = round(_mm2px(1.5, dpi))
    pay = round(_mm2px(1.0, dpi))
    satirlar = []
    for b0, b1 in bolunmus:
        if b1 - b0 < min_h:
            continue
        y0, y1 = max(0, b0 - pay), min(h, b1 + pay)
        # satırın yatay kapsamını da kırp (boş kenar boşluklarını at)
        sutun = ikili[b0:b1].sum(axis=0)
        dolu = np.nonzero(sutun > 0)[0]
        if dolu.size == 0:
            continue
        x0, x1 = max(0, dolu[0] - pay), min(w, dolu[-1] + pay)
        satirlar.append(kirp[y0:y1, x0:x1])
    return satirlar
