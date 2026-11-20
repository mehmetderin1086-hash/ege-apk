"""Hazır ses parçalarını yayın kalitesinde tek dosyada birleştiren uç.

BioProf'un podcast hattı replikleri konuşmacıya göre gruplayıp sentezliyor;
montaj ve mastering burada yapılıyor ki DSP zinciri (fade, seviye eşitleme,
-16 LUFS) tek yerde kalsın ve iki projede ayrı ayrı bakım gerektirmesin.
Sentez yapılmadığı için ağır motor yüklenmez.
"""
from __future__ import annotations

import asyncio
import io
import json
import wave

import numpy as np
from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import Response

from app.api.common import read_limited
from app.audio.io import decode_audio, encode_mp3
from app.audio.postprocess import match_levels, master, stitch, trim_edge_silence
from app.config import TTS_SR

router = APIRouter(prefix="/api", tags=["mastering"])

MAX_PARCA = 200


def _master_sync(
    parts: list[np.ndarray], gaps_s: list[float], normalize: bool
) -> tuple[np.ndarray, list[float]]:
    """Birleştirir ve parçaların NİHAİ sürelerini de döndürür.

    stitch(normalize=True) kenar sessizliğini kırptığı için parça süreleri
    değişiyor; çağıran (BioProf podcast altyazısı) zaman damgalarını ham TTS
    sürelerinden hesaplarsa altyazı kayıyor. Bu yüzden zincir burada adım adım
    yürütülüp kırpılmış süreler geri veriliyor.
    """
    if normalize:
        parts = [trim_edge_silence(p, TTS_SR) for p in parts]
        parts = match_levels(parts)
    durations = [len(p) / TTS_SR for p in parts]
    out = stitch(parts, TTS_SR, gaps_s=gaps_s, normalize=False)
    if normalize:
        out = master(out, TTS_SR)
    return out, durations


@router.post("/audio/master")
async def master_audio(
    files: list[UploadFile] = Form(...),
    gap_ms: int = Form(320),
    gaps_ms: str | None = Form(None),
    format: str = Form("wav"),
    normalize: bool = Form(True),
):
    """Sırayla verilen ses parçalarını birleştirip ustalar.

    `gaps_ms` verilirse parça başına aralık listesi (JSON dizi) olarak
    kullanılır; verilmezse tüm aralıklar `gap_ms` olur.
    """
    if not files:
        raise HTTPException(status_code=400, detail="En az bir ses parçası gerekli")
    if len(files) > MAX_PARCA:
        raise HTTPException(status_code=413, detail=f"En fazla {MAX_PARCA} parça birleştirilir")
    if format not in {"wav", "mp3"}:
        raise HTTPException(status_code=400, detail="format yalnız 'wav' veya 'mp3' olabilir")

    parts: list[np.ndarray] = []
    for item in files:
        data = await read_limited(item)
        if not data:
            raise HTTPException(status_code=400, detail=f"Boş ses parçası: {item.filename}")
        try:
            audio, _ = decode_audio(data, target_sr=TTS_SR)
        except Exception as exc:
            raise HTTPException(
                status_code=400, detail=f"Ses parçası çözülemedi: {item.filename}"
            ) from exc
        if audio.size == 0:
            raise HTTPException(status_code=400, detail=f"Sessiz ses parçası: {item.filename}")
        parts.append(audio)

    if gaps_ms:
        try:
            değerler = json.loads(gaps_ms)
            aralıklar = [max(0.0, float(value) / 1000.0) for value in değerler]
        except (json.JSONDecodeError, TypeError, ValueError) as exc:
            raise HTTPException(status_code=400, detail="gaps_ms geçerli bir JSON dizi değil") from exc
    else:
        aralıklar = [max(0, gap_ms) / 1000.0] * len(parts)

    out, durations = await asyncio.to_thread(_master_sync, parts, aralıklar, normalize)
    if out.size == 0:
        raise HTTPException(status_code=500, detail="Birleştirme boş ses üretti")
    headers = {"X-Segment-Durations": json.dumps([round(value, 3) for value in durations])}

    if format == "mp3":
        return Response(
            content=encode_mp3(out, TTS_SR), media_type="audio/mpeg", headers=headers
        )

    # 16-bit PCM: BioProf'un WAV doğrulayıcısı sıkıştırılmamış akış bekler.
    buffer = io.BytesIO()
    pcm = np.clip(out, -1.0, 1.0)
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(TTS_SR)
        handle.writeframes((pcm * 32767.0).astype("<i2").tobytes())
    return Response(content=buffer.getvalue(), media_type="audio/wav", headers=headers)
