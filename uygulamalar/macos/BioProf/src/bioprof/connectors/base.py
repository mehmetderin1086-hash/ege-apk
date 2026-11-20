from __future__ import annotations

import asyncio
import email.utils
import time
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

import httpx

from bioprof.connectors.models import ConnectorError, RateLimitError


class AsyncRateLimiter:
    """A monotonic, process-local minimum-interval limiter."""

    def __init__(self, requests_per_second: float) -> None:
        if requests_per_second <= 0:
            raise ValueError("requests_per_second must be positive")
        self._minimum_interval = 1.0 / requests_per_second
        self._lock = asyncio.Lock()
        self._next_at = 0.0

    async def wait(self) -> None:
        async with self._lock:
            now = time.monotonic()
            delay = max(0.0, self._next_at - now)
            if delay:
                await asyncio.sleep(delay)
                now = time.monotonic()
            self._next_at = now + self._minimum_interval


def _retry_after_seconds(value: str | None) -> float:
    if not value:
        return 1.0
    try:
        return max(0.0, min(float(value), 30.0))
    except ValueError:
        try:
            parsed = email.utils.parsedate_to_datetime(value)
            return max(0.0, min((parsed - datetime.now(UTC)).total_seconds(), 30.0))
        except (TypeError, ValueError):
            return 1.0


class OfficialAPIConnector:
    """HTTP helper constrained to a fixed, official API origin.

    Callers can only provide relative paths.  Redirects are disabled so an API
    response cannot redirect the local-first application to an arbitrary host.
    """

    base_url: str
    provider_name: str

    def __init__(
        self,
        *,
        base_url: str,
        provider_name: str,
        requests_per_second: float,
        client: httpx.AsyncClient | None = None,
        user_agent: str = "BioProf/0.1 (educational-research; local application)",
    ) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.provider_name = provider_name
        self._limiter = AsyncRateLimiter(requests_per_second)
        self._owns_client = client is None
        self._client = client or httpx.AsyncClient(
            base_url=self.base_url,
            headers={"User-Agent": user_agent, "Accept": "application/json, application/xml"},
            follow_redirects=False,
            timeout=httpx.Timeout(30.0, connect=10.0),
            trust_env=False,
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def _get(
        self,
        path: str,
        *,
        params: Mapping[str, Any] | None = None,
        accept: str | None = None,
    ) -> httpx.Response:
        if path.startswith(("http://", "https://", "//")) or ".." in path.split("/"):
            raise ConnectorError("Connector paths must be safe, relative API paths")
        headers = {"Accept": accept} if accept else None
        last_error: Exception | None = None
        for attempt in range(3):
            await self._limiter.wait()
            try:
                response = await self._client.get(path.lstrip("/"), params=params, headers=headers)
            except httpx.HTTPError as exc:
                last_error = exc
                if attempt < 2:
                    await asyncio.sleep(0.25 * 2**attempt)
                    continue
                raise ConnectorError(f"{self.provider_name} bağlantı hatası: {exc}") from exc
            if response.status_code in {301, 302, 303, 307, 308}:
                raise ConnectorError(f"{self.provider_name} beklenmeyen yönlendirme döndürdü")
            if response.status_code == 429:
                if attempt < 2:
                    await asyncio.sleep(_retry_after_seconds(response.headers.get("Retry-After")))
                    continue
                raise RateLimitError(f"{self.provider_name} istek sınırı aşıldı")
            if response.status_code >= 500 and attempt < 2:
                await asyncio.sleep(0.25 * 2**attempt)
                continue
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                detail = response.text[:300].replace("\n", " ")
                raise ConnectorError(
                    f"{self.provider_name} HTTP {response.status_code}: {detail}"
                ) from exc
            return response
        raise ConnectorError(f"{self.provider_name} isteği başarısız: {last_error}")
