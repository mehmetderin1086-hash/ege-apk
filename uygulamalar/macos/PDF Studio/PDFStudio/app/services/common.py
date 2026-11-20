"""Servisler arası paylaşılan yardımcılar."""
from __future__ import annotations

import re
from pathlib import Path

import fitz


class PdfError(Exception):
    """Kullanıcıya gösterilebilir, Türkçe PDF işleme hatası."""


def open_pdf(path: Path, password: str | None = None) -> fitz.Document:
    """PDF'i açar; parola korumalıysa doğrular, yanlış/eksik parolada PdfError."""
    doc = fitz.open(path)
    if doc.needs_pass:
        if not password or not doc.authenticate(password):
            doc.close()
            raise PdfError("Belge parola korumalı; işlem için doğru parola gerekli.")
    return doc


def parse_page_ranges(spec: str, page_count: int) -> list[int]:
    """"1-3,5,8-10" gibi bir ifadeyi 0 tabanlı sayfa indeksleri listesine çevirir.

    Sayfa numaraları 1 tabanlıdır. Geçersiz/boş girdi hata fırlatır.
    Sonuç, girilen sıraya sadık kalır (yeniden sıralamada kullanışlı).
    """
    if not spec or not spec.strip():
        raise PdfError("Sayfa aralığı boş olamaz.")
    result: list[int] = []
    for chunk in spec.split(","):
        chunk = chunk.strip()
        if not chunk:
            continue
        m = re.fullmatch(r"(\d+)\s*-\s*(\d+)", chunk)
        if m:
            start, end = int(m.group(1)), int(m.group(2))
            if start < 1 or end < 1:
                raise PdfError(f"Geçersiz sayfa numarası: {chunk}")
            step = 1 if end >= start else -1
            for p in range(start, end + step, step):
                if p < 1 or p > page_count:
                    raise PdfError(
                        f"Sayfa {p} aralık dışında (belge {page_count} sayfa)."
                    )
                result.append(p - 1)
        elif chunk.isdigit():
            p = int(chunk)
            if p < 1 or p > page_count:
                raise PdfError(
                    f"Sayfa {p} aralık dışında (belge {page_count} sayfa)."
                )
            result.append(p - 1)
        else:
            raise PdfError(f"Geçersiz sayfa ifadesi: '{chunk}'")
    if not result:
        raise PdfError("Geçerli sayfa bulunamadı.")
    return result


def hex_to_rgb01(color: str) -> tuple[float, float, float]:
    """'#RRGGBB' veya 'RRGGBB' -> (r, g, b) 0..1 aralığında."""
    if not color:
        return (0.0, 0.0, 0.0)
    c = color.strip().lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    if len(c) != 6:
        return (0.0, 0.0, 0.0)
    try:
        r = int(c[0:2], 16) / 255.0
        g = int(c[2:4], 16) / 255.0
        b = int(c[4:6], 16) / 255.0
    except ValueError:
        return (0.0, 0.0, 0.0)
    return (r, g, b)


def stem(name: str) -> str:
    return Path(name).stem


def with_suffix_name(name: str, suffix: str, ext: str = ".pdf") -> str:
    """'belge.pdf' + '_sikistirilmis' -> 'belge_sikistirilmis.pdf'."""
    return f"{Path(name).stem}{suffix}{ext}"
