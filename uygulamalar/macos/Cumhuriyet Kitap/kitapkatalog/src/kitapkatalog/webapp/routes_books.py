"""Kütüphane: arama, detay, düzenleme, toplu işlem, kapak servisi."""

from __future__ import annotations

import hashlib
import re
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse

from kitapkatalog.catalog import IdentifierConflictError
from kitapkatalog.domain import (
    BookInput,
    ContributorInput,
    CopyInput,
    IdentifierInput,
    SearchFilters,
)
from kitapkatalog.webapp.serialize import book_to_dict
from kitapkatalog.webapp.state import WebState
from kitapkatalog.webapp.uploads import stage_upload

router = APIRouter(tags=["books"])


def _state(request: Request) -> WebState:
    return request.app.state.web


# update_book'a geçirilebilecek alanlar (BookRecord metin/sayı alanları).
_EDITABLE_FIELDS = {
    "title", "subtitle", "original_title", "publisher", "imprint", "series",
    "volume", "language", "publication_place", "publication_date",
    "edition_statement", "printing_number", "printer", "binding", "page_count",
    "dimensions", "price_amount", "currency", "blurb", "awards", "quotations",
    "category", "review_status",
}

_COVER_ROLES = {
    "front": "front_path",
    "front_inside": "front_inside_path",
    "back_inside": "back_inside_path",
    "back": "back_path",
}

_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tif", ".tiff", ".bmp"}
_MAX_COPIES_PER_EDITION = 1_000
_MAX_COVER_BYTES = 40 * 1024**2


def _positive_int(
    raw: Any,
    *,
    field: str,
    default: int | None = None,
    maximum: int,
) -> int | None:
    if raw in (None, ""):
        return default
    if isinstance(raw, bool):
        raise ValueError(f"{field} tam sayı olmalıdır")
    try:
        value = int(raw)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{field} tam sayı olmalıdır") from exc
    if value < 1 or value > maximum:
        raise ValueError(f"{field} 1 ile {maximum} arasında olmalıdır")
    return value


def _servable_cover(state: WebState, raw: str | Path | None) -> Path | None:
    """Resolve only managed assets; symlinks cannot escape the asset root."""

    if not raw:
        return None
    try:
        source = Path(raw).resolve()
        root = state.paths.assets.resolve()
        if source.is_file() and source.is_relative_to(root):
            return source
    except OSError:
        pass
    return None


@router.get("/books")
def search_books(
    request: Request,
    q: str = "",
    publisher: str | None = None,
    language: str | None = None,
    review_status: str | None = None,
    category: str | None = None,
    identifier: str | None = None,
    missing: str | None = None,
    location: str | None = None,
    availability: str | None = Query(default=None, pattern="^(available|unavailable)$"),
    year_from: int | None = Query(default=None, ge=0, le=9999),
    year_to: int | None = Query(default=None, ge=0, le=9999),
    sort: str = Query(default="relevance", pattern="^(relevance|title|year|created|popular)$"),
    limit: int = Query(default=50, le=500),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    state = _state(request)
    filters = SearchFilters(
        publisher=publisher or None,
        language=language or None,
        review_status=review_status or None,
        identifier=identifier or None,
        category=category or None,
        missing=missing or None,
        location=location or None,
        availability=availability or None,
        year_from=year_from,
        year_to=year_to,
    )
    page = state.catalog.search(q, filters=filters, limit=limit, offset=offset, sort=sort)
    counts = state.loans.active_counts(book.edition_id for book in page.items)
    return {
        "items": [
            book_to_dict(book, on_loan=counts.get(book.edition_id, 0))
            for book in page.items
        ],
        "total": page.total,
        "limit": page.limit,
        "offset": page.offset,
    }


@router.get("/books/{edition_id}")
def get_book(request: Request, edition_id: int) -> dict[str, Any]:
    state = _state(request)
    book = state.catalog.get_book(edition_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    on_loan = state.loans.active_counts([edition_id]).get(edition_id, 0)
    return book_to_dict(book, detail=True, on_loan=on_loan)


def _authors_to_contributors(authors: str) -> tuple[ContributorInput, ...]:
    names = [name.strip() for name in authors.split(";") if name.strip()]
    return tuple(
        ContributorInput(name=name, sort_order=index) for index, name in enumerate(names)
    )


@router.post("/books", status_code=201)
def create_book(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    title = (payload.get("title") or "").strip()
    if not title:
        raise HTTPException(status_code=400, detail="Başlık zorunludur")
    isbn = (payload.get("isbn") or "").strip()
    # Bütün dönüştürmeler yazımdan önce yapılır; bozuk bir son alanın kitap
    # kaydı oluşturup 400 dönmesi engellenir.
    page_count = _positive_int(
        payload.get("page_count"), field="Sayfa sayısı", maximum=100_000
    )
    copy_count = _positive_int(
        payload.get("copy_count"),
        field="Nüsha sayısı",
        default=1,
        maximum=_MAX_COPIES_PER_EDITION,
    )
    assert copy_count is not None
    identifiers = (IdentifierInput(scheme="ISBN", value=isbn, source="user"),) if isbn else ()
    copy_payload = payload.get("copy") or {}
    book_input = BookInput(
        title=title,
        subtitle=(payload.get("subtitle") or "").strip() or None,
        publisher=(payload.get("publisher") or "").strip() or None,
        language=(payload.get("language") or "").strip() or None,
        publication_date=(payload.get("publication_date") or "").strip() or None,
        page_count=page_count,
        category=(payload.get("category") or "").strip() or None,
        blurb=(payload.get("blurb") or "").strip() or None,
        contributors=_authors_to_contributors(payload.get("authors") or ""),
        identifiers=identifiers,
        copy=CopyInput(
            source_fingerprint=f"web:manual:{uuid.uuid4().hex}",
            location=(payload.get("location") or "").strip() or None,
            acquisition_method=(copy_payload.get("acquisition_method") or "").strip() or None,
            acquisition_date=(copy_payload.get("acquisition_date") or "").strip() or None,
            acquisition_price=(copy_payload.get("acquisition_price") or "").strip() or None,
        ),
    )
    extra_location = (payload.get("location") or "").strip() or None
    with state.database.transaction(immediate=True):
        if isbn:
            existing = state.catalog.get_by_identifier("ISBN", isbn)
            if existing is not None:
                raise IdentifierConflictError(
                    f"Bu ISBN zaten kayıtlı: {existing.title} (No {existing.edition_id}). "
                    "Adet artırmak için mevcut kaydı kullanın."
                )
        record = state.catalog.save_book(
            book_input, source_fingerprint=f"web:manual:{uuid.uuid4().hex}"
        )
        state.catalog.update_book(
            record.edition_id, {"review_status": "completed"}, user_edit=True
        )
        for _ in range(max(0, copy_count - 1)):
            state.catalog.add_copy(
                record.edition_id,
                CopyInput(location=extra_location) if extra_location else None,
            )
        if payload.get("auto_inventory"):
            state.catalog.assign_missing_inventory_codes(record.edition_id)
        saved = state.catalog.get_book(record.edition_id)
        assert saved is not None
    return book_to_dict(saved, detail=True)


@router.patch("/books/{edition_id}")
def update_book(request: Request, edition_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    changes = {
        key: (value if value not in ("", None) else None)
        for key, value in (payload.get("changes") or {}).items()
        if key in _EDITABLE_FIELDS
    }
    if "page_count" in changes and changes["page_count"] is not None:
        changes["page_count"] = _positive_int(
            changes["page_count"], field="Sayfa sayısı", maximum=100_000
        )
    copy_count = None
    if "copy_count" in payload and payload["copy_count"] is not None:
        copy_count = _positive_int(
            payload["copy_count"],
            field="Nüsha sayısı",
            maximum=_MAX_COPIES_PER_EDITION,
        )
    isbn_raw: str | None = None
    if "isbn" in payload:
        isbn_raw = (payload["isbn"] or "").strip()
        # set_isbn rakamsız girdiyi boş sayıp mevcut ISBN'i siler; yazım
        # hatası sessiz silmeye dönüşmesin.
        if isbn_raw and not re.sub(r"[^0-9Xx]", "", isbn_raw):
            raise HTTPException(
                status_code=400, detail=f"ISBN rakam içermiyor: {isbn_raw!r}"
            )
    names: list[str] | None = None
    if "authors" in payload:
        names = [name.strip() for name in (payload["authors"] or "").split(";") if name.strip()]
    with state.database.transaction(immediate=True):
        if "isbn" in payload:
            state.catalog.set_isbn(edition_id, isbn_raw or None)
        if changes:
            state.catalog.update_book(edition_id, changes, user_edit=True)
        if names is not None:
            state.catalog.set_authors(edition_id, names)
        if "location" in payload:
            state.catalog.set_location(
                edition_id, (payload["location"] or "").strip() or None
            )
        if copy_count is not None:
            state.catalog.set_copy_count(edition_id, copy_count)
        book = state.catalog.get_book(edition_id)
        if book is None:
            raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    return book_to_dict(book, detail=True)


@router.delete("/books/{edition_id}")
def delete_book(request: Request, edition_id: int) -> dict[str, Any]:
    state = _state(request)
    if not state.catalog.delete_book(edition_id):
        raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    return {"deleted": edition_id}


@router.post("/books/{edition_id}/copies", status_code=201)
def add_copy(
    request: Request, edition_id: int, payload: dict[str, Any] | None = None
) -> dict[str, Any]:
    state = _state(request)
    payload = payload or {}
    count = _positive_int(payload.get("count"), field="Nüsha sayısı", default=1, maximum=100)
    assert count is not None
    location = (payload.get("location") or "").strip() or None
    acquisition_method = (payload.get("acquisition_method") or "").strip() or None
    acquisition_date = (payload.get("acquisition_date") or "").strip() or None
    acquisition_price = (payload.get("acquisition_price") or "").strip() or None
    copy_input = (
        CopyInput(
            location=location,
            acquisition_method=acquisition_method,
            acquisition_date=acquisition_date,
            acquisition_price=acquisition_price,
        )
        if any((location, acquisition_method, acquisition_date, acquisition_price))
        else None
    )
    with state.database.transaction(immediate=True):
        copy_ids = [
            state.catalog.add_copy(edition_id, copy_input) for _ in range(count)
        ]
        inventory_codes: list[str] = []
        if payload.get("auto_inventory"):
            assigned = state.catalog.assign_missing_inventory_codes(edition_id)
            inventory_codes = [assigned[copy_id] for copy_id in copy_ids if copy_id in assigned]
        book = state.catalog.get_book(edition_id)
        assert book is not None
    return {
        "copy_id": copy_ids[0],
        "copy_ids": copy_ids,
        "inventory_codes": inventory_codes,
        "copy_count": sum(1 for copy in book.copies if copy.status == "active"),
    }


@router.get("/quick/isbn/{code}")
def quick_isbn(request: Request, code: str) -> dict[str, Any]:
    """Hızlı kayıt: okutulan ISBN katalogda var mı, nüsha durumu ne?"""

    state = _state(request)
    compact = re.sub(r"[^0-9Xx]", "", code).upper()
    if len(compact) not in (10, 13):
        return {"found": False, "valid": False, "isbn": compact}
    book = state.catalog.get_by_identifier("ISBN", compact)
    if book is None:
        return {"found": False, "valid": True, "isbn": compact}
    active = [copy for copy in book.copies if copy.status == "active"]
    on_loan = state.database.fetchone(
        "SELECT COUNT(*) FROM loan WHERE edition_id = ? AND returned_at IS NULL",
        (book.edition_id,),
    )
    return {
        "found": True,
        "valid": True,
        "isbn": compact,
        "book": book_to_dict(book),
        "active_copies": len(active),
        "on_loan": int(on_loan[0]) if on_loan else 0,
        "next_code": state.catalog.peek_next_inventory_code(),
    }


@router.get("/quick/next-code")
def quick_next_code(request: Request) -> dict[str, str]:
    return {"next_code": _state(request).catalog.peek_next_inventory_code()}


@router.delete("/copies/{copy_id}")
def delete_copy(request: Request, copy_id: int) -> dict[str, Any]:
    state = _state(request)
    if not state.catalog.delete_copy(copy_id):
        raise HTTPException(status_code=404, detail="Nüsha bulunamadı")
    return {"deleted": copy_id}


@router.post("/copies/assign-codes")
def assign_codes(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    """Etiket basımı öncesi kodsuz nüshalara demirbaş numarası verir."""

    state = _state(request)
    scope = str(payload.get("scope") or "all")
    if scope == "edition":
        edition_id = payload.get("edition_id")
        if not edition_id:
            raise HTTPException(status_code=400, detail="edition_id gerekli")
        assigned = state.catalog.assign_missing_inventory_codes(int(edition_id))
    elif scope == "location":
        location = (payload.get("location") or "").strip()
        if not location:
            raise HTTPException(status_code=400, detail="location gerekli")
        assigned = state.catalog.assign_missing_codes_bulk(location=location)
    elif scope == "all":
        assigned = state.catalog.assign_missing_codes_bulk()
    else:
        raise HTTPException(status_code=400, detail=f"Bilinmeyen kapsam: {scope}")
    return {"assigned": len(assigned)}


_COPY_PATCH_FIELDS = (
    "location", "acquisition_method", "acquisition_date", "acquisition_price",
)


@router.patch("/copies/{copy_id}")
def update_copy(request: Request, copy_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    fields = {key: payload[key] for key in _COPY_PATCH_FIELDS if key in payload}
    if not fields:
        raise HTTPException(status_code=400, detail="Güncellenecek alan yok")
    state.catalog.update_copy_fields(copy_id, **fields)
    return {"updated": copy_id}


@router.post("/books/bulk")
def bulk_action(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    ids = [int(value) for value in payload.get("ids") or []]
    action = payload.get("action")
    value = payload.get("value")
    if not ids:
        raise HTTPException(status_code=400, detail="Kayıt seçilmedi")
    copies_value = None
    if action == "copies":
        copies_value = _positive_int(
            value,
            field="Nüsha sayısı",
            maximum=_MAX_COPIES_PER_EDITION,
        )
    done, errors = 0, []
    for edition_id in ids:
        try:
            with state.database.transaction(immediate=True):
                if action == "approve":
                    state.catalog.update_book(
                        edition_id, {"review_status": "completed"}, user_edit=True
                    )
                elif action == "category":
                    state.catalog.update_book(
                        edition_id, {"category": value or None}, user_edit=True
                    )
                elif action == "location":
                    state.catalog.set_location(edition_id, value or None)
                elif action == "copies":
                    assert copies_value is not None
                    state.catalog.set_copy_count(edition_id, copies_value)
                elif action == "delete":
                    if not state.catalog.delete_book(edition_id):
                        raise KeyError(f"Kayıt bulunamadı: {edition_id}")
                else:
                    raise HTTPException(status_code=400, detail=f"Bilinmeyen işlem: {action}")
            done += 1
        except HTTPException:
            raise
        except Exception as exc:
            errors.append({"edition_id": edition_id, "error": str(exc)})
    return {"done": done, "errors": errors}


@router.post("/books/{edition_id}/cover/{role}")
async def upload_cover(
    request: Request, edition_id: int, role: str, file: UploadFile
) -> dict[str, Any]:
    state = _state(request)
    if role not in _COVER_ROLES:
        raise HTTPException(status_code=400, detail=f"Geçersiz yüz: {role}")
    book = state.catalog.get_book(edition_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    suffix = Path(file.filename or "kapak.jpg").suffix.lower() or ".jpg"
    if suffix not in _IMAGE_SUFFIXES:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen görsel türü: {suffix}")
    covers = state.paths.assets / "web_covers"
    covers.mkdir(parents=True, exist_ok=True)
    target = await stage_upload(
        covers,
        file,
        allowed_suffixes=_IMAGE_SUFFIXES,
        maximum_bytes=_MAX_COVER_BYTES,
        kind="image",
        target_name=f"{edition_id}-{role}-{uuid.uuid4().hex[:8]}{suffix}",
    )
    try:
        state.catalog.set_cover_paths(edition_id, **{_COVER_ROLES[role]: str(target)})
    except BaseException:
        target.unlink(missing_ok=True)
        raise
    # Önceki kapak da web yüklemesiyse artığı sil; kullanıcının kendi seçtiği
    # orijinal dosyalara (web_covers dışı) dokunma.
    previous = getattr(book, _COVER_ROLES[role])
    if previous:
        previous_path = Path(previous)
        if (
            previous_path.resolve().is_relative_to(covers.resolve())
            and previous_path.resolve() != target.resolve()
        ):
            previous_path.unlink(missing_ok=True)
    return {"edition_id": edition_id, "role": role}


@router.get("/books/{edition_id}/cover/{role}")
def get_cover(
    request: Request, edition_id: int, role: str, thumb: bool = False
) -> FileResponse:
    state = _state(request)
    if role not in _COVER_ROLES:
        raise HTTPException(status_code=400, detail=f"Geçersiz yüz: {role}")
    book = state.catalog.get_book(edition_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    raw_cover = getattr(book, _COVER_ROLES[role])
    source = _servable_cover(state, raw_cover)
    if source is None:
        # Reference-mode/legacy Qt covers may intentionally live outside the
        # data root. Never serve those raw: decode and publish only a bounded,
        # script-free JPEG derivative under our own derivatives root. OPAC
        # remains managed-assets-only in routes_opac.py.
        if not raw_cover:
            raise HTTPException(status_code=404, detail="Kapak görseli yok")
        source = _thumbnail(
            state,
            Path(raw_cover),
            width=320 if thumb else 1_600,
            allow_reference=True,
        )
        return FileResponse(source, media_type="image/jpeg")
    if not thumb:
        return FileResponse(source)
    return FileResponse(_thumbnail(state, source), media_type="image/jpeg")


def _thumbnail(
    state: WebState,
    source: Path,
    width: int = 320,
    *,
    allow_reference: bool = False,
) -> Path:
    source = source.resolve()
    if not source.is_file():
        raise HTTPException(status_code=404, detail="Görsel yok")
    managed = source.is_relative_to(state.paths.root.resolve())
    if not managed and (
        not allow_reference
        or source.suffix.lower() not in _IMAGE_SUFFIXES
        or source.stat().st_size > _MAX_COVER_BYTES
    ):
        raise HTTPException(status_code=404, detail="Görsel yok")
    cache_dir = state.paths.derivatives / "web_thumbs"
    cache_dir.mkdir(parents=True, exist_ok=True)
    stamp = f"{source}:{source.stat().st_mtime_ns}:{width}"
    cached = cache_dir / (hashlib.sha1(stamp.encode()).hexdigest() + ".jpg")
    if cached.is_file():
        return cached
    from PIL import Image, ImageOps, UnidentifiedImageError

    try:
        import pillow_heif

        pillow_heif.register_heif_opener()
    except ImportError:
        pass
    part = cached.with_suffix(f".{uuid.uuid4().hex[:6]}.part")
    try:
        with Image.open(source) as image:
            if (
                image.width < 1
                or image.height < 1
                or image.width * image.height > 100_000_000
            ):
                raise ValueError("Görsel boyutları güvenli sınırların dışında")
            image = ImageOps.exif_transpose(image).convert("RGB")
            ratio = width / image.width
            resized = image.resize((width, max(1, int(image.height * ratio))))
            # Eşzamanlı iki istek aynı .part'a yazmasın: geçici ad isteğe özgü.
            resized.save(part, format="JPEG", quality=82)
        part.replace(cached)
    except (Image.DecompressionBombError, OSError, UnidentifiedImageError, ValueError) as exc:
        part.unlink(missing_ok=True)
        raise HTTPException(status_code=404, detail="Görsel yok") from exc
    return cached


@router.get("/meta/distinct/{column}")
def distinct_values(request: Request, column: str) -> list[str]:
    return _state(request).catalog.list_distinct_values(column)


@router.get("/stats")
def stats(request: Request) -> dict[str, Any]:
    state = _state(request)
    growth_rows = state.database.fetchall(
        """
        SELECT substr(created_at, 1, 7) AS month, COUNT(*) AS added
        FROM copy WHERE status = 'active'
        GROUP BY month ORDER BY month
        """
    )
    # Son 24 ayı çiz; öncesi kümülatif başlangıca katılır.
    growth: list[dict[str, Any]] = []
    cumulative = sum(int(row["added"]) for row in growth_rows[:-24])
    for row in growth_rows[-24:]:
        cumulative += int(row["added"])
        growth.append({"month": row["month"], "total": cumulative})
    last_session = state.database.fetchone(
        """
        SELECT id, name, closed_at FROM stocktake_session
        WHERE status = 'closed' ORDER BY closed_at DESC LIMIT 1
        """
    )
    last_stocktake = None
    if last_session is not None:
        report = state.stocktake.report(int(last_session["id"]))
        last_stocktake = {
            "name": last_session["name"],
            "closed_at": last_session["closed_at"],
            "missing": report["totals"]["missing"],
            "surplus": report["totals"]["surplus"],
        }
    return {
        "totals": state.catalog.stats(),
        "distributions": {
            column: [
                {"value": value, "count": count}
                for value, count in state.catalog.distribution(column)
            ]
            for column in ("category", "language", "publisher", "review_status")
        },
        "growth": growth,
        "loans": state.loans.stats(),
        "discards": state.discards.list_discards(limit=1)[1],
        "last_stocktake": last_stocktake,
    }
