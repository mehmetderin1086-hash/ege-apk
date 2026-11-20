"""CLI Proxy API adapter.

Although the daemon listens on loopback, its selected upstream can be remote;
therefore this provider always requires explicit project egress permission.
"""

from __future__ import annotations

import httpx

from bioprof.providers.keychain import KeychainSecret
from bioprof.providers.openai_compatible import OpenAICompatibleProvider


class CLIProxyProvider(OpenAICompatibleProvider):
    def __init__(
        self,
        *,
        base_url: str = "http://127.0.0.1:8317",
        credential: KeychainSecret | None = None,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.credential = credential or KeychainSecret(
            "BioProf CLI Proxy API Key",
            account="bioprof",
            env_name="BIOPROF_CLIPROXY_API_KEY",
        )
        super().__init__(
            name="cliproxy",
            base_url=base_url,
            api_key=self.credential.get,
            requires_egress=True,
            require_api_key=True,
            client=client,
            timeout=180,
        )

