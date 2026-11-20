from __future__ import annotations

from pathlib import Path
from typing import Any, Literal

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from bioprof.db.models import ArtifactRecord, SourceRecord
from bioprof.services.repositories import Repository
from bioprof.training.dataset import TrainingExample


class CandidateReview(BaseModel):
    model_config = ConfigDict(extra="forbid")

    review_status: Literal["pending", "approved", "rejected"]
    rights_approved: bool = False
    reviewed_by: str | None = Field(default=None, max_length=200)
    license: str | None = Field(default=None, max_length=500)
    instruction: str | None = Field(default=None, min_length=3, max_length=50_000)
    response: str | None = Field(default=None, min_length=1, max_length=200_000)
    rejected_response: str | None = Field(default=None, max_length=200_000)


class ModelStartRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    profile: Literal["fast", "balanced", "biomedical"]
    model_path: str | None = None
    engine: Literal["mlx-lm", "mlx-vlm", "llama.cpp", "external"] | None = None
    context_size: int = Field(default=8192, ge=512, le=262_144)


def _safe_file(settings: Any, value: str) -> Path:
    path = Path(value).expanduser().resolve()
    data_root = settings.data_dir.resolve()
    if not path.is_relative_to(data_root) or not path.is_file():
        raise HTTPException(status_code=404, detail="Dosya bulunamadı")
    return path


def create_file_router() -> APIRouter:
    router = APIRouter(prefix="/api/v1", tags=["BioProf local files"])

    @router.get("/sources/{source_id}/content")
    async def source_content(source_id: str, request: Request) -> FileResponse:
        database = request.app.state.database
        with database.session() as session:
            source = session.get(SourceRecord, source_id)
            if source is None:
                raise HTTPException(status_code=404, detail="Kaynak bulunamadı")
            if source.status in {"quarantined", "needs_review", "failed"}:
                raise HTTPException(status_code=403, detail="Karantinadaki kaynak açılamaz")
            path = _safe_file(request.app.state.settings, source.object_path)
            return FileResponse(
                path,
                media_type=source.mime_type,
                filename=Path(source.original_name).name,
                headers={"Cache-Control": "private, no-store"},
            )

    @router.get("/sources/{source_id}/chunks")
    async def source_chunks(source_id: str, request: Request) -> JSONResponse:
        database = request.app.state.database
        with database.session() as session:
            repository = Repository(session)
            source = repository.get_source(source_id)
            if source is None:
                raise HTTPException(status_code=404, detail="Kaynak bulunamadı")
            chunks = [
                {
                    "id": item.id,
                    "ordinal": item.ordinal,
                    "text": item.text,
                    "section": item.section,
                    "page": item.page,
                    "slide": item.slide,
                    "timestamp_start": item.timestamp_start,
                    "timestamp_end": item.timestamp_end,
                    "sequence_start": item.sequence_start,
                    "sequence_end": item.sequence_end,
                }
                for item in repository.list_chunks(source_id)
            ]
            return JSONResponse({"source_id": source_id, "chunks": chunks})

    @router.get("/artifacts/{artifact_id}/content")
    async def artifact_content(artifact_id: str, request: Request) -> FileResponse:
        database = request.app.state.database
        with database.session() as session:
            artifact = session.get(ArtifactRecord, artifact_id)
            if artifact is None:
                raise HTTPException(status_code=404, detail="Çıktı bulunamadı")
            path = _safe_file(request.app.state.settings, artifact.path)
            return FileResponse(
                path,
                media_type=artifact.mime_type,
                filename=path.name,
                headers={"Cache-Control": "private, no-store"},
            )

    @router.get("/datasets/{dataset_id}/candidates")
    async def dataset_candidates(dataset_id: str, request: Request) -> JSONResponse:
        application = request.app.state.native_service
        path = application.datasets_dir / dataset_id / "candidates.jsonl"
        if not path.is_file() or not path.resolve().is_relative_to(
            application.datasets_dir.resolve()
        ):
            raise HTTPException(status_code=404, detail="Dataset bulunamadı")
        records = [
            TrainingExample.model_validate_json(line).model_dump(mode="json")
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        return JSONResponse({"dataset_id": dataset_id, "candidates": records})

    @router.patch("/datasets/{dataset_id}/candidates/{example_id}")
    async def review_candidate(
        dataset_id: str,
        example_id: str,
        payload: CandidateReview,
        request: Request,
    ) -> JSONResponse:
        value = await request.app.state.native_service.dispatch(
            "review_dataset_candidate",
            dataset_id=dataset_id,
            example_id=example_id,
            payload=payload.model_dump(),
        )
        return JSONResponse(value)

    @router.post("/models/start")
    async def start_model(payload: ModelStartRequest, request: Request) -> JSONResponse:
        value = await request.app.state.native_service.dispatch(
            "start_model", payload=payload.model_dump()
        )
        return JSONResponse(value)

    @router.post("/models/stop")
    async def stop_model(request: Request) -> JSONResponse:
        value = await request.app.state.native_service.dispatch("stop_model")
        return JSONResponse(value)

    @router.get("/runtime")
    async def runtime(request: Request) -> JSONResponse:
        value = await request.app.state.native_service.dispatch("runtime")
        return JSONResponse(value)

    @router.get("/license-inventory")
    async def license_inventory(request: Request) -> JSONResponse:
        inventory_path = Path(__file__).resolve().parents[3] / "THIRD_PARTY.md"
        text = inventory_path.read_text(encoding="utf-8") if inventory_path.exists() else ""
        return JSONResponse({"format": "markdown", "content": text})

    return router
