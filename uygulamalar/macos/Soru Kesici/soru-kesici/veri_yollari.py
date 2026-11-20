#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — kalıcı veri ve önbellek köklerini platforma göre çözer.

macOS'ta uygulama standardı (~/Library/Application Support, ~/Library/Caches)
korunur; Windows'ta karşılığı %LOCALAPPDATA%\\SoruKesici'dir. ``~/.soru_kesici.json``
ayar dosyası bu modülün DIŞINDA kalır — home tabanlı olduğundan Windows'ta da
olduğu gibi çalışır, taşınmasına gerek yok.
"""
import os

_VERI_ENV = "SORU_KESICI_VERI"
_CACHE_ENV = "SORU_KESICI_CACHE"


def _windows_yerel_temel():
    temel = (os.environ.get("LOCALAPPDATA") or "").strip()
    return temel or os.path.expanduser(r"~\AppData\Local")


def veri_koku():
    """Kalıcı veri kökü (db, medya, geçmiş, indirilmiş model ağırlıkları).

    Öncelik: SORU_KESICI_VERI env > platform varsayılanı
    (macOS/Linux: ~/Library/Application Support/soru-kesici,
     Windows: %LOCALAPPDATA%\\SoruKesici)."""
    env = os.environ.get(_VERI_ENV, "").strip()
    if env:
        return os.path.expanduser(env)
    if os.name == "nt":
        return os.path.join(_windows_yerel_temel(), "SoruKesici")
    return os.path.expanduser("~/Library/Application Support/soru-kesici")


def onbellek_koku():
    """Yeniden üretilebilir önbellek kökü (OCR/düzen/optik/docx cache'leri).

    Öncelik: SORU_KESICI_CACHE env > platform varsayılanı
    (macOS/Linux: ~/Library/Caches/soru-kesici,
     Windows: %LOCALAPPDATA%\\SoruKesici\\cache)."""
    env = os.environ.get(_CACHE_ENV, "").strip()
    if env:
        return os.path.expanduser(env)
    if os.name == "nt":
        return os.path.join(_windows_yerel_temel(), "SoruKesici", "cache")
    return os.path.expanduser("~/Library/Caches/soru-kesici")
