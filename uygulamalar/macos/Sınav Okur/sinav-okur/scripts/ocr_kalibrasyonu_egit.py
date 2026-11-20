#!/usr/bin/env python3
"""Doğrulanmış OCR JSONL verisinden güven kalibrasyonu üret.

Her satır: {"ham_guven": 0.91, "dogru": true}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from sinav_okur.htr.kalibrasyon import GuvenKalibrasyonu


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("girdi", type=Path)
    parser.add_argument(
        "--cikti",
        type=Path,
        default=Path("modeller/ocr_kalibrasyon.json"),
    )
    args = parser.parse_args()
    kayitlar = [
        json.loads(satir)
        for satir in args.girdi.read_text(encoding="utf-8").splitlines()
        if satir.strip()
    ]
    ham = [float(x["ham_guven"]) for x in kayitlar]
    etiket = [bool(x["dogru"]) for x in kayitlar]
    kalibrasyon = GuvenKalibrasyonu().egit(ham, etiket)
    args.cikti.parent.mkdir(parents=True, exist_ok=True)
    kalibrasyon.kaydet(args.cikti)
    print(
        json.dumps(
            {
                "cikti": str(args.cikti),
                "ornek": len(kayitlar),
                **kalibrasyon.metrikler(ham, etiket),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()

