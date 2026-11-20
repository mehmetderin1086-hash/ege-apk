"""Dil modeli motorları: yerel MLX (metin ve görsel) ve OpenAI-uyumlu HTTP."""

from __future__ import annotations

import os

from .temel import (
    GorselMotor,
    Motor,
    MotorHatasi,
    SahteGorselMotor,
    SahteMotor,
    dusunceyi_ayikla,
    json_ayikla,
)

__all__ = [
    "GorselMotor",
    "Motor",
    "MotorHatasi",
    "SahteGorselMotor",
    "SahteMotor",
    "dusunceyi_ayikla",
    "json_ayikla",
    "motor_yukle",
]


def motor_yukle(tur: str | None = None, **secenekler) -> Motor:
    """Motoru adıyla kurar: ``mlx`` | ``vlm`` | ``karma`` | ``http`` | ``sahte``.

    Varsayılan `BIYO_MOTOR` ortam değişkeninden, o da yoksa ``mlx``.
    """
    tur = (tur or os.environ.get("BIYO_MOTOR", "mlx")).strip().casefold()
    if tur == "mlx":
        from .mlx_motor import MlxMotor

        return MlxMotor(**secenekler)
    if tur in {"vlm", "gorsel"}:
        from .vlm_motor import VlmMotor

        return VlmMotor(**secenekler)
    if tur in {"karma", "hibrit"}:
        from .karma_motor import KarmaMotor

        return KarmaMotor(**secenekler)
    if tur in {"http", "openai", "proxy"}:
        from .http_motor import HttpMotor

        return HttpMotor(**secenekler)
    if tur == "sahte":
        return SahteMotor(**secenekler)
    if tur in {"sahte-gorsel", "sahtegorsel"}:
        return SahteGorselMotor(**secenekler)
    raise MotorHatasi(f"Bilinmeyen motor türü: {tur}")
