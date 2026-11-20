"""Belgelerden metin çıkarma — PDF / DOCX / TXT (kitap boyu projeler için).

PDF çıkarımında satır içi kırılmalar onarılır: cümle ortasında biten satırlar
birleştirilir, tire ile bölünmüş kelimeler ("kelime-\\nler") yapıştırılır;
çift satır sonu paragraf sınırı olarak korunur.
"""
from __future__ import annotations

import io
import re

SUPPORTED_EXTS = {"pdf", "docx", "txt", "md"}


def _clean_pdf_text(raw: str) -> str:
    # Tireyle bölünmüş kelimeleri yapıştır: "geliş-\ntirme" → "geliştirme"
    text = re.sub(r"(\w)-\n(\w)", r"\1\2", raw)
    # 3+ satır sonu → paragraf sınırı işareti
    text = re.sub(r"\n{2,}", "\x00", text)
    # Kalan tekil satır sonları çoğunlukla dizgi kırılmasıdır → boşluk
    text = text.replace("\n", " ")
    text = text.replace("\x00", "\n\n")
    # Sayfa numarası artıkları: tek başına duran kısa rakam satırları zaten
    # yukarıda paragrafa karışır; en azından çoklu boşlukları topla
    return re.sub(r"[ \t]{2,}", " ", text).strip()


def _extract_pdf(data: bytes) -> str:
    from pypdf import PdfReader

    reader = PdfReader(io.BytesIO(data))
    pages = []
    for page in reader.pages:
        t = page.extract_text() or ""
        if t.strip():
            pages.append(t)
    if not pages:
        raise ValueError(
            "PDF'ten metin çıkarılamadı — dosya taranmış görüntü olabilir "
            "(OCR gerekir)."
        )
    return _clean_pdf_text("\n\n".join(pages))


def _extract_docx(data: bytes) -> str:
    from docx import Document

    doc = Document(io.BytesIO(data))
    paragraphs = [p.text.strip() for p in doc.paragraphs if p.text.strip()]
    if not paragraphs:
        raise ValueError("Word belgesinde metin bulunamadı.")
    return "\n\n".join(paragraphs)


def _extract_txt(data: bytes) -> str:
    for encoding in ("utf-8", "cp1254", "latin-5"):
        try:
            text = data.decode(encoding)
            break
        except (UnicodeDecodeError, LookupError):
            continue
    else:
        text = data.decode("utf-8", errors="replace")
    text = text.replace("\r\n", "\n")
    if not text.strip():
        raise ValueError("Dosya boş.")
    return text.strip()


def extract_text(filename: str, data: bytes) -> str:
    """Dosya uzantısına göre metin çıkarır; desteklenmeyen tipte ValueError."""
    ext = (filename or "").lower().rsplit(".", 1)[-1]
    if ext == "pdf":
        return _extract_pdf(data)
    if ext == "docx":
        return _extract_docx(data)
    if ext in ("txt", "md"):
        return _extract_txt(data)
    raise ValueError(
        f"Desteklenmeyen dosya türü: .{ext} — PDF, DOCX veya TXT yükleyin."
    )
