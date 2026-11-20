"""EngineManager — tembel yükleme, "en fazla 1 ağır motor", bellek watchdog.

16 GB RAM bütçesi politikaları:
- Ağır motorlardan (tts ~6 GB, vc ~3 GB) aynı anda yalnızca biri bellekte.
- stt (~2 GB, MLX) herhangi biriyle birlikte yaşayabilir.
- Her üretimden sonra watchdog: RSS > RSS_LIMIT_GB veya RELOAD_EVERY_N
  üretimde bir → ağır motor boşaltılır (bir sonraki kullanımda yeniden yüklenir;
  chatterbox'ın bilinen MPS bellek sızıntısına karşı — issue #218).
- IDLE_UNLOAD_S saniye boşta kalan motorlar arka plan görevince boşaltılır.
"""
from __future__ import annotations

import logging
import time

import psutil

from app.config import IDLE_UNLOAD_S, RELOAD_EVERY_N, RSS_LIMIT_GB

import sys

from .base import BaseEngine
from .chatterbox_tts import ChatterboxTTSEngine
from .chatterbox_vc import ChatterboxVCEngine
from .xtts import XTTSEngine

if sys.platform == "darwin":
    from .whisper_stt import WhisperSTTEngine as _STTEngine
else:
    # MLX yalnız Apple Silicon'da; diğer platformlar faster-whisper kullanır.
    from .whisper_stt_fw import FasterWhisperSTTEngine as _STTEngine

log = logging.getLogger("seslab.engines")


class EngineManager:
    def __init__(self) -> None:
        self.engines: dict[str, BaseEngine] = {
            "tts": ChatterboxTTSEngine(),
            "vc": ChatterboxVCEngine(),
            "stt": _STTEngine(),
            "xtts": XTTSEngine(),  # opsiyonel: .venv-xtts kuruluysa etkin
        }

    # -- erişim ---------------------------------------------------------------

    def ensure(self, name: str, checkpoint_dir: str | None = None) -> BaseEngine:
        """Motoru yükler (gerekirse çakışan ağır motoru boşaltarak) ve döndürür.

        XTTS ilk kez sese özgü bir modelle çağrılıyorsa checkpoint yüklemeden
        önce hazırlanır. Böylece önce varsayılan Emel'i yükleyip hemen Murat'a
        geçmek için ikinci kez 30 saniyelik worker kurulumu yapılmaz.
        """
        engine = self.engines[name]
        if engine.heavy:
            for other in self.engines.values():
                if other is not engine and other.heavy and other.is_loaded():
                    log.info("Ağır motor boşaltılıyor: %s (%s yüklenecek)",
                             other.name, name)
                    other.unload()
        if not engine.is_loaded():
            if isinstance(engine, XTTSEngine) and checkpoint_dir:
                engine.prepare_initial_checkpoint(checkpoint_dir)
            t0 = time.time()
            log.info("Motor yükleniyor: %s", name)
            engine.load()
            log.info("Motor yüklendi: %s (%.1f sn)", name, time.time() - t0)
        else:
            engine.touch()
        return engine

    # -- watchdog ---------------------------------------------------------------

    def rss_gb(self) -> float:
        return psutil.Process().memory_info().rss / 1e9

    def watchdog(self) -> None:
        """Her üretimden sonra çağrılır; gerekirse ağır motorları boşaltır."""
        rss = self.rss_gb()
        for engine in self.engines.values():
            if not (engine.heavy and engine.is_loaded()):
                continue
            over_rss = rss > RSS_LIMIT_GB
            over_count = engine.gen_count > 0 and engine.gen_count % RELOAD_EVERY_N == 0
            if over_rss or over_count:
                log.warning(
                    "Watchdog: %s boşaltılıyor (RSS=%.1f GB, üretim=%d)",
                    engine.name, rss, engine.gen_count,
                )
                engine.unload()

    def unload_idle(self) -> None:
        """Arka plan görevi: boşta kalan motorları boşalt (kilit korumalı)."""
        for engine in self.engines.values():
            if engine.unload_if_idle(IDLE_UNLOAD_S):
                log.info("Boşta motor boşaltıldı: %s", engine.name)

    def unload(self, name: str) -> None:
        self.engines[name].unload()

    # -- durum -----------------------------------------------------------------

    def status(self) -> dict:
        return {
            "rss_gb": round(self.rss_gb(), 2),
            "engines": {
                name: {
                    "loaded": e.is_loaded(),
                    "heavy": e.heavy,
                    "est_mem_gb": e.est_mem_gb,
                    "gen_count": e.gen_count,
                    "available": e.available(),
                }
                for name, e in self.engines.items()
            },
        }


# Uygulama genelinde tek örnek
manager = EngineManager()
