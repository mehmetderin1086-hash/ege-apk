from __future__ import annotations

import hashlib
import re
import threading
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

from downloadhub.engines.aria2 import Aria2Supervisor, DirectDownloadEngine
from downloadhub.models import DownloadJob
from downloadhub.runtime import RuntimeRegistry
from downloadhub.safe_proxy import SafeOutboundProxy

SEGMENT_PAYLOAD = bytes(range(256)) * 65_536  # 16 MiB, large enough for eight 1 MiB+ pieces.


class SegmentHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    range_starts: set[int] = set()
    range_lock = threading.Lock()

    def do_HEAD(self) -> None:  # noqa: N802
        self._headers(200, len(SEGMENT_PAYLOAD))

    def do_GET(self) -> None:  # noqa: N802
        start, end = 0, len(SEGMENT_PAYLOAD) - 1
        range_header = self.headers.get("Range")
        if range_header:
            match = re.fullmatch(r"bytes=(\d+)-(\d*)", range_header)
            if match:
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else end
                end = min(end, len(SEGMENT_PAYLOAD) - 1)
        with self.range_lock:
            self.range_starts.add(start)
        body = SEGMENT_PAYLOAD[start : end + 1]
        self._headers(206 if range_header else 200, len(body), start=start, end=end)
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # aria2 may close the initial stream once it has repartitioned the file.
            return

    def _headers(self, status: int, length: int, *, start: int = 0, end: int = 0) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Disposition", 'attachment; filename="segmented.bin"')
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("ETag", '"segment-test-v1"')
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(SEGMENT_PAYLOAD)}")
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


@pytest.fixture
def segment_server() -> Iterator[str]:
    SegmentHandler.range_starts.clear()
    server = ThreadingHTTPServer(("127.0.0.1", 0), SegmentHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}/segmented.bin"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


@pytest.mark.asyncio
async def test_real_aria2_uses_eight_segments(app_settings, segment_server: str) -> None:
    app_settings.split_count = 8
    app_settings.max_total_connections = 16
    app_settings.prepare()
    runtime = RuntimeRegistry(app_settings)
    if not runtime.aria2():
        pytest.skip("Doğrulanmış aria2 runtime kurulmamış")

    proxy = SafeOutboundProxy(app_settings)
    await proxy.start()
    supervisor = Aria2Supervisor(app_settings, runtime)
    assert await supervisor.start(), "aria2 JSON-RPC başlatılamadı"
    engine = DirectDownloadEngine(app_settings, supervisor)
    output = app_settings.download_dir / "Diğer" / "segmented.bin"
    job = DownloadJob(
        id="segmentedintegration000000000000",
        source_url=segment_server,
        final_url=segment_server,
        engine="direct",
        status="queued",
        title=output.name,
        category="Diğer",
        output_path=str(output),
        etag='"segment-test-v1"',
        options={},
    )

    async def progress(_values: dict) -> None:
        return

    try:
        result = Path(await engine.download(job, progress))
    finally:
        await supervisor.stop()
        await proxy.stop()

    expected = hashlib.sha256(SEGMENT_PAYLOAD).hexdigest()
    assert hashlib.sha256(result.read_bytes()).hexdigest() == expected
    assert len(SegmentHandler.range_starts) >= 8, SegmentHandler.range_starts
