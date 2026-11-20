"""PDF Studio — FastAPI uygulaması."""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from . import config
from .routers import (batch, compare, convert, core, edit, forms, optimize,
                      organize, security)

config.ensure_dirs()

app = FastAPI(title="PDF Studio", version="1.0.0",
              description="iLovePDF benzeri yerel PDF düzenleme uygulaması")


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    # Beklenmeyen hatalar jenerik İngilizce 500 yerine arayüzün gösterebileceği
    # Türkçe bir detayla döner (ErrorResponse şeması: {"detail": ...}).
    return JSONResponse(
        status_code=500,
        content={"detail": f"Beklenmeyen sunucu hatası: {type(exc).__name__}: {exc}"},
    )

# API router'ları
app.include_router(core.router)
app.include_router(organize.router)
app.include_router(optimize.router)
app.include_router(convert.router)
app.include_router(edit.router)
app.include_router(security.router)
app.include_router(forms.router)
app.include_router(batch.router)
app.include_router(compare.router)


@app.get("/health")
async def health():
    return {"status": "ok", "app": config.APP_ID,
            "version": app.version, "port": config.PORT}


@app.get("/")
async def index():
    return FileResponse(config.WEB_DIR / "index.html")


# Statik dosyalar (CSS/JS/asset) — en sona monte edilir ki /api rotalarını gölgelemesin
app.mount("/", StaticFiles(directory=str(config.WEB_DIR), html=True), name="web")
