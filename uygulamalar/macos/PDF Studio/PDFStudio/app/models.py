"""Ortak API şemaları (pydantic)."""
from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class FileInfo(BaseModel):
    file_id: str
    name: str
    size: int
    kind: str
    pages: int | None = None


class UploadResponse(BaseModel):
    session_id: str
    files: list[FileInfo]


class OutputInfo(BaseModel):
    file_id: str
    name: str
    size: int
    kind: str
    download_url: str


class ProcessResponse(BaseModel):
    session_id: str
    message: str
    outputs: list[OutputInfo]
    meta: dict[str, Any] | None = None


class ErrorResponse(BaseModel):
    detail: str
