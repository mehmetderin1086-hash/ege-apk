#!/usr/bin/env python3
"""Install or disable the optional per-user DownloadHub LaunchAgent."""

from __future__ import annotations

import argparse
import os
import platform
import plistlib
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

LABEL = "com.downloadhub.local"
PLIST_PATH = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
BACKUP_DIR = Path.home() / "Library" / "Application Support" / "DownloadHub" / "LaunchAgent Backups"
LOG_DIR = Path.home() / "Library" / "Logs" / "DownloadHub"


class LaunchAgentError(RuntimeError):
    pass


def require_macos() -> None:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise LaunchAgentError("LaunchAgent yalnız macOS arm64 üzerinde desteklenir")


def launchctl(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["/bin/launchctl", *arguments],
        check=check,
        capture_output=True,
        text=True,
        timeout=30,
    )


def app_executable(app_path: Path) -> Path:
    if not app_path.is_absolute():
        raise LaunchAgentError("Uygulama yolu mutlak olmalı")
    if app_path.is_symlink() or app_path.suffix != ".app" or not app_path.is_dir():
        raise LaunchAgentError(f"Güvenli bir .app paketi bulunamadı: {app_path}")
    executable = app_path / "Contents" / "MacOS" / "DownloadHub"
    if not executable.is_file() or executable.is_symlink() or not os.access(executable, os.X_OK):
        raise LaunchAgentError(f"Uygulama executable'ı bulunamadı: {executable}")
    return executable


def install(app_path: Path) -> None:
    executable = app_executable(app_path)
    if PLIST_PATH.exists() or PLIST_PATH.is_symlink():
        raise LaunchAgentError(
            f"Mevcut LaunchAgent üzerine yazılmayacak: {PLIST_PATH}. Önce disable kullanın."
        )
    PLIST_PATH.parent.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    payload = {
        "Label": LABEL,
        "ProgramArguments": [str(executable)],
        "RunAtLoad": True,
        "KeepAlive": False,
        "ProcessType": "Interactive",
        "EnvironmentVariables": {
            "DOWNLOADHUB_HOST": "127.0.0.1",
            "DOWNLOADHUB_PORT": "8765",
            "DOWNLOADHUB_OPEN_BROWSER": "0",
        },
        "StandardOutPath": str(LOG_DIR / "launchagent.stdout.log"),
        "StandardErrorPath": str(LOG_DIR / "launchagent.stderr.log"),
    }
    temporary = PLIST_PATH.with_name(f".{PLIST_PATH.name}.{os.getpid()}.tmp")
    try:
        temporary.write_bytes(plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True))
        os.chmod(temporary, 0o600)
        os.replace(temporary, PLIST_PATH)
        launchctl("bootstrap", f"gui/{os.getuid()}", str(PLIST_PATH))
    except Exception as exc:
        temporary.unlink(missing_ok=True)
        if PLIST_PATH.exists() and not PLIST_PATH.is_symlink():
            BACKUP_DIR.mkdir(parents=True, exist_ok=True)
            failed = BACKUP_DIR / f"{PLIST_PATH.name}.failed-{datetime.now(UTC):%Y%m%dT%H%M%SZ}"
            shutil.move(PLIST_PATH, failed)
        raise LaunchAgentError(f"LaunchAgent yüklenemedi: {exc}") from exc
    print(f"Oturum açılışında başlatma etkin: {PLIST_PATH}")


def disable() -> None:
    if not PLIST_PATH.exists() or PLIST_PATH.is_symlink():
        raise LaunchAgentError(f"Yönetilen LaunchAgent bulunamadı: {PLIST_PATH}")
    launchctl("bootout", f"gui/{os.getuid()}", str(PLIST_PATH), check=False)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ")
    backup = BACKUP_DIR / f"{PLIST_PATH.name}.disabled-{stamp}"
    if backup.exists():
        raise LaunchAgentError(f"Yedek hedefi zaten var; hiçbir dosya taşınmadı: {backup}")
    shutil.move(PLIST_PATH, backup)
    print(f"LaunchAgent devre dışı; geri alınabilir plist yedeği: {backup}")


def status() -> int:
    result = launchctl("print", f"gui/{os.getuid()}/{LABEL}", check=False)
    if result.returncode == 0:
        print(result.stdout.strip())
        return 0
    if PLIST_PATH.exists():
        print(f"Plist var fakat görev yüklü değil: {PLIST_PATH}")
    else:
        print("Oturum açılışında başlatma etkin değil.")
    return 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    install_parser = subparsers.add_parser("install")
    install_parser.add_argument(
        "--app",
        type=Path,
        default=Path("/Applications/DownloadHub.app"),
        help="DownloadHub.app mutlak yolu",
    )
    subparsers.add_parser("disable")
    subparsers.add_parser("status")
    return parser.parse_args()


def main() -> int:
    try:
        require_macos()
        args = parse_args()
        if args.command == "install":
            install(args.app)
            return 0
        if args.command == "disable":
            disable()
            return 0
        return status()
    except LaunchAgentError as exc:
        print(f"HATA: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
