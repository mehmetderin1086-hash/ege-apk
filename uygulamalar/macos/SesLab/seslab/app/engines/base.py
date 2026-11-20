"""Motor temel sınıfı — tembel yükleme, kilit, bellek muhasebesi."""
from __future__ import annotations

import gc
import threading
import time


def patch_torch_load_for_mps() -> None:
    """Chatterbox checkpoint'leri CUDA etiketli kaydedilmiş; MPS'e yönlendir.

    (resemble-ai/chatterbox example_for_mac.py deseni.)
    """
    import torch

    if not torch.backends.mps.is_available():
        return
    if getattr(torch.load, "_seslab_patched", False):
        return
    original = torch.load

    def patched(*args, **kwargs):
        if len(args) < 2 and "map_location" not in kwargs:
            kwargs["map_location"] = torch.device("mps")
        return original(*args, **kwargs)

    patched._seslab_patched = True
    torch.load = patched


def free_torch_memory() -> None:
    """MPS önbelleğini boşalt + çöp topla (bellek sızıntısı önlemi)."""
    gc.collect()
    try:
        import torch

        if torch.backends.mps.is_available():
            torch.mps.empty_cache()
    except ImportError:
        pass


class BaseEngine:
    """Tüm motorların temeli.

    Alt sınıflar `_load()` ve `_unload()` uygular. `heavy=True` motorlardan
    aynı anda yalnızca biri bellekte tutulur (EngineManager politikası).
    """

    name: str = "base"
    est_mem_gb: float = 0.0
    heavy: bool = False
    # None → manager'ın genel IDLE_UNLOAD_S değeri; motor kendi süresini
    # geçersiz kılabilir (XTTS: 30 dk — yeniden yükleme pahalı)
    idle_timeout_s: float | None = None

    @staticmethod
    def available() -> bool:
        """Motor bu kurulumda kullanılabilir mi? (XTTS ayrı venv ister.)"""
        return True

    def busy(self) -> bool:
        """Şu an üretim sürüyor mu? (Havuzlu motorlar geçersiz kılar.)"""
        return False

    def __init__(self) -> None:
        self._model = None
        self.lock = threading.Lock()
        self.gen_count = 0
        self.last_used = 0.0

    # -- yaşam döngüsü -------------------------------------------------------

    def load(self) -> None:
        with self.lock:
            if self._model is None:
                self._load()
            self.last_used = time.time()

    def unload(self) -> None:
        with self.lock:
            if self._model is not None:
                self._unload()
                self._model = None
        free_torch_memory()

    def unload_if_idle(self, idle_s: float) -> bool:
        """Kilit ALTINDA boşta kontrolü + boşaltma — üretimle yarışmaz.

        (Üretim metotları aynı kilidi tutar VEYA busy() bildirir; süren bir
        üretimin ortasında model elden alınamaz.)
        """
        timeout = self.idle_timeout_s if self.idle_timeout_s else idle_s
        with self.lock:
            if (
                self._model is None
                or self.busy()
                or time.time() - self.last_used <= timeout
            ):
                return False
            self._unload()
            self._model = None
        free_torch_memory()
        return True

    def is_loaded(self) -> bool:
        return self._model is not None

    def touch(self) -> None:
        self.last_used = time.time()

    # -- alt sınıflar uygular --------------------------------------------------

    def _load(self) -> None:
        raise NotImplementedError

    def _unload(self) -> None:
        pass
