"""Sistem durumu, motor yönetimi, model kurulumu ve iş (SSE) uçları."""
from __future__ import annotations

import asyncio

import psutil
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse

from app import setup_models
from app.engines.manager import manager
from app.jobs import queue

router = APIRouter(prefix="/api", tags=["system"])


@router.get("/system/status")
async def status():
    models = await asyncio.to_thread(setup_models.check)
    vm = psutil.virtual_memory()
    return {
        **manager.status(),
        "models": models,
        "models_present": all(v is not None for v in models.values()),
        "ram_total_gb": round(vm.total / 1e9, 1),
        "ram_used_gb": round((vm.total - vm.available) / 1e9, 1),
    }


@router.post("/system/engines/{name}/unload")
async def unload_engine(name: str):
    if name not in manager.engines:
        raise HTTPException(404, f"Bilinmeyen motor: {name}")
    await asyncio.to_thread(manager.unload, name)
    return manager.status()


@router.post("/setup/download")
async def download_models():
    async def runner(job):
        loop = asyncio.get_running_loop()

        def progress_cb(repo: str, done: int, total: int) -> None:
            msg = (
                f"{repo} indiriliyor ({done + 1}/{total})..."
                if done < total
                else f"{repo} tamam ({done}/{total})"
            )
            asyncio.run_coroutine_threadsafe(
                queue.update(job, progress=done / total, message=msg), loop
            )

        await asyncio.to_thread(setup_models.download, progress_cb)
        return {"ok": True}

    job = queue.submit("download", {}, runner)
    return {"job_id": job.id}


@router.get("/jobs/{job_id}")
async def get_job(job_id: str):
    job = queue.jobs.get(job_id)
    if job is None:
        raise HTTPException(404, "İş bulunamadı")
    return job.public()


@router.get("/jobs/{job_id}/events")
async def job_events(job_id: str):
    return StreamingResponse(
        queue.events(job_id),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
