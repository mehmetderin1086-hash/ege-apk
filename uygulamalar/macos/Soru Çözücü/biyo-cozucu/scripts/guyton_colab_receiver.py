#!/usr/bin/env python3
"""Guyton PDF aktarımı ve Colab JSONL kontrol noktası alıcısı."""

from __future__ import annotations

import argparse
import contextlib
import json
import os
import tempfile
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

AZAMI_GOVDE = 128 * 1024 * 1024
OCR_SAYFALARI = [
    4, 8, 24, 26, 34, 50, 68, 114, 124, 138, 152, 178, 180, 214, 236,
    266, 278, 308, 326, 368, 436, 446, 486, 488, 500, 538, 548, 550,
    566, 618, 620, 646, 668, 678, 704, 720, 734, 766, 776, 830, 832,
    882, 890, 902, 904, 918, 944, 962, 1042, 1053, 1054, 1066,
]


def dogrula(govde: bytes, beklenen_sayfa: int) -> tuple[int, int]:
    sayfalar: set[int] = set()
    hatali = 0
    for satir_no, satir in enumerate(govde.decode("utf-8").splitlines(), 1):
        if not satir.strip():
            continue
        try:
            kayit = json.loads(satir)
            sayfa = int(kayit["page"])
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise ValueError(f"gecersiz satir {satir_no}: {exc}") from exc
        if not 1 <= sayfa <= beklenen_sayfa:
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
    parser.add_argument("--beklenen-sayfa", type=int, required=True)
    parser.add_argument("--port", type=int, default=8768)
    args = parser.parse_args()

    pdf = args.pdf.resolve(strict=True)
    hedef = args.hedef.resolve()
    pdf_yolu = f"/{args.token}/guyton.pdf"
    kayit_yolu = f"/{args.token}/checkpoint"
    calistirici_yolu = f"/{args.token}/runner.py"
    defter = Path(__file__).resolve().parents[1] / "notebooks" / "guyton_colab.ipynb"

    def calistirici_kodu(host: str) -> bytes:
        """Colab hücresini kısa bir ``exec`` satırından çalıştırılabilir kılar."""
        with defter.open(encoding="utf-8") as dosya:
            notebook = json.load(dosya)
        kaynaklar = [
            "".join(hucre["source"])
            for hucre in notebook["cells"]
            if hucre["cell_type"] == "code"
        ]
        kod = "\n\n".join(kaynaklar)
        kod = kod.replace(
            "!pip -q install 'surya-ocr==0.22.1' 'pypdfium2>=5.10.1'",
            "import subprocess, sys\n"
            "subprocess.check_call([sys.executable, '-m', 'pip', '-q', 'install', "
            "'surya-ocr==0.22.1', 'pypdfium2>=5.10.1'])",
        )
        kod = kod.replace(
            "PDF_URL_BURAYA",
            "https://drive.usercontent.google.com/download?id=1bgZQw0DceAquuZG3Nib1ZU5ufTltKOED&export=download&confirm=t",
        )
        kod = kod.replace("CHECKPOINT_URL_BURAYA", f"https://{host}{kayit_yolu}")
        kod = kod.replace(
            "expected = list(range(1, len(pdf) + 1))",
            f"expected = {OCR_SAYFALARI!r}",
        )
        # Tünel yenilenirse OCR'ı durdurma. Colab'daki JSONL aynı çalışma
        # zamanında birikmeye devam eder ve çalışma sonunda eksiksizlik
        # doğrulamasından sonra tek dosya olarak alınır.
        kod = kod.replace(
            "    raise RuntimeError('Mac checkpoint gönderilemedi')",
            "    print('Mac checkpoint bu turda gönderilemedi; Colab kaydıyla devam ediliyor')",
        )
        return kod.encode("utf-8")

    class Istek(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            if self.path == calistirici_yolu:
                kod = calistirici_kodu(self.headers.get("Host", ""))
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "text/x-python; charset=utf-8")
                self.send_header("Content-Length", str(len(kod)))
                self.end_headers()
                self.wfile.write(kod)
                return
            if self.path == kayit_yolu:
                if not hedef.is_file():
                    self.send_error(HTTPStatus.NOT_FOUND)
                    return
                boyut = hedef.stat().st_size
                self.send_response(HTTPStatus.OK)
                self.send_header("Content-Type", "application/x-ndjson")
                self.send_header("Content-Length", str(boyut))
                self.end_headers()
                with hedef.open("rb") as dosya:
                    while parca := dosya.read(1024 * 1024):
                        self.wfile.write(parca)
                return
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
                sayfa, hatali = dogrula(govde, args.beklenen_sayfa)
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
    print(f"Runner: {calistirici_yolu}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), Istek).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
