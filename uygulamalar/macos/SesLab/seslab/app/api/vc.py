"""Ses değiştirici (speech-to-speech) uçları — ChatterboxVC."""
from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

from fastapi import APIRouter, Form, HTTPException, UploadFile

from app.api.common import read_limited
from app.audio.io import decode_audio, write_wav
from app.config import TTS_SR
from app.core import history
from app.core.synth import resolve_ref_wav
from app.engines.manager import manager
from app.jobs import queue

router = APIRouter(prefix="/api", tags=["vc"])


def _convert_sync(data: bytes, target_ref: str) -> tuple:
    audio, sr = decode_audio(data, target_sr=TTS_SR)
    # ChatterboxVC dosya yolu ister → geçici wav yaz
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp_path = Path(tmp.name)
    try:
        write_wav(tmp_path, audio, sr)
        engine = manager.ensure("vc")
        out = engine.convert(str(tmp_path), target_ref)
        manager.watchdog()
        return out, engine.sr
    finally:
        tmp_path.unlink(missing_ok=True)


@router.post("/vc")
async def voice_change(file: UploadFile = Form(...), voice_id: str = Form(...)):
    data = await read_limited(file)
    try:
        target_ref = resolve_ref_wav(voice_id)
    except KeyError as e:
        raise HTTPException(404, str(e)) from None
    if target_ref is None:
        raise HTTPException(400, "Ses değiştirici için kütüphaneden bir ses seçin")

    async def runner(job):
        await queue.update(job, message="Ses dönüştürülüyor...", progress=0.2)
        audio, sr = await asyncio.to_thread(_convert_sync, data, target_ref)
        record = history.add(
            "vc", audio, sr,
            text=f"Kaynak: {file.filename or 'kayıt'}",
            params={},
            voice_id=voice_id,
        )
        return {
            "history_id": record["id"],
            "url": f"/api/history/{record['id']}/audio",
            "duration_s": record["duration_s"],
        }

    job = await queue.submit_and_wait("vc", {"filename": file.filename}, runner)
    if job.status == "error":
        raise HTTPException(500, job.message or "Dönüştürme başarısız")
    return job.result
