"""SesLab — FastAPI uygulama fabrikası.

Çalıştırma:  uv run uvicorn app.main:app --port 8010
"""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api import (
    history,
    mastering,
    openai_compat,
    projects,
    stt,
    system,
    tts,
    vc,
    voices,
)
from app.config import WEB_DIR, ensure_dirs
from app.db import init_db
from app.engines.manager import manager
from app.jobs import queue

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)


async def _idle_unload_loop() -> None:
    """Boşta kalan motorları periyodik boşalt (16 GB bütçesi).

    Tek bir hata görevi öldürmemeli: boşaltma başarısız olsa bile döngü sürer.
    """
    log = logging.getLogger("seslab.idle")
    while True:
        await asyncio.sleep(60)
        try:
            await asyncio.to_thread(manager.unload_idle)
        except Exception:  # noqa: BLE001
            log.exception("Boşta motor boşaltma hatası (döngü sürüyor)")


@asynccontextmanager
async def lifespan(app: FastAPI):
    ensure_dirs()
    init_db()
    queue.start()
    idle_task = asyncio.create_task(_idle_unload_loop())
    yield
    idle_task.cancel()
    await queue.stop()


app = FastAPI(title="SesLab", version="0.1.0", lifespan=lifespan)


@app.middleware("http")
async def disable_frontend_cache(request, call_next):
    """Yerel arayüz değişikliklerinin tarayıcı önbelleğinde takılmasını önle."""
    response = await call_next(request)
    path = request.url.path
    if path == "/" or path.endswith((".html", ".css", ".js")):
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response

app.include_router(tts.router)
app.include_router(voices.router)
app.include_router(stt.router)
app.include_router(vc.router)
app.include_router(projects.router)
app.include_router(history.router)
app.include_router(system.router)
app.include_router(mastering.router)
app.include_router(openai_compat.router)

# Statik frontend — API rotalarından sonra; "/" → web/index.html
app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
