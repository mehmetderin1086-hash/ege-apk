#!/usr/bin/env python3
"""Hafif masaüstü başlatıcısı üretir: ~/Applications/Cumhuriyet Kitap.app

Çift tıklanınca launch_kitapkatalog.command --detach çalışır: varsa açık
sunucu tarayıcıda yeniden kullanılır, yoksa web sunucusu arka planda başlar
ve tarayıcı açılır. PyInstaller paketi DEĞİLDİR; repo'daki .venv'i kullanır.

Kullanım:
    python scripts/build_launcher_app.py            # üret + imzala + kur
    python scripts/build_launcher_app.py --dry-run  # yalnız üretim planını yaz
"""

from __future__ import annotations

import plistlib
import shutil
import stat
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

PROJECT = Path(__file__).resolve().parent.parent
APP_NAME = "Cumhuriyet Kitap"
APPLICATIONS = Path.home() / "Applications"
DESKTOP = Path.home() / "Desktop"
APP_PATH = APPLICATIONS / f"{APP_NAME}.app"
OLD_QT_APP = APPLICATIONS / f"{APP_NAME}-qt-eski.app"

STUB = f"""#!/bin/zsh
# {APP_NAME} masaüstü başlatıcısı (otomatik üretildi: build_launcher_app.py)
exec "{PROJECT}/scripts/launch_kitapkatalog.command" --detach
"""


def _version() -> str:
    for line in (PROJECT / "pyproject.toml").read_text().splitlines():
        if line.strip().startswith("version"):
            return line.split('"')[1]
    return "0.0.0"


def _find_icon() -> Path | None:
    for candidate in (PROJECT / "assets").glob("*.icns"):
        return candidate
    return None


def build(*, dry_run: bool = False) -> int:
    version = _version()
    icon = _find_icon()
    print(f"Üretilecek: {APP_PATH} (v{version}, ikon: {icon.name if icon else 'yok'})")
    if dry_run:
        return 0

    APPLICATIONS.mkdir(parents=True, exist_ok=True)
    # Önce aynı diskte tamamen ayrı bir paket üret. Canlı uygulamaya ancak
    # plist, imza ve binary doğrulandıktan sonra atomik ad değiştirmeyle geçilir.
    staging_root = Path(tempfile.mkdtemp(prefix=f".{APP_NAME}-build-", dir=APPLICATIONS))
    staged_app = staging_root / APP_PATH.name
    macos_dir = staged_app / "Contents" / "MacOS"
    resources = staged_app / "Contents" / "Resources"
    macos_dir.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)

    binary = macos_dir / APP_NAME
    binary.write_text(STUB)
    binary.chmod(binary.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    info: dict[str, object] = {
        "CFBundleDisplayName": APP_NAME,
        "CFBundleName": APP_NAME,
        "CFBundleExecutable": APP_NAME,
        "CFBundleIdentifier": "local.kitapkatalog.launcher",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "CFBundleInfoDictionaryVersion": "6.0",
        "NSHighResolutionCapable": True,
        "LSUIElement": True,  # Dock'ta kalıcı simge istemez; tarayıcı açılır.
    }
    if icon is not None:
        shutil.copy2(icon, resources / icon.name)
        info["CFBundleIconFile"] = icon.name
    with (staged_app / "Contents" / "Info.plist").open("wb") as handle:
        plistlib.dump(info, handle)

    rollback = APPLICATIONS / f".{APP_NAME}.rollback-{uuid.uuid4().hex}"
    preserved_old_qt = False
    installed_staged = False
    try:
        subprocess.run(
            ["codesign", "--force", "-s", "-", str(staged_app)],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(staged_app)],
            check=True,
            capture_output=True,
        )
        with (staged_app / "Contents" / "Info.plist").open("rb") as handle:
            verified = plistlib.load(handle)
        if verified.get("CFBundleShortVersionString") != version or not binary.is_file():
            raise RuntimeError("Hazırlanan launcher sürüm/binary doğrulamasını geçemedi")

        # Eski native Qt paketi bir defaya mahsus geri dönüş adıyla korunur;
        # mevcut launcher ise yalnız atomik geçiş süresince rollback'te tutulur.
        if APP_PATH.exists():
            current_binary = APP_PATH / "Contents" / "MacOS" / APP_NAME
            is_stub = current_binary.is_file() and current_binary.stat().st_size < 4096
            if not is_stub and not OLD_QT_APP.exists():
                print(f"Mevcut paket korunuyor: {OLD_QT_APP}")
                APP_PATH.rename(OLD_QT_APP)
                preserved_old_qt = True
            else:
                APP_PATH.rename(rollback)
        staged_app.rename(APP_PATH)
        installed_staged = True
        subprocess.run(
            ["codesign", "--verify", "--deep", "--strict", str(APP_PATH)],
            check=True,
            capture_output=True,
        )
    except BaseException:
        # Yeni paket canlı ada taşındıktan sonra doğrulama bozulursa önceki
        # uygulamayı geri getir; kullanıcı uygulamasız bırakılmaz.
        if installed_staged and APP_PATH.exists():
            shutil.rmtree(APP_PATH)
        if rollback.exists():
            rollback.rename(APP_PATH)
        elif preserved_old_qt and OLD_QT_APP.exists():
            OLD_QT_APP.rename(APP_PATH)
        raise
    else:
        if rollback.exists():
            shutil.rmtree(rollback)
    finally:
        shutil.rmtree(staging_root, ignore_errors=True)

    print(f"Hazır: {APP_PATH}")
    print("Çift tıklama artık web arayüzünü açar. Eski Qt arayüzü:")
    print(f"  {OLD_QT_APP if OLD_QT_APP.exists() else 'scripts/launch_kitapkatalog.command --qt'}")
    return 0


def _desktop_symlink() -> None:
    """Masaüstü'ne kısayol koyar; symlink olmayan mevcut bir girdiye dokunmaz.

    Kısayol hatası kurulumun başarısını bozmaz: uygulama ~/Applications'a
    kurulmuş durumdadır, yalnız uyarı basılır.
    """
    link = DESKTOP / APP_PATH.name
    try:
        if link.is_symlink():
            link.unlink()
        elif link.exists():
            print(f"Uyarı: {link} symlink değil, kısayol güncellenmedi.")
            return
        link.symlink_to(APP_PATH)
    except OSError as error:
        print(f"Uyarı: Masaüstü kısayolu kurulamadı: {error}")
        return
    print(f"Masaüstü kısayolu: {link}")


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    exit_code = build(dry_run=dry_run)
    if exit_code == 0 and not dry_run:
        _desktop_symlink()
    raise SystemExit(exit_code)
