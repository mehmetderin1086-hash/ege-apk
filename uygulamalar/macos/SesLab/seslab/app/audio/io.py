"""PyAV tabanlı ses G/Ç.

Sistemde ffmpeg CLI yok; PyAV tekerlekleri FFmpeg kütüphanelerini gömülü taşır.
Tarayıcı kayıtları (Chrome: webm/opus, Safari: mp4/aac) dahil her formatı
float32 mono numpy dizisine çözer. mlx-whisper'a HER ZAMAN numpy dizisi
verilmelidir (dosya yolu verilirse var olmayan ffmpeg CLI'ını arar).
"""
from __future__ import annotations

import io
from pathlib import Path

import av
import numpy as np
import soundfile as sf


def decode_audio(
    source: bytes | str | Path, target_sr: int = 24000
) -> tuple[np.ndarray, int]:
    """Herhangi bir ses kaynağını (bytes veya dosya yolu) çözer.

    Dönüş: (float32 mono dizi, target_sr)
    """
    if isinstance(source, (bytes, bytearray)):
        container = av.open(io.BytesIO(bytes(source)))
    else:
        container = av.open(str(source))

    try:
        stream = container.streams.audio[0]
    except IndexError:
        container.close()
        raise ValueError("Dosyada ses akışı bulunamadı") from None

    resampler = av.AudioResampler(format="flt", layout="mono", rate=target_sr)
    chunks: list[np.ndarray] = []
    for frame in container.decode(stream):
        for rf in resampler.resample(frame):
            chunks.append(rf.to_ndarray().reshape(-1))
    # Resampler tamponunu boşalt
    for rf in resampler.resample(None):
        chunks.append(rf.to_ndarray().reshape(-1))
    container.close()

    if not chunks:
        raise ValueError("Ses çözülemedi (boş akış)")
    return np.concatenate(chunks).astype(np.float32), target_sr


def write_wav(path: str | Path, audio: np.ndarray, sr: int) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(path), audio, sr)


def read_wav(path: str | Path) -> tuple[np.ndarray, int]:
    audio, sr = sf.read(str(path), dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    return audio, sr


def _mp3_stream(parts, sr: int, dest, bitrate: int) -> None:
    """Parça parça float32 mono dizileri tek mp3 akışına kodlar.

    `parts` bir yineleyici (generator) olabilir → tüm ses belleğe alınmadan
    akışla kodlanır (kitap ölçeği: 43 saatlik ses 14 GB float dizi + 4 GB WAV
    sınırını aşar; mp3 akışı aşmaz). `dest` bir dosya yolu veya BytesIO.
    """
    out = av.open(dest, "w", format="mp3")
    stream = out.add_stream("libmp3lame", rate=sr)
    stream.bit_rate = bitrate
    fifo = av.AudioFifo()
    frame_size = stream.codec_context.frame_size or 1152
    in_pts = 0
    try:
        for audio in parts:
            if audio is None or len(audio) == 0:
                continue
            frame = av.AudioFrame.from_ndarray(
                np.ascontiguousarray(audio.reshape(1, -1), dtype=np.float32),
                format="fltp", layout="mono",
            )
            frame.sample_rate = sr
            frame.pts = in_pts
            in_pts += frame.samples
            fifo.write(frame)
            while fifo.samples >= frame_size:
                for pkt in stream.encode(fifo.read(frame_size)):
                    out.mux(pkt)
        if fifo.samples:
            for pkt in stream.encode(fifo.read(fifo.samples)):
                out.mux(pkt)
        for pkt in stream.encode(None):
            out.mux(pkt)
    finally:
        out.close()


def encode_mp3(audio: np.ndarray, sr: int, bitrate: int = 192_000) -> bytes:
    """float32 mono diziyi mp3 baytlarına kodlar (libmp3lame, PyAV gömülü)."""
    buf = io.BytesIO()
    _mp3_stream([audio], sr, buf, bitrate)
    return buf.getvalue()


def encode_mp3_to_file(parts, sr: int, out_path: str | Path, bitrate: int = 192_000) -> None:
    """Parça yineleyicisini doğrudan bir mp3 dosyasına akışla kodlar."""
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    _mp3_stream(parts, sr, str(out_path), bitrate)


def duration_s(audio: np.ndarray, sr: int) -> float:
    return round(len(audio) / sr, 3)
