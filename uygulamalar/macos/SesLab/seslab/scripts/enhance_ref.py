"""Klon referansını koşullandırma için yoğunlaştırır (postprocess.enhance_ref).

Akış: ham referanstan ref_enhanced.wav üretilir, A/B taraması
(tune_xtts.py --stage 0) kazanırsa --apply ile devreye alınır.

Kullanım:
    uv run python scripts/enhance_ref.py [voice_id]             # ref_enhanced.wav üret
    uv run python scripts/enhance_ref.py [voice_id] --apply     # ref.wav'a geçir (yedekli)
    uv run python scripts/enhance_ref.py [voice_id] --rollback  # yedekten geri al
voice_id verilmezse kütüphanedeki en yeni ses kullanılır.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import numpy as np  # noqa: E402

from app.audio.io import read_wav, write_wav  # noqa: E402
from app.audio.postprocess import (  # noqa: E402
    drop_truncated_ending,
    enhance_ref,
    trim_edge_silence,
)
from app.config import VOICE_MIN_S, VOICES_DIR  # noqa: E402
from app.core.voices import list_voices  # noqa: E402


def stats(audio: np.ndarray, sr: int, top_db: float = 40.0) -> str:
    import librosa

    dur = len(audio) / sr
    peak = float(np.max(np.abs(audio))) if len(audio) else 0.0
    rms = float(np.sqrt(np.mean(np.square(audio)))) if len(audio) else 0.0
    intervals = librosa.effects.split(
        audio, top_db=top_db, frame_length=1024, hop_length=256
    )
    voiced = sum(int(e - s) for s, e in intervals) / len(audio) if len(audio) else 0.0
    db = lambda x: 20 * np.log10(max(x, 1e-9))  # noqa: E731
    return (f"{dur:6.2f} sn | tepe {db(peak):6.2f} dBFS | "
            f"RMS {db(rms):6.2f} dBFS | sesli %{voiced * 100:.1f}")


def resolve_vdir(voice_id: str | None) -> Path:
    if voice_id is None:
        vs = list_voices()
        assert vs, "kütüphanede ses yok"
        voice_id = vs[0]["id"]
    vdir = VOICES_DIR / voice_id
    assert (vdir / "ref.wav").exists(), f"ref.wav yok: {vdir}"
    return vdir


def update_meta_duration(vdir: Path, duration: float) -> None:
    mp = vdir / "meta.json"
    meta = json.loads(mp.read_text(encoding="utf-8"))
    meta["duration_s"] = round(duration, 3)
    mp.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


def build(vdir: Path, mode: str = "temiz") -> None:
    # Ham kaynak: uygulanmışsa yedek, değilse mevcut ref
    src = vdir / "ref_raw.wav" if (vdir / "ref_raw.wav").exists() else vdir / "ref.wav"
    audio, sr = read_wav(src)
    if mode == "yogun":
        # Sessizlik sıkıştırma — A/B'de kaybetti, karşılaştırma için duruyor
        out = enhance_ref(audio, sr, min_out_s=VOICE_MIN_S)
    else:
        # temiz (A/B galibi): yalnız kesik son segment + uç sessizliği at
        out = drop_truncated_ending(audio, sr, min_keep_s=VOICE_MIN_S)
        out = trim_edge_silence(out, sr)
    write_wav(vdir / "ref_enhanced.wav", out, sr)
    print(f"kaynak ({src.name}):  {stats(audio, sr)}")
    print(f"{mode} (ref_enhanced): {stats(out, sr)}")
    print(f"yazıldı: {vdir / 'ref_enhanced.wav'}")


def apply(vdir: Path) -> None:
    enh, ref, raw = vdir / "ref_enhanced.wav", vdir / "ref.wav", vdir / "ref_raw.wav"
    assert enh.exists(), "önce ref_enhanced.wav üretin (bayraksız çalıştırın)"
    assert not raw.exists(), "zaten uygulanmış (ref_raw.wav mevcut) — önce --rollback"
    ref.rename(raw)
    shutil.copy2(enh, ref)
    (vdir / "preview.wav").unlink(missing_ok=True)  # önbellek eski sesle üretilmişti
    audio, sr = read_wav(ref)
    update_meta_duration(vdir, len(audio) / sr)
    print(f"uygulandı: ref.wav ← ref_enhanced.wav (yedek: ref_raw.wav), preview silindi")


def rollback(vdir: Path) -> None:
    raw, ref = vdir / "ref_raw.wav", vdir / "ref.wav"
    assert raw.exists(), "geri alınacak yedek yok (ref_raw.wav bulunamadı)"
    raw.replace(ref)
    (vdir / "preview.wav").unlink(missing_ok=True)
    audio, sr = read_wav(ref)
    update_meta_duration(vdir, len(audio) / sr)
    print("geri alındı: ref.wav ← ref_raw.wav, preview silindi")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("voice_id", nargs="?", default=None,
                        help="ses kimliği (boşsa en yeni ses)")
    parser.add_argument("--mode", choices=("temiz", "yogun"), default="temiz",
                        help="temiz: kesik bitiş + uç kırpma (A/B galibi); "
                             "yogun: sessizlik sıkıştırma (enhance_ref)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--apply", action="store_true")
    group.add_argument("--rollback", action="store_true")
    args = parser.parse_args()

    vdir = resolve_vdir(args.voice_id)
    print(f"ses: {vdir.name}")
    if args.apply:
        apply(vdir)
    elif args.rollback:
        rollback(vdir)
    else:
        build(vdir, args.mode)


if __name__ == "__main__":
    main()
