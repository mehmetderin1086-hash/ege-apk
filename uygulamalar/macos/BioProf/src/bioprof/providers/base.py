"""Provider contracts and safety errors.

The provider layer deliberately has no automatic fallback.  A caller selects one
provider and either receives that provider's result or a typed error.  This is
important for medical source privacy: a local failure must never make the same
prompt leave the machine through a cloud provider.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Mapping, Sequence
from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable

from bioprof.domain.models import ProviderCapabilities


class ProviderError(RuntimeError):
    """Base class for provider failures safe to expose to API clients."""

    code = "provider_error"

    def __init__(self, message: str, *, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


class ProviderUnavailableError(ProviderError):
    code = "provider_unavailable"

    def __init__(self, message: str) -> None:
        super().__init__(message, status_code=503)


class UnsupportedCapabilityError(ProviderError):
    code = "unsupported_capability"

    def __init__(self, capability: str, provider: str) -> None:
        super().__init__(
            f"'{provider}' sağlayıcısı '{capability}' özelliğini desteklemiyor.",
            status_code=400,
        )
        self.capability = capability
        self.provider = provider


class PrivacyViolationError(ProviderError):
    code = "privacy_policy_violation"

    def __init__(self, provider: str) -> None:
        super().__init__(
            f"'{provider}' için dış veri aktarımı bu proje politikasında açıkça etkin değil.",
            status_code=403,
        )
        self.provider = provider


class AuthenticationError(ProviderError):
    code = "authentication_error"

    def __init__(self, provider: str) -> None:
        # Never put an API key, keychain output or Authorization header here.
        super().__init__(
            f"'{provider}' için kimlik doğrulama bilgisi yok veya reddedildi.",
            status_code=401,
        )


@dataclass(slots=True)
class ChatResult:
    """Provider-neutral chat result.

    ``raw`` is retained for standards-compatible proxy responses, while the
    normalized fields keep the rest of BioProf independent from a vendor SDK.
    """

    text: str
    model: str
    provider: str
    finish_reason: str = "stop"
    usage: dict[str, int] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class ResponseResult:
    text: str
    model: str
    provider: str
    status: str = "completed"
    usage: dict[str, int] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class EmbeddingResult:
    vectors: list[list[float]]
    model: str
    provider: str
    usage: dict[str, int] = field(default_factory=dict)
    raw: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class ChatProvider(Protocol):
    name: str
    requires_egress: bool

    async def probe(self, *, active: bool = False) -> ProviderCapabilities: ...

    async def chat(self, payload: Mapping[str, Any]) -> ChatResult: ...

    def stream_chat(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]: ...

    async def responses(self, payload: Mapping[str, Any]) -> ResponseResult: ...

    def stream_responses(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]: ...

    async def embeddings(self, payload: Mapping[str, Any]) -> EmbeddingResult: ...


@runtime_checkable
class Reranker(Protocol):
    name: str

    async def rerank(
        self, query: str, documents: Sequence[str], *, top_n: int | None = None
    ) -> list[dict[str, Any]]: ...


@runtime_checkable
class Transcriber(Protocol):
    name: str

    async def transcribe(
        self,
        data: bytes,
        *,
        filename: str,
        content_type: str | None = None,
        model: str | None = None,
        language: str | None = None,
        prompt: str | None = None,
        response_format: str = "json",
    ) -> dict[str, Any]: ...


@dataclass(slots=True)
class AudioPayload:
    data: bytes
    media_type: str
    # Servisin döndürdüğü yan bilgi (ör. mastering sonrası segment süreleri).
    metadata: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class Synthesizer(Protocol):
    name: str

    async def synthesize(
        self,
        text: str,
        *,
        voice: str = "Murat",
        model: str | None = None,
        response_format: str = "wav",
        speed: float = 1.0,
        verify: bool = False,
    ) -> AudioPayload: ...

