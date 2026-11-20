#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ml_kutu_esle birim testleri — sentetik kutular, model GEREKTİRMEZ.

Çalıştırma: .venv/bin/python test_duzen_esle.py
"""
import soru_kes as sk

G, Y = 600, 800   # sayfa (punto)

# 2 sütun × 2 soru: numara satır bbox'ları
NUMS = [(1, (30, 100, 50, 115)), (2, (30, 400, 50, 415)),
        (3, (320, 100, 340, 115)), (4, (320, 400, 340, 415))]


def b(sinif, kutu, guven=0.8):
    return {"sinif": sinif, "kutu": list(kutu), "guven": guven}


def main():
    assert sk.duzen_model is not None, "duzen_model import edilemedi"

    # --- tam eşleşme: 4 soru, gövde + şekil birleşimi -------------------
    bolgeler = [
        b("plain text", (25, 120, 280, 250)),
        b("figure", (60, 260, 250, 380), 0.9),
        b("plain text", (25, 420, 280, 600)),
        b("plain text", (315, 120, 580, 300), 0.7),
        b("figure", (330, 420, 570, 700), 0.9),
        b("abandon", (25, 700, 580, 790), 0.9),      # sınıf dışı → yok say
        b("plain text", (25, 130, 280, 240), 0.2),   # düşük güven → yok say
        b("figure", (400, 150, 420, 160), 0.9),      # minik → alan eşiği
    ]
    sonuc = sk.ml_kutu_esle(NUMS, bolgeler, G, Y)
    assert sonuc is not None, "eşleşme None döndü"
    assert len(sonuc) == 4, f"4 kutu beklendi, {len(sonuc)} geldi"
    kutular = [k for k, _ in sonuc]
    # okuma sırası: sütun 0 (1, 2), sütun 1 (3, 4)
    assert sonuc[0][1] == NUMS[0][1] and sonuc[1][1] == NUMS[1][1] \
        and sonuc[2][1] == NUMS[2][1] and sonuc[3][1] == NUMS[3][1], \
        "okuma sırası sütun→yukarı değil"
    # soru 1: numara + metin + şekil birleşimi
    assert kutular[0] == (25, 100, 280, 380), f"s1 birleşim: {kutular[0]}"
    # soru 4: numara + şekil
    assert kutular[3] == (320, 400, 570, 700), f"s4 birleşim: {kutular[3]}"

    # --- sonraki çapayı yutamaz: bölge 2. numaranın altına taşıyor ------
    tasan = [b("plain text", (25, 120, 280, 500)),       # n1'e ait, 400'ü aşar
             b("plain text", (25, 420, 280, 600)),
             b("plain text", (315, 120, 580, 300)),
             b("figure", (330, 420, 570, 700))]
    sonuc2 = sk.ml_kutu_esle(NUMS, tasan, G, Y)
    assert sonuc2 is not None
    k1 = sonuc2[0][0]
    assert k1[3] <= 400 - 2 + 1e-6, f"s1 kutusu 2. çapayı yuttu: {k1}"

    # --- %70 eşiği: 4 numaradan yalnız 2'si eşleşirse None --------------
    az = [b("plain text", (25, 120, 280, 250)),
          b("plain text", (315, 120, 580, 300))]
    assert sk.ml_kutu_esle(NUMS, az, G, Y) is None, "%70 eşiği çalışmadı"

    # --- <2 numara → None ------------------------------------------------
    assert sk.ml_kutu_esle(NUMS[:1], bolgeler, G, Y) is None

    # --- hiç geçerli bölge yok → None ------------------------------------
    assert sk.ml_kutu_esle(NUMS, [b("abandon", (25, 120, 280, 250))],
                           G, Y) is None

    print("TAMAM (5 senaryo)")


if __name__ == "__main__":
    main()
