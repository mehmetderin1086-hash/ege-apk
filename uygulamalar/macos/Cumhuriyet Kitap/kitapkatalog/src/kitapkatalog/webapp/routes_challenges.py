"""Okuma yarışması uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, ConfigDict, Field

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["reading-challenges"])

_CHALLENGE_FIELDS = (
    "name", "start_date", "end_date", "target_books", "scope", "class_name", "status",
)


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CreateChallengePayload(_StrictPayload):
    name: str = Field(min_length=1)
    start_date: str
    end_date: str
    target_books: int = Field(gt=0)
    scope: str = Field(default="all", pattern="^(all|class)$")
    class_name: str | None = None


class CertificatePayload(_StrictPayload):
    member_id: int = Field(gt=0)
    rank: int | None = Field(default=None, gt=0)


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/challenges")
def list_challenges(
    request: Request,
    status: str | None = Query(default=None, pattern="^(active|archived)$"),
) -> dict[str, Any]:
    items = _state(request).challenges.list_all(status=status)
    return {"items": [record.to_dict() for record in items]}


@router.post("/challenges", status_code=201)
def create_challenge(request: Request, payload: CreateChallengePayload) -> dict[str, Any]:
    return _state(request).challenges.create(
        name=payload.name,
        start_date=payload.start_date,
        end_date=payload.end_date,
        target_books=payload.target_books,
        scope=payload.scope,
        class_name=payload.class_name,
    ).to_dict()


@router.get("/challenges/{challenge_id}")
def get_challenge(request: Request, challenge_id: int) -> dict[str, Any]:
    return _state(request).challenges.get(challenge_id).to_dict()


@router.patch("/challenges/{challenge_id}")
def update_challenge(
    request: Request, challenge_id: int, payload: dict[str, Any]
) -> dict[str, Any]:
    fields = {key: payload[key] for key in _CHALLENGE_FIELDS if key in payload}
    return _state(request).challenges.update(challenge_id, **fields).to_dict()


@router.get("/challenges/{challenge_id}/standings")
def challenge_standings(request: Request, challenge_id: int) -> dict[str, Any]:
    return _state(request).challenges.standings(challenge_id)


@router.post("/challenges/{challenge_id}/certificates", status_code=201)
def record_certificate(
    request: Request, challenge_id: int, payload: CertificatePayload
) -> dict[str, Any]:
    return _state(request).challenges.record_certificate(
        challenge_id, payload.member_id, rank=payload.rank
    )


@router.get("/challenges/{challenge_id}/certificates")
def list_certificates(request: Request, challenge_id: int) -> dict[str, Any]:
    return {"items": _state(request).challenges.list_certificates(challenge_id)}
