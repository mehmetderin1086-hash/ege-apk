"""Explicit provider selection and privacy enforcement."""

from __future__ import annotations

from dataclasses import dataclass

from bioprof.providers.base import (
    ChatProvider,
    PrivacyViolationError,
    ProviderUnavailableError,
)


@dataclass(slots=True)
class ProviderPolicy:
    allow_remote_egress: bool = False


class ProviderRegistry:
    def __init__(self, *, policy: ProviderPolicy | None = None) -> None:
        self.policy = policy or ProviderPolicy()
        self._providers: dict[str, ChatProvider] = {}

    def register(self, provider: ChatProvider) -> None:
        if provider.name in self._providers:
            raise ValueError(f"Sağlayıcı zaten kayıtlı: {provider.name}")
        self._providers[provider.name] = provider

    def names(self) -> list[str]:
        return sorted(self._providers)

    def get(self, name: str) -> ChatProvider:
        provider = self._providers.get(name)
        if provider is None:
            raise ProviderUnavailableError(f"Bilinmeyen sağlayıcı: {name}")
        if provider.requires_egress and not self.policy.allow_remote_egress:
            raise PrivacyViolationError(name)
        return provider

    def get_for_model(self, model: str, *, default_provider: str) -> tuple[ChatProvider, str]:
        """Resolve ``provider/model`` without ever trying a second provider."""

        if "/" in model:
            candidate, provider_model = model.split("/", 1)
            if candidate in self._providers:
                return self.get(candidate), provider_model
        return self.get(default_provider), model

