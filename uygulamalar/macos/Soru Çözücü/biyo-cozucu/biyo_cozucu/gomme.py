"""Anlamsal erişim için gömme (embedding) soyutlaması.

sentence-transformers kuruluysa Türkçe erişim modeli kullanılır; kurulu değilse
`gomlemci_yukle()` None döner ve sistem sözcüksel (BM25) erişimle çalışmaya
devam eder — gömme modeli sistemin çalışması için zorunlu değildir.

E5 ailesi asimetrik eğitilmiştir: sorgu ve belge farklı önekler ister. Öneki
atlamak erişim kalitesini sessizce düşürdüğü için model adına göre burada
otomatik seçilir.
"""

from __future__ import annotations

import os
from typing import Protocol

import numpy as np

# Türkçe erişim için birincil model (MIT lisanslı, multilingual-e5-large-instruct tabanlı).
VARSAYILAN_MODEL = "ytu-ce-cosmos/turkish-e5-large"
# sentence-transformers kurulu ama birincil model indirilemiyorsa kullanılacak yedek.
YEDEK_MODEL = "emrecan/bert-base-turkish-cased-mean-nli-stsb-tr"

GOREV_TANIMI = (
    "Verilen biyoloji sorusuna benzer, çözülmüş referans soruları getir"
)


class Gomlemci(Protocol):
    # `model_adi` sözleşmenin parçası: artımlı indeksleme, yeni vektörün
    # eskilerle AYNI uzayda olduğunu bununla doğruluyor
    # (`hafiza/indeks.py:_gomlemci_uyumlu_mu`). Protokolde bildirilmezse
    # denetim `getattr(..., "")` üzerinden sessizce boş dizgeye düşer ve
    # model değişimi fark edilmez.
    model_adi: str

    def gom(self, metinler: list[str], *, sorgu: bool = False) -> np.ndarray: ...


def _onekler(model_adi: str) -> tuple[str, str]:
    """(sorgu_oneki, belge_oneki) — model ailesine göre."""
    ad = model_adi.casefold()
    if "e5" in ad:
        if "instruct" in ad or "cosmos" in ad:
            return f"Instruct: {GOREV_TANIMI}\nQuery: ", ""
        return "query: ", "passage: "
    if "bge-m3" in ad or "gte" in ad:
        return "", ""
    return "", ""


class SbertGomlemci:
    """sentence-transformers tabanlı gömlemci (Mac'te MPS/CPU üzerinde çalışır)."""

    def __init__(self, model_adi: str = VARSAYILAN_MODEL, cihaz: str | None = None):
        from sentence_transformers import SentenceTransformer

        self.model_adi = model_adi
        self._model = SentenceTransformer(model_adi, device=cihaz)
        self._sorgu_oneki, self._belge_oneki = _onekler(model_adi)

    def gom(self, metinler: list[str], *, sorgu: bool = False) -> np.ndarray:
        if not metinler:
            return np.zeros((0, 1), dtype=np.float32)
        onek = self._sorgu_oneki if sorgu else self._belge_oneki
        girdiler = [onek + m for m in metinler] if onek else list(metinler)
        return np.asarray(
            self._model.encode(
                girdiler, normalize_embeddings=True, show_progress_bar=False
            ),
            dtype=np.float32,
        )


def gomlemci_yukle(model_adi: str | None = None) -> Gomlemci | None:
    """Gömlemciyi yüklemeyi dener; başarısızsa None döner (sistem çalışmaya devam eder).

    Model adı `BIYO_GOMME_MODEL` ortam değişkeniyle de verilebilir.
    """
    istenen = model_adi or os.environ.get("BIYO_GOMME_MODEL") or VARSAYILAN_MODEL
    for aday in dict.fromkeys([istenen, YEDEK_MODEL]):
        try:
            return SbertGomlemci(aday)
        except ImportError:
            return None  # kütüphane yok: yedek modeli denemenin anlamı yok
        # İndirme/ağ/uyumsuzluk hatalarında sessizce yedek modele düşülür:
        # gömme katmanı isteğe bağlıdır, yokluğunda sistem BM25 ile çalışır ve
        # burada patlamak tüm çözücüyü gereksiz yere durdururdu.
        except Exception:  # noqa: BLE001, S112
            continue
    return None


def kosinus(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Satır-normalize edilmemiş vektörler için güvenli kosinüs benzerlik matrisi."""
    a = a / np.clip(np.linalg.norm(a, axis=-1, keepdims=True), 1e-9, None)
    b = b / np.clip(np.linalg.norm(b, axis=-1, keepdims=True), 1e-9, None)
    return a @ b.T
