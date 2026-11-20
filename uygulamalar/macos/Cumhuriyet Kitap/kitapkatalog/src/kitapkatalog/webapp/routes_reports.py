"""Okuma raporu uçları."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from fastapi import APIRouter, Query, Request

from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["reports"])


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/reports/top-readers")
def top_readers(
    request: Request,
    start: str = "",
    end: str = "",
    limit: int = Query(default=20, ge=1, le=200),
) -> list[dict[str, Any]]:
    return _state(request).reports.top_readers(
        start=start or None, end=end or None, limit=limit
    )


@router.get("/reports/by-class")
def by_class(request: Request, start: str = "", end: str = "") -> list[dict[str, Any]]:
    return _state(request).reports.by_class(start=start or None, end=end or None)


@router.get("/reports/snapshot-quality")
def snapshot_quality(
    request: Request, start: str = "", end: str = ""
) -> dict[str, int]:
    return _state(request).reports.snapshot_quality(
        start=start or None, end=end or None
    )


@router.get("/reports/popular-books")
def popular_books(
    request: Request,
    start: str = "",
    end: str = "",
    limit: int = Query(default=20, ge=1, le=200),
) -> list[dict[str, Any]]:
    return _state(request).reports.popular_books(
        start=start or None, end=end or None, limit=limit
    )


@router.get("/reports/monthly")
def monthly(request: Request, months: int = Query(default=12, ge=1, le=60)) -> list[dict[str, Any]]:
    return _state(request).reports.monthly(months=months)


@router.get("/reports/annual")
def annual(request: Request, start: str = "", end: str = "") -> dict[str, Any]:
    """Yıl sonu raporu. Dönem verilmezse eğitim-öğretim yılı varsayılır.

    Varsayılan dönem: içinde bulunulan tarihe göre 1 Eylül'den bugüne
    (Eylül öncesindeysek önceki yılın 1 Eylül'ü).
    """

    if not start or not end:
        today = datetime.now(UTC).date()
        school_year_start = today.year if today.month >= 9 else today.year - 1
        start = start or f"{school_year_start}-09-01"
        end = end or today.isoformat()
    return _state(request).reports.annual(start=start, end=end)


@router.get("/dashboard")
def dashboard(request: Request) -> dict[str, Any]:
    """Ana sayfa özet paneli: tek istekte tüm gösterge kartları.

    Boş veritabanında da hata fırlatmadan sıfır/boş değerler döner.
    """

    state = _state(request)
    today = datetime.now(UTC).date().isoformat()
    month_prefix = today[:7]

    totals = state.catalog.stats()
    loan_stats = state.loans.stats()

    today_events = state.database.fetchone(
        "SELECT COUNT(*) AS n FROM circulation_event WHERE substr(occurred_at, 1, 10) = ?",
        (today,),
    )
    pending_holds = state.database.fetchone(
        "SELECT COUNT(*) AS n FROM hold WHERE status IN ('active', 'ready')"
    )
    readers_this_month = state.database.fetchone(
        "SELECT COUNT(DISTINCT member_id) AS n FROM loan WHERE substr(loaned_at, 1, 7) = ?",
        (month_prefix,),
    )
    collection = state.database.fetchone(
        """
        SELECT
            (SELECT COUNT(*) FROM copy WHERE status = 'active') AS active_copies,
            (SELECT COUNT(*) FROM copy AS c
             JOIN loan AS l ON l.copy_id = c.id AND l.returned_at IS NULL
             WHERE c.status = 'active') AS on_loan
        """
    )
    active_copies = int(collection["active_copies"]) if collection else 0
    on_loan = int(collection["on_loan"]) if collection else 0

    category_distribution = [
        {"value": value, "count": count}
        for value, count in state.catalog.distribution("category")[:6]
    ]

    monthly_loans = [
        {"month": row["month"], "total": row["loans"]}
        for row in state.reports.monthly(months=12)
    ]

    active_challenge = None
    challenges = state.challenges.list_all(status="active")
    if challenges:
        challenge = challenges[0]
        standings = state.challenges.standings(challenge.id)
        active_challenge = {
            "id": challenge.id,
            "name": challenge.name,
            "top": [
                {"member_name": entry["member_name"], "value": entry["book_count"]}
                for entry in standings["standings"][:3]
            ],
        }

    return {
        "totals": {
            "works": totals["works"],
            "editions": totals["editions"],
            "copies": totals["copies"],
        },
        "active_loans": loan_stats["active"],
        "overdue": loan_stats["overdue"],
        "today_events": int(today_events["n"]) if today_events else 0,
        "unread_notifications": state.notifications.unread_count(),
        "pending_holds": int(pending_holds["n"]) if pending_holds else 0,
        "readers_this_month": int(readers_this_month["n"]) if readers_this_month else 0,
        "collection_status": {"on_shelf": active_copies - on_loan, "on_loan": on_loan},
        "category_distribution": category_distribution,
        "monthly_loans": monthly_loans,
        "active_challenge": active_challenge,
    }


@router.post("/reports/export", status_code=202)
def export_reports(request: Request, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    state = _state(request)
    payload = payload or {}
    start = str(payload.get("start") or "") or None
    end = str(payload.get("end") or "") or None

    def run(job) -> dict[str, Any]:
        job.message = "Okuma raporu hazırlanıyor…"
        stamp = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        destination = state.paths.exports / f"okuma-raporu-{stamp}.xlsx"
        state.paths.exports.mkdir(parents=True, exist_ok=True)
        state.reports.export_xlsx(destination, start=start, end=end)
        return {"download": destination.name}

    job = state.registry.start("export", "Okuma raporu (xlsx)", run)
    return job.to_dict()
