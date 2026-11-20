"""mlx-whisper STT motoru — Apple Silicon'da MLX hızlandırmalı Whisper.

Girdi HER ZAMAN 16 kHz float32 numpy dizisidir (dosya yolu verilirse
mlx-whisper var olmayan ffmpeg CLI'ını çağırmaya çalışır).
"""
from __future__ import annotations

import numpy as np

from app.config import STT_REPO

from .base import BaseEngine


class WhisperSTTEngine(BaseEngine):
    name = "stt"
    est_mem_gb = 2.0
    heavy = False

    def _load(self) -> None:
        import mlx.core as mx
        from mlx_whisper.transcribe import ModelHolder

        # Modeli önceden ısıt (ilk transcribe çağrısı beklemesin)
        ModelHolder.get_model(STT_REPO, mx.float16)
        self._model = ModelHolder  # sınıf düzeyi önbellek — referansı tutuyoruz

    def _unload(self) -> None:
        import mlx.core as mx
        from mlx_whisper.transcribe import ModelHolder

        ModelHolder.model = None
        ModelHolder.model_path = None
        mx.clear_cache()

    def transcribe(
        self,
        audio_16k: np.ndarray,
        language: str | None = "tr",
        word_timestamps: bool = True,
    ) -> dict:
        """16 kHz float32 mono diziyi çözümler.

        Dönüş: {"text", "language", "segments": [{start, end, text,
                 "words": [{word, start, end, probability}]}]}
        """
        import mlx_whisper

        with self.lock:  # boşta-boşaltma ile yarışı engelle
            assert self._model is not None, "Motor yüklü değil (önce load())"
            result = mlx_whisper.transcribe(
                audio_16k,
                path_or_hf_repo=STT_REPO,
                language=language,
                word_timestamps=word_timestamps,
            )
            self.gen_count += 1
            self.touch()
        return result
