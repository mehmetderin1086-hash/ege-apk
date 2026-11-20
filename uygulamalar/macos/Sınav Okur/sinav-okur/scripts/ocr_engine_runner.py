#!/usr/bin/env python3
"""Yalıtılmış OCR ortamı için küçük JSON giriş/çıkış köprüsü."""

from __future__ import annotations

import json
import os
import sys
from contextlib import redirect_stdout
from pathlib import Path

from PIL import Image


def _kutu(poly, w: int, h: int):
    xs = [float(p[0]) for p in poly]
    ys = [float(p[1]) for p in poly]
    x0, x1 = min(xs), max(xs)
    y0, y1 = min(ys), max(ys)
    return {
        "x": x0 / w,
        "y": y0 / h,
        "width": (x1 - x0) / w,
        "height": (y1 - y0) / h,
    }


# --sunucu modunda modellerin istekler arasında yeniden yüklenmemesi için.
_ONBELLEK: dict[str, object] = {}


def easyocr_oku(yol: Path):
    reader = _ONBELLEK.get("easyocr")
    if reader is None:
        import easyocr

        reader = easyocr.Reader(["tr", "en"], gpu=False, verbose=False)
        _ONBELLEK["easyocr"] = reader
    with Image.open(yol) as im:
        w, h = im.size
    sonuc = []
    for poly, text, confidence in reader.readtext(
        str(yol), detail=1, paragraph=False
    ):
        sonuc.append(
            {
                "text": text,
                "confidence": float(confidence),
                **_kutu(poly, w, h),
            }
        )
    return sonuc


def tesseract_oku(yol: Path):
    from tesserocr import PSM, RIL, PyTessBaseAPI

    tessdata = Path(os.environ.get("SINAV_OKUR_TESSDATA", Path(__file__).parents[1] / ".ocr-models" / "tessdata"))
    with Image.open(yol) as im:
        w, h = im.size
        with PyTessBaseAPI(path=str(tessdata), lang="tur+eng", psm=PSM.AUTO) as api:
            api.SetImage(im)
            api.Recognize()
            iterator = api.GetIterator()
            sonuc = []
            if iterator:
                while True:
                    text = iterator.GetUTF8Text(RIL.TEXTLINE)
                    bbox = iterator.BoundingBox(RIL.TEXTLINE)
                    if text and bbox:
                        x0, y0, x1, y1 = bbox
                        sonuc.append(
                            {
                                "text": text.strip(),
                                "confidence": max(0.0, iterator.Confidence(RIL.TEXTLINE) / 100),
                                "x": x0 / w,
                                "y": y0 / h,
                                "width": (x1 - x0) / w,
                                "height": (y1 - y0) / h,
                            }
                        )
                    if not iterator.Next(RIL.TEXTLINE):
                        break
    return sonuc


def paddle_oku(yol: Path):
    ocr = _ONBELLEK.get("paddle")
    if ocr is None:
        from paddleocr import PaddleOCR

        ocr = PaddleOCR(
            lang="tr",
            ocr_version="PP-OCRv5",
            device="cpu",
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
        )
        _ONBELLEK["paddle"] = ocr
    with Image.open(yol) as im:
        w, h = im.size
    sonuc = []
    for sayfa in ocr.predict(str(yol)):
        veri = getattr(sayfa, "json", sayfa)
        if callable(veri):
            veri = veri()
        if isinstance(veri, str):
            veri = json.loads(veri)
        if isinstance(veri, dict) and "res" in veri:
            veri = veri["res"]
        texts = veri.get("rec_texts", []) if isinstance(veri, dict) else []
        scores = veri.get("rec_scores", []) if isinstance(veri, dict) else []
        polys = veri.get("rec_polys", veri.get("dt_polys", [])) if isinstance(veri, dict) else []
        for text, score, poly in zip(texts, scores, polys):
            sonuc.append(
                {
                    "text": str(text),
                    "confidence": float(score),
                    **_kutu(poly, w, h),
                }
            )
    return sonuc


def rapidocr_oku(yol: Path):
    engine = _ONBELLEK.get("rapidocr")
    if engine is None:
        from rapidocr import RapidOCR

        engine = RapidOCR()
        _ONBELLEK["rapidocr"] = engine
    with Image.open(yol) as im:
        w, h = im.size
    sonuc = []
    rapor = engine(str(yol))
    if rapor.boxes is None:
        return sonuc
    for poly, text, confidence in zip(rapor.boxes, rapor.txts, rapor.scores):
        sonuc.append(
            {
                "text": str(text),
                "confidence": float(confidence),
                **_kutu(poly, w, h),
            }
        )
    return sonuc


def surya_oku(yol: Path):
    from bs4 import BeautifulSoup

    predictor = _ONBELLEK.get("surya")
    if predictor is None:
        from surya.inference import SuryaInferenceManager
        from surya.recognition import RecognitionPredictor

        # Sunucu modundaki asıl kazanç: llama-server bir kez başlar.
        predictor = RecognitionPredictor(SuryaInferenceManager())
        _ONBELLEK["surya"] = predictor
    image = Image.open(yol).convert("RGB")
    w, h = image.size
    sayfa = predictor([image], full_page=True)[0]
    sonuc = []
    for block in sayfa.blocks:
        text = BeautifulSoup(block.html, "html.parser").get_text(" ", strip=True)
        if not text or block.skipped or block.error:
            continue
        sonuc.append(
            {
                "text": text,
                "confidence": float(getattr(block, "confidence", 0.8)),
                **_kutu(block.polygon, w, h),
            }
        )
    return sonuc


def sunucu(okuyucu) -> None:
    """Satır-JSON sunucusu: stdin'den {"gorsel": ...} alır, tek satır yanıt yazar.

    Model ilk istekte yüklenir ve süreç yaşadıkça bellekte kalır. Motor
    hatası yanıtta ``hata`` alanıyla döner; süreç ölmez (havuz tarafındaki
    zaman aşımı/çökme yönetimi ana uygulamadadır).
    """
    for satir in sys.stdin:
        satir = satir.strip()
        if not satir:
            continue
        try:
            istek = json.loads(satir)
            if istek.get("kapat"):
                break
            with redirect_stdout(sys.stderr):
                bloklar = okuyucu(Path(istek["gorsel"]))
            yanit = {"blocks": bloklar}
        except Exception as exc:  # motor hatası süreci öldürmesin, yanıtla dönsün
            yanit = {"hata": str(exc).strip()[-600:]}
        print(json.dumps(yanit, ensure_ascii=False), flush=True)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("Kullanım: ocr_engine_runner.py MOTOR (GÖRSEL | --sunucu)")
    motor, hedef = sys.argv[1], sys.argv[2]
    okuyucular = {
        "easyocr": easyocr_oku,
        "tesseract": tesseract_oku,
        "paddle": paddle_oku,
        "surya": surya_oku,
        "rapidocr": rapidocr_oku,
    }
    if motor not in okuyucular:
        raise SystemExit(f"Bilinmeyen motor: {motor}")
    if hedef == "--sunucu":
        sunucu(okuyucular[motor])
        return
    # Bazı üçüncü taraf kütüphaneler model indirme/başlatma bilgisini stdout'a
    # yazar. Ana uygulamanın ayrıştırdığı stdout'u yalnız JSON olarak tut.
    with redirect_stdout(sys.stderr):
        bloklar = okuyucular[motor](Path(hedef))
    print(json.dumps({"blocks": bloklar}, ensure_ascii=False))


if __name__ == "__main__":
    main()
