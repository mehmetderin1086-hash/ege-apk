"""faster-whisper STT motoru — MLX'in olmadığı platformlar (Windows/Linux).

WhisperSTTEngine ile aynı sözleşme: girdi 16 kHz float32 mono numpy dizisi,
dönüş mlx-whisper biçiminde sözlük:
{"text", "language", "segments": [{start, end, text, "words": [...]}]}
"""
from __future__ import annotations

import os

import numpy as np

from .base import BaseEngine

# CTranslate2 model adı; Systran/faster-whisper-* deposundan otomatik iner.
STT_MODEL_FW = os.environ.get("SESLAB_STT_MODEL", "large-v3-turbo")


class FasterWhisperSTTEngine(BaseEngine):
    name = "stt"
    est_mem_gb = 2.0
    heavy = False

    def _load(self) -> None:
        from faster_whisper import WhisperModel

        self._model = WhisperModel(STT_MODEL_FW, device="cpu", compute_type="int8")

    def _unload(self) -> None:
        self._model = None

    def transcribe(
        self,
        audio_16k: np.ndarray,
        language: str | None = "tr",
        word_timestamps: bool = True,
    ) -> dict:
        with self.lock:
            assert self._model is not None, "Motor yüklü değil (önce load())"
            segments_iter, info = self._model.transcribe(
                audio_16k,
                language=language,
                word_timestamps=word_timestamps,
            )
            segments = []
            parcalar = []
            for seg in segments_iter:
                words = []
                if word_timestamps and seg.words:
                    words = [
                        {
                            "word": w.word,
                            "start": w.start,
                            "end": w.end,
                            "probability": w.probability,
                        }
                        for w in seg.words
                    ]
                segments.append(
                    {"start": seg.start, "end": seg.end, "text": seg.text, "words": words}
                )
                parcalar.append(seg.text)
            self.gen_count += 1
            self.touch()
        return {
            "text": "".join(parcalar),
            "language": info.language,
            "segments": segments,
        }
