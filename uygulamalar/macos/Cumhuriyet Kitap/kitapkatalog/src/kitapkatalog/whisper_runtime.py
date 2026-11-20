"""Yerel whisper.cpp sunucusu üzerinden Türkçe transkripsiyon çalışma zamanı.

``qwen_runtime`` ile aynı loopback-subprocess desenini izler; tek bilinçli
fark yaşam döngüsüdür: model yüklemesi pahalı olduğundan ``ManagedWhisperClient``
bir iş/oturum boyunca açık kalan bir bağlam yöneticisidir. Sunucu, iptalde
yetim süreç kalmaması için kendi süreç grubunda başlatılır ve grup olarak
sonlandırılır. Yanıt sözleşmesi fail-closed'dur: zaman damgalı ``segments``
listesi yoksa sonuç kabul edilmez (toplu bölütleme segmentsiz çalışamaz).
"""

from __future__ import annotations

import json
import math
import os
import shutil
import signal
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from contextlib import suppress

from kitapkatalog import portable
import uuid
from pathlib import Path

from kitapkatalog.config import AppPaths
from kitapkatalog.domain import TranscriptSegment

DEFAULT_WHISPER_MODEL_FILENAME = "ggml-large-v3-turbo-q5_0.bin"
_WHISPER_MODEL_ENV = "KITAPKATALOG_WHISPER_MODEL"
_WHISPER_SERVER_ENV = "KITAPKATALOG_WHISPER_SERVER"
_MAX_PROMPT_CHARS = 600


class WhisperRuntimeError(RuntimeError):
    """Whisper sunucusu başlatılamadı veya sözleşmeye uygun yanıt vermedi."""


def default_model_path(paths: AppPaths | None = None) -> Path:
    override = os.environ.get(_WHISPER_MODEL_ENV)
    if override:
        return Path(override).expanduser()
    resolved = paths if paths is not None else AppPaths.default()
    return resolved.models / "whisper" / DEFAULT_WHISPER_MODEL_FILENAME


def default_server_executable(paths: AppPaths | None = None) -> str:
    override = os.environ.get(_WHISPER_SERVER_ENV)
    if override:
        return override
    resolved = paths if paths is not None else AppPaths.default()
    bundled = resolved.models / "whisper" / "bin" / "whisper-server"
    if bundled.is_file():
        return str(bundled)
    return "whisper-server"


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
    threads: int,
    language: str,
) -> list[str]:
    return [
        executable,
        "--model",
        str(model_path),
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--threads",
        str(threads),
        "--language",
        language,
    ]


def _offline_environment() -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "HF_HUB_OFFLINE": "1",
            "TRANSFORMERS_OFFLINE": "1",
            "DO_NOT_TRACK": "1",
            "KITAPKATALOG_NETWORK_DISABLED": "1",
        }
    )
    return environment


def _wait_until_listening(process: subprocess.Popen[bytes], port: int, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    url = f"http://127.0.0.1:{port}/"
    while time.monotonic() < deadline:
        return_code = process.poll()
        if return_code is not None:
            raise WhisperRuntimeError(f"whisper-server model yüklerken kapandı: {return_code}")
        try:
            with urllib.request.urlopen(url, timeout=1):
                return
        except urllib.error.HTTPError:
            return  # 4xx/5xx bile olsa dinliyor demektir
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
            pass
        time.sleep(0.1)
    raise WhisperRuntimeError("whisper-server hazır olma zaman aşımına uğradı")


def _multipart_body(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = f"kitapkatalog-{uuid.uuid4().hex}"
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(
            (
                f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'
            ).encode()
        )
    parts.append(
        (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="{file_field}"; '
            f'filename="{file_path.name}"\r\n'
            "Content-Type: audio/wav\r\n\r\n"
        ).encode()
    )
    parts.append(file_path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), boundary


def _parse_transcript(payload: bytes, source: Path) -> tuple[TranscriptSegment, ...]:
    try:
        document = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise WhisperRuntimeError(
            f"whisper-server yanıtı çözümlenemedi ({source.name}): {error}"
        ) from error
    if not isinstance(document, dict):
        raise WhisperRuntimeError("whisper-server yanıtı sözlük değil")
    if "error" in document:
        raise WhisperRuntimeError(f"whisper-server hatası: {document['error']}")
    segments = document.get("segments")
    if not isinstance(segments, list):
        raise WhisperRuntimeError(
            "whisper-server yanıtında 'segments' yok; verbose_json bekleniyor"
        )
    parsed: list[TranscriptSegment] = []
    for entry in segments:
        if not isinstance(entry, dict):
            raise WhisperRuntimeError("Segment kaydı sözlük değil")
        try:
            start = float(entry["start"])
            end = float(entry["end"])
            text = str(entry["text"])
        except (KeyError, TypeError, ValueError) as error:
            raise WhisperRuntimeError(f"Segmentte zorunlu alan eksik/bozuk: {error}") from error
        # Fail-closed yalnız yapı değil semantik de kapsar: NaN/sonsuz/negatif
        # veya ters aralık, sahiplik ve örnek indeksi hesaplarını sessizce
        # bozar (NaN tüm karşılaştırmaları kaybeder).
        if (
            not math.isfinite(start)
            or not math.isfinite(end)
            or start < 0
            or end < start
            or end > 86_400
        ):
            raise WhisperRuntimeError(
                f"Segment zaman damgası geçersiz: start={start!r} end={end!r}"
            )
        avg_logprob = entry.get("avg_logprob")
        no_speech_prob = entry.get("no_speech_prob")
        parsed.append(
            TranscriptSegment(
                start_seconds=start,
                end_seconds=end,
                text=text,
                avg_logprob=(float(avg_logprob) if avg_logprob is not None else None),
                no_speech_prob=(float(no_speech_prob) if no_speech_prob is not None else None),
            )
        )
    return tuple(parsed)


class ManagedWhisperClient:
    """Bir iş boyunca açık kalan whisper-server; çıkışta süreç grubu kapanır."""

    def __init__(
        self,
        *,
        executable: str | Path | None = None,
        model_path: Path | None = None,
        threads: int = 4,
        language: str = "tr",
        startup_timeout: float = 300,
        request_timeout: float = 600,
    ) -> None:
        self.executable = executable if executable is not None else default_server_executable()
        self.model_path = Path(model_path) if model_path is not None else default_model_path()
        self.threads = max(1, int(threads))
        self.language = language
        self.startup_timeout = float(startup_timeout)
        self.request_timeout = float(request_timeout)
        self._process: subprocess.Popen[bytes] | None = None
        self._port: int | None = None
        self._log = None

    def availability(self) -> tuple[bool, tuple[str, ...]]:
        problems: list[str] = []
        if _resolve_executable(self.executable) is None:
            problems.append(
                f"whisper-server bulunamadı: {self.executable} "
                "(brew install whisper-cpp veya KITAPKATALOG_WHISPER_SERVER)"
            )
        if not self.model_path.is_file():
            problems.append(
                f"Whisper modeli bulunamadı: {self.model_path} "
                "(scripts/fetch_whisper_model.py ile bir kez indirin)"
            )
        return not problems, tuple(problems)

    def __enter__(self) -> ManagedWhisperClient:
        available, problems = self.availability()
        if not available:
            raise WhisperRuntimeError("; ".join(problems))
        executable = _resolve_executable(self.executable)
        assert executable is not None
        self._port = _unused_loopback_port()
        self._log = tempfile.TemporaryFile()
        try:
            self._process = subprocess.Popen(
                _server_command(
                    executable,
                    self.model_path,
                    port=self._port,
                    threads=self.threads,
                    language=self.language,
                ),
                stdin=subprocess.DEVNULL,
                stdout=self._log,
                stderr=subprocess.STDOUT,
                env=_offline_environment(),
                start_new_session=True,
            )
        except OSError as error:
            self._close_log()
            raise WhisperRuntimeError(f"whisper-server başlatılamadı: {error}") from error
        try:
            _wait_until_listening(self._process, self._port, self.startup_timeout)
        except BaseException:
            self._terminate_process_group()
            self._close_log()
            raise
        return self

    def __exit__(self, *exc_info: object) -> None:
        self._terminate_process_group()
        self._close_log()

    def transcribe(
        self,
        wav_path: str | Path,
        *,
        language: str | None = None,
        prompt: str | None = None,
        temperature: str | float | None = None,
        temperature_inc: str | float | None = None,
    ) -> tuple[TranscriptSegment, ...]:
        if self._process is None or self._port is None:
            raise WhisperRuntimeError("ManagedWhisperClient bağlam yöneticisi olarak açılmalı")
        if self._process.poll() is not None:
            raise WhisperRuntimeError(
                f"whisper-server beklenmedik şekilde kapandı: {self._process.returncode}"
            )
        source = Path(wav_path)
        if not source.is_file():
            raise WhisperRuntimeError(f"WAV bulunamadı: {source}")
        fields = {
            "response_format": "verbose_json",
            "language": language if language is not None else self.language,
            "temperature": "0.0" if temperature is None else str(temperature),
        }
        if prompt is not None:
            fields["prompt"] = prompt[:_MAX_PROMPT_CHARS]
        if temperature_inc is not None:
            fields["temperature_inc"] = str(temperature_inc)
        body, boundary = _multipart_body(fields, "file", source)
        request = urllib.request.Request(
            f"http://127.0.0.1:{self._port}/inference",
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.request_timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as error:
            detail = error.read()[:500].decode("utf-8", "replace")
            raise WhisperRuntimeError(
                f"whisper-server isteği reddetti ({error.code}): {detail}"
            ) from error
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            raise WhisperRuntimeError(f"whisper-server isteği başarısız: {error}") from error
        return _parse_transcript(payload, source)

    def _terminate_process_group(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        portable.surec_grubunu_sonlandir(process)
        try:
            process.wait(timeout=10)
            return
        except subprocess.TimeoutExpired:
            pass
        portable.surec_grubunu_sonlandir(process, zorla=True)
        with suppress(subprocess.TimeoutExpired):
            process.wait(timeout=5)

    def _close_log(self) -> None:
        if self._log is not None:
            self._log.close()
            self._log = None
