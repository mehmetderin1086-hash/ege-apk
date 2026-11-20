"""Dönüştürme uç noktaları."""
from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import convert
from ..services.common import PdfError
from ._helpers import (get_session, multi_response, output_info, require_file,
                       single_pdf_response)
from ..models import ProcessResponse

router = APIRouter(prefix="/api/convert", tags=["convert"])


# ---- PDF'E DÖNÜŞTÜR ----

class ImagesToPdfReq(BaseModel):
    session: str
    file_ids: list[str]
    page_size: str = "auto"  # auto | a4 | letter
    margin: int = 0
    output_name: str = "gorseller.pdf"


class TextReq(BaseModel):
    session: str
    text: str
    output_name: str = "metin.pdf"


class HtmlReq(BaseModel):
    session: str
    html: str
    output_name: str = "html.pdf"


class WordToPdfReq(BaseModel):
    session: str
    file_id: str


@router.post("/images-to-pdf")
async def images_to_pdf(req: ImagesToPdfReq):
    sess = get_session(req.session)
    paths = [require_file(sess, fid) for fid in req.file_ids]
    try:
        data = convert.images_to_pdf(paths, req.page_size, req.margin)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, req.output_name, data,
                               f"{len(paths)} görsel PDF'e dönüştürüldü.")


@router.post("/text-to-pdf")
async def text_to_pdf(req: TextReq):
    sess = get_session(req.session)
    try:
        data = convert.text_to_pdf(req.text)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, req.output_name, data, "Metin PDF'e dönüştürüldü.")


@router.post("/html-to-pdf")
async def html_to_pdf(req: HtmlReq):
    sess = get_session(req.session)
    try:
        data = convert.html_to_pdf(req.html)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, req.output_name, data, "HTML PDF'e dönüştürüldü.")


@router.post("/word-to-pdf")
async def word_to_pdf(req: WordToPdfReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data, meta = convert.word_to_pdf(path)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    name = Path(path.name).stem + ".pdf"
    engine = meta.get("engine")
    msg = "Word PDF'e dönüştürüldü." if engine == "libreoffice" else \
        "Word PDF'e dönüştürüldü (temel dönüşüm; karmaşık biçimler basitleştirildi)."
    return single_pdf_response(sess, name, data, msg, meta)


# ---- PDF'TEN DÖNÜŞTÜR ----

class PdfToImagesReq(BaseModel):
    session: str
    file_id: str
    fmt: str = "png"  # png | jpg
    dpi: int = 150
    password: str | None = None


class PdfConvReq(BaseModel):
    session: str
    file_id: str
    password: str | None = None


@router.post("/pdf-to-images")
async def pdf_to_images(req: PdfToImagesReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        items = convert.pdf_to_images(path, req.fmt, req.dpi, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return multi_response(sess, items, f"{len(items)} sayfa görsele dönüştürüldü.",
                          zip_name="gorseller.zip")


@router.post("/pdf-to-text")
async def pdf_to_text(req: PdfConvReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = convert.pdf_to_text(path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    name = Path(path.name).stem + ".txt"
    sf = sess.register_output(name, data)
    return ProcessResponse(session_id=sess.id, message="Metin çıkarıldı.",
                           outputs=[output_info(sess.id, sf)])


@router.post("/pdf-to-word")
async def pdf_to_word(req: PdfConvReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    name = Path(path.name).stem + ".docx"
    file_id, out_path = sess.new_output_path(name)
    try:
        meta = convert.pdf_to_word(path, out_path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    sf = sess.stored_file(file_id)
    return ProcessResponse(session_id=sess.id, message="PDF Word'e dönüştürüldü.",
                           outputs=[output_info(sess.id, sf)], meta=meta)


@router.post("/pdf-to-excel")
async def pdf_to_excel(req: PdfConvReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    name = Path(path.name).stem + ".xlsx"
    file_id, out_path = sess.new_output_path(name)
    try:
        meta = convert.pdf_to_excel(path, out_path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    sf = sess.stored_file(file_id)
    n = meta.get("tables", 0)
    msg = f"{n} tablo Excel'e aktarıldı." if n else "Tablo bulunamadı; boş çalışma kitabı oluşturuldu."
    return ProcessResponse(session_id=sess.id, message=msg,
                           outputs=[output_info(sess.id, sf)], meta=meta)
