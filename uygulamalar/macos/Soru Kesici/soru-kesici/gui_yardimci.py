#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici GUI — ortak yardımcılar.

IsYurutucu: tüm soru_kes çağrılarını TEK worker thread'inde sıraya sokar.
fitz belgeleri ve raster LRU önbelleği eşzamanlı erişime dayanıklı olmadığı
için GUI'nin her ağır işi (yükleme, özet, kesim, önizleme) buradan geçer.
Sonuçlar mevcut queue.Queue + after(100) deseniyle ana thread'e taşınır;
ImageTk üretimi HER ZAMAN ana thread'de yapılır.
"""

import queue
import threading

# Kutu renkleri — çekirdek inceleme paketiyle aynı dil (soru_kes.py
# _inceleme_bindirmesi): GUI editörü ile inceleme PNG'leri aynı anlamı taşır.
RENKLER = {
    "otomatik":   "#149B46",   # yeşil  — güvenli otomatik tespit
    "incele":     "#EB9114",   # turuncu — insan gözü istiyor
    "reddedildi": "#CD232D",   # kırmızı — çekirdek reddetti (çıktıya girmez)
    "secili":     "#007AFF",   # mavi   — kullanıcı seçimi (macOS vurgusu)
}


class IptalEdildi(Exception):
    """Kullanıcı 'Durdur'a bastı; ilerleme callback'inden fırlatılır."""


class IsYurutucu:
    """Tek daemon worker: işleri sırayla çalıştırır, sonucu UI kuyruğuna
    koyar.

    is_ver(fn, *args): fn worker thread'inde çağrılır. fn'nin kendisi
    sonucu ui_kuyruk'a koymaktan sorumludur (mesaj sözleşmesi GUI'de);
    yakalanmamış istisna ("hata", str) olarak, IptalEdildi ("iptal",)
    olarak kuyruğa düşer.

    iptal_et(): bekleyen işleri boşaltır ve iptal bayrağını kaldırır;
    çalışan iş bir sonraki ilerleme_kancasi() çağrısında IptalEdildi
    fırlatır. Bayrak yeni iş verildiğinde temizlenir.
    """

    def __init__(self, ui_kuyruk):
        self.ui_kuyruk = ui_kuyruk
        self._isler = queue.Queue()
        self._iptal = threading.Event()
        self._thread = threading.Thread(target=self._dongu, daemon=True)
        self._thread.start()

    # -------------------------------------------------------- genel API
    def is_ver(self, fn, *args):
        self._iptal.clear()
        self._isler.put((fn, args))

    def iptal_et(self):
        self._iptal.set()
        try:                        # kuyruğu boşalt: sıradakiler çalışmasın
            while True:
                self._isler.get_nowait()
        except queue.Empty:
            pass

    def ilerleme_kancasi(self):
        """Uzun döngülerin içinden (ilerleme callback'i) çağrılır."""
        if self._iptal.is_set():
            raise IptalEdildi()

    # -------------------------------------------------------- iç döngü
    def _dongu(self):
        while True:
            fn, args = self._isler.get()
            if self._iptal.is_set():
                continue            # iptal sonrası bayat iş: sessizce atla
            try:
                fn(*args)
            except IptalEdildi:
                self.ui_kuyruk.put(("iptal",))
            except Exception as e:  # noqa: BLE001 — worker asla ölmemeli
                self.ui_kuyruk.put(("hata", str(e)))
