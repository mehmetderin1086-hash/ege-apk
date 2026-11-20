"""Sayfa düzenleme işlemleri: birleştir, böl, döndür, sırala, sil, çıkar, kırp."""
from __future__ import annotations

from pathlib import Path

import fitz

from .common import PdfError, open_pdf as _open, parse_page_ranges


def merge(paths: list[Path]) -> bytes:
    """Birden çok PDF'i sırayla birleştirir."""
    if len(paths) < 2:
        raise PdfError("Birleştirmek için en az 2 PDF gerekli.")
    out = fitz.open()
    try:
        for p in paths:
            with fitz.open(p) as src:
                if src.needs_pass:
                    raise PdfError(f"'{p.name}' parola korumalı; önce şifresini kaldırın.")
                out.insert_pdf(src)
        return out.tobytes(garbage=4, deflate=True)
    finally:
        out.close()


def split_ranges(path: Path, ranges: list[str], password: str | None = None) -> list[tuple[str, bytes]]:
    """Her aralık için ayrı bir PDF üretir. Döndürülen: [(ad, veri), ...]."""
    outputs: list[tuple[str, bytes]] = []
    with _open(path, password) as doc:
        n = doc.page_count
        stem = path.stem
        for idx, spec in enumerate(ranges, start=1):
            pages = parse_page_ranges(spec, n)
            new = fitz.open()
            for pi in pages:
                new.insert_pdf(doc, from_page=pi, to_page=pi)
            data = new.tobytes(garbage=4, deflate=True)
            new.close()
            outputs.append((f"{stem}_bolum{idx}.pdf", data))
    return outputs


def split_every(path: Path, n_pages: int, password: str | None = None) -> list[tuple[str, bytes]]:
    """Belgeyi her ``n_pages`` sayfada bir böler."""
    if n_pages < 1:
        raise PdfError("Sayfa sayısı en az 1 olmalı.")
    outputs: list[tuple[str, bytes]] = []
    with _open(path, password) as doc:
        total = doc.page_count
        stem = path.stem
        part = 1
        for start in range(0, total, n_pages):
            end = min(start + n_pages - 1, total - 1)
            new = fitz.open()
            new.insert_pdf(doc, from_page=start, to_page=end)
            outputs.append((f"{stem}_bolum{part}.pdf", new.tobytes(garbage=4, deflate=True)))
            new.close()
            part += 1
    return outputs


def extract_pages(path: Path, spec: str, password: str | None = None) -> bytes:
    """Belirtilen sayfaları tek bir yeni PDF olarak çıkarır."""
    with _open(path, password) as doc:
        pages = parse_page_ranges(spec, doc.page_count)
        new = fitz.open()
        for pi in pages:
            new.insert_pdf(doc, from_page=pi, to_page=pi)
        data = new.tobytes(garbage=4, deflate=True)
        new.close()
        return data


def delete_pages(path: Path, spec: str, password: str | None = None) -> bytes:
    """Belirtilen sayfaları siler."""
    with _open(path, password) as doc:
        to_delete = sorted(set(parse_page_ranges(spec, doc.page_count)))
        if len(to_delete) >= doc.page_count:
            raise PdfError("Tüm sayfaları silemezsiniz.")
        doc.delete_pages(to_delete)
        return doc.tobytes(garbage=4, deflate=True)


def reorder(path: Path, order: list[int], password: str | None = None) -> bytes:
    """Sayfaları verilen 0 tabanlı sıraya göre yeniden düzenler.

    ``order`` mevcut tüm sayfaları (silinmeyecek olanları) içermelidir.
    """
    with _open(path, password) as doc:
        n = doc.page_count
        for i in order:
            if i < 0 or i >= n:
                raise PdfError(f"Geçersiz sayfa indeksi: {i}")
        new = fitz.open()
        for i in order:
            new.insert_pdf(doc, from_page=i, to_page=i)
        data = new.tobytes(garbage=4, deflate=True)
        new.close()
        return data


def compose(path: Path, pages: list[dict], password: str | None = None) -> bytes:
    """Sayfaları verilen sıra + döndürme ile yeniden oluşturur.

    ``pages`` = [{"index": 0 tabanlı kaynak sayfa, "rotation": eklenecek açı}, ...]
    Listede olmayan sayfalar silinmiş sayılır.
    """
    with _open(path, password) as doc:
        n = doc.page_count
        new = fitz.open()
        try:
            for item in pages:
                i = int(item.get("index", -1))
                if i < 0 or i >= n:
                    raise PdfError(f"Geçersiz sayfa indeksi: {i}")
                new.insert_pdf(doc, from_page=i, to_page=i)
                rot = int(item.get("rotation", 0)) % 360
                if rot:
                    pg = new.load_page(new.page_count - 1)
                    pg.set_rotation((pg.rotation + rot) % 360)
            if new.page_count == 0:
                raise PdfError("Belgede en az bir sayfa kalmalı.")
            return new.tobytes(garbage=4, deflate=True)
        finally:
            new.close()


def rotate(path: Path, spec: str | None, degrees: int, password: str | None = None) -> bytes:
    """Sayfaları döndürür. ``spec`` boşsa tüm sayfalar döner."""
    if degrees % 90 != 0:
        raise PdfError("Döndürme açısı 90'ın katı olmalı (90, 180, 270).")
    with _open(path, password) as doc:
        if spec and spec.strip():
            targets = set(parse_page_ranges(spec, doc.page_count))
        else:
            targets = set(range(doc.page_count))
        for i in targets:
            page = doc.load_page(i)
            page.set_rotation((page.rotation + degrees) % 360)
        return doc.tobytes(garbage=4, deflate=True)


def crop(path: Path, margins: dict, spec: str | None = None, password: str | None = None) -> bytes:
    """Sayfaları kırpar. ``margins`` = {left, top, right, bottom} (puan/points).

    Değerler her kenardan içeri doğru kırpılacak miktardır.
    """
    left = float(margins.get("left", 0) or 0)
    top = float(margins.get("top", 0) or 0)
    right = float(margins.get("right", 0) or 0)
    bottom = float(margins.get("bottom", 0) or 0)
    with _open(path, password) as doc:
        if spec and spec.strip():
            targets = set(parse_page_ranges(spec, doc.page_count))
        else:
            targets = set(range(doc.page_count))
        for i in targets:
            page = doc.load_page(i)
            r = page.rect
            new_rect = fitz.Rect(
                r.x0 + left, r.y0 + top, r.x1 - right, r.y1 - bottom
            )
            if new_rect.width <= 10 or new_rect.height <= 10:
                raise PdfError("Kırpma değerleri çok büyük; sayfa kalmıyor.")
            page.set_cropbox(new_rect)
        return doc.tobytes(garbage=4, deflate=True)
