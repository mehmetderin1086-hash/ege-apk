"""Üye (öğrenci/personel) uçları: CRUD, e-Okul içe aktarımı, yıl sonu sihirbazı."""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

from anyio import to_thread
from fastapi import APIRouter, HTTPException, Query, Request, UploadFile
from pydantic import BaseModel, ConfigDict, Field

from kitapkatalog.webapp.state import WebState
from kitapkatalog.webapp.uploads import purge_expired_files, stage_upload

router = APIRouter(tags=["members"])


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class BlockPayload(_StrictPayload):
    reason: str = Field(min_length=1)
    end_date: str | None = None


class LiftPayload(_StrictPayload):
    reason: str | None = None


class AmnestyPayload(_StrictPayload):
    reason: str = Field(min_length=1)

_MAX_XLSX_BYTES = 50 * 1024**2
_PREVIEW_TTL_SECONDS = 2 * 60 * 60


def _state(request: Request) -> WebState:
    return request.app.state.web


def _staging_root(state: WebState) -> Path:
    root = state.upload_root / "members"
    root.mkdir(parents=True, exist_ok=True)
    purge_expired_files(root, maximum_age_seconds=_PREVIEW_TTL_SECONDS)
    return root


async def _stage_xlsx(state: WebState, file: UploadFile) -> Path:
    name = Path(file.filename or "liste.xlsx").name
    if Path(name).suffix.lower() != ".xlsx":
        raise HTTPException(
            status_code=400,
            detail="Yalnız .xlsx desteklenir; dosyayı e-Okul'dan Excel (.xlsx) olarak kaydedin",
        )
    return await stage_upload(
        _staging_root(state),
        file,
        allowed_suffixes={".xlsx"},
        maximum_bytes=_MAX_XLSX_BYTES,
        kind="xlsx",
        target_name=f"{uuid.uuid4().hex}.xlsx",
    )


@router.get("/members")
def list_members(
    request: Request,
    q: str = "",
    class_name: str = "",
    member_type: str = "",
    active: bool | None = True,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    state = _state(request)
    items, total = state.members.search(
        q,
        class_name=class_name or None,
        member_type=member_type or None,
        active=active,
        limit=limit,
        offset=offset,
    )
    return {
        "items": [item.to_dict() for item in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.post("/members", status_code=201)
def add_member(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    record = state.members.add(
        member_type=str(payload.get("member_type") or "student"),
        school_number=payload.get("school_number"),
        first_name=str(payload.get("first_name") or ""),
        last_name=str(payload.get("last_name") or ""),
        class_name=payload.get("class_name"),
        notes=payload.get("notes"),
    )
    return record.to_dict()


@router.get("/members/by-number/{school_number}")
def get_member_by_number(request: Request, school_number: str) -> dict[str, Any]:
    record = _state(request).members.get_by_number(school_number)
    if record is None:
        raise HTTPException(status_code=404, detail="Bu numarayla üye bulunamadı")
    return record.to_dict()


@router.get("/members/{member_id}")
def get_member(request: Request, member_id: int) -> dict[str, Any]:
    record = _state(request).members.get(member_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Üye bulunamadı")
    return record.to_dict()


@router.patch("/members/{member_id}")
def update_member(request: Request, member_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    record = _state(request).members.update(member_id, **payload)
    return record.to_dict()


@router.delete("/members/{member_id}", status_code=204)
def delete_member(request: Request, member_id: int) -> None:
    _state(request).members.delete(member_id)


@router.get("/members/{member_id}/summary")
def member_summary(request: Request, member_id: int) -> dict[str, Any]:
    """Üye çekmecesi: aktif ödünçler, kısa geçmiş, toplamlar, ceza durumu."""

    state = _state(request)
    member = state.members.get(member_id)
    if member is None:
        raise HTTPException(status_code=404, detail="Üye bulunamadı")
    loans = state.loans
    active, _ = loans.list_loans(status="active", member_id=member_id, limit=100)
    history, total_loans = loans.member_history(member_id, limit=20)
    totals = state.database.fetchone(
        """
        SELECT COUNT(*) AS total,
               SUM(returned_at IS NOT NULL) AS returned,
               SUM(returned_at IS NOT NULL AND substr(returned_at, 1, 10) > due_at) AS late
        FROM loan WHERE member_id = ?
        """,
        (member_id,),
    )
    penalty_end = loans.penalty_end_for(member_id)
    active_block = loans.active_manual_block(member_id)
    active_items = [record.to_dict() for record in active]
    return {
        "member": member.to_dict(),
        "active": active_items,
        "history": [record.to_dict() for record in history],
        "totals": {
            "total": int(totals["total"]) if totals else total_loans,
            "returned": int(totals["returned"] or 0) if totals else 0,
            "late": int(totals["late"] or 0) if totals else 0,
        },
        "overdue_count": sum(1 for item in active_items if item["overdue"]),
        "penalty_end": penalty_end.isoformat() if penalty_end else None,
        "active_block": active_block.to_dict() if active_block else None,
    }


@router.post("/members/{member_id}/blocks", status_code=201)
def add_member_block(request: Request, member_id: int, payload: BlockPayload) -> dict[str, Any]:
    block = _state(request).loans.add_block(
        member_id, reason=payload.reason, end_date=payload.end_date
    )
    return block.to_dict()


@router.post("/members/{member_id}/blocks/{block_id}/lift")
def lift_member_block(
    request: Request, member_id: int, block_id: int, payload: LiftPayload | None = None
) -> dict[str, Any]:
    block = _state(request).loans.lift_block(
        member_id, block_id, reason=payload.reason if payload else None
    )
    return block.to_dict()


@router.post("/members/{member_id}/amnesty", status_code=201)
def member_amnesty(request: Request, member_id: int, payload: AmnestyPayload) -> dict[str, Any]:
    block = _state(request).loans.grant_amnesty(member_id, reason=payload.reason)
    return block.to_dict()


@router.get("/members/{member_id}/blocks")
def list_member_blocks(request: Request, member_id: int) -> list[dict[str, Any]]:
    return [block.to_dict() for block in _state(request).loans.list_blocks(member_id)]


@router.post("/members/import")
async def import_members(request: Request, file: UploadFile) -> dict[str, Any]:
    state = _state(request)
    staged = await _stage_xlsx(state, file)
    try:
        report = await to_thread.run_sync(state.members.import_eokul_xlsx, staged)
    finally:
        staged.unlink(missing_ok=True)
    return report.to_dict()


@router.post("/members/promote/preview")
async def promote_preview(request: Request, file: UploadFile) -> dict[str, Any]:
    state = _state(request)
    staged = await _stage_xlsx(state, file)
    try:
        plan = await to_thread.run_sync(state.members.promote_preview, staged)
    except Exception:
        staged.unlink(missing_ok=True)
        raise
    plan["staged_id"] = staged.stem
    return plan


@router.post("/members/promote/apply")
def promote_apply(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    staged_id = str(payload.get("staged_id") or "")
    if not staged_id.isalnum():
        raise HTTPException(status_code=400, detail="Geçersiz dosya kimliği")
    staged = _staging_root(state) / f"{staged_id}.xlsx"
    if not staged.is_file():
        raise HTTPException(
            status_code=404, detail="Önizleme dosyası bulunamadı; listeyi yeniden yükleyin"
        )
    try:
        report = state.members.promote_apply(staged)
    finally:
        staged.unlink(missing_ok=True)
    return report.to_dict()


@router.delete("/members/promote/staged/{staged_id}", status_code=204)
def promote_cancel(request: Request, staged_id: str) -> None:
    """Explicitly discard a retained year-end preview containing student data."""

    if len(staged_id) != 32 or not all(character in "0123456789abcdef" for character in staged_id):
        raise HTTPException(status_code=400, detail="Geçersiz dosya kimliği")
    staged = _staging_root(_state(request)) / f"{staged_id}.xlsx"
    staged.unlink(missing_ok=True)


@router.get("/meta/classes")
def list_classes(request: Request) -> list[str]:
    return _state(request).members.list_classes()
