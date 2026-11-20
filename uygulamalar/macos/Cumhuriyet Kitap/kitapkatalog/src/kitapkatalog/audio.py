"""Ses dosyası hazırlama katmanı: kanonik WAV üretimi ve örnek-hassas dilimleme.

Sesli kitap kaydı hattının tüm zaman aralıkları bu modülün ürettiği kanonik
16 kHz / mono / s16le WAV'ın örnek (sample) indekslerine bağlanır; sıkıştırılmış
kaynağa bir daha dönülmez. Böylece chunk'lama, kanıt kesitleri ve checkpoint'ler
deterministik kalır.
"""

from __future__ import annotations

import hashlib
import os
import wave
from array import array
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path

WAV_SAMPLE_RATE = 16_000
WAV_SAMPLE_WIDTH = 2  # s16le
_DECODE_CHUNK_FRAMES = 4096


class AudioError(RuntimeError):
    pass


class AudioDependencyError(AudioError):
    pass


def _require_av():  # pragma: no cover - içe aktarma zarfı
    try:
        import av
    except ImportError as error:
        raise AudioDependencyError(
            "Ses dönüştürme için PyAV gerekli; 'pip install kitapkatalog[voice]' "
            "veya 'uv sync --extra voice' ile kurun"
        ) from error
    return av


@dataclass(frozen=True, slots=True)
class AudioInfo:
    duration_seconds: float
    sample_rate: int
    channels: int
    codec: str


def audio_fingerprint(path: str | Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def probe_audio(path: str | Path) -> AudioInfo:
    av = _require_av()
    try:
        with av.open(str(path)) as container:
            stream = next((item for item in container.streams if item.type == "audio"), None)
            if stream is None:
                raise AudioError(f"Ses akışı bulunamadı: {path}")
            context = stream.codec_context
            duration = 0.0
            if stream.duration is not None and stream.time_base is not None:
                duration = float(stream.duration * stream.time_base)
            elif container.duration is not None:
                duration = float(container.duration) / av.time_base
            return AudioInfo(
                duration_seconds=duration,
                sample_rate=int(context.sample_rate or 0),
                channels=int(context.channels or 0),
                codec=str(context.name),
            )
    except av.error.FFmpegError as error:
        raise AudioError(f"Ses dosyası okunamadı: {path} ({error})") from error


def transcode_to_wav16k(source: str | Path, target: str | Path) -> Path:
    """Kaynağı baştan sona sıralı çöz ve kanonik WAV'ı atomik olarak yaz.

    Resampler gecikmeli örnek bırakabildiği için sonda ``resample(None)`` ile
    flush edilir; çıktı önce ``.part`` dosyasına yazılır, fsync sonrası
    ``os.replace`` ile hedefe taşınır (yarım dosya asla hedef adını alamaz).
    """

    av = _require_av()
    from av.audio.resampler import AudioResampler

    source_path = Path(source)
    target_path = Path(target)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    part_path = target_path.with_name(f"{target_path.name}.part")

    resampler = AudioResampler(format="s16", layout="mono", rate=WAV_SAMPLE_RATE)

    def _frame_bytes(frame) -> bytes:
        return bytes(frame.planes[0])[: frame.samples * WAV_SAMPLE_WIDTH]

    try:
        with av.open(str(source_path)) as container:
            stream = next((item for item in container.streams if item.type == "audio"), None)
            if stream is None:
                raise AudioError(f"Ses akışı bulunamadı: {source_path}")
            with open(part_path, "wb") as handle:
                with closing(wave.open(handle, "wb")) as writer:
                    writer.setnchannels(1)
                    writer.setsampwidth(WAV_SAMPLE_WIDTH)
                    writer.setframerate(WAV_SAMPLE_RATE)
                    for frame in container.decode(stream):
                        for resampled in resampler.resample(frame):
                            writer.writeframes(_frame_bytes(resampled))
                    for resampled in resampler.resample(None):
                        writer.writeframes(_frame_bytes(resampled))
                handle.flush()
                os.fsync(handle.fileno())
    except av.error.FFmpegError as error:
        part_path.unlink(missing_ok=True)
        raise AudioError(f"Ses dönüştürülemedi: {source_path} ({error})") from error
    except BaseException:
        part_path.unlink(missing_ok=True)
        raise
    os.replace(part_path, target_path)
    return target_path


def wav_sample_count(path: str | Path) -> int:
    with wave.open(str(path), "rb") as reader:
        _assert_canonical(reader, path)
        return reader.getnframes()


def slice_wav(
    source: str | Path,
    target: str | Path,
    *,
    start_sample: int,
    end_sample: int,
) -> Path:
    """Kanonik WAV'dan [start_sample, end_sample) aralığını yeni WAV'a kopyala."""

    if end_sample <= start_sample:
        raise AudioError("end_sample, start_sample'dan büyük olmalı")
    target_path = Path(target)
    target_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(source), "rb") as reader:
        _assert_canonical(reader, source)
        total = reader.getnframes()
        start = max(0, min(start_sample, total))
        end = max(start, min(end_sample, total))
        reader.setpos(start)
        remaining = end - start
        part_path = target_path.with_name(f"{target_path.name}.part")
        try:
            with open(part_path, "wb") as handle:
                with closing(wave.open(handle, "wb")) as writer:
                    writer.setnchannels(1)
                    writer.setsampwidth(WAV_SAMPLE_WIDTH)
                    writer.setframerate(WAV_SAMPLE_RATE)
                    while remaining > 0:
                        frames = reader.readframes(min(remaining, _DECODE_CHUNK_FRAMES))
                        if not frames:
                            break
                        writer.writeframes(frames)
                        remaining -= len(frames) // WAV_SAMPLE_WIDTH
                handle.flush()
                os.fsync(handle.fileno())
        except BaseException:
            part_path.unlink(missing_ok=True)
            raise
    os.replace(part_path, target_path)
    return target_path


def find_quietest_sample(
    path: str | Path,
    *,
    around_sample: int,
    span_seconds: float = 15.0,
    window_seconds: float = 1.0,
) -> int:
    """Verilen nokta çevresindeki (±span) en sessiz pencerenin ortasını döndür.

    Chunk kesim noktalarını kelime ortasından sessizliğe kaydırmak için
    kullanılır; RMS enerjisi 100 ms'lik adımlarla taranır.
    """

    with wave.open(str(path), "rb") as reader:
        _assert_canonical(reader, path)
        total = reader.getnframes()
        span = int(span_seconds * WAV_SAMPLE_RATE)
        window = max(1, int(window_seconds * WAV_SAMPLE_RATE))
        begin = max(0, around_sample - span)
        end = min(total, around_sample + span)
        if end - begin <= window:
            return min(max(around_sample, 0), total)
        reader.setpos(begin)
        samples = array("h")
        samples.frombytes(reader.readframes(end - begin))
        hop = max(1, WAV_SAMPLE_RATE // 10)
        best_offset = 0
        best_energy: float | None = None
        for offset in range(0, len(samples) - window + 1, hop):
            section = samples[offset : offset + window]
            energy = sum(value * value for value in section) / len(section)
            if best_energy is None or energy < best_energy:
                best_energy = energy
                best_offset = offset
        return begin + best_offset + window // 2


def _assert_canonical(reader: wave.Wave_read, path: str | Path) -> None:
    if (
        reader.getnchannels() != 1
        or reader.getsampwidth() != WAV_SAMPLE_WIDTH
        or reader.getframerate() != WAV_SAMPLE_RATE
    ):
        raise AudioError(
            f"Kanonik olmayan WAV: {path} "
            f"({reader.getnchannels()}ch/{reader.getframerate()}Hz/"
            f"{reader.getsampwidth() * 8}bit; beklenen 1ch/16000Hz/16bit)"
        )
