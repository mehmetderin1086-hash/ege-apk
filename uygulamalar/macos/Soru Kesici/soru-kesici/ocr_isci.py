#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — çok-motorlu OCR işçisi (.venv-ml altında koşar).

duzen_isci.py fd-izolasyon deseni: gerçek stdout protokol kanalı, fd 1
stderr'e yönlendirilir (torch/onnx gürültüsü log'a düşer). Motorlar tembel
yüklenir; bir motorun çökmesi diğerlerini/yanıtı düşürmez.

Protokol (satır-JSON, stdin istek / stdout yanıt):
  el sıkışma → {"ok": true, "motorlar": {ad: bool}, "cihaz": "mps"|"cpu"}
  istek  {"id", "png", "motorlar": [...], "bolgeler": [[x0,y0,x1,y1],...]|null}
  yanıt  bolgeler verildiyse:
         {"id", "bolge_sonuclari": [{motor: [{metin,kutu,guven}]}, ...]}
         bolgeler=null (tüm sayfa):
         {"id", "sonuclar": {motor: [{metin,kutu,guven}] | {"hata": ...}}}
  {"bosalt": "surya"} → modeli RAM'den bırak · {"cikis": true} → çık
"""

import json
import os
import sys

import veri_yollari

MODEL_DIZIN = os.path.join(veri_yollari.veri_koku(), "ocr-modeller")
TESSDATA = os.path.join(MODEL_DIZIN, "tessdata")

# Çalışma zamanı ağ erişimini kapat (kurulum sonrası indirme YOK).
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

_MOTORLAR = {}          # ad -> yüklü motor nesnesi (tembel)
_CIHAZ = "cpu"


def _cihaz_bul():
    global _CIHAZ
    try:
        import torch
        _CIHAZ = "mps" if torch.backends.mps.is_available() else "cpu"
    except Exception:  # noqa: BLE001
        _CIHAZ = "cpu"
    return _CIHAZ


def _motor_var(ad):
    """Motor içe aktarılabilir mi (yüklemeden)."""
    import importlib.util
    paket = {"easyocr": "easyocr", "rapidocr": "rapidocr",
             "tesseract": "tesserocr", "surya": "surya"}.get(ad)
    if not paket:
        return False
    try:
        return importlib.util.find_spec(paket) is not None
    except (ImportError, ValueError):
        return False


def _yukle(ad):
    """Motoru tembel yükler; başarısızsa None."""
    if ad in _MOTORLAR:
        return _MOTORLAR[ad]
    try:
        if ad == "easyocr":
            import easyocr
            m = easyocr.Reader(["tr", "en"], gpu=(_CIHAZ == "mps"),
                               model_storage_directory=os.path.join(
                                   MODEL_DIZIN, "easyocr"),
                               verbose=False)
        elif ad == "rapidocr":
            from rapidocr import RapidOCR
            m = RapidOCR()
        elif ad == "tesseract":
            import tesserocr
            m = tesserocr.PyTessBaseAPI(path=TESSDATA, lang="tur+eng")
        elif ad == "surya":
            from surya.recognition import RecognitionPredictor
            from surya.detection import DetectionPredictor
            m = (DetectionPredictor(), RecognitionPredictor())
        else:
            return None
        _MOTORLAR[ad] = m
        return m
    except Exception:  # noqa: BLE001
        _MOTORLAR[ad] = None
        return None


def _oku(ad, pil_img):
    """Motorla PIL görüntüsünü okur → [{metin, kutu[x0,y0,x1,y1], guven}].
    Güven 0..1 normalize edilir (tesseract 0..100)."""
    m = _yukle(ad)
    if m is None:
        raise RuntimeError(f"{ad} yüklenemedi")
    import numpy as np
    if ad == "easyocr":
        sonuc = m.readtext(np.array(pil_img))
        cikti = []
        for kutu, metin, guven in sonuc:
            xs = [p[0] for p in kutu]
            ys = [p[1] for p in kutu]
            cikti.append({"metin": metin,
                          "kutu": [min(xs), min(ys), max(xs), max(ys)],
                          "guven": float(guven)})
        return cikti
    if ad == "rapidocr":
        sonuc = m(np.array(pil_img))
        cikti = []
        kutular = getattr(sonuc, "boxes", None)
        metinler = getattr(sonuc, "txts", None)
        skorlar = getattr(sonuc, "scores", None)
        if kutular is not None and metinler is not None:
            for kutu, metin, skor in zip(kutular, metinler,
                                         skorlar or [1.0] * len(metinler)):
                xs = [float(p[0]) for p in kutu]
                ys = [float(p[1]) for p in kutu]
                cikti.append({"metin": str(metin),
                              "kutu": [min(xs), min(ys), max(xs), max(ys)],
                              "guven": float(skor)})
        return cikti
    if ad == "tesseract":
        import tesserocr
        m.SetImage(pil_img)
        cikti = []
        m.Recognize()
        ri = m.GetIterator()
        seviye = tesserocr.RIL.TEXTLINE
        while True:
            metin = ri.GetUTF8Text(seviye)
            if metin and metin.strip():
                x0, y0, x1, y1 = ri.BoundingBox(seviye)
                cikti.append({"metin": metin.strip(),
                              "kutu": [x0, y0, x1, y1],
                              "guven": ri.Confidence(seviye) / 100.0})
            if not ri.Next(seviye):
                break
        return cikti
    if ad == "surya":
        det, rec = m
        sonuc = rec([pil_img], det_predictor=det)
        cikti = []
        for sayfa in sonuc:
            for satir in getattr(sayfa, "text_lines", []):
                bbox = satir.bbox
                cikti.append({"metin": satir.text,
                              "kutu": [bbox[0], bbox[1], bbox[2], bbox[3]],
                              "guven": float(getattr(satir, "confidence",
                                                     0.8))})
        return cikti
    return []


def _bolge_oku(ad, pil_img, bolge):
    """Bölgeyi 2× büyütüp okur; kutuları orijinal koordinata geri taşır."""
    x0, y0, x1, y1 = (int(v) for v in bolge)
    x0, y0 = max(0, x0), max(0, y0)
    x1 = min(pil_img.width, max(x1, x0 + 1))
    y1 = min(pil_img.height, max(y1, y0 + 1))
    parca = pil_img.crop((x0, y0, x1, y1))
    if max(parca.size) < 1400:
        parca = parca.resize((parca.width * 2, parca.height * 2))
        f = 2.0
    else:
        f = 1.0
    satlar = _oku(ad, parca)
    for s in satlar:
        k = s["kutu"]
        s["kutu"] = [k[0] / f + x0, k[1] / f + y0,
                     k[2] / f + x0, k[3] / f + y0]
    return satlar


def main():
    proto = os.fdopen(os.dup(1), "w", buffering=1)
    os.dup2(2, 1)

    def yaz(obj):
        # default=float: numpy skaları (float32 vb.) yakalanır → çökme yok
        proto.write(json.dumps(obj, ensure_ascii=False, default=float) + "\n")

    _cihaz_bul()
    motorlar = {ad: _motor_var(ad)
                for ad in ("easyocr", "rapidocr", "tesseract", "surya")}
    yaz({"ok": True, "motorlar": motorlar, "cihaz": _CIHAZ})

    from PIL import Image
    for satir in sys.stdin:
        satir = satir.strip()
        if not satir:
            continue
        try:
            istek = json.loads(satir)
        except ValueError:
            continue
        if istek.get("cikis"):
            break
        if istek.get("bosalt"):
            _MOTORLAR.pop(istek["bosalt"], None)
            continue
        no = istek.get("id")
        istenen = [m for m in (istek.get("motorlar") or []) if motorlar.get(m)]
        try:
            pil = Image.open(istek["png"]).convert("RGB")
        except Exception as e:  # noqa: BLE001
            yaz({"id": no, "hata": f"görüntü açılamadı: {e}"})
            continue
        bolgeler = istek.get("bolgeler")
        if bolgeler:
            sonuc = []
            for bolge in bolgeler:
                bs = {}
                for ad in istenen:
                    try:
                        bs[ad] = _bolge_oku(ad, pil, bolge)
                    except Exception as e:  # noqa: BLE001
                        bs[ad] = {"hata": f"{type(e).__name__}: {e}"}
                sonuc.append(bs)
            yaz({"id": no, "bolge_sonuclari": sonuc})
        else:
            sonuc = {}
            for ad in istenen:
                try:
                    sonuc[ad] = _oku(ad, pil)
                except Exception as e:  # noqa: BLE001
                    sonuc[ad] = {"hata": f"{type(e).__name__}: {e}"}
            yaz({"id": no, "sonuclar": sonuc})
    return 0


if __name__ == "__main__":
    sys.exit(main())
