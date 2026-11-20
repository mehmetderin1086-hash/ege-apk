from __future__ import annotations

import re
import threading
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from downloadhub.config import AppSettings

PAYLOAD = (b"DownloadHub integration payload\n" * 8192) + b"done"


class RangeHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self) -> None:  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="payload.bin"')
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("ETag", '"downloadhub-test"')
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        start = 0
        range_header = self.headers.get("Range")
        if range_header:
            match = re.match(r"bytes=(\d+)-", range_header)
            if match:
                start = int(match.group(1))
        body = PAYLOAD[start:]
        self.send_response(206 if start else 200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(len(body)))
        if start:
            self.send_header("Content-Range", f"bytes {start}-{len(PAYLOAD) - 1}/{len(PAYLOAD)}")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, _format: str, *_args: object) -> None:
        return


@pytest.fixture
def file_server() -> Iterator[str]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), RangeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/payload.bin"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@pytest.fixture
def app_settings(tmp_path: Path) -> AppSettings:
    return AppSettings(
        data_dir=tmp_path / "data",
        cache_dir=tmp_path / "cache",
        log_dir=tmp_path / "logs",
        download_dir=tmp_path / "downloads",
        database_url=f"sqlite+aiosqlite:///{tmp_path / 'downloadhub.db'}",
        allow_private_networks=True,
        max_concurrent_jobs=2,
    )
