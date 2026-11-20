"""Meta veri (başlık, yazar, konu, anahtar kelime) okuma ve yazma."""
from __future__ import annotations

from pathlib import Path

import fitz

from .common import PdfError


def _open(path: Path, password: str | None = None) -> fitz.Document:
    doc = fitz.open(path)
    if doc.needs_pass:
        if not password or not doc.authenticate(password):
            doc.close()
            raise PdfError("Belge parola korumalı; işlem için doğru parola gerekli.")
    return doc


def read(path: Path, password: str | None = None) -> dict:
    with _open(path, password) as doc:
        md = dict(doc.metadata or {})
        md["page_count"] = doc.page_count
        return md


def write(path: Path, fields: dict, password: str | None = None) -> bytes:
    """Meta verileri günceller. Kabul edilen anahtarlar: title, author,
    subject, keywords, creator, producer."""
    allowed = {"title", "author", "subject", "keywords", "creator", "producer"}
    with _open(path, password) as doc:
        md = dict(doc.metadata or {})
        for k, v in fields.items():
            if k in allowed:
                md[k] = v or ""
        doc.set_metadata(md)
        return doc.tobytes(garbage=4, deflate=True)
