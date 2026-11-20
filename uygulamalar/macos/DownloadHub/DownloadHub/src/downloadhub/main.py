from __future__ import annotations

import argparse
import threading
import webbrowser
from contextlib import suppress
from types import FrameType
from typing import Any

import uvicorn

from .config import get_settings


class DownloadHubServer(uvicorn.Server):
    """Close SSE subscribers as soon as a process shutdown signal arrives."""

    def handle_exit(self, sig: int, frame: FrameType | None) -> None:
        application: Any = self.config.app
        components = getattr(getattr(application, "state", None), "components", None)
        if components is not None:
            components.events.close_subscribers()
        super().handle_exit(sig, frame)


def main() -> None:
    settings = get_settings()
    parser = argparse.ArgumentParser(description="DownloadHub yerel indirme yöneticisi")
    parser.add_argument("--host", default=settings.host)
    parser.add_argument("--port", type=int, default=settings.port)
    parser.add_argument("--open", action="store_true", help="Web arayüzünü varsayılan tarayıcıda aç")
    parser.add_argument("--reload", action="store_true", help="Geliştirme için otomatik yeniden yükle")
    args = parser.parse_args()
    if args.host not in {"127.0.0.1", "localhost"}:
        parser.error("DownloadHub güvenlik nedeniyle yalnız loopback üzerinde çalışır")
    settings.host = "127.0.0.1"
    settings.port = args.port
    if args.open:
        threading.Timer(1.0, lambda: webbrowser.open(f"http://127.0.0.1:{args.port}")).start()
    if args.reload:
        uvicorn.run(
            "downloadhub.app:app",
            host="127.0.0.1",
            port=args.port,
            reload=True,
            timeout_graceful_shutdown=5,
        )
        return

    from .app import app as application

    server = DownloadHubServer(
        uvicorn.Config(
            application,
            host="127.0.0.1",
            port=args.port,
            timeout_graceful_shutdown=5,
        )
    )
    with suppress(KeyboardInterrupt):
        server.run()


if __name__ == "__main__":
    main()
