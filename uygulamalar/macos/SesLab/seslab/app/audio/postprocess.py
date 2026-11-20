"""Parça birleştirme, seviye eşitleme ve stüdyo mastering zinciri.

Cümle-başına üretimde her parça ayrı sentezlendiği için üç sorun doğar ve
burada çözülür:
1. Sert ekler → parça başına fade-in/fade-out (tık/ani kesilme hissi biter)
2. Parçalar arası ses düzeyi farkı → RMS eşitleme (ortanca hedefe ±6 dB)
3. Tek tip boşluk → noktalamaya duyarlı duraksama (synth.gap_after_chunk)

Mastering: 70 Hz yüksek geçiren (uğultu/DC) → LUFS -16 normalizasyonu
(podcast/yayın standardı) → -1 dBFS tepe emniyeti.
"""
from __future__ import annotations

import numpy as np

MASTER_LUFS = -16.0     # yayın/podcast hedef ses yüksekliği
PEAK_CEILING_DB = -1.0  # tepe emniyet tavanı
FADE_IN_S = 0.015
FADE_OUT_S = 0.060
LEVEL_CAP_DB = 6.0      # RMS eşitlemede parçaya uygulanacak azami kazanç


def peak_normalize(audio: np.ndarray, peak: float = 0.95) -> np.ndarray:
    """Tepe genliği hedefe ölçekler (sessiz/boş dizilere dokunmaz)."""
    m = float(np.max(np.abs(audio))) if len(audio) else 0.0
    if m < 1e-6:
        return audio
    return (audio * (peak / m)).astype(np.float32)


def apply_fades(
    part: np.ndarray, sr: int,
    fade_in_s: float = FADE_IN_S, fade_out_s: float = FADE_OUT_S,
) -> np.ndarray:
    """Parça uçlarına doğrusal fade uygular (yeni dizi döndürür)."""
    part = part.astype(np.float32).copy()
    n_in = int(sr * fade_in_s)
    n_out = int(sr * fade_out_s)
    if n_in + n_out >= len(part) or len(part) == 0:
        return part
    if n_in > 0:
        part[:n_in] *= np.linspace(0.0, 1.0, n_in, dtype=np.float32)
    if n_out > 0:
        part[-n_out:] *= np.linspace(1.0, 0.0, n_out, dtype=np.float32)
    return part


def trim_edge_silence(part: np.ndarray, sr: int, top_db: float = 40.0) -> np.ndarray:
    """Parça uçlarındaki sessizliği kırpar — duraksama süresi tamamen
    bizim eklediğimiz boşluklardan gelsin diye (tasarlanan 0.4/0.55/0.8 sn
    değerleri modelin kendi kenar sessizliğiyle şişmesin)."""
    if len(part) < 256:
        return part
    import librosa

    trimmed, _ = librosa.effects.trim(part, top_db=top_db)
    return trimmed if len(trimmed) > 0 else part


def drop_truncated_ending(
    audio: np.ndarray, sr: int, top_db: float = 40.0, min_keep_s: float = 3.0
) -> np.ndarray:
    """Kayıt dosya sonunda ses içindeyken bitiyorsa son sesli segmenti atar.

    Sert kesilmiş (kelime ortası biten) klon referansı, XTTS'in cümle
    bitirme davranışını bozup üretimlerde kuyruk halüsinasyonu doğuruyor
    (A/B ölçümüyle doğrulandı) — referans doğal bir duraksamayla bitmeli.
    Kalan süre min_keep_s altına düşecekse dokunulmaz.
    """
    if len(audio) < 256:
        return audio
    import librosa

    intervals = librosa.effects.split(
        audio, top_db=top_db, frame_length=1024, hop_length=256
    )
    if len(intervals) < 2:
        return audio
    if intervals[-1][1] < len(audio) - 512:  # zaten sessizlikle bitiyor
        return audio
    keep = int(intervals[-2][1])
    if keep < int(min_keep_s * sr):
        return audio
    return audio[:keep]


def _crossfade_append(out: np.ndarray, piece: np.ndarray, n: int) -> np.ndarray:
    """İki parçayı n örneklik doğrusal çapraz geçişle birleştirir."""
    if n <= 0 or len(out) < n or len(piece) < n:
        return np.concatenate([out, piece])
    fade = np.linspace(0.0, 1.0, n, dtype=np.float32)
    blended = out[-n:] * (1.0 - fade) + piece[:n] * fade
    return np.concatenate([out[:-n], blended, piece[n:]])


def enhance_ref(
    audio: np.ndarray,
    sr: int,
    top_db: float = 40.0,
    max_gap_s: float = 0.25,
    crossfade_s: float = 0.010,
    min_out_s: float = 3.0,
) -> np.ndarray:
    """Klon referansını koşullandırma için yoğunlaştırır.

    XTTS koşullandırma latent'leri ~4 sn'lik mel parçalarının ortalaması
    olduğundan referanstaki uzun sessizlikler sesi seyreltir. Zincir:
    70 Hz HPF → iç sessizlikleri max_gap_s'e kapla → ek yerlerinde
    crossfade → uç sessizliğini kırp → tepe normalizasyonu.

    Boşluklar kapatılırken orijinal boşluk sesi korunur (baş+son yarım;
    sentetik sıfır eklenmez) — oda tonu ve nefes başlangıçları kalır.
    LUFS/limiter bilinçli olarak YOK: dinamikleri ezmek tınıyı boyar.
    Sonuç min_out_s altına düşerse yalnız trim+normalize edilmiş girdi döner.
    """
    if len(audio) == 0:
        return audio.astype(np.float32)
    import librosa
    from scipy.signal import butter, sosfilt

    sos = butter(2, 70, btype="highpass", fs=sr, output="sos")
    audio = sosfilt(sos, audio).astype(np.float32)
    fallback = peak_normalize(trim_edge_silence(audio, sr, top_db=top_db))

    intervals = librosa.effects.split(
        audio, top_db=top_db, frame_length=1024, hop_length=256
    )
    if len(intervals) == 0:
        return fallback

    half_gap = int(sr * max_gap_s / 2)
    n_fade = int(sr * crossfade_s)
    out = audio[intervals[0][0]:intervals[0][1]]
    for (_, prev_end), (start, end) in zip(intervals, intervals[1:]):
        if start - prev_end <= 2 * half_gap + n_fade:
            out = np.concatenate([out, audio[prev_end:end]])
        else:
            head = audio[prev_end:prev_end + half_gap]
            tail = audio[start - half_gap:end]
            out = _crossfade_append(np.concatenate([out, head]), tail, n_fade)

    out = peak_normalize(trim_edge_silence(out, sr, top_db=top_db))
    if len(out) < int(min_out_s * sr):
        return fallback
    return out.astype(np.float32)


def _voiced_rms(part: np.ndarray) -> float:
    """Sessiz örnekleri dışlayarak RMS (konuşma düzeyi) ölçer."""
    voiced = part[np.abs(part) > 0.01]
    ref = voiced if len(voiced) > 100 else part
    return float(np.sqrt(np.mean(np.square(ref)))) if len(ref) else 0.0


def match_levels(parts: list[np.ndarray], cap_db: float = LEVEL_CAP_DB) -> list[np.ndarray]:
    """Parçaları ortanca konuşma düzeyine eşitler (±cap_db sınırlı)."""
    if len(parts) < 2:
        return parts
    rms = [_voiced_rms(p) for p in parts]
    positive = [r for r in rms if r > 1e-5]
    if not positive:
        return parts
    target = float(np.median(positive))
    cap = 10 ** (cap_db / 20)
    out = []
    for p, r in zip(parts, rms):
        gain = 1.0 if r <= 1e-5 else float(np.clip(target / r, 1 / cap, cap))
        out.append((p * gain).astype(np.float32))
    return out


def master(audio: np.ndarray, sr: int, lufs: float = MASTER_LUFS) -> np.ndarray:
    """Stüdyo mastering: yüksek geçiren → LUFS normalizasyonu → tepe emniyeti."""
    if len(audio) == 0:
        return audio
    from scipy.signal import butter, sosfilt

    # 1. 70 Hz yüksek geçiren: uğultu, DC kayması, oda gürlemesi temizliği
    sos = butter(2, 70, btype="highpass", fs=sr, output="sos")
    audio = sosfilt(sos, audio).astype(np.float32)

    # 2. LUFS -16 (pyloudnorm en az ~0.4 sn ister)
    if len(audio) / sr >= 0.5:
        try:
            import pyloudnorm as pyln

            meter = pyln.Meter(sr)
            loudness = meter.integrated_loudness(audio.astype(np.float64))
            if np.isfinite(loudness):
                audio = pyln.normalize.loudness(
                    audio.astype(np.float64), loudness, lufs
                ).astype(np.float32)
        except Exception:  # noqa: BLE001 — mastering asla üretimi düşürmesin
            pass

    # 3. Yumuşak sınırlayıcı: tavanı aşan tepeler şeffafça bastırılır —
    #    tüm sinyali kısmak yerine (bu LUFS'u hedeften 2-3 dB düşürüyordu)
    #    yalnız tepeler tanh diziyle yuvarlanır, ses yüksekliği hedefte kalır.
    ceiling = 10 ** (PEAK_CEILING_DB / 20)
    knee = 0.7 * ceiling
    absx = np.abs(audio)
    over = absx > knee
    if np.any(over):
        squashed = knee + (ceiling - knee) * np.tanh(
            (absx[over] - knee) / (ceiling - knee)
        )
        audio = audio.copy()
        audio[over] = np.sign(audio[over]) * squashed
    return audio.astype(np.float32)


def stitch(
    parts: list[np.ndarray],
    sr: int,
    gaps_s: list[float] | None = None,
    normalize: bool = True,
) -> np.ndarray:
    """Parçaları fade + seviye eşitleme + mastering ile birleştirir.

    gaps_s[i] → parts[i]'den SONRAKİ sessizlik süresi.
    normalize=True → tam mastering zinciri; False → ham birleştirme.
    """
    if not parts:
        return np.zeros(0, dtype=np.float32)
    if gaps_s is None:
        gaps_s = [0.3] * len(parts)

    if normalize:
        parts = [trim_edge_silence(p, sr) for p in parts]
        parts = match_levels(parts)
    parts = [apply_fades(p, sr) for p in parts]

    segments: list[np.ndarray] = []
    for i, part in enumerate(parts):
        segments.append(part.astype(np.float32))
        if i < len(parts) - 1:
            gap = gaps_s[i] if i < len(gaps_s) else 0.3
            if gap > 0:
                segments.append(np.zeros(int(sr * gap), dtype=np.float32))
    out = np.concatenate(segments)
    return master(out, sr) if normalize else out
