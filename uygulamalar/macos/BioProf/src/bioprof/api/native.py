"""Typed native BioProf API with an injectable application facade.

The router knows HTTP, validation and streaming, but deliberately knows
nothing about SQLAlchemy, vector stores or provider implementations.  The app
factory injects one ``NativeServiceFacade`` and can therefore use the same
contract in tests, CLI embedding and the desktop runtime.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator, Awaitable, Callable, Mapping
from pathlib import Path
from typing import Any, Literal, Protocol, runtime_checkable

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response, StreamingResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from starlette.background import BackgroundTask


class NativeAPIError(RuntimeError):
    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


@runtime_checkable
class NativeServiceFacade(Protocol):
    async def dispatch(self, operation: str, **kwargs: Any) -> Any: ...

    def events(self, job_id: str) -> AsyncIterator[Mapping[str, Any]]: ...

    def ask_stream(
        self, notebook_id: str, payload: dict[str, Any]
    ) -> AsyncIterator[Mapping[str, Any]]: ...


FacadeGetter = Callable[[], NativeServiceFacade | Awaitable[NativeServiceFacade]]


class _StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class NotebookCreate(_StrictModel):
    name: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=10_000)
    privacy_mode: Literal["local_only", "local_first", "cloud_allowed"] = "local_first"
    remote_egress_approved: bool = False


class NotebookUpdate(_StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=10_000)
    privacy_mode: Literal["local_only", "local_first", "cloud_allowed"] | None = None
    remote_egress_approved: bool | None = None


class SourceReference(_StrictModel):
    url: str = Field(min_length=8, max_length=4_000)
    title: str | None = Field(default=None, max_length=500)
    license: str | None = Field(default=None, max_length=500)


class SearchRequest(_StrictModel):
    query: str = Field(min_length=1, max_length=8_000)
    source_ids: list[str] | None = Field(default=None, max_length=1_000)
    limit: int = Field(default=20, ge=1, le=100)
    filters: dict[str, Any] = Field(default_factory=dict)
    include_trace: bool = True


class AskRequest(_StrictModel):
    question: str = Field(min_length=1, max_length=50_000)
    mode: Literal["strict", "hybrid", "research", "raw"] = "strict"
    source_ids: list[str] | None = Field(default=None, max_length=1_000)
    conversation_id: str | None = Field(default=None, min_length=1, max_length=64)
    provider: str | None = Field(default=None, max_length=100)
    model: str | None = Field(default=None, max_length=300)
    speak: bool = False
    strict_voice_verification: bool = False


class ResearchRequest(_StrictModel):
    notebook_id: str
    query: str = Field(min_length=1, max_length=2_000)
    provider: Literal[
        "pubmed", "pmc", "gene", "protein", "taxonomy", "clinvar", "clinical_trials"
    ] = "pubmed"
    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = Field(default=None, max_length=4_000)
    import_record_ids: list[str] = Field(default_factory=list, max_length=100)


class NoteRequest(_StrictModel):
    title: str = Field(default="", max_length=300)
    content: str = Field(default="", max_length=100_000)
    pinned: bool = False


class NoteUpdateRequest(_StrictModel):
    title: str | None = Field(default=None, max_length=300)
    content: str | None = Field(default=None, max_length=100_000)
    pinned: bool | None = None


class PaketRequest(_StrictModel):
    artifact_ids: list[str] = Field(min_length=1, max_length=100)


class FlashcardDeckRequest(_StrictModel):
    artifact_id: str
    title: str | None = Field(default=None, max_length=300)


class FlashcardReviewRequest(_StrictModel):
    # SM-2 notu: 0-5; arayüz üç düğmesi 2/3/5'e eşlenir.
    grade: int = Field(ge=0, le=5)


class StudioRequest(_StrictModel):
    notebook_id: str
    kind: Literal[
        "summary",
        "faq",
        "glossary",
        "timeline",
        "study_guide",
        "quiz",
        "flashcards",
        "mind_map",
        "ders_plani",
        "table",
        "slides",
        "infographic",
        "audio_lesson",
        "audio_lecture",
        "video_overview",
        "podcast",
    ]
    title: str = Field(min_length=1, max_length=300)
    source_ids: list[str] | None = Field(default=None, max_length=1_000)
    instructions: str = Field(default="", max_length=10_000)
    # Yalnız podcast için: yaklaşık replik sayısını belirler.
    length: Literal["kisa", "orta", "uzun"] = "orta"
    # Hedef süre (dakika). Verilirse length yerine bu kullanılır; uzun
    # bölümler anahat çıkarılıp bölüm bölüm üretilir.
    target_minutes: float | None = Field(default=None, ge=1, le=120)
    # Bölümün dokusu: sohbet, ders, tartisma, tekrar, roportaj.
    style: Literal["sohbet", "ders", "tartisma", "tekrar", "roportaj"] = "sohbet"
    # Bu üretim için getirilecek kanıt bloğu sayısı. Uzun bir podcast dar bir
    # kanıt havuzuyla kısa kalır (replikler kapıdan geçemez), ama havuzu kalıcı
    # olarak genişletmek her işi yavaşlatır; bu yüzden istek başına verilir.
    max_evidence: int | None = Field(default=None, ge=1, le=50)
    # Yalnız ders_plani için: sınıf, ders süresi ve elle kazanım seçimi.
    sinif: int | None = Field(default=None, ge=9, le=12)
    sure_dakika: int | None = Field(default=None, ge=10, le=120)
    kazanim_kodlari: list[str] | None = Field(default=None, max_length=12)
    output_format: (
        Literal[
            "markdown", "json", "csv", "xlsx", "docx", "pdf", "pptx", "wav", "mp3", "mp4", "podcast"
        ]
        | None
    ) = None


class ProviderTestRequest(_StrictModel):
    provider: str | None = Field(default=None, max_length=100)
    active: bool = False


class ModelRequest(_StrictModel):
    model: str = Field(min_length=1, max_length=500)


class DatasetCreate(_StrictModel):
    notebook_id: str
    name: str = Field(min_length=1, max_length=300)
    seed: int = 42
    train_ratio: float = Field(default=0.8, ge=0, le=1)
    validation_ratio: float = Field(default=0.1, ge=0, le=1)
    test_ratio: float = Field(default=0.1, ge=0, le=1)


class TrainingRunCreate(_StrictModel):
    dataset_id: str
    name: str = Field(min_length=1, max_length=300)
    base_model: str = Field(min_length=1, max_length=500)
    method: Literal["qlora_sft", "lora_sft", "dpo"] = "qlora_sft"
    parameters: dict[str, Any] = Field(default_factory=dict)


class EvalRunCreate(_StrictModel):
    model_id: str
    suite: str = Field(default="gold", min_length=1, max_length=100)


class ToolRunRequest(_StrictModel):
    name: str = Field(min_length=1, max_length=100)
    arguments: dict[str, Any] = Field(default_factory=dict)


def _detail(code: str, message: str, *, trace_id: str | None = None) -> dict[str, Any]:
    value: dict[str, Any] = {"error": {"code": code, "message": message}}
    if trace_id:
        value["error"]["trace_id"] = trace_id
    return value


async def _call(facade: NativeServiceFacade, operation: str, **kwargs: Any) -> Any:
    try:
        return await facade.dispatch(operation, **kwargs)
    except NativeAPIError as exc:
        raise HTTPException(
            status_code=exc.status_code,
            detail={"code": exc.code, "message": exc.message},
        ) from exc


def _json(
    value: Any,
    *,
    status_code: int = 200,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    return JSONResponse(jsonable_encoder(value), status_code=status_code, headers=headers)


async def _bounded_upload(upload: Any, *, maximum_bytes: int) -> bytes:
    output = bytearray()
    while True:
        chunk = await upload.read(min(1024 * 1024, maximum_bytes + 1 - len(output)))
        if not chunk:
            return bytes(output)
        output.extend(chunk)
        if len(output) > maximum_bytes:
            raise NativeAPIError(
                status.HTTP_413_CONTENT_TOO_LARGE,
                "upload_too_large",
                f"Dosya sınırı {maximum_bytes // (1024 * 1024)} MiB",
            )


def create_native_router(
    get_facade: FacadeGetter | None = None,
    *,
    maximum_upload_mb: int = 250,
) -> APIRouter:
    router = APIRouter(prefix="/api/v1", tags=["BioProf native"])

    async def from_app_state(request: Request) -> NativeServiceFacade:
        try:
            return request.app.state.native_service
        except AttributeError as exc:
            raise RuntimeError("app.state.native_service is not configured") from exc

    dependency: Callable[..., Any] = get_facade or from_app_state

    @router.get("/notebooks")
    async def list_notebooks(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_notebooks"))

    @router.post("/notebooks", status_code=status.HTTP_201_CREATED)
    async def create_notebook(
        payload: NotebookCreate, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        value = await _call(facade, "create_notebook", payload=payload.model_dump())
        return _json(value, status_code=status.HTTP_201_CREATED)

    @router.get("/notebooks/{notebook_id}")
    async def get_notebook(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "get_notebook", notebook_id=notebook_id))

    @router.patch("/notebooks/{notebook_id}")
    async def update_notebook(
        notebook_id: str,
        payload: NotebookUpdate,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(
            await _call(
                facade,
                "update_notebook",
                notebook_id=notebook_id,
                payload=payload.model_dump(exclude_unset=True),
            )
        )

    @router.delete("/notebooks/{notebook_id}", status_code=status.HTTP_204_NO_CONTENT)
    async def delete_notebook(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        await _call(facade, "delete_notebook", notebook_id=notebook_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.get("/notebooks/{notebook_id}/sources")
    async def list_sources(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "list_sources", notebook_id=notebook_id))

    @router.post("/notebooks/{notebook_id}/sources", status_code=status.HTTP_202_ACCEPTED)
    async def add_source(
        notebook_id: str,
        request: Request,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        content_type = request.headers.get("content-type", "").casefold()
        if "multipart/form-data" in content_type:
            form = await request.form()
            upload = form.get("file")
            if upload is None or not hasattr(upload, "read"):
                raise HTTPException(
                    status_code=422,
                    detail={"code": "file_required", "message": "Multipart 'file' alanı gerekli"},
                )
            try:
                content = await _bounded_upload(
                    upload, maximum_bytes=maximum_upload_mb * 1024 * 1024
                )
            except NativeAPIError as exc:
                raise HTTPException(
                    status_code=exc.status_code,
                    detail={"code": exc.code, "message": exc.message},
                ) from exc
            if not content:
                raise HTTPException(
                    status_code=422,
                    detail={"code": "empty_file", "message": "Boş dosya yüklenemez"},
                )
            value = await _call(
                facade,
                "add_source",
                notebook_id=notebook_id,
                upload={
                    "filename": getattr(upload, "filename", None) or "upload.bin",
                    "content_type": getattr(upload, "content_type", None),
                    "content": content,
                    "title": form.get("title"),
                    "license": form.get("license"),
                },
            )
        elif "application/json" in content_type:
            try:
                payload = SourceReference.model_validate(await request.json())
            except (ValidationError, json.JSONDecodeError) as exc:
                raise HTTPException(status_code=422, detail=str(exc)) from exc
            value = await _call(
                facade,
                "add_source",
                notebook_id=notebook_id,
                reference=payload.model_dump(),
            )
        else:
            raise HTTPException(
                status_code=415,
                detail={
                    "code": "unsupported_media_type",
                    "message": "multipart/form-data veya application/json gerekli",
                },
            )
        return _json(value, status_code=status.HTTP_202_ACCEPTED)

    @router.delete("/sources/{source_id}", status_code=status.HTTP_204_NO_CONTENT)
    async def delete_source(
        source_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        await _call(facade, "delete_source", source_id=source_id)
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    @router.post("/notebooks/{notebook_id}/search")
    async def search_notebook(
        notebook_id: str,
        payload: SearchRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(
            await _call(facade, "search", notebook_id=notebook_id, payload=payload.model_dump())
        )

    @router.post("/notebooks/{notebook_id}/ask")
    async def ask(
        notebook_id: str,
        payload: AskRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        value = await _call(facade, "ask", notebook_id=notebook_id, payload=payload.model_dump())
        trace_id = value.get("trace_id") if isinstance(value, Mapping) else None
        headers = {"X-BioProf-Trace-ID": str(trace_id)} if trace_id else None
        return _json(value, headers=headers)

    @router.post("/notebooks/{notebook_id}/ask/stream")
    async def ask_stream(
        notebook_id: str,
        payload: AskRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> StreamingResponse:
        async def stream() -> AsyncIterator[bytes]:
            yield b"retry: 1500\n\n"
            try:
                events = facade.ask_stream(notebook_id, payload.model_dump())
                async for event in events:
                    name = str(event.get("event") or "message")
                    body = json.dumps(jsonable_encoder(event), ensure_ascii=False)
                    yield f"event: {name}\ndata: {body}\n\n".encode()
            except NativeAPIError as exc:
                detail = json.dumps(
                    {"code": exc.code, "message": exc.message}, ensure_ascii=False
                )
                yield f"event: error\ndata: {detail}\n\n".encode()
            except Exception as exc:  # akış başladıktan sonra HTTP kodu değişemez
                detail = json.dumps(
                    {"code": "stream_failed", "message": str(exc)}, ensure_ascii=False
                )
                yield f"event: error\ndata: {detail}\n\n".encode()

        return StreamingResponse(
            stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    @router.post("/research", status_code=status.HTTP_202_ACCEPTED)
    async def research(
        payload: ResearchRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "research", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/studio", status_code=status.HTTP_202_ACCEPTED)
    async def studio(
        payload: StudioRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "studio", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/notebooks/{notebook_id}/notes")
    async def list_notes(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "list_notes", notebook_id=notebook_id))

    @router.post("/notebooks/{notebook_id}/notes", status_code=status.HTTP_201_CREATED)
    async def create_note(
        notebook_id: str,
        payload: NoteRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        return _json(
            await _call(
                facade,
                "create_note",
                payload={"notebook_id": notebook_id, **payload.model_dump()},
            )
        )

    @router.patch("/notes/{note_id}")
    async def update_note(
        note_id: str,
        payload: NoteUpdateRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        return _json(
            await _call(
                facade,
                "update_note",
                note_id=note_id,
                payload=payload.model_dump(exclude_unset=True),
            )
        )

    @router.delete("/notes/{note_id}")
    async def delete_note(
        note_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "delete_note", note_id=note_id))

    @router.get("/notebooks/{notebook_id}/conversations")
    async def list_conversations(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "list_conversations", notebook_id=notebook_id))

    @router.get("/conversations/{conversation_id}/messages")
    async def list_conversation_messages(
        conversation_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(
            await _call(
                facade, "list_conversation_messages", conversation_id=conversation_id
            )
        )

    @router.delete("/conversations/{conversation_id}")
    async def delete_conversation(
        conversation_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(
            await _call(facade, "delete_conversation", conversation_id=conversation_id)
        )

    @router.post("/notebooks/{notebook_id}/paket")
    async def export_paket(
        notebook_id: str,
        payload: PaketRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> FileResponse:
        sonuc = await _call(
            facade,
            "export_paket",
            payload={"notebook_id": notebook_id, "artifact_ids": payload.artifact_ids},
        )
        return FileResponse(
            sonuc["path"],
            media_type="application/zip",
            filename=sonuc["filename"],
        )

    @router.post("/notebooks/{notebook_id}/flashcard-decks", status_code=status.HTTP_201_CREATED)
    async def create_flashcard_deck(
        notebook_id: str,
        payload: FlashcardDeckRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        return _json(
            await _call(
                facade,
                "create_flashcard_deck",
                payload={"notebook_id": notebook_id, **payload.model_dump()},
            )
        )

    @router.get("/notebooks/{notebook_id}/flashcard-decks")
    async def list_flashcard_decks(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "list_flashcard_decks", notebook_id=notebook_id))

    @router.get("/flashcard-decks/{deck_id}/due")
    async def due_flashcards(
        deck_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "due_flashcards", deck_id=deck_id))

    @router.post("/flashcards/{card_id}/review")
    async def review_flashcard(
        card_id: str,
        payload: FlashcardReviewRequest,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        return _json(
            await _call(facade, "review_flashcard", card_id=card_id, grade=payload.grade)
        )

    @router.delete("/flashcard-decks/{deck_id}")
    async def delete_flashcard_deck(
        deck_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "delete_flashcard_deck", deck_id=deck_id))

    @router.get("/flashcard-decks/{deck_id}/export")
    async def export_flashcards(
        deck_id: str,
        format: Literal["csv", "apkg"] = "csv",
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        import base64

        sonuc = await _call(facade, "export_flashcards", deck_id=deck_id, format=format)
        return Response(
            content=base64.b64decode(sonuc["data_base64"]),
            media_type=sonuc["media_type"],
            headers={
                "Content-Disposition": f'attachment; filename="{sonuc["filename"]}"'
            },
        )

    @router.get("/artifacts/{artifact_id}")
    async def get_artifact(
        artifact_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "get_artifact", artifact_id=artifact_id))

    @router.delete("/artifacts/{artifact_id}")
    async def delete_artifact(
        artifact_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> Response:
        return _json(await _call(facade, "delete_artifact", artifact_id=artifact_id))

    @router.get("/notebooks/{notebook_id}/artifacts")
    async def list_artifacts(
        notebook_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "list_artifacts", notebook_id=notebook_id))

    @router.get("/jobs/{job_id}")
    async def get_job(
        job_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "get_job", job_id=job_id))

    @router.delete("/jobs/{job_id}", status_code=status.HTTP_202_ACCEPTED)
    async def cancel_job(
        job_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "cancel_job", job_id=job_id),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/jobs/{job_id}/events")
    async def job_events(
        job_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> StreamingResponse:
        async def stream() -> AsyncIterator[bytes]:
            try:
                events = facade.events(job_id)
            except (AttributeError, NotImplementedError):
                events = _poll_job(facade, job_id)
            yield b"retry: 1500\n\n"
            async for event in events:
                event_name = str(event.get("status") or event.get("event") or "message")
                payload = json.dumps(jsonable_encoder(event), ensure_ascii=False)
                yield f"event: {event_name}\ndata: {payload}\n\n".encode()

        return StreamingResponse(
            stream(),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    @router.get("/citations/{citation_id}")
    async def resolve_citation(
        citation_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "resolve_citation", citation_id=citation_id))

    @router.get("/providers")
    async def list_providers(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_providers"))

    @router.post("/providers/test")
    async def test_providers(
        payload: ProviderTestRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "test_providers", payload=payload.model_dump()))

    @router.get("/models")
    async def list_models(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_models"))

    @router.post("/models/pull", status_code=status.HTTP_202_ACCEPTED)
    async def pull_model(
        payload: ModelRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "pull_model", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/models/benchmark", status_code=status.HTTP_202_ACCEPTED)
    async def benchmark_model(
        payload: ModelRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "benchmark_model", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/models/{model_id}/rollback", status_code=status.HTTP_202_ACCEPTED)
    async def rollback_model(
        model_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "rollback_model", model_id=model_id),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/datasets")
    async def list_datasets(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_datasets"))

    @router.post("/datasets", status_code=status.HTTP_202_ACCEPTED)
    async def create_dataset(
        payload: DatasetCreate, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "create_dataset", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/datasets/{dataset_id}/validate", status_code=status.HTTP_202_ACCEPTED)
    async def validate_dataset(
        dataset_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "validate_dataset", dataset_id=dataset_id),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/training-runs")
    async def list_training_runs(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_training_runs"))

    @router.post("/training-runs", status_code=status.HTTP_202_ACCEPTED)
    async def create_training_run(
        payload: TrainingRunCreate,
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(
            await _call(facade, "create_training_run", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/training-runs/{run_id}/export-colab", status_code=status.HTTP_202_ACCEPTED)
    async def export_colab(
        run_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "export_colab", run_id=run_id),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.post("/training-runs/import", status_code=status.HTTP_201_CREATED)
    async def import_training_run(
        request: Request, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        form = await request.form()
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            raise HTTPException(status_code=422, detail="Manifest file is required")
        content = await _bounded_upload(upload, maximum_bytes=10 * 1024 * 1024)
        return _json(
            await _call(
                facade,
                "import_training_run",
                filename=getattr(upload, "filename", None) or "manifest.json",
                content=content,
            ),
            status_code=status.HTTP_201_CREATED,
        )

    @router.post("/training-runs/{run_id}/promote", status_code=status.HTTP_202_ACCEPTED)
    async def promote_training_run(
        run_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "promote_training_run", run_id=run_id),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/eval-runs")
    async def list_eval_runs(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_eval_runs"))

    @router.post("/eval-runs", status_code=status.HTTP_202_ACCEPTED)
    async def create_eval_run(
        payload: EvalRunCreate, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(
            await _call(facade, "create_eval_run", payload=payload.model_dump()),
            status_code=status.HTTP_202_ACCEPTED,
        )

    @router.get("/eval-runs/{run_id}")
    async def get_eval_run(
        run_id: str, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "get_eval_run", run_id=run_id))

    @router.get("/tools")
    async def list_tools(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> JSONResponse:
        return _json(await _call(facade, "list_tools"))

    @router.post("/tools/run")
    async def run_tool(
        payload: ToolRunRequest, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        return _json(await _call(facade, "run_tool", payload=payload.model_dump()))

    @router.post("/backup")
    async def backup(
        facade: NativeServiceFacade = Depends(dependency),
    ) -> Response:
        value = await _call(facade, "backup")
        if not isinstance(value, tuple) or len(value) not in {2, 3}:
            return _json(value)
        content, media_type, *filename = value
        download_name = filename[0] if filename else "bioprof-backup.zip"
        headers = {"Content-Disposition": f'attachment; filename="{download_name}"'}
        if isinstance(content, Path):
            return FileResponse(
                content,
                media_type=media_type,
                filename=download_name,
                headers={"Cache-Control": "no-store"},
                background=BackgroundTask(content.unlink, missing_ok=True),
            )
        return Response(content=content, media_type=media_type, headers=headers)

    @router.post("/restore", status_code=status.HTTP_202_ACCEPTED)
    async def restore(
        request: Request, facade: NativeServiceFacade = Depends(dependency)
    ) -> JSONResponse:
        form = await request.form()
        upload = form.get("file")
        if upload is None or not hasattr(upload, "read"):
            raise HTTPException(status_code=422, detail="Backup file is required")
        content = await _bounded_upload(upload, maximum_bytes=maximum_upload_mb * 1024 * 1024)
        return _json(
            await _call(
                facade,
                "restore",
                filename=getattr(upload, "filename", None) or "backup.zip",
                content=content,
            ),
            status_code=status.HTTP_202_ACCEPTED,
        )

    return router


async def _poll_job(facade: NativeServiceFacade, job_id: str) -> AsyncIterator[Mapping[str, Any]]:
    previous: str | None = None
    for _ in range(1_200):
        value = await _call(facade, "get_job", job_id=job_id)
        encoded = json.dumps(jsonable_encoder(value), sort_keys=True)
        if encoded != previous:
            previous = encoded
            yield value
        if isinstance(value, Mapping) and value.get("status") in {
            "completed",
            "failed",
            "cancelled",
        }:
            return
        await asyncio.sleep(1.0)


def create_ui_router(templates: Jinja2Templates) -> APIRouter:
    router = APIRouter(include_in_schema=False)

    @router.get("/", response_class=HTMLResponse)
    async def index(request: Request) -> Response:
        return templates.TemplateResponse(
            request=request,
            name="index.html",
            context={
                "app_name": "BioProf",
                "api_prefix": "/api/v1",
                "educational_notice": (
                    "Eğitim ve araştırma içindir; tanı, tedavi, reçete veya "
                    "kişiselleştirilmiş doz vermez."
                ),
            },
        )

    return router
