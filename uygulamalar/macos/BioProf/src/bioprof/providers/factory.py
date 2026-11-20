"""Side-effect-free provider registry factory used by the application container."""

from __future__ import annotations

from typing import Protocol

from bioprof.providers.cliproxy import CLIProxyProvider
from bioprof.providers.keychain import KeychainSecret
from bioprof.providers.local import LocalEvidenceProvider
from bioprof.providers.openai_compatible import OpenAICompatibleProvider
from bioprof.providers.registry import ProviderPolicy, ProviderRegistry


class ProviderSettings(Protocol):
    allow_remote_egress: bool
    cliproxy_base_url: str
    cliproxy_key_name: str
    generic_openai_base_url: str | None
    generic_openai_api_key: str | None


def create_provider_registry(settings: ProviderSettings) -> ProviderRegistry:
    """Create known adapters without probing, downloading or contacting a service."""

    registry = ProviderRegistry(
        policy=ProviderPolicy(allow_remote_egress=settings.allow_remote_egress)
    )
    registry.register(LocalEvidenceProvider())
    registry.register(
        CLIProxyProvider(
            base_url=settings.cliproxy_base_url,
            credential=KeychainSecret(
                settings.cliproxy_key_name,
                account="bioprof",
                env_name="BIOPROF_CLIPROXY_API_KEY",
            ),
        )
    )
    if settings.generic_openai_base_url:
        registry.register(
            OpenAICompatibleProvider(
                name="openai_compatible",
                base_url=settings.generic_openai_base_url,
                api_key=settings.generic_openai_api_key,
                require_api_key=not settings.generic_openai_base_url.startswith(
                    ("http://127.0.0.1", "http://localhost", "http://[::1]")
                ),
            )
        )
    return registry

