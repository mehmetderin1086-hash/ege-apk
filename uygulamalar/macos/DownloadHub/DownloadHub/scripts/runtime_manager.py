#!/usr/bin/env python3
"""Install and verify optional DownloadHub runtimes from a fail-closed manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zipfile
from datetime import UTC, datetime
from pathlib import Path, PurePosixPath
from typing import Any, BinaryIO
from urllib.parse import urlparse

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = PROJECT_ROOT / "runtime-manifest.json"
DEFAULT_RUNTIME_DIR = PROJECT_ROOT / "runtime"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SUPPORTED_ARCHIVES = {"raw", "zip", "tar", "tar.gz", "tar.xz", "tar.bz2"}
SUPPORTED_INSTALL_METHODS = {"archive", "source-build"}


class RuntimePolicyError(RuntimeError):
    """Raised when a manifest or runtime violates the installation policy."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def platform_key() -> str:
    system = platform.system().lower()
    machine = platform.machine().lower()
    if machine in {"aarch64", "arm64"}:
        machine = "arm64"
    return f"{system}-{machine}"


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise RuntimePolicyError(f"Manifest bulunamadı: {path}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimePolicyError(f"Manifest geçerli JSON değil: {exc}") from exc

    if manifest.get("schema_version") != 1:
        raise RuntimePolicyError("Desteklenmeyen runtime manifest şema sürümü")
    policy = manifest.get("policy")
    if not isinstance(policy, dict):
        raise RuntimePolicyError("Manifest policy bölümü eksik")
    platforms = manifest.get("platforms")
    if not isinstance(platforms, dict):
        raise RuntimePolicyError("Manifest platforms bölümü eksik")
    return manifest


def get_components(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    key = platform_key()
    if key != "darwin-arm64":
        raise RuntimePolicyError(f"Bu manifest yalnız macOS arm64 içindir; algılanan platform: {key}")
    platform_record = manifest["platforms"].get(key)
    if not isinstance(platform_record, dict):
        raise RuntimePolicyError(f"Manifestte platform yok: {key}")
    components = platform_record.get("components")
    if not isinstance(components, dict):
        raise RuntimePolicyError(f"Manifestte component listesi yok: {key}")
    return components


def require_simple_filename(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value or value in {".", ".."}:
        raise RuntimePolicyError(f"Geçersiz {field}")
    if Path(value).name != value or "/" in value or "\\" in value:
        raise RuntimePolicyError(f"{field} yalnız güvenli bir dosya adı olmalı: {value!r}")
    return value


def require_safe_member(value: Any) -> str:
    if not isinstance(value, str) or not value:
        raise RuntimePolicyError("binary_path eksik")
    member = PurePosixPath(value)
    if member.is_absolute() or ".." in member.parts or not member.name:
        raise RuntimePolicyError(f"Güvensiz binary_path: {value!r}")
    return member.as_posix()


def validate_component(name: str, record: dict[str, Any]) -> None:
    if not record.get("enabled"):
        raise RuntimePolicyError(
            f"{name}: bileşen devre dışı. URL ve SHA-256 doğrulanmadan etkinleştirilemez."
        )
    version = record.get("version")
    if not isinstance(version, str) or not version or version == "PIN_REQUIRED":
        raise RuntimePolicyError(f"{name}: sabitlenmiş version eksik")
    url = record.get("url")
    if not isinstance(url, str) or urlparse(url).scheme != "https":
        raise RuntimePolicyError(f"{name}: yalnız HTTPS indirme adresi kabul edilir")
    expected = record.get("sha256")
    if not isinstance(expected, str) or not SHA256_RE.fullmatch(expected):
        raise RuntimePolicyError(f"{name}: 64 haneli küçük harf SHA-256 eksik/geçersiz")
    if expected == "0" * 64:
        raise RuntimePolicyError(f"{name}: sıfır/yer tutucu SHA-256 reddedildi")
    archive = record.get("archive")
    if archive not in SUPPORTED_ARCHIVES:
        raise RuntimePolicyError(f"{name}: desteklenmeyen arşiv türü: {archive!r}")
    require_safe_member(record.get("binary_path"))
    require_simple_filename(record.get("install_name"), "install_name")
    method = record.get("install_method", "archive")
    if method not in SUPPORTED_INSTALL_METHODS:
        raise RuntimePolicyError(f"{name}: desteklenmeyen kurulum yöntemi: {method!r}")
    if method == "source-build":
        if platform_key() != "darwin-arm64" or archive not in {
            "tar",
            "tar.gz",
            "tar.xz",
            "tar.bz2",
        }:
            raise RuntimePolicyError(f"{name}: source-build yalnız macOS arm64 TAR kaynağını kabul eder")
        require_safe_member(record.get("source_dir"))
        arguments = record.get("configure_args")
        if (
            not isinstance(arguments, list)
            or not arguments
            or not all(
                isinstance(value, str) and value.startswith("--") and "\x00" not in value
                for value in arguments
            )
        ):
            raise RuntimePolicyError(f"{name}: güvenli configure_args listesi eksik")


def load_registry(runtime_dir: Path) -> dict[str, Any]:
    path = runtime_dir / "installed.json"
    if not path.exists():
        return {"schema_version": 1, "components": {}}
    try:
        registry = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RuntimePolicyError(f"Kurulu runtime kaydı okunamadı: {exc}") from exc
    if registry.get("schema_version") != 1 or not isinstance(registry.get("components"), dict):
        raise RuntimePolicyError("Kurulu runtime kaydının şeması geçersiz")
    return registry


def write_registry(runtime_dir: Path, registry: dict[str, Any]) -> None:
    runtime_dir.mkdir(parents=True, exist_ok=True)
    destination = runtime_dir / "installed.json"
    temporary = runtime_dir / f".installed.{os.getpid()}.tmp"
    temporary.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, destination)


def download_verified(
    name: str,
    record: dict[str, Any],
    destination: Path,
    maximum_download_bytes: int,
) -> None:
    request = urllib.request.Request(
        record["url"],
        headers={"User-Agent": "DownloadHub-runtime-installer/0.1"},
    )
    digest = hashlib.sha256()
    received = 0
    try:
        with urllib.request.urlopen(request, timeout=60) as response:  # noqa: S310
            final_url = response.geturl()
            if urlparse(final_url).scheme != "https":
                raise RuntimePolicyError(f"{name}: yönlendirme HTTPS dışına çıktı")
            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > maximum_download_bytes:
                raise RuntimePolicyError(f"{name}: dosya manifest boyut sınırını aşıyor")
            with destination.open("wb") as output:
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    received += len(block)
                    if received > maximum_download_bytes:
                        raise RuntimePolicyError(f"{name}: indirme manifest boyut sınırını aştı")
                    digest.update(block)
                    output.write(block)
    except RuntimePolicyError:
        raise
    except Exception as exc:
        raise RuntimePolicyError(f"{name}: indirme başarısız: {exc}") from exc

    actual = digest.hexdigest()
    if actual != record["sha256"]:
        destination.unlink(missing_ok=True)
        raise RuntimePolicyError(f"{name}: SHA-256 uyuşmadı; beklenen {record['sha256']}, bulunan {actual}")


def copy_stream(source: BinaryIO, destination: Path) -> None:
    with destination.open("wb") as output:
        shutil.copyfileobj(source, output, length=1024 * 1024)


def extract_payload(archive_path: Path, record: dict[str, Any], destination: Path) -> None:
    archive_type = record["archive"]
    member_name = require_safe_member(record["binary_path"])
    if archive_type == "raw":
        shutil.copyfile(archive_path, destination)
        return

    if archive_type == "zip":
        try:
            with zipfile.ZipFile(archive_path) as archive:
                info = archive.getinfo(member_name)
                unix_mode = info.external_attr >> 16
                if info.is_dir() or stat.S_ISLNK(unix_mode):
                    raise RuntimePolicyError("Arşivdeki binary_path normal dosya değil")
                with archive.open(info) as source:
                    copy_stream(source, destination)
        except KeyError as exc:
            raise RuntimePolicyError(f"Arşivde binary_path bulunamadı: {member_name}") from exc
        except zipfile.BadZipFile as exc:
            raise RuntimePolicyError("Geçersiz ZIP arşivi") from exc
        return

    try:
        with tarfile.open(archive_path, mode="r:*") as archive:
            member = archive.getmember(member_name)
            if not member.isfile():
                raise RuntimePolicyError("Arşivdeki binary_path normal dosya değil")
            source = archive.extractfile(member)
            if source is None:
                raise RuntimePolicyError("Arşivdeki binary_path okunamadı")
            with source:
                copy_stream(source, destination)
    except KeyError as exc:
        raise RuntimePolicyError(f"Arşivde binary_path bulunamadı: {member_name}") from exc
    except tarfile.TarError as exc:
        raise RuntimePolicyError("Geçersiz TAR arşivi") from exc


def build_source_payload(
    name: str,
    archive_path: Path,
    record: dict[str, Any],
    work_dir: Path,
    destination: Path,
) -> None:
    """Compile a pinned official source archive without a shell or Homebrew."""

    source_area = work_dir / "source"
    source_area.mkdir(mode=0o700)
    try:
        with tarfile.open(archive_path, mode="r:*") as archive:
            archive.extractall(source_area, filter="data")
    except (tarfile.TarError, OSError) as exc:
        raise RuntimePolicyError(f"{name}: kaynak arşivi güvenle çıkarılamadı") from exc

    relative_source = require_safe_member(record["source_dir"])
    source_root = (source_area / relative_source).resolve()
    try:
        source_root.relative_to(source_area.resolve())
    except ValueError as exc:
        raise RuntimePolicyError(f"{name}: kaynak klasörü çalışma alanının dışında") from exc
    configure = source_root / "configure"
    if not configure.is_file() or configure.is_symlink():
        raise RuntimePolicyError(f"{name}: doğrulanmış kaynakta configure betiği bulunamadı")

    build_home = work_dir / "home"
    build_home.mkdir(mode=0o700)
    environment = {
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "HOME": str(build_home),
        "TMPDIR": str(work_dir),
        "LC_ALL": "C",
        "LANG": "C",
        "CC": "/usr/bin/clang",
        "CXX": "/usr/bin/clang++",
        "MACOSX_DEPLOYMENT_TARGET": "13.0",
        "SOURCE_DATE_EPOCH": "1700000000",
        "ZERO_AR_DATE": "1",
    }
    log_path = work_dir / f"{name}-source-build.log"
    try:
        with log_path.open("wb") as log:
            configured = subprocess.run(
                [str(configure), *record["configure_args"]],
                cwd=source_root,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=300,
            )
            if configured.returncode != 0:
                raise RuntimePolicyError(f"{name}: kaynak yapılandırması başarısız")
            built = subprocess.run(
                ["/usr/bin/make", "-j", str(min(os.cpu_count() or 2, 8))],
                cwd=source_root,
                env=environment,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=900,
            )
            if built.returncode != 0:
                raise RuntimePolicyError(f"{name}: kaynak derlemesi başarısız")
    except FileNotFoundError as exc:
        raise RuntimePolicyError(
            f"{name}: Apple Command Line Tools bulunamadı; Xcode CLT kurun veya paketli uygulamayı kullanın"
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimePolicyError(f"{name}: kaynak derlemesi zaman aşımına uğradı") from exc

    relative_binary = require_safe_member(record["binary_path"])
    built_binary = (source_area / relative_binary).resolve()
    try:
        built_binary.relative_to(source_area.resolve())
    except ValueError as exc:
        raise RuntimePolicyError(f"{name}: derleme çıktısı çalışma alanının dışında") from exc
    if not built_binary.is_file() or built_binary.is_symlink():
        raise RuntimePolicyError(f"{name}: beklenen derleme çıktısı oluşmadı")
    shutil.copyfile(built_binary, destination)


def validate_executable(path: Path, name: str) -> None:
    if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
        raise RuntimePolicyError(f"{name}: çıkarılan içerik normal, dolu bir dosya değil")
    os.chmod(path, 0o755)
    file_tool = Path("/usr/bin/file")
    if file_tool.exists():
        result = subprocess.run(
            [str(file_tool), "-b", str(path)],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
        description = result.stdout.lower()
        if "mach-o" in description and "arm64" not in description:
            raise RuntimePolicyError(f"{name}: indirilen Mach-O arm64 değil: {result.stdout.strip()}")


def backup_existing(target: Path, backup_dir: Path) -> Path | None:
    if not target.exists():
        return None
    if not target.is_file() or target.is_symlink():
        raise RuntimePolicyError(f"Mevcut runtime güvenli bir normal dosya değil: {target}")
    backup_dir.mkdir(parents=True, exist_ok=True)
    digest = sha256_file(target)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
    backup = backup_dir / f"{target.name}.{stamp}.{digest}.bak"
    shutil.copy2(target, backup)
    return backup


def backup_history(registry: dict[str, Any], name: str) -> list[dict[str, Any]]:
    histories = registry.setdefault("backups", {})
    if not isinstance(histories, dict):
        raise RuntimePolicyError("Kurulu runtime yedek kaydının şeması geçersiz")
    history = histories.setdefault(name, [])
    if not isinstance(history, list):
        raise RuntimePolicyError(f"{name}: runtime yedek geçmişinin şeması geçersiz")
    return history


def install_component(
    name: str,
    record: dict[str, Any],
    runtime_dir: Path,
    maximum_download_bytes: int,
) -> None:
    validate_component(name, record)
    runtime_dir.mkdir(parents=True, exist_ok=True)
    bin_dir = runtime_dir / "bin"
    bin_dir.mkdir(parents=True, exist_ok=True)
    target = bin_dir / require_simple_filename(record["install_name"], "install_name")
    registry = load_registry(runtime_dir)
    previous_record = registry["components"].get(name)
    try:
        existing = verify_component(name, record, runtime_dir, registry)
    except RuntimePolicyError:
        pass
    else:
        print(f"{name}: zaten doğrulanmış ve hazır ({existing})")
        return

    with tempfile.TemporaryDirectory(prefix=f".{name}-", dir=runtime_dir) as temporary_name:
        temporary_dir = Path(temporary_name)
        archive = temporary_dir / "download"
        candidate = temporary_dir / "candidate"
        print(f"{name}: HTTPS kaynağı indiriliyor…")
        download_verified(name, record, archive, maximum_download_bytes)
        if record.get("install_method", "archive") == "source-build":
            print(f"{name}: doğrulanmış resmi kaynak Homebrew olmadan derleniyor…")
            build_source_payload(name, archive, record, temporary_dir, candidate)
        else:
            extract_payload(archive, record, candidate)
        validate_executable(candidate, name)
        candidate_digest = sha256_file(candidate)
        backup = backup_existing(target, runtime_dir / "backups")
        try:
            os.replace(candidate, target)
        except Exception:
            if backup is not None and not target.exists():
                shutil.copy2(backup, target)
            raise

    if backup is not None and isinstance(previous_record, dict):
        backup_history(registry, name).append(
            {
                "file": backup.name,
                "binary_sha256": sha256_file(backup),
                "component": previous_record,
                "saved_at": datetime.now(UTC).isoformat(),
            }
        )
    registry["components"][name] = {
        "version": record["version"],
        "manifest_sha256": record["sha256"],
        "binary_sha256": candidate_digest,
        "install_name": target.name,
        "installed_at": datetime.now(UTC).isoformat(),
    }
    write_registry(runtime_dir, registry)
    print(f"{name}: doğrulandı ve kuruldu ({target})")


def verify_component(name: str, record: dict[str, Any], runtime_dir: Path, registry: dict[str, Any]) -> Path:
    validate_component(name, record)
    installed = registry["components"].get(name)
    if not isinstance(installed, dict):
        raise RuntimePolicyError(f"{name}: manifestte etkin fakat kurulu değil")
    install_name = require_simple_filename(record["install_name"], "install_name")
    if installed.get("install_name") != install_name:
        raise RuntimePolicyError(f"{name}: kurulu dosya adı manifest ile uyuşmuyor")
    if installed.get("version") != record["version"]:
        raise RuntimePolicyError(f"{name}: kurulu sürüm manifest ile uyuşmuyor")
    if installed.get("manifest_sha256") != record["sha256"]:
        raise RuntimePolicyError(f"{name}: kurulum kaydı güncel manifest hash'iyle uyuşmuyor")
    target = runtime_dir / "bin" / install_name
    if not target.is_file() or target.is_symlink():
        raise RuntimePolicyError(f"{name}: kurulu binary kayıp veya güvensiz")
    actual = sha256_file(target)
    if actual != installed.get("binary_sha256"):
        raise RuntimePolicyError(f"{name}: kurulu binary bütünlük kontrolünden geçmedi")
    return target


def rollback_component(name: str, record: dict[str, Any], runtime_dir: Path) -> None:
    install_name = require_simple_filename(record.get("install_name"), "install_name")
    target = runtime_dir / "bin" / install_name
    registry = load_registry(runtime_dir)
    history = backup_history(registry, name)
    if not history:
        raise RuntimePolicyError(f"{name}: geri alınabilecek yedek yok")
    restore_entry = history.pop()
    if not isinstance(restore_entry, dict):
        raise RuntimePolicyError(f"{name}: yedek kaydı geçersiz")
    backup_name = require_simple_filename(restore_entry.get("file"), "backup file")
    backup = runtime_dir / "backups" / backup_name
    if not backup.is_file() or backup.is_symlink():
        raise RuntimePolicyError(f"{name}: kayıtlı yedek bulunamadı veya güvensiz")
    parts = backup.name.split(".")
    if len(parts) < 4 or not SHA256_RE.fullmatch(parts[-2]):
        raise RuntimePolicyError(f"{name}: yedek adı bütünlük bilgisi taşımıyor")
    expected = parts[-2]
    actual = sha256_file(backup)
    if actual != expected or actual != restore_entry.get("binary_sha256"):
        raise RuntimePolicyError(f"{name}: yedek bütünlük kontrolünden geçmedi")
    restored_record = restore_entry.get("component")
    if not isinstance(restored_record, dict):
        raise RuntimePolicyError(f"{name}: yedek kurulum kaydı geçersiz")
    target.parent.mkdir(parents=True, exist_ok=True)
    current_record = registry["components"].get(name)
    current_backup = backup_existing(target, runtime_dir / "backups")
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temporary:
        temp_path = Path(temporary.name)
    try:
        shutil.copy2(backup, temp_path)
        os.chmod(temp_path, 0o755)
        validate_executable(temp_path, name)
        os.replace(temp_path, target)
    finally:
        temp_path.unlink(missing_ok=True)

    if current_backup is not None and isinstance(current_record, dict):
        history.append(
            {
                "file": current_backup.name,
                "binary_sha256": sha256_file(current_backup),
                "component": current_record,
                "saved_at": datetime.now(UTC).isoformat(),
            }
        )
    registry["components"][name] = dict(restored_record)
    registry["components"][name]["restored_at"] = datetime.now(UTC).isoformat()
    registry["components"][name]["restored_from"] = backup.name
    write_registry(runtime_dir, registry)
    print(f"{name}: {backup.name} yedeğine geri alındı")


def names_for_action(
    components: dict[str, dict[str, Any]], requested: list[str], required: bool = False
) -> list[str]:
    if requested:
        unknown = sorted(set(requested) - set(components))
        if unknown:
            raise RuntimePolicyError(f"Bilinmeyen bileşen: {', '.join(unknown)}")
        return requested
    if required:
        return [name for name, item in components.items() if item.get("required")]
    return [name for name, item in components.items() if item.get("enabled")]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--runtime-dir", type=Path, default=DEFAULT_RUNTIME_DIR)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("status", help="manifest ve kurulum durumunu göster")
    install = subparsers.add_parser("install", help="etkin bileşenleri indir ve doğrula")
    install.add_argument("components", nargs="*")
    verify = subparsers.add_parser("verify", help="kurulu bileşen bütünlüğünü doğrula")
    verify.add_argument("components", nargs="*")
    verify.add_argument("--required", action="store_true")
    paths = subparsers.add_parser("paths", help="doğrulanmış etkin binary yollarını yaz")
    paths.add_argument("components", nargs="*")
    rollback = subparsers.add_parser("rollback", help="bileşenin son güvenli yedeğini geri al")
    rollback.add_argument("component")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        manifest = load_manifest(args.manifest.resolve())
        components = get_components(manifest)
        runtime_dir = args.runtime_dir.resolve()
        registry = load_registry(runtime_dir)

        if args.command == "status":
            for name, record in components.items():
                state = "disabled"
                detail = record.get("note", "")
                if record.get("enabled"):
                    try:
                        path = verify_component(name, record, runtime_dir, registry)
                        state = "ready"
                        detail = str(path)
                    except RuntimePolicyError as exc:
                        state = "not-ready"
                        detail = str(exc)
                print(f"{name:8} {state:10} {record.get('version', '-'):16} {detail}")
            return 0

        if args.command == "install":
            names = names_for_action(components, args.components)
            if not names:
                raise RuntimePolicyError(
                    "Etkin runtime yok. Resmî URL ve SHA-256 eklemeden indirme yapılmaz."
                )
            maximum = int(manifest["policy"].get("maximum_download_bytes", 0))
            if maximum <= 0:
                raise RuntimePolicyError("Manifest indirme boyut sınırı geçersiz")
            for name in names:
                install_component(name, components[name], runtime_dir, maximum)
            return 0

        if args.command in {"verify", "paths"}:
            names = names_for_action(
                components,
                args.components,
                required=getattr(args, "required", False),
            )
            if not names:
                raise RuntimePolicyError("Doğrulanacak etkin runtime yok")
            verified = [verify_component(name, components[name], runtime_dir, registry) for name in names]
            if args.command == "verify":
                for name, path in zip(names, verified, strict=True):
                    print(f"{name}: OK ({path})")
            else:
                for path in verified:
                    print(path)
            return 0

        if args.command == "rollback":
            if args.component not in components:
                raise RuntimePolicyError(f"Bilinmeyen bileşen: {args.component}")
            rollback_component(args.component, components[args.component], runtime_dir)
            return 0
    except RuntimePolicyError as exc:
        print(f"HATA: {exc}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
