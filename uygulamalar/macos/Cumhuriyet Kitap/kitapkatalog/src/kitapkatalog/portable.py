"""POSIX'e özgü güvenlik sıkılaştırmalarının platform-taşınabilir karşılıkları.

macOS/Linux'ta davranış birebir korunur (uid sahiplik kontrolü, 0600 izinleri,
dizin fsync'i, follow_symlinks korumalı hard-link). Windows'ta bu API'lerin
karşılığı olmayanlar güvenli biçimde gevşetilir: NTFS ACL'leri kullanıcı
profilinde zaten kullanıcıya özeldir; POSIX izin bitleri anlamlı değildir.
"""
from __future__ import annotations

import os
import stat as stat_mod
from pathlib import Path

POSIX = os.name != "nt"


def kullanici_sahibi_mi(metadata: os.stat_result) -> bool:
    """Dosya normal ve çalışan kullanıcıya mı ait? (Windows'ta yalnız normal dosya kontrolü)"""
    if not stat_mod.S_ISREG(metadata.st_mode):
        return False
    if not POSIX:
        return True
    return metadata.st_uid == os.getuid()


def sikilastir_0600(path: Path | str) -> None:
    """POSIX'te 0600'e çeker; Windows'ta no-op (NTFS profil ACL'i yeterli)."""
    if POSIX:
        os.chmod(path, 0o600, follow_symlinks=False)


def izin_0600_mu(metadata: os.stat_result) -> bool:
    """POSIX'te 0600 doğrulaması; Windows'ta yalnız normal-dosya kontrolü."""
    if not stat_mod.S_ISREG(metadata.st_mode):
        return False
    if not POSIX:
        return True
    return stat_mod.S_IMODE(metadata.st_mode) == 0o600


def dizin_fsync(root: Path | str) -> None:
    """Dizin girdisini kalıcılaştırır; Windows'ta dizin fd'si açılamaz, no-op."""
    if not POSIX:
        return
    fd = os.open(root, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomik_hardlink(temporary: Path | str, path: Path | str) -> None:
    """Hard-link ile atomik yayım; Windows os.link follow_symlinks kabul etmez."""
    if POSIX:
        os.link(temporary, path, follow_symlinks=False)
    else:
        os.link(temporary, path)


def surec_grubunu_sonlandir(proc, *, zorla: bool = False) -> None:
    """POSIX'te süreç grubunu, Windows'ta yalnız süreci sonlandırır."""
    if POSIX and hasattr(os, "killpg"):
        import signal

        sig = signal.SIGKILL if zorla else signal.SIGTERM
        try:
            os.killpg(os.getpgid(proc.pid), sig)
            return
        except (ProcessLookupError, PermissionError, OSError):
            return
    try:
        if zorla:
            proc.kill()
        else:
            proc.terminate()
    except OSError:
        pass
