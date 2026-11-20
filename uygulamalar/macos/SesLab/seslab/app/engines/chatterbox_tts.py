"""Chatterbox Multilingual TTS motoru — Türkçe dahil 23 dil, zero-shot klonlama.

MIT lisanslı (Resemble AI). Çıktılar Perth nöral filigranı içerir.
"""
from __future__ import annotations

import numpy as np

from app.config import CHATTERBOX_T3, DEFAULT_LANGUAGE

from .base import BaseEngine, free_torch_memory, patch_torch_load_for_mps


class ChatterboxTTSEngine(BaseEngine):
    name = "tts"
    est_mem_gb = 6.0
    heavy = True

    sr: int = 24000  # S3GEN_SR; _load sonrası modelden teyit edilir

    def _load(self) -> None:
        import os

        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS

        # SESLAB_CHATTERBOX_DEVICE=cpu: 16 GB'lık Mac'te (macOS 27, Ekim 2026) V3 MPS'te tek üretimde 17 GB'a şişip
        # sistem tarafından öldürülüyor; işlemcide ~5 GB ile çalışır.
        device = os.environ.get("SESLAB_CHATTERBOX_DEVICE", "auto")
        if device == "auto":
            device = "mps" if torch.backends.mps.is_available() else "cpu"
        if device == "mps":
            patch_torch_load_for_mps()
        self._model = ChatterboxMultilingualTTS.from_pretrained(device=device, t3_model=CHATTERBOX_T3)
        self.sr = self._model.sr

    def generate(
        self,
        text: str,
        language: str = DEFAULT_LANGUAGE,
        ref_wav_path: str | None = None,
        exaggeration: float = 0.5,
        cfg_weight: float = 0.5,
        temperature: float = 0.8,
        speed: float = 1.0,
        checkpoint_dir: str | None = None,  # XTTS'e özgü — Chatterbox yok sayar
    ) -> np.ndarray:
        """Metni seslendirir; float32 mono dizi döndürür (self.sr hızında).

        ref_wav_path verilirse ses o kayıttan klonlanır; verilmezse modelin
        yerleşik varsayılan sesi kullanılır.
        """
        import torch

        # Kilit: boşta-boşaltma görevi üretim ortasında modeli elden alamaz
        with self.lock:
            assert self._model is not None, "Motor yüklü değil (önce load())"
            with torch.inference_mode():
                wav = self._model.generate(
                    text,
                    language_id=language,
                    audio_prompt_path=str(ref_wav_path) if ref_wav_path else None,
                    exaggeration=exaggeration,
                    cfg_weight=cfg_weight,
                    temperature=temperature,
                )
            audio = wav.squeeze(0).detach().cpu().numpy().astype(np.float32)
            self.gen_count += 1
            self.touch()
        free_torch_memory()  # MPS sızıntı önlemi: her üretimden sonra

        if speed and abs(speed - 1.0) > 1e-3:
            import librosa

            audio = librosa.effects.time_stretch(audio, rate=float(speed))
        return audio


# --- Duman testi: uv run python -m app.engines.chatterbox_tts --smoke ---------
if __name__ == "__main__":
    import argparse
    import time

    from app.audio.io import write_wav
    from app.config import OUTPUTS_DIR, ensure_dirs

    parser = argparse.ArgumentParser()
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--text", default="Merhaba, ben SesLab. Türkçe konuşuyorum.")
    parser.add_argument("--language", default="tr")
    parser.add_argument("--ref", default=None, help="klon referans wav yolu")
    args = parser.parse_args()

    ensure_dirs()
    engine = ChatterboxTTSEngine()
    print("Model yükleniyor...", flush=True)
    t0 = time.time()
    engine.load()
    print(f"Yüklendi ({time.time() - t0:.1f} sn). Üretiliyor...", flush=True)
    t0 = time.time()
    audio = engine.generate(args.text, language=args.language, ref_wav_path=args.ref)
    dur = len(audio) / engine.sr
    out = OUTPUTS_DIR / "smoke.wav"
    write_wav(out, audio, engine.sr)
    print(
        f"Tamam: {out} ({dur:.1f} sn ses, {time.time() - t0:.1f} sn üretim, "
        f"RTF={(time.time() - t0) / max(dur, 0.01):.2f})"
    )
