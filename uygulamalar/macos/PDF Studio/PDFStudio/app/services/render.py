"""Sayfa önizleme/thumbnail üretimi (PyMuPDF ile PNG).

Arka uçta render ederek tarayıcıda harici PDF.js/CDN bağımlılığını ortadan
kaldırırız.
"""
from __future__ import annotations

from pathlib import Path

import fitz  # PyMuPDF

from .. import config
from .common import PdfError


def page_count(path: Path) -> int:
    try:
        with fitz.open(path) as doc:
            return doc.page_count
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"PDF açılamadı: {exc}") from exc


def document_info(path: Path) -> dict:
    """Sayfa sayısı, boyutlar, şifreli mi vb. özet bilgi."""
    try:
        with fitz.open(path) as doc:
            encrypted = doc.needs_pass
            pages = []
            if not encrypted:
                for pg in doc:
                    r = pg.rect
                    pages.append(
                        {"width": round(r.width, 1), "height": round(r.height, 1),
                         "rotation": pg.rotation}
                    )
            return {
                "page_count": doc.page_count,
                "encrypted": encrypted,
                "metadata": doc.metadata or {},
                "pages": pages,
            }
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"PDF bilgisi okunamadı: {exc}") from exc


def render_page_png(
    path: Path,
    page_index: int,
    dpi: int = config.PREVIEW_DPI,
    password: str | None = None,
) -> bytes:
    """Belirli bir sayfayı PNG olarak render eder."""
    try:
        with fitz.open(path) as doc:
            if doc.needs_pass:
                if not password or not doc.authenticate(password):
                    raise PdfError("Belge parola korumalı; önizleme için parola gerekli.")
            if page_index < 0 or page_index >= doc.page_count:
                raise PdfError("Sayfa bulunamadı.")
            page = doc.load_page(page_index)
            zoom = dpi / 72.0
            mat = fitz.Matrix(zoom, zoom)
            pix = page.get_pixmap(matrix=mat, alpha=False)
            return pix.tobytes("png")
    except PdfError:
        raise
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"Sayfa render edilemedi: {exc}") from exc


def render_thumbnail_png(path: Path, page_index: int, password: str | None = None) -> bytes:
    return render_page_png(path, page_index, dpi=config.THUMBNAIL_DPI, password=password)
