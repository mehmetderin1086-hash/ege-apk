"""Karşılaştırma uç noktaları: metin raporu ve görsel fark PNG'leri."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import compare
from ..services.common import PdfError
from ._helpers import get_session, multi_response, require_file

router = APIRouter(prefix="/api/compare", tags=["compare"])


class CompareReq(BaseModel):
    session: str
    file_id_a: str
    file_id_b: str
    password_a: str | None = None
    password_b: str | None = None


# Bilinçli olarak senkron def: FastAPI bunları thread pool'da çalıştırır,
# uzun karşılaştırma event loop'u (ve /health'i) bloke etmez.
@router.post("/text")
def compare_text(req: CompareReq):
    sess = get_session(req.session)
    path_a = require_file(sess, req.file_id_a)
    path_b = require_file(sess, req.file_id_b)
    try:
        return compare.compare_text(path_a, path_b, req.password_a, req.password_b)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/visual")
def compare_visual(req: CompareReq):
    sess = get_session(req.session)
    path_a = require_file(sess, req.file_id_a)
    path_b = require_file(sess, req.file_id_b)
    try:
        count_a, count_b = compare.page_counts(path_a, path_b, req.password_a, req.password_b)
        items = compare.compare_visual(path_a, path_b, req.password_a, req.password_b)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    if items:
        msg = f"{len(items)} sayfada görsel fark bulundu."
        if len(items) >= compare.MAX_DIFF_PAGES:
            msg += f" (İlk {compare.MAX_DIFF_PAGES} fark gösteriliyor; sonrası taranmadı.)"
    else:
        msg = "Ortak sayfalarda görsel fark bulunamadı."
    if count_a != count_b:
        msg += f" Sayfa sayıları farklı (A: {count_a}, B: {count_b}); yalnız ortak {min(count_a, count_b)} sayfa karşılaştırıldı."
    return multi_response(sess, items, msg, zip_name="gorsel_farklar.zip")
