from __future__ import annotations

from collections.abc import Sequence
from pathlib import Path

import pytest

from kitapkatalog.extractor import EvidenceToken
from kitapkatalog.qwen_runtime import (
    ManagedQwenClient,
    QwenRuntimeError,
    _server_command,
)


def test_qwen_command_is_loopback_and_offline(tmp_path: Path) -> None:
    model = tmp_path / "qwen.gguf"
    model.write_bytes(b"x")
    command = _server_command(
        "/bin/llama-server",
        model,
        port=43210,
        context_size=8192,
        threads=2,
    )
    assert command[command.index("--host") + 1] == "127.0.0.1"
    assert command[command.index("--port") + 1] == "43210"
    assert "--offline" in command
    assert command[command.index("--parallel") + 1] == "1"


def test_availability_reports_both_missing_parts(tmp_path: Path) -> None:
    client = ManagedQwenClient(
        executable=tmp_path / "missing-server",
        model_path=tmp_path / "missing-model",
    )
    available, problems = client.availability()
    assert not available
    assert len(problems) == 2


def test_default_context_fits_dense_four_surface_evidence(tmp_path: Path) -> None:
    client = ManagedQwenClient(
        executable=tmp_path / "server",
        model_path=tmp_path / "model",
    )

    assert client.context_size == 32_768


class _FlakyFieldClient:
    """Fails a fixed number of times, then answers."""

    def __init__(self, failures: int) -> None:
        self.failures = failures
        self.calls = 0

    def extract(self, tokens: Sequence[EvidenceToken]) -> list[dict]:
        self.calls += 1
        if self.calls <= self.failures:
            raise ValueError("model geçersiz JSON döndürdü")
        return [{"field": "title", "value": "Kitap"}]


def _client(tmp_path: Path, **kwargs: object) -> ManagedQwenClient:
    return ManagedQwenClient(
        executable=tmp_path / "server",
        model_path=tmp_path / "model",
        **kwargs,  # type: ignore[arg-type]
    )


def test_extraction_survives_a_transient_model_failure(tmp_path: Path) -> None:
    flaky = _FlakyFieldClient(failures=2)

    fields = _client(tmp_path)._extract_with_retry(flaky, ())

    # Two bad responses used to discard the whole model extraction silently.
    assert flaky.calls == 3
    assert fields == [{"field": "title", "value": "Kitap"}]


def test_extraction_gives_up_after_the_retry_budget(tmp_path: Path) -> None:
    flaky = _FlakyFieldClient(failures=99)

    with pytest.raises(QwenRuntimeError, match="3 denemede tamamlanamadı"):
        _client(tmp_path)._extract_with_retry(flaky, ())

    assert flaky.calls == 3


def test_retry_budget_is_configurable(tmp_path: Path) -> None:
    flaky = _FlakyFieldClient(failures=99)

    with pytest.raises(QwenRuntimeError, match="1 denemede tamamlanamadı"):
        _client(tmp_path, max_retries=0)._extract_with_retry(flaky, ())

    assert flaky.calls == 1
