"""Anlamsal benzerlik için gömme (embedding) soyutlaması.

sentence-transformers kuruluysa Türkçe STS modeli kullanılır; kurulu değilse
puanlama sözcüksel (fuzzy) katmanla sınırlı kalır — sistem çalışmaya devam eder.
"""

from __future__ import annotations

import os
from typing import Protocol

import numpy as np

# transformers, TensorFlow kuruluysa TF yolunu da yüklemeye çalışır ve
# Keras 3 ile çakışıp ValueError fırlatır — bu makinede gömlemci tam olarak
# bu yüzden hiç yüklenemiyordu. Import'tan ÖNCE ayarlanmalı.
os.environ.setdefault("USE_TF", "0")
os.environ.setdefault("TRANSFORMERS_NO_TF", "1")

VARSAYILAN_MODEL = "emrecan/bert-base-turkish-cased-mean-nli-stsb-tr"


class Gomlemci(Protocol):
    def gom(self, metinler: list[str]) -> np.ndarray: ...


class SbertGomlemci:
    """sentence-transformers tabanlı gömlemci (Mac'te MPS/CPU üzerinde çalışır)."""

    def __init__(self, model_adi: str = VARSAYILAN_MODEL, cihaz: str | None = None):
        from sentence_transformers import SentenceTransformer

        self._model = SentenceTransformer(model_adi, device=cihaz)

    def gom(self, metinler: list[str]) -> np.ndarray:
        return np.asarray(
            self._model.encode(metinler, normalize_embeddings=True, show_progress_bar=False)
        )


def gomlemci_yukle(model_adi: str | None = None) -> Gomlemci | None:
    """Gömlemciyi yüklemeyi dener; yüklenemezse ``None`` döner.

    Yalnız ``ImportError`` yakalamak yetmiyordu: Keras/TF çakışması
    ``ValueError``, bozuk önbellek ``OSError``, uyumsuz sürüm
    ``RuntimeError`` fırlatıyor ve bunlar çağıranlara sızıp puanlamayı
    tamamen düşürüyordu. Gömlemci opsiyoneldir; yokluğunda sistem sözcüksel
    katmanla çalışmaya devam etmeli.
    """
    try:
        return SbertGomlemci(model_adi or VARSAYILAN_MODEL)
    except (ImportError, OSError, ValueError, RuntimeError):
        return None


def kosinus(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Satır-normalize edilmemiş vektörler için güvenli kosinüs benzerlik matrisi."""
    a = a / np.clip(np.linalg.norm(a, axis=-1, keepdims=True), 1e-9, None)
    b = b / np.clip(np.linalg.norm(b, axis=-1, keepdims=True), 1e-9, None)
    return a @ b.T
