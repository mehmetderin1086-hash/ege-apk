"""İçe aktarma, OCR işleme kuyruğu ve eşleştirme onayı uçları."""

from __future__ import annotations

import threading
import uuid
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from anyio import to_thread
from fastapi import APIRouter, HTTPException, Request, Response
from fastapi.responses import FileResponse

# ``request.form()`` Starlette'in UploadFile'ını üretir; FastAPI'ninki onun ALT
# sınıfıdır, dolayısıyla alt sınıfa karşı isinstance her zaman False döner ve
# yüklenen dosyalar sessizce "dosya yok" sayılırdı.
from starlette.datastructures import UploadFile
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.formparsers import MultiPartException

from kitapkatalog.capacity import estimate_import_capacity, require_capacity
from kitapkatalog.database import StateConflictError
from kitapkatalog.documents import (
    DocumentInputError,
    build_single_book_scan,
    expand_bulk_documents,
    folder_locations,
)
from kitapkatalog.domain import StorageMode
from kitapkatalog.images import SUPPORTED_SUFFIXES as _QUALITY_CHECKABLE_SUFFIXES
from kitapkatalog.images import ImageProcessingError, assess_upload_quality
from kitapkatalog.importzip import ZipExpansionError, expand_zip_upload
from kitapkatalog.pairing import pair_cover_files
from kitapkatalog.webapp.jobs import WebJob
from kitapkatalog.webapp.serialize import import_job_to_dict, job_item_to_dict
from kitapkatalog.webapp.state import WebState
from kitapkatalog.webapp.uploads import (
    UploadBudget,
    cleanup_staging,
    safe_upload_name,
    stage_upload,
    staging_folder,
)

router = APIRouter(tags=["imports"])

_UPLOAD_SUFFIXES = {
    ".jpg", ".jpeg", ".png", ".webp", ".heic", ".heif", ".tif", ".tiff", ".bmp", ".pdf", ".zip",
}

_MAX_IMPORT_FILES = 2_000
_MAX_IMPORT_FILE_BYTES = 512 * 1024**2
_MAX_IMPORT_BATCH_BYTES = 8 * 1024**3

_FACES = ("front", "front_inside", "back_inside", "back")
_TRUE_VALUES = {"1", "true", "on", "yes", "evet", "doğru", "dogru"}


def _state(request: Request) -> WebState:
    return request.app.state.web


def _flag(value: Any) -> bool:
    return str(value or "").strip().casefold() in _TRUE_VALUES


def _shelf_name(value: Any) -> str | None:
    """Dolap adı; `copy.location` serbest metniyle birebir eşleşmesi gerekir."""

    if value is None:
        return None
    if not isinstance(value, str):
        # JSON gövdesinden gelen sözlük/liste, str() ile Python temsiline
        # dönüşüp dolap adı diye saklanmamalı.
        raise HTTPException(status_code=400, detail="Dolap adı metin olmalıdır")
    cleaned = " ".join(value.split())
    if len(cleaned) > 120:
        raise HTTPException(status_code=400, detail="Dolap adı en çok 120 karakter olabilir")
    return cleaned or None


def _register_shelves(state: WebState, names: Iterable[str]) -> list[str]:
    """Yeni dolap adlarını raf haritasına ekler; iş bunun için başarısız olmaz."""

    known = {record.name for record in state.shelves.list()}
    created: list[str] = []
    for name in dict.fromkeys(filter(None, names)):
        if name in known:
            continue
        try:
            state.shelves.create(name)
        except (StateConflictError, ValueError):
            continue
        created.append(name)
    return created


async def _parse_form(request: Request, *, max_files: int, max_fields: int) -> Any:
    """Çok parçalı gövdeyi Türkçe hata sözleşmesiyle ayrıştırır.

    Starlette sınır aşımını kendisi İngilizce metinli bir HTTPException'a
    çevirir; arayüzün tamamı Türkçe olduğu için mesaj burada karşılanır.
    """

    try:
        return await request.form(max_files=max_files, max_fields=max_fields)
    except (MultiPartException, StarletteHTTPException) as error:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Yükleme kabul edilmedi: bir istekte en fazla {max_files} dosya "
                f"ve {max_fields} alan gönderilebilir"
            ),
        ) from error


def _quality_report(paths: Iterable[Path]) -> list[dict[str, Any]]:
    """Ön kontrol uyarıları; yalnız görüntüler için (PDF/ZIP hariç tutulur).

    ``stage_upload`` içeriği zaten doğruladığından burada bir dosyanın
    açılamaması beklenmez; yine de tek bozuk dosya bütün raporu düşürmesin
    diye sessizce atlanır. Uyarısız dosyalar rapora hiç girmez.
    """

    report: list[dict[str, Any]] = []
    for path in paths:
        if path.suffix.lower() not in _QUALITY_CHECKABLE_SUFFIXES:
            continue
        try:
            quality = assess_upload_quality(path)
        except ImageProcessingError:
            continue
        if not quality.warnings:
            continue
        report.append(
            {
                "file": path.name,
                "warnings": list(quality.warnings),
                "blur_score": quality.blur_score,
                "width": quality.width,
                "height": quality.height,
            }
        )
    return report


def _enqueue(
    state: WebState,
    *,
    name: str,
    pairs: tuple,
    key: str,
    location: str | None = None,
    locations: Mapping[str, str] | None = None,
) -> Any:
    from kitapkatalog.cli import _enqueue_pairs, _pair_image_paths

    estimate = estimate_import_capacity(
        _pair_image_paths(pairs),
        data_root=state.paths.root,
        model_root=state.paths.models,
        storage_mode=StorageMode.MANAGED_COPY,
    )
    require_capacity(estimate)
    return _enqueue_pairs(
        state.database,
        name=name,
        pairs=pairs,
        storage_mode=StorageMode.MANAGED_COPY,
        idempotency_key=key,
        location=location,
        locations=locations,
    )


@router.post("/imports/single", status_code=201)
async def import_single(request: Request, response: Response) -> dict[str, Any]:
    """Bir kitabı dört ayrı yüzden ya da dört içerikli tek belgeden ekler."""

    state = _state(request)
    form = await _parse_form(request, max_files=4, max_fields=12)
    documents = [item for item in form.getlist("document") if isinstance(item, UploadFile)]
    if documents:
        # Toplu aktarımdaki gibi: dört yüz tek dosyada (4 sayfalık PDF) olabilir.
        if len(documents) not in {1, 4}:
            raise HTTPException(
                status_code=400,
                detail=(
                    "Tek kitap için ya dört sayfalık tek belge ya da sırayla "
                    "dört belge seçin."
                ),
            )
        labels = ["belge"] if len(documents) == 1 else list(_FACES)
    else:
        documents = []
        for face in _FACES:
            upload = form.get(face)
            if not isinstance(upload, UploadFile):
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "Dört yüz de gereklidir: ön, ön iç, arka iç, arka kapak. "
                        "Ya da dört sayfalık tek belge yükleyin."
                    ),
                )
            documents.append(upload)
        labels = list(_FACES)
    shelf = _shelf_name(form.get("shelf"))
    preflight = _flag(form.get("preflight"))
    batch = uuid.uuid4().hex[:12]
    staging = state.upload_root / batch
    staging.mkdir(parents=True)
    budget = UploadBudget(_MAX_IMPORT_BATCH_BYTES)
    try:
        stored = [
            await stage_upload(
                staging,
                upload,
                allowed_suffixes=_UPLOAD_SUFFIXES,
                maximum_bytes=_MAX_IMPORT_FILE_BYTES,
                kind="document",
                budget=budget,
                target_name=f"{label}-{safe_upload_name(upload.filename)}",
            )
            for label, upload in zip(labels, documents, strict=True)
        ]
        if preflight:
            # Yalnızca kalite raporu istenmiştir: kuyruğa alınmaz, staging
            # hemen temizlenir.
            quality_warnings = await to_thread.run_sync(_quality_report, stored)
            cleanup_staging(staging, root=state.upload_root)
            response.status_code = 200
            return {"preflight": True, "quality_warnings": quality_warnings}

        name = str(form.get("name") or "").strip() or "Tek kitap - dört yüz"

        def prepare_single() -> tuple[Any, list[dict[str, Any]]]:
            quality_warnings = _quality_report(stored)
            try:
                scan = build_single_book_scan(stored, state.paths.derivatives / "pdf-pages")
            except DocumentInputError as error:
                raise HTTPException(status_code=400, detail=str(error)) from error
            job = _enqueue(
                state, name=name, pairs=(scan,), key=f"web:{batch}", location=shelf
            )
            return job, quality_warnings

        job, quality_warnings = await to_thread.run_sync(prepare_single)
    except BaseException:
        cleanup_staging(staging, root=state.upload_root)
        raise
    return {
        "job": import_job_to_dict(job),
        "books": 1,
        "shelf": shelf,
        "quality_warnings": quality_warnings,
        "shelves_created": await to_thread.run_sync(
            _register_shelves, state, [shelf] if shelf else []
        ),
    }


@router.post("/imports/bulk", status_code=201)
async def import_bulk(request: Request) -> dict[str, Any]:
    """Bir partiyi kuyruğa alır; parti ya da klasör başına dolap atanabilir."""

    state = _state(request)
    form = await _parse_form(request, max_files=_MAX_IMPORT_FILES, max_fields=12)
    uploads = [item for item in form.getlist("files") if isinstance(item, UploadFile)]
    if not uploads:
        raise HTTPException(status_code=400, detail="Dosya yüklenmedi")
    if len(uploads) > _MAX_IMPORT_FILES:
        raise HTTPException(
            status_code=413,
            detail=f"Bir yüklemede en fazla {_MAX_IMPORT_FILES} dosya kabul edilir",
        )
    shelf = _shelf_name(form.get("shelf"))
    folder_shelves = _flag(form.get("folder_shelf"))
    batch = uuid.uuid4().hex[:12]
    staging = state.upload_root / batch
    staging.mkdir(parents=True)
    budget = UploadBudget(_MAX_IMPORT_BATCH_BYTES)
    try:
        stored = []
        shelf_names: dict[Path, str] = {}
        for upload in uploads:
            # Klasör seçiminde tarayıcı göreli yolu dosya adı olarak gönderir;
            # eşleştirme klasör bazlı gruplandığı için yapı korunur.  Ayrı
            # klasörler staging'de birbirine karışmasın diye dizin adı özet
            # taşır; dolap adı okunur kısımdır.
            folder = staging_folder(upload.filename)
            directory = staging / folder[0] if folder else staging
            if folder:
                shelf_names[directory] = folder[1]
            stored.append(
                await stage_upload(
                    directory,
                    upload,
                    allowed_suffixes=_UPLOAD_SUFFIXES,
                    maximum_bytes=_MAX_IMPORT_FILE_BYTES,
                    kind="document",
                    budget=budget,
                    target_name=safe_upload_name(upload.filename),
                )
            )
        name = str(form.get("name") or "").strip() or f"Web toplu aktarım {batch[:6]}"

        def prepare_bulk() -> tuple[
            Any, Any, tuple[Any, ...], dict[str, str], Any, list[dict[str, Any]], list[dict[str, Any]]
        ]:
            documents = [path for path in stored if path.suffix.lower() != ".zip"]
            zip_sources = [path for path in stored if path.suffix.lower() == ".zip"]
            zip_expanded: list[dict[str, Any]] = []
            for index, zip_path in enumerate(zip_sources, start=1):
                zip_root = staging / f"zip-{index}"
                # Kalan bütçe: bir zip tek başına partinin sınırını delemez.
                remaining_files = max(0, _MAX_IMPORT_FILES - len(documents))
                remaining_bytes = max(0, _MAX_IMPORT_BATCH_BYTES - budget.used)
                try:
                    expansion = expand_zip_upload(
                        zip_path,
                        zip_root,
                        allowed_suffixes=_UPLOAD_SUFFIXES - {".zip"},
                        max_members=remaining_files,
                        max_total_bytes=remaining_bytes,
                        max_file_bytes=_MAX_IMPORT_FILE_BYTES,
                    )
                except ZipExpansionError as error:
                    raise HTTPException(
                        status_code=413, detail=f"{zip_path.name}: {error}"
                    ) from error
                # Zip'in kök dizinindeki dosyalar (klasörsüz) staging'in
                # dahili "zip-N" adını dolap sanmasın diye boş ada eşlenir.
                shelf_names[zip_root] = ""
                for extracted in expansion.files:
                    budget.consume(extracted.stat().st_size)
                    relative = extracted.parent.relative_to(zip_root)
                    if relative.parts:
                        # Yalnız İLK SEVİYE klasör dolap adı olur; daha derin
                        # iç içe klasörler aynı ilk seviyeye eşlenir.
                        shelf_names[extracted.parent] = relative.parts[0]
                documents.extend(expansion.files)
                if len(documents) > _MAX_IMPORT_FILES:
                    raise HTTPException(
                        status_code=413,
                        detail=f"Bir yüklemede en fazla {_MAX_IMPORT_FILES} dosya kabul edilir",
                    )
                zip_expanded.append(
                    {
                        "file": zip_path.name,
                        "files": len(expansion.files),
                        "rejected": [
                            {"file": member, "reason": reason}
                            for member, reason in expansion.rejected
                        ],
                    }
                )

            quality_warnings = _quality_report(documents)
            expanded_result = expand_bulk_documents(
                documents, state.paths.derivatives / "pdf-pages"
            )
            pairing_result = pair_cover_files(
                expanded_result.images, infer_sequence=True, require_four_surfaces=True
            )
            paired = (*expanded_result.four_page_books, *pairing_result.pairs)
            if not paired:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "Hiç kitap eşleştirilemedi. Dosya adları sıralı olmalı "
                        "(ör. kitap1-1.jpg … kitap1-4.jpg), her kitap ayrı bir "
                        "klasörde olmalı ya da sayfa sayısı 4'ün katı olan bir PDF "
                        "yüklenmelidir."
                    ),
                )
            by_folder = (
                folder_locations(
                    paired, expanded_result, root=staging, names=shelf_names
                )
                if folder_shelves
                else {}
            )
            queued = _enqueue(
                state,
                name=name,
                pairs=paired,
                key=f"web:{batch}",
                location=shelf,
                locations=by_folder,
            )
            return expanded_result, pairing_result, paired, by_folder, queued, zip_expanded, quality_warnings

        (
            expanded,
            pairing,
            pairs,
            by_folder,
            job,
            zip_expanded,
            quality_warnings,
        ) = await to_thread.run_sync(prepare_bulk)
    except BaseException:
        cleanup_staging(staging, root=state.upload_root)
        raise
    used_shelves = sorted({*by_folder.values(), *([shelf] if shelf else [])})
    return {
        "job": import_job_to_dict(job),
        "books": len(pairs),
        "shelf": shelf,
        "folder_shelves": sorted(set(by_folder.values())),
        "books_without_shelf": (
            0 if shelf else sum(1 for pair in pairs if pair.pair_key not in by_folder)
        ),
        "shelves_created": await to_thread.run_sync(_register_shelves, state, used_shelves),
        "zip_expanded": zip_expanded,
        "quality_warnings": quality_warnings,
        "split_documents": [
            {"file": Path(path).name, "books": books}
            for path, books in expanded.split_documents
        ],
        "unpaired": [Path(p).name for p in pairing.unpaired],
        "ambiguous": [
            {"reason": issue.reason, "files": [c.name for c in issue.candidates]}
            for issue in pairing.ambiguous
        ],
        "rejected": [
            {"file": Path(path).name, "reason": reason}
            for path, reason in expanded.rejected
        ],
    }


@router.get("/imports")
def list_jobs(request: Request) -> list[dict[str, Any]]:
    return [import_job_to_dict(job) for job in _state(request).database.list_import_jobs()]


@router.get("/imports/{job_id}")
def job_detail(request: Request, job_id: str) -> dict[str, Any]:
    state = _state(request)
    job = state.database.get_import_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="İçe aktarma işi bulunamadı")
    progress = state.database.job_progress(job_id)
    failed = state.database.list_job_items(job_id, stage="failed", limit=100)
    return {
        "job": import_job_to_dict(job),
        "stages": progress.get("stages"),
        "engines": progress.get("engines"),
        "shelves": state.database.job_location_summary(job_id),
        # Çok kitaplı PDF'ten bölünen kitaplar yükleme raporundan sonra da
        # görünür kalsın: yanlış bölünmüş bir tarama başka türlü fark edilmez.
        "split_books": int(
            state.database.fetchone(
                """
                SELECT COUNT(*) AS total FROM job_item
                WHERE job_id = ? AND pairing_basis LIKE 'bulk_multi_book_pdf%'
                """,
                (job_id,),
            )["total"]
        ),
        "failed_items": [job_item_to_dict(item) for item in failed],
    }


@router.post("/imports/{job_id}/pause")
def pause_job(request: Request, job_id: str) -> dict[str, Any]:
    return import_job_to_dict(_state(request).database.pause_job(job_id))


@router.post("/imports/{job_id}/resume")
def resume_job(request: Request, job_id: str) -> dict[str, Any]:
    return import_job_to_dict(_state(request).database.resume_job(job_id))


@router.post("/imports/{job_id}/cancel")
def cancel_job(request: Request, job_id: str) -> dict[str, Any]:
    return import_job_to_dict(_state(request).database.cancel_job(job_id))


@router.post("/imports/{job_id}/retry-failed")
def retry_failed(request: Request, job_id: str) -> dict[str, Any]:
    state = _state(request)
    requeued, remaining = state.database.retry_failed_items(job_id)
    job = state.database.get_import_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="İçe aktarma işi bulunamadı")
    return {"requeued": requeued, "remaining": remaining, "job": import_job_to_dict(job)}


@router.patch("/imports/{job_id}")
async def update_job(request: Request, job_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    """İşin dolabını değiştirir; işlenmeye başlamamış kitaplar oraya girer."""

    state = _state(request)
    if "shelf" not in payload:
        raise HTTPException(status_code=400, detail="Değiştirilecek alan verilmedi")
    shelf = _shelf_name(payload.get("shelf"))
    job = await to_thread.run_sync(state.database.set_job_location, job_id, shelf)
    return {
        "job": import_job_to_dict(job),
        "shelves_created": await to_thread.run_sync(
            _register_shelves, state, [shelf] if shelf else []
        ),
    }


@router.delete("/imports/{job_id}", status_code=204)
def delete_job(request: Request, job_id: str) -> None:
    _state(request).database.delete_import_job(job_id)


@router.post("/imports/items/{item_id}/retry")
def retry_item(request: Request, item_id: int) -> dict[str, Any]:
    return job_item_to_dict(_state(request).database.retry_failed_item(item_id))


# ------------------------------------------------------------- OCR işleme


@router.post("/process/start", status_code=202)
def start_processing(request: Request, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    state = _state(request)
    job_id = (payload or {}).get("job_id")
    worker_prefix = f"web-{uuid.uuid4().hex[:8]}"

    def run(job: WebJob) -> dict[str, Any]:
        job.message = "Modeller doğrulanıyor ve işlem hattı kuruluyor…"
        scheduler = state.ctx.processing_scheduler(cancel=job.stop_event)
        job.message = "5 OCR işleme başladı"
        counter_lock = threading.Lock()
        processed = 0
        worker_errors: list[str] = []

        def worker(index: int) -> None:
            nonlocal processed
            try:
                while not job.stop_event.is_set():
                    result = scheduler.run_next(f"{worker_prefix}-{index}", job_id=job_id)
                    if result is None:
                        return
                    with counter_lock:
                        processed += 1
                        job.progress_done = processed
                        job.message = f"{processed} kitap işlendi"
            except Exception as exc:
                # Worker ölümü sessiz başarıya dönüşmesin: hata işe raporlanır.
                with counter_lock:
                    worker_errors.append(f"{type(exc).__name__}: {exc}")

        threads = [
            threading.Thread(target=worker, args=(index,), daemon=True)
            for index in range(scheduler.limits.book_workers)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        if worker_errors:
            raise RuntimeError(
                f"{processed} kitap işlendi, sonrasında işçi hatası: " + "; ".join(worker_errors)
            )
        return {"processed": processed}

    web_job = state.registry.start("process", "5 OCR işleme", run)
    return web_job.to_dict()


@router.post("/process/stop")
def stop_processing(request: Request) -> dict[str, Any]:
    job = _state(request).registry.request_stop("process")
    if job is None:
        raise HTTPException(status_code=404, detail="Çalışan işlem yok")
    return job.to_dict()


@router.get("/process/status")
def process_status(request: Request) -> dict[str, Any]:
    job = _state(request).registry.get("process")
    return job.to_dict() if job else {"status": "idle"}


# ------------------------------------------------------- eşleştirme onayı


@router.get("/pair-reviews")
def pair_reviews(request: Request, job_id: str | None = None) -> list[dict[str, Any]]:
    items = _state(request).database.list_pending_pair_reviews(job_id=job_id)
    return [job_item_to_dict(item) for item in items]


@router.post("/pair-reviews/{item_id}")
def decide_pair(request: Request, item_id: int, payload: dict[str, Any]) -> dict[str, Any]:
    approved = bool(payload.get("approved"))
    item = _state(request).database.approve_pair(item_id, approved=approved)
    return job_item_to_dict(item)


@router.get("/items/{item_id}/image/{face}")
def item_image(request: Request, item_id: int, face: str, thumb: bool = False) -> FileResponse:
    state = _state(request)
    item = state.database.get_job_item(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Öğe bulunamadı")
    path = {
        "front": item.front_path,
        "front_inside": item.front_inside_path,
        "back_inside": item.back_inside_path,
        "back": item.back_path,
    }.get(face)
    try:
        source = Path(path).resolve() if path is not None else None
        allowed = bool(
            source
            and source.is_file()
            and source.is_relative_to(state.paths.root.resolve())
        )
    except OSError:
        allowed = False
        source = None
    if not allowed or source is None:
        raise HTTPException(status_code=404, detail="Görsel yok")
    if thumb:
        from kitapkatalog.webapp.routes_books import _thumbnail

        return FileResponse(_thumbnail(state, source), media_type="image/jpeg")
    return FileResponse(source)
