#!/usr/bin/env python3
"""Guyton PDF metin katmanını, Colab OCR ile eksik sayfalarda birleştir."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from pypdf import PdfReader


def jsonl_oku(yol: Path) -> dict[int, dict]:
    sonuc: dict[int, dict] = {}
    for sira, satir in enumerate(yol.read_text(encoding="utf-8").splitlines(), 1):
        if not satir.strip():
            continue
        kayit = json.loads(satir)
        sayfa = int(kayit["page"])
        if sayfa in sonuc:
            raise ValueError(f"yinelenen OCR sayfası: {sayfa} (satır {sira})")
        if kayit.get("error"):
            raise ValueError(f"OCR hatalı sayfa: {sayfa}: {kayit['error']}")
        sonuc[sayfa] = kayit
    return sonuc


def atomik_yaz(hedef: Path, satirlar: list[str]) -> None:
    hedef.parent.mkdir(parents=True, exist_ok=True)
    fd, gecici = tempfile.mkstemp(prefix=f".{hedef.name}.", dir=hedef.parent, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as dosya:
            dosya.write("\n".join(satirlar) + "\n")
            dosya.flush()
            os.fsync(dosya.fileno())
        os.replace(gecici, hedef)
    except BaseException:
        Path(gecici).unlink(missing_ok=True)
        raise


def hazirla(pdf_yolu: Path, ocr_yolu: Path, hedef: Path, esik: int) -> tuple[int, int, int]:
    pdf = PdfReader(pdf_yolu)
    ocr = jsonl_oku(ocr_yolu)
    kayitlar: list[str] = []
    katman = colab = 0

    for sayfa, pdf_sayfasi in enumerate(pdf.pages, 1):
        metin = (pdf_sayfasi.extract_text() or "").strip()
        if len(metin) > esik:
            kayit = {"page": sayfa, "text": metin, "confidence": 1.0, "method": "pdf_text_layer"}
            katman += 1
        else:
            if sayfa not in ocr:
                raise ValueError(f"metin katmanı yetersiz ama OCR kaydı yok: sayfa {sayfa}")
            kaynak = ocr[sayfa]
            ocr_metin = str(kaynak.get("text", "")).strip()
            if len(ocr_metin) > len(metin):
                kayit = {
                    "page": sayfa,
                    "text": ocr_metin,
                    "confidence": float(kaynak.get("confidence", 0.0) or 0.0),
                    "method": "colab_ocr",
                }
            else:
                kayit = {
                    "page": sayfa,
                    "text": metin,
                    "confidence": 1.0,
                    "method": "pdf_text_layer_short",
                }
            colab += 1
        kayitlar.append(json.dumps(kayit, ensure_ascii=False))

    atomik_yaz(hedef, kayitlar)
    return len(pdf.pages), katman, colab


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf", type=Path)
    parser.add_argument("ocr", type=Path)
    parser.add_argument("hedef", type=Path)
    parser.add_argument("--metin-esigi", type=int, default=100)
    args = parser.parse_args()
    toplam, katman, colab = hazirla(args.pdf, args.ocr, args.hedef, args.metin_esigi)
    print(f"hibrit kayıt: {toplam} · PDF metin katmanı: {katman} · Colab OCR: {colab}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
