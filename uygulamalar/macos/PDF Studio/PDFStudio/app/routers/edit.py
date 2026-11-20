"""Düzenleme uç noktaları: filigran, sayfa no, üst/alt bilgi, redaksiyon, anotasyon."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import edit
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, require_file, single_pdf_response

router = APIRouter(prefix="/api/edit", tags=["edit"])


class WatermarkTextReq(BaseModel):
    session: str
    file_id: str
    text: str
    opacity: float = 0.25
    rotation: int = 45
    fontsize: int = 48
    color: str = "#888888"
    pages: str | None = None
    tiled: bool = False
    password: str | None = None


class WatermarkImageReq(BaseModel):
    session: str
    file_id: str
    image_file_id: str
    opacity: float = 0.3
    scale: float = 0.5
    pages: str | None = None
    password: str | None = None


class PageNumbersReq(BaseModel):
    session: str
    file_id: str
    position: str = "alt-orta"
    start_at: int = 1
    fmt: str = "{n}"
    fontsize: int = 11
    color: str = "#333333"
    pages: str | None = None
    password: str | None = None


class HeaderFooterReq(BaseModel):
    session: str
    file_id: str
    header: str = ""
    footer: str = ""
    fontsize: int = 10
    color: str = "#555555"
    password: str | None = None


class RedactReq(BaseModel):
    session: str
    file_id: str
    boxes: list[dict]
    password: str | None = None


class AnnotateReq(BaseModel):
    session: str
    file_id: str
    annotations: list[dict]
    image_refs: dict[str, str] | None = None  # ref -> uploaded file_id
    password: str | None = None


@router.post("/watermark-text")
async def watermark_text(req: WatermarkTextReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = edit.watermark_text(
            path, req.text, opacity=req.opacity, rotation=req.rotation,
            fontsize=req.fontsize, color=req.color, spec=req.pages,
            tiled=req.tiled, password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_filigran"), data,
                               "Metin filigranı eklendi.")


@router.post("/watermark-image")
async def watermark_image(req: WatermarkImageReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    img_path = require_file(sess, req.image_file_id)
    try:
        data = edit.watermark_image(
            path, img_path.read_bytes(), opacity=req.opacity, scale=req.scale,
            spec=req.pages, password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_filigran"), data,
                               "Görsel filigranı eklendi.")


@router.post("/page-numbers")
async def page_numbers(req: PageNumbersReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = edit.page_numbers(
            path, position=req.position, start_at=req.start_at, fmt=req.fmt,
            fontsize=req.fontsize, color=req.color, spec=req.pages,
            password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_numarali"), data,
                               "Sayfa numaraları eklendi.")


@router.post("/header-footer")
async def header_footer(req: HeaderFooterReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    if not req.header and not req.footer:
        raise HTTPException(status_code=400, detail="Üst veya alt bilgi girin.")
    try:
        data = edit.header_footer(
            path, header=req.header, footer=req.footer, fontsize=req.fontsize,
            color=req.color, password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_bilgi"), data,
                               "Üst/alt bilgi eklendi.")


@router.post("/redact")
async def redact(req: RedactReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    if not req.boxes:
        raise HTTPException(status_code=400, detail="Karartılacak alan seçilmedi.")
    try:
        data = edit.redact(path, req.boxes, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_redaksiyon"), data,
                               "Seçili alanlar kalıcı olarak karartıldı.")


@router.post("/annotate")
async def annotate(req: AnnotateReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    images: dict[str, bytes] = {}
    if req.image_refs:
        for ref, fid in req.image_refs.items():
            p = sess.path_for(fid)
            if p:
                images[ref] = p.read_bytes()
    try:
        data = edit.apply_annotations(path, req.annotations, images, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_duzenlenmis"), data,
                               "Düzenlemeler PDF'e uygulandı.")
