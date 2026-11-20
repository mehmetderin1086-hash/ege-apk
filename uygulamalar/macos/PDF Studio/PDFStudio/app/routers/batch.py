"""Toplu işlem: birden çok dosyaya aynı işlemi tek istekte uygular."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from .. import config
from ..models import ProcessResponse
from ..services import edit, optimize, organize, security
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, multi_response

router = APIRouter(prefix="/api/batch", tags=["batch"])

_SUFFIX = {
    "compress": "_sikistirilmis",
    "watermark-text": "_filigranli",
    "page-numbers": "_numarali",
    "rotate": "_dondurulmus",
    "protect": "_sifreli",
}


class BatchReq(BaseModel):
    session: str
    file_ids: list[str] = Field(min_length=1, max_length=config.MAX_FILES_PER_REQUEST)
    operation: str
    params: dict[str, Any] = Field(default_factory=dict)


def _apply(operation: str, path: Path, params: dict[str, Any]) -> bytes:
    password = params.get("password") or None
    if operation == "compress":
        data, _ = optimize.compress(path, level=params.get("level", "orta"), password=password)
        return data
    if operation == "watermark-text":
        text = (params.get("text") or "").strip()
        if not text:
            raise PdfError("Filigran metni boş olamaz.")
        if len(text) > 500:
            raise PdfError("Filigran metni çok uzun (en fazla 500 karakter).")
        return edit.watermark_text(
            path, text,
            opacity=min(1.0, max(0.0, float(params.get("opacity", 0.25)))),
            rotation=int(params.get("rotation", 45)) % 360,
            fontsize=min(200, max(6, int(params.get("fontsize", 48)))),
            color=params.get("color", "#888888"),
            password=password,
        )
    if operation == "page-numbers":
        return edit.page_numbers(
            path,
            position=params.get("position", "alt-orta"),
            fmt=params.get("fmt", "{n}"),
            password=password,
        )
    if operation == "rotate":
        return organize.rotate(path, None, int(params.get("degrees", 90)), password=password)
    if operation == "protect":
        return security.protect(
            path, params.get("new_password") or "",
            allow_print=bool(params.get("allow_print", True)),
            allow_copy=bool(params.get("allow_copy", True)),
            allow_modify=bool(params.get("allow_modify", False)),
            current_password=password,
        )
    raise PdfError(f"Bilinmeyen toplu işlem: {operation}")


@router.post("/apply", response_model=ProcessResponse)
def apply_batch(req: BatchReq) -> ProcessResponse:
    if req.operation not in _SUFFIX:
        raise HTTPException(status_code=400, detail=f"Bilinmeyen toplu işlem: {req.operation}")
    sess = get_session(req.session)

    # Aynı file_id birden çok kez gönderilirse bir kez işlenir (sıra korunur)
    seen: set[str] = set()
    file_ids = [f for f in req.file_ids if not (f in seen or seen.add(f))]

    items: list[tuple[str, bytes]] = []
    failed: list[dict[str, str]] = []
    used_names: dict[str, int] = {}
    for fid in file_ids:
        path = sess.path_for(fid)
        if path is None:
            failed.append({"file_id": fid, "name": fid, "error": "Dosya bulunamadı."})
            continue
        try:
            data = _apply(req.operation, path, req.params)
            name = with_suffix_name(path.name, _SUFFIX[req.operation])
            # Aynı adlı girdiler zip içinde birbirini ezmesin: rapor.pdf + rapor.pdf
            # -> rapor_sikistirilmis.pdf, rapor_sikistirilmis_2.pdf
            if name in used_names:
                used_names[name] += 1
                p = Path(name)
                name = f"{p.stem}_{used_names[name]}{p.suffix}"
            else:
                used_names[name] = 1
            items.append((name, data))
        except PdfError as exc:
            failed.append({"file_id": fid, "name": path.name, "error": str(exc)})
        except Exception as exc:  # tek bozuk dosya toplu işi düşürmesin
            failed.append({"file_id": fid, "name": path.name, "error": f"{type(exc).__name__}: {exc}"})

    if not items:
        first = failed[0]["error"] if failed else "İşlenecek dosya yok."
        raise HTTPException(status_code=400, detail=f"Hiçbir dosya işlenemedi. İlk hata: {first}")

    msg = f"{len(items)} dosya işlendi"
    if failed:
        msg += f", {len(failed)} dosya atlandı"
    return multi_response(
        sess, items, msg + ".",
        zip_name="toplu_islem.zip",
        meta={"failed": failed} if failed else None,
    )
