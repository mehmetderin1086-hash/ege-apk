"""Persistent, private identity for one KitapKatalog data root."""

from __future__ import annotations

import os
import re
import secrets
import stat

from kitapkatalog import portable
from pathlib import Path

INSTANCE_FILE_NAME = "web_instance_id"
_INSTANCE_PATTERN = re.compile(r"^[0-9a-f]{32}$")


class InstanceIdentityError(RuntimeError):
    """The data-root identity cannot be created or trusted."""


def instance_id_for_root(root: Path) -> str:
    """Return a stable random ID stored as an owned regular ``0600`` file."""

    root = Path(root)
    root_existed = root.exists()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    # A custom --database path may deliberately live in an existing shared
    # parent such as /tmp or a project directory. Never change that parent's
    # mode here; AppPaths.ensure hardens only data roots it owns.
    if not root_existed:
        os.chmod(root, 0o700)
    path = root / INSTANCE_FILE_NAME
    try:
        path.lstat()
    except FileNotFoundError:
        temporary = root / (
            f".{INSTANCE_FILE_NAME}.{os.getpid()}.{secrets.token_hex(8)}.tmp"
        )
        descriptor = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
            0o600,
        )
        value = secrets.token_hex(16)
        try:
            os.write(descriptor, f"{value}\n".encode("ascii"))
            os.fsync(descriptor)
        finally:
            os.close(descriptor)
        try:
            # A hard-link publishes the fully fsynced inode without replacing
            # an identity won by a concurrent launcher. A crash can leave only
            # an unreferenced private temp, never a partial final identity.
            portable.atomik_hardlink(temporary, path)
        except FileExistsError:
            pass
        except OSError as exc:
            raise InstanceIdentityError(
                f"Veri kökü kimliği atomik yayımlanamadı: {path}"
            ) from exc
        finally:
            temporary.unlink(missing_ok=True)
        portable.dizin_fsync(root)
    except OSError as exc:
        raise InstanceIdentityError(
            f"Veri kökü kimliği güvenli denetlenemedi: {path}"
        ) from exc

    try:
        metadata = path.lstat()
        if not portable.kullanici_sahibi_mi(metadata):
            raise InstanceIdentityError(
                "Veri kökü kimliği kullanıcıya ait normal bir dosya değil"
            )
        portable.sikilastir_0600(path)
        value = path.read_text(encoding="ascii").strip()
    except (OSError, UnicodeError) as exc:
        raise InstanceIdentityError(f"Veri kökü kimliği okunamadı: {path}") from exc
    if not _INSTANCE_PATTERN.fullmatch(value):
        raise InstanceIdentityError("Veri kökü kimliğinin biçimi geçersiz")
    return value
