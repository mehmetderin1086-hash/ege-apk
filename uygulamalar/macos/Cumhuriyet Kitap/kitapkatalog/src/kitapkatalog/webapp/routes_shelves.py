"""Raf/dolap haritası uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["shelves"])

_FIELDS = ("name", "grid_row", "grid_col", "capacity", "color", "notes")


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/shelves/map")
def shelf_map(request: Request) -> dict[str, Any]:
    return _state(request).shelves.map_summary()


@router.get("/shelves")
def list_shelves(request: Request) -> list[dict[str, Any]]:
    return [record.to_dict() for record in _state(request).shelves.list()]


@router.post("/shelves", status_code=201)
def create_shelf(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    kwargs = {key: payload.get(key) for key in _FIELDS if key != "name"}
    return _state(request).shelves.create(str(payload.get("name") or ""), **kwargs).to_dict()


@router.patch("/shelves/{shelf_id}")
def update_shelf(request: Request, shelf_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    fields = {key: payload[key] for key in _FIELDS if key in payload}
    return _state(request).shelves.update(shelf_id, **fields).to_dict()


@router.delete("/shelves/{shelf_id}", status_code=204)
def delete_shelf(request: Request, shelf_id: int) -> None:
    _state(request).shelves.delete(shelf_id)


@router.post("/shelves/{shelf_id}/adopt")
def adopt_location(request: Request, shelf_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    moved = _state(request).shelves.adopt(shelf_id, str(payload.get("location") or ""))
    return {"moved": moved}
