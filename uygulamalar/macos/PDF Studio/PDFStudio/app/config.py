"""Uygulama yapılandırması ve dizin tanımları."""
from __future__ import annotations

import os
from pathlib import Path

# Proje kökü (app/ dizininin bir üstü)
BASE_DIR = Path(__file__).resolve().parent.parent

WEB_DIR = BASE_DIR / "web"
# Windows kurulumunda depolama, güncellemede silinen app dizini yerine
# kalıcı veri dizinine PDFSTUDIO_STORAGE ile yönlendirilir.
STORAGE_DIR = Path(os.environ.get("PDFSTUDIO_STORAGE", BASE_DIR / "storage"))
SESSIONS_DIR = STORAGE_DIR / "sessions"

# Yükleme/işleme limitleri
MAX_UPLOAD_BYTES = 200 * 1024 * 1024  # dosya başına 200 MB
MAX_FILES_PER_REQUEST = 100

# Oturum yaşam süresi (saniye) — bu süre boyunca dokunulmayan oturumlar temizlenir
SESSION_TTL_SECONDS = 6 * 60 * 60  # 6 saat

# Önizleme (thumbnail) render ölçeği
PREVIEW_DPI = 110
THUMBNAIL_DPI = 42

# Sunucu — 8000-8010 aralığı Sınav Okur'a ayrılı, PDF Studio 8060-8070 kullanır.
# Launcher taşma portu seçerse PDFSTUDIO_PORT ile ezer.
HOST = os.environ.get("PDFSTUDIO_HOST", "127.0.0.1")
PORT = int(os.environ.get("PDFSTUDIO_PORT", "8060"))

# /health imzası — launcher "portta gerçekten biz miyiz" kontrolünü bununla yapar
APP_ID = "pdf-studio"

# Kabul edilen uzantılar
PDF_EXTS = {".pdf"}
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff", ".webp"}
OFFICE_EXTS = {".docx", ".doc"}


def ensure_dirs() -> None:
    """Gerekli çalışma dizinlerini oluşturur."""
    STORAGE_DIR.mkdir(parents=True, exist_ok=True)
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
