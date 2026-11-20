"""Düşüm defteri uçları."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Query, Request

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["discards"])


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.post("/discards", status_code=201)
def discard_copy(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    copy_id = payload.get("copy_id")
    if copy_id is None:
        raise ValueError("copy_id gerekli")
    record = state.discards.discard_copy(
        int(copy_id),
        reason=str(payload.get("reason") or ""),
        note=payload.get("note"),
    )
    return record.to_dict()


@router.post("/discards/bulk-from-stocktake")
def bulk_from_stocktake(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    session_id = payload.get("session_id")
    if session_id is None:
        raise ValueError("session_id gerekli")
    return _state(request).discards.bulk_from_stocktake(int(session_id))


@router.post("/discards/{discard_id}/restore")
def restore_discard(request: Request, discard_id: int) -> dict[str, Any]:
    _state(request).discards.restore(discard_id)
    return {"ok": True}


@router.get("/discards")
def list_discards(
    request: Request,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    items, total = _state(request).discards.list_discards(limit=limit, offset=offset)
    return {
        "items": [item.to_dict() for item in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.post("/discards/export", status_code=202)
def export_tutanak(request: Request) -> dict[str, Any]:
    state = _state(request)

    def run(job) -> dict[str, Any]:
        job.message = "Düşüm tutanağı hazırlanıyor…"
        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        destination = state.paths.exports / f"dusum-tutanagi-{stamp}.xlsx"
        state.paths.exports.mkdir(parents=True, exist_ok=True)
        state.discards.export_tutanak_xlsx(destination)
        return {"download": destination.name}

    job = state.registry.start("export", "Düşüm tutanağı (xlsx)", run)
    return job.to_dict()
