"""Güvenlik uç noktaları: şifrele, şifre kaldır, imza, düzleştir, meta veri."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from ..services import metadata as md_service
from ..services import security
from ..services.common import PdfError, with_suffix_name
from ._helpers import get_session, require_file, single_pdf_response

router = APIRouter(prefix="/api/security", tags=["security"])


class ProtectReq(BaseModel):
    session: str
    file_id: str
    password: str
    allow_print: bool = True
    allow_copy: bool = True
    allow_modify: bool = False
    current_password: str | None = None


class UnlockReq(BaseModel):
    session: str
    file_id: str
    password: str


class SignReq(BaseModel):
    session: str
    file_id: str
    image_file_id: str
    page: int
    x: float
    y: float
    w: float
    h: float
    password: str | None = None


class SimpleReq(BaseModel):
    session: str
    file_id: str
    password: str | None = None


class MetadataReq(BaseModel):
    session: str
    file_id: str
    fields: dict
    password: str | None = None


@router.post("/protect")
async def protect(req: ProtectReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = security.protect(
            path, req.password, allow_print=req.allow_print,
            allow_copy=req.allow_copy, allow_modify=req.allow_modify,
            current_password=req.current_password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_korumali"), data,
                               "Belge parola ile şifrelendi.")


@router.post("/unlock")
async def unlock(req: UnlockReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = security.unlock(path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_sifresiz"), data,
                               "Parola koruması kaldırıldı.")


@router.post("/sign")
async def sign(req: SignReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    img_path = require_file(sess, req.image_file_id)
    try:
        data = security.place_signature(
            path, img_path.read_bytes(), page=req.page, x=req.x, y=req.y,
            w=req.w, h=req.h, password=req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_imzali"), data,
                               "İmza eklendi.")


@router.post("/flatten")
async def flatten(req: SimpleReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = security.flatten(path, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_duzlestirilmis"), data,
                               "Belge düzleştirildi.")


@router.post("/metadata")
async def set_metadata(req: MetadataReq):
    sess = get_session(req.session)
    path = require_file(sess, req.file_id)
    try:
        data = md_service.write(path, req.fields, req.password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return single_pdf_response(sess, with_suffix_name(path.name, "_metaveri"), data,
                               "Meta veriler güncellendi.")
