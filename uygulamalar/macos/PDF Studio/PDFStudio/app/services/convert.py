"""Dönüştürme işlemleri: PDF'e ve PDF'ten."""
from __future__ import annotations

import html as html_lib
import io
import shutil
import subprocess
import tempfile
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


# ---------------------------------------------------------------------------
# PDF'E DÖNÜŞTÜR
# ---------------------------------------------------------------------------

def images_to_pdf(paths: list[Path], page_size: str = "auto", margin: int = 0) -> bytes:
    """Görselleri tek bir PDF'e dönüştürür (her görsel bir sayfa)."""
    from PIL import Image

    if not paths:
        raise PdfError("En az bir görsel gerekli.")
    doc = fitz.open()
    try:
        for p in paths:
            try:
                pil = Image.open(p)
            except Exception as exc:  # noqa: BLE001
                raise PdfError(f"'{p.name}' görseli açılamadı.") from exc
            if pil.mode in ("RGBA", "P", "LA"):
                pil = pil.convert("RGB")
            buf = io.BytesIO()
            pil.save(buf, format="JPEG", quality=90)
            img_bytes = buf.getvalue()
            iw, ih = pil.size

            if page_size == "a4":
                pw, ph = fitz.paper_size("a4")  # (595, 842)
            elif page_size == "letter":
                pw, ph = fitz.paper_size("letter")
            else:  # auto -> görsel boyutuna göre
                pw, ph = iw, ih

            page = doc.new_page(width=pw + 2 * margin, height=ph + 2 * margin)
            if page_size == "auto":
                rect = fitz.Rect(margin, margin, margin + iw, margin + ih)
            else:
                # Görseli sayfaya sığdır (oran koru)
                avail_w, avail_h = pw - 2 * margin, ph - 2 * margin
                scale = min(avail_w / iw, avail_h / ih)
                dw, dh = iw * scale, ih * scale
                x0 = margin + (avail_w - dw) / 2
                y0 = margin + (avail_h - dh) / 2
                rect = fitz.Rect(x0, y0, x0 + dw, y0 + dh)
            page.insert_image(rect, stream=img_bytes)
        return doc.tobytes(garbage=4, deflate=True)
    finally:
        doc.close()


def text_to_pdf(text: str, title: str = "Belge") -> bytes:
    """Düz metni A4 PDF'e döker."""
    safe = html_lib.escape(text or "").replace("\n", "<br/>")
    story_html = (
        "<div style='font-family:sans-serif;font-size:11pt;line-height:1.5'>"
        f"{safe}</div>"
    )
    return _html_to_pdf_bytes(story_html)


def html_to_pdf(html: str) -> bytes:
    """HTML içeriğini PDF'e dönüştürür (PyMuPDF Story)."""
    return _html_to_pdf_bytes(html or "<p></p>")


def _html_to_pdf_bytes(html: str, margin: int = 40) -> bytes:
    """HTML'i A4 sayfalara akıtıp PDF bayt dizisi üretir (Story + DocumentWriter)."""
    buf = io.BytesIO()
    mediabox = fitz.paper_rect("a4")
    where = mediabox + (margin, margin, -margin, -margin)
    writer = fitz.DocumentWriter(buf)
    try:
        story = fitz.Story(html=html)
        more = 1
        guard = 0
        while more and guard < 5000:
            guard += 1
            device = writer.begin_page(mediabox)
            more, _ = story.place(where)
            story.draw(device)
            writer.end_page()
    finally:
        writer.close()
    return buf.getvalue()


def word_to_pdf(path: Path) -> tuple[bytes, dict]:
    """Word (.docx) -> PDF.

    Sistemde LibreOffice/soffice varsa tam sadakatle; yoksa python-docx ile
    temel bir dönüşüm uygular.
    """
    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if soffice:
        with tempfile.TemporaryDirectory() as tmp:
            tmpdir = Path(tmp)
            src = tmpdir / path.name
            shutil.copy(path, src)
            try:
                subprocess.run(
                    [soffice, "--headless", "--convert-to", "pdf", "--outdir", str(tmpdir), str(src)],
                    check=True, capture_output=True, timeout=120,
                )
                out_pdf = src.with_suffix(".pdf")
                if out_pdf.exists():
                    return out_pdf.read_bytes(), {"engine": "libreoffice"}
            except Exception:  # noqa: BLE001
                pass  # fallback'e düş

    # Fallback: python-docx ile temel dönüşüm
    try:
        from docx import Document as DocxDocument
    except Exception as exc:  # noqa: BLE001
        raise PdfError("Word dönüştürme için gerekli modül yüklenemedi.") from exc

    try:
        docx = DocxDocument(str(path))
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"Word belgesi açılamadı: {exc}") from exc

    parts: list[str] = []
    for para in docx.paragraphs:
        style = (para.style.name or "").lower() if para.style else ""
        text = html_lib.escape(para.text)
        if not text.strip():
            parts.append("<br/>")
            continue
        if "heading 1" in style or style == "title":
            parts.append(f"<h1>{text}</h1>")
        elif "heading 2" in style:
            parts.append(f"<h2>{text}</h2>")
        elif "heading" in style:
            parts.append(f"<h3>{text}</h3>")
        else:
            parts.append(f"<p>{text}</p>")
    # Tabloları basitçe ekle
    for table in docx.tables:
        rows_html = []
        for row in table.rows:
            cells = "".join(
                f"<td style='border:1px solid #999;padding:4px'>{html_lib.escape(c.text)}</td>"
                for c in row.cells
            )
            rows_html.append(f"<tr>{cells}</tr>")
        parts.append(
            "<table style='border-collapse:collapse;width:100%'>" + "".join(rows_html) + "</table>"
        )
    body = "".join(parts) or "<p></p>"
    full_html = (
        "<div style='font-family:sans-serif;font-size:11pt;line-height:1.5'>" + body + "</div>"
    )
    doc = fitz.open()
    _render_html_story(doc, full_html)
    data = doc.tobytes(garbage=4, deflate=True)
    doc.close()
    return data, {"engine": "python-docx"}


# ---------------------------------------------------------------------------
# PDF'TEN DÖNÜŞTÜR
# ---------------------------------------------------------------------------

def pdf_to_images(path: Path, fmt: str = "png", dpi: int = 150, password: str | None = None) -> list[tuple[str, bytes]]:
    """Her sayfayı bir görsele dönüştürür."""
    fmt = fmt.lower()
    if fmt not in ("png", "jpg", "jpeg"):
        fmt = "png"
    ext = "jpg" if fmt in ("jpg", "jpeg") else "png"
    outputs: list[tuple[str, bytes]] = []
    zoom = dpi / 72.0
    with _open(path, password) as doc:
        stem = path.stem
        for i, page in enumerate(doc, start=1):
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
            if ext == "jpg":
                data = pix.tobytes("jpg", jpg_quality=90)
            else:
                data = pix.tobytes("png")
            outputs.append((f"{stem}_sayfa{i}.{ext}", data))
    return outputs


def pdf_to_text(path: Path, password: str | None = None) -> bytes:
    """Metni düz metin olarak çıkarır."""
    chunks: list[str] = []
    with _open(path, password) as doc:
        for i, page in enumerate(doc, start=1):
            chunks.append(f"--- Sayfa {i} ---\n{page.get_text()}\n")
    return "\n".join(chunks).encode("utf-8")


def pdf_to_word(path: Path, out_path: Path, password: str | None = None) -> dict:
    """PDF -> Word (.docx). pdf2docx kullanır."""
    try:
        from pdf2docx import Converter
    except Exception as exc:  # noqa: BLE001
        raise PdfError("PDF→Word için gerekli modül yüklenemedi.") from exc

    # pdf2docx şifreli dosyaları çözemez; gerekirse önce çözüp geçici dosyaya yaz
    src = path
    tmp_created: Path | None = None
    with fitz.open(path) as doc:
        if doc.needs_pass:
            if not password or not doc.authenticate(password):
                raise PdfError("Belge parola korumalı; doğru parola gerekli.")
            tmp_created = out_path.parent / (path.stem + "_cozulmus.pdf")
            tmp_created.write_bytes(doc.tobytes())
            src = tmp_created
    try:
        cv = Converter(str(src))
        cv.convert(str(out_path))
        cv.close()
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"PDF Word'e dönüştürülemedi: {exc}") from exc
    finally:
        if tmp_created and tmp_created.exists():
            tmp_created.unlink(missing_ok=True)
    return {"engine": "pdf2docx"}


def pdf_to_excel(path: Path, out_path: Path, password: str | None = None) -> dict:
    """PDF içindeki tabloları Excel'e (.xlsx) aktarır (PyMuPDF find_tables)."""
    try:
        from openpyxl import Workbook
    except Exception as exc:  # noqa: BLE001
        raise PdfError("Excel oluşturmak için gerekli modül yüklenemedi.") from exc

    wb = Workbook()
    wb.remove(wb.active)
    table_count = 0
    with _open(path, password) as doc:
        for pno, page in enumerate(doc, start=1):
            try:
                tabs = page.find_tables()
            except Exception:  # noqa: BLE001
                continue
            for ti, tab in enumerate(tabs.tables, start=1):
                table_count += 1
                ws = wb.create_sheet(title=f"S{pno}_T{ti}"[:31])
                for row in tab.extract():
                    ws.append([("" if c is None else str(c)) for c in row])
    if table_count == 0:
        # Tablo yoksa boş bir sayfa ekleyip kullanıcıyı uyaralım
        ws = wb.create_sheet(title="Bilgi")
        ws.append(["Bu PDF'te otomatik algılanabilen tablo bulunamadı."])
    wb.save(out_path)
    return {"tables": table_count}
