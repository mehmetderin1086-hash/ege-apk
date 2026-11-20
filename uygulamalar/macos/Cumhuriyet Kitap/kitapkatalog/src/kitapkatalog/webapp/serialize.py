"""Domain nesnelerini JSON'a çeviren yardımcılar.

Web arayüzü yalnız gösterime dönük düz sözlükler ister; datetime alanları
ISO-8601 metnine, Path alanları dosya adına indirgenir (tam yol istemciye
sızdırılmaz, görseller kimlik üzerinden ayrı uçtan servis edilir).
"""

from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from kitapkatalog.domain import BookRecord, ImportJob, JobItem, VoiceAlias, VoiceJob
from kitapkatalog.model_manager import EngineStatus

_STATUS_TR = {
    "review": "İncelemede",
    "completed": "Tamamlandı",
}

_JOB_STATUS_TR = {
    "queued": "Sırada",
    "running": "Çalışıyor",
    "paused": "Duraklatıldı",
    "completed": "Tamamlandı",
    "completed_with_errors": "Hatalarla tamamlandı",
    "cancelled": "İptal edildi",
}

_VOICE_PHASE_TR = {
    "ingested": "Alındı",
    "converted": "Ses dönüştürüldü",
    "transcribed": "Yazıya döküldü",
    "segmented": "Kitaplara bölündü",
    "items": "Kitaplar işleniyor",
    "done": "Bitti",
}

STAGE_TR = {
    "discovered": "Keşfedildi",
    "paired": "Eşleştirildi",
    "preprocessed": "Ön işlendi",
    "5_ocr_complete": "5 OCR tamam",
    "reconciled": "Uzlaştırıldı",
    "extracted": "Alanlar çıkarıldı",
    "review": "İncelemede",
    "completed": "Tamamlandı",
    "failed": "Hatalı",
    "cancelled": "İptal edildi",
}


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _name(value: Path | str | None) -> str | None:
    return Path(value).name if value else None


def book_to_dict(
    book: BookRecord, *, detail: bool = False, on_loan: int | None = None
) -> dict[str, Any]:
    authors = "; ".join(
        contributor.name
        for contributor in book.contributors
        if str(contributor.role) == "author"
    )
    others = "; ".join(
        f"{contributor.name} ({contributor.role})"
        for contributor in book.contributors
        if str(contributor.role) != "author"
    )
    # Katalog ISBN'i ISBN13+ISBN10 çifti olarak saklar; gösterimde 13 öncelikli.
    by_scheme = {identifier.scheme: identifier.value for identifier in book.identifiers}
    isbn = by_scheme.get("ISBN13") or by_scheme.get("ISBN10") or by_scheme.get("ISBN")
    active_copies = [copy for copy in book.copies if copy.status == "active"]
    discarded_copies = [copy for copy in book.copies if copy.status == "discarded"]
    locations = sorted({copy.location for copy in active_copies if copy.location})
    data: dict[str, Any] = {
        "edition_id": book.edition_id,
        "title": book.title,
        "subtitle": book.subtitle,
        "isbn": isbn,
        "authors": authors,
        "other_contributors": others,
        "publisher": book.publisher,
        "publication_date": book.publication_date,
        "page_count": book.page_count,
        "language": book.language,
        "category": book.category,
        # Kullanıcı arayüzündeki "adet" daima dolaşımdaki aktif nüshadır.
        # Düşüm kayıtları denetim izi olarak DB'de kalır ve ayrıca raporlanır.
        "copy_count": len(active_copies),
        "active_copies": len(active_copies),
        "discarded_copies": len(discarded_copies),
        "total_copy_records": len(book.copies),
        "location": locations[0] if locations else None,
        "review_status": book.review_status,
        "review_status_label": _STATUS_TR.get(book.review_status, book.review_status),
        "covers": {
            "front": bool(book.front_path),
            "front_inside": bool(book.front_inside_path),
            "back_inside": bool(book.back_inside_path),
            "back": bool(book.back_path),
        },
    }
    if on_loan is not None:
        data["on_loan"] = on_loan
    if detail:
        data.update(
            {
                "original_title": book.original_title,
                "imprint": book.imprint,
                "series": book.series,
                "volume": book.volume,
                "publication_place": book.publication_place,
                "edition_statement": book.edition_statement,
                "printing_number": book.printing_number,
                "printer": book.printer,
                "binding": book.binding,
                "dimensions": book.dimensions,
                "price_amount": book.price_amount,
                "currency": book.currency,
                "blurb": book.blurb,
                "awards": book.awards,
                "quotations": book.quotations,
                "identifiers": [
                    {"scheme": identifier.scheme, "value": identifier.value}
                    for identifier in book.identifiers
                ],
                "contributors": [
                    {"name": contributor.name, "role": str(contributor.role)}
                    for contributor in book.contributors
                ],
                "copies": [
                    {
                        "id": copy.id,
                        "inventory_code": copy.inventory_code,
                        "location": copy.location,
                        "notes": copy.notes,
                        "status": copy.status,
                        "acquisition_method": copy.acquisition_method,
                        "acquisition_date": copy.acquisition_date,
                        "acquisition_price": copy.acquisition_price,
                    }
                    for copy in book.copies
                ],
                "created_at": _iso(book.created_at),
                "updated_at": _iso(book.updated_at),
            }
        )
    return data


def import_job_to_dict(job: ImportJob) -> dict[str, Any]:
    return {
        "id": job.id,
        "name": job.name,
        "status": str(job.status),
        "status_label": _JOB_STATUS_TR.get(str(job.status), str(job.status)),
        "total_items": job.total_items,
        "successful_items": job.successful_items,
        "failed_items": job.failed_items,
        "review_items": job.review_items,
        "terminal_items": job.terminal_items,
        "location": job.location,
        "created_at": _iso(job.created_at),
        "started_at": _iso(job.started_at),
        "finished_at": _iso(job.finished_at),
    }


def job_item_to_dict(item: JobItem) -> dict[str, Any]:
    return {
        "id": item.id,
        "job_id": item.job_id,
        "pair_key": item.pair_key,
        "stage": str(item.stage),
        "stage_label": STAGE_TR.get(str(item.stage), str(item.stage)),
        "pairing_confidence": item.pairing_confidence,
        "pairing_basis": item.pairing_basis,
        "needs_pair_review": item.needs_pair_review,
        "retry_count": item.retry_count,
        "last_error": item.last_error,
        "edition_id": item.edition_id,
        "location": item.location,
        "faces": {
            "front": _name(item.front_path),
            "front_inside": _name(item.front_inside_path),
            "back_inside": _name(item.back_inside_path),
            "back": _name(item.back_path),
        },
    }


def voice_job_to_dict(job: VoiceJob) -> dict[str, Any]:
    return {
        "id": job.id,
        "name": job.name,
        "status": str(job.status),
        "status_label": _JOB_STATUS_TR.get(str(job.status), str(job.status)),
        "phase": str(job.phase),
        "phase_label": _VOICE_PHASE_TR.get(str(job.phase), str(job.phase)),
        "single_book": job.single_book,
        "language": job.language,
        "total_items": job.total_items,
        "successful_items": job.successful_items,
        "failed_items": job.failed_items,
        "review_items": job.review_items,
        "last_error": job.last_error,
        "created_at": _iso(job.created_at),
        "finished_at": _iso(job.finished_at),
    }


def voice_alias_to_dict(alias: VoiceAlias) -> dict[str, Any]:
    return {
        "id": alias.id,
        "heard": alias.heard,
        "canonical": alias.canonical,
        "field_scope": alias.field_scope,
        "created_at": _iso(alias.created_at),
    }


def engine_status_to_dict(status: EngineStatus) -> dict[str, Any]:
    return {
        "engine_id": status.engine_id,
        "version": status.version,
        "family": status.family,
        "license": status.license,
        "available": status.available,
        "reasons": list(status.reasons),
        "artifact_count": len(status.artifacts),
        "invalid_artifacts": [
            {"path": _name(artifact.path), "reason": artifact.reason}
            for artifact in status.artifacts
            if not artifact.valid
        ],
    }
