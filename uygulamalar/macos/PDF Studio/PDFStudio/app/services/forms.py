"""Form işlemleri: alanları listeleme, doldurma, veri çıkarma, düzleştirme."""
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


_FIELD_TYPE_NAMES = {
    fitz.PDF_WIDGET_TYPE_TEXT: "metin",
    fitz.PDF_WIDGET_TYPE_CHECKBOX: "onay-kutusu",
    fitz.PDF_WIDGET_TYPE_RADIOBUTTON: "radyo",
    fitz.PDF_WIDGET_TYPE_COMBOBOX: "acilir-liste",
    fitz.PDF_WIDGET_TYPE_LISTBOX: "liste",
    fitz.PDF_WIDGET_TYPE_SIGNATURE: "imza",
    fitz.PDF_WIDGET_TYPE_BUTTON: "buton",
}


def list_fields(path: Path, password: str | None = None) -> list[dict]:
    """Formdaki tüm alanları döndürür."""
    fields: list[dict] = []
    with _open(path, password) as doc:
        for pno, page in enumerate(doc):
            for w in page.widgets() or []:
                fields.append({
                    "page": pno,
                    "name": w.field_name,
                    "type": _FIELD_TYPE_NAMES.get(w.field_type, "diger"),
                    "value": w.field_value,
                    "options": list(w.choice_values) if w.choice_values else None,
                    "rect": [round(w.rect.x0, 1), round(w.rect.y0, 1),
                             round(w.rect.x1, 1), round(w.rect.y1, 1)],
                })
    return fields


def extract_data(path: Path, password: str | None = None) -> dict[str, str]:
    """Alan adı -> değer sözlüğü döndürür."""
    data: dict[str, str] = {}
    with _open(path, password) as doc:
        for page in doc:
            for w in page.widgets() or []:
                if w.field_name:
                    data[w.field_name] = w.field_value or ""
    return data


def fill(path: Path, values: dict[str, str], *, flatten: bool = False,
         password: str | None = None) -> bytes:
    """Form alanlarını verilen değerlerle doldurur."""
    if not values:
        raise PdfError("Doldurulacak değer bulunamadı.")
    filled = 0
    with _open(path, password) as doc:
        has_form = False
        for page in doc:
            widgets = page.widgets()
            if not widgets:
                continue
            for w in widgets:
                has_form = True
                if w.field_name in values:
                    val = values[w.field_name]
                    try:
                        if w.field_type == fitz.PDF_WIDGET_TYPE_CHECKBOX:
                            truthy = str(val).lower() in ("1", "true", "on", "yes", "evet", "x", "✓")
                            w.field_value = bool(truthy)
                        else:
                            w.field_value = str(val)
                        w.update()
                        filled += 1
                    except Exception:  # noqa: BLE001
                        continue
        if not has_form:
            raise PdfError("Bu PDF'te doldurulabilir form alanı bulunamadı.")
        if flatten:
            # Alanları içeriğe göm (değiştirilemez hale getir)
            for page in doc:
                page.wrap_contents()
            pdf_bytes = doc.convert_to_pdf()
            with fitz.open("pdf", pdf_bytes) as flat:
                return flat.tobytes(garbage=4, deflate=True)
        return doc.tobytes(garbage=4, deflate=True)
