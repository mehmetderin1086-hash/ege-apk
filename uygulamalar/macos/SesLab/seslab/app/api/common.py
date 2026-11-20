"""API katmanı ortak yardımcıları."""
from __future__ import annotations

from fastapi import HTTPException, UploadFile

MAX_UPLOAD_MB = 200  # 16 GB RAM bütçesinde sınırsız yükleme kabul edilemez


async def read_limited(file: UploadFile, max_mb: int = MAX_UPLOAD_MB) -> bytes:
    """Yüklemeyi boyut sınırıyla okur; aşarsa 413 döndürür."""
    max_bytes = max_mb * 1024 * 1024
    data = await file.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise HTTPException(
            413, f"Dosya çok büyük (sınır: {max_mb} MB). Daha kısa bir kayıt deneyin."
        )
    if not data:
        raise HTTPException(400, "Boş dosya")
    return data
