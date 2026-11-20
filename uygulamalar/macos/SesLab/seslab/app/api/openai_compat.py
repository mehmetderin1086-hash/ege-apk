"""OpenAI uyumlu uçlar — mevcut SDK/araçlar SesLab'e bağlanabilsin diye.

POST /v1/audio/speech          (OpenAI TTS şekli)
POST /v1/audio/transcriptions  (OpenAI Whisper şekli)
"""
from __future__ import annotations

import asyncio
import io

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import Response
from pydantic import BaseModel, Field

from app.api.common import read_limited
from app.audio.io import decode_audio, encode_mp3
from app.config import DEFAULT_LANGUAGE, STT_SR
from app.core import voices
from app.core.subtitles import to_srt, to_vtt
from app.core.synth import default_engine, synth_text
from app.engines.manager import manager
from app.jobs import queue

router = APIRouter(prefix="/v1", tags=["openai-compat"])


class SpeechRequest(BaseModel):
    model: str = "seslab"
    input: str = Field(min_length=1, max_length=20_000)
    voice: str = "default"
    response_format: str = "wav"   # wav | mp3
    # None → sunucu varsayılanı (insan temposu); OpenAI istemcileri 1.0
    # gönderirse aynen uygulanır (mutlak değer)
    speed: float | None = Field(default=None, ge=0.5, le=2.0)
    language: str = DEFAULT_LANGUAGE  # OpenAI şemasına ek alan


def _resolve_voice(name_or_id: str) -> str | None:
    """OpenAI 'voice' alanı: kütüphane kimliği, ad veya 'default'."""
    if not name_or_id or name_or_id in ("default", "alloy", "echo", "fable",
                                        "onyx", "nova", "shimmer"):
        return None  # yerleşik varsayılan ses
    if voices.get_voice(name_or_id) is not None:
        return name_or_id
    for v in voices.list_voices():
        if v["name"].lower() == name_or_id.lower():
            return v["id"]
    raise HTTPException(404, f"Ses bulunamadı: {name_or_id}")


@router.post("/audio/speech")
async def speech(req: SpeechRequest):
    voice_id = _resolve_voice(req.voice)
    # Ses verisi JSON'a giremez (iş kaydı serileştirilir) → bant dışı taşı
    holder: dict = {}

    async def runner(job):
        audio, sr, _ = await synth_text(
            req.input,
            language=req.language,
            voice_id=voice_id,
            speed=req.speed,
            engine=default_engine(),
            job=job,
            verify=False,
        )
        holder["audio"], holder["sr"] = audio, sr
        return {"ok": True}

    job = await queue.submit_and_wait("tts", {"source": "openai"}, runner)
    if job.status == "error":
        raise HTTPException(500, job.message or "Sentez başarısız")
    audio, sr = holder["audio"], holder["sr"]

    if req.response_format == "mp3":
        data = await asyncio.to_thread(encode_mp3, audio, sr)
        return Response(content=data, media_type="audio/mpeg")

    def _wav_bytes() -> bytes:
        import soundfile as sf

        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV")
        return buf.getvalue()

    return Response(
        content=await asyncio.to_thread(_wav_bytes), media_type="audio/wav"
    )


@router.post("/audio/transcriptions")
async def transcriptions(
    file: UploadFile = Form(...),
    model: str = Form("whisper-1"),
    # None: FastAPI boş string'i "gönderilmemiş" sayar; OpenAI'de de language
    # opsiyoneldir → verilmezse otomatik dil algılama
    language: str | None = Form(None),
    response_format: str = Form("json"),
):
    data = await read_limited(file)

    def _run() -> dict:
        audio, _ = decode_audio(data, target_sr=STT_SR)
        engine = manager.ensure("stt")
        result = engine.transcribe(
            audio, language=language or None,
            word_timestamps=response_format in ("verbose_json", "srt", "vtt"),
        )
        manager.watchdog()
        return result

    async def runner(job):
        result = await asyncio.to_thread(_run)
        return {
            "text": (result.get("text") or "").strip(),
            "language": result.get("language"),
            "segments": [
                {"start": s["start"], "end": s["end"], "text": s["text"].strip(),
                 "words": s.get("words", [])}
                for s in result.get("segments", [])
            ],
        }

    job = await queue.submit_and_wait("stt", {"source": "openai"}, runner)
    if job.status == "error":
        raise HTTPException(500, job.message or "Deşifre başarısız")
    result = job.result

    if response_format == "text":
        return Response(result["text"] + "\n", media_type="text/plain; charset=utf-8")
    if response_format == "srt":
        return Response(to_srt(result), media_type="text/plain; charset=utf-8")
    if response_format == "vtt":
        return Response(to_vtt(result), media_type="text/vtt; charset=utf-8")
    if response_format == "verbose_json":
        return {
            "task": "transcribe",
            "language": result["language"],
            "text": result["text"],
            "segments": result["segments"],
        }
    return {"text": result["text"]}
