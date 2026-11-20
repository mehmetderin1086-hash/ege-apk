"""Optimizasyon işlemleri: sıkıştırma, onarma, OCR."""
from __future__ import annotations

import io
from pathlib import Path

import fitz

from .common import PdfError, open_pdf as _open


# Sıkıştırma seviyeleri: (görsel hedef DPI, JPEG kalitesi)
_COMPRESS_LEVELS = {
    "dusuk": (150, 80),
    "orta": (110, 65),
    "yuksek": (72, 45),
}


def compress(path: Path, level: str = "orta", password: str | None = None) -> tuple[bytes, dict]:
    """Görselleri yeniden örnekleyip JPEG'e çevirerek PDF boyutunu düşürür."""
    from PIL import Image

    if level not in _COMPRESS_LEVELS:
        level = "orta"
    target_dpi, quality = _COMPRESS_LEVELS[level]
    original_size = path.stat().st_size

    with _open(path, password) as doc:
        seen_xrefs: set[int] = set()
        for page in doc:
            for img in page.get_images(full=True):
                xref = img[0]
                if xref in seen_xrefs:
                    continue
                seen_xrefs.add(xref)
                try:
                    base = doc.extract_image(xref)
                except Exception:  # noqa: BLE001
                    continue
                img_bytes = base.get("image")
                if not img_bytes:
                    continue
                try:
                    pil = Image.open(io.BytesIO(img_bytes))
                except Exception:  # noqa: BLE001
                    continue
                # Büyük görselleri hedef boyuta indir
                max_dim = max(pil.size)
                # kabaca: 72 dpi'de bir sayfa ~ genişlik; downscale oranı
                scale = min(1.0, (target_dpi * 8.5) / max_dim) if max_dim else 1.0
                if scale < 1.0:
                    new_size = (max(1, int(pil.size[0] * scale)), max(1, int(pil.size[1] * scale)))
                    pil = pil.resize(new_size, Image.LANCZOS)
                if pil.mode in ("RGBA", "P", "LA"):
                    pil = pil.convert("RGB")
                buf = io.BytesIO()
                pil.save(buf, format="JPEG", quality=quality, optimize=True)
                new_bytes = buf.getvalue()
                if len(new_bytes) < len(img_bytes):
                    try:
                        doc.update_stream(xref, new_bytes)
                        # Görselin filtresini DCT (JPEG) olarak işaretle
                        doc.xref_set_key(xref, "Filter", "/DCTDecode")
                        doc.xref_set_key(xref, "ColorSpace", "/DeviceRGB")
                        doc.xref_set_key(xref, "BitsPerComponent", "8")
                        doc.xref_set_key(xref, "Width", str(pil.size[0]))
                        doc.xref_set_key(xref, "Height", str(pil.size[1]))
                    except Exception:  # noqa: BLE001
                        pass
        data = doc.tobytes(garbage=4, deflate=True, deflate_images=True, deflate_fonts=True, clean=True)

    new_size = len(data)
    if new_size >= original_size:
        # Sıkıştırma fayda etmediyse en azından temizlenmiş halini ver
        ratio = 0.0
    else:
        ratio = round((1 - new_size / original_size) * 100, 1)
    meta = {
        "original_size": original_size,
        "new_size": new_size,
        "reduction_percent": ratio,
        "level": level,
    }
    return data, meta


def repair(path: Path, password: str | None = None) -> bytes:
    """Bozuk PDF'i yeniden yazarak onarmaya çalışır."""
    try:
        with _open(path, password) as doc:
            return doc.tobytes(garbage=4, deflate=True, clean=True)
    except PdfError:
        raise
    except Exception as exc:  # noqa: BLE001
        raise PdfError(f"PDF onarılamadı: {exc}") from exc


def ocr(path: Path, languages: str = "tr,en", password: str | None = None) -> tuple[bytes, dict]:
    """Sayfa görsellerini OCR'dan geçirip görünmez metin katmanı ekler.

    rapidocr-onnxruntime kullanır (sistem tesseract gerektirmez).
    """
    try:
        from rapidocr_onnxruntime import RapidOCR
    except Exception as exc:  # noqa: BLE001
        raise PdfError(
            "OCR modülü yüklenemedi. Bağımlılıkların kurulu olduğundan emin olun."
        ) from exc

    import numpy as np
    from PIL import Image

    engine = RapidOCR()
    words_added = 0

    with _open(path, password) as doc:
        for page in doc:
            zoom = 2.0  # ~144 dpi
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
            img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
            arr = np.array(img)
            result, _ = engine(arr)
            if not result:
                continue
            for box, text, score in result:
                if not text or score is not None and score < 0.3:
                    continue
                # box: 4 nokta (piksel). Sol-üst ve sağ-alt ile dikdörtgen kur.
                xs = [pt[0] for pt in box]
                ys = [pt[1] for pt in box]
                x0, y0, x1, y1 = min(xs) / zoom, min(ys) / zoom, max(xs) / zoom, max(ys) / zoom
                rect = fitz.Rect(x0, y0, x1, y1)
                if rect.height <= 1:
                    continue
                # Kutuya sığacak yazı boyutu (görünmez katman)
                fontsize = max(4.0, rect.height * 0.8)
                try:
                    page.insert_textbox(
                        rect,
                        text,
                        fontsize=fontsize,
                        fontname="helv",
                        color=(0, 0, 0),
                        render_mode=3,  # görünmez
                        align=0,
                    )
                    words_added += 1
                except Exception:  # noqa: BLE001
                    continue
        data = doc.tobytes(garbage=4, deflate=True)
    return data, {"regions": words_added}
