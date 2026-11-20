"""Biyoloji Stüdyosu için imzalı, Finder uyumlu bir macOS uygulaması kurar.

Kurulumdaki diğer programlarla (Sınav Okur, Soru Kesici, PDF Studio…) aynı
desen: ince bir Swift sarmalayıcı paketteki `launcher.sh`'i çalıştırıyor,
o da sunucuyu boş bir portta ayağa kaldırıp tarayıcıyı açıyor.

    uv run python scripts/install_macos_app.py --replace
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

# Eski "Soru Çözücü.app" yerinde bırakılır; Stüdyo ayrı bundle kimliğiyle
# kurulur ki iki kısayol Finder'da çakışmasın.
APP_NAME = "Biyoloji Stüdyosu.app"
BUNDLE_ID = "com.mehmetderin.biyolojistudyosu"
CALISTIRILABILIR = "BiyoCozucuLauncher"


def _calistir(*komut: str | Path) -> None:
    # Komutlar bu dosyada sabit yazılı (sips, iconutil, swiftc, codesign);
    # kullanıcı girdisi yalnız yol argümanı olarak ve liste biçiminde geçiyor.
    subprocess.run([str(x) for x in komut], check=True)  # noqa: S603


def _icns_uret(kaynak: Path, hedef: Path, gecici: Path) -> None:
    iconset = gecici / "AppIcon.iconset"
    iconset.mkdir()
    boyutlar = {
        "icon_16x16.png": 16, "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32, "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512, "icon_512x512@2x.png": 1024,
    }
    for ad, boyut in boyutlar.items():
        _calistir("/usr/bin/sips", "-z", str(boyut), str(boyut), str(kaynak),
                  "--out", str(iconset / ad))
    _calistir("/usr/bin/iconutil", "-c", "icns", str(iconset), "-o", str(hedef))


def kur(proje: Path, logo: Path, hedef: Path, masaustu: Path, *, replace: bool) -> None:
    proje = proje.resolve()
    logo = logo.resolve()
    if not (proje / ".venv/bin/biyo-cozucu").is_file():
        raise SystemExit(
            "Hata: .venv/bin/biyo-cozucu bulunamadı. Önce: uv sync --extra web"
        )
    if not logo.is_file():
        raise SystemExit(f"Hata: simge bulunamadı: {logo}")
    if (hedef.exists() or hedef.is_symlink()) and not replace:
        raise SystemExit(f"Hata: {hedef} zaten var. Yenilemek için --replace kullanın.")
    if hedef.exists() or hedef.is_symlink():
        if hedef.is_symlink() or hedef.is_file():
            hedef.unlink()
        else:
            shutil.rmtree(hedef)

    hedef.parent.mkdir(parents=True, exist_ok=True)
    masaustu.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="biyo-cozucu-app-") as gecici_ham:
        gecici = Path(gecici_ham)
        app = gecici / APP_NAME
        contents = app / "Contents"
        macos = contents / "MacOS"
        resources = contents / "Resources"
        macos.mkdir(parents=True)
        resources.mkdir()

        plist = {
            "CFBundleDevelopmentRegion": "tr",
            "CFBundleDisplayName": "Biyoloji Stüdyosu",
            "CFBundleExecutable": CALISTIRILABILIR,
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Biyoloji Stüdyosu",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            # Dock'ta simge açmaz: sunucuyu başlatıp tarayıcıya devreder.
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
        }
        with (contents / "Info.plist").open("wb") as f:
            plistlib.dump(plist, f, sort_keys=True)

        betik = (proje / "macos/launcher.sh").read_text(encoding="utf-8")
        (resources / "launcher.sh").write_text(
            betik.replace("__PROJECT_DIR__", str(proje)), encoding="utf-8"
        )
        (resources / "launcher.sh").chmod(0o755)
        shutil.copy2(logo, resources / "biyo-cozucu-icon.png")
        _icns_uret(logo, resources / "AppIcon.icns", gecici)

        _calistir(
            "/usr/bin/xcrun", "swiftc", "-O",
            "-target", "arm64-apple-macosx13.0",
            "-framework", "AppKit",
            str(proje / f"macos/{CALISTIRILABILIR}.swift"),
            "-o", str(macos / CALISTIRILABILIR),
        )
        _calistir("/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app))

        gecici_hedef = hedef.parent / f".{APP_NAME}.kuruluyor"
        if gecici_hedef.exists():
            shutil.rmtree(gecici_hedef)
        shutil.copytree(app, gecici_hedef, symlinks=True)
        os.replace(gecici_hedef, hedef)

    if masaustu.exists() or masaustu.is_symlink():
        if masaustu.is_symlink() or masaustu.is_file():
            masaustu.unlink()
        elif replace:
            shutil.rmtree(masaustu)
        else:
            raise SystemExit(f"Hata: Masaüstü hedefi zaten var: {masaustu}")
    masaustu.symlink_to(hedef)
    _calistir("/usr/bin/codesign", "--verify", "--deep", "--strict", str(hedef))
    print(f"Kuruldu : {hedef}")
    print(f"Masaüstü: {masaustu} -> {hedef}")


def main() -> None:
    proje = Path(__file__).resolve().parents[1]
    ayristirici = argparse.ArgumentParser(description=__doc__)
    ayristirici.add_argument("--replace", action="store_true")
    ayristirici.add_argument(
        "--hedef", type=Path, default=Path.home() / "Applications" / APP_NAME
    )
    ayristirici.add_argument(
        "--masaustu", type=Path, default=Path.home() / "Desktop" / APP_NAME
    )
    ayristirici.add_argument(
        "--logo", type=Path, default=proje / "assets/biyo-cozucu-icon.png"
    )
    args = ayristirici.parse_args()
    kur(proje, args.logo, args.hedef, args.masaustu, replace=args.replace)


if __name__ == "__main__":
    main()
