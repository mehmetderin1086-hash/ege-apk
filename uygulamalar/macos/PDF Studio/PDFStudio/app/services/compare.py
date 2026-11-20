"""İki PDF'in metin ve görsel karşılaştırması."""
from __future__ import annotations

import difflib
import io
from pathlib import Path

import fitz

from .common import open_pdf

# Rapor başına sayfa çifti başına en fazla bu kadar satır farkı taşınır
_MAX_DIFF_LINES = 200
# Görsel karşılaştırmada en fazla bu kadar fark PNG'si üretilir (bellek sınırı)
MAX_DIFF_PAGES = 50
# Sayfa başına piksel bütçesi: dev sayfa geometrilerinde (ör. 14.400 pt) DPI
# otomatik düşürülür, yoksa tek sayfa GB'larca bellek isteyebilir
_MAX_PIXELS_PER_PAGE = 4_000_000


def compare_text(
    path_a: Path, path_b: Path,
    password_a: str | None = None, password_b: str | None = None,
) -> dict:
    """Sayfa sayfa metin benzerliği ve satır bazlı eklenen/çıkan farkları döndürür."""
    with open_pdf(path_a, password_a) as da, open_pdf(path_b, password_b) as db:
        count_a, count_b = da.page_count, db.page_count
        pairs: list[dict] = []
        ratios: list[float] = []
        for i in range(max(count_a, count_b)):
            text_a = da[i].get_text() if i < count_a else None
            text_b = db[i].get_text() if i < count_b else None
            if text_a is None or text_b is None:
                pairs.append({
                    "page": i + 1, "similarity": 0.0,
                    "missing_in": "a" if text_a is None else "b",
                    "added": [], "removed": [],
                })
                ratios.append(0.0)
                continue
            ratio = difflib.SequenceMatcher(None, text_a, text_b, autojunk=False).ratio()
            lines_a = [ln for ln in text_a.splitlines() if ln.strip()]
            lines_b = [ln for ln in text_b.splitlines() if ln.strip()]
            added: list[str] = []
            removed: list[str] = []
            if ratio < 1.0:
                for ln in difflib.ndiff(lines_a, lines_b):
                    if ln.startswith("+ "):
                        added.append(ln[2:])
                    elif ln.startswith("- "):
                        removed.append(ln[2:])
                    if len(added) + len(removed) >= _MAX_DIFF_LINES:
                        break
            pairs.append({
                "page": i + 1, "similarity": round(ratio, 4),
                "missing_in": None, "added": added, "removed": removed,
            })
            ratios.append(ratio)
        overall = round(sum(ratios) / len(ratios), 4) if ratios else 1.0
        return {
            "summary": {
                "page_count_a": count_a,
                "page_count_b": count_b,
                "overall_similarity": overall,
                "identical": count_a == count_b and all(r == 1.0 for r in ratios),
            },
            "page_pairs": pairs,
        }


def page_counts(
    path_a: Path, path_b: Path,
    password_a: str | None = None, password_b: str | None = None,
) -> tuple[int, int]:
    with open_pdf(path_a, password_a) as da, open_pdf(path_b, password_b) as db:
        return da.page_count, db.page_count


def compare_visual(
    path_a: Path, path_b: Path,
    password_a: str | None = None, password_b: str | None = None,
    dpi: int = 120, max_diff_pages: int = MAX_DIFF_PAGES,
) -> list[tuple[str, bytes]]:
    """Farklı pikselleri kırmızı vurgulanmış sayfa PNG'leri üretir.

    Yalnız görsel farkı olan sayfalar için çıktı verir; sayfa sayıları
    farklıysa ortak aralık karşılaştırılır. ``max_diff_pages`` fark PNG'sine
    ulaşılınca tarama durur (bellek sınırı).
    """
    import numpy as np
    from PIL import Image

    base_zoom = dpi / 72
    outputs: list[tuple[str, bytes]] = []

    def page_rgb(doc: fitz.Document, index: int, zoom: float) -> "np.ndarray":
        pix = doc[index].get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
        arr = np.frombuffer(pix.samples, dtype=np.uint8)
        return arr.reshape(pix.height, pix.width, pix.n)[:, :, :3]

    def pair_zoom(da: fitz.Document, db: fitz.Document, index: int) -> float:
        # İki sayfa aynı ölçekle render edilmeli (fark hizası); ölçek, büyük
        # olan sayfanın piksel bütçesini aşmayacak şekilde düşürülür.
        ra, rb = da[index].rect, db[index].rect
        w = max(ra.width, rb.width) * base_zoom
        h = max(ra.height, rb.height) * base_zoom
        if w * h <= _MAX_PIXELS_PER_PAGE:
            return base_zoom
        return base_zoom * (_MAX_PIXELS_PER_PAGE / (w * h)) ** 0.5

    def pad_to(arr: "np.ndarray", h: int, w: int) -> "np.ndarray":
        if arr.shape[0] == h and arr.shape[1] == w:
            return arr
        canvas = np.full((h, w, 3), 255, dtype=np.uint8)
        canvas[: arr.shape[0], : arr.shape[1]] = arr
        return canvas

    with open_pdf(path_a, password_a) as da, open_pdf(path_b, password_b) as db:
        for i in range(min(da.page_count, db.page_count)):
            if len(outputs) >= max_diff_pages:
                break
            zoom = pair_zoom(da, db, i)
            img_a = page_rgb(da, i, zoom)
            img_b = page_rgb(db, i, zoom)
            h = max(img_a.shape[0], img_b.shape[0])
            w = max(img_a.shape[1], img_b.shape[1])
            img_a, img_b = pad_to(img_a, h, w), pad_to(img_b, h, w)
            diff = np.any(np.abs(img_a.astype(np.int16) - img_b.astype(np.int16)) > 30, axis=2)
            if not diff.any():
                continue
            # B sayfası üzerine, farklı pikselleri kırmızıyla harmanla
            blended = img_b.copy()
            blended[diff] = (img_b[diff] * 0.35 + np.array([255, 0, 0]) * 0.65).astype(np.uint8)
            buf = io.BytesIO()
            Image.fromarray(blended).save(buf, format="PNG")
            outputs.append((f"fark_sayfa_{i + 1}.png", buf.getvalue()))
    return outputs
