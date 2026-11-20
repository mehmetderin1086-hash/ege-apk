"""Okuma listeleri uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request
from pydantic import BaseModel, ConfigDict, Field

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["reading-lists"])

_LIST_FIELDS = ("name", "description", "is_opac_visible", "position")


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CreateListPayload(_StrictPayload):
    name: str = Field(min_length=1)
    description: str | None = None
    is_opac_visible: bool = False


class AddItemPayload(_StrictPayload):
    edition_id: int = Field(gt=0)


class ReorderItemsPayload(_StrictPayload):
    edition_ids: list[int]


class AssignPayload(_StrictPayload):
    member_id: int = Field(gt=0)
    note: str | None = None


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/lists")
def list_reading_lists(request: Request) -> dict[str, Any]:
    return {"items": [record.to_dict() for record in _state(request).reading_lists.list_all()]}


@router.post("/lists", status_code=201)
def create_reading_list(request: Request, payload: CreateListPayload) -> dict[str, Any]:
    return _state(request).reading_lists.create(
        name=payload.name, description=payload.description,
        is_opac_visible=payload.is_opac_visible,
    ).to_dict()


@router.get("/lists/{list_id}")
def get_reading_list(request: Request, list_id: int) -> dict[str, Any]:
    lists = _state(request).reading_lists
    record = lists.get(list_id)
    data = record.to_dict()
    data["items"] = [item.to_dict() for item in lists.list_items(list_id)]
    data["assignments"] = [item.to_dict() for item in lists.list_assignments(list_id)]
    return data


@router.patch("/lists/{list_id}")
def update_reading_list(request: Request, list_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    fields = {key: payload[key] for key in _LIST_FIELDS if key in payload}
    return _state(request).reading_lists.update(list_id, **fields).to_dict()


@router.delete("/lists/{list_id}", status_code=204)
def delete_reading_list(request: Request, list_id: int) -> None:
    _state(request).reading_lists.delete(list_id)


@router.post("/lists/{list_id}/items", status_code=201)
def add_list_item(request: Request, list_id: int, payload: AddItemPayload) -> dict[str, Any]:
    return _state(request).reading_lists.add_item(list_id, payload.edition_id).to_dict()


@router.delete("/lists/{list_id}/items/{edition_id}", status_code=204)
def remove_list_item(request: Request, list_id: int, edition_id: int) -> None:
    _state(request).reading_lists.remove_item(list_id, edition_id)


@router.post("/lists/{list_id}/items/reorder")
def reorder_list_items(
    request: Request, list_id: int, payload: ReorderItemsPayload
) -> dict[str, Any]:
    items = _state(request).reading_lists.reorder_items(list_id, payload.edition_ids)
    return {"items": [item.to_dict() for item in items]}


@router.post("/lists/{list_id}/assign", status_code=201)
def assign_member(request: Request, list_id: int, payload: AssignPayload) -> dict[str, Any]:
    return _state(request).reading_lists.assign(
        list_id, payload.member_id, note=payload.note
    ).to_dict()


@router.delete("/lists/{list_id}/assign/{member_id}", status_code=204)
def unassign_member(request: Request, list_id: int, member_id: int) -> None:
    _state(request).reading_lists.unassign(list_id, member_id)


@router.get("/lists/{list_id}/progress")
def list_progress(request: Request, list_id: int, member_id: int | None = None) -> dict[str, Any]:
    lists = _state(request).reading_lists
    lists.get(list_id)  # 404 if the list itself doesn't exist
    if member_id is not None:
        return lists.progress(list_id, member_id)
    return {"items": lists.list_progress_bulk(list_id)}


@router.get("/members/{member_id}/reading-lists")
def member_reading_progress(request: Request, member_id: int) -> dict[str, Any]:
    return {"items": _state(request).reading_lists.member_progress(member_id)}


@router.post("/lists/template/100-temel-eser")
def import_template(request: Request) -> dict[str, Any]:
    return _state(request).reading_lists.import_template("100-temel-eser")
