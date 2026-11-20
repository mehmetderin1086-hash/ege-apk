from __future__ import annotations

import ipaddress
from collections import deque
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from urllib.parse import urlparse

from fastapi import HTTPException, Request, status
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from bioprof.domain.models import PrivacyMode


def is_loopback_host(host: str) -> bool:
    normalized = host.strip("[]").lower()
    if normalized in {"localhost", "testclient", "testserver"}:
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def _is_json_request(scope: Scope) -> bool:
    for name, value in scope.get("headers", []):
        if name.lower() != b"content-type":
            continue
        media_type = value.split(b";", 1)[0].strip().lower()
        return media_type == b"application/json" or media_type.endswith(b"+json")
    return False


class JSONBodyLimitMiddleware:
    """Bound the aggregate JSON body even when no Content-Length is supplied."""

    def __init__(self, app: ASGIApp, maximum_bytes: int) -> None:
        if maximum_bytes < 1:
            raise ValueError("maximum_bytes pozitif olmalıdır")
        self.app = app
        self.maximum_bytes = maximum_bytes

    async def _reject(self, scope: Scope, receive: Receive, send: Send) -> None:
        response = JSONResponse(
            {"detail": "JSON istek gövdesi izin verilen toplam boyutu aşıyor."},
            status_code=status.HTTP_413_CONTENT_TOO_LARGE,
        )
        await response(scope, receive, send)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or not _is_json_request(scope):
            await self.app(scope, receive, send)
            return

        for name, value in scope.get("headers", []):
            if name.lower() != b"content-length":
                continue
            try:
                if int(value) > self.maximum_bytes:
                    await self._reject(scope, receive, send)
                    return
            except ValueError:
                # The server normally rejects malformed framing. Reading below still
                # enforces the authoritative aggregate limit.
                pass

        buffered: deque[Message] = deque()
        total = 0
        while True:
            message = await receive()
            buffered.append(message)
            if message["type"] == "http.disconnect":
                break
            if message["type"] != "http.request":
                continue
            total += len(message.get("body", b""))
            if total > self.maximum_bytes:
                await self._reject(scope, receive, send)
                return
            if not message.get("more_body", False):
                break

        async def replay() -> Message:
            if buffered:
                return buffered.popleft()
            return await receive()

        await self.app(scope, replay, send)


class LocalAccessMiddleware(BaseHTTPMiddleware):
    """Reject DNS rebinding and cross-site mutation attempts on the local app."""

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        host = request.url.hostname or ""
        if not is_loopback_host(host):
            return Response("BioProf yalnız yerel bağlantı kabul eder.", status_code=403)
        client_host = request.client.host if request.client else ""
        if client_host and not is_loopback_host(client_host):
            return Response("BioProf yalnız yerel istemci kabul eder.", status_code=403)

        if request.method not in {"GET", "HEAD", "OPTIONS"}:
            origin = request.headers.get("origin")
            if origin:
                origin_host = urlparse(origin).hostname or ""
                if not is_loopback_host(origin_host):
                    return Response("Çapraz site isteği reddedildi.", status_code=403)
            fetch_site = request.headers.get("sec-fetch-site")
            if fetch_site and fetch_site not in {"same-origin", "none"}:
                return Response("Çapraz site isteği reddedildi.", status_code=403)

        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Permissions-Policy", "camera=(), geolocation=(), payment=()")
        response.headers.setdefault(
            "Content-Security-Policy",
            "default-src 'self'; img-src 'self' data: blob:; media-src 'self' blob:; "
            "style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'",
        )
        if request.url.path.startswith(("/api/", "/v1/")):
            response.headers.setdefault("Cache-Control", "no-store")
        return response


@dataclass(frozen=True, slots=True)
class EgressDecision:
    allowed: bool
    reason: str


class EgressPolicy:
    def __init__(self, global_remote_enabled: bool = False) -> None:
        self.global_remote_enabled = global_remote_enabled

    def evaluate(
        self,
        *,
        privacy_mode: str | PrivacyMode,
        notebook_approved: bool,
        destination_is_loopback: bool,
    ) -> EgressDecision:
        if destination_is_loopback:
            return EgressDecision(True, "Yerel loopback servisi")
        mode = PrivacyMode(privacy_mode)
        if mode == PrivacyMode.LOCAL_ONLY:
            return EgressDecision(False, "Notebook local-only modunda")
        if not self.global_remote_enabled:
            return EgressDecision(False, "Uzak sağlayıcılar genel ayarda kapalı")
        if not notebook_approved:
            return EgressDecision(False, "Notebook için veri çıkışı onaylanmadı")
        return EgressDecision(True, "Açık notebook ve uygulama onayı mevcut")

    def require(self, **kwargs: object) -> None:
        decision = self.evaluate(**kwargs)  # type: ignore[arg-type]
        if not decision.allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Uzak veri çıkışı engellendi: {decision.reason}",
            )
