"""Servis katmanı (PyMuPDF/pikepdf) birim testleri."""
from __future__ import annotations

from pathlib import Path

import fitz
import pytest

from app.services import convert, edit, metadata, optimize, organize, security
from app.services.common import PdfError, parse_page_ranges


def _pages(data: bytes) -> int:
    with fitz.open("pdf", data) as d:
        return d.page_count


# ---- common ----
def test_parse_page_ranges():
    assert parse_page_ranges("1-3,5", 10) == [0, 1, 2, 4]
    assert parse_page_ranges("3-1", 10) == [2, 1, 0]
    with pytest.raises(PdfError):
        parse_page_ranges("50", 10)
    with pytest.raises(PdfError):
        parse_page_ranges("abc", 10)


# ---- organize ----
def test_merge(sample_pdf):
    data = organize.merge([sample_pdf, sample_pdf])
    assert _pages(data) == 8


def test_split_and_extract(sample_pdf):
    parts = organize.split_ranges(sample_pdf, ["1-2", "3-4"])
    assert len(parts) == 2
    assert _pages(parts[0][1]) == 2
    every = organize.split_every(sample_pdf, 2)
    assert len(every) == 2
    assert _pages(organize.extract_pages(sample_pdf, "1,3")) == 2


def test_delete_reorder_rotate_crop_compose(sample_pdf):
    assert _pages(organize.delete_pages(sample_pdf, "2")) == 3
    assert _pages(organize.reorder(sample_pdf, [3, 2, 1, 0])) == 4
    assert _pages(organize.rotate(sample_pdf, None, 90)) == 4
    assert _pages(organize.crop(sample_pdf, {"left": 10, "top": 10, "right": 10, "bottom": 10})) == 4
    composed = organize.compose(sample_pdf, [{"index": 3, "rotation": 90}, {"index": 0}])
    assert _pages(composed) == 2


def test_merge_requires_two(sample_pdf):
    with pytest.raises(PdfError):
        organize.merge([sample_pdf])


# ---- optimize ----
def test_compress(sample_pdf):
    data, meta = optimize.compress(sample_pdf, "orta")
    assert _pages(data) == 4
    assert "new_size" in meta


def test_repair(sample_pdf):
    assert _pages(optimize.repair(sample_pdf)) == 4


# ---- convert ----
def test_images_to_pdf(sample_image):
    data = convert.images_to_pdf([sample_image], "a4")
    assert _pages(data) == 1


def test_text_and_html_to_pdf():
    assert _pages(convert.text_to_pdf("Merhaba\nDünya çğ")) >= 1
    assert _pages(convert.html_to_pdf("<h1>Başlık</h1><p>x</p>")) >= 1


def test_pdf_to_images_and_text(sample_pdf):
    imgs = convert.pdf_to_images(sample_pdf, "png", 100)
    assert len(imgs) == 4
    txt = convert.pdf_to_text(sample_pdf)
    assert "Sayfa 1" in txt.decode("utf-8")


def test_pdf_to_word(sample_pdf, tmp_path):
    out = tmp_path / "cikti.docx"
    convert.pdf_to_word(sample_pdf, out)
    assert out.exists() and out.stat().st_size > 0


# ---- edit ----
def test_watermark_and_numbers(sample_pdf):
    assert _pages(edit.watermark_text(sample_pdf, "GİZLİ", rotation=45)) == 4
    assert _pages(edit.watermark_text(sample_pdf, "TASLAK", tiled=True)) == 4
    assert _pages(edit.page_numbers(sample_pdf, position="alt-orta", fmt="{n}/{total}")) == 4
    assert _pages(edit.header_footer(sample_pdf, header="Üst", footer="Alt")) == 4


def test_redact_and_annotate(sample_pdf):
    r = edit.redact(sample_pdf, [{"page": 0, "x0": 70, "y0": 80, "x1": 320, "y1": 100}])
    assert _pages(r) == 4
    annos = [
        {"page": 0, "type": "text", "text": "Not", "x": 50, "y": 50, "w": 200, "h": 40, "fontsize": 14},
        {"page": 0, "type": "rect", "x": 60, "y": 250, "w": 100, "h": 40, "color": "#ff0000"},
        {"page": 1, "type": "ellipse", "x": 60, "y": 250, "w": 100, "h": 60, "color": "#00aa00"},
        {"page": 1, "type": "arrow", "x1": 50, "y1": 50, "x2": 200, "y2": 150, "color": "#0000ff"},
        {"page": 2, "type": "freehand", "points": [[50, 50], [60, 70], [80, 60]]},
        {"page": 2, "type": "highlight", "x": 60, "y": 95, "w": 200, "h": 20, "color": "#ffeb3b"},
    ]
    assert _pages(edit.apply_annotations(sample_pdf, annos)) == 4


# ---- security ----
def test_protect_unlock(sample_pdf, tmp_path):
    enc = security.protect(sample_pdf, "sifre123")
    enc_path = tmp_path / "enc.pdf"
    enc_path.write_bytes(enc)
    with fitz.open("pdf", enc) as d:
        assert d.needs_pass
    dec = security.unlock(enc_path, "sifre123")
    with fitz.open("pdf", dec) as d:
        assert not d.needs_pass
    with pytest.raises(PdfError):
        security.unlock(enc_path, "yanlis")


def test_flatten(sample_pdf):
    assert _pages(security.flatten(sample_pdf)) == 4


# ---- metadata ----
def test_metadata(sample_pdf):
    data = metadata.write(sample_pdf, {"title": "Başlık", "author": "Yazar"})
    with fitz.open("pdf", data) as d:
        assert d.metadata["title"] == "Başlık"
