"""Yerel web sunucusunu başlat: port seç, uvicorn'u tek worker koştur.

Port ayrımı: 8080-8090 KitapKatalog web arayüzüne ayrılmıştır (Mac'teki
diğer yerel uygulamalarla çakışmaması için; bkz. proje README). "Port boş
mu" yerine "portta gerçekten KitapKatalog mu var" sorusu `/health`
imzasıyla (`app: kitapkatalog`) yanıtlanır.
"""

from __future__ import annotations

import json
import os
import shlex
import signal
import socket
import stat

from kitapkatalog import portable
import subprocess
import sys
import threading
import time
import urllib.request
import uuid
import webbrowser
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from kitapkatalog import __version__
from kitapkatalog.webapp.instance import InstanceIdentityError, instance_id_for_root

PORT_RANGE = range(8080, 8091)
_REUSE_SESSION = 0
_START_SERVER = 10
_LIFECYCLE_ERROR = 20
_BACKUP_SHUTDOWN_TIMEOUT_SECONDS = 5.0


class LifecycleError(RuntimeError):
    """Başlatıcının güvenli biçimde uzlaştıramadığı eski sunucu durumu."""


class ServerInstanceLock:
    """Process-lifetime singleton lock independent from ``web_session.json``.

    The session file is intentionally removable at clean shutdown and can be
    lost after a crash or an over-eager cleanup tool.  It therefore cannot be
    the sole single-server primitive.  This advisory lock is held from before
    the application opens its database until uvicorn has fully shut down.
    """

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._fd: int | None = None

    def acquire(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(self.path.parent, 0o700)
        descriptor = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o600)
        os.chmod(self.path, 0o600)
        try:
            if os.name == "nt":  # pragma: no cover - Windows release path
                import msvcrt

                os.lseek(descriptor, 0, os.SEEK_SET)
                if os.fstat(descriptor).st_size == 0:
                    os.write(descriptor, b"0")
                    os.lseek(descriptor, 0, os.SEEK_SET)
                msvcrt.locking(descriptor, msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, ImportError) as exc:
            os.close(descriptor)
            raise LifecycleError(
                "Başka bir KitapKatalog web sunucusu çalışıyor; ikinci sunucu açılmadı"
            ) from exc
        self._fd = descriptor

    def release(self) -> None:
        descriptor, self._fd = self._fd, None
        if descriptor is None:
            return
        try:
            if os.name == "nt":  # pragma: no cover - Windows release path
                import msvcrt

                os.lseek(descriptor, 0, os.SEEK_SET)
                msvcrt.locking(descriptor, msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)

    def __enter__(self) -> ServerInstanceLock:
        self.acquire()
        return self

    def __exit__(self, *_: object) -> None:
        self.release()


def _session_payload(
    port: int, token: str, nonce: str, instance_id: str | None = None
) -> dict[str, Any]:
    payload = {
        "port": port,
        "token": token,
        "nonce": nonce,
        "version": __version__,
        "pid": os.getpid(),
        "started_at": datetime.now(UTC).isoformat(timespec="seconds"),
    }
    if instance_id is not None:
        payload["instance_id"] = instance_id
    return payload


def _atomic_write_session(path: Path, payload: dict[str, Any]) -> None:
    """Oturum JSON'unu aynı dizinde atomik olarak ve baştan 0600 yaz."""

    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        os.chmod(path, 0o600)
        directory = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def _read_session(path: Path) -> dict[str, Any]:
    try:
        metadata = path.lstat()
    except FileNotFoundError:
        return {}
    if not portable.kullanici_sahibi_mi(metadata):
        raise LifecycleError("Oturum dosyası güvenli bir kullanıcı dosyası değil")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise LifecycleError(f"Oturum dosyası okunamadı: {exc}") from exc
    if not isinstance(payload, dict):
        raise LifecycleError("Oturum dosyasının biçimi geçersiz")
    return payload


def _unlink_owned_session(path: Path, *, nonce: str | None = None, pid: int | None = None) -> None:
    """Yalnız hâlâ aynı sürece aitse oturum dosyasını kaldır."""

    try:
        current = _read_session(path)
    except LifecycleError:
        return
    if not current:
        return
    if nonce is not None and current.get("nonce") != nonce:
        return
    if pid is not None and current.get("pid") != pid:
        return
    path.unlink(missing_ok=True)


def _fetch_health(port: int, *, timeout: float = 1.0) -> dict[str, Any] | None:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=timeout) as reply:
            payload = json.load(reply)
    except (OSError, ValueError, json.JSONDecodeError):
        return None
    return payload if isinstance(payload, dict) else None


def _port_listening(port: int) -> bool:
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.25):
            return True
    except OSError:
        return False


def _listener_pids(port: int) -> set[int]:
    try:
        result = subprocess.run(
            ["lsof", "-nP", "-iTCP:" + str(port), "-sTCP:LISTEN", "-t"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise LifecycleError("Dinleyici süreç sahipliği lsof ile doğrulanamadı") from exc
    if result.returncode not in (0, 1):
        raise LifecycleError("Dinleyici süreç sahipliği lsof ile doğrulanamadı")
    try:
        return {int(value) for value in result.stdout.split()}
    except ValueError as exc:
        raise LifecycleError("Dinleyici süreç kimliği geçersiz") from exc


def _process_identity(pid: int) -> tuple[int, list[str]] | None:
    try:
        uid_result = subprocess.run(
            ["ps", "-o", "uid=", "-p", str(pid)],
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
        command_result = subprocess.run(
            ["ps", "-o", "command=", "-p", str(pid)],
            check=True,
            capture_output=True,
            text=True,
            timeout=2,
        )
        uid = int(uid_result.stdout.strip())
        command = shlex.split(command_result.stdout.strip())
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    return uid, command


def _is_expected_server_process(pid: int) -> bool:
    identity = _process_identity(pid)
    if identity is None or not portable.POSIX or identity[0] != os.getuid():
        return False
    command = identity[1]
    return any(
        command[index] == "-m" and command[index + 1] == "kitapkatalog.webapp.server"
        for index in range(len(command) - 1)
    )


def _process_running(pid: int) -> bool:
    try:
        result = subprocess.run(
            ["ps", "-o", "stat=", "-p", str(pid)],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        # Süreç var/yok durumu kanıtlanamıyorsa güvenli tarafta kalıp bekle.
        return True
    status = result.stdout.strip()
    return result.returncode == 0 and bool(status) and not status.startswith("Z")


def _verified_listener_pid(port: int, declared_pid: int | None) -> int:
    listeners = _listener_pids(port)
    if len(listeners) != 1:
        raise LifecycleError(f"{port} portundaki dinleyici tek bir süreç olarak doğrulanamadı")
    pid = next(iter(listeners))
    if declared_pid is not None and declared_pid != pid:
        raise LifecycleError("Oturum dosyası ile dinleyici süreç kimliği eşleşmiyor")
    if not _is_expected_server_process(pid):
        raise LifecycleError(
            "Dinleyici bu kullanıcıya ait beklenen kitapkatalog.webapp.server süreci değil"
        )
    return pid


def _terminate_listener(pid: int, port: int, *, timeout: float = 8.0) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError as exc:
        raise LifecycleError(f"Eski KitapKatalog sunucusu kapatılamadı: {exc}") from exc
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not _port_listening(port) and not _process_running(pid):
            return
        time.sleep(0.1)
    raise LifecycleError(
        "Eski KitapKatalog sunucusu veya dinleyicisi SIGTERM sonrasında zamanında kapanmadı"
    )


def reconcile_existing_session(
    session_file: Path,
    *,
    expected_version: str = __version__,
    open_browser: bool = True,
) -> str:
    """Oturumu yeniden kullan, güvenle emekliye ayır ya da yeni sunucuya izin ver.

    Dönüş değeri ``reused`` veya ``start`` olur. Canlı dinleyicinin sahipliği
    kanıtlanamazsa ``LifecycleError`` yükselir; çağıran ikinci sunucu açmamalıdır.
    """

    try:
        expected_instance_id = instance_id_for_root(session_file.parent)
    except InstanceIdentityError as exc:
        raise LifecycleError(str(exc)) from exc

    if not session_file.exists():
        # A crashed/removed session file must not turn one local catalogue into
        # two concurrent uvicorn processes.  Identify orphan listeners through
        # both the health signature and OS process ownership.  A single proven
        # orphan is retired so a fresh token/session can be issued; anything
        # ambiguous fails closed.
        orphans: list[tuple[int, int]] = []
        for candidate_port in PORT_RANGE:
            if not _port_listening(candidate_port):
                continue
            health = _fetch_health(candidate_port)
            looks_like_app = bool(health and health.get("app") == "kitapkatalog")
            health_instance = health.get("instance_id") if health else None
            # A healthy server belonging to another isolated catalogue is not
            # an orphan of this data root and must never be signalled.
            if (
                looks_like_app
                and health_instance is not None
                and health_instance != expected_instance_id
            ):
                continue
            listeners = _listener_pids(candidate_port)
            expected = {pid for pid in listeners if _is_expected_server_process(pid)}
            if not looks_like_app and not expected:
                continue
            if looks_like_app and health_instance is None:
                raise LifecycleError(
                    f"{candidate_port} portunda veri kökü kimliği olmayan eski bir "
                    "KitapKatalog süreci var; hangi kataloğa ait olduğu kanıtlanamadı"
                )
            if not looks_like_app or len(listeners) != 1 or expected != listeners:
                raise LifecycleError(
                    f"{candidate_port} portunda olası KitapKatalog süreci var ancak "
                    "sahipliği ve sağlık imzası birlikte doğrulanamadı; ikinci sunucu açılmadı"
                )
            orphans.append((candidate_port, next(iter(listeners))))
        if len(orphans) > 1:
            raise LifecycleError(
                "Birden fazla yetim KitapKatalog sunucusu bulundu; otomatik müdahale "
                "edilmedi ve ikinci sunucu açılmadı"
            )
        if orphans:
            orphan_port, orphan_pid = orphans[0]
            _terminate_listener(orphan_pid, orphan_port)
        return "start"
    session = _read_session(session_file)
    try:
        port = int(session["port"])
        nonce = str(session["nonce"])
        token = str(session["token"])
    except (KeyError, TypeError, ValueError) as exc:
        raise LifecycleError(f"Oturum dosyasının zorunlu alanları eksik: {exc}") from exc
    if not 1 <= port <= 65535 or not nonce or not token:
        raise LifecycleError("Oturum dosyasının port/nonce/token alanları geçersiz")
    raw_pid = session.get("pid")
    try:
        declared_pid = int(raw_pid) if raw_pid is not None else None
    except (TypeError, ValueError) as exc:
        raise LifecycleError("Oturum dosyasındaki süreç kimliği geçersiz") from exc
    session_instance = session.get("instance_id")
    if session_instance is not None and session_instance != expected_instance_id:
        raise LifecycleError("Oturum dosyası başka bir veri kökü kimliğine ait")

    health = _fetch_health(port)
    session_version = session.get("version")

    if (
        health
        and health.get("app") == "kitapkatalog"
        and health.get("instance_id") is not None
        and health.get("instance_id") != expected_instance_id
    ):
        raise LifecycleError(
            f"{port} portundaki KitapKatalog başka bir veri köküne ait; sürece dokunulmadı"
        )

    def exact() -> bool:
        return bool(
            health
            and health.get("app") == "kitapkatalog"
            and health.get("nonce") == nonce
            and health.get("version") == expected_version
            and (session_version is None or session_version == expected_version)
            and (session_instance is None or health.get("instance_id") == session_instance)
        )

    # Oturum dosyası bind'dan hemen önce yazılır. Aynı süreç henüz açılıyorsa
    # kısa bir hazır-olma penceresi tanı; iki hızlı tıklama iki sunucu yarışına
    # dönüşmesin.
    if not exact() and declared_pid is not None and _is_expected_server_process(declared_pid):
        for _ in range(20):
            time.sleep(0.1)
            health = _fetch_health(port)
            if exact():
                break

    exact_health = exact()
    if exact_health:
        if open_browser:
            webbrowser.open(f"http://127.0.0.1:{port}/?token={token}", new=2)
        return "reused"

    if not _port_listening(port):
        if declared_pid is not None and _is_expected_server_process(declared_pid):
            raise LifecycleError(
                "Oturum süreci çalışıyor ancak sağlık ucu henüz doğrulanamadı; "
                "ikinci sunucu başlatılmadı"
            )
        _unlink_owned_session(session_file, nonce=nonce, pid=declared_pid)
        return "start"

    try:
        pid = _verified_listener_pid(port, declared_pid)
        _terminate_listener(pid, port)
    except LifecycleError as exc:
        actual_version = health.get("version") if health else "yanıt yok"
        raise LifecycleError(
            f"{port} portunda yeniden kullanılamayan bir dinleyici var "
            f"(beklenen sürüm {expected_version}, bulunan {actual_version}). "
            f"İkinci sunucu başlatılmadı: {exc}"
        ) from exc
    _unlink_owned_session(session_file, nonce=nonce, pid=declared_pid)
    return "start"


def _check_session_command(session_file: Path) -> int:
    try:
        action = reconcile_existing_session(session_file)
    except LifecycleError as exc:
        print(f"KitapKatalog başlatılamadı: {exc}", file=sys.stderr)
        return _LIFECYCLE_ERROR
    return _REUSE_SESSION if action == "reused" else _START_SERVER


def _port_available(port: int, host: str = "127.0.0.1") -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            probe.bind((host, port))
        except OSError:
            return False
    return True


def pick_port() -> int:
    for port in PORT_RANGE:
        if _port_available(port):
            return port
    raise RuntimeError(
        f"{PORT_RANGE.start}-{PORT_RANGE.stop - 1} aralığında boş port yok. "
        "Açık KitapKatalog pencerelerini kapatıp yeniden deneyin."
    )


def _backup_scheduler(
    stop_event: threading.Event,
    run_if_due: Any,
    *,
    initial_delay: float = 3.0,
    check_interval: float = 60.0 * 60.0,
) -> None:
    """Gecikmeli başla, sonra gün değişimini kaçırmayacak aralıkla denetle.

    Asıl günde-bir ve rotasyon politikası ``AutoBackup.run_if_due`` içinde
    kalır. Saatlik uyanma, yerel gün sınırını en geç bir saat içinde görür ve
    uzun yaşayan sunucuda 24 saatten daha seyrek kontrol yapılmasını önler.
    """

    if stop_event.wait(initial_delay):
        return
    while not stop_event.is_set():
        try:
            run_if_due()
        except Exception as error:  # yedek hatası sunucuyu düşürmesin
            print(f"Otomatik yedek alınamadı: {error}", file=sys.stderr)
        if stop_event.wait(check_interval):
            return


def _stop_backup_thread(
    stop_event: threading.Event,
    thread: threading.Thread,
    *,
    timeout: float = _BACKUP_SHUTDOWN_TIMEOUT_SECONDS,
) -> bool:
    """Request shutdown without letting a stuck archive block upgrades forever."""

    stop_event.set()
    if thread.is_alive():
        thread.join(timeout=max(0.0, timeout))
    return not thread.is_alive()


def run_server(
    *,
    port: int | None = None,
    open_browser: bool = True,
) -> int:
    import uvicorn

    from kitapkatalog.config import AppPaths
    from kitapkatalog.webapp.app import create_app

    singleton = ServerInstanceLock(AppPaths.default().root / "web_server.lock")
    singleton.acquire()
    state = None
    try:
        app = create_app()
        selected = port or pick_port()
        state = app.state.web
        url = f"http://127.0.0.1:{selected}/?token={state.token}"

        # Başlatıcı, çalışan sunucuyu yeniden kullanabilsin diye oturum bilgisini
        # yalnız kullanıcı tarafından okunabilir bir dosyaya yaz.
        session_file = state.paths.root / "web_session.json"
        payload = _session_payload(selected, state.token, state.nonce, state.instance_id)
        pid = int(payload["pid"])
        _atomic_write_session(session_file, payload)

        if open_browser:
            # Tarayıcıyı sunucu dinlemeye başladıktan hemen sonra aç.
            threading.Timer(0.8, webbrowser.open, args=(url,)).start()
        # Oturum anahtarı yalnız tarayıcı açılışına ve 0600 oturum dosyasına gider;
        # stdout/stderr günlüklerine token içeren URL yazılmaz.
        print(f"KitapKatalog web arayüzü: http://127.0.0.1:{selected}/")

        # Gerçek yaşam döngülü günlük yedek denetimi: ilk kontrol gecikmeli,
        # sonraki kontroller saatlik; kapanışta Event ile uyandırılıp join edilir.
        from kitapkatalog.backup import AutoBackup

        backup = AutoBackup(state.database, state.settings, state.paths.root)
        backup_stop = threading.Event()
        backup_thread = threading.Thread(
            target=_backup_scheduler,
            args=(backup_stop, backup.run_if_due),
            name="kitapkatalog-auto-backup",
            daemon=True,
        )

        from kitapkatalog.maintenance import DailyMaintenance

        maintenance = DailyMaintenance(state.database, state.settings)
        maintenance_stop = threading.Event()
        maintenance_thread = threading.Thread(
            target=_backup_scheduler,
            args=(maintenance_stop, maintenance.run_if_due),
            name="kitapkatalog-daily-maintenance",
            daemon=True,
        )
        cleanup_lock = threading.Lock()
        cleanup_complete = False

        def cleanup_runtime() -> None:
            nonlocal cleanup_complete
            with cleanup_lock:
                if cleanup_complete:
                    return
                try:
                    stopped = _stop_backup_thread(backup_stop, backup_thread)
                    if not stopped:
                        print(
                            "Otomatik yedek kapanış süresini aştı; "
                            "atomik geçici dosya sonraki açılışta temizlenecek.",
                            file=sys.stderr,
                        )
                    _stop_backup_thread(maintenance_stop, maintenance_thread)
                finally:
                    _unlink_owned_session(session_file, nonce=state.nonce, pid=pid)
                    cleanup_complete = True

        # Uvicorn 0.52 restores the default SIGTERM handler and re-raises the
        # captured signal after its graceful ASGI shutdown. Python outer-finally
        # blocks therefore do not run on that path. Lifespan closes WebState before
        # the re-raise, so bind the session/scheduler cleanup to WebState as well.
        state.add_shutdown_callback(cleanup_runtime)
        backup_thread.start()
        maintenance_thread.start()

        config = uvicorn.Config(
            app,
            host="127.0.0.1",
            port=selected,
            workers=1,
            log_level="warning",
            access_log=False,
        )
        server = uvicorn.Server(config)
        try:
            server.run()
        finally:
            # Normal dönüş/startup hatasında da aynı idempotent yol çalışır.
            # SIGTERM'de ASGI lifespan zaten state.close() üzerinden bunu çağır.
            state.close()
        return 0
    finally:
        if state is not None:
            state.close()
        singleton.release()


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description="KitapKatalog web arayüzü")
    parser.add_argument(
        "--port", type=int, default=None, help="Sabit port (varsayılan: 8080-8090 içinde ilk boş)"
    )
    parser.add_argument("--no-browser", action="store_true", help="Tarayıcıyı otomatik açma")
    parser.add_argument("--check-session", type=Path, default=None, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.check_session is not None:
        return _check_session_command(args.check_session)
    try:
        return run_server(port=args.port, open_browser=not args.no_browser)
    except LifecycleError as exc:
        print(f"KitapKatalog başlatılamadı: {exc}", file=sys.stderr)
        return _LIFECYCLE_ERROR


if __name__ == "__main__":
    raise SystemExit(main())
