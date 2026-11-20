"""ChatterboxVC — konuşmadan konuşmaya ses değiştirici (voice changer).

Kaynak kayıttaki konuşma içeriğini korur, sesi hedef referansa dönüştürür.
"""
from __future__ import annotations

import numpy as np

from .base import BaseEngine, free_torch_memory, patch_torch_load_for_mps


class ChatterboxVCEngine(BaseEngine):
    name = "vc"
    est_mem_gb = 3.0
    heavy = True

    sr: int = 24000

    def _load(self) -> None:
        patch_torch_load_for_mps()
        import torch
        from chatterbox.vc import ChatterboxVC

        device = "mps" if torch.backends.mps.is_available() else "cpu"
        self._model = ChatterboxVC.from_pretrained(device=device)
        self.sr = self._model.sr

    def convert(self, source_wav_path: str, target_voice_wav_path: str) -> np.ndarray:
        """Kaynak wav'daki konuşmayı hedef sese dönüştürür (float32 mono)."""
        import torch

        with self.lock:  # boşta-boşaltma ile yarışı engelle
            assert self._model is not None, "Motor yüklü değil (önce load())"
            with torch.inference_mode():
                wav = self._model.generate(
                    str(source_wav_path), target_voice_path=str(target_voice_wav_path)
                )
            audio = wav.squeeze(0).detach().cpu().numpy().astype(np.float32)
            self.gen_count += 1
            self.touch()
        free_torch_memory()
        return audio
