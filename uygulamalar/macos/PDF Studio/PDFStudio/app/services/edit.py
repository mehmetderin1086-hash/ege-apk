"""Düzenleme işlemleri: filigran, sayfa no, üst/alt bilgi, redaksiyon, anotasyonlar."""
from __future__ import annotations

import io
from pathlib import Path

import fitz

from .common import PdfError, hex_to_rgb01, open_pdf as _open, parse_page_ranges


_POSITIONS = {
    "ust-sol", "ust-orta", "ust-sag",
    "orta-sol", "orta", "orta-sag",
    "alt-sol", "alt-orta", "alt-sag",
}


def _anchor_point(rect: fitz.Rect, position: str, margin: float = 36.0) -> tuple[float, float, str]:
    """Konum adına göre (x, y, hizalama) döndürür. y metin taban çizgisi içindir."""
    x_left = rect.x0 + margin
    x_center = (rect.x0 + rect.x1) / 2
    x_right = rect.x1 - margin
    y_top = rect.y0 + margin
    y_mid = (rect.y0 + rect.y1) / 2
    y_bot = rect.y1 - margin

    vpos, _, hpos = position.partition("-")
    if position == "orta":
        return x_center, y_mid, "center"
    y = {"ust": y_top, "orta": y_mid, "alt": y_bot}.get(vpos, y_bot)
    if hpos == "sol":
        return x_left, y, "left"
    if hpos == "sag":
        return x_right, y, "right"
    return x_center, y, "center"


def watermark_text(
    path: Path,
    text: str,
    *,
    opacity: float = 0.25,
    rotation: int = 45,
    fontsize: int = 48,
    color: str = "#888888",
    spec: str | None = None,
    tiled: bool = False,
    password: str | None = None,
) -> bytes:
    """Metin filigranı ekler (sayfanın ortasına veya döşeli)."""
    if not text or not text.strip():
        raise PdfError("Filigran metni boş olamaz.")
    rgb = hex_to_rgb01(color)
    # Herhangi bir açıda döndürme için matris (insert_text yalnızca 0/90/180/270
    # kabul ettiğinden morph kullanıyoruz).
    rot_matrix = fitz.Matrix(1, 1).prerotate(-rotation)
    text_w = fitz.get_text_length(text, fontname="helv", fontsize=fontsize)
    with _open(path, password) as doc:
        targets = (
            set(parse_page_ranges(spec, doc.page_count))
            if spec and spec.strip() else set(range(doc.page_count))
        )
        for i in targets:
            page = doc.load_page(i)
            r = page.rect
            if tiled:
                step_x = max(150, int(text_w + fontsize * 2))
                step_y = max(120, fontsize * 4)
                y = r.y0 + step_y / 2
                while y < r.y1:
                    x = r.x0 + step_x / 2
                    while x < r.x1:
                        pivot = fitz.Point(x, y)
                        page.insert_text(
                            (x - text_w / 2, y), text, fontsize=fontsize, fontname="helv",
                            color=rgb, fill_opacity=opacity, morph=(pivot, rot_matrix),
                        )
                        x += step_x
                    y += step_y
            else:
                cx, cy = (r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2
                pivot = fitz.Point(cx, cy)
                page.insert_text(
                    (cx - text_w / 2, cy), text,
                    fontsize=fontsize, fontname="helv", color=rgb,
                    fill_opacity=opacity, morph=(pivot, rot_matrix),
                )
        return doc.tobytes(garbage=4, deflate=True)


def watermark_image(
    path: Path, image_bytes: bytes, *, opacity: float = 0.3,
    scale: float = 0.5, spec: str | None = None, password: str | None = None,
) -> bytes:
    """Görsel filigran ekler (sayfa ortasına)."""
    with _open(path, password) as doc:
        targets = (
            set(parse_page_ranges(spec, doc.page_count))
            if spec and spec.strip() else set(range(doc.page_count))
        )
        for i in targets:
            page = doc.load_page(i)
            r = page.rect
            w = r.width * scale
            h = r.height * scale
            x0 = (r.width - w) / 2 + r.x0
            y0 = (r.height - h) / 2 + r.y0
            rect = fitz.Rect(x0, y0, x0 + w, y0 + h)
            page.insert_image(rect, stream=image_bytes, overlay=True, keep_proportion=True)
        return doc.tobytes(garbage=4, deflate=True)


def page_numbers(
    path: Path, *, position: str = "alt-orta", start_at: int = 1,
    fmt: str = "{n}", fontsize: int = 11, color: str = "#333333",
    spec: str | None = None, margin: float = 28.0, password: str | None = None,
) -> bytes:
    """Sayfa numarası ekler. ``fmt`` içinde {n} numara, {total} toplam."""
    if position not in _POSITIONS:
        position = "alt-orta"
    rgb = hex_to_rgb01(color)
    with _open(path, password) as doc:
        total = doc.page_count
        targets = (
            parse_page_ranges(spec, total) if spec and spec.strip()
            else list(range(total))
        )
        counter = start_at
        for i in targets:
            page = doc.load_page(i)
            label = fmt.replace("{n}", str(counter)).replace("{total}", str(total))
            x, y, align = _anchor_point(page.rect, position, margin)
            align_map = {"left": fitz.TEXT_ALIGN_LEFT, "center": fitz.TEXT_ALIGN_CENTER,
                         "right": fitz.TEXT_ALIGN_RIGHT}
            box = fitz.Rect(page.rect.x0 + 10, y - fontsize, page.rect.x1 - 10, y + fontsize)
            page.insert_textbox(box, label, fontsize=fontsize, fontname="helv",
                                color=rgb, align=align_map[align])
            counter += 1
        return doc.tobytes(garbage=4, deflate=True)


def header_footer(
    path: Path, *, header: str = "", footer: str = "", fontsize: int = 10,
    color: str = "#555555", password: str | None = None,
) -> bytes:
    """Her sayfaya üst ve/veya alt bilgi ekler."""
    rgb = hex_to_rgb01(color)
    with _open(path, password) as doc:
        for page in doc:
            r = page.rect
            if header:
                box = fitz.Rect(r.x0 + 36, r.y0 + 12, r.x1 - 36, r.y0 + 12 + fontsize * 2)
                page.insert_textbox(box, header, fontsize=fontsize, fontname="helv",
                                    color=rgb, align=fitz.TEXT_ALIGN_CENTER)
            if footer:
                box = fitz.Rect(r.x0 + 36, r.y1 - 12 - fontsize * 2, r.x1 - 36, r.y1 - 12)
                page.insert_textbox(box, footer, fontsize=fontsize, fontname="helv",
                                    color=rgb, align=fitz.TEXT_ALIGN_CENTER)
        return doc.tobytes(garbage=4, deflate=True)


def redact(path: Path, boxes: list[dict], password: str | None = None) -> bytes:
    """Verilen dikdörtgenleri kalıcı olarak karartır (içerik silinir).

    boxes: [{page:int, x0,y0,x1,y1 (PDF puanı), color?: '#000000'}]
    """
    with _open(path, password) as doc:
        by_page: dict[int, list[dict]] = {}
        for b in boxes:
            by_page.setdefault(int(b["page"]), []).append(b)
        for pno, items in by_page.items():
            if pno < 0 or pno >= doc.page_count:
                continue
            page = doc.load_page(pno)
            for b in items:
                rect = fitz.Rect(b["x0"], b["y0"], b["x1"], b["y1"])
                fill = hex_to_rgb01(b.get("color", "#000000"))
                page.add_redact_annot(rect, fill=fill)
            page.apply_redactions()
        return doc.tobytes(garbage=4, deflate=True)


# ---------------------------------------------------------------------------
# EDİTÖR ANOTASYONLARI (tarayıcıdan gelen JSON'u PDF'e uygula)
# ---------------------------------------------------------------------------

def apply_annotations(
    path: Path, annotations: list[dict], images: dict[str, bytes] | None = None,
    password: str | None = None,
) -> bytes:
    """Editörde oluşturulan öğeleri PDF'e kalıcı yazar.

    Her öğe ``page`` (0 tabanlı) ve ``type`` içerir. Koordinatlar PDF puanı
    (points, sol-üst köşe orijin) cinsindendir.

    Desteklenen type'lar: text, rect, ellipse, line, arrow, freehand,
    highlight, image, signature (image ile aynı).
    """
    images = images or {}
    with _open(path, password) as doc:
        for a in annotations:
            try:
                pno = int(a.get("page", 0))
            except (TypeError, ValueError):
                continue
            if pno < 0 or pno >= doc.page_count:
                continue
            page = doc.load_page(pno)
            _apply_one(page, a, images)
        return doc.tobytes(garbage=4, deflate=True)


def _apply_one(page: fitz.Page, a: dict, images: dict[str, bytes]) -> None:
    t = a.get("type")
    color = hex_to_rgb01(a.get("color", "#000000"))
    width = float(a.get("width", 1.5) or 1.5)
    opacity = float(a.get("opacity", 1.0) or 1.0)

    if t == "text":
        text = a.get("text", "")
        fontsize = float(a.get("fontsize", 14) or 14)
        x = float(a.get("x", 0)); y = float(a.get("y", 0))
        w = float(a.get("w", 300) or 300); h = float(a.get("h", fontsize * 2) or fontsize * 2)
        bold = a.get("bold"); italic = a.get("italic")
        fontname = "helv"
        if bold and italic:
            fontname = "hebi"
        elif bold:
            fontname = "hebo"
        elif italic:
            fontname = "heit"
        rect = fitz.Rect(x, y, x + w, y + h)
        page.insert_textbox(rect, text, fontsize=fontsize, fontname=fontname,
                            color=color, fill_opacity=opacity)

    elif t == "rect":
        rect = fitz.Rect(a["x"], a["y"], a["x"] + a["w"], a["y"] + a["h"])
        fill = hex_to_rgb01(a["fill"]) if a.get("fill") else None
        shape = page.new_shape()
        shape.draw_rect(rect)
        shape.finish(color=color, fill=fill, width=width, fill_opacity=opacity,
                     stroke_opacity=opacity)
        shape.commit()

    elif t == "ellipse":
        rect = fitz.Rect(a["x"], a["y"], a["x"] + a["w"], a["y"] + a["h"])
        fill = hex_to_rgb01(a["fill"]) if a.get("fill") else None
        shape = page.new_shape()
        shape.draw_oval(rect)
        shape.finish(color=color, fill=fill, width=width, fill_opacity=opacity,
                     stroke_opacity=opacity)
        shape.commit()

    elif t in ("line", "arrow"):
        p1 = fitz.Point(a["x1"], a["y1"])
        p2 = fitz.Point(a["x2"], a["y2"])
        shape = page.new_shape()
        shape.draw_line(p1, p2)
        if t == "arrow":
            _draw_arrowhead(shape, p1, p2)
        shape.finish(color=color, width=width, stroke_opacity=opacity)
        shape.commit()

    elif t == "freehand":
        pts = a.get("points", [])
        if len(pts) >= 2:
            shape = page.new_shape()
            for j in range(len(pts) - 1):
                shape.draw_line(fitz.Point(pts[j][0], pts[j][1]),
                                fitz.Point(pts[j + 1][0], pts[j + 1][1]))
            shape.finish(color=color, width=width, stroke_opacity=opacity,
                         lineCap=1, lineJoin=1)
            shape.commit()

    elif t == "highlight":
        rect = fitz.Rect(a["x"], a["y"], a["x"] + a["w"], a["y"] + a["h"])
        hl_color = hex_to_rgb01(a.get("color", "#ffeb3b"))
        shape = page.new_shape()
        shape.draw_rect(rect)
        shape.finish(fill=hl_color, color=None, fill_opacity=float(a.get("opacity", 0.35) or 0.35))
        shape.commit()

    elif t in ("image", "signature"):
        ref = a.get("image_ref")
        data = images.get(ref) if ref else None
        if data is None and a.get("data_url"):
            data = _decode_data_url(a["data_url"])
        if data:
            rect = fitz.Rect(a["x"], a["y"], a["x"] + a["w"], a["y"] + a["h"])
            page.insert_image(rect, stream=data, overlay=True, keep_proportion=True)


def _draw_arrowhead(shape: fitz.Shape, p1: fitz.Point, p2: fitz.Point, size: float = 10.0) -> None:
    import math
    angle = math.atan2(p2.y - p1.y, p2.x - p1.x)
    for da in (math.radians(150), math.radians(-150)):
        hx = p2.x + size * math.cos(angle + da)
        hy = p2.y + size * math.sin(angle + da)
        shape.draw_line(p2, fitz.Point(hx, hy))


def _decode_data_url(data_url: str) -> bytes | None:
    import base64
    if "," not in data_url:
        return None
    try:
        return base64.b64decode(data_url.split(",", 1)[1])
    except Exception:  # noqa: BLE001
        return None
