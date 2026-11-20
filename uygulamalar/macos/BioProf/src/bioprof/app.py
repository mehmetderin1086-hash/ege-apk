from __future__ import annotations

import logging
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable, Mapping
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, cast

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from sqlalchemy import text
from starlette.middleware.base import BaseHTTPMiddleware

from bioprof import __version__
from bioprof.api.files import create_file_router
from bioprof.api.native import NativeAPIError, create_native_router, create_ui_router
from bioprof.api.openai import ProviderOpenAIService, create_openai_router
from bioprof.application import BioProfApplication
from bioprof.config import Settings, get_settings
from bioprof.db.session import Database
from bioprof.logging import configure_logging, trace_context
from bioprof.providers import create_provider_registry
from bioprof.providers.base import ProviderError, Reranker, Synthesizer, Transcriber
from bioprof.security import JSONBodyLimitMiddleware, LocalAccessMiddleware
from bioprof.services.repositories import Repository
from bioprof.voice.seslab import SesLabAdapter

logger = logging.getLogger(__name__)


class TraceMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        candidate = request.headers.get("x-bioprof-trace-id", "")
        trace_id = candidate if candidate and len(candidate) <= 128 else uuid.uuid4().hex
        token = trace_context.set(trace_id)
        try:
            response = await call_next(request)
            response.headers.setdefault("X-BioProf-Trace-ID", trace_id)
            return response
        finally:
            trace_context.reset(token)


def create_app(
    *,
    settings: Settings | None = None,
    database: Database | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    settings.ensure_directories()
    database = database or Database(settings)
    database.initialize()
    providers = create_provider_registry(settings)
    voice = SesLabAdapter(base_url=settings.seslab_base_url)
    application = BioProfApplication(settings, database, providers, voice)

    async def native_ask(
        notebook_id: str, payload: Mapping[str, Any]
    ) -> Mapping[str, Any]:
        try:
            result = await application.dispatch(
                "ask", notebook_id=notebook_id, payload=dict(payload)
            )
        except NativeAPIError as exc:
            raise ProviderError(exc.message, status_code=exc.status_code) from exc
        return cast(dict[str, Any], result)

    openai_service = ProviderOpenAIService(
        providers,
        default_provider=settings.default_provider,
        transcriber=cast(Transcriber, application),
        synthesizer=cast(Synthesizer, application),
        reranker=cast(
            Reranker,
            providers.get("local_evidence"),
        ),  # deterministic bootstrap reranker
        provider_guard=application.provider_guard,
        allow_remote_egress=settings.allow_openai_compat_remote,
        native_ask=native_ask,
    )

    with database.session() as session:
        repository = Repository(session)
        if not repository.list_notebooks():
            repository.create_notebook(
                "İlk Notebook",
                "Kaynaklarınızı ekleyin ve kanıta dayalı sorular sorun.",
                privacy_mode=settings.privacy_mode,
            )

    @asynccontextmanager
    async def lifespan(_app: FastAPI) -> AsyncIterator[None]:
        interrupted = application.jobs.recover_interrupted()
        if interrupted:
            logger.warning("%d kesilmiş iş güvenli biçimde failed durumuna alındı", interrupted)
        removed = application.cleanup_incoming()
        if removed:
            logger.warning("%d kesilmiş geçici kaynak kopyası temizlendi", removed)
        removed_exports = application.cleanup_exports()
        if removed_exports:
            logger.warning("%d sahipsiz geçici yedek temizlendi", removed_exports)
        orphaned = application.cleanup_orphan_blobs()
        if orphaned:
            logger.warning("%d sahipsiz kaynak blob'u temizlendi", orphaned)
        yield
        await application.close()

    configure_logging(settings.log_level)
    app = FastAPI(
        title="BioProf",
        version=__version__,
        description=(
            "Yerel-öncelikli, kaynak alıntılı biyoloji ve tıp eğitim/araştırma asistanı. "
            "Tanı, tedavi, reçete veya kişiselleştirilmiş doz vermez."
        ),
        lifespan=lifespan,
    )
    app.state.settings = settings
    app.state.database = database
    app.state.native_service = application
    app.state.openai_service = openai_service
    app.state.provider_registry = providers
    app.state.voice_service = voice

    app.add_middleware(TraceMiddleware)
    app.add_middleware(
        JSONBodyLimitMiddleware,
        maximum_bytes=settings.max_json_request_mb * 1024 * 1024,
    )
    app.add_middleware(LocalAccessMiddleware)

    package_dir = Path(__file__).resolve().parent
    static_dir = package_dir / "static"
    templates_dir = package_dir / "templates"
    static_dir.mkdir(exist_ok=True)
    templates_dir.mkdir(exist_ok=True)
    app.mount("/static", StaticFiles(directory=static_dir), name="static")
    templates = Jinja2Templates(directory=templates_dir)

    app.include_router(create_ui_router(templates))
    app.include_router(create_native_router(maximum_upload_mb=settings.max_upload_mb))
    app.include_router(create_file_router())
    app.include_router(create_openai_router())

    @app.get("/favicon.ico", include_in_schema=False)
    async def favicon() -> FileResponse:
        return FileResponse(static_dir / "bioprof-icon-256.png", media_type="image/png")

    @app.get("/healthz", tags=["system"])
    async def health() -> dict[str, object]:
        try:
            with database.engine.connect() as connection:
                connection.execute(text("SELECT 1"))
            database_ok = True
        except Exception:  # noqa: BLE001 - health boundary
            database_ok = False
        # Which embedding is actually running is not cosmetic: a BGE-M3
        # deployment can quietly fall back to the 384-dim hashing stand-in
        # (missing sentence-transformers, or Qdrant failing to start) and the
        # only visible symptom is worse answers. Report it.
        from bioprof.rag.dense import build_embedder

        try:
            embedder = build_embedder(settings)
            embedding = {
                "name": getattr(embedder, "model_name", type(embedder).__name__),
                "dimensions": getattr(embedder, "dimension", None),
                "configured": settings.embedding_model,
            }
            embedding["degraded"] = bool(
                settings.local_embeddings
                and embedding["name"] != settings.embedding_model
            )
        except Exception as exc:  # noqa: BLE001 - health boundary
            embedding = {"error": f"{type(exc).__name__}: {exc}"}
        return {
            "status": "ok" if database_ok else "degraded",
            "version": __version__,
            "database": database_ok,
            "privacy_mode": settings.privacy_mode,
            "embedding": embedding,
        }

    @app.get("/readyz", tags=["system"])
    async def ready() -> JSONResponse:
        value = await health()
        ready_value = bool(value["database"])
        value["ready"] = ready_value
        return JSONResponse(value, status_code=200 if ready_value else 503)

    @app.get("/api/v1/system/status", tags=["system"])
    async def system_status() -> dict[str, object]:
        return {
            "app": await health(),
            "runtime": await application.dispatch("runtime"),
            "providers": await application.dispatch("list_providers"),
        }

    return app
