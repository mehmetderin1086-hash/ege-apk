"""Öğretmen Çantası için imzalı, Finder uyumlu bir macOS uygulaması kurar.

Kurulumdaki diğer programlarla (Sınav Okur, Soru Kesici, PDF Studio…) aynı
desen: ince bir Swift sarmalayıcı paketteki `launcher.sh`'i çalıştırıyor,
o da sunucuyu boş bir portta ayağa kaldırıp tarayıcıyı açıyor.

    uv run python scripts/install_macos_app.py --replace
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import tomllib
from pathlib import Path

APP_NAME = "Öğretmen Çantası.app"
BUNDLE_ID = "com.mehmetderin.ogretmencantasi"
CALISTIRILABILIR = "OgretmenCantasiLauncher"


def _calistir(*komut: str | Path) -> None:
    # Komutlar bu dosyada sabit yazılı (sips, iconutil, swiftc, codesign);
    # kullanıcı girdisi yalnız yol argümanı olarak ve liste biçiminde geçiyor.
    subprocess.run([str(x) for x in komut], check=True)  # noqa: S603


def _icns_uret(kaynak: Path, hedef: Path, gecici: Path) -> None:
    """PNG temsillerini doğrudan ICNS kapsayıcısına koyar.

    macOS 26'daki `iconutil` geçerli iconset'i "Invalid Iconset" diye
    reddedebildiği için standart PNG tabanlı ICNS blokları Python ile yazılır.
    """
    temsiller = (
        (b"icp4", 16),
        (b"icp5", 32),
        (b"icp6", 64),
        (b"ic07", 128),
        (b"ic08", 256),
        (b"ic09", 512),
        (b"ic10", 1024),
    )
    bloklar: list[bytes] = []
    for tur, boyut in temsiller:
        png = gecici / f"icon-{boyut}.png"
        _calistir(
            "/usr/bin/sips",
            "-z",
            str(boyut),
            str(boyut),
            str(kaynak),
            "--out",
            str(png),
        )
        veri = png.read_bytes()
        bloklar.append(tur + struct.pack(">I", len(veri) + 8) + veri)
    govde = b"".join(bloklar)
    hedef.write_bytes(b"icns" + struct.pack(">I", len(govde) + 8) + govde)


def _runtime_uret(proje: Path, hedef: Path, gecici: Path) -> None:
    pyinstaller = proje / ".venv/bin/pyinstaller"
    if not pyinstaller.is_file():
        raise SystemExit("Hata: PyInstaller yok. Önce: uv sync --extra dev")
    dist = gecici / "dist"
    work = gecici / "build"
    spec = gecici / "spec"
    _calistir(
        pyinstaller,
        "--noconfirm",
        "--clean",
        "--onedir",
        "--name",
        "ogretmen-cantasi",
        "--target-architecture",
        "arm64",
        "--distpath",
        dist,
        "--workpath",
        work,
        "--specpath",
        spec,
        "--add-data",
        f"{proje / 'ogretmen_cantasi/web/sablonlar'}:ogretmen_cantasi/web/sablonlar",
        "--add-data",
        f"{proje / 'ogretmen_cantasi/web/statik'}:ogretmen_cantasi/web/statik",
        "--add-data",
        f"{proje / 'veri'}:veri",
        "--copy-metadata",
        "ogretmen-cantasi",
        proje / "scripts/pyinstaller_entry.py",
    )
    shutil.copytree(dist / "ogretmen-cantasi", hedef)


def _yolu_kaldir(yol: Path) -> None:
    """Symlink/dosya/dizin ayrımıyla hedefi kaldırır; yoksa sessiz geçer."""
    if not (yol.exists() or yol.is_symlink()):
        return
    if yol.is_dir() and not yol.is_symlink():
        shutil.rmtree(yol)
    else:
        yol.unlink()


def _surum_dogrula(proje: Path) -> str:
    """pyproject ile launcher.sh sürümünün eşleştiğini garanti eder.

    Başlatıcı /saglik yanıtındaki sürümü kendi sabitine karşı denetliyor;
    ikisi ayrışırsa başlatıcı kendi sunucusunu yabancı sayıp her tıklamada
    yeni port açar. Sürüm yükseltmesinde launcher.sh unutulursa kurulum
    burada açık hatayla durur.
    """
    surum = tomllib.loads((proje / "pyproject.toml").read_text(encoding="utf-8"))["project"][
        "version"
    ]
    betik = (proje / "macos/launcher.sh").read_text(encoding="utf-8")
    eslesme = re.search(r'^expected_version="([^"]+)"', betik, re.M)
    if not eslesme or eslesme.group(1) != surum:
        raise SystemExit(
            f"Hata: launcher.sh expected_version={eslesme.group(1) if eslesme else 'YOK'} "
            f"ile pyproject sürümü {surum} uyuşmuyor; ikisini birlikte güncelleyin."
        )
    return surum


def kur(proje: Path, logo: Path, hedef: Path, masaustu: Path, *, replace: bool) -> None:
    proje = proje.resolve()
    logo = logo.resolve()
    if not (proje / ".venv/bin/ogretmen-cantasi").is_file():
        raise SystemExit(
            "Hata: .venv/bin/ogretmen-cantasi bulunamadı. Önce: uv sync"
        )
    if not logo.is_file():
        raise SystemExit(f"Hata: simge bulunamadı: {logo}")
    if (hedef.exists() or hedef.is_symlink()) and not replace:
        raise SystemExit(f"Hata: {hedef} zaten var. Yenilemek için --replace kullanın.")
    surum = _surum_dogrula(proje)

    hedef.parent.mkdir(parents=True, exist_ok=True)
    masaustu.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="ogretmen-cantasi-app-") as gecici_ham:
        gecici = Path(gecici_ham)
        app = gecici / APP_NAME
        contents = app / "Contents"
        macos = contents / "MacOS"
        resources = contents / "Resources"
        macos.mkdir(parents=True)
        resources.mkdir()
        _runtime_uret(proje, resources / "runtime", gecici)

        plist = {
            "CFBundleDevelopmentRegion": "tr",
            "CFBundleDisplayName": "Öğretmen Çantası",
            "CFBundleExecutable": CALISTIRILABILIR,
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": BUNDLE_ID,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Öğretmen Çantası",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": surum,
            "CFBundleVersion": "2",
            "LSMinimumSystemVersion": "13.0",
            # Dock'ta simge açmaz: sunucuyu başlatıp tarayıcıya devreder.
            "LSUIElement": True,
            "NSHighResolutionCapable": True,
        }
        with (contents / "Info.plist").open("wb") as f:
            plistlib.dump(plist, f, sort_keys=True)

        betik = (proje / "macos/launcher.sh").read_text(encoding="utf-8")
        (resources / "launcher.sh").write_text(betik, encoding="utf-8")
        (resources / "launcher.sh").chmod(0o755)
        shutil.copy2(logo, resources / "ogretmen-cantasi-icon.png")
        _icns_uret(logo, resources / "AppIcon.icns", gecici)

        _calistir(
            "/usr/bin/xcrun", "swiftc", "-O",
            "-target", "arm64-apple-macosx13.0",
            "-framework", "AppKit",
            str(proje / f"macos/{CALISTIRILABILIR}.swift"),
            "-o", str(macos / CALISTIRILABILIR),
        )
        _calistir("/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app))
        _calistir("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))

        gecici_hedef = hedef.parent / f".{APP_NAME}.kuruluyor"
        if gecici_hedef.exists():
            shutil.rmtree(gecici_hedef)
        shutil.copytree(app, gecici_hedef, symlinks=True)
        _calistir("/usr/bin/codesign", "--verify", "--deep", "--strict", str(gecici_hedef))

        eski_hedef = hedef.parent / f".{APP_NAME}.onceki"
        _yolu_kaldir(eski_hedef)
        if hedef.exists() or hedef.is_symlink():
            os.replace(hedef, eski_hedef)
        try:
            os.replace(gecici_hedef, hedef)
            _calistir("/usr/bin/codesign", "--verify", "--deep", "--strict", str(hedef))
        except Exception:
            if hedef.exists():
                shutil.rmtree(hedef)
            if eski_hedef.exists():
                os.replace(eski_hedef, hedef)
            raise
        if eski_hedef.exists():
            shutil.rmtree(eski_hedef)

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
        "--logo", type=Path, default=proje / "assets/ogretmen-cantasi-icon.png"
    )
    args = ayristirici.parse_args()
    kur(proje, args.logo, args.hedef, args.masaustu, replace=args.replace)


if __name__ == "__main__":
    main()
