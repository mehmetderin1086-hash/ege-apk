"""sinav-okur: Türkçe el yazısı sınavlarını okuyup puanlayan sistem."""

from .modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
    TanimaSonucu,
)

__version__ = "0.1.0"

__all__ = [
    "Sinav",
    "Soru",
    "SoruTipi",
    "CevapAnahtari",
    "RubrikKalemi",
    "TanimaSonucu",
    "__version__",
]
