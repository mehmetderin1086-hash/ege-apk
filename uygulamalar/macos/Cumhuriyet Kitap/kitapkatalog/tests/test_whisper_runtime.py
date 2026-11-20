from __future__ import annotations

import json
import re
import wave
from array import array
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from typing import ClassVar

import pytest

from kitapkatalog.whisper_runtime import (
    DEFAULT_WHISPER_MODEL_FILENAME,
    ManagedWhisperClient,
    WhisperRuntimeError,
    _parse_transcript,
    _server_command,
    default_model_path,
    default_server_executable,
)

_VERBOSE_JSON = {
    "task": "transcribe",
    "language": "tr",
    "duration": 4.2,
    "text": "Başlık Kar yazar Orhan Pamuk",
    "segments": [
        {
            "id": 0,
            "start": 0.0,
            "end": 2.1,
            "text": "Başlık Kar",
            "avg_logprob": -0.15,
            "no_speech_prob": 0.02,
            "beklenmeyen_alan": "yok sayılmalı",
        },
        {"id": 1, "start": 2.1, "end": 4.2, "text": "yazar Orhan Pamuk"},
    ],
}


def _parse_multipart_fields(body: bytes) -> dict[str, str]:
    """Basit multipart/form-data ayrıştırıcı: yalnız metin alanlarını çıkarır (file hariç)."""

    first_line_end = body.find(b"\r\n")
    boundary = body[:first_line_end]
    fields: dict[str, str] = {}
    for part in body.split(boundary):
        part = part.strip(b"\r\n-")
        if not part or b"Content-Disposition" not in part:
            continue
        header_end = part.find(b"\r\n\r\n")
        if header_end == -1:
            continue
        headers = part[:header_end].decode("utf-8", "replace")
        if "filename=" in headers:
            continue  # dosya alanı, atla
        name_match = re.search(r'name="([^"]+)"', headers)
        if not name_match:
            continue
        value = part[header_end + 4 :].decode("utf-8", "replace").rstrip("\r\n")
        fields[name_match.group(1)] = value
    return fields


class _FakeWhisperHandler(BaseHTTPRequestHandler):
    payload: bytes = json.dumps(_VERBOSE_JSON).encode()
    status: int = 200
    last_fields: ClassVar[dict[str, str]] = {}

    def do_POST(self) -> None:
        if self.path != "/inference":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length)
        assert b"verbose_json" in body
        assert b'name="file"' in body
        type(self).last_fields = _parse_multipart_fields(body)
        self.send_response(type(self).status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(type(self).payload)

    def log_message(self, *args: object) -> None:  # gürültüyü kes
        pass


@pytest.fixture()
def fake_server():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _FakeWhisperHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server
    finally:
        server.shutdown()
        thread.join(timeout=5)
        _FakeWhisperHandler.payload = json.dumps(_VERBOSE_JSON).encode()
        _FakeWhisperHandler.status = 200
        _FakeWhisperHandler.last_fields = {}


def _client_bound_to(server, tmp_path: Path) -> ManagedWhisperClient:
    """Sunucu başlatmadan, sahte sunucuya bağlı bir istemci kur."""

    model = tmp_path / "model.bin"
    model.write_bytes(b"gguf")
    client = ManagedWhisperClient(executable="/bin/ls", model_path=model)
    client._port = server.server_address[1]

    class _AliveStub:
        returncode = None

        @staticmethod
        def poll() -> None:
            return None

    client._process = _AliveStub()  # type: ignore[assignment]
    return client


def _wav(tmp_path: Path) -> Path:
    path = tmp_path / "utterance.wav"
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(16000)
        writer.writeframes(array("h", [0] * 1600).tobytes())
    return path


def test_transcribe_parses_verbose_json(fake_server, tmp_path: Path) -> None:
    client = _client_bound_to(fake_server, tmp_path)
    segments = client.transcribe(_wav(tmp_path))
    assert len(segments) == 2
    assert segments[0].text == "Başlık Kar"
    assert segments[0].avg_logprob == pytest.approx(-0.15)
    assert segments[0].no_speech_prob == pytest.approx(0.02)
    assert segments[1].no_speech_prob is None
    assert segments[1].end_seconds == pytest.approx(4.2)


def test_transcribe_fails_closed_without_segments(fake_server, tmp_path: Path) -> None:
    _FakeWhisperHandler.payload = json.dumps({"text": "sadece metin"}).encode()
    client = _client_bound_to(fake_server, tmp_path)
    with pytest.raises(WhisperRuntimeError, match="segments"):
        client.transcribe(_wav(tmp_path))


def test_transcribe_reports_server_error_body(fake_server, tmp_path: Path) -> None:
    _FakeWhisperHandler.status = 500
    _FakeWhisperHandler.payload = "model çöktü".encode()
    client = _client_bound_to(fake_server, tmp_path)
    with pytest.raises(WhisperRuntimeError, match="500"):
        client.transcribe(_wav(tmp_path))


def test_transcribe_requires_context_manager(tmp_path: Path) -> None:
    client = ManagedWhisperClient(executable="/bin/ls", model_path=tmp_path / "x")
    with pytest.raises(WhisperRuntimeError, match="bağlam yöneticisi"):
        client.transcribe(tmp_path / "a.wav")


def test_parse_transcript_rejects_malformed_segment(tmp_path: Path) -> None:
    payload = json.dumps({"segments": [{"start": "abc"}]}).encode()
    with pytest.raises(WhisperRuntimeError, match="zorunlu alan"):
        _parse_transcript(payload, tmp_path / "a.wav")
    with pytest.raises(WhisperRuntimeError, match="çözümlenemedi"):
        _parse_transcript(b"html degil json", tmp_path / "a.wav")
    with pytest.raises(WhisperRuntimeError, match="hatası"):
        _parse_transcript(json.dumps({"error": "bozuk wav"}).encode(), tmp_path / "a.wav")


def test_availability_reports_missing_pieces(tmp_path: Path) -> None:
    client = ManagedWhisperClient(
        executable=tmp_path / "yok-boyle-sunucu",
        model_path=tmp_path / "yok-model.bin",
    )
    available, problems = client.availability()
    assert not available
    assert len(problems) == 2
    assert "whisper-server" in problems[0]
    assert "fetch_whisper_model" in problems[1]


def test_server_command_shape() -> None:
    command = _server_command(
        "/opt/bin/whisper-server",
        Path("/models/ggml.bin"),
        port=8123,
        threads=6,
        language="tr",
    )
    assert command[0] == "/opt/bin/whisper-server"
    assert "--model" in command and "/models/ggml.bin" in command
    assert "--port" in command and "8123" in command
    assert "--language" in command and "tr" in command
    assert "--host" in command and "127.0.0.1" in command
    # whisper-server '--no-prints' tanımıyor (yalnız whisper-cli bayrağı);
    # bilinmeyen bayrak sunucuyu açılışta düşürür.
    assert "--no-prints" not in command


def test_default_paths_respect_environment(monkeypatch, tmp_path: Path) -> None:
    monkeypatch.setenv("KITAPKATALOG_WHISPER_MODEL", str(tmp_path / "ozel.bin"))
    monkeypatch.setenv("KITAPKATALOG_WHISPER_SERVER", "/opt/ozel/whisper-server")
    assert default_model_path() == tmp_path / "ozel.bin"
    assert default_server_executable() == "/opt/ozel/whisper-server"
    monkeypatch.delenv("KITAPKATALOG_WHISPER_MODEL")
    monkeypatch.delenv("KITAPKATALOG_WHISPER_SERVER")
    monkeypatch.setenv("KITAPKATALOG_DATA_DIR", str(tmp_path / "veri"))
    assert default_model_path().name == DEFAULT_WHISPER_MODEL_FILENAME


def test_parse_transcript_rejects_nonsense_timestamps(tmp_path: Path) -> None:
    for start, end in ((float("nan"), 2.0), (-1.0, 2.0), (5.0, 1.0)):
        payload = json.dumps({"segments": [{"start": start, "end": end, "text": "x"}]}).encode()
        with pytest.raises(WhisperRuntimeError, match="zaman damgası"):
            _parse_transcript(payload, tmp_path / "a.wav")


def test_transcribe_default_request_omits_prompt_and_temperature_inc(
    fake_server, tmp_path: Path
) -> None:
    client = _client_bound_to(fake_server, tmp_path)
    client.transcribe(_wav(tmp_path))
    fields = _FakeWhisperHandler.last_fields
    assert "prompt" not in fields
    assert "temperature_inc" not in fields
    assert fields["language"] == "tr"
    assert fields["temperature"] == "0.0"


def test_transcribe_passes_language_prompt_and_temperature_inc(
    fake_server, tmp_path: Path
) -> None:
    client = _client_bound_to(fake_server, tmp_path)
    client.transcribe(_wav(tmp_path), language="en", prompt="Merhaba dünya", temperature_inc=0.2)
    fields = _FakeWhisperHandler.last_fields
    assert fields["language"] == "en"
    assert fields["prompt"] == "Merhaba dünya"
    assert fields["temperature_inc"] == "0.2"


def test_transcribe_truncates_prompt_at_600_chars(fake_server, tmp_path: Path) -> None:
    client = _client_bound_to(fake_server, tmp_path)
    client.transcribe(_wav(tmp_path), prompt="a" * 900)
    assert len(_FakeWhisperHandler.last_fields["prompt"]) == 600
