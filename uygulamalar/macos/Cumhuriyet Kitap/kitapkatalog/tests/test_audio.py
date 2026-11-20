from __future__ import annotations

import math
import wave
from array import array
from pathlib import Path

import pytest

from kitapkatalog.audio import (
    WAV_SAMPLE_RATE,
    AudioError,
    audio_fingerprint,
    find_quietest_sample,
    probe_audio,
    slice_wav,
    transcode_to_wav16k,
    wav_sample_count,
)


def _write_wav(
    path: Path,
    *,
    seconds: float,
    rate: int = WAV_SAMPLE_RATE,
    channels: int = 1,
    tone_hz: float = 440.0,
    silent_ranges: tuple[tuple[float, float], ...] = (),
) -> Path:
    frame_count = int(seconds * rate)
    samples = array("h")
    for index in range(frame_count):
        moment = index / rate
        value = int(12_000 * math.sin(2 * math.pi * tone_hz * moment))
        if any(start <= moment < end for start, end in silent_ranges):
            value = 0
        for _ in range(channels):
            samples.append(value)
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(channels)
        writer.setsampwidth(2)
        writer.setframerate(rate)
        writer.writeframes(samples.tobytes())
    return path


def test_transcode_produces_canonical_wav(tmp_path: Path) -> None:
    pytest.importorskip("av")
    source = _write_wav(tmp_path / "source.wav", seconds=1.5, rate=44_100, channels=2)
    target = transcode_to_wav16k(source, tmp_path / "canonical.wav")

    with wave.open(str(target), "rb") as reader:
        assert reader.getnchannels() == 1
        assert reader.getframerate() == WAV_SAMPLE_RATE
        assert reader.getsampwidth() == 2
        expected = int(1.5 * WAV_SAMPLE_RATE)
        assert abs(reader.getnframes() - expected) <= WAV_SAMPLE_RATE // 100
    assert not (tmp_path / "canonical.wav.part").exists()


def test_probe_reports_duration_and_codec(tmp_path: Path) -> None:
    pytest.importorskip("av")
    source = _write_wav(tmp_path / "probe.wav", seconds=2.0, rate=22_050)
    info = probe_audio(source)
    assert info.channels == 1
    assert info.sample_rate == 22_050
    assert abs(info.duration_seconds - 2.0) < 0.1


def test_probe_rejects_non_audio_file(tmp_path: Path) -> None:
    pytest.importorskip("av")
    junk = tmp_path / "junk.m4a"
    junk.write_bytes(b"bu bir ses dosyasi degil")
    with pytest.raises(AudioError):
        probe_audio(junk)


def test_slice_wav_is_sample_accurate(tmp_path: Path) -> None:
    source = _write_wav(tmp_path / "canonical.wav", seconds=3.0)
    piece = slice_wav(
        source,
        tmp_path / "piece.wav",
        start_sample=WAV_SAMPLE_RATE,
        end_sample=2 * WAV_SAMPLE_RATE,
    )
    assert wav_sample_count(piece) == WAV_SAMPLE_RATE

    clamped = slice_wav(
        source,
        tmp_path / "clamped.wav",
        start_sample=2 * WAV_SAMPLE_RATE,
        end_sample=99 * WAV_SAMPLE_RATE,
    )
    assert wav_sample_count(clamped) == WAV_SAMPLE_RATE

    with pytest.raises(AudioError):
        slice_wav(source, tmp_path / "bos.wav", start_sample=5, end_sample=5)


def test_slice_rejects_non_canonical_wav(tmp_path: Path) -> None:
    source = _write_wav(tmp_path / "stereo.wav", seconds=1.0, rate=44_100, channels=2)
    with pytest.raises(AudioError):
        slice_wav(source, tmp_path / "out.wav", start_sample=0, end_sample=100)


def test_find_quietest_sample_prefers_silence(tmp_path: Path) -> None:
    source = _write_wav(
        tmp_path / "gap.wav",
        seconds=30.0,
        silent_ranges=((14.0, 16.0),),
    )
    found = find_quietest_sample(source, around_sample=10 * WAV_SAMPLE_RATE, span_seconds=8.0)
    assert 14.0 <= found / WAV_SAMPLE_RATE <= 16.0


def test_fingerprint_is_stable(tmp_path: Path) -> None:
    source = _write_wav(tmp_path / "fp.wav", seconds=0.2)
    assert audio_fingerprint(source) == audio_fingerprint(source)
