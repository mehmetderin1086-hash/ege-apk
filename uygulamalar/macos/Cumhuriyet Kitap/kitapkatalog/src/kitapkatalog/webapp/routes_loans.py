"""Ödünç verme/iade uçları."""

from __future__ import annotations

from fastapi import APIRouter, Query, Request
from pydantic import BaseModel, ConfigDict, Field, model_validator

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["loans"])


class _StrictPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")


class CheckoutPayload(_StrictPayload):
    member_id: int | None = Field(default=None, gt=0)
    school_number: str | None = None
    edition_id: int | None = Field(default=None, gt=0)
    isbn: str | None = None
    copy_id: int | None = Field(default=None, gt=0)
    code: str | None = None
    request_id: str | None = Field(default=None, min_length=8, max_length=200)

    @model_validator(mode="after")
    def exactly_one_book_selector(self) -> CheckoutPayload:
        selected = (
            self.edition_id is not None,
            bool(self.isbn and self.isbn.strip()),
            self.copy_id is not None,
            bool(self.code and self.code.strip()),
        )
        if sum(selected) != 1:
            raise ValueError(
                "edition_id, isbn, copy_id veya code alanlarından tam olarak biri gerekli"
            )
        return self


class ReturnByCodePayload(_StrictPayload):
    code: str
    request_id: str | None = Field(default=None, min_length=8, max_length=200)


class MutationPayload(_StrictPayload):
    request_id: str | None = Field(default=None, min_length=8, max_length=200)


class ExtendPayload(MutationPayload):
    days: int | None = Field(default=None, gt=0, le=365)


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.post("/loans", status_code=201)
def checkout(request: Request, payload: CheckoutPayload) -> dict[str, object]:
    state = _state(request)
    member_id = payload.member_id
    school_number = payload.school_number
    if member_id is not None and school_number is not None:
        # Çelişki riski: ikisi farklı üyeleri gösterebilir; birini seçtir.
        raise ValueError("member_id ve school_number birlikte verilemez")
    if member_id is None:
        if school_number is None:
            raise ValueError("member_id veya school_number gerekli")
        member = state.members.get_by_number(str(school_number).strip())
        if member is None:
            raise KeyError(f"Bu numarayla üye bulunamadı: {school_number}")
        member_id = member.id
    loan = state.loans.checkout(
        int(member_id),
        edition_id=payload.edition_id,
        isbn=payload.isbn,
        copy_id=payload.copy_id,
        code=payload.code,
        request_id=payload.request_id,
    )
    return loan.to_dict()


@router.post("/loans/return-by-code")
def return_by_code(
    request: Request, payload: ReturnByCodePayload
) -> dict[str, object]:
    return _state(request).loans.return_by_code(
        payload.code, request_id=payload.request_id
    ).to_dict()


@router.post("/loans/{loan_id}/return")
def return_loan(
    request: Request, loan_id: int, payload: MutationPayload | None = None
) -> dict[str, object]:
    return _state(request).loans.return_loan(
        loan_id, request_id=payload.request_id if payload else None
    ).to_dict()


@router.post("/loans/{loan_id}/extend")
def extend_loan(
    request: Request, loan_id: int, payload: ExtendPayload | None = None
) -> dict[str, object]:
    return _state(request).loans.extend(
        loan_id,
        days=payload.days if payload else None,
        request_id=payload.request_id if payload else None,
    ).to_dict()


@router.get("/loans")
def list_loans(
    request: Request,
    status: str = Query(default="active", pattern="^(active|overdue|returned|all)$"),
    q: str = "",
    member_id: int | None = None,
    edition_id: int | None = None,
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict[str, object]:
    items, total = _state(request).loans.list_loans(
        status=status,
        q=q,
        member_id=member_id,
        edition_id=edition_id,
        limit=limit,
        offset=offset,
    )
    return {
        "items": [item.to_dict() for item in items],
        "total": total,
        "limit": limit,
        "offset": offset,
    }


@router.get("/loans/stats")
def loan_stats(request: Request) -> dict[str, int]:
    return _state(request).loans.stats()
