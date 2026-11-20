from __future__ import annotations

import json
import wave
from array import array
from pathlib import Path

import pytest

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.cli import main
from kitapkatalog.offline import _uninstall_for_tests


@pytest.fixture(autouse=True)
def restore_network_guard() -> None:
    _uninstall_for_tests()
    yield
    _uninstall_for_tests()


def _wav(path: Path, seconds: float = 2.0) -> Path:
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(WAV_SAMPLE_RATE)
        writer.writeframes((array("h", [0]) * int(seconds * WAV_SAMPLE_RATE)).tobytes())
    return path


def test_voice_add_and_jobs_round_trip(tmp_path: Path, capsys) -> None:
    database = tmp_path / "veri" / "catalog.sqlite3"
    audio = _wav(tmp_path / "kayit.wav")

    code = main(
        [
            "--database",
            str(database),
            "--json",
            "voice",
            "add",
            str(audio),
            "--name",
            "raf-1",
            "--single",
        ]
    )
    assert code == 0
    created = json.loads(capsys.readouterr().out)
    assert created["name"] == "raf-1"
    assert created["single_book"] is True
    assert created["status"] == "queued"

    code = main(["--database", str(database), "--json", "voice", "jobs"])
    assert code == 0
    jobs = json.loads(capsys.readouterr().out)
    assert len(jobs) == 1 and jobs[0]["id"] == created["id"]

    # Aynı dosyayı ikinci kez eklemek aynı işi döndürür (idempotent).
    code = main(["--database", str(database), "--json", "voice", "add", str(audio)])
    assert code == 0
    again = json.loads(capsys.readouterr().out)
    assert again["id"] == created["id"]


def test_voice_pause_resume_cancel(tmp_path: Path, capsys) -> None:
    database = tmp_path / "veri" / "catalog.sqlite3"
    audio = _wav(tmp_path / "kayit.wav")
    main(["--database", str(database), "--json", "voice", "add", str(audio)])
    job_id = json.loads(capsys.readouterr().out)["id"]

    for command, expected in (
        ("pause", "paused"),
        ("resume", "running"),
        ("cancel", "cancelled"),
    ):
        code = main(["--database", str(database), "--json", "voice", command, job_id])
        assert code == 0
        assert json.loads(capsys.readouterr().out)["status"] == expected
