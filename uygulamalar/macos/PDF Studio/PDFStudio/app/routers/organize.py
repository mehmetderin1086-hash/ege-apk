"""Sayfa düzenleme uç noktaları."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import organize
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, multi_response, require_file, single_pdf_response

router = APIRouter(prefix="/api/organize", tags=["organize"])


class MergeReq(BaseModel):
    session: str
    file_ids: list[str]
    output_name: str = "birlestirilmis.pdf"


class SplitReq(BaseModel):
    session: str
    file_id: str
    mode: str = "ranges"  # "ranges" | "every"
    ranges: list[str] | None = None
    every: int | None = None
    password: str | None = None


class PagesReq(BaseModel):
    session: str
    file_id: str
    pages: str
    password: str | None = None


class ReorderReq(BaseModel):
    session: str
    file_id: str
    order: list[int]
    password: str | None = None


class ComposeReq(BaseModel):
    session: str
    file_id: str
    pages: list[dict]
    password: str | None = None


class RotateReq(BaseModel):
    session: str
    file_id: str
    degrees: int = 90
    pages: str | None = None
    password: str | None = None


class CropReq(BaseModel):
    session: str
    file_id: str
    margins: dict
    pages: str | None = None
    password: str | None = None


@router.post("/merge")
async def merge(req: MergeReq):
    sess = get_session(req.session)
    paths = [require_file(sess, fid) for fid in req.file_ids]
    try:
        data = organize.merge(paths)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, req.output_name, data,
                               f"{len(paths)} PDF birleştirildi.")


@router.post("/split")
async def split(req: SplitReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        if req.mode == "every":
            items = organize.split_every(path, req.every or 1, req.password)
        else:
            if not req.ranges:
                raise PdfError("En az bir sayfa aralığı girin.")
            items = organize.split_ranges(path, req.ranges, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return multi_response(sess, items, f"{len(items)} parçaya bölündü.",
                          zip_name="bolunmus.zip")


@router.post("/extract")
async def extract(req: PagesReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.extract_pages(path, req.pages, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_secili"), data,
                               "Seçili sayfalar çıkarıldı.")


@router.post("/delete")
async def delete(req: PagesReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.delete_pages(path, req.pages, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_duzenlenmis"), data,
                               "Seçili sayfalar silindi.")


@router.post("/reorder")
async def reorder(req: ReorderReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.reorder(path, req.order, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_siralanmis"), data,
                               "Sayfalar yeniden sıralandı.")


@router.post("/compose")
async def compose(req: ComposeReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.compose(path, req.pages, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_duzenlenmis"), data,
                               "Sayfalar düzenlendi.")


@router.post("/rotate")
async def rotate(req: RotateReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.rotate(path, req.pages, req.degrees, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_dondurulmus"), data,
                               "Sayfalar döndürüldü.")


@router.post("/crop")
async def crop(req: CropReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = organize.crop(path, req.margins, req.pages, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_kirpilmis"), data,
                               "Sayfalar kırpıldı.")
