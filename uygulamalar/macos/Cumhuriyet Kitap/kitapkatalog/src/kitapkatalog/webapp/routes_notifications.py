"""Bildirim merkezi uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query, Request

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["notifications"])


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/notifications")
def list_notifications(
    request: Request,
    unread: bool = False,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    items, total = _state(request).notifications.list(unread=unread, limit=limit, offset=offset)
    return {"items": items, "total": total, "limit": limit, "offset": offset}


@router.post("/notifications/{notification_id}/read")
def mark_notification_read(request: Request, notification_id: int) -> dict[str, Any]:
    return _state(request).notifications.mark_read(notification_id)


@router.post("/notifications/read-all")
def mark_all_notifications_read(request: Request) -> dict[str, int]:
    return {"updated": _state(request).notifications.mark_all_read()}


@router.post("/notifications/{notification_id}/dismiss", status_code=204)
def dismiss_notification(request: Request, notification_id: int) -> None:
    _state(request).notifications.dismiss(notification_id)
