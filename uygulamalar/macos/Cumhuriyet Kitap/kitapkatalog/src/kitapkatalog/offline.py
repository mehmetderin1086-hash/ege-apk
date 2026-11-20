"""Process-wide network guard for a local-only application.

Environment flags are useful hints to model libraries but are not a security
boundary.  The guard below rejects DNS resolution and TCP connections to every
non-loopback address.  Unix-domain sockets and localhost sidecars remain
available.  It is installed explicitly by the CLI/GUI entry points before any
OCR implementation is imported.
"""

from __future__ import annotations

import ipaddress
import os
import socket
import threading
from collections.abc import Callable
from typing import Any


class OfflineNetworkError(OSError):
    """Raised when code attempts an external connection."""


_lock = threading.Lock()
_installed = False
_original_connect: Callable[..., Any] | None = None
_original_connect_ex: Callable[..., Any] | None = None
_original_create_connection: Callable[..., Any] | None = None
_original_getaddrinfo: Callable[..., Any] | None = None


def _host_is_loopback(host: object) -> bool:
    if isinstance(host, bytes):
        try:
            host = host.decode("ascii")
        except UnicodeDecodeError:
            return False
    if not isinstance(host, str):
        return False
    normalized = host.strip().strip("[]").casefold()
    if normalized in {"localhost", "localhost.localdomain"}:
        return True
    try:
        return ipaddress.ip_address(normalized).is_loopback
    except ValueError:
        return False


def _address_allowed(address: object) -> bool:
    # Unix-domain sockets use a filesystem string, not a (host, port) tuple.
    if isinstance(address, (str, bytes)):
        return True
    return bool(isinstance(address, tuple) and address and _host_is_loopback(address[0]))


def _blocked(address: object) -> OfflineNetworkError:
    return OfflineNetworkError(
        f"KitapKatalog çevrimdışı kipte dış ağ bağlantısını engelledi: {address!r}"
    )


def install_network_guard() -> None:
    """Idempotently deny non-loopback DNS and socket connections."""

    global _installed
    global _original_connect, _original_connect_ex
    global _original_create_connection, _original_getaddrinfo
    with _lock:
        if _installed:
            return
        if _allowlist_installed:
            raise RuntimeError(
                "Allowlist kilidi kuruluyken tam çevrimdışı kilit kurulamaz; "
                "bu süreç çevrimiçi öneri sürecidir."
            )
        _original_connect = socket.socket.connect
        _original_connect_ex = socket.socket.connect_ex
        _original_create_connection = socket.create_connection
        _original_getaddrinfo = socket.getaddrinfo

        def guarded_connect(instance: socket.socket, address: object) -> Any:
            if not _address_allowed(address):
                raise _blocked(address)
            assert _original_connect is not None
            return _original_connect(instance, address)

        def guarded_connect_ex(instance: socket.socket, address: object) -> int:
            if not _address_allowed(address):
                # connect_ex convention: return an errno instead of raising.
                return 101
            assert _original_connect_ex is not None
            return int(_original_connect_ex(instance, address))

        def guarded_create_connection(
            address: tuple[str, int],
            timeout: float | object = socket._GLOBAL_DEFAULT_TIMEOUT,
            source_address: tuple[str, int] | None = None,
            *,
            all_errors: bool = False,
        ) -> socket.socket:
            if not _address_allowed(address):
                raise _blocked(address)
            assert _original_create_connection is not None
            return _original_create_connection(
                address,
                timeout,
                source_address,
                all_errors=all_errors,
            )

        def guarded_getaddrinfo(
            host: str | bytes | None,
            port: str | int | None,
            family: int = 0,
            type: int = 0,
            proto: int = 0,
            flags: int = 0,
        ) -> list[tuple[Any, ...]]:
            if host is not None and not _host_is_loopback(host):
                raise _blocked((host, port))
            assert _original_getaddrinfo is not None
            return _original_getaddrinfo(host, port, family, type, proto, flags)

        socket.socket.connect = guarded_connect
        socket.socket.connect_ex = guarded_connect_ex
        socket.create_connection = guarded_create_connection
        socket.getaddrinfo = guarded_getaddrinfo
        os.environ.update(
            {
                "HF_HUB_OFFLINE": "1",
                "TRANSFORMERS_OFFLINE": "1",
                "HF_DATASETS_OFFLINE": "1",
                "DO_NOT_TRACK": "1",
                "KITAPKATALOG_NETWORK_DISABLED": "1",
            }
        )
        _installed = True


def network_guard_installed() -> bool:
    return _installed


# ---------------------------------------------------------------------------
# Allowlist guard — YALNIZ ayrı "online-oneri" süreci için.
#
# Ana uygulama (web/GUI/CLI işleme) her zaman install_network_guard() kullanır;
# bu ikisi aynı süreçte asla birlikte kurulamaz (RuntimeError). Allowlist kipi
# loopback'e ek olarak sadece listedeki ana bilgisayarlara, yalnız 80/443
# portlarından çıkışa izin verir. DNS çözümü sırasında dönen IP'ler kaydedilir
# ki çözüm-sonrası doğrudan IP bağlantıları da doğrulanabilsin.
# ---------------------------------------------------------------------------

_ALLOWED_PORTS = frozenset({80, 443})

_allowlist_installed = False
_allowed_hosts: frozenset[str] = frozenset()
_allowed_ips: set[str] = set()
_allow_original_connect: Callable[..., Any] | None = None
_allow_original_connect_ex: Callable[..., Any] | None = None
_allow_original_create_connection: Callable[..., Any] | None = None
_allow_original_getaddrinfo: Callable[..., Any] | None = None


def _normalized_host(host: object) -> str | None:
    if isinstance(host, bytes):
        try:
            host = host.decode("ascii")
        except UnicodeDecodeError:
            return None
    if not isinstance(host, str):
        return None
    return host.strip().strip("[]").casefold()


def _allowlist_address_allowed(address: object) -> bool:
    if isinstance(address, (str, bytes)):
        return True  # Unix-domain soketleri (yerel sidecar'lar).
    if not (isinstance(address, tuple) and address):
        return False
    if _host_is_loopback(address[0]):
        return True
    host = _normalized_host(address[0])
    if host is None:
        return False
    port = address[1] if len(address) > 1 else None
    if port not in _ALLOWED_PORTS:
        return False
    return host in _allowed_hosts or host in _allowed_ips


def install_allowlist_guard(hosts: frozenset[str] | set[str]) -> None:
    """Yalnız ``hosts`` + loopback'e (80/443) izin veren süreç-geneli kilit.

    Ana giriş noktalarında ASLA çağrılmaz; sadece ayrı çevrimiçi öneri komutu
    kurar. Tam çevrimdışı kilitle aynı süreçte birleştirilemez.
    """

    global _allowlist_installed, _allowed_hosts
    global _allow_original_connect, _allow_original_connect_ex
    global _allow_original_create_connection, _allow_original_getaddrinfo
    normalized = frozenset(
        h for h in (_normalized_host(host) for host in hosts) if h
    )
    if not normalized:
        raise ValueError("Allowlist guard için en az bir ana bilgisayar gerekir")
    with _lock:
        if _installed:
            raise RuntimeError(
                "Çevrimdışı ağ kilidi kuruluyken allowlist kilidi kurulamaz; "
                "çevrimiçi öneri ayrı bir süreçte çalışmalıdır."
            )
        if _allowlist_installed:
            if normalized == _allowed_hosts:
                return
            raise RuntimeError("Allowlist kilidi farklı bir listeyle zaten kurulu")
        _allowed_hosts = normalized
        _allow_original_connect = socket.socket.connect
        _allow_original_connect_ex = socket.socket.connect_ex
        _allow_original_create_connection = socket.create_connection
        _allow_original_getaddrinfo = socket.getaddrinfo

        def guarded_connect(instance: socket.socket, address: object) -> Any:
            if not _allowlist_address_allowed(address):
                raise _blocked(address)
            assert _allow_original_connect is not None
            return _allow_original_connect(instance, address)

        def guarded_connect_ex(instance: socket.socket, address: object) -> int:
            if not _allowlist_address_allowed(address):
                return 101
            assert _allow_original_connect_ex is not None
            return int(_allow_original_connect_ex(instance, address))

        def guarded_create_connection(
            address: tuple[str, int],
            timeout: float | object = socket._GLOBAL_DEFAULT_TIMEOUT,
            source_address: tuple[str, int] | None = None,
            *,
            all_errors: bool = False,
        ) -> socket.socket:
            if not _allowlist_address_allowed(address):
                raise _blocked(address)
            assert _allow_original_create_connection is not None
            return _allow_original_create_connection(
                address,
                timeout,
                source_address,
                all_errors=all_errors,
            )

        def guarded_getaddrinfo(
            host: str | bytes | None,
            port: str | int | None,
            family: int = 0,
            type: int = 0,
            proto: int = 0,
            flags: int = 0,
        ) -> list[tuple[Any, ...]]:
            normalized_host = _normalized_host(host)
            if (
                host is not None
                and not _host_is_loopback(host)
                and normalized_host not in _allowed_hosts
            ):
                raise _blocked((host, port))
            assert _allow_original_getaddrinfo is not None
            results = _allow_original_getaddrinfo(host, port, family, type, proto, flags)
            if normalized_host in _allowed_hosts:
                # Çözülen IP'leri kaydet: urllib çözüm sonrası IP ile bağlanır.
                for _family, _type, _proto, _canon, sockaddr in results:
                    if isinstance(sockaddr, tuple) and sockaddr:
                        ip = _normalized_host(sockaddr[0])
                        if ip:
                            _allowed_ips.add(ip)
            return results

        socket.socket.connect = guarded_connect
        socket.socket.connect_ex = guarded_connect_ex
        socket.create_connection = guarded_create_connection
        socket.getaddrinfo = guarded_getaddrinfo
        os.environ["DO_NOT_TRACK"] = "1"
        _allowlist_installed = True


def allowlist_guard_installed() -> bool:
    return _allowlist_installed


def _uninstall_allowlist_for_tests() -> None:
    """Restore socket functions; intentionally private and only used by tests."""

    global _allowlist_installed, _allowed_hosts
    with _lock:
        if not _allowlist_installed:
            return
        assert _allow_original_connect is not None
        assert _allow_original_connect_ex is not None
        assert _allow_original_create_connection is not None
        assert _allow_original_getaddrinfo is not None
        socket.socket.connect = _allow_original_connect
        socket.socket.connect_ex = _allow_original_connect_ex
        socket.create_connection = _allow_original_create_connection
        socket.getaddrinfo = _allow_original_getaddrinfo
        _allowed_hosts = frozenset()
        _allowed_ips.clear()
        _allowlist_installed = False


def _uninstall_for_tests() -> None:
    """Restore socket functions; intentionally private and only used by tests."""

    global _installed
    with _lock:
        if not _installed:
            return
        assert _original_connect is not None
        assert _original_connect_ex is not None
        assert _original_create_connection is not None
        assert _original_getaddrinfo is not None
        socket.socket.connect = _original_connect
        socket.socket.connect_ex = _original_connect_ex
        socket.create_connection = _original_create_connection
        socket.getaddrinfo = _original_getaddrinfo
        _installed = False
