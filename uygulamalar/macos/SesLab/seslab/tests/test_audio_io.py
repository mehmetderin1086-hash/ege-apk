"""Ses G/Ç testleri — tarayıcı formatları (webm/opus, mp4/aac) gidiş-dönüş.

Fixture'lar PyAV ile üretilir: Chrome webm/opus, Safari mp4/aac üretir;
aynı kodekleri PyAV ile kodlayıp geri çözmek gerçek yükü temsil eder.
"""
import io

import av
import numpy as np
import pytest

from app.audio.io import decode_audio, duration_s, encode_mp3, read_wav, write_wav
from app.audio.postprocess import peak_normalize, stitch


def make_tone(sr: int, seconds: float = 1.0, freq: float = 440.0) -> np.ndarray:
    t = np.arange(int(sr * seconds)) / sr
    return (0.5 * np.sin(2 * np.pi * freq * t)).astype(np.float32)


def encode_with_pyav(audio: np.ndarray, sr: int, fmt: str, codec: str) -> bytes:
    """Test yardımcısı: diziyi verilen kapsayıcı/kodek ile kodlar."""
    buf = io.BytesIO()
    out = av.open(buf, "w", format=fmt)
    stream = out.add_stream(codec, rate=sr)
    frame = av.AudioFrame.from_ndarray(
        audio.reshape(1, -1), format="fltp", layout="mono"
    )
    frame.sample_rate = sr
    frame.pts = 0
    fifo = av.AudioFifo()
    fifo.write(frame)
    fs = stream.codec_context.frame_size or 1024
    while fifo.samples >= fs:
        for pkt in stream.encode(fifo.read(fs)):
            out.mux(pkt)
    if fifo.samples:
        for pkt in stream.encode(fifo.read(fifo.samples)):
            out.mux(pkt)
    for pkt in stream.encode(None):
        out.mux(pkt)
    out.close()
    return buf.getvalue()


# --- WAV gidiş-dönüş ----------------------------------------------------------

def test_wav_yaz_oku(tmp_path):
    tone = make_tone(24000)
    p = tmp_path / "ton.wav"
    write_wav(p, tone, 24000)
    audio, sr = read_wav(p)
    assert sr == 24000
    assert abs(len(audio) - len(tone)) < 10


def test_wav_bytes_decode():
    tone = make_tone(24000)
    import soundfile as sf

    buf = io.BytesIO()
    sf.write(buf, tone, 24000, format="WAV")
    audio, sr = decode_audio(buf.getvalue(), target_sr=24000)
    assert sr == 24000
    assert abs(duration_s(audio, sr) - 1.0) < 0.05


# --- Tarayıcı formatları --------------------------------------------------------

def test_webm_opus_chrome_kaydi():
    """Chrome MediaRecorder çıktısını temsil eder (webm/opus, 48 kHz)."""
    tone = make_tone(48000)
    data = encode_with_pyav(tone, 48000, "webm", "libopus")
    audio, sr = decode_audio(data, target_sr=24000)
    assert sr == 24000
    assert abs(duration_s(audio, sr) - 1.0) < 0.1


def test_mp4_aac_safari_kaydi():
    """Safari MediaRecorder çıktısını temsil eder (mp4/aac, 44.1 kHz)."""
    tone = make_tone(44100)
    data = encode_with_pyav(tone, 44100, "mp4", "aac")
    audio, sr = decode_audio(data, target_sr=16000)
    assert sr == 16000
    assert abs(duration_s(audio, sr) - 1.0) < 0.1


# --- MP3 kodlama ---------------------------------------------------------------

def test_mp3_encode_decode():
    tone = make_tone(24000, seconds=0.5)
    mp3 = encode_mp3(tone, 24000)
    assert len(mp3) > 1000
    audio, sr = decode_audio(mp3, target_sr=24000)
    assert abs(duration_s(audio, sr) - 0.5) < 0.15  # mp3 kodek gecikmesi payı


# --- Yeniden örnekleme -----------------------------------------------------------

def test_resample_16k():
    tone = make_tone(24000)
    import soundfile as sf

    buf = io.BytesIO()
    sf.write(buf, tone, 24000, format="WAV")
    audio, sr = decode_audio(buf.getvalue(), target_sr=16000)
    assert sr == 16000
    assert abs(len(audio) - 16000) < 200


# --- Hatalı girdi ---------------------------------------------------------------

def test_ses_olmayan_dosya():
    with pytest.raises((ValueError, av.error.InvalidDataError, OSError)):
        decode_audio(b"bu bir ses dosyasi degil" * 10)


# --- Birleştirme -----------------------------------------------------------------

def test_stitch_sessizlik_araliklari():
    sr = 24000
    a = make_tone(sr, 1.0)
    b = make_tone(sr, 1.0)
    out = stitch([a, b], sr, gaps_s=[0.5])
    assert abs(len(out) - int(sr * 2.5)) < 10


def test_stitch_bos():
    assert len(stitch([], 24000)) == 0


def test_peak_normalize():
    quiet = make_tone(24000) * 0.1
    out = peak_normalize(quiet, peak=0.95)
    assert abs(float(np.max(np.abs(out))) - 0.95) < 0.01
