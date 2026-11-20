"""Çalışan OCR bileşenlerinin yeniden üretilebilir model kaydı."""

from __future__ import annotations

import hashlib
from pathlib import Path
from typing import Iterable


def _kisa_parmakizi(yol: Path) -> str:
    """Büyük ağırlığı okumadan dosya kimliğini sürümlendir."""
    bilgi = yol.stat()
    ham = f"{yol.resolve()}:{bilgi.st_size}:{bilgi.st_mtime_ns}".encode()
    return hashlib.sha256(ham).hexdigest()[:16]


def model_kaydi(motorlar: Iterable[tuple]) -> dict:
    kayitlar: list[dict] = []
    for motor_verisi in motorlar:
        ad, motor = motor_verisi[0], motor_verisi[1]
        kayit = {
            "ad": str(ad),
            "sinif": f"{motor.__class__.__module__}.{motor.__class__.__name__}",
        }
        model_yolu = getattr(motor, "model_yolu", None) or getattr(
            motor, "model_dir", None
        )
        if model_yolu:
            yol = Path(model_yolu)
            kayit["model_yolu"] = str(yol)
            if yol.is_file():
                kayit["parmakizi"] = _kisa_parmakizi(yol)
            elif yol.is_dir():
                aday = next(
                    (
                        p
                        for ad_ in ("config.json", "model.safetensors", "pytorch_model.bin")
                        if (p := yol / ad_).exists()
                    ),
                    None,
                )
                if aday:
                    kayit["parmakizi"] = _kisa_parmakizi(aday)
        aygit = getattr(motor, "device", None) or getattr(motor, "_device", None)
        if aygit is not None:
            kayit["aygit"] = str(aygit)
        kayitlar.append(kayit)
    return {"boru_hatti": "siyah-kursun-v2", "motorlar": kayitlar}

