"""Dışa aktarım, taşınabilir arşiv, geri yükleme, motor ve iş durumu uçları."""

from __future__ import annotations

import re
import shutil
import uuid
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse

from kitapkatalog.exporters import ExportFormat, export_catalog
from kitapkatalog.webapp.jobs import WebJob
from kitapkatalog.webapp.serialize import engine_status_to_dict
from kitapkatalog.webapp.state import WebState
from kitapkatalog.webapp.uploads import stage_upload

router = APIRouter(tags=["system"])

_SAFE_NAME = re.compile(r"^[\w][\w.\-]*$")


def _state(request: Request) -> WebState:
    return request.app.state.web


def _stamp() -> str:
    return datetime.now(UTC).strftime("%Y%m%d-%H%M%S")


@router.post("/exports", status_code=202)
def start_export(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    format_name = str(payload.get("format") or "xlsx").lower()
    try:
        export_format = ExportFormat(format_name)
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Bilinmeyen biçim: {format_name}") from None
    completed_only = bool(payload.get("completed_only", True))

    def run(job: WebJob) -> dict[str, Any]:
        job.message = "Katalog dışa aktarılıyor…"
        exports = state.paths.exports
        exports.mkdir(parents=True, exist_ok=True)
        stamp = _stamp()
        if export_format is ExportFormat.MARKDOWN:
            # Markdown çok dosyalı üretir: dizine yaz, tek ZIP olarak indirt.
            directory = exports / f"katalog-{stamp}-md"
            result = export_catalog(
                state.database, directory, format=export_format, completed_only=completed_only
            )
            archive = exports / f"katalog-{stamp}-markdown.zip"
            with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
                for path in sorted(directory.rglob("*")):
                    if path.is_file():
                        bundle.write(path, path.relative_to(directory))
            shutil.rmtree(directory, ignore_errors=True)
            download = archive.name
        else:
            destination = exports / f"katalog-{stamp}.{export_format.value}"
            result = export_catalog(
                state.database, destination, format=export_format, completed_only=completed_only
            )
            download = Path(result.path).name
        return {"download": download, "records": result.records}

    web_job = state.registry.start("export", f"Dışa aktarım ({format_name})", run)
    return web_job.to_dict()


@router.post("/archive", status_code=202)
def start_archive(request: Request, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    state = _state(request)
    include_covers = bool((payload or {}).get("include_covers", False))

    def run(job: WebJob) -> dict[str, Any]:
        from kitapkatalog.archive import create_archive
        from kitapkatalog.restore import collect_cover_paths

        job.message = "Taşınabilir yedek oluşturuluyor…"
        cover_paths = (
            collect_cover_paths(state.database.path, state.paths.assets)
            if include_covers
            else []
        )
        target = state.paths.exports / f"kitapkatalog-{_stamp()}.kitaparsiv"
        info = create_archive(
            state.database.path,
            target,
            asset_root=state.paths.assets,
            cover_paths=cover_paths,
            include_covers=include_covers,
        )
        return {
            "download": Path(info.path).name,
            "cover_count": info.cover_count,
            "database_size": info.database_size,
        }

    web_job = state.registry.start("archive", "Taşınabilir yedek", run)
    return web_job.to_dict()


@router.post("/restore/upload", status_code=202)
async def restore_upload(request: Request, file: UploadFile) -> dict[str, Any]:
    """`.kitaparsiv` yükle → arka planda doğrula ve hazırlığa çıkar."""

    from kitapkatalog.restore import MAX_UPLOAD_BYTES, RESTORE_DIRNAME, stage_archive

    state = _state(request)
    name = Path(file.filename or "yedek").name
    if not name.lower().endswith(".kitaparsiv"):
        raise HTTPException(status_code=400, detail="Yalnız .kitaparsiv dosyası yüklenebilir")
    restore_dir = state.paths.root / RESTORE_DIRNAME
    restore_dir.mkdir(parents=True, exist_ok=True)
    upload_path: Path | None = None
    try:
        upload_path = await stage_upload(
            restore_dir,
            file,
            allowed_suffixes={".kitaparsiv"},
            maximum_bytes=MAX_UPLOAD_BYTES,
            kind="archive",
            target_name=f"yukleme-{uuid.uuid4().hex}.kitaparsiv",
        )
        assert upload_path is not None

        def run(job: WebJob) -> dict[str, Any]:
            job.message = "Yedek doğrulanıyor…"
            try:
                summary = stage_archive(upload_path, state.paths)
            finally:
                upload_path.unlink(missing_ok=True)
            return summary.to_dict()

        return state.registry.start("restore", "Yedek doğrulama", run).to_dict()
    except Exception:
        # Doğrulama işi başlatılamadıysa (409 dolu yuva, 413, IO hatası)
        # yükleme dosyası artık kalmasın.
        if upload_path is not None:
            upload_path.unlink(missing_ok=True)
        raise


@router.get("/restore/status")
def restore_status(request: Request) -> dict[str, Any]:
    from kitapkatalog.restore import pending_info

    state = _state(request)
    job = state.registry.get("restore")
    return {"job": job.to_dict() if job else None, **pending_info(state.paths)}


@router.post("/restore/confirm")
def restore_confirm(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    from kitapkatalog.restore import confirm_restore

    staging_id = str(payload.get("staging_id") or "")
    return confirm_restore(staging_id, _state(request).paths)


@router.delete("/restore/pending")
def restore_cancel(request: Request) -> dict[str, Any]:
    from kitapkatalog.restore import cancel_pending

    return {"cancelled": cancel_pending(_state(request).paths)}


@router.get("/exports/status")
def export_status(request: Request) -> dict[str, Any]:
    state = _state(request)
    return {
        "export": (job.to_dict() if (job := state.registry.get("export")) else None),
        "archive": (job.to_dict() if (job := state.registry.get("archive")) else None),
    }


@router.get("/exports/download/{name}")
def download_export(request: Request, name: str) -> FileResponse:
    state = _state(request)
    if not _SAFE_NAME.match(name):
        raise HTTPException(status_code=400, detail="Geçersiz dosya adı")
    path = (state.paths.exports / name).resolve()
    if not path.is_file() or state.paths.exports.resolve() not in path.parents:
        raise HTTPException(status_code=404, detail="Dışa aktarım dosyası bulunamadı")
    return FileResponse(path, filename=name)


# ------------------------------------------------------------------ motorlar


@router.get("/engines")
def engine_statuses(request: Request) -> dict[str, Any]:
    state = _state(request)
    job = state.registry.get("engines")
    return {
        "statuses": state.engine_cache,
        "job": job.to_dict() if job else None,
    }


@router.post("/engines/verify", status_code=202)
def verify_engines(request: Request) -> dict[str, Any]:
    state = _state(request)

    def run(job: WebJob) -> list[dict[str, Any]]:
        job.message = "Motor paketleri doğrulanıyor (SHA-256)…"
        statuses = [
            engine_status_to_dict(status)
            for status in state.ctx.models.engine_statuses()
        ]
        statuses.append(engine_status_to_dict(state.ctx.models.extractor_status()))
        state.engine_cache = statuses
        return statuses

    web_job = state.registry.start("engines", "Motor doğrulama", run)
    return web_job.to_dict()


@router.get("/jobs/overview")
def jobs_overview(request: Request) -> dict[str, Any]:
    """Tüm iş yuvalarının anlık görünümü (üst çubuk göstergesi için)."""

    return _state(request).registry.snapshot()


@router.get("/badges")
def badges(request: Request) -> dict[str, Any]:
    """Gezinme rozetleri için hafif sayaçlar (tam kayıt listesi kurulmaz)."""

    state = _state(request)
    pair_row = state.database.fetchone(
        "SELECT COUNT(*) FROM job_item WHERE needs_pair_review = 1"
    )
    return {
        "review": state.catalog.stats()["review"],
        "pairs": int(pair_row[0]) if pair_row else 0,
        "overdue": state.loans.stats()["overdue"],
        "notifications": state.notifications.unread_count(),
    }


@router.get("/status/summary")
def status_summary(request: Request) -> dict[str, Any]:
    """One lightweight request for navigation badges and running web jobs."""

    return {
        "badges": badges(request),
        "jobs": _state(request).registry.snapshot(),
    }
