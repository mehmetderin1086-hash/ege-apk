#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — ML işçi süreçlerinin (duzen_isci, ocr_isci, optik_isci) hangi
Python yorumlayıcısıyla başlatılacağını tek yerden çözer.

macOS/Linux'ta ağır bağımlılıklar (torch, easyocr, cv2 vb.) ana .venv'i
(Py3.9, stdlib-only istemciler) şişirmesin diye ayrı bir .venv-ml sanal
ortamında tutulur; işçiler her zaman o ortamın yorumlayıcısıyla başlatılır
(kurulu olup olmadığını her çağıran kendi os.path kontrolüyle anlar — bu
modül var/yok kararı VERMEZ, yalnız yolu döndürür). Windows paketinde ayrı
bir .venv-ml kurulumu yoktur; işçiler ana yorumlayıcıyla (sys.executable)
aynı süreç ailesinde çalışır.

Öncelik: SORU_KESICI_ISCI_PY ortam değişkeni > platforma göre varsayılan.
"""
import os
import sys

PROJE = os.path.dirname(os.path.abspath(__file__))


def isci_python():
    """ML işçi süreçlerini başlatacak Python yorumlayıcısının yolu.

    macOS/Linux'ta dönüş her zaman ``.venv-ml/bin/python`` sabitidir (mevcut
    davranışla birebir) — kurulu olup olmadığını çağıran kendi kontrol eder.
    """
    env = os.environ.get("SORU_KESICI_ISCI_PY", "").strip()
    if env:
        return env
    if os.name == "nt":
        return sys.executable
    return os.path.join(PROJE, ".venv-ml", "bin", "python")
