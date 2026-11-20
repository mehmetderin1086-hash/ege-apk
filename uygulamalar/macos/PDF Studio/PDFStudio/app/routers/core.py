"""Çekirdek uç noktalar: yükleme, önizleme render, dosya bilgisi, indirme."""
from __future__ import annotations

import mimetypes
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import FileResponse, Response

from .. import config
from ..models import FileInfo, UploadResponse
from ..services import render
from ..services.common import PdfError
from ..session import manager
from ._helpers import get_session, require_file

router = APIRouter(prefix="/api", tags=["core"])


@router.post("/upload", response_model=UploadResponse)
async def upload(
    files: list[UploadFile] = File(...),
    session_id: str | None = Form(None),
):
    if not files:
        raise HTTPException(status_code=400, detail="Dosya seçilmedi.")
    if len(files) > config.MAX_FILES_PER_REQUEST:
        raise HTTPException(status_code=400, detail="Çok fazla dosya.")

    manager.cleanup_expired()
    sess = manager.get_or_create(session_id)

    infos: list[FileInfo] = []
    for uf in files:
        data = await uf.read()
        if len(data) > config.MAX_UPLOAD_BYTES:
            raise HTTPException(status_code=400, detail=f"'{uf.filename}' çok büyük (200 MB üstü).")
        sf = sess.save_upload(uf.filename or "dosya", data)
        pages = None
        if sf.kind == "pdf":
            try:
                pages = render.page_count(sf.path)
            except PdfError:
                pages = None
        infos.append(FileInfo(file_id=sf.file_id, name=sf.name, size=sf.size,
                              kind=sf.kind, pages=pages))
    return UploadResponse(session_id=sess.id, files=infos)


@router.get("/info/{file_id}")
async def info(file_id: str, session: str = Query(...)):
    sess = get_session(session)
    path = require_file(sess, file_id)
    try:
        return render.document_info(path)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/render/{file_id}")
async def render_page(file_id: str, session: str = Query(...), page: int = Query(0),
                      password: str | None = Query(None)):
    sess = get_session(session)
    path = require_file(sess, file_id)
    try:
        png = render.render_page_png(path, page, password=password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return Response(content=png, media_type="image/png",
                    headers={"Cache-Control": "no-store"})


@router.get("/thumb/{file_id}")
async def thumb(file_id: str, session: str = Query(...), page: int = Query(0),
                password: str | None = Query(None)):
    sess = get_session(session)
    path = require_file(sess, file_id)
    try:
        png = render.render_thumbnail_png(path, page, password=password)
    except PdfError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return Response(content=png, media_type="image/png",
                    headers={"Cache-Control": "no-store"})


@router.get("/download/{session}/{file_id}")
async def download(session: str, file_id: str):
    sess = get_session(session)
    path = require_file(sess, file_id)
    media, _ = mimetypes.guess_type(path.name)
    return FileResponse(path, media_type=media or "application/octet-stream",
                        filename=path.name)


@router.get("/session/files")
async def session_files(session: str = Query(...)):
    sess = get_session(session)
    files = [
        FileInfo(file_id=sf.file_id, name=sf.name, size=sf.size, kind=sf.kind)
        for sf in sess.list_files()
    ]
    return {
        "session_id": sess.id,
        "files": files,
        "total_size": sum(item.size for item in files),
    }


@router.delete("/session/files/{file_id}")
async def delete_session_file(file_id: str, session: str = Query(...)):
    sess = get_session(session)
    if not sess.delete_file(file_id):
        raise HTTPException(status_code=404, detail="Dosya bulunamadı.")
    return {"message": "Dosya silindi.", "file_id": file_id}


@router.delete("/session")
async def delete_session(session: str = Query(...)):
    if not manager.delete(session):
        raise HTTPException(status_code=404, detail="Oturum bulunamadı.")
    return {"message": "Tüm geçici dosyalar silindi."}
