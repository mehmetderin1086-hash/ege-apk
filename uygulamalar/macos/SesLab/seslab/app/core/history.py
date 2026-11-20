"""Üretim geçmişi — her TTS/VC çıktısı diske ve veritabanına kaydedilir."""
from __future__ import annotations

import json
import time
import uuid
from pathlib import Path

import numpy as np

from app import db
from app.audio.io import duration_s, write_wav
from app.config import OUTPUTS_DIR


def add(
    type_: str,
    audio: np.ndarray,
    sr: int,
    text: str = "",
    params: dict | None = None,
    voice_id: str | None = None,
) -> dict:
    rec_id = uuid.uuid4().hex[:12]
    path = OUTPUTS_DIR / f"{rec_id}.wav"
    write_wav(path, audio, sr)
    record = {
        "id": rec_id,
        "type": type_,
        "text": text,
        "params": params or {},
        "voice_id": voice_id,
        "path": str(path),
        "duration_s": duration_s(audio, sr),
        "created_at": time.time(),
    }
    with db.connect() as conn:
        conn.execute(
            """INSERT INTO history (id, type, text, params, voice_id, path,
                                    duration_s, created_at)
               VALUES (?,?,?,?,?,?,?,?)""",
            (
                rec_id, type_, text,
                json.dumps(params or {}, ensure_ascii=False),
                voice_id, str(path), record["duration_s"], record["created_at"],
            ),
        )
    return record


def _row_to_dict(row) -> dict:
    d = dict(row)
    d["params"] = json.loads(d["params"] or "{}")
    return d


def list_(type_: str | None = None, limit: int = 100) -> list[dict]:
    with db.connect() as conn:
        if type_:
            rows = conn.execute(
                "SELECT * FROM history WHERE type=? ORDER BY created_at DESC LIMIT ?",
                (type_, limit),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM history ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
    return [_row_to_dict(r) for r in rows]


def get(rec_id: str) -> dict | None:
    with db.connect() as conn:
        row = conn.execute("SELECT * FROM history WHERE id=?", (rec_id,)).fetchone()
    return _row_to_dict(row) if row else None


def delete(rec_id: str) -> None:
    rec = get(rec_id)
    if rec is None:
        raise KeyError("Kayıt bulunamadı")
    Path(rec["path"]).unlink(missing_ok=True)
    with db.connect() as conn:
        conn.execute("DELETE FROM history WHERE id=?", (rec_id,))
