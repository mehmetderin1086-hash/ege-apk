#!/usr/bin/env python3
"""Read-only diagnostics for a local DownloadHub installation."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]


@dataclass
class Check:
    name: str
    status: str
    detail: str


def command_version(command: Path | str, args: list[str]) -> str | None:
    try:
        result = subprocess.run(
            [str(command), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    output = (result.stdout or result.stderr).strip().splitlines()
    return output[0][:240] if output else f"exit={result.returncode}"


def nearest_existing_parent(path: Path) -> Path:
    candidate = path.expanduser()
    while not candidate.exists() and candidate != candidate.parent:
        candidate = candidate.parent
    return candidate


def runtime_candidate(name: str) -> Path | str | None:
    bundled = PROJECT_ROOT / "runtime" / "bin" / name
    if bundled.is_file():
        return bundled
    located = shutil.which(name)
    if located:
        return located
    if name == "ffmpeg":
        try:
            import imageio_ffmpeg

            fallback = Path(imageio_ffmpeg.get_ffmpeg_exe())
            if fallback.is_file():
                return fallback
        except (ImportError, OSError):
            pass
    return None


def service_check(host: str, port: int) -> Check:
    for endpoint in ("/health", "/healthz", "/api/v1/health"):
        try:
            with urllib.request.urlopen(  # noqa: S310
                f"http://{host}:{port}{endpoint}", timeout=1
            ) as response:
                return Check(
                    "local_service",
                    "ok",
                    f"{endpoint} HTTP {response.status} (yalnız loopback)",
                )
        except (urllib.error.URLError, TimeoutError):
            continue
    try:
        with socket.create_connection((host, port), timeout=1):
            return Check("local_service", "warn", f"{host}:{port} kullanımda; sağlık yanıtı yok")
    except OSError:
        return Check("local_service", "info", f"{host}:{port} üzerinde servis çalışmıyor")


def collect(host: str, port: int) -> list[Check]:
    checks: list[Check] = []
    current_platform = f"{platform.system()} {platform.machine()}"
    checks.append(
        Check(
            "platform",
            "ok" if platform.system() == "Darwin" and platform.machine() == "arm64" else "fail",
            current_platform,
        )
    )
    checks.append(
        Check(
            "python",
            "ok" if sys.version_info >= (3, 12) else "fail",
            f"{platform.python_version()} ({sys.executable})",
        )
    )
    uv = shutil.which("uv")
    checks.append(Check("uv", "ok" if uv else "warn", uv or "PATH üzerinde bulunamadı"))

    for module in ("fastapi", "sqlalchemy", "alembic", "jinja2", "yt_dlp"):
        available = importlib.util.find_spec(module) is not None
        checks.append(
            Check(
                f"python:{module}",
                "ok" if available else "fail",
                "kurulu" if available else "eksik",
            )
        )

    commands = {
        "aria2c": ["--version"],
        "ffmpeg": ["-version"],
        "deno": ["--version"],
        "yt-dlp": ["--version"],
    }
    for name, arguments in commands.items():
        candidate = runtime_candidate(name)
        version = command_version(candidate, arguments) if candidate else None
        status = "ok" if version else ("info" if name == "yt-dlp" else "warn")
        checks.append(Check(f"runtime:{name}", status, version or "binary bulunamadı"))

    home = Path.home()
    paths = {
        "data_dir": home / "Library" / "Application Support" / "DownloadHub",
        "cache_dir": home / "Library" / "Caches" / "DownloadHub",
        "log_dir": home / "Library" / "Logs" / "DownloadHub",
        "download_dir": home / "Downloads" / "DownloadHub",
    }
    for name, path in paths.items():
        parent = nearest_existing_parent(path)
        writable = os.access(parent, os.W_OK)
        checks.append(Check(name, "ok" if writable else "fail", f"{path} (yazılabilir üst dizin: {parent})"))

    manifest = PROJECT_ROOT / "runtime-manifest.json"
    if manifest.is_file():
        result = subprocess.run(
            [sys.executable, str(PROJECT_ROOT / "scripts" / "runtime_manager.py"), "status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        detail = (result.stdout or result.stderr).strip().replace("\n", "; ")
        checks.append(Check("runtime_manifest", "ok" if result.returncode == 0 else "fail", detail))
    else:
        checks.append(Check("runtime_manifest", "fail", "runtime-manifest.json eksik"))

    checks.append(service_check(host, port))
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=8765, type=int)
    args = parser.parse_args()
    if args.host != "127.0.0.1":
        print("Tanılama güvenlik gereği yalnız 127.0.0.1 hedefini kabul eder.", file=sys.stderr)
        return 2
    checks = collect(args.host, args.port)
    if args.as_json:
        print(json.dumps([asdict(check) for check in checks], ensure_ascii=False, indent=2))
    else:
        for check in checks:
            print(f"[{check.status.upper():4}] {check.name:20} {check.detail}")
    return 1 if any(check.status == "fail" for check in checks) else 0


if __name__ == "__main__":
    raise SystemExit(main())
