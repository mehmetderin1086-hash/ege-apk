"""Read-only environment and service diagnostics for ``bioprof doctor``."""

from __future__ import annotations

import importlib.util
import os
import platform
import shutil
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from importlib import metadata
from pathlib import Path
from typing import Any

from bioprof.providers.cliproxy import CLIProxyProvider
from bioprof.providers.keychain import KeychainSecret
from bioprof.voice.seslab import SesLabAdapter


@dataclass(slots=True)
class DoctorCheck:
    name: str
    ok: bool
    status: str
    details: dict[str, Any] = field(default_factory=dict)


@dataclass(slots=True)
class DoctorReport:
    ok: bool
    hardware: dict[str, Any]
    checks: list[DoctorCheck]

    def model_dump(self) -> dict[str, Any]:
        return asdict(self)


def _sysctl(name: str) -> str | None:
    try:
        result = subprocess.run(
            ["/usr/sbin/sysctl", "-n", name],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def _memory_bytes() -> int | None:
    value = _sysctl("hw.memsize")
    if value and value.isdigit():
        return int(value)
    try:
        return int(os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE"))
    except (ValueError, OSError, AttributeError):
        return None


def hardware_report(data_dir: Path | None = None) -> dict[str, Any]:
    machine = platform.machine()
    memory = _memory_bytes()
    disk_path = data_dir if data_dir and data_dir.exists() else Path.home()
    disk = shutil.disk_usage(disk_path)
    chip = _sysctl("machdep.cpu.brand_string") or _sysctl("hw.model") or platform.processor()
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": machine,
        "chip": chip or "unknown",
        "apple_silicon": platform.system() == "Darwin" and machine == "arm64",
        "cpu_count": os.cpu_count(),
        "memory_bytes": memory,
        "memory_gib": round(memory / (1024**3), 2) if memory else None,
        "disk_free_bytes": disk.free,
        "disk_free_gib": round(disk.free / (1024**3), 2),
        "python": sys.version.split()[0],
        "python_executable": sys.executable,
    }


_DEPENDENCIES = {
    "fastapi": ("fastapi", "fastapi"),
    "httpx": ("httpx", "httpx"),
    "qdrant": ("qdrant_client", "qdrant-client"),
    "docling": ("docling", "docling"),
    "mlx_lm": ("mlx_lm", "mlx-lm"),
    "mlx_whisper": ("mlx_whisper", "mlx-whisper"),
    "av": ("av", "av"),
    "sentence_transformers": ("sentence_transformers", "sentence-transformers"),
}


def dependency_check() -> DoctorCheck:
    installed: dict[str, str | None] = {}
    missing_optional: list[str] = []
    for label, (module, distribution) in _DEPENDENCIES.items():
        if importlib.util.find_spec(module) is None:
            installed[label] = None
            if label not in {"fastapi", "httpx"}:
                missing_optional.append(label)
            continue
        try:
            installed[label] = metadata.version(distribution)
        except metadata.PackageNotFoundError:
            installed[label] = "installed"
    core_ok = installed["fastapi"] is not None and installed["httpx"] is not None
    return DoctorCheck(
        name="dependencies",
        ok=core_ok,
        status="ready" if core_ok else "core_missing",
        details={"packages": installed, "missing_optional": missing_optional},
    )


def command_check() -> DoctorCheck:
    commands = {
        name: shutil.which(name)
        for name in ("uv", "ffmpeg", "tesseract", "pdftotext", "llama-server", "ollama")
    }
    return DoctorCheck(
        name="commands",
        ok=commands["uv"] is not None,
        status="ready" if commands["uv"] else "uv_missing",
        details={"commands": commands},
    )


class SystemDoctor:
    def __init__(
        self,
        *,
        data_dir: Path | None = None,
        seslab_base_url: str = "http://127.0.0.1:8000",
        cliproxy_base_url: str = "http://127.0.0.1:8317",
        cliproxy_credential: KeychainSecret | None = None,
    ) -> None:
        self.data_dir = data_dir
        self.seslab_base_url = seslab_base_url
        self.cliproxy_base_url = cliproxy_base_url
        self.cliproxy_credential = cliproxy_credential or KeychainSecret(
            "BioProf CLI Proxy API Key",
            account="bioprof",
            env_name="BIOPROF_CLIPROXY_API_KEY",
        )

    async def run(self, *, active_provider_probe: bool = False) -> DoctorReport:
        checks = [dependency_check(), command_check()]

        voice = SesLabAdapter(base_url=self.seslab_base_url)
        try:
            voice_caps = await voice.probe()
            checks.append(
                DoctorCheck(
                    name="seslab",
                    ok=voice_caps.available,
                    status="ready" if voice_caps.available else "unavailable",
                    details=voice_caps.details,
                )
            )
        finally:
            await voice.aclose()

        credential_status = self.cliproxy_credential.status()
        proxy = CLIProxyProvider(
            base_url=self.cliproxy_base_url,
            credential=self.cliproxy_credential,
        )
        try:
            proxy_caps = await proxy.probe(active=active_provider_probe)
            proxy_details = dict(proxy_caps.details)
            proxy_details["credential_available"] = credential_status.available
            proxy_details["credential_source"] = credential_status.source
            checks.append(
                DoctorCheck(
                    name="cliproxy",
                    ok=proxy_caps.available,
                    status="ready" if proxy_caps.available else "unavailable_or_unauthorized",
                    details=proxy_details,
                )
            )
        finally:
            await proxy.aclose()

        hardware = hardware_report(self.data_dir)
        # Optional services do not make the core unhealthy. The overall flag says
        # whether the core environment itself can start.
        core_names = {"dependencies", "commands"}
        ok = all(check.ok for check in checks if check.name in core_names)
        return DoctorReport(ok=ok, hardware=hardware, checks=checks)

