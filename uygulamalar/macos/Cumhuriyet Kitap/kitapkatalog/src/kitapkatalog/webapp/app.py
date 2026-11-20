"""FastAPI uygulama fabrikası.

Sunucu tek süreç + tek uvicorn worker olarak tasarlandı; ağır işler
JobRegistry thread'lerinde koşar, SQLite erişimi işlem başına bağlantıyla
zaten thread güvenlidir.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from kitapkatalog import __version__
from kitapkatalog.application import ApplicationContext, open_application
from kitapkatalog.capacity import CapacityError
from kitapkatalog.database import DatabaseError, StateConflictError
from kitapkatalog.model_manager import ModelBundleError
from kitapkatalog.webapp.jobs import JobRegistry, JobSlotBusyError
from kitapkatalog.webapp.security import LocalAuthMiddleware, new_token
from kitapkatalog.webapp.state import WebState

STATIC_DIR = Path(__file__).parent / "static"


def create_app(
    context: ApplicationContext | None = None,
    *,
    token: str | None = None,
) -> FastAPI:
    state = WebState(
        ctx=context or open_application(),
        registry=JobRegistry(),
        token=token or new_token(),
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        try:
            yield
        finally:
            state.close()

    app = FastAPI(title="Cumhuriyet Kitap", version=__version__, lifespan=lifespan)
    app.state.web = state
    app.add_middleware(LocalAuthMiddleware, token=state.token)

    @app.exception_handler(JobSlotBusyError)
    async def _busy(request: Request, exc: JobSlotBusyError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=409)

    @app.exception_handler(StateConflictError)
    async def _conflict(request: Request, exc: StateConflictError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=409)

    @app.exception_handler(CapacityError)
    async def _capacity(request: Request, exc: CapacityError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=507)

    @app.exception_handler(ModelBundleError)
    async def _models(request: Request, exc: ModelBundleError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=503)

    @app.exception_handler(DatabaseError)
    async def _database(request: Request, exc: DatabaseError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=409)

    @app.exception_handler(KeyError)
    async def _missing(request: Request, exc: KeyError) -> JSONResponse:
        return JSONResponse({"detail": str(exc.args[0]) if exc.args else "Bulunamadı"}, status_code=404)

    @app.exception_handler(ValueError)
    async def _invalid(request: Request, exc: ValueError) -> JSONResponse:
        return JSONResponse({"detail": str(exc)}, status_code=400)

    @app.get("/health")
    async def health() -> dict:
        row = state.database.fetchone("PRAGMA user_version")
        schema_version = int(row[0]) if row is not None else 0
        return {
            "app": "kitapkatalog",
            "version": __version__,
            "schema_version": schema_version,
            "nonce": state.nonce,
            "instance_id": state.instance_id,
        }

    @app.get("/")
    async def index() -> FileResponse:
        return FileResponse(STATIC_DIR / "index.html")

    @app.get("/opac")
    async def opac_page() -> FileResponse:
        return FileResponse(STATIC_DIR / "opac.html")

    from kitapkatalog.webapp.routes_books import router as books_router
    from kitapkatalog.webapp.routes_challenges import router as challenges_router
    from kitapkatalog.webapp.routes_discards import router as discards_router
    from kitapkatalog.webapp.routes_holds import router as holds_router
    from kitapkatalog.webapp.routes_imports import router as imports_router
    from kitapkatalog.webapp.routes_lists import router as lists_router
    from kitapkatalog.webapp.routes_loans import router as loans_router
    from kitapkatalog.webapp.routes_members import router as members_router
    from kitapkatalog.webapp.routes_notifications import router as notifications_router
    from kitapkatalog.webapp.routes_opac import router as opac_router
    from kitapkatalog.webapp.routes_print import router as print_router
    from kitapkatalog.webapp.routes_reports import router as reports_router
    from kitapkatalog.webapp.routes_review import router as review_router
    from kitapkatalog.webapp.routes_settings import router as settings_router
    from kitapkatalog.webapp.routes_shelves import router as shelves_router
    from kitapkatalog.webapp.routes_stocktake import router as stocktake_router
    from kitapkatalog.webapp.routes_system import router as system_router
    from kitapkatalog.webapp.routes_voice import router as voice_router

    app.include_router(books_router, prefix="/api")
    app.include_router(imports_router, prefix="/api")
    app.include_router(voice_router, prefix="/api")
    app.include_router(review_router, prefix="/api")
    app.include_router(system_router, prefix="/api")
    app.include_router(members_router, prefix="/api")
    app.include_router(settings_router, prefix="/api")
    app.include_router(loans_router, prefix="/api")
    app.include_router(holds_router, prefix="/api")
    app.include_router(notifications_router, prefix="/api")
    app.include_router(shelves_router, prefix="/api")
    app.include_router(stocktake_router, prefix="/api")
    app.include_router(discards_router, prefix="/api")
    app.include_router(reports_router, prefix="/api")
    app.include_router(opac_router, prefix="/api")
    app.include_router(lists_router, prefix="/api")
    app.include_router(challenges_router, prefix="/api")
    # Öneksiz: /print/* HTML sayfaları (oturum zorunlu, security.py muafiyetinde değil).
    app.include_router(print_router)

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    return app


def get_web_state(request: Request) -> WebState:
    return request.app.state.web
