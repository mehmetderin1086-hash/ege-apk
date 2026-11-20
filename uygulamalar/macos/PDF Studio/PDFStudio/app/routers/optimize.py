"""Optimizasyon uç noktaları."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import optimize
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, require_file, single_pdf_response

router = APIRouter(prefix="/api/optimize", tags=["optimize"])


class CompressReq(BaseModel):
    session: str
    file_id: str
    level: str = "orta"  # dusuk | orta | yuksek
    password: str | None = None


class SimpleReq(BaseModel):
    session: str
    file_id: str
    password: str | None = None


class OcrReq(BaseModel):
    session: str
    file_id: str
    languages: str = "tr,en"
    password: str | None = None


@router.post("/compress")
async def compress(req: CompressReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data, meta = optimize.compress(path, req.level, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    pct = meta.get("reduction_percent", 0)
    msg = f"Boyut %{pct} azaltıldı." if pct > 0 else "Belge optimize edildi (ek küçülme sağlanamadı)."
    return single_pdf_response(sess, with_suffix_name(path.name, "_sikistirilmis"), data, msg, meta)


@router.post("/repair")
async def repair(req: SimpleReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = optimize.repair(path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_onarilmis"), data,
                               "PDF onarıldı ve yeniden yazıldı.")


@router.post("/ocr")
async def ocr(req: OcrReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data, meta = optimize.ocr(path, req.languages, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_ocr"), data,
                               f"OCR tamamlandı, {meta.get('regions', 0)} metin bölgesi eklendi.", meta)
