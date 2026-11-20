"""Small, dependency-light adapter for OpenAI-compatible HTTP servers."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Callable, Mapping
from typing import Any
from urllib.parse import urlparse

import httpx

from bioprof.domain.models import ProviderCapabilities
from bioprof.providers.base import (
    AuthenticationError,
    ChatResult,
    EmbeddingResult,
    ProviderError,
    ProviderUnavailableError,
    ResponseResult,
    UnsupportedCapabilityError,
)

SecretGetter = Callable[[], str | None]


def _is_loopback(url: str) -> bool:
    hostname = (urlparse(url).hostname or "").casefold()
    return hostname in {"localhost", "127.0.0.1", "::1"}


def _content_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if not isinstance(value, list):
        return ""
    parts: list[str] = []
    for item in value:
        if not isinstance(item, Mapping):
            continue
        text = item.get("text") or item.get("output_text")
        if isinstance(text, str):
            parts.append(text)
    return "".join(parts)


def _response_output_text(body: Mapping[str, Any]) -> str:
    direct = body.get("output_text")
    if isinstance(direct, str):
        return direct
    parts: list[str] = []
    output = body.get("output")
    if isinstance(output, list):
        for item in output:
            if not isinstance(item, Mapping):
                continue
            content = item.get("content")
            if isinstance(content, list):
                for part in content:
                    if not isinstance(part, Mapping):
                        continue
                    text = part.get("text") or part.get("output_text")
                    if isinstance(text, str):
                        parts.append(text)
    return "".join(parts)


class OpenAICompatibleProvider:
    """OpenAI-compatible adapter with explicit, independently probed features."""

    def __init__(
        self,
        *,
        name: str,
        base_url: str,
        api_key: str | SecretGetter | None = None,
        requires_egress: bool | None = None,
        require_api_key: bool = False,
        timeout: float = 120.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.name = name
        self.base_url = base_url.rstrip("/")
        self._api_key = api_key
        self.requires_egress = (
            not _is_loopback(base_url) if requires_egress is None else requires_egress
        )
        self.require_api_key = require_api_key
        self._client = client
        self._owns_client = client is None
        self.timeout = timeout
        self._last_capabilities: ProviderCapabilities | None = None

    async def __aenter__(self) -> OpenAICompatibleProvider:
        return self

    async def __aexit__(self, *_: object) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()
            self._client = None

    def _secret(self) -> str | None:
        value = self._api_key() if callable(self._api_key) else self._api_key
        return value or None

    def _headers(self, *, require_auth: bool = True) -> dict[str, str]:
        secret = self._secret()
        if require_auth and self.require_api_key and not secret:
            raise AuthenticationError(self.name)
        headers = {"Accept": "application/json"}
        if secret:
            headers["Authorization"] = f"Bearer {secret}"
        return headers

    def _http(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=self.timeout,
                follow_redirects=False,
                trust_env=False,
            )
        return self._client

    def _safe_error(self, response: httpx.Response) -> ProviderError:
        if response.status_code in {401, 403}:
            return AuthenticationError(self.name)
        message = f"'{self.name}' HTTP {response.status_code} döndürdü."
        try:
            body = response.json()
            candidate = body.get("error", body) if isinstance(body, Mapping) else None
            if isinstance(candidate, Mapping) and isinstance(candidate.get("message"), str):
                public_message = candidate["message"].replace(self._secret() or "\0", "<redacted>")
                message = f"{message} {public_message[:300]}"
        except (ValueError, TypeError):
            pass
        return ProviderError(message, status_code=502)

    async def _request(
        self,
        method: str,
        path: str,
        *,
        payload: Mapping[str, Any] | None = None,
    ) -> httpx.Response:
        try:
            response = await self._http().request(
                method,
                f"{self.base_url}{path}",
                headers=self._headers(),
                json=dict(payload) if payload is not None else None,
            )
        except AuthenticationError:
            raise
        except httpx.HTTPError as exc:
            raise ProviderUnavailableError(
                f"'{self.name}' servisine bağlanılamadı: {exc.__class__.__name__}."
            ) from exc
        if response.is_error:
            raise self._safe_error(response)
        return response

    async def _route_exists(self, path: str) -> bool:
        try:
            response = await self._http().request(
                "OPTIONS",
                f"{self.base_url}{path}",
                headers=self._headers(require_auth=False),
            )
        except (ProviderError, httpx.HTTPError):
            return False
        return response.status_code != 404

    async def probe(self, *, active: bool = False) -> ProviderCapabilities:
        details: dict[str, Any] = {"base_url": self.base_url, "active_probe": active}
        health_ok = False
        ready_ok = False
        for label, path in (("health", "/healthz"), ("ready", "/readyz")):
            try:
                response = await self._http().get(
                    f"{self.base_url}{path}",
                    headers=self._headers(require_auth=False),
                    timeout=5,
                )
                details[f"{label}_status"] = response.status_code
                if label == "health":
                    health_ok = response.is_success
                else:
                    ready_ok = response.is_success
            except (ProviderError, httpx.HTTPError) as exc:
                details[f"{label}_error"] = exc.__class__.__name__

        models: list[str] = []
        auth_ok = True
        try:
            response = await self._http().get(
                f"{self.base_url}/v1/models",
                headers=self._headers(require_auth=False),
                timeout=10,
            )
            details["models_status"] = response.status_code
            auth_ok = response.status_code not in {401, 403}
            if response.is_success:
                body = response.json()
                data = body.get("data", []) if isinstance(body, Mapping) else []
                models = [
                    str(item["id"])
                    for item in data
                    if isinstance(item, Mapping) and item.get("id")
                ]
        except (ProviderError, httpx.HTTPError, ValueError) as exc:
            details["models_error"] = exc.__class__.__name__

        chat = await self._route_exists("/v1/chat/completions")
        responses = await self._route_exists("/v1/responses")
        embeddings = await self._route_exists("/v1/embeddings")

        if active and models:
            model = models[0]
            if chat:
                try:
                    await self.chat(
                        {
                            "model": model,
                            "messages": [{"role": "user", "content": "ping"}],
                            "max_tokens": 1,
                        }
                    )
                    details["chat_active"] = True
                except ProviderError as exc:
                    details["chat_active"] = False
                    details["chat_error"] = exc.code
            if responses:
                try:
                    await self.responses({"model": model, "input": "ping", "max_output_tokens": 1})
                    details["responses_active"] = True
                except ProviderError as exc:
                    details["responses_active"] = False
                    details["responses_error"] = exc.code

        ready_status = details.get("ready_status")
        ready_gate = ready_ok or ready_status in {None, 404}
        capabilities = ProviderCapabilities(
            name=self.name,
            available=(health_ok or bool(models)) and auth_ok and ready_gate,
            models=models,
            chat=chat,
            responses=responses,
            streaming=chat or responses,
            embeddings=embeddings,
            details=details,
        )
        self._last_capabilities = capabilities
        return capabilities

    async def chat(self, payload: Mapping[str, Any]) -> ChatResult:
        body_payload = dict(payload)
        body_payload["stream"] = False
        response = await self._request("POST", "/v1/chat/completions", payload=body_payload)
        body = response.json()
        choices = body.get("choices", []) if isinstance(body, Mapping) else []
        if not choices or not isinstance(choices[0], Mapping):
            raise ProviderError(f"'{self.name}' geçerli bir chat yanıtı döndürmedi.")
        choice = choices[0]
        message = choice.get("message", {})
        text = _content_text(message.get("content")) if isinstance(message, Mapping) else ""
        return ChatResult(
            text=text,
            model=str(body.get("model") or payload.get("model") or "unknown"),
            provider=self.name,
            finish_reason=str(choice.get("finish_reason") or "stop"),
            usage={k: int(v) for k, v in body.get("usage", {}).items() if isinstance(v, int)},
            raw=dict(body),
        )

    async def _stream(self, path: str, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        body_payload = dict(payload)
        body_payload["stream"] = True
        try:
            async with self._http().stream(
                "POST",
                f"{self.base_url}{path}",
                headers=self._headers(),
                json=body_payload,
            ) as response:
                if response.is_error:
                    await response.aread()
                    raise self._safe_error(response)
                async for line in response.aiter_lines():
                    if not line or line.startswith(":"):
                        continue
                    data = line[5:].strip() if line.startswith("data:") else line
                    if data == "[DONE]":
                        return
                    try:
                        event = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    if isinstance(event, dict):
                        yield event
        except ProviderError:
            raise
        except httpx.HTTPError as exc:
            raise ProviderUnavailableError(
                f"'{self.name}' akış bağlantısı kesildi: {exc.__class__.__name__}."
            ) from exc

    def stream_chat(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        return self._stream("/v1/chat/completions", payload)

    async def responses(self, payload: Mapping[str, Any]) -> ResponseResult:
        body_payload = dict(payload)
        body_payload["stream"] = False
        response = await self._request("POST", "/v1/responses", payload=body_payload)
        body = response.json()
        if not isinstance(body, Mapping):
            raise ProviderError(f"'{self.name}' geçerli bir Responses yanıtı döndürmedi.")
        return ResponseResult(
            text=_response_output_text(body),
            model=str(body.get("model") or payload.get("model") or "unknown"),
            provider=self.name,
            status=str(body.get("status") or "completed"),
            usage={k: int(v) for k, v in body.get("usage", {}).items() if isinstance(v, int)},
            raw=dict(body),
        )

    def stream_responses(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        return self._stream("/v1/responses", payload)

    async def embeddings(self, payload: Mapping[str, Any]) -> EmbeddingResult:
        if self._last_capabilities is not None and not self._last_capabilities.embeddings:
            raise UnsupportedCapabilityError("embeddings", self.name)
        response = await self._request("POST", "/v1/embeddings", payload=payload)
        body = response.json()
        data = body.get("data", []) if isinstance(body, Mapping) else []
        vectors = [
            [float(value) for value in item.get("embedding", [])]
            for item in data
            if isinstance(item, Mapping)
        ]
        return EmbeddingResult(
            vectors=vectors,
            model=str(body.get("model") or payload.get("model") or "unknown"),
            provider=self.name,
            usage={k: int(v) for k, v in body.get("usage", {}).items() if isinstance(v, int)},
            raw=dict(body),
        )
