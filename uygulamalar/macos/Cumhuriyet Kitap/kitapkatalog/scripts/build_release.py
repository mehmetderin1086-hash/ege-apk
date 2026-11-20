#!/usr/bin/env python3
"""Build native releases and deterministic source archives without downloads."""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import importlib.util
import json
import os
import platform
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Final, Literal

PROJECT_ROOT: Final = Path(__file__).resolve().parents[1]
SOURCE_ROOT_FILES: Final = (
    ".gitignore",
    "LICENSE",
    "README.md",
    "pyproject.toml",
    "uv.lock",
)
SOURCE_DIRECTORIES: Final = ("deployment", "docs", "scripts", "src", "tests")
IGNORED_PARTS: Final = {
    ".git",
    ".pytest_cache",
    ".ruff_cache",
    ".venv",
    "__pycache__",
    "build",
    "dist",
    "outputs",
    "work",
}
FIXED_ZIP_TIME: Final = (2020, 1, 1, 0, 0, 0)
APP_NAME: Final = "KitapKatalog"
NativeBackend = Literal["pyside6", "pyinstaller"]


@dataclass(frozen=True, slots=True)
class BuildTarget:
    name: str
    system: str
    machines: frozenset[str]
    artifact_suffix: str


TARGETS: Final = {
    "macos-arm64": BuildTarget(
        name="macos-arm64",
        system="darwin",
        machines=frozenset({"arm64", "aarch64"}),
        artifact_suffix=".app",
    ),
    "windows-x64": BuildTarget(
        name="windows-x64",
        system="windows",
        machines=frozenset({"amd64", "x86_64"}),
        artifact_suffix=".exe",
    ),
}


class ReleaseBuildError(RuntimeError):
    """A release cannot be produced without violating the build contract."""


def _is_ignored(relative: Path) -> bool:
    return any(part in IGNORED_PARTS for part in relative.parts) or any(
        part.endswith((".pyc", ".pyo")) for part in relative.parts
    )


def source_files(project_root: Path) -> tuple[Path, ...]:
    project_root = project_root.resolve()
    selected: list[Path] = []
    for name in SOURCE_ROOT_FILES:
        path = project_root / name
        if path.is_file() and not path.is_symlink():
            selected.append(path)
    for directory_name in SOURCE_DIRECTORIES:
        directory = project_root / directory_name
        if not directory.is_dir():
            continue
        for path in directory.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(project_root)
            if not _is_ignored(relative):
                selected.append(path)
    return tuple(sorted(set(selected), key=lambda item: item.relative_to(project_root).as_posix()))


def _publish_file_without_overwrite(part: Path, target: Path) -> None:
    """Atomically publish a same-filesystem part file and refuse replacement."""

    try:
        os.link(part, target)
    except FileExistsError as exc:
        raise ReleaseBuildError(f"Hedef zaten var; üzerine yazılmadı: {target}") from exc
    except OSError as exc:
        # Hard-link publication is supported by APFS/NTFS. Failing closed is
        # safer than falling back to a copy that could leave a partial archive.
        raise ReleaseBuildError(f"Arşiv atomik yayımlanamadı: {exc}") from exc
    finally:
        part.unlink(missing_ok=True)


def build_source_archive(project_root: Path, target: Path) -> Path:
    project_root = project_root.resolve()
    target = target.resolve()
    if target.exists():
        raise ReleaseBuildError(f"Hedef zaten var; üzerine yazılmadı: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    files = source_files(project_root)
    if not files:
        raise ReleaseBuildError(f"Arşivlenecek kaynak bulunamadı: {project_root}")

    descriptor, part_name = tempfile.mkstemp(
        prefix=f".{target.name}.",
        suffix=".part",
        dir=target.parent,
    )
    os.close(descriptor)
    part = Path(part_name)
    try:
        with zipfile.ZipFile(part, "w", compression=zipfile.ZIP_STORED) as archive:
            for path in files:
                relative = path.relative_to(project_root).as_posix()
                info = zipfile.ZipInfo(f"{APP_NAME}/{relative}", date_time=FIXED_ZIP_TIME)
                info.create_system = 3
                executable = path.suffix == ".command" or os.access(path, os.X_OK)
                permissions = 0o755 if executable else 0o644
                info.external_attr = (permissions & 0xFFFF) << 16
                info.compress_type = zipfile.ZIP_STORED
                archive.writestr(info, path.read_bytes())
        _publish_file_without_overwrite(part, target)
    except Exception:
        part.unlink(missing_ok=True)
        raise
    return target


def assert_native_target(target: BuildTarget) -> None:
    current_system = platform.system().casefold()
    current_machine = platform.machine().casefold()
    if current_system != target.system or current_machine not in target.machines:
        raise ReleaseBuildError(
            f"{target.name} paketi yalnız kendi platformunda üretilir; "
            f"bu makine {current_system}/{current_machine}."
        )
    if sys.version_info[:2] != (3, 12):
        raise ReleaseBuildError(
            f"Paketleme Python 3.12 gerektirir; çalışan sürüm {platform.python_version()}."
        )


def _adjacent_or_path_command(
    value: str | None,
    *,
    command_name: str,
    display_name: str,
) -> Path:
    if value:
        candidate = Path(value).expanduser()
        if candidate.is_file():
            return candidate.resolve()
        located = shutil.which(value)
        if located:
            return Path(located).resolve()
        raise ReleaseBuildError(f"{display_name} bulunamadı: {value}")

    # Keep the virtual-environment path. Resolving the python symlink first
    # would incorrectly look beside uv's base interpreter instead of .venv/bin.
    adjacent = (
        Path(sys.executable)
        .absolute()
        .with_name(f"{command_name}.exe" if os.name == "nt" else command_name)
    )
    if adjacent.is_file():
        return adjacent
    located = shutil.which(command_name)
    if located:
        return Path(located).resolve()
    raise ReleaseBuildError(
        f"{display_name} bulunamadı. Build ortamını yerel wheel deposundan kurun."
    )


def _command_path(value: str | None) -> Path:
    return _adjacent_or_path_command(
        value,
        command_name="pyside6-deploy",
        display_name="pyside6-deploy",
    )


def _pyinstaller_command_path(value: str | None) -> Path:
    return _adjacent_or_path_command(
        value,
        command_name="pyinstaller",
        display_name="PyInstaller",
    )


def _build_packages() -> str:
    missing: list[str] = []
    package_names = ("nuitka", "ordered_set", "zstandard")
    locked: list[str] = []
    for name in package_names:
        if importlib.util.find_spec(name) is None:
            missing.append(name)
            continue
        locked.append(f"{name}=={importlib.metadata.version(name)}")
    if importlib.util.find_spec("PySide6") is None:
        missing.append("PySide6")
    if missing:
        raise ReleaseBuildError(
            "Çevrimdışı build bağımlılıkları eksik: "
            + ", ".join(missing)
            + ". Araç bunları internetten indirmeyecek."
        )
    return ",".join(locked)


def _require_pyinstaller() -> None:
    missing = [
        name
        for name in ("PyInstaller", "_pyinstaller_hooks_contrib")
        if importlib.util.find_spec(name) is None
    ]
    if missing:
        raise ReleaseBuildError(
            "Çevrimdışı PyInstaller bağımlılıkları eksik: "
            + ", ".join(missing)
            + ". Araç bunları internetten indirmeyecek."
        )


def _icon_arguments() -> tuple[str, ...]:
    """Uygulama simgesini PyInstaller'a geçirir; simge yoksa sessizce atlar.

    Simge sürüm yapısının zorunlu parçası değil: yoksa paket PyInstaller'ın
    jenerik simgesiyle çıkar ve yapı yine de tamamlanır.
    """
    icon = PROJECT_ROOT / "assets/kitapkatalog-icon.icns"
    return ("--icon", str(icon)) if icon.is_file() else ()


def render_deploy_spec(
    *,
    project_root: Path,
    executable_directory: Path,
    python_path: Path | None = None,
    build_packages: str = "nuitka,ordered_set,zstandard",
) -> str:
    template = (project_root / "deployment" / "pysidedeploy.spec.template").read_text(
        encoding="utf-8"
    )
    replacements = {
        "@PROJECT_DIR@": str(project_root.resolve()),
        "@INPUT_FILE@": str((project_root / "deployment" / "entry.py").resolve()),
        "@EXEC_DIRECTORY@": str(executable_directory.resolve()),
        "@PYTHON_PATH@": str((python_path or Path(sys.executable)).resolve()),
        "@BUILD_PACKAGES@": build_packages,
    }
    for marker, value in replacements.items():
        if "\n" in value or "\r" in value:
            raise ReleaseBuildError(f"Geçersiz spec değeri: {marker}")
        template = template.replace(marker, value)
    unresolved = [marker for marker in replacements if marker in template]
    if unresolved:
        raise ReleaseBuildError("Deploy spec işaretçileri çözülemedi: " + ", ".join(unresolved))
    return template


def _validate_model_bundle(path: Path) -> None:
    source_path = PROJECT_ROOT / "src"
    if str(source_path) not in sys.path:
        sys.path.insert(0, str(source_path))
    from kitapkatalog.model_bundle import verify_locked_bundle

    problems = verify_locked_bundle(path)
    if problems:
        raise ReleaseBuildError("Model paketi eklenmedi: " + "; ".join(problems))


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(4 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def _sha256_tree(path: Path) -> str:
    if path.is_file():
        return _sha256_file(path)
    digest = hashlib.sha256()
    for item in sorted(
        path.rglob("*"), key=lambda candidate: candidate.relative_to(path).as_posix()
    ):
        if not item.is_file():
            continue
        relative = item.relative_to(path).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(4, "big"))
        digest.update(relative)
        digest.update(bytes.fromhex(_sha256_file(item)))
    return digest.hexdigest()


def _find_application(directory: Path, target: BuildTarget) -> Path:
    expected_name = f"{APP_NAME}{target.artifact_suffix}"
    matches = tuple(directory.rglob(expected_name))
    matches = tuple(
        item
        for item in matches
        if (item.is_dir() if target.artifact_suffix == ".app" else item.is_file())
    )
    if len(matches) != 1:
        raise ReleaseBuildError(
            f"pyside6-deploy çıktısında {expected_name} tekil bulunamadı ({len(matches)} eşleşme)."
        )
    return matches[0]


def _run_release_command(command: list[str], *, action: str) -> None:
    completed = subprocess.run(command, check=False)
    if completed.returncode != 0:
        raise ReleaseBuildError(f"{action} başarısız oldu (çıkış {completed.returncode}).")


def _sign_macos_bundle(application: Path) -> None:
    """Remove cloud metadata, ad-hoc sign, and verify the final app bundle."""

    _run_release_command(
        ["/usr/bin/xattr", "-cr", str(application)],
        action="macOS genişletilmiş öznitelik temizliği",
    )
    _run_release_command(
        ["/usr/bin/chflags", "-R", "nohidden", str(application)],
        action="macOS dosya bayrağı temizliği",
    )
    _run_release_command(
        [
            "/usr/bin/codesign",
            "--force",
            "--deep",
            "--sign",
            "-",
            "--timestamp=none",
            str(application),
        ],
        action="macOS ad-hoc imzalama",
    )
    _run_release_command(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(application)],
        action="macOS imza doğrulaması",
    )


def _project_bundle_version(project_root: Path) -> tuple[str, str]:
    """Return the project version and its validated Apple build-number form."""

    pyproject = project_root / "pyproject.toml"
    try:
        with pyproject.open("rb") as stream:
            payload = tomllib.load(stream)
        version = str(payload["project"]["version"]).strip()
    except (OSError, KeyError, TypeError, tomllib.TOMLDecodeError) as exc:
        raise ReleaseBuildError(
            f"Proje sürümü pyproject.toml dosyasından okunamadı: {pyproject}: {exc}"
        ) from exc

    match = re.fullmatch(r"([0-9]{1,4})\.([0-9]{1,2})\.([0-9]{1,2})", version)
    if match is None:
        raise ReleaseBuildError(
            "macOS paket sürümü üç sayısal bileşenden oluşmalıdır "
            f"(örnek: 0.2.2); bulunan: {version!r}"
        )
    components = tuple(int(value) for value in match.groups())
    bundle_version = ".".join(str(value) for value in components)
    return version, bundle_version


def _stamp_macos_bundle_version(
    application: Path,
    *,
    project_root: Path = PROJECT_ROOT,
) -> None:
    """Write project version keys atomically before the bundle is signed."""

    plist_path = application / "Contents" / "Info.plist"
    if not plist_path.is_file():
        raise ReleaseBuildError(f"macOS Info.plist bulunamadı: {plist_path}")
    short_version, bundle_version = _project_bundle_version(project_root)
    try:
        with plist_path.open("rb") as stream:
            payload = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as exc:
        raise ReleaseBuildError(f"macOS Info.plist okunamadı: {plist_path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise ReleaseBuildError(f"macOS Info.plist sözlük değil: {plist_path}")

    payload["CFBundleShortVersionString"] = short_version
    payload["CFBundleVersion"] = bundle_version
    part = plist_path.with_name(f".{plist_path.name}.{os.getpid()}.part")
    try:
        with part.open("wb") as stream:
            plistlib.dump(payload, stream, fmt=plistlib.FMT_XML, sort_keys=True)
            stream.flush()
            os.fsync(stream.fileno())
        part.replace(plist_path)
    except (OSError, TypeError, OverflowError) as exc:
        part.unlink(missing_ok=True)
        raise ReleaseBuildError(f"macOS Info.plist yazılamadı: {plist_path}: {exc}") from exc


def _release_manifest(
    *,
    target: BuildTarget,
    application: Path,
    release_root: Path,
    model_directory: Path | None,
    build_backend: NativeBackend,
) -> dict[str, object]:
    model_manifest = model_directory / "model_manifest.lock.json" if model_directory else None
    return {
        "schema_version": 1,
        "application": APP_NAME,
        "target": target.name,
        "python": platform.python_version(),
        "build_backend": build_backend,
        "artifact": {
            "path": application.relative_to(release_root).as_posix(),
            "sha256_tree": _sha256_tree(application),
        },
        "models": {
            "mode": (
                "embedded"
                if model_directory and target.system == "darwin"
                else ("sidecar" if model_directory else "excluded")
            ),
            "path": (
                model_directory.relative_to(release_root).as_posix() if model_directory else None
            ),
            "manifest_sha256": _sha256_file(model_manifest) if model_manifest else None,
        },
        "network_downloads_allowed": False,
        "user_data_embedded": False,
    }


def build_native_release(
    *,
    target: BuildTarget,
    output_directory: Path,
    pyside6_deploy: str | None = None,
    pyinstaller: str | None = None,
    backend: NativeBackend = "pyside6",
    model_bundle: Path | None = None,
    dry_run: bool = False,
    keep_deployment_files: bool = False,
) -> Path | None:
    assert_native_target(target)
    if not (PROJECT_ROOT / "src" / "kitapkatalog" / "gui.py").is_file():
        raise ReleaseBuildError("GUI girişi eksik: src/kitapkatalog/gui.py")
    if backend == "pyside6":
        deploy_command = _command_path(pyside6_deploy)
        build_packages = _build_packages()
    elif backend == "pyinstaller":
        deploy_command = _pyinstaller_command_path(pyinstaller)
        _require_pyinstaller()
        build_packages = ""
    else:
        raise ReleaseBuildError(f"Bilinmeyen native build backend'i: {backend}")

    output_directory = output_directory.resolve()
    if output_directory.exists():
        raise ReleaseBuildError(f"Hedef zaten var; üzerine yazılmadı: {output_directory}")
    if model_bundle is not None:
        model_bundle = model_bundle.resolve()
        _validate_model_bundle(model_bundle)
    output_directory.parent.mkdir(parents=True, exist_ok=True)

    environment = os.environ.copy()
    existing_pythonpath = environment.get("PYTHONPATH")
    environment.update(
        {
            "PYTHONPATH": str(PROJECT_ROOT / "src")
            + (os.pathsep + existing_pythonpath if existing_pythonpath else ""),
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "PIP_NO_INDEX": "1",
            "PIP_DISABLE_PIP_VERSION_CHECK": "1",
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }
    )

    with tempfile.TemporaryDirectory(
        prefix=f".{output_directory.name}.",
        dir=output_directory.parent,
    ) as staging_name:
        staging = Path(staging_name)
        spec_path: Path | None = None
        if backend == "pyside6":
            spec_path = staging / "pysidedeploy.spec"
            spec_path.write_text(
                render_deploy_spec(
                    project_root=PROJECT_ROOT,
                    executable_directory=staging,
                    build_packages=build_packages,
                ),
                encoding="utf-8",
            )
            command = [str(deploy_command), "-c", str(spec_path), "--force"]
            if dry_run:
                command.append("--dry-run")
            if keep_deployment_files:
                command.append("--keep-deployment-files")
        else:
            command = [
                str(deploy_command),
                "--noconfirm",
                "--clean",
                "--windowed",
                "--onedir",
                "--name",
                APP_NAME,
                "--distpath",
                str(staging / "dist"),
                "--workpath",
                str(staging / "build"),
                "--specpath",
                str(staging / "spec"),
                "--paths",
                str(PROJECT_ROOT / "src"),
                # Verilmezse PyInstaller kendi jenerik `icon-windowed.icns`ini
                # gömer; simgeyi `scripts/make_icon.py` üretir.
                *_icon_arguments(),
                "--collect-data",
                "kitapkatalog",
                "--collect-data",
                "rapidocr",
                "--collect-data",
                "easyocr",
                "--collect-data",
                "pillow_heif",
                "--collect-all",
                "pypdfium2",
                "--copy-metadata",
                "rapidocr",
                "--copy-metadata",
                "easyocr",
                "--copy-metadata",
                "pillow_heif",
                "--copy-metadata",
                "pypdfium2",
                "--copy-metadata",
                "zxing-cpp",
                "--hidden-import",
                "zxingcpp",
            ]
            if target.system == "darwin":
                command.extend(
                    (
                        "--osx-bundle-identifier",
                        "local.kitapkatalog.app",
                    )
                )
            command.append(str(PROJECT_ROOT / "deployment" / "entry.py"))
            if dry_run:
                print(" ".join(command))
                return None
        completed = subprocess.run(
            command,
            cwd=PROJECT_ROOT,
            env=environment,
            check=False,
        )
        if completed.returncode != 0:
            raise ReleaseBuildError(
                f"{backend} build başarısız oldu (çıkış {completed.returncode})."
            )
        if dry_run:
            return None

        if spec_path is not None:
            spec_path.unlink(missing_ok=True)
        application = _find_application(staging, target)
        copied_models: Path | None = None
        if model_bundle is not None:
            copied_models = (
                application / "Contents" / "Resources" / "KitapKatalog-models"
                if target.system == "darwin"
                else staging / "KitapKatalog-models"
            )
            shutil.copytree(model_bundle, copied_models)
        if target.system == "darwin":
            _stamp_macos_bundle_version(application)
            _sign_macos_bundle(application)
        manifest = _release_manifest(
            target=target,
            application=application,
            release_root=staging,
            model_directory=copied_models,
            build_backend=backend,
        )
        (staging / "release-manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        if output_directory.exists():
            raise ReleaseBuildError(
                f"Hedef build sırasında oluşturuldu; üzerine yazılmadı: {output_directory}"
            )
        os.rename(staging, output_directory)
        return output_directory


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="KitapKatalog çevrimdışı yayınlarını üretir.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    source = subparsers.add_parser("source", help="Deterministik kaynak ZIP'i üret")
    source.add_argument("target", type=Path)

    native = subparsers.add_parser("native", help="Yerel platform uygulamasını üret")
    native.add_argument("target", choices=tuple(TARGETS))
    native.add_argument("output_directory", type=Path)
    native.add_argument("--model-bundle", type=Path)
    native.add_argument(
        "--backend",
        choices=("pyside6", "pyinstaller"),
        default="pyside6",
        help="Yerel paketleyici (varsayılan: pyside6)",
    )
    native.add_argument("--pyside6-deploy")
    native.add_argument("--pyinstaller")
    native.add_argument("--dry-run", action="store_true")
    native.add_argument("--keep-deployment-files", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    arguments = _parser().parse_args(argv)
    try:
        if arguments.command == "source":
            result = build_source_archive(PROJECT_ROOT, arguments.target)
        else:
            result = build_native_release(
                target=TARGETS[arguments.target],
                output_directory=arguments.output_directory,
                pyside6_deploy=arguments.pyside6_deploy,
                pyinstaller=arguments.pyinstaller,
                backend=arguments.backend,
                model_bundle=arguments.model_bundle,
                dry_run=arguments.dry_run,
                keep_deployment_files=arguments.keep_deployment_files,
            )
    except ReleaseBuildError as exc:
        print(f"HATA: {exc}", file=sys.stderr)
        return 2
    if result is not None:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
