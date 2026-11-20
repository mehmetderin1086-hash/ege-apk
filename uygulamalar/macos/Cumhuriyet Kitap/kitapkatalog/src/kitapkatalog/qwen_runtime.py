"""Short-lived, loopback-only Qwen3 field-classification runtime."""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Sequence
from pathlib import Path

from kitapkatalog.extractor import EvidenceToken, LlamaFieldClient


class QwenRuntimeError(RuntimeError):
    """The local Qwen model could not start or return grounded fields."""


def _resolve_executable(value: str | Path) -> str | None:
    candidate = Path(value).expanduser()
    if candidate.parent != Path(".") or candidate.is_absolute():
        return str(candidate.resolve()) if candidate.is_file() else None
    return shutil.which(str(value))


def _unused_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _server_command(
    executable: str,
    model_path: Path,
    *,
    port: int,
    context_size: int,
    threads: int,
) -> list[str]:
    return [
        executable,
        "--model",
        str(model_path),
        "--alias",
        "qwen3-field-extractor",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--ctx-size",
        str(context_size),
        "--threads",
        str(threads),
        "--parallel",
        "1",
        "--offline",
        "--no-webui",
        "--jinja",
        "--reasoning",
        "off",
    ]


def _offline_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "HF_DATASETS_OFFLINE": "1",
            "DO_NOT_TRACK": "1",
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }
    )
    return environment


def _wait_for_health(process: subprocess.Popen[bytes], port: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    url = f"http://127.0.0.1:{port}/health"
    while time.monotonic() < deadline:
        return_code = process.poll()
        if return_code is not None:
            raise QwenRuntimeError(f"Qwen llama-server model yüklerken kapandı: {return_code}")
        try:
            with urllib.request.urlopen(url, timeout=1) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            pass
        time.sleep(0.1)
    raise QwenRuntimeError("Qwen llama-server hazır olma zaman aşımına uğradı")


class ManagedQwenClient:
    """Start Qwen for one book, classify evidence, then release all model memory."""

    def __init__(
        self,
        *,
        executable: str | Path,
        model_path: Path,
        context_size: int = 32_768,
        threads: int = 4,
        startup_timeout: float = 600,
        request_timeout: float = 300,
        max_retries: int = 2,
    ) -> None:
        self.executable = executable
        self.model_path = Path(model_path)
        self.context_size = max(4096, int(context_size))
        self.threads = max(1, int(threads))
        self.startup_timeout = float(startup_timeout)
        self.request_timeout = float(request_timeout)
        self.max_retries = max(0, int(max_retries))

    def availability(self) -> tuple[bool, tuple[str, ...]]:
        problems: list[str] = []
        if _resolve_executable(self.executable) is None:
            problems.append(f"llama-server bulunamadı: {self.executable}")
        if not self.model_path.is_file():
            problems.append(f"Qwen3 model bulunamadı: {self.model_path}")
        return not problems, tuple(problems)

    def _extract_with_retry(
        self,
        client: LlamaFieldClient,
        tokens: Sequence[EvidenceToken],
    ) -> list[dict]:
        """Retry the request while the loaded model is still in memory.

        A truncated response or a malformed JSON body used to discard the whole
        model extraction and silently drop the book to rule-based fields only.
        The model is already loaded here, so another attempt costs one inference
        rather than another model load — the same bargain the OCR engines make.
        """

        final_error: Exception | None = None
        for _attempt in range(self.max_retries + 1):
            try:
                return client.extract(tokens)
            except Exception as exc:
                final_error = exc
        assert final_error is not None
        raise QwenRuntimeError(
            f"Qwen alan çıkarımı {self.max_retries + 1} denemede tamamlanamadı: {final_error}"
        ) from final_error

    def extract(self, tokens: Sequence[EvidenceToken]) -> list[dict]:
        available, problems = self.availability()
        if not available:
            raise QwenRuntimeError("; ".join(problems))
        executable = _resolve_executable(self.executable)
        assert executable is not None
        port = _unused_loopback_port()
        with tempfile.TemporaryFile() as log:
            try:
                process = subprocess.Popen(
                    _server_command(
                        executable,
                        self.model_path,
                        port=port,
                        context_size=self.context_size,
                        threads=self.threads,
                    ),
                    stdin=subprocess.DEVNULL,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    env=_offline_environment(),
                )
            except OSError as exc:
                raise QwenRuntimeError(f"Qwen llama-server başlatılamadı: {exc}") from exc
            try:
                _wait_for_health(process, port, self.startup_timeout)
                client = LlamaFieldClient(
                    f"http://127.0.0.1:{port}",
                    timeout_seconds=self.request_timeout,
                )
                return self._extract_with_retry(client, tokens)
            except Exception as exc:
                if isinstance(exc, QwenRuntimeError):
                    raise
                raise QwenRuntimeError(f"Qwen alan çıkarımı başarısız: {exc}") from exc
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
