"""Rezervasyon (hold) uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["holds"])


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CreateHoldPayload(_StrictPayload):
    member_id: int = Field(gt=0)
    edition_id: int = Field(gt=0)
    request_id: str | None = Field(default=None, min_length=8, max_length=200)


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.post("/holds", status_code=201)
def create_hold(request: Request, payload: CreateHoldPayload) -> dict[str, Any]:
    state = _state(request)
    if not state.settings.hold_enabled:
        raise HTTPException(status_code=403, detail="Rezervasyon özelliği kapalı")
    hold = state.loans.create_hold(
        edition_id=payload.edition_id,
        member_id=payload.member_id,
        request_id=payload.request_id,
    )
    return hold.to_dict()


@router.get("/holds")
def list_holds(
    request: Request,
    member_id: int | None = None,
    edition_id: int | None = None,
    status: str | None = Query(
        default=None, pattern="^(active|ready|fulfilled|cancelled|expired)$"
    ),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    items = _state(request).loans.list_holds(
        member_id=member_id,
        edition_id=edition_id,
        status=status,
        limit=limit,
        offset=offset,
    )
    return {"items": [item.to_dict() for item in items]}


@router.post("/holds/{hold_id}/cancel")
def cancel_hold(request: Request, hold_id: int) -> dict[str, Any]:
    return _state(request).loans.cancel_hold(hold_id).to_dict()
