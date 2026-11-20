"""Uzun metin projeleri uçları."""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field

from app.config import DEFAULT_SPEECH_SPEED, LANGUAGES
from app.core import projects
from app.core.synth import default_engine
from app.jobs import queue

router = APIRouter(prefix="/api/projects", tags=["projects"])


class ProjectCreateRequest(BaseModel):
    title: str = Field(default="", max_length=200)
    # Kitap boyu metinler desteklenir (5 milyon karakter ≈ 1500+ sayfa)
    text: str = Field(min_length=1, max_length=5_000_000)
    # STT doğrulama: kapatılırsa sentez ~%40-50 hızlanır ama artefakt
    # yakalama/onarma devre dışı kalır (uzun kitaplarda hız için seçenek)
    verify: bool = False
    voice_id: str | None = None
    language: str = "tr"
    exaggeration: float = Field(default=0.5, ge=0.0, le=2.0)
    cfg_weight: float = Field(default=0.5, ge=0.0, le=1.0)
    temperature: float = Field(default=0.8, ge=0.05, le=2.0)
    # None → sunucu varsayılanı (insan temposu)
    speed: float | None = Field(default=None, ge=0.5, le=2.0)
    normalize: bool = True
    # None → sunucu varsayılanı (XTTS kuruluysa xtts)
    engine: str | None = Field(default=None, pattern="^(chatterbox|xtts)$")


@router.get("")
async def list_all():
    return {"projects": projects.list_projects()}


@router.post("")
async def create(req: ProjectCreateRequest):
    if req.language not in LANGUAGES:
        raise HTTPException(400, f"Desteklenmeyen dil: {req.language}")
    try:
        project = projects.create_project(
            req.title,
            req.text,
            req.voice_id,
            params={
                "engine": req.engine or default_engine(),
                "verify": req.verify,
                "language": req.language,
                "exaggeration": req.exaggeration,
                "cfg_weight": req.cfg_weight,
                "temperature": req.temperature,
                "speed": req.speed if req.speed is not None else DEFAULT_SPEECH_SPEED,
            },
            normalize=req.normalize,
        )
    except ValueError as e:
        raise HTTPException(400, str(e)) from None
    return project


@router.post("/extract")
async def extract(file: UploadFile = Form(...)):
    """PDF / DOCX / TXT dosyasından metin çıkarır (proje oluşturma öncesi)."""
    from app.api.common import read_limited
    from app.core.extract import extract_text

    data = await read_limited(file, max_mb=100)
    try:
        text = await asyncio.to_thread(extract_text, file.filename or "", data)
    except ValueError as e:
        raise HTTPException(400, str(e)) from None
    return {
        "filename": file.filename,
        "chars": len(text),
        "text": text,
    }


@router.get("/{project_id}")
async def get(project_id: str):
    project = projects.get_project(project_id)
    if project is None:
        raise HTTPException(404, "Proje bulunamadı")
    return project


@router.delete("/{project_id}")
async def delete(project_id: str):
    try:
        projects.delete_project(project_id)
    except KeyError:
        raise HTTPException(404, "Proje bulunamadı") from None
    return {"ok": True}


@router.post("/{project_id}/start")
async def start(project_id: str):
    if projects.get_project(project_id) is None:
        raise HTTPException(404, "Proje bulunamadı")

    async def runner(job):
        return await projects.run_project(project_id, job)

    job = queue.submit("project", {"project_id": project_id}, runner)
    return {"job_id": job.id}


@router.post("/{project_id}/chunks/{idx}/regenerate")
async def regenerate_chunk(project_id: str, idx: int):
    project = projects.get_project(project_id)
    if project is None:
        raise HTTPException(404, "Proje bulunamadı")
    if not any(c["idx"] == idx for c in project["chunks"]):
        raise HTTPException(404, "Bölüm bulunamadı")

    async def runner(job):
        return await projects.run_project(project_id, job, only_idx=idx)

    job = queue.submit("chunk", {"project_id": project_id, "idx": idx}, runner)
    return {"job_id": job.id}


@router.get("/{project_id}/export")
async def export(project_id: str, format: str = "mp3"):
    # MP3: akışlı dosya kodlaması — kitap ölçeğinde bile belleği/4 GB WAV
    # sınırını aşmaz (tek dosya). WAV: yalnız makul boyut (aksi hâlde 400).
    try:
        if format == "mp3":
            out_path = await asyncio.to_thread(projects.export_mp3_to_file, project_id)
            return FileResponse(
                out_path, media_type="audio/mpeg",
                filename=f"proje_{project_id}.mp3",
            )
        audio, sr = await asyncio.to_thread(projects.export_audio, project_id)
    except KeyError:
        raise HTTPException(404, "Proje bulunamadı") from None
    except ValueError as e:
        raise HTTPException(400, str(e)) from None

    def _wav_bytes() -> bytes:
        import io

        import soundfile as sf

        buf = io.BytesIO()
        sf.write(buf, audio, sr, format="WAV")
        return buf.getvalue()

    data = await asyncio.to_thread(_wav_bytes)
    return Response(
        content=data,
        media_type="audio/wav",
        headers={
            "Content-Disposition": f'attachment; filename="proje_{project_id}.wav"'
        },
    )
