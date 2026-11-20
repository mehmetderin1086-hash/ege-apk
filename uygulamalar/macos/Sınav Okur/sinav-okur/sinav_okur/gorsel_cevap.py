"""Grafik, tablo ve çizim cevaplarında yerel yapısal görüntü özellikleri."""

from __future__ import annotations

import cv2
import numpy as np

from .modeller import SoruTipi


def gorsel_cevabi_incele(goruntu: np.ndarray, tip: SoruTipi) -> dict:
    if goruntu is None or not goruntu.size:
        return {"tip": tip.value, "algilandi": False, "neden": "Görüntü yok"}
    gri = cv2.cvtColor(goruntu, cv2.COLOR_BGR2GRAY)
    kenar = cv2.Canny(gri, 60, 160)
    min_uzunluk = max(20, min(gri.shape) // 8)
    cizgiler = cv2.HoughLinesP(
        kenar,
        1,
        np.pi / 180,
        threshold=max(20, min_uzunluk // 2),
        minLineLength=min_uzunluk,
        maxLineGap=12,
    )
    yatay = dikey = capraz = 0
    if cizgiler is not None:
        # OpenCV 4.x çıktısı (N, 1, 4), 5.x çıktısı (N, 4) — ikisini de düzle.
        for x1, y1, x2, y2 in np.asarray(cizgiler).reshape(-1, 4):
            aci = abs(np.degrees(np.arctan2(y2 - y1, x2 - x1)))
            if aci <= 12 or aci >= 168:
                yatay += 1
            elif 78 <= aci <= 102:
                dikey += 1
            else:
                capraz += 1
    konturlar, _ = cv2.findContours(kenar, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    buyuk_bilesen = sum(
        1 for k in konturlar if cv2.contourArea(k) >= max(30, gri.size * 0.0001)
    )
    koyu_oran = float(np.mean(gri < 190))
    if tip == SoruTipi.GRAFIK:
        algilandi = yatay >= 1 and dikey >= 1 and (capraz >= 1 or buyuk_bilesen >= 2)
        neden = (
            "Yatay/dikey eksen ve veri izi algılandı."
            if algilandi else "Eksen veya veri eğrisi güvenle algılanamadı."
        )
    elif tip == SoruTipi.TABLO:
        algilandi = yatay >= 2 and dikey >= 2
        neden = (
            "Satır ve sütun çizgileri algılandı."
            if algilandi else "Tablo ızgarası güvenle algılanamadı."
        )
    else:
        algilandi = buyuk_bilesen >= 2 and koyu_oran > 0.002
        neden = (
            "Birden çok çizim bileşeni algılandı."
            if algilandi else "Çizim yapısı güvenle algılanamadı."
        )
    return {
        "tip": tip.value,
        "algilandi": bool(algilandi),
        "yatay_cizgi": yatay,
        "dikey_cizgi": dikey,
        "capraz_cizgi": capraz,
        "bilesen": buyuk_bilesen,
        "koyu_oran": round(koyu_oran, 5),
        "neden": neden,
    }

