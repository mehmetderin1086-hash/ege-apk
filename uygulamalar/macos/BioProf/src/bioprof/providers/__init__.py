"""Model/provider adapters."""

from bioprof.providers.base import (
    AudioPayload,
    AuthenticationError,
    ChatProvider,
    ChatResult,
    EmbeddingResult,
    PrivacyViolationError,
    ProviderError,
    ProviderUnavailableError,
    ResponseResult,
    Synthesizer,
    Transcriber,
    UnsupportedCapabilityError,
)
from bioprof.providers.cliproxy import CLIProxyProvider
from bioprof.providers.doctor import DoctorCheck, DoctorReport, SystemDoctor
from bioprof.providers.factory import create_provider_registry
from bioprof.providers.keychain import CredentialStatus, KeychainSecret
from bioprof.providers.local import LocalEvidenceProvider
from bioprof.providers.openai_compatible import OpenAICompatibleProvider
from bioprof.providers.registry import ProviderPolicy, ProviderRegistry

__all__ = [
    "AudioPayload",
    "AuthenticationError",
    "ChatProvider",
    "ChatResult",
    "CLIProxyProvider",
    "CredentialStatus",
    "create_provider_registry",
    "DoctorCheck",
    "DoctorReport",
    "EmbeddingResult",
    "LocalEvidenceProvider",
    "KeychainSecret",
    "OpenAICompatibleProvider",
    "PrivacyViolationError",
    "ProviderError",
    "ProviderPolicy",
    "ProviderRegistry",
    "ProviderUnavailableError",
    "ResponseResult",
    "Synthesizer",
    "SystemDoctor",
    "Transcriber",
    "UnsupportedCapabilityError",
]
