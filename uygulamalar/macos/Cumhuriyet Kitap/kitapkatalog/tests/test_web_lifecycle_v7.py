"""v0.7 web güvenliği, oturum ve uzun yaşayan sunucu regresyonları."""

from __future__ import annotations

import json
import os
import signal
import socket
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

fastapi = pytest.importorskip("fastapi")

from fastapi.testclient import TestClient  # noqa: E402

from kitapkatalog import __version__  # noqa: E402
from kitapkatalog.application import open_application  # noqa: E402
from kitapkatalog.config import AppPaths  # noqa: E402
from kitapkatalog.database import SCHEMA_VERSION  # noqa: E402
from kitapkatalog.webapp import instance as web_instance  # noqa: E402
from kitapkatalog.webapp import server  # noqa: E402
from kitapkatalog.webapp.app import create_app  # noqa: E402
from kitapkatalog.webapp.instance import instance_id_for_root  # noqa: E402


def _paths(tmp_path: Path) -> AppPaths:
    return AppPaths(
        root=tmp_path,
        database=tmp_path / "catalog.sqlite3",
        assets=tmp_path / "assets",
        derivatives=tmp_path / "derivatives",
        ocr_raw=tmp_path / "ocr-raw",
        models=tmp_path / "models",
        exports=tmp_path / "exports",
        logs=tmp_path / "logs",
    )


def _write_session(path: Path, *, version: str = __version__) -> dict:
    payload = server._session_payload(
        8080, "gizli-token", "nonce-1", instance_id_for_root(path.parent)
    )
    payload["version"] = version
    server._atomic_write_session(path, payload)
    return payload


def test_session_json_is_atomic_private_and_complete(tmp_path: Path) -> None:
    session_file = tmp_path / "web_session.json"
    session_file.write_text("eski", encoding="utf-8")
    session_file.chmod(0o644)

    instance_id = instance_id_for_root(tmp_path)
    payload = server._session_payload(8084, "secret", "nonce", instance_id)
    server._atomic_write_session(session_file, payload)

    assert stat.S_IMODE(session_file.stat().st_mode) == 0o600
    assert json.loads(session_file.read_text(encoding="utf-8")) == payload
    assert payload["version"] == __version__
    assert payload["pid"] == os.getpid()
    assert payload["instance_id"] == instance_id
    assert payload["started_at"].endswith("+00:00")
    assert list(tmp_path.glob(".web_session.json.*.tmp")) == []


def test_invalid_utf8_private_session_fails_closed_without_traceback(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    session_file = tmp_path / "web_session.json"
    session_file.write_bytes(b"\xff\xfe\x00")
    session_file.chmod(0o600)

    assert server._check_session_command(session_file) == 20
    captured = capsys.readouterr()
    assert "Oturum dosyası okunamadı" in captured.err
    assert "Traceback" not in captured.err


def test_data_root_identity_is_private_stable_and_race_safe(tmp_path: Path) -> None:
    root = tmp_path / "race-root"
    barrier = threading.Barrier(4)
    values: list[str] = []

    def load() -> None:
        barrier.wait()
        values.append(instance_id_for_root(root))

    threads = [threading.Thread(target=load) for _ in range(4)]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()

    assert len(values) == 4 and len(set(values)) == 1
    identity_file = root / web_instance.INSTANCE_FILE_NAME
    assert stat.S_IMODE(identity_file.stat().st_mode) == 0o600
    assert list(root.glob(f".{web_instance.INSTANCE_FILE_NAME}.*.tmp")) == []


def test_data_root_identity_never_publishes_partial_final(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    root = tmp_path / "fault-root"

    def fail_link(*_args, **_kwargs) -> None:
        raise OSError("fault injection")

    monkeypatch.setattr(web_instance.os, "link", fail_link)
    with pytest.raises(web_instance.InstanceIdentityError, match="atomik"):
        instance_id_for_root(root)
    assert not (root / web_instance.INSTANCE_FILE_NAME).exists()
    assert list(root.glob(f".{web_instance.INSTANCE_FILE_NAME}.*.tmp")) == []


def test_data_root_identity_does_not_chmod_existing_shared_parent(tmp_path: Path) -> None:
    shared_parent = tmp_path / "shared-parent"
    shared_parent.mkdir(mode=0o755)

    instance_id_for_root(shared_parent)

    assert stat.S_IMODE(shared_parent.stat().st_mode) == 0o755
    assert stat.S_IMODE((shared_parent / web_instance.INSTANCE_FILE_NAME).stat().st_mode) == 0o600


def test_matching_session_is_reused_without_printing_token(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch, capsys: pytest.CaptureFixture[str]
) -> None:
    session_file = tmp_path / "web_session.json"
    _write_session(session_file)
    instance_id = instance_id_for_root(tmp_path)
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: {
            "app": "kitapkatalog",
            "nonce": "nonce-1",
            "version": __version__,
            "instance_id": instance_id,
        },
    )
    opened: list[str] = []
    monkeypatch.setattr(server.webbrowser, "open", lambda url, new=0: opened.append(url) or True)

    assert server.reconcile_existing_session(session_file) == "reused"
    assert opened == ["http://127.0.0.1:8080/?token=gizli-token"]
    assert "gizli-token" not in capsys.readouterr().out
    assert session_file.is_file()


def test_stale_session_is_removed_when_port_is_free(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    _write_session(session_file, version="0.1.0")
    monkeypatch.setattr(server, "_fetch_health", lambda port: None)
    monkeypatch.setattr(server, "_port_listening", lambda port: False)

    assert server.reconcile_existing_session(session_file) == "start"
    assert not session_file.exists()


def test_missing_session_retires_one_verified_orphan_server(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    instance_id = instance_id_for_root(tmp_path)
    monkeypatch.setattr(server, "_port_listening", lambda port: port == 8083)
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: (
            {
                "app": "kitapkatalog",
                "version": __version__,
                "instance_id": instance_id,
            }
            if port == 8083
            else None
        ),
    )
    monkeypatch.setattr(server, "_listener_pids", lambda port: {4321})
    monkeypatch.setattr(server, "_is_expected_server_process", lambda pid: pid == 4321)
    terminated: list[tuple[int, int]] = []
    monkeypatch.setattr(
        server,
        "_terminate_listener",
        lambda pid, port: terminated.append((pid, port)),
    )

    assert server.reconcile_existing_session(session_file) == "start"
    assert terminated == [(4321, 8083)]


def test_missing_session_fails_closed_for_ambiguous_orphan(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    instance_id = instance_id_for_root(tmp_path)
    monkeypatch.setattr(server, "_port_listening", lambda port: port == 8083)
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: {
            "app": "kitapkatalog",
            "version": __version__,
            "instance_id": instance_id,
        },
    )
    monkeypatch.setattr(server, "_listener_pids", lambda port: {4321, 4322})
    monkeypatch.setattr(server, "_is_expected_server_process", lambda pid: True)

    with pytest.raises(server.LifecycleError, match="ikinci sunucu açılmadı"):
        server.reconcile_existing_session(session_file)


def test_missing_session_ignores_verified_server_from_other_data_root(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    own_id = instance_id_for_root(tmp_path)
    other_id = "0" * 32 if own_id != "0" * 32 else "1" * 32
    monkeypatch.setattr(server, "_port_listening", lambda port: port == 8083)
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: {
            "app": "kitapkatalog",
            "version": __version__,
            "instance_id": other_id,
        },
    )
    monkeypatch.setattr(
        server,
        "_listener_pids",
        lambda _port: pytest.fail("Başka veri kökü süreci sorgulanmamalı"),
    )

    assert server.reconcile_existing_session(session_file) == "start"


def test_server_instance_lock_is_private_and_exclusive(tmp_path: Path) -> None:
    path = tmp_path / "private" / "web_server.lock"
    first = server.ServerInstanceLock(path)
    second = server.ServerInstanceLock(path)
    first.acquire()
    try:
        assert stat.S_IMODE(path.parent.stat().st_mode) == 0o700
        assert stat.S_IMODE(path.stat().st_mode) == 0o600
        with pytest.raises(server.LifecycleError, match="ikinci sunucu açılmadı"):
            second.acquire()
    finally:
        second.release()
        first.release()

    # Advisory lock file may remain, but the ownership lock is reusable.
    with server.ServerInstanceLock(path):
        pass


def test_version_mismatch_retires_only_verified_server(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    payload = _write_session(session_file, version="0.6.0")
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: {
            "app": "kitapkatalog",
            "nonce": "nonce-1",
            "version": "0.6.0",
        },
    )
    monkeypatch.setattr(server, "_port_listening", lambda port: True)
    monkeypatch.setattr(
        server, "_verified_listener_pid", lambda port, declared: int(payload["pid"])
    )
    terminated: list[tuple[int, int]] = []
    monkeypatch.setattr(
        server,
        "_terminate_listener",
        lambda pid, port: terminated.append((pid, port)),
    )

    assert server.reconcile_existing_session(session_file, expected_version="0.7.0") == "start"
    assert terminated == [(int(payload["pid"]), 8080)]
    assert not session_file.exists()


def test_unverified_listener_blocks_second_server(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    session_file = tmp_path / "web_session.json"
    _write_session(session_file, version="0.6.0")
    monkeypatch.setattr(
        server,
        "_fetch_health",
        lambda port: {"app": "baska", "nonce": "x", "version": "1"},
    )
    monkeypatch.setattr(server, "_port_listening", lambda port: True)

    def unsafe(port: int, declared: int | None) -> int:
        raise server.LifecycleError("sahiplik kanıtlanamadı")

    monkeypatch.setattr(server, "_verified_listener_pid", unsafe)

    with pytest.raises(server.LifecycleError, match="İkinci sunucu başlatılmadı"):
        server.reconcile_existing_session(session_file, expected_version="0.7.0")
    assert session_file.is_file()


def test_backup_scheduler_repeats_and_stops_cleanly() -> None:
    stop = threading.Event()
    calls: list[int] = []

    def backup() -> None:
        calls.append(len(calls) + 1)
        if len(calls) == 2:
            stop.set()

    server._backup_scheduler(stop, backup, initial_delay=0, check_interval=0.001)
    assert calls == [1, 2]

    already_stopped = threading.Event()
    already_stopped.set()
    server._backup_scheduler(
        already_stopped,
        lambda: calls.append(3),
        initial_delay=0,
        check_interval=0.001,
    )
    assert calls == [1, 2]


def test_stuck_backup_thread_has_a_bounded_shutdown_wait() -> None:
    release = threading.Event()
    stop = threading.Event()
    thread = threading.Thread(target=release.wait, daemon=True)
    thread.start()

    started = time.monotonic()
    try:
        assert server._stop_backup_thread(stop, thread, timeout=0.02) is False
        assert stop.is_set()
        assert time.monotonic() - started < 0.5
    finally:
        release.set()
        thread.join(timeout=1)


def test_health_reports_runtime_version_and_database_schema(tmp_path: Path) -> None:
    context = open_application(_paths(tmp_path), enforce_offline=False)
    app = create_app(context, token="test-token")
    with TestClient(app, base_url="http://127.0.0.1:8080") as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["version"] == __version__
    assert response.json()["schema_version"] == SCHEMA_VERSION


def test_real_sigterm_removes_session_before_uvicorn_reraises_signal(tmp_path: Path) -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = int(probe.getsockname()[1])
    environment = os.environ.copy()
    environment.update(
        {
            "KITAPKATALOG_DATA_DIR": str(tmp_path),
            "KITAPKATALOG_MODEL_DIR": str(tmp_path / "models"),
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }
    )
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "kitapkatalog.webapp.server",
            "--port",
            str(port),
            "--no-browser",
        ],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    session_file = tmp_path / "web_session.json"
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            health = server._fetch_health(port, timeout=0.25)
            if session_file.is_file() and health and health.get("version") == __version__:
                break
            if process.poll() is not None:
                pytest.fail(f"Sunucu hazır olmadan kapandı: {process.returncode}")
            time.sleep(0.05)
        else:
            pytest.fail("Gerçek sunucu zamanında hazır olmadı")

        os.kill(process.pid, signal.SIGTERM)
        assert process.wait(timeout=15) in {-signal.SIGTERM, 0}
        assert not session_file.exists()
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def test_real_missing_session_checker_retires_orphan_without_second_listener(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    port = next(
        (candidate for candidate in server.PORT_RANGE if server._port_available(candidate)), None
    )
    if port is None:
        pytest.skip("KitapKatalog port aralığında boş port yok")
    environment = os.environ.copy()
    environment.update(
        {
            "KITAPKATALOG_DATA_DIR": str(tmp_path),
            "KITAPKATALOG_MODEL_DIR": str(tmp_path / "models"),
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }
    )
    process = subprocess.Popen(
        [
            sys.executable,
            "-m",
            "kitapkatalog.webapp.server",
            "--port",
            str(port),
            "--no-browser",
        ],
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    session_file = tmp_path / "web_session.json"
    try:
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            health = server._fetch_health(port, timeout=0.25)
            if session_file.is_file() and health and health.get("version") == __version__:
                break
            if process.poll() is not None:
                pytest.fail(f"Yetim testi sunucusu hazır olmadan kapandı: {process.returncode}")
            time.sleep(0.05)
        else:
            pytest.fail("Yetim testi sunucusu zamanında hazır olmadı")

        session_file.unlink()
        # Limit discovery to this test-owned listener. A user's real running
        # KitapKatalog on another reserved port must not make the test
        # nondeterministic or be terminated by the test process.
        monkeypatch.setattr(server, "PORT_RANGE", range(port, port + 1))
        assert server.reconcile_existing_session(session_file, open_browser=False) == "start"
        assert process.wait(timeout=15) in {-signal.SIGTERM, 0}
        assert not server._port_listening(port)
        assert not session_file.exists()
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def test_origin_must_match_scheme_host_and_port(tmp_path: Path) -> None:
    context = open_application(_paths(tmp_path), enforce_offline=False)
    app = create_app(context, token="test-token")
    with TestClient(app, base_url="http://127.0.0.1:8080") as client:
        client.get("/?token=test-token", follow_redirects=False)
        accepted = client.get("/api/stats", headers={"Origin": "http://127.0.0.1:8080"})
        other_port = client.get("/api/stats", headers={"Origin": "http://127.0.0.1:9999"})
        other_scheme = client.get("/api/stats", headers={"Origin": "https://127.0.0.1:8080"})
    assert accepted.status_code == 200
    assert other_port.status_code == 403
    assert other_scheme.status_code == 403
