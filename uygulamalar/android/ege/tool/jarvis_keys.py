"""Builds the --dart-define-from-file JSON that embeds the CLI Proxy API keys
into a personal JARVIS APK so the phone works on its own (no PC needed).

Usage:
    python tool/jarvis_keys.py <output.json>

The output file contains secrets: write it OUTSIDE the project (e.g. %TEMP%)
and delete it after the build. Keys never go into source control.
Encoding must match lib/services/embedded_keys.dart.
"""
from __future__ import annotations

import base64
import json
import os
import socket
import sys
from pathlib import Path

SALT = "J.A.R.V.I.S-mobil-2026".encode("utf-8")
VERSION = 3


def windows_user_env() -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        import winreg  # type: ignore

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            i = 0
            while True:
                try:
                    name, value, _ = winreg.EnumValue(key, i)
                except OSError:
                    break
                out[str(name)] = str(value)
                i += 1
    except Exception:  # noqa: BLE001 - non-Windows
        pass
    return out


def env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                out[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        pass
    return out


def lan_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return ""


def encode(values: dict[str, str]) -> str:
    data = json.dumps(values, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    out = bytes(b ^ SALT[i % len(SALT)] ^ ((i * 31) & 0xFF) for i, b in enumerate(data))
    return base64.urlsafe_b64encode(out).decode("ascii")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("kullanım: python tool/jarvis_keys.py <cikti.json>")
    proxy_dir = Path.home() / "cli-proxy-api"
    env = windows_user_env()
    for k in ("GEMINI_API_KEY", "AZURE_SPEECH_KEY", "AZURE_SPEECH_REGION", "PROXY_API_KEY"):
        if os.environ.get(k):
            env.setdefault(k, os.environ[k])
    env.update({k: v for k, v in env_file(proxy_dir / ".env").items() if v})
    env.update({k: v for k, v in env_file(proxy_dir / "image-fallback.env").items() if v})
    ip = lan_ip()
    values = {
        "g": env.get("GEMINI_API_KEY") or env.get("GOOGLE_API_KEY", ""),
        "az": env.get("AZURE_SPEECH_KEY", ""),
        "azr": env.get("AZURE_SPEECH_REGION", "westeurope") or "westeurope",
        "px": env.get("PROXY_API_KEY", ""),
        "pu": f"http://{ip}:8317" if ip else "",
        "oa": env.get("OPENAI_API_KEY") or env.get("OPENAI_IMAGE_FALLBACK_KEY", ""),
    }
    Path(sys.argv[1]).write_text(
        json.dumps({"JARVIS_KEYS": encode(values), "JARVIS_KEYS_VERSION": str(VERSION)}),
        encoding="utf-8",
    )
    found = [name for name, key in (("Gemini", "g"), ("Azure", "az"), ("CLI Proxy", "px"), ("OpenAI/Whisper", "oa")) if values[key]]
    print("Gömülecek anahtarlar:", ", ".join(found) or "yok", "| PC proxy:", values["pu"] or "-")


if __name__ == "__main__":
    main()
