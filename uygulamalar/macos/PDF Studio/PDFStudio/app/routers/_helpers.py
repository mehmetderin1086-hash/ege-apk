"""Router'lar arası paylaşılan yardımcılar."""
from __future__ import annotations

import io
import zipfile
from pathlib import Path

from fastapi import HTTPException

from ..models import OutputInfo, ProcessResponse
from ..services.common import PdfError
from ..session import Session, StoredFile, manager


def get_session(session_id: str) -> Session:
    sess = manager.get(session_id)
    if sess is None:
        raise HTTPException(status_code=404, detail="Oturum bulunamadı. Lütfen dosyaları yeniden yükleyin.")
    sess.touch()
    return sess


def require_file(sess: Session, file_id: str) -> Path:
    path = sess.path_for(file_id)
    if path is None:
        raise HTTPException(status_code=404, detail="Dosya bulunamadı.")
    return path


def output_info(session_id: str, sf: StoredFile) -> OutputInfo:
    kind_map = {".pdf": "pdf", ".docx": "office", ".xlsx": "office", ".txt": "text",
                ".zip": "zip", ".png": "image", ".jpg": "image", ".jpeg": "image"}
    ext = Path(sf.name).suffix.lower()
    return OutputInfo(
        file_id=sf.file_id,
        name=sf.name,
        size=sf.size,
        kind=kind_map.get(ext, sf.kind),
        download_url=f"/api/download/{session_id}/{sf.file_id}",
    )


def single_pdf_response(sess: Session, name: str, data: bytes, message: str,
                        meta: dict | None = None) -> ProcessResponse:
    sf = sess.register_output(name, data)
    return ProcessResponse(
        session_id=sess.id,
        message=message,
        outputs=[output_info(sess.id, sf)],
        meta=meta,
    )


def multi_response(sess: Session, items: list[tuple[str, bytes]], message: str,
                   zip_name: str = "sonuc.zip", make_zip: bool = True,
                   meta: dict | None = None) -> ProcessResponse:
    """Birden çok çıktı kaydeder; 1'den fazlaysa bir de zip üretir."""
    outputs: list[OutputInfo] = []
    stored: list[StoredFile] = []
    for name, data in items:
        sf = sess.register_output(name, data)
        stored.append(sf)
        outputs.append(output_info(sess.id, sf))
    if make_zip and len(items) > 1:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            for name, data in items:
                zf.writestr(name, data)
        zsf = sess.register_output(zip_name, buf.getvalue())
        outputs.insert(0, output_info(sess.id, zsf))
    return ProcessResponse(session_id=sess.id, message=message, outputs=outputs, meta=meta)


def pdf_error_to_http(exc: PdfError) -> HTTPException:
    return HTTPException(status_code=400, detail=str(exc))
