from __future__ import annotations

import asyncio
import json
import secrets
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import select

from . import __version__
from .config import AppSettings, get_settings
from .db import Database
from .engines.aria2 import Aria2Supervisor, DirectDownloadEngine, DownloadEngineError
from .engines.media import MediaDownloadEngine
from .events import EventBroker
from .inspection import InspectionService
from .logging_config import configure_logging
from .models import JobEvent, PairCode, PairedClient, utcnow
from .queue import QueueManager
from .runtime import RuntimeRegistry
from .safe_proxy import SafeOutboundProxy
from .schemas import (
    CancelRequest,
    HealthResponse,
    InspectRequest,
    InspectResponse,
    JobCreate,
    JobRead,
    JobsPage,
    PairCompleteRequest,
    PairCompleteResponse,
    PairedClientRead,
    PairStartResponse,
    PriorityUpdate,
    SettingsRead,
    SettingsUpdate,
)
from .security import ensure_allowed_path, hash_secret, new_token, require_extension_origin
from .service import DownloadService

PACKAGE_DIR = Path(__file__).resolve().parent


class Components:
    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.transient_urls: dict[str, tuple[str, str | None]] = {}
        self.database = Database(settings)
        self.runtime = RuntimeRegistry(settings)
        self.safe_proxy = SafeOutboundProxy(settings)
        self.events = EventBroker(self.database)
        self.inspections = InspectionService(settings, self.runtime)
        self.service = DownloadService(
            settings,
            self.database,
            self.inspections,
            self.events,
            self.transient_urls,
        )
        self.aria2 = Aria2Supervisor(settings, self.runtime)
        self.direct = DirectDownloadEngine(settings, self.aria2)
        self.media = MediaDownloadEngine(settings, self.runtime)
        self.queue = QueueManager(
            settings,
            self.database,
            self.events,
            self.direct,
            self.media,
            self.transient_urls,
        )
        self.pair_attempts: defaultdict[str, deque[float]] = defaultdict(deque)
        self.pair_attempts_global: deque[float] = deque()
        self.pair_attempt_lock = asyncio.Lock()


def create_app(settings: AppSettings | None = None) -> FastAPI:
    settings = settings or get_settings()
    settings.prepare()
    configure_logging(settings.log_dir)
    components = Components(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        await components.safe_proxy.start()
        try:
            await components.database.initialize()
            try:
                await components.service.apply_persisted_settings()
                await components.aria2.start()
                try:
                    await components.queue.start()
                    app.state.components = components
                    try:
                        yield
                    finally:
                        await components.queue.stop()
                finally:
                    await components.aria2.stop()
            finally:
                await components.database.close()
        finally:
            await components.safe_proxy.stop()

    app = FastAPI(
        title="DownloadHub",
        version=__version__,
        docs_url="/api/docs",
        redoc_url=None,
        lifespan=lifespan,
    )
    app.state.components = components
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"chrome-extension://.*",
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-CSRF-Token"],
    )
    app.mount("/static", StaticFiles(directory=PACKAGE_DIR / "static"), name="static")
    templates = Jinja2Templates(directory=PACKAGE_DIR / "templates")

    @app.middleware("http")
    async def local_security(request: Request, call_next):
        allowed_hosts = {
            "127.0.0.1",
            f"127.0.0.1:{settings.port}",
            "localhost",
            f"localhost:{settings.port}",
        }
        if request.headers.get("host", "").lower() not in allowed_hosts:
            return JSONResponse(status_code=400, content={"detail": "Geçersiz Host başlığı"})
        origin = request.headers.get("origin")
        extension_request = bool(origin and origin.startswith("chrome-extension://"))
        if origin and not extension_request:
            allowed = {
                f"http://127.0.0.1:{settings.port}",
                f"http://localhost:{settings.port}",
            }
            if origin.rstrip("/") not in allowed:
                return JSONResponse(status_code=403, content={"detail": "Geçersiz origin"})
        if request.method in {"POST", "PUT", "PATCH", "DELETE"} and not extension_request:
            cookie = request.cookies.get("dh_csrf")
            header = request.headers.get("x-csrf-token")
            if cookie and header != cookie:
                return JSONResponse(status_code=403, content={"detail": "CSRF doğrulaması başarısız"})
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' data: https:; "
            "script-src 'self'; style-src 'self'; connect-src 'self' http://127.0.0.1:*; "
            "object-src 'none'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
        )
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        return response

    def get_components(request: Request) -> Components:
        return request.app.state.components

    async def authorize_extension_if_needed(
        request: Request,
        current: Components = Depends(get_components),
    ) -> None:
        origin = request.headers.get("origin")
        if not origin or not origin.startswith("chrome-extension://"):
            return
        authorization = request.headers.get("authorization", "")
        if not authorization.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Eklenti eşleştirilmemiş")
        token_hash = hash_secret(authorization.removeprefix("Bearer ").strip())
        async with current.database.sessions.begin() as session:
            client = await session.scalar(
                select(PairedClient).where(
                    PairedClient.token_hash == token_hash,
                    PairedClient.revoked_at.is_(None),
                )
            )
            if not client or client.origin != origin.rstrip("/"):
                raise HTTPException(status_code=401, detail="Eklenti erişimi geçersiz")
            client.last_seen_at = utcnow()

    @app.exception_handler(DownloadEngineError)
    async def engine_exception(_request: Request, exc: DownloadEngineError):
        status_code = 404 if exc.code == "NOT_FOUND" else 409
        return JSONResponse(
            status_code=status_code,
            content={"detail": str(exc), "code": exc.code},
        )

    @app.get("/", response_class=HTMLResponse)
    async def index(request: Request):
        csrf_token = secrets.token_urlsafe(24)
        response = templates.TemplateResponse(
            request=request,
            name="index.html",
            context={"csrf_token": csrf_token, "version": __version__},
        )
        response.set_cookie(
            "dh_csrf",
            csrf_token,
            httponly=False,
            samesite="strict",
            secure=False,
            max_age=86_400,
        )
        return response

    @app.get("/health", response_model=HealthResponse)
    @app.get("/readyz", response_model=HealthResponse)
    async def health(current: Components = Depends(get_components)):
        runtime_components = await current.runtime.components()
        missing = [item for item in runtime_components if item.required and not item.available]
        return HealthResponse(
            status="degraded" if missing else "ready",
            version=__version__,
            components=runtime_components,
        )

    @app.post(
        "/api/v1/inspect",
        response_model=InspectResponse,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def inspect(payload: InspectRequest, current: Components = Depends(get_components)):
        return await current.inspections.inspect(payload)

    @app.post(
        "/api/v1/jobs",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def create_job(
        payload: JobCreate,
        idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
        current: Components = Depends(get_components),
    ):
        job = await current.service.create_job(payload, idempotency_key=idempotency_key)
        return JobRead.model_validate(job)

    @app.get(
        "/api/v1/jobs",
        response_model=JobsPage,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def list_jobs(
        status: str | None = None,
        engine: str | None = None,
        category: str | None = None,
        q: str | None = None,
        page: int = Query(1, ge=1),
        page_size: int = Query(50, ge=1, le=200),
        current: Components = Depends(get_components),
    ):
        return await current.service.list_jobs(
            status=status,
            engine=engine,
            category=category,
            query=q,
            page=page,
            page_size=page_size,
        )

    @app.get(
        "/api/v1/jobs/{job_id}",
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def get_job(job_id: str, current: Components = Depends(get_components)):
        job = await current.service.get_job(job_id)
        async with current.database.sessions() as session:
            events = list(
                (
                    await session.scalars(
                        select(JobEvent)
                        .where(JobEvent.job_id == job_id)
                        .order_by(JobEvent.id.desc())
                        .limit(200)
                    )
                ).all()
            )
        return {
            "job": JobRead.model_validate(job).model_dump(mode="json"),
            "items": [
                {
                    "id": item.id,
                    "source_id": item.source_id,
                    "title": item.title,
                    "position": item.position,
                    "selected": item.selected,
                    "status": item.status,
                    "error_message": item.error_message,
                }
                for item in job.items
            ],
            "artifacts": [
                {
                    "id": artifact.id,
                    "kind": artifact.kind,
                    "path": artifact.path,
                    "size_bytes": artifact.size_bytes,
                    "sha256": artifact.sha256,
                }
                for artifact in job.artifacts
            ],
            "events": [
                {
                    "id": event.id,
                    "type": event.event_type,
                    "payload": event.payload,
                    "created_at": event.created_at.isoformat(),
                }
                for event in events
            ],
        }

    @app.post(
        "/api/v1/jobs/{job_id}/pause",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def pause_job(job_id: str, current: Components = Depends(get_components)):
        return JobRead.model_validate(await current.queue.pause(job_id))

    @app.post(
        "/api/v1/jobs/{job_id}/resume",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def resume_job(job_id: str, current: Components = Depends(get_components)):
        return JobRead.model_validate(await current.queue.resume(job_id))

    @app.post(
        "/api/v1/jobs/{job_id}/cancel",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def cancel_job(
        job_id: str,
        payload: CancelRequest | None = None,
        current: Components = Depends(get_components),
    ):
        keep_partial = payload.keep_partial if payload else True
        return JobRead.model_validate(await current.queue.cancel(job_id, keep_partial=keep_partial))

    @app.post(
        "/api/v1/jobs/{job_id}/retry",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def retry_job(job_id: str, current: Components = Depends(get_components)):
        return JobRead.model_validate(await current.queue.retry(job_id))

    @app.post(
        "/api/v1/jobs/{job_id}/priority",
        response_model=JobRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def update_job_priority(
        job_id: str,
        payload: PriorityUpdate,
        current: Components = Depends(get_components),
    ):
        return JobRead.model_validate(await current.queue.set_priority(job_id, payload.priority))

    async def file_action(job_id: str, reveal: bool, current: Components) -> Response:
        job = await current.service.get_job(job_id)
        if not job.output_path:
            raise HTTPException(status_code=409, detail="Görevin çıktı dosyası yok")
        artifact = next((item for item in job.artifacts if item.path == job.output_path), None)
        if artifact is None and job.artifacts:
            artifact = job.artifacts[-1]
        if artifact is None:
            raise HTTPException(status_code=409, detail="Görevin kayıtlı çıktı dosyası yok")
        path = ensure_allowed_path(Path(artifact.path), await current.service.allowed_download_roots())
        if not path.exists():
            raise HTTPException(status_code=404, detail="Çıktı dosyası bulunamadı")
        args = ["open", "-R", str(path)] if reveal else ["open", str(path)]
        process = await asyncio.create_subprocess_exec(
            *args, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL
        )
        await process.wait()
        if process.returncode != 0:
            raise HTTPException(status_code=500, detail="Dosya açılamadı")
        return Response(status_code=204)

    @app.post(
        "/api/v1/jobs/{job_id}/reveal",
        status_code=204,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def reveal_job(job_id: str, current: Components = Depends(get_components)):
        return await file_action(job_id, True, current)

    @app.post(
        "/api/v1/jobs/{job_id}/open",
        status_code=204,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def open_job(job_id: str, current: Components = Depends(get_components)):
        return await file_action(job_id, False, current)

    @app.get(
        "/api/v1/settings",
        response_model=SettingsRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def get_app_settings(current: Components = Depends(get_components)):
        return await current.service.get_settings()

    @app.put(
        "/api/v1/settings",
        response_model=SettingsRead,
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def update_app_settings(payload: SettingsUpdate, current: Components = Depends(get_components)):
        updated = await current.service.update_settings(payload)
        if current.aria2.available:
            await current.aria2.rpc(
                "aria2.changeGlobalOption",
                {
                    "max-concurrent-downloads": str(updated.max_concurrent_jobs),
                    "max-overall-download-limit": updated.global_speed_limit,
                },
            )
        return updated

    @app.post("/api/v1/pair/start", response_model=PairStartResponse)
    async def pair_start(request: Request, current: Components = Depends(get_components)):
        if request.headers.get("origin", "").startswith("chrome-extension://"):
            raise HTTPException(
                status_code=403,
                detail="Eşleştirme kodu yalnız DownloadHub web panelinden üretilebilir",
            )
        code = f"{secrets.randbelow(1_000_000):06d}"
        expires = datetime.now(UTC) + timedelta(minutes=5)
        async with current.database.sessions.begin() as session:
            session.add(PairCode(code_hash=hash_secret(code), expires_at=expires))
        return PairStartResponse(code=code, expires_at=expires)

    @app.post("/api/v1/pair/complete", response_model=PairCompleteResponse)
    async def pair_complete(
        payload: PairCompleteRequest,
        request: Request,
        current: Components = Depends(get_components),
    ):
        origin = require_extension_origin(request.headers.get("origin"))
        now_monotonic = asyncio.get_running_loop().time()
        async with current.pair_attempt_lock:
            cutoff = now_monotonic - 300
            while current.pair_attempts_global and current.pair_attempts_global[0] < cutoff:
                current.pair_attempts_global.popleft()
            attempts = current.pair_attempts[origin]
            while attempts and attempts[0] < cutoff:
                attempts.popleft()
            if len(attempts) >= 5 or len(current.pair_attempts_global) >= 20:
                raise HTTPException(
                    status_code=429,
                    detail="Çok fazla eşleştirme denemesi. Beş dakika sonra yeniden deneyin.",
                )
            attempts.append(now_monotonic)
            current.pair_attempts_global.append(now_monotonic)
        async with current.database.sessions.begin() as session:
            pair_code = await session.get(PairCode, hash_secret(payload.code.strip()))
            now = datetime.now(UTC)
            expires = pair_code.expires_at if pair_code else None
            if expires and expires.tzinfo is None:
                expires = expires.replace(tzinfo=UTC)
            if not pair_code or pair_code.used_at or not expires or expires < now:
                raise HTTPException(status_code=400, detail="Eşleştirme kodu geçersiz veya süresi dolmuş")
            pair_code.used_at = now
            token = new_token()
            client = PairedClient(
                name=payload.client_name[:128],
                origin=origin,
                token_hash=hash_secret(token),
            )
            session.add(client)
            await session.flush()
            client_id = client.id
        return PairCompleteResponse(token=token, client_id=client_id)

    @app.get("/api/v1/pair/clients", response_model=list[PairedClientRead])
    async def pair_clients(request: Request, current: Components = Depends(get_components)):
        if request.headers.get("origin", "").startswith("chrome-extension://"):
            raise HTTPException(status_code=403, detail="Eşleştirme listesi yalnız web panelinde gösterilir")
        async with current.database.sessions() as session:
            clients = (
                await session.scalars(
                    select(PairedClient)
                    .where(PairedClient.revoked_at.is_(None))
                    .order_by(PairedClient.created_at.desc())
                )
            ).all()
        return [PairedClientRead.model_validate(client) for client in clients]

    @app.post("/api/v1/pair/revoke", status_code=204)
    async def pair_revoke(
        payload: dict[str, Any],
        request: Request,
        current: Components = Depends(get_components),
    ):
        origin = request.headers.get("origin", "").rstrip("/")
        authorization = request.headers.get("authorization", "")
        async with current.database.sessions.begin() as session:
            if origin.startswith("chrome-extension://") and authorization.startswith("Bearer "):
                client = await session.scalar(
                    select(PairedClient).where(
                        PairedClient.token_hash == hash_secret(authorization.removeprefix("Bearer ").strip()),
                        PairedClient.origin == origin,
                        PairedClient.revoked_at.is_(None),
                    )
                )
            else:
                client_id = str(payload.get("client_id") or "")
                client = await session.get(PairedClient, client_id)
            if not client:
                raise HTTPException(status_code=404, detail="Eşleştirilmiş istemci bulunamadı")
            client.revoked_at = datetime.now(UTC)
        return Response(status_code=204)

    @app.get(
        "/api/v1/events",
        dependencies=[Depends(authorize_extension_if_needed)],
    )
    async def events_stream(
        request: Request,
        after: int = Query(0, ge=0),
        current: Components = Depends(get_components),
    ):
        async def stream():
            try:
                snapshot = await current.service.list_jobs(page=1, page_size=200)
                yield _sse(
                    0,
                    "snapshot",
                    {"jobs": [job.model_dump(mode="json") for job in snapshot.items]},
                )
                if after:
                    async with current.database.sessions() as session:
                        backlog = (
                            await session.scalars(
                                select(JobEvent)
                                .where(JobEvent.id > after)
                                .order_by(JobEvent.id.asc())
                                .limit(500)
                            )
                        ).all()
                    for event in backlog:
                        yield _sse(event.id, event.event_type, event.payload)
                async for event in current.events.subscribe():
                    if await request.is_disconnected():
                        break
                    yield _sse(event["id"], event["event"], event["data"])
            except asyncio.CancelledError:
                return

        return StreamingResponse(
            stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    return app


def _sse(event_id: int, event: str, data: dict[str, Any]) -> str:
    return (
        f"id: {event_id}\n"
        f"event: {event}\n"
        f"data: {json.dumps(data, ensure_ascii=False, separators=(',', ':'))}\n\n"
    )


app = create_app()
