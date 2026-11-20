"""Ses kütüphanesi uçları — klonlama, listeleme, önizleme."""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel

from app.api.common import read_limited
from app.core import voices
from app.core.synth import default_engine, synth_text

router = APIRouter(prefix="/api/voices", tags=["voices"])

PREVIEW_SENTENCE = (
    "Merhaba! Bu, klonlanan sesimin daha canlı ve anlaşılır bir önizlemesi. "
    "SesLab ile metinleri doğal bir tempoda seslendirebilirim."
)
PREVIEW_SPEED = 1.0
PREVIEW_VERSION = 2


def _preview_path(voice_id: str):
    """Ayar değişince eski, bayat önizleme otomatik olarak kullanılmasın."""
    return voices.preview_path(voice_id).with_name(
        f"preview_v{PREVIEW_VERSION}.wav"
    )


class RenameRequest(BaseModel):
    name: str


@router.get("")
async def list_all():
    return {"voices": voices.list_voices()}


@router.post("")
async def create(name: str = Form(...), file: UploadFile = Form(...)):
    data = await read_limited(file)
    try:
        meta = await asyncio.to_thread(voices.create_voice, name, data)
    except ValueError as e:
        raise HTTPException(400, str(e)) from None
    return meta


@router.patch("/{voice_id}")
async def rename(voice_id: str, req: RenameRequest):
    try:
        return voices.rename_voice(voice_id, req.name)
    except KeyError:
        raise HTTPException(404, "Ses bulunamadı") from None


@router.delete("/{voice_id}")
async def delete(voice_id: str):
    try:
        voices.delete_voice(voice_id)
    except KeyError:
        raise HTTPException(404, "Ses bulunamadı") from None
    return {"ok": True}


@router.get("/{voice_id}/audio")
async def ref_audio(voice_id: str):
    p = voices.ref_path(voice_id)
    if not p.exists():
        raise HTTPException(404, "Ses bulunamadı")
    return FileResponse(p, media_type="audio/wav")


@router.post("/{voice_id}/preview")
async def make_preview(voice_id: str):
    """Sabit cümleyle önizleme üretir (önbelleğe alınır)."""
    if voices.get_voice(voice_id) is None:
        raise HTTPException(404, "Ses bulunamadı")
    pp = _preview_path(voice_id)
    if not pp.exists():
        from app.audio.io import write_wav
        from app.jobs import queue

        async def runner(job):
            audio, sr, _ = await synth_text(
                PREVIEW_SENTENCE, voice_id=voice_id,
                engine=default_engine(), job=job, verify=False,
                speed=PREVIEW_SPEED,
            )
            write_wav(pp, audio, sr)
            return {"ok": True}

        job = await queue.submit_and_wait("preview", {"voice_id": voice_id}, runner)
        if job.status == "error":
            raise HTTPException(500, job.message or "Önizleme üretilemedi")
    return {
        "url": (
            f"/api/voices/{voice_id}/preview_audio?v={PREVIEW_VERSION}"
        )
    }


@router.get("/{voice_id}/preview_audio")
async def preview_audio(voice_id: str):
    pp = _preview_path(voice_id)
    if not pp.exists():
        raise HTTPException(404, "Önizleme henüz üretilmedi")
    return FileResponse(pp, media_type="audio/wav")
