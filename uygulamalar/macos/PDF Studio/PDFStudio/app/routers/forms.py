"""Form uç noktaları: alan listeleme, doldurma, veri çıkarma."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from ..services import forms
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, require_file, single_pdf_response

router = APIRouter(prefix="/api/forms", tags=["forms"])


class FillReq(BaseModel):
    session: str
    file_id: str
    values: dict[str, str]
    flatten: bool = False
    password: str | None = None


@router.get("/fields/{file_id}")
async def fields(file_id: str, session: str = Query(...), password: str | None = Query(None)):
    sess = get_session(session)
    path = require_file(sess, file_id)
    try:
        return {"fields": forms.list_fields(path, password)}
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/extract/{file_id}")
async def extract(file_id: str, session: str = Query(...), password: str | None = Query(None)):
    sess = get_session(session)
    path = require_file(sess, file_id)
    try:
        return {"data": forms.extract_data(path, password)}
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/fill")
async def fill(req: FillReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = forms.fill(path, req.values, flatten=req.flatten, password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_dolduruldu"), data,
                               "Form dolduruldu.")
