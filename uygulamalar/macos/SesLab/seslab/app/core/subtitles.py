"""STT sonuçlarını dışa aktarma: TXT / SRT / VTT / JSON."""
from __future__ import annotations

import json


def _ts_srt(seconds: float) -> str:
    ms = int(round(seconds * 1000))
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _ts_vtt(seconds: float) -> str:
    return _ts_srt(seconds).replace(",", ".")


def to_txt(result: dict) -> str:
    return (result.get("text") or "").strip() + "\n"


def to_srt(result: dict) -> str:
    lines = []
    for i, seg in enumerate(result.get("segments", []), start=1):
        lines.append(str(i))
        lines.append(f"{_ts_srt(seg['start'])} --> {_ts_srt(seg['end'])}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)


def to_vtt(result: dict) -> str:
    lines = ["WEBVTT", ""]
    for seg in result.get("segments", []):
        lines.append(f"{_ts_vtt(seg['start'])} --> {_ts_vtt(seg['end'])}")
        lines.append(seg["text"].strip())
        lines.append("")
    return "\n".join(lines)


def to_json(result: dict) -> str:
    slim = {
        "text": (result.get("text") or "").strip(),
        "language": result.get("language"),
        "segments": [
            {
                "start": seg["start"],
                "end": seg["end"],
                "text": seg["text"].strip(),
                "words": [
                    {
                        "word": w["word"],
                        "start": w["start"],
                        "end": w["end"],
                        "probability": round(w.get("probability", 0), 3),
                    }
                    for w in seg.get("words", [])
                ],
            }
            for seg in result.get("segments", [])
        ],
    }
    return json.dumps(slim, ensure_ascii=False, indent=2)


EXPORTERS = {"txt": to_txt, "srt": to_srt, "vtt": to_vtt, "json": to_json}
MEDIA_TYPES = {
    "txt": "text/plain; charset=utf-8",
    "srt": "text/plain; charset=utf-8",
    "vtt": "text/vtt; charset=utf-8",
    "json": "application/json; charset=utf-8",
}
