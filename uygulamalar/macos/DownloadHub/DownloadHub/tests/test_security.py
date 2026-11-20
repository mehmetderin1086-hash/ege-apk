from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import HTTPException

from downloadhub.security import (
    ensure_allowed_path,
    has_sensitive_query,
    redact_sensitive_text,
    redact_url,
    sanitize_filename,
    unique_path,
    validate_http_url,
)


@pytest.mark.asyncio
async def test_rejects_private_network_by_default() -> None:
    with pytest.raises(HTTPException) as error:
        await validate_http_url("http://127.0.0.1/private")
    assert error.value.status_code == 403


@pytest.mark.asyncio
async def test_allows_private_network_only_when_explicit() -> None:
    assert await validate_http_url("http://127.0.0.1/file", allow_private=True) == ("http://127.0.0.1/file")


def test_sanitizes_filename_and_keeps_extension() -> None:
    assert sanitize_filename("../../tehlikeli:dosya.pdf") == "_.._tehlikeli_dosya.pdf"
    assert not sanitize_filename(".env").startswith(".")
    assert len(sanitize_filename("ü" * 500 + ".zip").encode()) <= 220


def test_unique_path_never_overwrites(tmp_path: Path) -> None:
    existing = tmp_path / "rapor.pdf"
    existing.write_bytes(b"original")
    assert unique_path(existing).name == "rapor (1).pdf"


def test_path_confinement(tmp_path: Path) -> None:
    root = tmp_path / "downloads"
    root.mkdir()
    assert ensure_allowed_path(root / "file.bin", [root]) == root / "file.bin"
    with pytest.raises(HTTPException):
        ensure_allowed_path(tmp_path / "secret", [root])


def test_redacts_sensitive_query_values() -> None:
    redacted = redact_url("https://example.com/file?token=abc&part=1&signature=xyz")
    assert "abc" not in redacted
    assert "xyz" not in redacted
    assert "part=1" in redacted


@pytest.mark.parametrize(
    "key",
    ["hdnea", "hmac", "jwt", "Key-Pair-Id", "GoogleAccessId", "client_secret"],
)
def test_recognizes_common_signed_url_keys(key: str) -> None:
    raw_url = f"https://cdn.example/video?{key}=super-secret&part=1"
    assert has_sensitive_query(raw_url)
    assert "super-secret" not in redact_url(raw_url)


def test_redacts_all_url_query_values_from_persisted_error_text() -> None:
    message = "500 Server Error for url 'https://cdn.example/file?id=12&opaque=secret-value'"
    redacted = redact_sensitive_text(message)
    assert "secret-value" not in redacted
    assert "id=[GİZLİ]" in redacted
    assert "opaque=[GİZLİ]" in redacted
