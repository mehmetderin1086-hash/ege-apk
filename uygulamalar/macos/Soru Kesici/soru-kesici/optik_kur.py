#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik okuma kurulumu (isteğe bağlı özellik) — hafif profil.

Okuma motoru OpenCV gerektirir; ana .venv'e (3.9) DOKUNMADAN .venv-ml
kullanılır (duzen_kur ile paylaşılır). torch GEREKMEZ: yalnız
opencv-python-headless (~40 MB) kurulur. .venv-ml'de zaten cv2 varsa
(ör. duzen_kur kurduysa) hiçbir şey kurulmaz.

Kullanım: python3 optik_kur.py [--pasif]   (--pasif: ayarı açma)
"""
import json
import os
import subprocess
import sys

import duzen_kur

PROJE = os.path.dirname(os.path.abspath(__file__))
VENV = os.path.join(PROJE, ".venv-ml")
VENV_PY = os.path.join(VENV, "bin", "python")
ISCI_BETIK = os.path.join(PROJE, "optik_isci.py")
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")


def cv2_var_mi():
    if not os.path.isfile(VENV_PY):
        return False
    try:
        s = subprocess.run([VENV_PY, "-c", "import cv2"],
                           capture_output=True, timeout=60)
        return s.returncode == 0
    except Exception:  # noqa: BLE001
        return False


def kur():
    if cv2_var_mi():
        print(".venv-ml'de OpenCV zaten mevcut, kurulum atlanıyor")
        return
    if not os.path.isfile(VENV_PY):
        py = duzen_kur.python_bul() or duzen_kur.python_indir()
        print(f".venv-ml kuruluyor (taban: {py})")
        subprocess.run([py, "-m", "venv", VENV], check=True)
        subprocess.run([VENV_PY, "-m", "pip", "install", "--upgrade",
                        "pip", "--quiet"], check=True)
    print("  pip install opencv-python-headless (~40 MB)")
    subprocess.run([VENV_PY, "-m", "pip", "install",
                    "opencv-python-headless", "--quiet"], check=True)


def probe():
    print("işçi doğrulanıyor…")
    s = subprocess.run([VENV_PY, ISCI_BETIK, "--probe"],
                       capture_output=True, text=True, timeout=120)
    ilk = (s.stdout or "").strip().splitlines()
    durum = json.loads(ilk[0]) if ilk else {}
    if not durum.get("ok"):
        raise RuntimeError(durum.get("hata") or "işçi başlatılamadı")
    print(f"  hazır (cv2 {durum.get('cv2')})")


def ayar_aktif_et():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            ayar = json.load(f)
    except (OSError, ValueError):
        ayar = {}
    ayar["optik_aktif"] = True
    with open(AYAR_YOLU, "w", encoding="utf-8") as f:
        json.dump(ayar, f, ensure_ascii=False, indent=2)
    print("optik_aktif=true yazıldı (~/.soru_kesici.json)")


def main():
    pasif = "--pasif" in sys.argv[1:]
    try:
        kur()
        probe()
    except subprocess.CalledProcessError as e:
        print(f"\nKURULUM BAŞARISIZ: komut hata verdi ({e}).\n"
              "İnternet bağlantısını kontrol edin; sorun sürerse "
              "'brew install python@3.12' sonrası tekrar deneyin.")
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"\nKURULUM BAŞARISIZ: {e}")
        return 1
    if pasif:
        print("kurulum tamam (--pasif: ayar açılmadı)")
    else:
        ayar_aktif_et()
        print("kurulum tamam — optik okuma etkin.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
