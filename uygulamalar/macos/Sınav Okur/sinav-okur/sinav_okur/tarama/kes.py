"""Cevap görüntüsünde boşluk (mürekkep) kontrolü."""

from __future__ import annotations

import cv2
import numpy as np

def murekkep_orani(kirp: np.ndarray) -> float:
    """Kırpıntıdaki mürekkepli piksel oranı (0-1); boş kutu tespiti için."""
    if kirp.size == 0:
        return 0.0
    gri = cv2.cvtColor(kirp, cv2.COLOR_BGR2GRAY) if kirp.ndim == 3 else kirp
    ikili = cv2.adaptiveThreshold(
        gri, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 31, 15
    )
    return float(np.count_nonzero(ikili)) / ikili.size


def bos_mu(kirp: np.ndarray, esik: float = 0.003) -> bool:
    return murekkep_orani(kirp) < esik
