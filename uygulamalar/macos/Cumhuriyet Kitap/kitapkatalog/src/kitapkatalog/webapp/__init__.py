"""Tarayıcıda çalışan yerel web arayüzü (FastAPI, yalnız 127.0.0.1)."""

from kitapkatalog.webapp.app import create_app

__all__ = ["create_app"]
