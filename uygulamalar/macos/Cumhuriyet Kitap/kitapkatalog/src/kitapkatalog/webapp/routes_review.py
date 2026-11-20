"""Kitap bilgisi incelemesi ve güven kalibrasyonu uçları."""

from __future__ import annotations

import io
import json
import re
import uuid
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import FileResponse, Response

from kitapkatalog.webapp.jobs import WebJob
from kitapkatalog.webapp.serialize import book_to_dict
from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["review"])

_MINIMUM_CALIBRATION_SAMPLES = 200

# consensus.reconcile_results'ın auto_confidence varsayılanıyla aynı çizgide:
# bu eşiğin altındaki okumalar otomatik kabul için yeterince güvenilir
# sayılmaz, kullanıcıya "düşük güvenli" olarak işaretlenir.
_SPAN_REVIEW_THRESHOLD = 0.98
# scheduler.py'nin isbn_conflict sentinel'i: çelişki olduğunda pair'deki tüm
# kimliklere 0.80 güven yazılır (bkz. scheduler.py confidence=0.99/0.80).
_ISBN_TRUSTED_CONFIDENCE = 0.99
_ISBN_SCHEMES = {"ISBN", "ISBN10", "ISBN13"}
_ISBN_SOURCE_TR = {
    "barcode": "Barkod",
    "ocr_corroborated": "OCR (çift motor doğrulaması)",
    "user": "Elle girildi",
    "local_import": "Yerel içe aktarma",
    "voice:whisper": "Sesli kayıt",
}


def _json_list(raw: str | None) -> list[str]:
    try:
        return [str(item) for item in json.loads(raw or "[]")]
    except (TypeError, ValueError):
        return []


def _register_heif_if_needed(path: Path) -> None:
    if path.suffix.lower() not in {".heic", ".heif"}:
        return
    try:
        from pillow_heif import register_heif_opener
    except ImportError:
        return
    register_heif_opener()


def _crop_polygon_bbox(source: Path, polygon: list[list[float]]) -> bytes | None:
    """Poligonun sınırlayıcı kutusunu ±%10 payla kırpıp JPEG bayt döndürür.

    Dejenere (alanı sıfıra yakın/negatif) poligonlarda ``None`` döner.
    """

    from PIL import Image, ImageOps, UnidentifiedImageError

    try:
        xs = [float(point[0]) for point in polygon]
        ys = [float(point[1]) for point in polygon]
    except (TypeError, ValueError, IndexError):
        return None
    if not xs or not ys:
        return None
    left, right = min(xs), max(xs)
    top, bottom = min(ys), max(ys)
    if right - left <= 1.0 or bottom - top <= 1.0:
        return None
    _register_heif_if_needed(source)
    try:
        with Image.open(source) as opened:
            oriented = ImageOps.exif_transpose(opened)
            oriented.load()
            image = oriented.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError):
        return None
    width, height = image.size
    pad_x = (right - left) * 0.10
    pad_y = (bottom - top) * 0.10
    box = (
        max(0, int(left - pad_x)),
        max(0, int(top - pad_y)),
        min(width, int(right + pad_x)),
        min(height, int(bottom + pad_y)),
    )
    if box[2] <= box[0] or box[3] <= box[1]:
        return None
    buffer = io.BytesIO()
    image.crop(box).save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/review/books")
def review_books(
    request: Request,
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> dict[str, Any]:
    state = _state(request)
    total = state.catalog.stats()["review"]
    books = state.catalog.list_books(limit=limit, offset=offset, review_status="review")
    items = []
    for book in books:
        data = book_to_dict(book)
        fingerprints = [
            copy.source_fingerprint or "" for copy in book.copies
        ]
        data["source"] = (
            "Ses" if any(f.startswith("voice:") for f in fingerprints) else "Foto"
        )
        items.append(data)
    return {"items": items, "count": len(items), "total": total, "limit": limit, "offset": offset}


@router.get("/review/{edition_id}")
def review_detail(request: Request, edition_id: int) -> dict[str, Any]:
    from kitapkatalog.domain import UNKNOWN_VALUE
    from kitapkatalog.webapp.routes_books import _EDITABLE_FIELDS

    state = _state(request)
    book = state.catalog.get_book(edition_id)
    if book is None:
        raise HTTPException(status_code=404, detail="Kitap bulunamadı")
    data = book_to_dict(book, detail=True)
    voice_item = state.database.get_voice_item_by_edition(edition_id)
    if voice_item is not None:
        try:
            segments = json.loads(voice_item.transcript_json)
            transcript = " ".join(
                segment.get("text", "") for segment in segments
            ).strip()
        except (ValueError, AttributeError):
            transcript = ""
        data["voice"] = {
            "item_id": voice_item.id,
            "transcript": transcript,
            "has_audio": True,
        }

    reasons: list[str] = []

    # ── OCR kanıtı: uzlaşılmış span'lar (kaynak fotoğraf üzerinde kırpılabilir) ──
    span_rows = state.database.fetchall(
        """
        SELECT cs.id AS span_id, ia.cover_role AS cover_role, cs.text AS text,
               cs.confidence AS confidence, cs.engine_support_json AS engine_evidence_json,
               cs.source_polygon_json AS source_polygon_json
        FROM consensus_span AS cs
        JOIN image_asset AS ia ON ia.id = cs.image_asset_id
        WHERE ia.edition_id = ?
        ORDER BY ia.cover_role, cs.span_index
        """,
        (edition_id,),
    )
    spans = [
        {
            "span_id": f"cs:{int(row['span_id'])}",
            "cover_role": row["cover_role"],
            "text": row["text"],
            "confidence": float(row["confidence"]),
            "engine_evidence": _json_list(row["engine_evidence_json"]),
            "has_polygon": bool(row["source_polygon_json"]),
        }
        for row in span_rows
    ]
    data["spans"] = spans
    low_confidence = sum(1 for span in spans if span["confidence"] < _SPAN_REVIEW_THRESHOLD)
    if low_confidence:
        reasons.append(f"{low_confidence} okuma düşük güvenle işaretlendi")

    # ── Alan alternatifleri: extractor'ın değerlendirdiği tüm adaylar ──
    observation_rows = state.database.fetchall(
        """
        SELECT id, field_path, normalized_value, confidence, cover_role,
               engine_evidence_json, source_polygon_json
        FROM field_observation
        WHERE edition_id = ?
        ORDER BY field_path, confidence DESC, id
        """,
        (edition_id,),
    )
    field_alternatives: dict[str, list[dict[str, Any]]] = {}
    isbn_candidates: list[dict[str, Any]] = []
    for row in observation_rows:
        value = (row["normalized_value"] or "").strip()
        if not value or value == UNKNOWN_VALUE:
            continue
        entry = {
            "value": value,
            "confidence": float(row["confidence"]),
            "engine_evidence": _json_list(row["engine_evidence_json"]),
            "cover_role": row["cover_role"],
            "span_id": f"fo:{int(row['id'])}",
            "has_polygon": bool(row["source_polygon_json"]),
        }
        path = row["field_path"]
        if path.startswith("edition."):
            key = path.removeprefix("edition.")
            if key not in _EDITABLE_FIELDS:
                continue
            current = data.get(key)
            current_text = "" if current is None else str(current).strip()
            if value == current_text:
                continue
            bucket = field_alternatives.setdefault(key, [])
            if len(bucket) < 4 and value not in {item["value"] for item in bucket}:
                bucket.append(entry)
        elif path in {"identifier.isbn_candidate", "identifier.isbn13", "identifier.isbn10"}:
            isbn_candidates.append(entry)
    data["field_alternatives"] = field_alternatives

    # ── ISBN kanıtı: kabul edilmiş kimlikler + OCR adayları ──
    isbn_evidence: list[dict[str, Any]] = []
    accepted_values: set[str] = set()
    for identifier in book.identifiers:
        if identifier.scheme not in _ISBN_SCHEMES:
            continue
        conflict = (
            identifier.confidence is not None
            and identifier.confidence < _ISBN_TRUSTED_CONFIDENCE
        )
        isbn_evidence.append(
            {
                "value": identifier.value,
                "scheme": identifier.scheme,
                "source": identifier.source,
                "source_label": _ISBN_SOURCE_TR.get(identifier.source, identifier.source),
                "confidence": identifier.confidence,
                "accepted": True,
                "conflict": conflict,
            }
        )
        accepted_values.add(identifier.value)
        if conflict:
            reasons.append("ISBN barkod ve OCR arasında çelişkili")
    for candidate in isbn_candidates:
        if candidate["value"] in accepted_values:
            continue
        isbn_evidence.append(
            {
                "value": candidate["value"],
                "scheme": None,
                "source": "ocr",
                "source_label": "OCR adayı (kabul edilmedi)",
                "confidence": candidate["confidence"],
                "accepted": False,
                "conflict": False,
                "engine_evidence": candidate["engine_evidence"],
                "span_id": candidate["span_id"],
            }
        )
        accepted_values.add(candidate["value"])
    if isbn_evidence:
        data["isbn_evidence"] = isbn_evidence

    data["review_reasons"] = reasons
    return data


@router.get("/external-suggestions")
def external_suggestions(request: Request, status: str = "pending") -> list[dict[str, Any]]:
    """`kitapkatalog online-oneri` CLI'sinin doldurduğu dış öneri kuyruğu."""

    state = _state(request)
    where = ""
    params: list[Any] = []
    if status:
        where = "WHERE es.status = ?"
        params.append(status)
    rows = state.database.fetchall(
        f"""
        SELECT es.id, es.isbn13, es.source, es.payload_json, es.fetched_at,
               es.edition_id, es.status, e.title AS edition_title,
               (SELECT GROUP_CONCAT(c.display_name, '; ')
                FROM edition_contributor AS ec
                JOIN contributor AS c ON c.id = ec.contributor_id
                WHERE ec.edition_id = es.edition_id AND ec.role = 'author') AS edition_authors
        FROM external_suggestion AS es
        LEFT JOIN edition AS e ON e.id = es.edition_id
        {where}
        ORDER BY es.fetched_at DESC, es.id DESC
        """,
        params,
    )
    items: list[dict[str, Any]] = []
    for row in rows:
        try:
            payload = json.loads(row["payload_json"])
        except (TypeError, ValueError):
            payload = {}
        matched_title = None
        if row["edition_title"]:
            matched_title = str(row["edition_title"])
            if row["edition_authors"]:
                matched_title = f"{matched_title} ({row['edition_authors']})"
        items.append(
            {
                "id": int(row["id"]),
                "isbn13": row["isbn13"],
                "source": row["source"],
                "payload": payload,
                "fetched_at": row["fetched_at"],
                "edition_id": row["edition_id"],
                "status": row["status"],
                "matched_title": matched_title,
            }
        )
    return items


@router.post("/external-suggestions/{suggestion_id}/dismiss")
def dismiss_external_suggestion(request: Request, suggestion_id: int) -> dict[str, Any]:
    state = _state(request)
    with state.database.transaction(immediate=True) as connection:
        row = connection.execute(
            "SELECT status FROM external_suggestion WHERE id = ?", (suggestion_id,)
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Öneri bulunamadı")
        if row["status"] == "pending":
            connection.execute(
                "UPDATE external_suggestion SET status = 'dismissed' WHERE id = ?",
                (suggestion_id,),
            )
            final_status = "dismissed"
        else:
            final_status = str(row["status"])
    return {"id": suggestion_id, "status": final_status}


@router.get("/review/{edition_id}/span-crop/{span_id}")
def review_span_crop(request: Request, edition_id: int, span_id: str) -> Response:
    """Bir kanıt span'ının kaynak fotoğraftaki bölgesini kırpıp JPEG döndürür."""

    state = _state(request)
    kind, _, raw_id = span_id.partition(":")
    try:
        row_id = int(raw_id)
    except ValueError:
        raise HTTPException(status_code=404, detail="Kanıt görseli yok") from None

    if kind == "cs":
        row = state.database.fetchone(
            """
            SELECT cs.source_polygon_json AS polygon_json, ia.source_path AS source_path
            FROM consensus_span AS cs
            JOIN image_asset AS ia ON ia.id = cs.image_asset_id
            WHERE cs.id = ? AND ia.edition_id = ?
            """,
            (row_id, edition_id),
        )
    elif kind == "fo":
        row = state.database.fetchone(
            """
            SELECT fo.source_polygon_json AS polygon_json, ia.source_path AS source_path
            FROM field_observation AS fo
            JOIN image_asset AS ia
              ON ia.item_id = fo.item_id AND ia.cover_role = fo.cover_role
            WHERE fo.id = ? AND fo.edition_id = ?
            """,
            (row_id, edition_id),
        )
    else:
        row = None

    if row is None or not row["polygon_json"]:
        raise HTTPException(status_code=404, detail="Kanıt görseli yok")
    try:
        polygon = json.loads(row["polygon_json"])
    except (TypeError, ValueError):
        raise HTTPException(status_code=404, detail="Kanıt görseli yok") from None

    try:
        source = Path(row["source_path"]).resolve()
        allowed = source.is_file() and source.is_relative_to(state.paths.root.resolve())
    except OSError:
        allowed = False
        source = None
    if not allowed or source is None:
        raise HTTPException(status_code=404, detail="Kanıt görseli yok")

    crop = _crop_polygon_bbox(source, polygon)
    if crop is None:
        raise HTTPException(status_code=404, detail="Kanıt görseli yok")
    return Response(content=crop, media_type="image/jpeg")


@router.post("/review/{edition_id}/save")
def review_save(request: Request, edition_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    from kitapkatalog.webapp.routes_books import _EDITABLE_FIELDS, _positive_int

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
    isbn_raw: str | None = None
    if "isbn" in payload:
        isbn_raw = (payload["isbn"] or "").strip()
        # set_isbn rakamsız girdiyi boş sayıp mevcut ISBN'i siler; yazım
        # hatası sessiz silmeye dönüşmesin (routes_books.update_book ile aynı kural).
        if isbn_raw and not re.sub(r"[^0-9Xx]", "", isbn_raw):
            raise HTTPException(status_code=400, detail=f"ISBN rakam içermiyor: {isbn_raw!r}")
    if payload.get("approve", True):
        changes["review_status"] = "completed"
    with state.database.transaction(immediate=True) as connection:
        if "isbn" in payload:
            state.catalog.set_isbn(edition_id, isbn_raw or None)
        if changes:
            state.catalog.update_book(edition_id, changes, user_edit=True)
        if "location" in payload:
            state.catalog.set_location(
                edition_id, (payload["location"] or "").strip() or None
            )
        book = state.catalog.get_book(edition_id)
        if book is None:
            raise HTTPException(status_code=404, detail="Kitap bulunamadı")
        # Kullanıcı inceleme formunu kaydettiğinde bu baskıya bağlı bekleyen
        # dış öneriler kabul edilmiş sayılır.
        connection.execute(
            "UPDATE external_suggestion SET status = 'accepted' "
            "WHERE edition_id = ? AND status = 'pending'",
            (edition_id,),
        )
    return book_to_dict(book, detail=True)


@router.get("/review/{edition_id}/audio")
def review_audio(request: Request, edition_id: int) -> FileResponse:
    """Ses kaynaklı kaydın söylem kesitini WAV olarak döndür."""

    state = _state(request)
    item = state.database.get_voice_item_by_edition(edition_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Bu kayda ait ses yok")
    job = state.database.get_voice_job(item.job_id)
    if job is None or job.canonical_wav_path is None:
        raise HTTPException(status_code=404, detail="Kanonik ses dosyası yok")
    try:
        canonical = Path(job.canonical_wav_path).resolve()
        if not canonical.is_file() or not canonical.is_relative_to(
            state.paths.voice_assets.resolve()
        ):
            raise HTTPException(status_code=404, detail="Kanonik ses dosyası yok")
    except OSError as exc:
        raise HTTPException(status_code=404, detail="Kanonik ses dosyası yok") from exc
    from kitapkatalog.audio import slice_wav

    target = state.paths.derivatives / "web_audio" / f"{item.job_id}-{item.id}.wav"
    if not target.is_file():
        slice_wav(
            canonical,
            target,
            start_sample=item.start_sample,
            end_sample=item.end_sample,
        )
    return FileResponse(target, media_type="audio/wav")


# ------------------------------------------------------------- kalibrasyon


@router.get("/calibration/status")
def calibration_status(request: Request) -> dict[str, Any]:
    state = _state(request)
    labels = state.database.review_label_count()
    profile = state.ctx.models.optional_calibration_profile()
    job = state.registry.get("calibration")
    return {
        "label_count": labels,
        "minimum_samples": _MINIMUM_CALIBRATION_SAMPLES,
        "profile_trusted": bool(profile.trusted) if profile is not None else False,
        "profile_exists": profile is not None,
        "job": job.to_dict() if job else None,
    }


@router.post("/calibration/fit", status_code=202)
def calibration_fit(request: Request) -> dict[str, Any]:
    state = _state(request)

    def run(job: WebJob) -> dict[str, Any]:
        from kitapkatalog.calibration import fit_isotonic_profile, samples_from_reviews

        job.message = "İnceleme etiketleri toplanıyor…"
        labels = state.database.review_labels()
        job.message = f"{len(labels)} etiketle profil üretiliyor…"
        profile = fit_isotonic_profile(
            samples_from_reviews(labels),
            version=f"web-inceleme-{len(labels)}-{uuid.uuid4().hex[:6]}",
        )
        destination = state.ctx.models.local_calibration_path
        profile.save(destination)
        return {"trusted": profile.trusted, "labels": len(labels)}

    web_job = state.registry.start("calibration", "Kalibrasyon profili üretimi", run)
    return web_job.to_dict()
