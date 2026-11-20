"""macOS launcher sınırları — canlı uygulamaya dokunmadan geçici sunucuyla.

Launcher mutlak macOS araç yolları kullandığı için yalnız ``open`` ve
``osascript`` geçici kayıtçılarla değiştirilir. Port gerçek loopback'te,
rastgele boş bir değerdir; child her test sonunda mutlaka temizlenir.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

import pytest

KOK = Path(__file__).resolve().parents[1]
LAUNCHER = KOK / "macos/launcher.sh"


def _bos_port() -> int:
    with socket.socket() as soket:
        soket.bind(("127.0.0.1", 0))
        return int(soket.getsockname()[1])


def _yaz_calistirilabilir(yol: Path, metin: str) -> None:
    yol.parent.mkdir(parents=True, exist_ok=True)
    yol.write_text(metin, encoding="utf-8")
    yol.chmod(0o755)


def _sahte_proje(tmp_path: Path) -> tuple[Path, Path]:
    proje = tmp_path / "proje"
    giris = proje / ".venv/bin/biyo-cozucu"
    kod = f"""#!{sys.executable}
import json
import os
import signal
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(sys.argv[sys.argv.index("--port") + 1])
mode = os.environ.get("FAKE_MODE", "normal")
with open(os.environ["FAKE_START_FILE"], "a", encoding="utf-8") as dosya:
    dosya.write(str(os.getpid()) + "\\n")

if mode == "early_exit":
    raise SystemExit(23)

def term(_signum, _frame):
    with open(os.environ["FAKE_SIGNAL_FILE"], "a", encoding="utf-8") as dosya:
        dosya.write("TERM\\n")
    if os.environ.get("FAKE_IGNORE_TERM") != "1":
        raise SystemExit(0)

signal.signal(signal.SIGTERM, term)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/healthz":
            self.send_response(404)
            self.end_headers()
            return
        build = os.environ.get("BIYO_BUILD_ID", "missing")
        if mode == "wrong_build":
            build = "wrong-build"
        govde = json.dumps({{
            "app": "biyo-cozucu",
            "build": build,
            "pid": os.getpid() + (1 if mode == "wrong_pid" else 0),
            "status": "ready",
        }}, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(govde)))
        self.end_headers()
        self.wfile.write(govde)

    def log_message(self, _format, *_args):
        pass

HTTPServer(("127.0.0.1", port), Handler).serve_forever()
"""
    _yaz_calistirilabilir(giris, kod)
    return proje, giris


def _launcher_hazirla(tmp_path: Path, port: int) -> tuple[Path, Path, dict[str, str]]:
    proje, _giris = _sahte_proje(tmp_path)
    araclar = tmp_path / "araclar"
    ac_kaydi = tmp_path / "open.log"
    sahte_open = araclar / "open"
    sahte_osascript = araclar / "osascript"
    _yaz_calistirilabilir(
        sahte_open,
        "#!/bin/zsh\n/usr/bin/printf '%s\\n' \"$*\" >>\"$FAKE_OPEN_FILE\"\n",
    )
    _yaz_calistirilabilir(sahte_osascript, "#!/bin/zsh\nexit 0\n")

    metin = LAUNCHER.read_text(encoding="utf-8")
    metin = metin.replace('project_dir="__PROJECT_DIR__"', f'project_dir="{proje}"')
    metin = metin.replace("port_start=8020", f"port_start={port}")
    metin = metin.replace("port_end=8030", f"port_end={port}")
    metin = metin.replace("/usr/bin/open", str(sahte_open))
    metin = metin.replace("/usr/bin/osascript", str(sahte_osascript))
    # Üretimde 30 saniye olan sınırı davranışı değiştirmeden testte kısalt.
    metin = metin.replace("for _attempt in {1..60};", "for _attempt in {1..30};")
    metin = metin.replace("/bin/sleep 0.5", "/bin/sleep 0.05")
    metin = metin.replace("/bin/sleep 0.25", "/bin/sleep 0.02")
    metin = metin.replace("/bin/sleep 0.1", "/bin/sleep 0.02")
    launcher = tmp_path / "launcher.sh"
    _yaz_calistirilabilir(launcher, metin)

    ev = tmp_path / "ev"
    ev.mkdir()
    ortam = os.environ.copy()
    ortam.update(
        {
            "HOME": str(ev),
            "FAKE_OPEN_FILE": str(ac_kaydi),
            "FAKE_START_FILE": str(tmp_path / "start.log"),
            "FAKE_SIGNAL_FILE": str(tmp_path / "signal.log"),
        }
    )
    return launcher, ev, ortam


def _pid_yasiyor(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def _durdur(pid: int) -> None:
    if not _pid_yasiyor(pid):
        return
    os.kill(pid, signal.SIGTERM)
    for _ in range(100):
        if not _pid_yasiyor(pid):
            return
        time.sleep(0.01)
    if _pid_yasiyor(pid):
        os.kill(pid, signal.SIGKILL)


def _health(port: int) -> dict:
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=2) as yanit:
        return json.loads(yanit.read())


def _log_dizini(ev: Path) -> Path:
    return ev / "Library/Logs/BiyoCozucu"


def _kilit_alinabilir(lock: Path) -> bool:
    sonuc = subprocess.run(  # noqa: S603 - sabit macOS aracı ve geçici test yolu
        ["/usr/bin/lockf", "-s", "-t", "0", "-k", lock, "/usr/bin/true"],
        check=False,
    )
    return sonuc.returncode == 0


def test_eszamanli_launcher_tek_child_baslatir_ve_bayat_kayitlari_onarir(
    tmp_path,
) -> None:
    port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    log_dizini = _log_dizini(ev)
    lock = log_dizini / "launch.lock"
    log_dizini.mkdir(parents=True)
    # lockf'te dosyanın içeriği/salt varlığı kilit değildir; eski bir dosya
    # yeni başlatmayı engellememeli.
    lock.write_text("999999\n", encoding="utf-8")
    # Yaşayan fakat biyo-cozucu olmayan PID, PID-reuse sınırını taklit eder.
    (log_dizini / "server.pid").write_text(f"{os.getpid()}\n", encoding="utf-8")

    surecler = [
        subprocess.Popen([launcher], env=ortam)  # noqa: S603 - geçici test betiği
        for _ in range(4)
    ]
    pid = 0
    try:
        assert [surec.wait(timeout=10) for surec in surecler] == [0, 0, 0, 0]
        baslayanlar = (tmp_path / "start.log").read_text(encoding="utf-8").splitlines()
        assert len(baslayanlar) == 1
        pid = int(baslayanlar[0])
        assert int((log_dizini / "server.pid").read_text()) == pid
        assert _health(port)["pid"] == pid
        assert lock.is_file()
        assert _kilit_alinabilir(lock)
        assert not list(log_dizini.glob("server.pid.*.tmp"))
        assert len((tmp_path / "open.log").read_text().splitlines()) == 4
        launcher_log = (log_dizini / "launcher.log").read_text(encoding="utf-8")
        assert "Bayat/geçersiz PID dosyası temizleniyor" in launcher_log
    finally:
        for surec in surecler:
            if surec.poll() is None:
                surec.terminate()
                try:
                    surec.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    surec.kill()
        if (tmp_path / "start.log").exists():
            for satir in (tmp_path / "start.log").read_text().splitlines():
                _durdur(int(satir))


@pytest.mark.parametrize("mode", ["wrong_build", "wrong_pid"])
def test_yanlis_health_kimligi_childi_term_sonra_kill_ile_temizler(
    tmp_path, mode
) -> None:
    port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    ortam["FAKE_MODE"] = mode
    ortam["FAKE_IGNORE_TERM"] = "1"

    sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
        [launcher], env=ortam, timeout=10, check=False
    )
    pid = int((tmp_path / "start.log").read_text().strip())
    assert sonuc.returncode == 1
    assert not _pid_yasiyor(pid)
    assert not (_log_dizini(ev) / "server.pid").exists()
    assert _kilit_alinabilir(_log_dizini(ev) / "launch.lock")
    assert "TERM" in (tmp_path / "signal.log").read_text(encoding="utf-8")
    launcher_log = (_log_dizini(ev) / "launcher.log").read_text(encoding="utf-8")
    assert "Child temizleniyor" in launcher_log
    assert "Child TERM ile kapanmadı" in launcher_log


def test_erken_cikan_child_pid_ve_kilidi_birakmaz(tmp_path) -> None:
    port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    ortam["FAKE_MODE"] = "early_exit"

    sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
        [launcher], env=ortam, timeout=10, check=False
    )
    pid = int((tmp_path / "start.log").read_text().strip())
    assert sonuc.returncode == 1
    assert not _pid_yasiyor(pid)
    assert not (_log_dizini(ev) / "server.pid").exists()
    assert _kilit_alinabilir(_log_dizini(ev) / "launch.lock")
    assert "Sunucu hazır olmadan kapandı" in (
        _log_dizini(ev) / "launcher.log"
    ).read_text(encoding="utf-8")


def _sahte_soru_kesici(ev: Path, port: int, isaret: Path) -> Path:
    """Stüdyo'nun başlatacağı sahte Soru Kesici kurulumu."""
    kok = ev / "Developer/soru-kesici"
    (kok / "soru_kes_web.py").parent.mkdir(parents=True, exist_ok=True)
    (kok / "soru_kes_web.py").write_text("# sahte\n", encoding="utf-8")
    sunucu_kodu = f"""#!{sys.executable}
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

with open(os.environ["FAKE_SK_FILE"], "a", encoding="utf-8") as dosya:
    dosya.write(" ".join(sys.argv[1:]) + "\\n")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        govde = json.dumps({{"app": "soru-kesici", "status": "ready",
                            "version": "v3.4"}}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(govde)))
        self.end_headers()
        self.wfile.write(govde)

    def log_message(self, _f, *_a):
        pass

HTTPServer(("127.0.0.1", {port}), Handler).serve_forever()
"""
    _yaz_calistirilabilir(kok / ".venv/bin/python", sunucu_kodu)
    isaret.write_text("", encoding="utf-8")
    return kok


def _isaret_bekle(yol: Path, sure: float = 8.0) -> str:
    bitis = time.monotonic() + sure
    while time.monotonic() < bitis:
        icerik = yol.read_text(encoding="utf-8")
        if icerik.strip():
            return icerik
        time.sleep(0.05)
    return ""


def test_stüdyo_soru_kesiciyi_arka_planda_baslatir(tmp_path) -> None:
    port = _bos_port()
    sk_port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    metin = launcher.read_text(encoding="utf-8").replace(
        "soru_kesici_port=8756", f"soru_kesici_port={sk_port}"
    )
    _yaz_calistirilabilir(launcher, metin)
    isaret = tmp_path / "soru-kesici-cagri.log"
    ortam["FAKE_SK_FILE"] = str(isaret)
    _sahte_soru_kesici(ev, sk_port, isaret)

    sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
        [launcher], env=ortam, timeout=25, check=False
    )
    try:
        assert sonuc.returncode == 0
        assert "soru_kes_web.py" in _isaret_bekle(isaret)
    finally:
        for satir in (tmp_path / "start.log").read_text().split():
            if satir.strip().isdigit():
                _durdur(int(satir))
        _kapat_port(sk_port)


def _kapat_port(port: int) -> None:
    """Test için başlatılan sahte servisi portundan bulup kapatır."""
    sonuc = subprocess.run(  # noqa: S603 - sabit macOS aracı
        ["/usr/sbin/lsof", "-t", f"-iTCP:{port}", "-sTCP:LISTEN"],
        capture_output=True, text=True, check=False,
    )
    for satir in sonuc.stdout.split():
        if satir.strip().isdigit():
            _durdur(int(satir))


def test_calisan_soru_kesici_ikinci_kez_baslatilmaz(tmp_path) -> None:
    port = _bos_port()
    sk_port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    metin = launcher.read_text(encoding="utf-8").replace(
        "soru_kesici_port=8756", f"soru_kesici_port={sk_port}"
    )
    _yaz_calistirilabilir(launcher, metin)
    isaret = tmp_path / "soru-kesici-cagri.log"
    ortam["FAKE_SK_FILE"] = str(isaret)
    kok = _sahte_soru_kesici(ev, sk_port, isaret)

    # Soru Kesici'yi launcher'dan ÖNCE elle ayağa kaldır.
    onceki = subprocess.Popen(  # noqa: S603 - geçici test betiği
        [str(kok / ".venv/bin/python"), str(kok / "soru_kes_web.py")],
        env={**ortam, "FAKE_SK_FILE": str(isaret)},
    )
    try:
        assert _isaret_bekle(isaret), "Sahte Soru Kesici ayağa kalkmadı."
        oncesi = isaret.read_text(encoding="utf-8").count("\n")

        sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
            [launcher], env=ortam, timeout=25, check=False
        )
        assert sonuc.returncode == 0
        time.sleep(1.0)
        assert isaret.read_text(encoding="utf-8").count("\n") == oncesi
    finally:
        onceki.terminate()
        onceki.wait(timeout=5)
        for satir in (tmp_path / "start.log").read_text().split():
            if satir.strip().isdigit():
                _durdur(int(satir))


def test_yardimci_servisler_kapatilabilir(tmp_path) -> None:
    port = _bos_port()
    sk_port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    metin = launcher.read_text(encoding="utf-8").replace(
        "soru_kesici_port=8756", f"soru_kesici_port={sk_port}"
    )
    _yaz_calistirilabilir(launcher, metin)
    isaret = tmp_path / "soru-kesici-cagri.log"
    ortam["FAKE_SK_FILE"] = str(isaret)
    ortam["BIYO_YARDIMCI_SERVISLER"] = "0"
    _sahte_soru_kesici(ev, sk_port, isaret)

    sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
        [launcher], env=ortam, timeout=25, check=False
    )
    try:
        assert sonuc.returncode == 0
        time.sleep(1.0)
        assert isaret.read_text(encoding="utf-8").strip() == ""
    finally:
        for satir in (tmp_path / "start.log").read_text().split():
            if satir.strip().isdigit():
                _durdur(int(satir))


def test_farkli_buildli_sunucu_ikinci_kopya_acmadan_kullanilir(tmp_path) -> None:
    """Eski Soru Çözücü kısayolu ile Stüdyo aynı sunucuyu paylaşmalı."""
    port = _bos_port()
    launcher, ev, ortam = _launcher_hazirla(tmp_path, port)
    ortam["BIYO_YARDIMCI_SERVISLER"] = "0"
    proje_giris = tmp_path / "proje/.venv/bin/biyo-cozucu"
    onceki = subprocess.Popen(  # noqa: S603 - geçici test betiği
        [str(proje_giris), "sunucu", "--port", str(port)],
        env={**ortam, "BIYO_BUILD_ID": "eski-kisayol-build"},
    )
    try:
        bitis = time.monotonic() + 10
        while time.monotonic() < bitis:
            try:
                if _health(port)["build"] == "eski-kisayol-build":
                    break
            except OSError:
                time.sleep(0.05)
        else:  # pragma: no cover - ortam hatası
            pytest.fail("Sahte sunucu ayağa kalkmadı.")
        baslangic = (tmp_path / "start.log").read_text().count("\n")

        sonuc = subprocess.run(  # noqa: S603 - geçici test betiği
            [launcher], env=ortam, timeout=25, check=False
        )
        assert sonuc.returncode == 0
        # Yeni child başlatılmamalı: aynı sunucu paylaşılır.
        assert (tmp_path / "start.log").read_text().count("\n") == baslangic
        assert f"127.0.0.1:{port}/merkez" in (
            tmp_path / "open.log"
        ).read_text(encoding="utf-8")
        gunluk = (_log_dizini(ev) / "launcher.log").read_text(encoding="utf-8")
        assert "Farklı build'li sunucu kullanılıyor" in gunluk
    finally:
        onceki.terminate()
        onceki.wait(timeout=5)
