"""PDF Studio'yu başlatır: sunucuyu ayağa kaldırır ve tarayıcıyı açar."""
from __future__ import annotations

import os
import threading
import webbrowser

import uvicorn

from app import config


def _open_browser() -> None:
    url = f"http://{config.HOST}:{config.PORT}"
    try:
        webbrowser.open(url)
    except Exception:  # noqa: BLE001
        pass


def main() -> None:
    print("=" * 52)
    print("  PDF Studio başlatılıyor…")
    print(f"  Adres: http://{config.HOST}:{config.PORT}")
    print("  Kapatmak için: Ctrl+C")
    print("=" * 52)
    # Masaüstü .app başlatıcısı hazır olmayı kendisi bekler; doğrudan komut satırı
    # kullanımında mevcut otomatik tarayıcı davranışı korunur.
    if os.environ.get("PDFSTUDIO_OPEN_BROWSER", "1") == "1":
        threading.Timer(1.5, _open_browser).start()
    uvicorn.run("app.main:app", host=config.HOST, port=config.PORT, reload=False)


if __name__ == "__main__":
    main()
