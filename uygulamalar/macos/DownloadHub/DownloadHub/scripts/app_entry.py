"""PyInstaller entry point for the macOS app bundle."""

from __future__ import annotations

import os
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path


def bundled_root() -> Path:
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[1]))


def configure_bundled_runtimes() -> None:
    runtime_bin = bundled_root() / "runtime" / "bin"
    variables = {
        "aria2c": "DOWNLOADHUB_ARIA2_PATH",
        "ffmpeg": "DOWNLOADHUB_FFMPEG_PATH",
        "deno": "DOWNLOADHUB_DENO_PATH",
        "yt-dlp": "DOWNLOADHUB_YT_DLP_PATH",
    }
    for filename, variable in variables.items():
        candidate = runtime_bin / filename
        if candidate.is_file():
            os.environ[variable] = str(candidate)


def open_when_ready(port: int) -> None:
    url = f"http://127.0.0.1:{port}"
    for _ in range(120):
        for endpoint in ("/health", "/healthz", "/api/v1/health", "/"):
            try:
                with urllib.request.urlopen(url + endpoint, timeout=0.5):  # noqa: S310
                    webbrowser.open(url)
                    return
            except (urllib.error.URLError, TimeoutError):
                continue
        time.sleep(0.25)


def dispatch_embedded_module() -> bool:
    """Emulate ``python -m yt_dlp`` when the frozen executable calls itself."""
    if sys.argv[1:3] != ["-m", "yt_dlp"]:
        return False
    sys.argv = [sys.argv[0], *sys.argv[3:]]
    from yt_dlp import main as yt_dlp_main

    yt_dlp_main()
    return True


def main() -> None:
    if dispatch_embedded_module():
        return
    sys.argv = [argument for argument in sys.argv if not argument.startswith("-psn_")]
    os.environ["DOWNLOADHUB_HOST"] = "127.0.0.1"
    port = int(os.environ.setdefault("DOWNLOADHUB_PORT", "8765"))
    configure_bundled_runtimes()
    if os.environ.get("DOWNLOADHUB_OPEN_BROWSER", "1") == "1":
        threading.Thread(target=open_when_ready, args=(port,), daemon=True).start()
    from downloadhub.main import main as application_main

    application_main()


if __name__ == "__main__":
    main()
