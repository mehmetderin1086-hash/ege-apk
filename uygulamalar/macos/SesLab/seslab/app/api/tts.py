"""TTS uçları: /api/tts ve /api/normalize/preview."""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.config import DEFAULT_LANGUAGE, DEFAULT_SPEECH_SPEED, LANGUAGES
from app.core import history
from app.core.synth import default_engine, effective_voice_id, synth_text
from app.core.text.chunk_tr import chunk_text
from app.core.text.normalize_tr import normalize_tr
from app.jobs import queue

router = APIRouter(prefix="/api", tags=["tts"])

class TTSRequest(BaseModel):
    # Uzun metinler synth_text içinde güvenli XTTS/Chatterbox parçalarına
    # bölünür. Konuşturucu ekranında yapay bir karakter tavanı yoktur.
    text: str = Field(min_length=1)
    voice_id: str | None = None
    language: str = DEFAULT_LANGUAGE
    exaggeration: float = Field(default=0.5, ge=0.0, le=2.0)
    cfg_weight: float = Field(default=0.5, ge=0.0, le=1.0)
    temperature: float = Field(default=0.8, ge=0.05, le=2.0)
    # None → sunucu varsayılanı (DEFAULT_SPEECH_SPEED — insan temposu)
    speed: float | None = Field(default=None, ge=0.5, le=2.0)
    normalize: bool = True
    # Parça başına Whisper + yeniden üretim çok pahalıdır. Ana stüdyo varsayılanı
    # hızlıdır; kullanıcı gerektiğinde arayüzden titiz denetimi açabilir.
    verify: bool = False
    # None → sunucu varsayılanı (XTTS kuruluysa xtts; kullanıcı tercihi)
    engine: str | None = Field(default=None, pattern="^(chatterbox|xtts)$")


class NormalizePreviewRequest(BaseModel):
    text: str = Field(min_length=1)


@router.post("/tts")
async def tts(req: TTSRequest):
    if req.language not in LANGUAGES:
        raise HTTPException(400, f"Desteklenmeyen dil: {req.language}")
    engine = req.engine or default_engine()
    speed = req.speed if req.speed is not None else DEFAULT_SPEECH_SPEED
    used_voice_id = effective_voice_id(req.voice_id, req.language, engine)
    if engine == "xtts":
        from app.engines.manager import manager

        if not manager.engines["xtts"].available():
            raise HTTPException(
                400,
                "XTTS motoru kurulu değil (.venv-xtts eksik). "
                "Kurulum için README'deki kurulum adımlarına bakın.",
            )
    async def runner(job):
        audio, sr, norm_text = await synth_text(
            req.text,
            language=req.language,
            # Varsayılan seçim de gerçekte hangi klon/model kullanıldıysa onu
            # kaydetsin; kalite karşılaştırmaları yeniden üretilebilir olsun.
            voice_id=used_voice_id,
            exaggeration=req.exaggeration,
            cfg_weight=req.cfg_weight,
            temperature=req.temperature,
            speed=speed,
            normalize=req.normalize,
            verify=req.verify,
            engine=engine,
            job=job,
        )
        record = history.add(
            "tts", audio, sr,
            text=req.text,
            params={
                "engine": engine,
                "language": req.language,
                "exaggeration": req.exaggeration,
                "cfg_weight": req.cfg_weight,
                "temperature": req.temperature,
                "speed": speed,
                "normalize": req.normalize,
                "verify": req.verify,
                "normalized_text": norm_text,
            },
            voice_id=req.voice_id,
        )
        return {
            "history_id": record["id"],
            "url": f"/api/history/{record['id']}/audio",
            "duration_s": record["duration_s"],
            "normalized_text": norm_text,
        }

    job = await queue.submit_and_wait("tts", {"text_len": len(req.text)}, runner)
    if job.status == "error":
        raise HTTPException(500, job.message or "Sentez başarısız")
    return job.result


@router.post("/normalize/preview")
async def normalize_preview(req: NormalizePreviewRequest):
    normalized, applied = normalize_tr(req.text)
    chunks = chunk_text(normalized)
    return {
        "original": req.text,
        "normalized": normalized,
        "applied_rules": applied,
        "chunks": [
            {"i": c.i, "text": c.text, "chars": c.chars,
             "paragraph_break": c.paragraph_break}
            for c in chunks
        ],
    }


@router.get("/languages")
async def languages():
    return {"languages": LANGUAGES, "default": DEFAULT_LANGUAGE}


@router.get("/engines")
async def engines():
    """Kullanılabilir TTS motorları ve sunucu varsayılanı (UI bunu okur)."""
    from app.engines.manager import manager

    return {
        "default": default_engine(),
        "default_speed": DEFAULT_SPEECH_SPEED,
        "engines": {
            "chatterbox": {"label": "Chatterbox (MIT)", "available": True},
            "xtts": {
                "label": "XTTS-v2 (ticari değil)",
                "available": manager.engines["xtts"].available(),
            },
        },
    }
