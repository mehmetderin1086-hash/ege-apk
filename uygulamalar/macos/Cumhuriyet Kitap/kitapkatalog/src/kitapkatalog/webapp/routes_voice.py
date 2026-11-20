"""Sesli kayıt: tarayıcı kaydı analizi, kayıt onayı ve toplu ses işleri.

Tarayıcı MediaRecorder çıktısı (webm/opus, mp4/aac…) sunucuda PyAV ile
kanonik 16 kHz mono WAV'a çevrilir; whisper yalnız bu kanonik biçimi görür.
Analiz whisper model yüklemesi yüzünden uzun sürebileceğinden iş yuvasında
koşar, sonuç `pending_id` ile bekletilir ve kayıt onayında kullanılır.
"""

from __future__ import annotations

import uuid
from pathlib import Path
from typing import Any

from anyio import to_thread
from fastapi import APIRouter, HTTPException, Request, UploadFile

# Rota parametresi FastAPI'nin alt sınıfını gerektirir, ancak ``request.form()``
# Starlette'in taban sınıfını üretir; isinstance kontrolü tabana karşı
# yapılmalıdır, yoksa yüklenen dosyalar sessizce görünmez olur.
from starlette.datastructures import UploadFile as FormUploadFile

from kitapkatalog.audio import transcode_to_wav16k
from kitapkatalog.settings import AppSettings
from kitapkatalog.voice_protocol import fold_text
from kitapkatalog.voice_scheduler import build_voice_scheduler
from kitapkatalog.webapp.jobs import WebJob
from kitapkatalog.webapp.serialize import voice_alias_to_dict, voice_job_to_dict
from kitapkatalog.webapp.state import WebState
from kitapkatalog.webapp.uploads import UploadBudget, safe_upload_name, stage_upload

router = APIRouter(tags=["voice"])

_AUDIO_SUFFIXES = {".webm", ".mp4", ".m4a", ".mp3", ".wav", ".aac", ".flac", ".ogg", ".opus"}

_MAX_AUDIO_FILE_BYTES = 200 * 1024**2
_MAX_AUDIO_ANALYZE_BYTES = 100 * 1024**2
_MAX_AUDIO_BATCH_BYTES = 2 * 1024**3
_MAX_AUDIO_BATCH_FILES = 500
_MAX_VOICE_COPIES = 1_000
_BATCH_LANGUAGES = frozenset({"tr", "auto", "en"})

_FORM_FIELDS = (
    "isbn", "title", "author", "publisher", "publication_date",
    "page_count", "language", "category", "location",
)

# Sözlüğe öğrenilebilir düzeltmeler yalnız bu metinsel alanlar için önerilir
# (voice_refine.alias_suggestions'ın uyguladığı alan kümesiyle aynı).
_LEARNABLE_FIELDS = ("title", "author", "publisher")
_FIELD_SCOPES = frozenset({"any", "title", "author", "publisher"})
_REFIELD_FIELDS = frozenset({"title", "author", "publisher"})
_REFIELD_LABELS_TR = {"title": "Başlık", "author": "Yazar", "publisher": "Yayınevi"}


def _state(request: Request) -> WebState:
    return request.app.state.web


def _result_to_form(result) -> dict[str, Any]:
    values = {field: result.value_of(field) or "" for field in _FORM_FIELDS}
    if result.isbn:
        values["isbn"] = result.isbn
    return {
        "values": values,
        "copy_count": result.copy_count,
        "review_reasons": list(result.review_reasons),
        "suggestions": list(result.suggestions),
    }


def _learnable_corrections(original_result, values: dict[str, str]) -> list[dict[str, str]]:
    """Transkript iddiasıyla kullanıcının kaydettiği değer farklıysa aday üret.

    Otomatik yazmaz — yalnız arayüze "sözlüğe eklensin mi?" önerisi taşır.
    """

    learnable: list[dict[str, str]] = []
    for field in _LEARNABLE_FIELDS:
        heard_raw = (original_result.value_of(field) or "").strip()
        canonical = (values.get(field) or "").strip()
        if not heard_raw or not canonical:
            continue
        if fold_text(heard_raw) == fold_text(canonical):
            continue
        learnable.append({"field": field, "heard": fold_text(heard_raw), "canonical": canonical})
    return learnable


def _delete_unapproved_audio(pending: Any) -> None:
    """Remove a voice artifact only when no approved JSON sidecar exists."""

    sidecar = pending.wav_path.with_suffix(".json")
    if not sidecar.exists():
        pending.wav_path.unlink(missing_ok=True)


@router.post("/voice/analyze", status_code=202)
async def analyze(request: Request, file: UploadFile) -> dict[str, Any]:
    state = _state(request)
    suffix = Path(file.filename or "kayit.webm").suffix.lower() or ".webm"
    if suffix not in _AUDIO_SUFFIXES:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen ses türü: {suffix}")
    staging = state.upload_root / "voice"
    staging.mkdir(parents=True, exist_ok=True)
    raw = await stage_upload(
        staging,
        file,
        allowed_suffixes=_AUDIO_SUFFIXES,
        maximum_bytes=_MAX_AUDIO_ANALYZE_BYTES,
        kind="audio",
        target_name=f"{uuid.uuid4().hex}{suffix}",
    )

    def run(job: WebJob) -> dict[str, Any]:
        job.message = "Ses kanonik WAV'a çevriliyor…"
        # ".wav" yüklemesinde with_suffix aynı yolu üretir; hedef adı ayrık tut
        # ki kaynağı silerken kanonik dosya silinmesin.
        wav = raw.with_name(f"{raw.stem}-canonical.wav")
        try:
            transcode_to_wav16k(raw, wav)
            job.message = (
                "Konuşma yazıya dökülüyor (ilk seferde model yüklemesi sürebilir)…"
            )
            session = state.voice_session()
            pending = session.analyze(wav)
            result = pending.result
            job.message = "Benzer kayıtlar aranıyor…"
            title = result.value_of("title") or ""
            authors = result.value_of("author") or ""
            similar = session.similar_books(title, authors)
            pending_id = uuid.uuid4().hex[:12]
            with state.pending_lock:
                state.pending_utterances[pending_id] = pending
                # Bellek büyümesin: son 20 bekleyen söylemden eskilerini at.
                while len(state.pending_utterances) > 20:
                    evicted = state.pending_utterances.pop(next(iter(state.pending_utterances)))
                    _delete_unapproved_audio(evicted)
            return {
                "pending_id": pending_id,
                "transcript": pending.transcript,
                **_result_to_form(result),
                "similar": [
                    {
                        "edition_id": book.edition_id,
                        "title": book.title,
                        "authors": book.authors,
                        "title_score": round(book.title_score, 2),
                    }
                    for book in similar
                ],
                "auto_save_allowed": session.auto_save_allowed(result, similar),
            }
        except BaseException:
            # Transcoder hedefi kısmen yazıp hata verebilir. Pending kaydı
            # oluşmadan önceki her hata kişisel sesi ve disk kotasını temizler.
            wav.unlink(missing_ok=True)
            raise
        finally:
            raw.unlink(missing_ok=True)

    try:
        job = state.registry.start("voice_analyze", "Ses analizi", run)
    except BaseException:
        raw.unlink(missing_ok=True)
        raise
    return job.to_dict()


@router.get("/voice/analyze/status")
def analyze_status(request: Request) -> dict[str, Any]:
    job = _state(request).registry.get("voice_analyze")
    return job.to_dict() if job else {"status": "idle"}


@router.post("/voice/refield", status_code=202)
async def refield(request: Request, field: str, file: UploadFile) -> dict[str, Any]:
    """Tek bir alanı (başlık/yazar/yayınevi) kısa bir kayıtla yeniden söylet.

    Kayıt/pending durumuna dokunmaz; ``/voice/analyze`` ile AYNI iş yuvasını
    (``voice_analyze``) paylaşır, bu yüzden ikisi aynı anda koşamaz — istemci
    aynı ``/voice/analyze/status`` uç noktasını yoklar.
    """

    if field not in _REFIELD_FIELDS:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen alan: {field}")
    state = _state(request)
    suffix = Path(file.filename or "kayit.webm").suffix.lower() or ".webm"
    if suffix not in _AUDIO_SUFFIXES:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen ses türü: {suffix}")
    staging = state.upload_root / "voice"
    staging.mkdir(parents=True, exist_ok=True)
    raw = await stage_upload(
        staging,
        file,
        allowed_suffixes=_AUDIO_SUFFIXES,
        maximum_bytes=_MAX_AUDIO_ANALYZE_BYTES,
        kind="audio",
        target_name=f"{uuid.uuid4().hex}{suffix}",
    )

    def run(job: WebJob) -> dict[str, Any]:
        job.message = "Ses kanonik WAV'a çevriliyor…"
        wav = raw.with_name(f"{raw.stem}-canonical.wav")
        try:
            transcode_to_wav16k(raw, wav)
            job.message = "Alan yeniden okunuyor…"
            settings = AppSettings(state.database)
            language = (
                settings.voice_second_pass_language
                if field in {"title", "author"}
                else settings.voice_language
            )
            session = state.voice_session()
            value, transcript = session.transcribe_field(
                wav, field, language=language, prompt=f"{_REFIELD_LABELS_TR[field]}: "
            )
            return {"field": field, "value": value, "transcript": transcript}
        finally:
            wav.unlink(missing_ok=True)
            raw.unlink(missing_ok=True)

    try:
        job = state.registry.start("voice_analyze", "Alan yeniden okuma", run)
    except BaseException:
        raw.unlink(missing_ok=True)
        raise
    return job.to_dict()


@router.post("/voice/save")
def save_voice(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    pending_id = payload.get("pending_id") or ""
    with state.pending_lock:
        pending = state.pending_utterances.get(pending_id)
    if pending is None:
        raise HTTPException(
            status_code=404,
            detail="Bekleyen ses kaydı bulunamadı; kaydı yeniden analiz edin.",
        )
    session = state.voice_session()
    values = {field: str(payload.get("values", {}).get(field) or "") for field in _FORM_FIELDS}
    try:
        copy_count = int(payload.get("copy_count") or 1)
    except (TypeError, ValueError) as exc:
        raise ValueError("Nüsha sayısı tam sayı olmalıdır") from exc
    if not 1 <= copy_count <= _MAX_VOICE_COPIES:
        raise ValueError(f"Nüsha sayısı 1 ile {_MAX_VOICE_COPIES} arasında olmalıdır")
    result = session.form_result(values, copy_count=copy_count)
    learnable = _learnable_corrections(pending.result, values)
    merge_into = payload.get("merge_into_edition")
    edition_id = session.save(
        pending,
        result,
        approve=bool(payload.get("approve", True)),
        merge_into_edition=int(merge_into) if merge_into else None,
    )
    with state.pending_lock:
        state.pending_utterances.pop(pending_id, None)
    return {
        "edition_id": edition_id,
        "review_reasons": list(result.review_reasons),
        "learnable": learnable,
    }


@router.delete("/voice/pending/{pending_id}", status_code=204)
def discard_pending_voice(request: Request, pending_id: str) -> None:
    """Discard a cancelled, not-yet-approved microphone recording."""

    if len(pending_id) != 12 or not all(character in "0123456789abcdef" for character in pending_id):
        raise HTTPException(status_code=400, detail="Geçersiz ses kaydı kimliği")
    state = _state(request)
    with state.pending_lock:
        pending = state.pending_utterances.pop(pending_id, None)
    if pending is None:
        raise HTTPException(status_code=404, detail="Bekleyen ses kaydı bulunamadı")
    _delete_unapproved_audio(pending)


# ------------------------------------------------------- düzeltme sözlüğü


@router.get("/voice/aliases")
def list_voice_aliases(request: Request) -> list[dict[str, Any]]:
    return [voice_alias_to_dict(item) for item in _state(request).database.list_voice_aliases()]


@router.post("/voice/aliases", status_code=201)
def create_voice_alias(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    heard = str(payload.get("heard") or "").strip()
    canonical = str(payload.get("canonical") or "").strip()
    field_scope = str(payload.get("field_scope") or "any").strip()
    if not heard:
        raise HTTPException(status_code=400, detail="Duyulan metin boş olamaz")
    if not canonical:
        raise HTTPException(status_code=400, detail="Kanonik değer boş olamaz")
    if field_scope not in _FIELD_SCOPES:
        raise HTTPException(
            status_code=400,
            detail=f"Kapsam şunlardan biri olmalı: {', '.join(sorted(_FIELD_SCOPES))}",
        )
    alias = _state(request).database.upsert_voice_alias(fold_text(heard), canonical, field_scope)
    return voice_alias_to_dict(alias)


@router.delete("/voice/aliases/{alias_id}", status_code=204)
def delete_voice_alias(request: Request, alias_id: int) -> None:
    _state(request).database.delete_voice_alias(alias_id)


# ------------------------------------------------------------ toplu işler


@router.post("/voice/jobs", status_code=201)
async def create_voice_jobs(request: Request) -> dict[str, Any]:
    state = _state(request)
    form = await request.form(max_files=_MAX_AUDIO_BATCH_FILES, max_fields=8)
    uploads = [item for item in form.getlist("files") if isinstance(item, FormUploadFile)]
    if not uploads:
        raise HTTPException(status_code=400, detail="Ses dosyası yüklenmedi")
    if len(uploads) > _MAX_AUDIO_BATCH_FILES:
        raise HTTPException(
            status_code=413,
            detail=f"Bir ses grubunda en fazla {_MAX_AUDIO_BATCH_FILES} dosya kabul edilir",
        )
    single_book = str(form.get("single_book") or "") in {"1", "true", "on"}
    language = str(form.get("language") or "").strip() or None
    if language is not None and language not in _BATCH_LANGUAGES:
        raise HTTPException(status_code=400, detail=f"Desteklenmeyen dil: {language}")
    # Önce TÜM adları doğrula: ortadaki geçersiz dosya, öncekiler kuyruğa
    # alındıktan sonra 400 dönüp mükerrer işlere yol açmasın.
    for upload in uploads:
        name = Path(upload.filename or "ses").name
        if Path(name).suffix.lower() not in _AUDIO_SUFFIXES:
            raise HTTPException(status_code=400, detail=f"Desteklenmeyen ses türü: {name}")
    staging = state.upload_root / "voice-batch"
    staging.mkdir(parents=True, exist_ok=True)
    budget = UploadBudget(_MAX_AUDIO_BATCH_BYTES)
    staged: list[tuple[Path, str]] = []
    try:
        for upload in uploads:
            name = safe_upload_name(upload.filename, "ses.webm")
            target = await stage_upload(
                staging,
                upload,
                allowed_suffixes=_AUDIO_SUFFIXES,
                maximum_bytes=_MAX_AUDIO_FILE_BYTES,
                kind="audio",
                budget=budget,
                target_name=f"{uuid.uuid4().hex[:8]}-{name}",
            )
            staged.append((target, Path(name).stem))
    except BaseException:
        for target, _name in staged:
            target.unlink(missing_ok=True)
        raise

    def enqueue_all() -> list[dict[str, Any]]:
        scheduler = build_voice_scheduler(state.database, state.paths)
        return [
            voice_job_to_dict(
                scheduler.enqueue(
                    target, name=name, single_book=single_book, language=language
                )
            )
            for target, name in staged
        ]

    try:
        jobs = await to_thread.run_sync(enqueue_all)
    finally:
        # VoiceScheduler.enqueue kaynak sesi hashli yönetilen alana kopyalar;
        # kişisel sesin web staging kopyasını başarı/hata sonrasında tutma.
        for target, _name in staged:
            target.unlink(missing_ok=True)
    return {"jobs": jobs}


@router.get("/voice/jobs")
def list_voice_jobs(request: Request) -> list[dict[str, Any]]:
    return [voice_job_to_dict(job) for job in _state(request).database.list_voice_jobs()]


@router.post("/voice/run", status_code=202)
def run_voice_queue(request: Request) -> dict[str, Any]:
    state = _state(request)

    def run(job: WebJob) -> dict[str, Any]:
        scheduler = build_voice_scheduler(
            state.database, state.paths, stop_event=job.stop_event
        )
        completed = 0
        job.message = "Ses kuyruğu işleniyor…"
        while not job.stop_event.is_set():
            summary = scheduler.run_next()
            if summary is None:
                break
            completed += 1
            job.progress_done = completed
            job.message = f"{completed} ses işi tamamlandı"
        return {"completed": completed}

    web_job = state.registry.start("voice", "Toplu ses işleme", run)
    return web_job.to_dict()


@router.post("/voice/stop")
def stop_voice_queue(request: Request) -> dict[str, Any]:
    job = _state(request).registry.request_stop("voice")
    if job is None:
        raise HTTPException(status_code=404, detail="Çalışan ses işi yok")
    return job.to_dict()


@router.get("/voice/status")
def voice_status(request: Request) -> dict[str, Any]:
    job = _state(request).registry.get("voice")
    return job.to_dict() if job else {"status": "idle"}


@router.post("/voice/jobs/{job_id}/pause")
def pause_voice(request: Request, job_id: str) -> dict[str, Any]:
    scheduler = build_voice_scheduler(_state(request).database, _state(request).paths)
    return voice_job_to_dict(scheduler.pause(job_id))


@router.post("/voice/jobs/{job_id}/resume")
def resume_voice(request: Request, job_id: str) -> dict[str, Any]:
    scheduler = build_voice_scheduler(_state(request).database, _state(request).paths)
    return voice_job_to_dict(scheduler.resume(job_id))


@router.post("/voice/jobs/{job_id}/cancel")
def cancel_voice(request: Request, job_id: str) -> dict[str, Any]:
    scheduler = build_voice_scheduler(_state(request).database, _state(request).paths)
    return voice_job_to_dict(scheduler.cancel(job_id))


@router.get("/voice/recent")
def recent_voice_books(request: Request, limit: int = 10) -> list[dict[str, Any]]:
    """Son ses kaynaklı kayıtlar (GUI'deki 'Son kaydedilenler' listesi)."""

    state = _state(request)
    rows = state.database.fetchall(
        """
        SELECT DISTINCT edition_id FROM copy
        WHERE source_fingerprint LIKE 'voice:%' AND edition_id IS NOT NULL
        ORDER BY id DESC LIMIT ?
        """,
        (limit,),
    )
    from kitapkatalog.webapp.serialize import book_to_dict

    books = []
    for row in rows:
        record = state.catalog.get_book(int(row["edition_id"]))
        if record is not None:
            books.append(book_to_dict(record))
    return books
