#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ML düzen tespiti kurulumu (isteğe bağlı özellik).

DocLayout-YOLO, torch gerektirdiği ve modern torch Python 3.10+ istediği
için ana .venv'e (3.9) DOKUNMADAN ayrı bir .venv-ml kurar:
  1. Python 3.10+ ara (Homebrew/sistem); yoksa python-build-standalone'dan
     bağımsız CPython 3.12 indir (~45 MB, sistemi değiştirmez).
  2. .venv-ml oluştur + pip install doclayout-yolo (torch dahil ~1 GB disk,
     indirme ~150-300 MB).
  3. Model ağırlığını HuggingFace'ten indir (~40 MB).
  4. İşçiyi --probe ile doğrula; başarıda duzen_model_aktif=true yaz.

Kullanım: python3 duzen_kur.py [--pasif]   (--pasif: ayarı açma)
"""
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

PROJE = os.path.dirname(os.path.abspath(__file__))
VENV = os.path.join(PROJE, ".venv-ml")
VENV_PY = os.path.join(VENV, "bin", "python")
DESTEK = os.path.expanduser("~/Library/Application Support/soru-kesici")
PYTHON_DIZIN = os.path.join(DESTEK, "python")
MODEL_DIZIN = os.path.join(DESTEK, "modeller")
MODEL_AD = "doclayout_yolo_docstructbench_imgsz1024.pt"
MODEL_URL = ("https://huggingface.co/juliozhao/DocLayout-YOLO-DocStructBench/"
             "resolve/main/" + MODEL_AD)
PBS_API = ("https://api.github.com/repos/astral-sh/python-build-standalone/"
           "releases/latest")
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")


def _indir(url, hedef, aciklama):
    """URL'yi atomik indirir (.tmp + os.replace), kaba ilerleme basar."""
    print(f"  indiriliyor: {aciklama}")
    istek = urllib.request.Request(url, headers={"User-Agent": "soru-kesici"})
    fd, gecici = tempfile.mkstemp(dir=os.path.dirname(hedef), suffix=".tmp")
    try:
        with urllib.request.urlopen(istek, timeout=60) as k, \
                os.fdopen(fd, "wb") as f:
            toplam, okunan = k.headers.get("Content-Length"), 0
            while True:
                parca = k.read(1 << 20)
                if not parca:
                    break
                f.write(parca)
                okunan += len(parca)
                if toplam:
                    print(f"\r    {okunan >> 20} / {int(toplam) >> 20} MB",
                          end="", flush=True)
        print()
        os.replace(gecici, hedef)
    except BaseException:
        try:
            os.unlink(gecici)
        except OSError:
            pass
        raise


def _surum(py):
    try:
        s = subprocess.run(
            [py, "-c", "import sys; print(sys.version_info[0],"
                       " sys.version_info[1])"],
            capture_output=True, text=True, timeout=15)
        a, b = s.stdout.split()
        return int(a), int(b)
    except Exception:  # noqa: BLE001
        return None


def python_bul():
    """Kurulabilir Python 3.10+ yolu veya None."""
    adaylar = []
    for ad in ("python3.13", "python3.12", "python3.11", "python3.10"):
        yol = shutil.which(ad)
        if yol:
            adaylar.append(yol)
        for kok in ("/opt/homebrew/bin", "/usr/local/bin"):
            yol = os.path.join(kok, ad)
            if os.path.isfile(yol):
                adaylar.append(yol)
    genel = shutil.which("python3")
    if genel:
        adaylar.append(genel)
    onceki = os.path.join(PYTHON_DIZIN, "bin", "python3")  # eski indirme
    if os.path.isfile(onceki):
        adaylar.append(onceki)
    for aday in adaylar:
        s = _surum(aday)
        if s and s >= (3, 10):
            return aday
    return None


def python_indir():
    """python-build-standalone'dan bağımsız CPython 3.12 kurar."""
    mimari = {"arm64": "aarch64", "x86_64": "x86_64"}.get(platform.machine())
    if not mimari:
        raise RuntimeError(f"desteklenmeyen mimari: {platform.machine()}")
    print("Python 3.10+ bulunamadı → bağımsız CPython 3.12 indiriliyor "
          "(~45 MB, yalnız soru-kesici için, sistemi değiştirmez).")
    istek = urllib.request.Request(PBS_API,
                                   headers={"User-Agent": "soru-kesici"})
    with urllib.request.urlopen(istek, timeout=60) as k:
        surum = json.load(k)
    hedef_ek = f"{mimari}-apple-darwin-install_only.tar.gz"
    url = next((v["browser_download_url"] for v in surum.get("assets", [])
                if v["name"].startswith("cpython-3.12.")
                and v["name"].endswith(hedef_ek)), None)
    if not url:
        raise RuntimeError("uygun cpython-3.12 paketi bulunamadı "
                           "(python-build-standalone sürümü değişmiş olabilir)")
    os.makedirs(DESTEK, exist_ok=True)
    arsiv = os.path.join(DESTEK, "cpython312.tar.gz")
    _indir(url, arsiv, os.path.basename(url))
    with tempfile.TemporaryDirectory(dir=DESTEK) as gecici:
        with tarfile.open(arsiv) as t:
            t.extractall(gecici)  # kök dizini: python/
        kaynak = os.path.join(gecici, "python")
        if os.path.isdir(PYTHON_DIZIN):
            shutil.rmtree(PYTHON_DIZIN)
        shutil.move(kaynak, PYTHON_DIZIN)
    os.unlink(arsiv)
    return os.path.join(PYTHON_DIZIN, "bin", "python3")


def venv_kur(py):
    print(f".venv-ml kuruluyor (taban: {py})")
    subprocess.run([py, "-m", "venv", "--clear", VENV], check=True)
    subprocess.run([VENV_PY, "-m", "pip", "install", "--upgrade", "pip",
                    "--quiet"], check=True)
    print("  pip install doclayout-yolo (torch dahil, ~150-300 MB indirme; "
          "birkaç dakika sürebilir)")
    # huggingface_hub: doclayout_yolo import'unda gerekir ama paket bunu
    # bağımlılık olarak bildirmiyor → açıkça kur
    subprocess.run([VENV_PY, "-m", "pip", "install", "doclayout-yolo",
                    "huggingface_hub", "dill", "--quiet"], check=True)


def model_indir():
    hedef = os.path.join(MODEL_DIZIN, MODEL_AD)
    if os.path.isfile(hedef) and os.stat(hedef).st_size > 1_000_000:
        print("model ağırlığı zaten mevcut, atlanıyor")
        return
    os.makedirs(MODEL_DIZIN, exist_ok=True)
    _indir(MODEL_URL, hedef, MODEL_AD + " (~40 MB)")


def probe():
    print("işçi doğrulanıyor (ilk model yüklemesi 1-2 dk sürebilir)…")
    import duzen_model
    durum = duzen_model.duzen_dogrula(derin=True)
    if not durum["ok"]:
        raise RuntimeError(durum["mesaj"])
    print(f"  {durum['mesaj']}")


def ayar_aktif_et():
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            ayar = json.load(f)
    except (OSError, ValueError):
        ayar = {}
    ayar["duzen_model_aktif"] = True
    with open(AYAR_YOLU, "w", encoding="utf-8") as f:
        json.dump(ayar, f, ensure_ascii=False, indent=2)
    print("duzen_model_aktif=true yazıldı (~/.soru_kesici.json)")


def main():
    pasif = "--pasif" in sys.argv[1:]
    try:
        py = python_bul() or python_indir()
        venv_kur(py)
        model_indir()
        probe()
    except subprocess.CalledProcessError as e:
        print(f"\nKURULUM BAŞARISIZ: komut hata verdi ({e}).\n"
              "İnternet bağlantısını kontrol edin; sorun sürerse "
              "'brew install python@3.12' sonrası tekrar deneyin.")
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"\nKURULUM BAŞARISIZ: {e}\n"
              "İnternet bağlantısını kontrol edin (torch ~150-300 MB, "
              "model ~40 MB). İşçi hatası için: "
              "~/Library/Caches/soru-kesici/duzen/isci.log")
        return 1
    if pasif:
        print("kurulum tamam (--pasif: ayar açılmadı; web arayüzünden "
              "veya --duzen-model acik ile etkinleştirin)")
    else:
        ayar_aktif_et()
        print("kurulum tamam — ML düzen tespiti etkin.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
