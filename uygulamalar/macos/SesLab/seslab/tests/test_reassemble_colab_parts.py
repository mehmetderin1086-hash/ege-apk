from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import pytest


def _module():
    path = Path(__file__).resolve().parents[1] / "scripts" / "reassemble_colab_parts.py"
    spec = importlib.util.spec_from_file_location("reassemble_colab_parts_test", path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _make_parts(root: Path, payload: bytes) -> None:
    chunks = [payload[:3], payload[3:]]
    entries = []
    for index, chunk in enumerate(chunks):
        name = f"voice.part{index:03d}"
        (root / name).write_bytes(chunk)
        entries.append({"name": name, "bytes": len(chunk), "sha256": hashlib.sha256(chunk).hexdigest()})
    (root / "manifest.json").write_text(json.dumps({
        "archive": "voice.zip",
        "archive_bytes": len(payload),
        "archive_sha256": hashlib.sha256(payload).hexdigest(),
        "parts": entries,
    }), encoding="utf-8")


def test_reassemble_verifies_and_writes_atomically(tmp_path):
    helper = _module()
    source = tmp_path / "parts"
    source.mkdir()
    _make_parts(source, b"abcdef")

    target = helper.reassemble(source, tmp_path / "voice.zip")

    assert target.read_bytes() == b"abcdef"
    assert not (tmp_path / ".voice.zip.partial").exists()


def test_reassemble_rejects_corrupt_part_without_target(tmp_path):
    helper = _module()
    source = tmp_path / "parts"
    source.mkdir()
    _make_parts(source, b"abcdef")
    (source / "voice.part001").write_bytes(b"broken")

    with pytest.raises(ValueError, match="dosya boyutu|SHA-256"):
        helper.reassemble(source, tmp_path / "voice.zip")

    assert not (tmp_path / "voice.zip").exists()
