"""Uzun metin projeleri — parça bazlı sentez, checkpoint, birleştirme.

Her parça data/projects/<id>/chunks/<idx>.wav olarak diske yazılır;
watchdog motoru boşaltsa bile tamamlanan parçalar kaybolmaz ve tek tek
yeniden üretilebilir.
"""
from __future__ import annotations

import asyncio
import json
import shutil
import time
import uuid
from pathlib import Path

import numpy as np

from app import db
from app.audio.io import read_wav, write_wav
from app.audio.postprocess import stitch
from app.config import DEFAULT_LANGUAGE, DEFAULT_SPEECH_SPEED, PROJECTS_DIR
from app.core.synth import (
    _generate_once,
    default_engine,
    finalize_chunk_sync,
    gap_after_chunk,
    resolve_checkpoint_dir,
    resolve_ref_wav,
    should_verify,
)
from app.core.text.chunk_tr import chunk_text
from app.core.text.normalize_tr import normalize_tr
from app.jobs import Job, queue


def _chunk_path(project_id: str, idx: int) -> Path:
    return PROJECTS_DIR / project_id / "chunks" / f"{idx:04d}.wav"


def create_project(
    title: str,
    text: str,
    voice_id: str | None,
    params: dict | None = None,
    normalize: bool = True,
) -> dict:
    params = params or {}
    language = params.get("language", DEFAULT_LANGUAGE)
    norm_text = normalize_tr(text)[0] if (normalize and language == "tr") else text
    # XTTS: ≤226 karakterlik çok cümleli grup + tek GPT geçişi (bkz. synth.py)
    if params.get("engine") == "xtts":
        from app.config import XTTS_CHUNK_HARD, XTTS_CHUNK_TARGET

        chunks = chunk_text(norm_text, target=XTTS_CHUNK_TARGET, hard=XTTS_CHUNK_HARD)
    else:
        chunks = chunk_text(norm_text)
    if not chunks:
        raise ValueError("Metin boş veya parçalanamadı")

    project_id = uuid.uuid4().hex[:12]
    params["normalize"] = normalize
    with db.connect() as conn:
        conn.execute(
            """INSERT INTO projects (id, title, text, voice_id, params, status,
                                     created_at)
               VALUES (?,?,?,?,?,?,?)""",
            (
                project_id, title.strip() or "Adsız proje", text, voice_id,
                json.dumps(params, ensure_ascii=False), "draft", time.time(),
            ),
        )
        conn.executemany(
            """INSERT INTO chunks (project_id, idx, text, status, paragraph_break)
               VALUES (?,?,?,?,?)""",
            [
                (project_id, c.i, c.text, "pending", int(c.paragraph_break))
                for c in chunks
            ],
        )
    return get_project(project_id)


def get_project(project_id: str) -> dict | None:
    with db.connect() as conn:
        row = conn.execute(
            "SELECT * FROM projects WHERE id=?", (project_id,)
        ).fetchone()
        if row is None:
            return None
        chunk_rows = conn.execute(
            "SELECT * FROM chunks WHERE project_id=? ORDER BY idx", (project_id,)
        ).fetchall()
    project = dict(row)
    project["params"] = json.loads(project["params"] or "{}")
    project["chunks"] = [dict(c) for c in chunk_rows]
    done = sum(1 for c in project["chunks"] if c["status"] == "done")
    project["done_chunks"] = done
    project["chunk_count"] = len(project["chunks"])
    return project


def list_projects() -> list[dict]:
    with db.connect() as conn:
        rows = conn.execute(
            """SELECT p.*,
                      (SELECT COUNT(*) FROM chunks c WHERE c.project_id = p.id)
                        AS chunk_count,
                      (SELECT COUNT(*) FROM chunks c WHERE c.project_id = p.id
                        AND c.status='done') AS done_chunks
               FROM projects p ORDER BY created_at DESC"""
        ).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d["params"] = json.loads(d["params"] or "{}")
        out.append(d)
    return out


def delete_project(project_id: str) -> None:
    with db.connect() as conn:
        cur = conn.execute("DELETE FROM projects WHERE id=?", (project_id,))
        conn.execute("DELETE FROM chunks WHERE project_id=?", (project_id,))
    if cur.rowcount == 0:
        raise KeyError("Proje bulunamadı")
    shutil.rmtree(PROJECTS_DIR / project_id, ignore_errors=True)


def _project_exists(project_id: str) -> bool:
    """Hafif varlık kontrolü — get_project'in tüm chunk'ları okumasından kaçınır
    (kitap ölçeğinde her chunk'ta O(N) okuma = O(N²) olurdu)."""
    with db.connect() as conn:
        return conn.execute(
            "SELECT 1 FROM projects WHERE id=?", (project_id,)
        ).fetchone() is not None


def _set_chunk_status(project_id: str, idx: int, status: str, path: str = "") -> None:
    with db.connect() as conn:
        conn.execute(
            "UPDATE chunks SET status=?, path=? WHERE project_id=? AND idx=?",
            (status, path, project_id, idx),
        )


def _set_project_status(project_id: str, status: str) -> None:
    with db.connect() as conn:
        conn.execute(
            "UPDATE projects SET status=? WHERE id=?", (status, project_id)
        )


async def run_project(project_id: str, job: Job, only_idx: int | None = None) -> dict:
    """Bekleyen (veya seçilen) parçaları sırayla sentezler."""
    project = get_project(project_id)
    if project is None:
        raise KeyError("Proje bulunamadı")

    params = project["params"]
    language = params.get("language", DEFAULT_LANGUAGE)
    ref_wav = resolve_ref_wav(
        project["voice_id"], language, params.get("engine") or default_engine()
    )

    if only_idx is not None:
        todo = [c for c in project["chunks"] if c["idx"] == only_idx]
    else:
        todo = [c for c in project["chunks"] if c["status"] != "done"]
    total_all = project["chunk_count"]
    already_done = total_all - len(todo)

    verify = bool(params.get("verify", True))
    engine_name = params.get("engine") or default_engine()
    checkpoint_dir = resolve_checkpoint_dir(project["voice_id"], language, engine_name)

    def gen_args(chunk: dict) -> tuple:
        return (
            chunk["text"], language, ref_wav,
            float(params.get("exaggeration", 0.5)),
            float(params.get("cfg_weight", 0.5)),
            float(params.get("temperature", 0.8)),
            float(params.get("speed") or DEFAULT_SPEECH_SPEED),
            engine_name,
            checkpoint_dir,
        )

    # PARALEL SENTEZ: bölümler bağımsız dosyalara yazılır → sıra önemsiz.
    # XTTS worker havuzu kadar üretim uçuşta tutulur; STT denetimi üretim
    # yuvasını serbest bıraktıktan sonra koşar (üret∥denetle boru hattı,
    # havuz=2 iken 2 üretim + denetimler eşzamanlı ilerler).
    if engine_name == "xtts":
        from app.engines.xtts import XTTSEngine

        pool = XTTSEngine.planned_pool_size()
    else:
        pool = 1
    sem = asyncio.Semaphore(pool)
    done_count = already_done

    async def process(chunk: dict) -> None:
        nonlocal done_count
        async with sem:
            # Proje iş sürerken silinmiş olabilir → temiz iptal (hafif kontrol)
            if not _project_exists(project_id):
                raise KeyError("Proje sentez sırasında silindi")
            audio, sr = await asyncio.to_thread(_generate_once, *gen_args(chunk))
        if should_verify(language, verify):
            audio, sr = await asyncio.to_thread(
                finalize_chunk_sync, audio, sr,
                chunk["text"], language, gen_args(chunk),
            )
        path = _chunk_path(project_id, chunk["idx"])
        write_wav(path, audio, sr)
        _set_chunk_status(project_id, chunk["idx"], "done", str(path))
        done_count += 1
        await queue.update(
            job,
            progress=done_count / total_all,
            message=f"{done_count}/{total_all} bölüm tamamlandı"
            + (f" (havuz: {pool})" if pool > 1 else ""),
        )

    _set_project_status(project_id, "running")
    # Parti parti işle: kitap ölçeğinde (10.000+ bölüm) tüm coroutine'leri aynı
    # anda yaratmak yerine (semafor zaten eşzamanlılığı sınırlar) bellek/zamanlayıcı
    # yükünü sabit tutar.
    BATCH = 200
    for start in range(0, len(todo), BATCH):
        batch = todo[start:start + BATCH]
        results = await asyncio.gather(
            *(process(c) for c in batch), return_exceptions=True
        )
        errors = [r for r in results if isinstance(r, BaseException)]
        if errors:
            _set_project_status(project_id, "error")
            raise errors[0]

    # Durum, parça gerçekliğinden türetilir: tek parça yeniden üretiminde
    # kalan pending'ler varken projeyi "done" işaretleme.
    final = get_project(project_id)
    all_done = final is not None and final["done_chunks"] == final["chunk_count"]
    _set_project_status(project_id, "done" if all_done else "draft")
    return {"project_id": project_id, "done": all_done}


EXPORT_SR = 24000
MAX_WAV_HOURS = 3.0  # WAV konteyner 4 GB/~6 saatle sınırlı; üstü için mp3


def _require_all_done(project: dict) -> None:
    for chunk in project["chunks"]:
        if chunk["status"] != "done" or not chunk["path"]:
            raise ValueError(
                f"Bölüm {chunk['idx'] + 1} henüz sentezlenmedi; önce projeyi çalıştırın."
            )


def estimate_duration_s(project_id: str) -> float:
    """Tamamlanan bölüm wav'larının toplam süresini kabaca tahmin eder (PCM16)."""
    project = get_project(project_id)
    if project is None:
        raise KeyError("Proje bulunamadı")
    total_bytes = 0
    for chunk in project["chunks"]:
        p = chunk["path"]
        if p and Path(p).exists():
            total_bytes += Path(p).stat().st_size
    return total_bytes / (EXPORT_SR * 2)  # 2 bayt/örnek (soundfile PCM16)


def export_audio(project_id: str) -> tuple[np.ndarray, int]:
    """Tamamlanan parçaları paragraf duraklamalarıyla birleştirir (bellekte).

    Yalnız makul boyuttaki projeler için; kitap ölçeğinde belleği/4 GB WAV
    sınırını aşar → çağıran mp3 akışına yönlendirilmeli.
    """
    if estimate_duration_s(project_id) > MAX_WAV_HOURS * 3600:
        raise ValueError(
            f"Proje {MAX_WAV_HOURS:.0f} saatten uzun; tek WAV dosyası "
            f"desteklenmez (4 GB sınırı). Lütfen MP3 olarak dışa aktarın."
        )
    project = get_project(project_id)
    if project is None:
        raise KeyError("Proje bulunamadı")
    _require_all_done(project)
    parts: list[np.ndarray] = []
    gaps: list[float] = []
    sr = EXPORT_SR
    for chunk in project["chunks"]:
        audio, sr = read_wav(chunk["path"])
        parts.append(audio)
        gaps.append(gap_after_chunk(chunk["text"], bool(chunk["paragraph_break"])))
    return stitch(parts, sr, gaps_s=gaps), sr


def _iter_export_parts(project_id: str):
    """Bölümleri sırayla üretir: her biri kırpılır, bölüm-bazlı ustalanır
    (tekdüze ses düzeyi), fade'lenir; ardından duraklama sessizliği.

    Bütün-dosya LUFS yerine bölüm bazlı ustalama: 43 saati tek ölçmek hem
    yavaş hem belleği şişirir; her bölüm zaten ≥0.5 sn olduğundan pyloudnorm
    çalışır ve kitap boyunca tekdüze yükseklik verir.
    """
    from app.audio.postprocess import apply_fades, master, trim_edge_silence

    project = get_project(project_id)
    if project is None:
        raise KeyError("Proje bulunamadı")
    _require_all_done(project)
    for chunk in project["chunks"]:
        audio, sr = read_wav(chunk["path"])
        audio = apply_fades(master(trim_edge_silence(audio, sr), sr), sr)
        yield audio
        gap = gap_after_chunk(chunk["text"], bool(chunk["paragraph_break"]))
        if gap > 0:
            yield np.zeros(int(sr * gap), dtype=np.float32)


def export_mp3_to_file(project_id: str) -> Path:
    """Kitap ölçeğinde bile çalışan akışlı tek-MP3 dışa aktarma."""
    from app.audio.io import encode_mp3_to_file

    out_path = PROJECTS_DIR / project_id / "export.mp3"
    encode_mp3_to_file(_iter_export_parts(project_id), EXPORT_SR, out_path)
    return out_path
