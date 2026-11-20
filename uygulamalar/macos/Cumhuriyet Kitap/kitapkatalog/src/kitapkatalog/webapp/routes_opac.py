"""OPAC: öğrencilerin kendi başına kitap arayabildiği salt-okunur uçlar.

Oturum İSTEMEZ (security.py muafiyeti). Yalnız katalog bilgisi döner;
üye/ödünç kişi bilgisi asla sızmaz — sadece "rafta / ödünçte" durumu.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse

from kitapkatalog.domain import SearchFilters
from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["opac"])

# Öğrenci sekmeleri → katalog sıralaması. "popular" sıralar ama sayı DÖNDÜRMEZ.
_OPAC_SORTS = {"new": "created", "popular": "popular"}


def _state(request: Request) -> WebState:
    return request.app.state.web


def _cover_servable(state: WebState, front_path: str | None) -> bool:
    """Kapak ucu bu yolu gerçekten servis edebilecek mi? (dosya var + varlık
    kökü altında). has_cover=True deyip 404 veren kırık <img> üretilmesin."""

    if not front_path:
        return False
    try:
        resolved = Path(front_path).resolve()
        return resolved.is_file() and resolved.is_relative_to(state.paths.assets.resolve())
    except OSError:  # pragma: no cover - erişilemeyen yol
        return False


@router.get("/opac/categories")
def opac_categories(request: Request) -> list[str]:
    """Yalnız ayrık kategori adları; başka hiçbir alan dönmez."""

    return _state(request).catalog.list_distinct_values("category")


@router.get("/opac/cover/{edition_id}")
def opac_cover(request: Request, edition_id: int) -> FileResponse:
    """Öğrenci ekranı için yalnız ÖN kapak, her zaman küçük boy.

    Sıkılaştırma: DB'deki yol veri kökü dışını gösteriyorsa 404 — oturumsuz
    uç keyfi mutlak yolu asla servis etmez (yönetim ucunda olmayan denetim).
    """

    from kitapkatalog.webapp.routes_books import _thumbnail

    state = _state(request)
    book = state.catalog.get_book(edition_id)
    # Sınır veri kökü değil YALNIZ varlık köküdür; resolve() symlink'le
    # dışarı kaçışı da kapatır (_cover_servable).
    if book is None or not _cover_servable(state, book.front_path):
        raise HTTPException(status_code=404, detail="Kapak yok")
    return FileResponse(_thumbnail(state, Path(book.front_path).resolve()))


@router.get("/opac/lists")
def opac_lists(request: Request) -> dict[str, Any]:
    """Yalnız görünür işaretlenmiş okuma listeleri; üye/atama verisi asla sızmaz."""

    state = _state(request)
    lists = state.reading_lists.opac_lists()
    for entry in lists:
        for item in entry["items"]:
            item["has_cover"] = _cover_servable(state, item.pop("front_path"))
    return {"items": lists}


@router.get("/opac/search")
def opac_search(
    request: Request,
    q: str = "",
    category: str = "",
    available: bool = False,
    sort: str = Query(default="", pattern="^(new|popular)?$"),
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    state = _state(request)
    filters = SearchFilters(
        category=category or None,
        availability="available" if available else None,
    )
    page = state.catalog.search(
        q,
        filters=filters,
        limit=limit,
        offset=offset,
        sort=_OPAC_SORTS.get(sort, "relevance"),
    )
    edition_ids = [record.edition_id for record in page.items]
    on_loan = state.loans.active_counts(edition_ids)
    on_hold = state.loans.hold_counts(edition_ids)
    items = []
    for record in page.items:
        active = [copy for copy in record.copies if copy.status == "active"]
        loaned = on_loan.get(record.edition_id, 0)
        authors = "; ".join(
            contributor.name
            for contributor in record.contributors
            if str(contributor.role) == "author"
        ) or "; ".join(contributor.name for contributor in record.contributors)
        locations = sorted({copy.location for copy in active if copy.location})
        items.append(
            {
                # edition_id + has_cover yalnız katalog kimliğidir (kapak ucu
                # için); üye/ödünç kişi verisi bu sözlüğe asla girmez.
                "edition_id": record.edition_id,
                "has_cover": _cover_servable(state, record.front_path),
                "title": record.title,
                "subtitle": record.subtitle,
                "authors": authors,
                "publisher": record.publisher,
                "publication_date": record.publication_date,
                "category": record.category,
                "locations": locations,
                "total_copies": len(active),
                "available": max(0, len(active) - loaned),
                "holds_waiting": on_hold.get(record.edition_id, 0),
            }
        )
    return {"items": items, "total": page.total, "limit": limit, "offset": offset}
