#!/usr/bin/env python3
"""Campbell Colab PDF aktarımı ve atomik JSONL kontrol noktası alıcısı."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import tempfile
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BEKLENEN = set(range(141, 150)) | set(range(162, 1102))
AZAMI_GOVDE = 64 * 1024 * 1024


def dogrula(govde: bytes) -> tuple[int, int]:
    satirlar = govde.decode("utf-8").splitlines()
    sayfalar: set[int] = set()
    hatali = 0
    for satir_no, satir in enumerate(satirlar, 1):
        if not satir.strip():
            continue
        try:
            kayit = json.loads(satir)
            sayfa = int(kayit["page"])
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise ValueError(f"gecersiz satir {satir_no}: {exc}") from exc
        if sayfa not in BEKLENEN:
            raise ValueError(f"beklenmeyen sayfa: {sayfa}")
        if sayfa in sayfalar:
            raise ValueError(f"yinelenen sayfa: {sayfa}")
        sayfalar.add(sayfa)
        if kayit.get("error"):
            hatali += 1
    return len(sayfalar), hatali


def atomik_yaz(hedef: Path, govde: bytes) -> None:
    hedef.parent.mkdir(parents=True, exist_ok=True)
    fd, gecici = tempfile.mkstemp(prefix=f".{hedef.name}.", dir=hedef.parent)
    try:
        with os.fdopen(fd, "wb") as dosya:
            dosya.write(govde)
            dosya.flush()
            os.fsync(dosya.fileno())
        os.replace(gecici, hedef)
    except BaseException:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(gecici)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path, required=True)
    parser.add_argument("--hedef", type=Path, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--port", type=int, default=8767)
    args = parser.parse_args()

    pdf = args.pdf.resolve(strict=True)
    hedef = args.hedef.resolve()
    pdf_yolu = f"/{args.token}/campbell.pdf"
    kayit_yolu = f"/{args.token}/checkpoint"

    class Istek(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path != pdf_yolu:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            boyut = pdf.stat().st_size
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/pdf")
            self.send_header("Content-Length", str(boyut))
            self.end_headers()
            with pdf.open("rb") as dosya:
                while parca := dosya.read(1024 * 1024):
                    self.wfile.write(parca)

        def do_POST(self) -> None:
            if self.path != kayit_yolu:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            try:
                boyut = int(self.headers.get("Content-Length", "-1"))
            except ValueError:
                boyut = -1
            if not 0 < boyut <= AZAMI_GOVDE:
                self.send_error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
                return
            govde = self.rfile.read(boyut)
            try:
                sayfa, hatali = dogrula(govde)
                atomik_yaz(hedef, govde)
            except (UnicodeDecodeError, ValueError) as exc:
                self.send_error(HTTPStatus.BAD_REQUEST, str(exc))
                return
            yanit = json.dumps({"pages": sayfa, "errors": hatali}).encode()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(yanit)))
            self.end_headers()
            self.wfile.write(yanit)

        def log_message(self, bicim: str, *degerler: object) -> None:
            print(f"{self.client_address[0]} - {bicim % degerler}", flush=True)

    print(f"PDF: {pdf_yolu}", flush=True)
    print(f"Checkpoint: {kayit_yolu} -> {hedef}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Istek).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
