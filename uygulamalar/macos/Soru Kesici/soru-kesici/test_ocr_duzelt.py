#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""_ocr_tr_duzelt birim testleri (düz assert, framework yok).

Çalıştırma: .venv/bin/python test_ocr_duzelt.py

Girdilerdeki diakritik işaretler \\u kaçışlarıyla yazılır; görünmez
kombinasyon karakterleri düz literal olarak kaynakta tutulmaz.
"""
import unicodedata

import soru_kes as sk

# (girdi, beklenen, açıklama)
DURUMLAR = [
    ("DO˘GAL", "DOĞAL", "spacing breve taban harften önde"),
    ("DO\u0306GAL", "DOĞAL", "combining breve önceki sesliye yapışık"),
    ("D\u014EGAL", "DOĞAL", "hazır-bileşik artık Ŏ+G"),
    ("DO ˘GAL", "DOĞAL", "sözcük içi boşluk + işaret"),
    ("DO˘ GAL", "DOĞAL", "işaret sonrası boşluk"),
    ("BE¸SERİ", "BEŞERİ", "spacing cedilla"),
    ("BE\u0327SERİ", "BEŞERİ", "combining cedilla (NFC→Ȩ)"),
    ("AVU¸C", "AVUÇ", "cedilla + C"),
    ("˙I", "İ", "spacing üst nokta + I"),
    ("I\u0307", "İ", "combining üst nokta (NFC birleştirir)"),
    ("MÌLLÌ", "MİLLİ", "Ì→İ sözcük bağlamı"),
    ("Ìstanbul", "İstanbul", "Ì→İ sözcük başı"),
    ("¨Oğrenci", "Öğrenci", "spacing trema + O"),
    ("D¨UNYA", "DÜNYA", "sözcük içi trema + U"),
    ("GSYÌH", "GSYİH", "OCRTurk örneği: GSYÌH"),
    ("Ali'nin (2, 5) noktası.", "Ali'nin (2, 5) noktası.",
     "meşru noktalama dokunulmaz"),
    ("ışık", "ışık", "ı/i tahmini YOK"),
    ("Isparta", "Isparta", "I→İ tahmini YOK"),
    ("TAXÌ", "TAXÌ", "q/w/x'li sözcükte Ì korunur"),
    ("Ì", "Ì", "tek karakterlik Ì korunur (bağlam yok)"),
    ("A) 3 cm  B) 5 cm", "A) 3 cm  B) 5 cm", "şık satırı dokunulmaz"),
    ("", "", "boş girdi"),
]


def main():
    hata = 0
    for girdi, beklenen, aciklama in DURUMLAR:
        beklenen = unicodedata.normalize("NFC", beklenen)
        sonuc = sk._ocr_tr_duzelt(girdi)
        if sonuc != beklenen:
            hata += 1
            print(f"HATA [{aciklama}]: {girdi!r} → {sonuc!r}, "
                  f"beklenen {beklenen!r}")
        # idempotentlik: ikinci uygulama sonucu değiştirmemeli
        tekrar = sk._ocr_tr_duzelt(sonuc)
        if tekrar != sonuc:
            hata += 1
            print(f"HATA [idempotent değil, {aciklama}]: "
                  f"{sonuc!r} → {tekrar!r}")
        # onarılan girdilerde başıboş spacing işaret kalmamalı
        for isaretler, _ in sk._AKSAN_GRUPLARI:
            spacing = isaretler[0]
            if spacing in girdi and spacing in sonuc and girdi != beklenen:
                hata += 1
                print(f"HATA [artık işaret, {aciklama}]: "
                      f"{sonuc!r} içinde U+{ord(spacing):04X}")
    if hata:
        raise SystemExit(f"{hata} hata")
    print(f"TAMAM ({len(DURUMLAR)} durum)")


if __name__ == "__main__":
    main()
