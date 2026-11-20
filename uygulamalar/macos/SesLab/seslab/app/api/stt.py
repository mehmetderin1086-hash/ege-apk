"""STT (deşifre) uçları — kelime zaman damgalı Türkçe çözümleme + exportlar."""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import Response

from app.api.common import read_limited
from app.audio.io import decode_audio
from app.config import STT_SR
from app.core.subtitles import EXPORTERS, MEDIA_TYPES
from app.engines.manager import manager
from app.jobs import queue

router = APIRouter(prefix="/api/stt", tags=["stt"])


def _transcribe_sync(data: bytes, language: str | None, word_timestamps: bool) -> dict:
    audio, _sr = decode_audio(data, target_sr=STT_SR)
    engine = manager.ensure("stt")
    result = engine.transcribe(
        audio, language=language, word_timestamps=word_timestamps
    )
    manager.watchdog()
    return result


@router.post("")
async def transcribe(
    file: UploadFile = Form(...),
    # None varsayılan ÖNEMLİ: FastAPI form'da boş string'i "gönderilmemiş"
    # sayar; default "tr" olsaydı otomatik dil algılama asla seçilemezdi.
    language: str | None = Form(None),
    word_timestamps: bool = Form(True),
):
    data = await read_limited(file)

    async def runner(job):
        await queue.update(job, message="Ses çözümleniyor...", progress=0.1)
        result = await asyncio.to_thread(
            _transcribe_sync, data, language or None, word_timestamps
        )
        return {
            "text": (result.get("text") or "").strip(),
            "language": result.get("language"),
            "segments": [
                {
                    "start": s["start"],
                    "end": s["end"],
                    "text": s["text"].strip(),
                    "words": [
                        {
                            "word": w["word"],
                            "start": w["start"],
                            "end": w["end"],
                            "probability": round(w.get("probability", 0), 3),
                        }
                        for w in s.get("words", [])
                    ],
                }
                for s in result.get("segments", [])
            ],
        }

    job = queue.submit("stt", {"filename": file.filename}, runner)
    return {"job_id": job.id}


@router.get("/{job_id}")
async def get_result(job_id: str):
    job = queue.jobs.get(job_id)
    if job is None:
        raise HTTPException(404, "İş bulunamadı")
    return job.public()


@router.get("/{job_id}/export")
async def export(job_id: str, format: str = "txt"):
    job = queue.jobs.get(job_id)
    if job is None or job.status != "done" or not job.result:
        raise HTTPException(404, "Tamamlanmış deşifre bulunamadı")
    if format not in EXPORTERS:
        raise HTTPException(400, f"Bilinmeyen format: {format}")
    content = EXPORTERS[format](job.result)
    return Response(
        content=content,
        media_type=MEDIA_TYPES[format],
        headers={
            "Content-Disposition": f'attachment; filename="desifre.{format}"'
        },
    )
