#!/usr/bin/env python3
"""Assemble a hash-locked KitapKatalog model bundle from local files only."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from kitapkatalog.model_bundle import (
    BundleAssemblyError,
    assemble_bundle,
    verify_locked_bundle,
)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Yerel model dosyalarından ağsız KitapKatalog paketi oluşturur."
    )
    result.add_argument("source", type=Path, help="Manifest yollarını içeren yerel kaynak")
    result.add_argument("target", type=Path, help="Yeni oluşturulacak hedef model klasörü")
    result.add_argument("--manifest", type=Path, help="İsteğe bağlı manifest şablonu")
    result.add_argument(
        "--rapidocr-source",
        choices=("installed", "source"),
        default="installed",
        help=(
            "PP-OCRv6 small/cls ONNX kaynağı; medium det+rec her durumda "
            "yerel source dizininden alınır"
        ),
    )
    result.add_argument(
        "--allow-missing-executables",
        action="store_true",
        help="Yalnız geliştirme için bin/tesseract ve bin/llama-server zorunluluğunu kaldırır",
    )
    result.add_argument("--verify", type=Path, help="Oluşturmak yerine mevcut paketi doğrula")
    return result


def main() -> int:
    arguments = parser().parse_args()
    if arguments.verify:
        problems = verify_locked_bundle(arguments.verify)
        print(json.dumps({"valid": not problems, "problems": problems}, ensure_ascii=False))
        return 0 if not problems else 2
    try:
        outcome = assemble_bundle(
            arguments.source,
            arguments.target,
            template_manifest=arguments.manifest,
            copy_installed_rapidocr=arguments.rapidocr_source == "installed",
            require_executables=not arguments.allow_missing_executables,
        )
    except BundleAssemblyError as exc:
        print(f"HATA: {exc}")
        return 2
    print(
        json.dumps(
            {
                "target": str(outcome.target),
                "manifest": str(outcome.manifest),
                "artifact_count": outcome.artifact_count,
                "byte_count": outcome.byte_count,
                "executables": outcome.executables,
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
