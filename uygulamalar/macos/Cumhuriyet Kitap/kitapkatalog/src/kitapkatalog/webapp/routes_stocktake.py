"""Sayım oturumu uçları."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["stocktake"])


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.post("/stocktake/sessions", status_code=201)
def open_session(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    session = state.stocktake.open_session(
        str(payload.get("name") or ""),
        scope_location=payload.get("scope_location"),
    )
    return session.to_dict()


@router.get("/stocktake/sessions")
def list_sessions(request: Request) -> list[dict[str, Any]]:
    return [session.to_dict() for session in _state(request).stocktake.list_sessions()]


@router.get("/stocktake/sessions/{session_id}")
def session_detail(request: Request, session_id: int) -> dict[str, Any]:
    state = _state(request)
    session = state.stocktake.get_session(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Sayım oturumu bulunamadı")
    data = session.to_dict()
    data["progress"] = state.stocktake.progress(session_id)
    data["recent"] = state.stocktake.recent_scans(session_id)
    return data


@router.post("/stocktake/sessions/{session_id}/scans")
def record_scan(request: Request, session_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    result = state.stocktake.record_scan(
        session_id,
        str(payload.get("code") or ""),
        manual_edition_id=payload.get("manual_edition_id"),
    )
    result["progress"] = state.stocktake.progress(session_id)
    return result


@router.delete("/stocktake/scans/{scan_id}")
def undo_scan(request: Request, scan_id: int) -> dict[str, Any]:
    if not _state(request).stocktake.undo_scan(scan_id):
        raise HTTPException(status_code=404, detail="Okutma kaydı bulunamadı")
    return {"ok": True}


@router.post("/stocktake/sessions/{session_id}/close")
def close_session(request: Request, session_id: int) -> dict[str, Any]:
    return _state(request).stocktake.close_session(session_id).to_dict()


@router.get("/stocktake/sessions/{session_id}/report")
def session_report(request: Request, session_id: int) -> dict[str, Any]:
    return _state(request).stocktake.report(session_id)


@router.post("/stocktake/sessions/{session_id}/export", status_code=202)
def export_report(request: Request, session_id: int) -> dict[str, Any]:
    state = _state(request)
    if state.stocktake.get_session(session_id) is None:
        raise HTTPException(status_code=404, detail="Sayım oturumu bulunamadı")

    def run(job) -> dict[str, Any]:
        job.message = "Sayım raporu hazırlanıyor…"
        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        destination = state.paths.exports / f"sayim-{session_id}-{stamp}.xlsx"
        state.paths.exports.mkdir(parents=True, exist_ok=True)
        state.stocktake.export_report_xlsx(session_id, destination)
        return {"download": destination.name}

    job = state.registry.start("export", "Sayım raporu (xlsx)", run)
    return job.to_dict()
