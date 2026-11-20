from __future__ import annotations

import socket

import pytest

from kitapkatalog.offline import (
    OfflineNetworkError,
    _uninstall_for_tests,
    install_network_guard,
    network_guard_installed,
)


@pytest.fixture(autouse=True)
def restore_socket() -> None:
    _uninstall_for_tests()
    yield
    _uninstall_for_tests()


def test_external_dns_is_blocked_before_resolution() -> None:
    install_network_guard()
    with pytest.raises(OfflineNetworkError, match="engelledi"):
        socket.getaddrinfo("example.com", 443)


def test_external_literal_connection_is_blocked() -> None:
    install_network_guard()
    with socket.socket() as connection, pytest.raises(OfflineNetworkError):
        connection.connect(("1.1.1.1", 443))


def test_loopback_resolution_remains_available() -> None:
    install_network_guard()
    addresses = socket.getaddrinfo("localhost", 8765)
    assert addresses
    assert network_guard_installed()


def test_install_is_idempotent() -> None:
    install_network_guard()
    installed_connect = socket.socket.connect
    install_network_guard()
    assert socket.socket.connect is installed_connect


class TestAllowlistGuard:
    """Allowlist kilidi yalnız ayrı çevrimiçi öneri sürecinde kurulur."""

    @pytest.fixture(autouse=True)
    def restore_allowlist(self) -> None:
        from kitapkatalog.offline import _uninstall_allowlist_for_tests

        _uninstall_allowlist_for_tests()
        yield
        _uninstall_allowlist_for_tests()

    def test_unlisted_host_resolution_is_blocked(self) -> None:
        from kitapkatalog.offline import install_allowlist_guard

        install_allowlist_guard({"izinli.example"})
        with pytest.raises(OfflineNetworkError, match="engelledi"):
            socket.getaddrinfo("baska.example", 443)

    def test_unlisted_literal_connection_is_blocked(self) -> None:
        from kitapkatalog.offline import install_allowlist_guard

        install_allowlist_guard({"izinli.example"})
        with socket.socket() as connection, pytest.raises(OfflineNetworkError):
            connection.connect(("1.1.1.1", 443))

    def test_listed_host_resolves_and_records_addresses(self, monkeypatch) -> None:
        from kitapkatalog import offline
        from kitapkatalog.offline import install_allowlist_guard

        def fake_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
            return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("93.184.216.34", 443))]

        monkeypatch.setattr(socket, "getaddrinfo", fake_getaddrinfo)
        install_allowlist_guard({"izinli.example"})
        results = socket.getaddrinfo("izinli.example", 443)
        assert results[0][4][0] == "93.184.216.34"
        # Çözülen IP artık 443 portundan bağlantıya açık, başka port kapalı.
        assert offline._allowlist_address_allowed(("93.184.216.34", 443))
        assert not offline._allowlist_address_allowed(("93.184.216.34", 4444))

    def test_loopback_stays_available_and_ports_are_restricted(self) -> None:
        from kitapkatalog import offline
        from kitapkatalog.offline import install_allowlist_guard

        install_allowlist_guard({"izinli.example"})
        assert socket.getaddrinfo("localhost", 8765)
        assert offline._allowlist_address_allowed(("127.0.0.1", 12345))
        assert not offline._allowlist_address_allowed(("izinli.example", 25))

    def test_mutual_exclusion_with_full_guard(self) -> None:
        from kitapkatalog.offline import allowlist_guard_installed, install_allowlist_guard

        install_network_guard()
        with pytest.raises(RuntimeError, match="ayrı bir süreçte"):
            install_allowlist_guard({"izinli.example"})
        assert not allowlist_guard_installed()

    def test_full_guard_refuses_over_allowlist(self) -> None:
        from kitapkatalog.offline import install_allowlist_guard

        install_allowlist_guard({"izinli.example"})
        with pytest.raises(RuntimeError, match="çevrimiçi öneri"):
            install_network_guard()

    def test_reinstall_same_hosts_is_idempotent_different_hosts_fails(self) -> None:
        from kitapkatalog.offline import install_allowlist_guard

        install_allowlist_guard({"izinli.example"})
        install_allowlist_guard({"IZINLI.EXAMPLE"})  # casefold aynı liste
        with pytest.raises(RuntimeError, match="zaten kurulu"):
            install_allowlist_guard({"farkli.example"})
