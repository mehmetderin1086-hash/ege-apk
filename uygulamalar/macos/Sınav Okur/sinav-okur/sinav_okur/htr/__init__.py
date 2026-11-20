"""El yazısı tanıma soyutlaması; kazananı gerçek, yazar-ayrık CER/WER belirler."""

from __future__ import annotations

from typing import Protocol

import numpy as np

from ..modeller import TanimaSonucu


class Taniyici(Protocol):
    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        """Bir cevap kutusu kırpıntısındaki tüm metni tanır."""
        ...


class YapayTaniyici:
    """Test ve kuru-çalıştırma için sabit metin dönen tanıyıcı."""

    def __init__(self, metin: str = "", guven: float = 1.0):
        self.metin, self.guven = metin, guven

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        return TanimaSonucu(metin=self.metin, guven=self.guven)


def taniyici_yukle(tur: str = "trocr", model_yolu: str | None = None) -> Taniyici:
    """Tanıyıcı fabrikası."""
    if tur == "coklu":
        from .coklu import CokluTaniyici
        from .vision import VisionTaniyici

        return CokluTaniyici([("apple-vision", VisionTaniyici())])
    if tur == "vision":
        from .vision import VisionTaniyici

        return VisionTaniyici()
    if tur == "trocr":
        from .trocr import TrocrTaniyici, yerel_model_yolu

        yol = model_yolu or yerel_model_yolu()
        return TrocrTaniyici(yol) if yol else TrocrTaniyici()
    if tur == "mlx":
        from .mlxvlm import MlxVlmTaniyici

        return MlxVlmTaniyici(model_yolu) if model_yolu else MlxVlmTaniyici()
    if tur == "keras-karakter":
        from .keras_cnn import KerasKarakterTaniyici

        return KerasKarakterTaniyici(model_yolu)
    if tur == "keras-ctc":
        from .keras_ctc import KerasCtcTaniyici

        return KerasCtcTaniyici(model_yolu)
    if tur == "yapay":
        return YapayTaniyici()
    raise ValueError(f"Bilinmeyen tanıyıcı türü: {tur}")


__all__ = [
    "Taniyici",
    "YapayTaniyici",
    "taniyici_yukle",
    "TanimaSonucu",
    "CokluTaniyici",
]


def __getattr__(ad: str):
    if ad == "CokluTaniyici":
        from .coklu import CokluTaniyici

        return CokluTaniyici
    raise AttributeError(ad)
