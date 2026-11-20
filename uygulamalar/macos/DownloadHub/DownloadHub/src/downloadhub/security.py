from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import re
import secrets
import socket
import unicodedata
from pathlib import Path
from urllib.parse import unquote, urlsplit, urlunsplit

from fastapi import HTTPException, status

PRIVATE_HOSTNAMES = {"localhost", "localhost.localdomain", "metadata.google.internal"}
INVALID_FILENAME = re.compile(r"[\x00-\x1f/:\\]+")
SECRET_QUERY_KEYS = {
    "access_token",
    "api_key",
    "apikey",
    "auth",
    "authorization",
    "client_secret",
    "googleaccessid",
    "hdnea",
    "hdnts",
    "hmac",
    "jwt",
    "key",
    "key_pair_id",
    "keypairid",
    "password",
    "policy",
    "secret",
    "session",
    "sessionid",
    "signature",
    "sig",
    "ticket",
    "token",
}

URL_IN_TEXT = re.compile(r"https?://[^\s<>\"']+", re.IGNORECASE)


def is_secret_query_key(value: str) -> bool:
    normalized = unquote(value).casefold().replace("-", "_")
    if normalized in SECRET_QUERY_KEYS:
        return True
    parts = {part for part in normalized.split("_") if part}
    return bool(
        parts
        & {
            "auth",
            "authorization",
            "credential",
            "hmac",
            "jwt",
            "password",
            "secret",
            "session",
            "signature",
            "ticket",
            "token",
        }
    )


def has_sensitive_query(raw_url: str) -> bool:
    try:
        query = urlsplit(raw_url).query
    except ValueError:
        return False
    return any(is_secret_query_key(item.partition("=")[0]) for item in query.split("&") if item)


def hash_secret(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def new_token() -> str:
    return secrets.token_urlsafe(36)


def sanitize_filename(value: str, fallback: str = "indirme") -> str:
    value = unicodedata.normalize("NFC", unquote(value)).strip()
    value = INVALID_FILENAME.sub("_", value)
    value = re.sub(r"\s+", " ", value).strip(" .")
    if not value or value in {".", ".."}:
        value = fallback
    if value.startswith("."):
        value = f"_{value[1:]}"
    encoded = value.encode("utf-8")
    if len(encoded) > 220:
        suffix = Path(value).suffix[:20]
        stem = Path(value).stem
        while len((stem + suffix).encode("utf-8")) > 220:
            stem = stem[:-1]
        value = stem.rstrip() + suffix
    return value


def unique_path(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suffix = path.stem, path.suffix
    for number in range(1, 10_000):
        candidate = path.with_name(f"{stem} ({number}){suffix}")
        if not candidate.exists():
            return candidate
    raise RuntimeError("Benzersiz dosya adı üretilemedi")


def ensure_allowed_path(path: Path, roots: list[Path]) -> Path:
    resolved = path.expanduser().resolve(strict=False)
    for root in roots:
        resolved_root = root.expanduser().resolve(strict=False)
        try:
            resolved.relative_to(resolved_root)
            return resolved
        except ValueError:
            continue
    raise HTTPException(status_code=403, detail="Dosya izin verilen indirme alanının dışında")


def redact_url(raw_url: str, *, all_query_values: bool = False) -> str:
    try:
        parts = urlsplit(raw_url)
        if not parts.query:
            return raw_url
        pairs = []
        for item in parts.query.split("&"):
            key, separator, value = item.partition("=")
            if all_query_values or is_secret_query_key(key):
                value = "[GİZLİ]"
            pairs.append(key + (separator + value if separator else ""))
        return urlunsplit((parts.scheme, parts.netloc, parts.path, "&".join(pairs), ""))
    except ValueError:
        return "[GEÇERSİZ URL]"


def redact_sensitive_text(value: str) -> str:
    """Remove URL query values and common inline credentials before persistence."""

    redacted = URL_IN_TEXT.sub(
        lambda match: redact_url(match.group(0), all_query_values=True),
        value,
    )
    return re.sub(
        r"(?i)\b(cookie|token|authorization|password|secret)\s*[:=]\s*[^\s,;]+",
        r"\1=[GİZLİ]",
        redacted,
    )


async def validate_http_url(raw_url: str, *, allow_private: bool = False) -> str:
    normalized, _addresses = await resolve_http_target(raw_url, allow_private=allow_private)
    return normalized


async def resolve_http_target(
    raw_url: str,
    *,
    allow_private: bool = False,
) -> tuple[str, tuple[str, ...]]:
    try:
        parsed = urlsplit(raw_url)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="Geçersiz URL") from exc
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise HTTPException(status_code=422, detail="Yalnız HTTP ve HTTPS adresleri desteklenir")
    if parsed.username or parsed.password:
        raise HTTPException(status_code=422, detail="URL içinde kullanıcı adı/parola kabul edilmez")
    hostname = parsed.hostname.rstrip(".").lower()
    if not allow_private and hostname in PRIVATE_HOSTNAMES:
        raise HTTPException(status_code=403, detail="Yerel ve özel ağ adresleri engellendi")
    loop = asyncio.get_running_loop()
    try:
        records = await loop.run_in_executor(
            None,
            lambda: socket.getaddrinfo(hostname, parsed.port or 443, type=socket.SOCK_STREAM),
        )
    except socket.gaierror as exc:
        raise HTTPException(status_code=422, detail="Alan adı çözümlenemedi") from exc
    addresses = tuple(dict.fromkeys(record[4][0] for record in records))
    if not addresses:
        raise HTTPException(status_code=422, detail="Alan adı çözümlenemedi")
    for value in addresses:
        address = ipaddress.ip_address(value)
        if not allow_private and not address.is_global:
            raise HTTPException(status_code=403, detail="Yerel ve özel ağ adresleri engellendi")
    return raw_url, addresses


def require_extension_origin(origin: str | None) -> str:
    if not origin or not origin.startswith("chrome-extension://"):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Geçersiz eklenti origin'i")
    return origin.rstrip("/")
