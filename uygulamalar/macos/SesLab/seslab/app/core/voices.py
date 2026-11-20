"""Ses kütüphanesi — klonlanan seslerin CRUD'u.

Her ses data/voices/<voice_id>/ altında: ref.wav (24 kHz mono referans),
meta.json (ad, süre, tarih), preview.wav (önbelleğe alınmış önizleme).
"""
from __future__ import annotations

import json
import re
import shutil
import time
import uuid
from pathlib import Path

from app.audio.io import decode_audio, duration_s, write_wav
from app.audio.postprocess import drop_truncated_ending
from app.config import DATA_DIR, REF_SR, VOICE_MAX_S, VOICE_MIN_S, VOICES_DIR


_ID_RE = re.compile(r"^[0-9a-f]{12}$")  # uuid4().hex[:12] biçimi


def _validate_id(voice_id: str) -> str:
    """Dosya yoluna girecek kimliği doğrular — path traversal önlemi."""
    if not _ID_RE.fullmatch(voice_id or ""):
        raise KeyError("Ses bulunamadı")
    return voice_id


def _meta_path(voice_id: str) -> Path:
    return VOICES_DIR / _validate_id(voice_id) / "meta.json"


def ref_path(voice_id: str) -> Path:
    return VOICES_DIR / _validate_id(voice_id) / "ref.wav"


def preview_path(voice_id: str) -> Path:
    return VOICES_DIR / _validate_id(voice_id) / "preview.wav"


def resolve_checkpoint_dir(voice_id: str | None) -> str | None:
    """Sesin fine-tuned XTTS checkpoint dizini (varsa mutlak yol), yoksa None.

    Ses meta.json'unda opsiyonel `checkpoint_dir` alanı, bu sesin kendi eğitilmiş
    modelini işaret eder (ör. Murat → "xtts_murat_ft"). Göreli verilirse
    DATA_DIR/models altında çözülür; yalnızca `model.pth` içeren dizin geçerlidir.
    Alan yoksa None → çağıran, genel varsayılan checkpoint'e (Emel/taban) düşer.
    """
    if not voice_id or voice_id == "default":
        return None
    meta = get_voice(voice_id)
    if not meta:
        return None
    ckpt = (meta.get("checkpoint_dir") or "").strip()
    if not ckpt:
        return None
    p = Path(ckpt)
    if not p.is_absolute():
        p = DATA_DIR / "models" / ckpt
    return str(p) if (p / "model.pth").is_file() else None


def create_voice(name: str, audio_bytes: bytes) -> dict:
    """Yüklenen/kaydedilen örneği çözer, doğrular ve kütüphaneye ekler."""
    audio, sr = decode_audio(audio_bytes, target_sr=REF_SR)
    dur = duration_s(audio, sr)
    if dur < VOICE_MIN_S:
        raise ValueError(
            f"Örnek çok kısa ({dur:.1f} sn). En az {VOICE_MIN_S:.0f} saniye gerekli; "
            f"10 saniye civarı idealdir."
        )
    if dur > VOICE_MAX_S:
        # Fazlasını at: Chatterbox ~10 sn referansla çalışır, 30 sn üstü gereksiz
        audio = audio[: int(VOICE_MAX_S * sr)]
        # Sert kesme kelime ortasında bitebilir; XTTS bitiş davranışını
        # referanstan öğrendiğinden bu, kuyruk halüsinasyonu doğuruyor —
        # kesik son segmenti at ki referans duraksamayla bitsin
        audio = drop_truncated_ending(audio, sr, min_keep_s=VOICE_MIN_S)
        dur = duration_s(audio, sr)

    voice_id = uuid.uuid4().hex[:12]
    vdir = VOICES_DIR / voice_id
    vdir.mkdir(parents=True, exist_ok=True)
    write_wav(vdir / "ref.wav", audio, sr)

    meta = {
        "id": voice_id,
        "name": name.strip() or "Adsız ses",
        "duration_s": dur,
        "created_at": time.time(),
    }
    _meta_path(voice_id).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return meta


def list_voices() -> list[dict]:
    voices = []
    if VOICES_DIR.exists():
        for meta_file in VOICES_DIR.glob("*/meta.json"):
            try:
                voices.append(json.loads(meta_file.read_text(encoding="utf-8")))
            except (json.JSONDecodeError, OSError):
                continue
    return sorted(voices, key=lambda v: v.get("created_at", 0), reverse=True)


def get_voice(voice_id: str) -> dict | None:
    try:
        p = _meta_path(voice_id)
    except KeyError:
        return None
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None  # bozuk meta → ses yok say (list_voices ile tutarlı)


def rename_voice(voice_id: str, new_name: str) -> dict:
    meta = get_voice(voice_id)
    if meta is None:
        raise KeyError("Ses bulunamadı")
    meta["name"] = new_name.strip() or meta["name"]
    _meta_path(voice_id).write_text(
        json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return meta


def delete_voice(voice_id: str) -> None:
    vdir = VOICES_DIR / _validate_id(voice_id)
    if not vdir.exists():
        raise KeyError("Ses bulunamadı")
    shutil.rmtree(vdir)
