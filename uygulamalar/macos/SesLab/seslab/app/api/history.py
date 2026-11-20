"""Üretim geçmişi uçları."""
from __future__ import annotations

import asyncio
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse, Response

from app.audio.io import encode_mp3, read_wav
from app.core import history

router = APIRouter(prefix="/api/history", tags=["history"])


@router.get("")
async def list_all(type: str | None = None, limit: int = 100):
    # Negatif limit SQLite'ta "sınırsız" demek → [1, 500] aralığına sıkıştır
    return {"items": history.list_(type, max(1, min(limit, 500)))}


@router.get("/{rec_id}/audio")
async def audio(rec_id: str, format: str = "wav"):
    rec = history.get(rec_id)
    if rec is None or not Path(rec["path"]).exists():
        raise HTTPException(404, "Kayıt bulunamadı")
    if format == "mp3":
        data, sr = read_wav(rec["path"])
        mp3 = await asyncio.to_thread(encode_mp3, data, sr)
        return Response(
            content=mp3,
            media_type="audio/mpeg",
            headers={
                "Content-Disposition": f'attachment; filename="{rec_id}.mp3"'
            },
        )
    return FileResponse(rec["path"], media_type="audio/wav")


@router.delete("/{rec_id}")
async def delete(rec_id: str):
    try:
        history.delete(rec_id)
    except KeyError:
        raise HTTPException(404, "Kayıt bulunamadı") from None
    return {"ok": True}
