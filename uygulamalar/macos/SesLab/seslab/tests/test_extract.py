"""Belge metin çıkarma testleri (PDF/DOCX/TXT)."""
import io

import pytest

from app.core.extract import _clean_pdf_text, extract_text

# Bilinen-geçerli minimal PDF (tek sayfa, "Merhaba Dunya Test" metni)
MINIMAL_PDF = b"""%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 612 792]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj
4 0 obj<</Length 62>>stream
BT /F1 24 Tf 72 700 Td (Merhaba Dunya Test) Tj ET
endstream
endobj
5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj
xref
0 6
0000000000 65535 f
trailer<</Size 6/Root 1 0 R>>
startxref
0
%%EOF"""


def test_txt_utf8():
    text = extract_text("kitap.txt", "Türkçe karakterler: ğüşıöç\n\nİkinci paragraf.".encode())
    assert "ğüşıöç" in text
    assert "\n\n" in text


def test_txt_cp1254_fallback():
    data = "Türkçe yazı: şğı".encode("cp1254")
    text = extract_text("eski.txt", data)
    assert "şğı" in text


def test_docx():
    from docx import Document

    doc = Document()
    doc.add_paragraph("Birinci paragraf burada.")
    doc.add_paragraph("İkinci paragraf: Türkçe içerik ğüş.")
    buf = io.BytesIO()
    doc.save(buf)
    text = extract_text("belge.docx", buf.getvalue())
    assert "Birinci paragraf burada." in text
    assert "ğüş" in text
    assert text.count("\n\n") == 1  # iki paragraf


def test_pdf():
    text = extract_text("test.pdf", MINIMAL_PDF)
    assert "Merhaba Dunya Test" in text


def test_pdf_satir_onarimi():
    raw = "Bu cümle satır or-\ntasında bölündü ve devam\nediyor.\n\nYeni paragraf."
    out = _clean_pdf_text(raw)
    assert "ortasında" in out            # tire onarımı
    assert "devam ediyor" in out         # tekil \n → boşluk
    assert "\n\nYeni paragraf." in out   # paragraf korunur


def test_desteklenmeyen_tur():
    with pytest.raises(ValueError, match="Desteklenmeyen"):
        extract_text("resim.png", b"...")


def test_bos_txt():
    with pytest.raises(ValueError, match="boş"):
        extract_text("bos.txt", b"   ")
