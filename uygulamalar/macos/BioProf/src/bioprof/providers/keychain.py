"""Read provider credentials without putting them in logs or process arguments."""

from __future__ import annotations

import os
import platform
import subprocess
from dataclasses import dataclass


class KeychainLookupError(RuntimeError):
    """A deliberately redacted key lookup failure."""


@dataclass(frozen=True, slots=True)
class CredentialStatus:
    available: bool
    source: str | None = None


class KeychainSecret:
    """Lazy macOS Keychain reader with an optional environment fallback.

    Only availability/source metadata is printable. ``repr`` never retrieves or
    displays the secret.
    """

    def __init__(
        self,
        service: str,
        *,
        account: str = "bioprof",
        env_name: str | None = None,
    ) -> None:
        self.service = service
        self.account = account
        self.env_name = env_name

    def __repr__(self) -> str:
        return (
            f"KeychainSecret(service={self.service!r}, account={self.account!r}, "
            "value=<redacted>)"
        )

    def get(self, *, required: bool = False) -> str | None:
        if self.env_name:
            value = os.getenv(self.env_name)
            if value:
                return value

        if platform.system() != "Darwin":
            if required:
                raise KeychainLookupError("Kimlik bilgisi bulunamadı.")
            return None

        try:
            completed = subprocess.run(
                [
                    "/usr/bin/security",
                    "find-generic-password",
                    "-s",
                    self.service,
                    "-a",
                    self.account,
                    "-w",
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            if required:
                raise KeychainLookupError("Keychain okunamadı.") from None
            return None

        value = completed.stdout.strip() if completed.returncode == 0 else ""
        if value:
            return value
        if required:
            raise KeychainLookupError("Keychain girdisi bulunamadı.")
        return None

    def status(self) -> CredentialStatus:
        if self.env_name and os.getenv(self.env_name):
            return CredentialStatus(True, "environment")
        value = self.get(required=False)
        return CredentialStatus(bool(value), "keychain" if value else None)

