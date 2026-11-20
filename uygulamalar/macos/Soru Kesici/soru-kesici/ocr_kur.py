#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Çok-motorlu OCR kurulumu (isteğe bağlı özellik).

Türkçe için 5 yerel OCR motorunu .venv-ml'e kurar (ana .venv'e DOKUNMAZ):
  Temel (çatışmasız): easyocr + rapidocr + onnxruntime + tesserocr
  --tam: Surya (RİSKLİ — pillow/opencv pinleri .venv-ml'i bozabilir; pip
         freeze anlık görüntüsü alınır, bozulursa geri alınır)
  --paddle: B planı PaddleOCR

Model/ağırlıklar ~/Library/Application Support/soru-kesici/ocr-modeller/
altına indirilir; tessdata (tur+eng) GitHub'dan çekilir. Kurulum sonrası
çalışma zamanında AĞ ERİŞİMİ YOK.

Kullanım:
    .venv-ml/bin/python ocr_kur.py            # temel üçlü
    .venv-ml/bin/python ocr_kur.py --tam      # + Surya
    python3 ocr_kur.py                        # .venv-ml yoksa duzen_kur ile kur
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.request

PROJE = os.path.dirname(os.path.abspath(__file__))
VENV = os.path.join(PROJE, ".venv-ml")
VENV_PY = os.path.join(VENV, "bin", "python")
DESTEK = os.path.expanduser("~/Library/Application Support/soru-kesici")
MODEL_DIZIN = os.path.join(DESTEK, "ocr-modeller")
TESSDATA = os.path.join(MODEL_DIZIN, "tessdata")
AYAR_YOLU = os.path.expanduser("~/.soru_kesici.json")

TESSDATA_URL = ("https://github.com/tesseract-ocr/tessdata_fast/"
                "raw/main/{}.traineddata")
TEMEL_PAKETLER = ["easyocr", "rapidocr", "onnxruntime", "tesserocr"]


def _venv_hazirla():
    """.venv-ml yoksa duzen_kur ile kurar (torch tabanı ortak)."""
    if os.path.exists(VENV_PY):
        return
    print(".venv-ml yok — duzen_kur ile taban ortam kuruluyor…")
    import duzen_kur
    py = duzen_kur.python_bul() or duzen_kur.python_indir()
    duzen_kur.venv_kur(py)


def _pip(*paketler, sessiz=True):
    komut = [VENV_PY, "-m", "pip", "install", *paketler]
    if sessiz:
        komut.append("--quiet")
    subprocess.run(komut, check=True)


def _freeze():
    return subprocess.run([VENV_PY, "-m", "pip", "freeze"],
                          capture_output=True, text=True).stdout


def temel_kur():
    print("Temel OCR motorları kuruluyor: " + ", ".join(TEMEL_PAKETLER))
    print("  (easyocr torch'u paylaşır; onnxruntime + tesserocr wheel'i "
          "brew gerektirmez; birkaç dakika sürebilir)")
    _pip(*TEMEL_PAKETLER)


def tessdata_indir():
    os.makedirs(TESSDATA, exist_ok=True)
    for dil in ("tur", "eng"):
        hedef = os.path.join(TESSDATA, f"{dil}.traineddata")
        if os.path.isfile(hedef) and os.stat(hedef).st_size > 100_000:
            continue
        url = TESSDATA_URL.format(dil)
        print(f"  tessdata indiriliyor: {dil}")
        try:
            fd, gecici = tempfile.mkstemp(dir=TESSDATA, suffix=".tmp")
            istek = urllib.request.Request(
                url, headers={"User-Agent": "soru-kesici"})
            with urllib.request.urlopen(istek, timeout=60) as k, \
                    os.fdopen(fd, "wb") as f:
                f.write(k.read())
            os.replace(gecici, hedef)
        except Exception as e:  # noqa: BLE001
            print(f"  UYARI: {dil}.traineddata indirilemedi: {e}")


def modelleri_isit():
    """easyocr/rapidocr modellerini ilk koşumla sabit dizine indirir."""
    print("Motor modelleri ısıtılıyor (ilk indirme birkaç dakika)…")
    kod = (
        "import os; os.makedirs(%r, exist_ok=True)\n"
        "try:\n"
        "    import easyocr; easyocr.Reader(['tr','en'], gpu=False,\n"
        "        model_storage_directory=os.path.join(%r,'easyocr'),\n"
        "        verbose=False)\n"
        "    print('  easyocr OK')\n"
        "except Exception as e: print('  easyocr:', e)\n"
        "try:\n"
        "    from rapidocr import RapidOCR; import numpy as np\n"
        "    RapidOCR()(np.zeros((32,120,3),dtype='uint8')); print('  rapidocr OK')\n"
        "except Exception as e: print('  rapidocr:', e)\n"
    ) % (MODEL_DIZIN, MODEL_DIZIN)
    subprocess.run([VENV_PY, "-c", kod], check=False)


def surya_kur():
    """Surya RİSKLİ: freeze anlık görüntüsü → kur → probe; bozulursa geri al."""
    print("Surya kuruluyor (RİSKLİ: .venv-ml bağımlılıklarını değiştirebilir)…")
    onceki = _freeze()
    yedek = os.path.join(VENV, "ocr-kur-onceki.txt")
    with open(yedek, "w") as f:
        f.write(onceki)
    try:
        _pip("surya-ocr")
    except subprocess.CalledProcessError as e:
        print(f"  Surya kurulamadı: {e}")
        return False
    # Hem OCR işçisi hem düzen modeli hâlâ çalışıyor mu?
    ocr_ok = probe(sessiz=True)
    duzen_ok = True
    try:
        sys.path.insert(0, PROJE)
        import duzen_model
        durum = duzen_model.duzen_dogrula(derin=True)
        duzen_ok = durum.get("ok", True)
    except Exception:  # noqa: BLE001
        duzen_ok = True   # düzen modeli kurulu değilse umursama
    if ocr_ok and duzen_ok:
        print("  Surya kuruldu, probe temiz.")
        return True
    print("  Surya kurulumu bir şeyi bozdu — geri alınıyor…")
    subprocess.run([VENV_PY, "-m", "pip", "install", "-r", yedek, "--quiet"],
                   check=False)
    subprocess.run([VENV_PY, "-m", "pip", "uninstall", "-y", "surya-ocr",
                    "--quiet"], check=False)
    return False


def probe(sessiz=False):
    """İşçiyi başlatıp motor durumlarını okur."""
    if not sessiz:
        print("OCR işçisi doğrulanıyor…")
    proc = subprocess.Popen([VENV_PY, os.path.join(PROJE, "ocr_isci.py")],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.DEVNULL, text=True, bufsize=1)
    try:
        satir = proc.stdout.readline()
        durum = json.loads(satir)
    except Exception:  # noqa: BLE001
        durum = None
    finally:
        try:
            proc.stdin.write(json.dumps({"cikis": True}) + "\n")
            proc.stdin.flush()
            proc.wait(timeout=3)
        except Exception:  # noqa: BLE001
            proc.kill()
    if durum and durum.get("ok"):
        aktif = [k for k, v in (durum.get("motorlar") or {}).items() if v]
        if not sessiz:
            print(f"  cihaz: {durum.get('cihaz')} · aktif motorlar: "
                  f"{', '.join(aktif) or 'yok'}")
        return bool(aktif)
    if not sessiz:
        print(f"  işçi hazır değil: {durum}")
    return False


def ayar_yaz(mod="dengeli"):
    try:
        with open(AYAR_YOLU, encoding="utf-8") as f:
            ayar = json.load(f)
    except (OSError, ValueError):
        ayar = {}
    ayar["ocr_modu"] = mod
    with open(AYAR_YOLU, "w", encoding="utf-8") as f:
        json.dump(ayar, f, ensure_ascii=False, indent=2)
    print(f"ocr_modu={mod} yazıldı (~/.soru_kesici.json)")


def main():
    args = sys.argv[1:]
    pasif = "--pasif" in args
    try:
        _venv_hazirla()
        temel_kur()
        os.makedirs(MODEL_DIZIN, exist_ok=True)
        tessdata_indir()
        modelleri_isit()
        if "--tam" in args:
            surya_kur()
        if "--paddle" in args:
            try:
                _pip("paddlepaddle", "paddleocr")
            except subprocess.CalledProcessError as e:
                print(f"  PaddleOCR kurulamadı: {e}")
        if probe() and not pasif:
            ayar_yaz("dengeli")
        print("\n✓ OCR kurulumu tamamlandı. Web ayarlarından modu seçin "
              "(hızlı / dengeli / tam).")
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Kurulum başarısız: {e}")
        return 1
    except Exception as e:  # noqa: BLE001
        print(f"\n✗ Beklenmeyen hata: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
