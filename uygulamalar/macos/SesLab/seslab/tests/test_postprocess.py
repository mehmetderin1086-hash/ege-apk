"""Mastering zinciri ve duraksama mühendisliği testleri."""
import numpy as np

from app.audio.postprocess import (
    apply_fades,
    drop_truncated_ending,
    enhance_ref,
    master,
    match_levels,
    stitch,
)
from app.core.synth import gap_after_chunk


def tone(sr=24000, seconds=1.0, amp=0.5):
    t = np.arange(int(sr * seconds)) / sr
    return (amp * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


# --- Fade'ler ------------------------------------------------------------------

def test_fade_uclari_yumusatir():
    sr = 24000
    p = apply_fades(tone(sr), sr)
    assert abs(p[0]) < 1e-4          # başlangıç sıfırdan açılır
    assert abs(p[-1]) < 1e-4         # bitiş sıfıra iner
    mid = len(p) // 2
    assert np.max(np.abs(p[mid - 100:mid + 100])) > 0.4  # orta bozulmaz


def test_fade_cok_kisa_parcayi_bozmaz():
    sr = 24000
    p = tone(sr, seconds=0.02)
    out = apply_fades(p, sr)
    assert len(out) == len(p)


# --- Seviye eşitleme ---------------------------------------------------------------

def test_seviye_esitleme():
    # Gerçekçi cümleler arası fark (~6 dB) tamamen eşitlenir
    sr = 24000
    quiet, loud = tone(sr, amp=0.3), tone(sr, amp=0.6)
    a, b = match_levels([quiet, loud])
    rms = lambda x: float(np.sqrt(np.mean(np.square(x))))  # noqa: E731
    assert 0.8 < rms(a) / rms(b) < 1.25


def test_seviye_esitleme_kazanc_siniri():
    # Aşırı fark ±6 dB şapkasıyla sınırlanır (sessiz parça patlatılmaz)
    sr = 24000
    quiet, loud = tone(sr, amp=0.05), tone(sr, amp=0.8)
    a, _ = match_levels([quiet, loud])
    rms = lambda x: float(np.sqrt(np.mean(np.square(x))))  # noqa: E731
    assert rms(a) <= rms(quiet) * 2.01  # kazanç ≤ +6 dB (2×)


def test_seviye_esitleme_tek_parca_dokunmaz():
    p = tone()
    out = match_levels([p])
    assert np.array_equal(out[0], p)


# --- Mastering ------------------------------------------------------------------------

def test_master_tepe_emniyeti():
    sr = 24000
    hot = tone(sr, amp=1.4)  # kırpılmış giriş
    out = master(hot, sr)
    assert float(np.max(np.abs(out))) <= 10 ** (-1 / 20) + 1e-3  # ≤ -1 dBFS


def test_master_uzunluk_korunur():
    sr = 24000
    p = tone(sr, seconds=2.0)
    assert len(master(p, sr)) == len(p)


def test_stitch_master_zinciri():
    sr = 24000
    out = stitch([tone(sr, amp=0.1), tone(sr, amp=0.7)], sr, gaps_s=[0.4])
    assert abs(len(out) - int(sr * 2.4)) < 20
    assert float(np.max(np.abs(out))) <= 10 ** (-1 / 20) + 1e-3


# --- Referans yoğunlaştırma (enhance_ref) ----------------------------------------------

def test_enhance_ref_ic_sessizligi_kaplar():
    # 2 sn ton + 1.5 sn sessizlik + 2 sn ton → boşluk ~0.25 sn'ye iner
    sr = 24000
    gap = np.zeros(int(sr * 1.5), dtype=np.float32)
    audio = np.concatenate([tone(sr, 2.0), gap, tone(sr, 2.0)])
    out = enhance_ref(audio, sr, min_out_s=1.0)
    assert abs(len(out) / sr - 4.25) < 0.15
    assert out.dtype == np.float32
    assert not np.any(np.isnan(out))
    # konuşma (ton) bozulmaz: baş ve son bölgede genlik korunur
    assert np.max(np.abs(out[: sr // 2])) > 0.4
    assert np.max(np.abs(out[-sr // 2:])) > 0.4


def test_enhance_ref_kisa_bosluklara_dokunmaz():
    # Boşluk zaten ≤ max_gap_s ise kesme yapılmaz, uzunluk korunur
    sr = 24000
    gap = np.zeros(int(sr * 0.2), dtype=np.float32)
    audio = np.concatenate([tone(sr, 1.0), gap, tone(sr, 1.0)])
    out = enhance_ref(audio, sr, min_out_s=1.0)
    assert abs(len(out) - len(audio)) < sr * 0.05


def test_enhance_ref_tamamen_sessiz_girdi_cokmez():
    sr = 24000
    out = enhance_ref(np.zeros(sr * 2, dtype=np.float32), sr)
    assert isinstance(out, np.ndarray)
    assert not np.any(np.isnan(out))


def test_enhance_ref_kisa_sonuc_girdiye_doner():
    # Yoğunlaştırma min_out_s altına düşerse trim+normalize edilmiş girdi döner
    sr = 24000
    audio = tone(sr, 1.0)
    out = enhance_ref(audio, sr, min_out_s=3.0)
    assert len(out) >= sr * 0.9  # 1 sn'lik ton kırpılmadan korunur


# --- Kesik bitiş atma (drop_truncated_ending) ------------------------------------------

def test_kesik_son_segment_atilir():
    # Kayıt ses içinde bitiyor (sert kesme) → son segment atılır
    sr = 24000
    gap = np.zeros(sr // 2, dtype=np.float32)
    audio = np.concatenate([tone(sr, 1.0), gap, tone(sr, 0.3)])
    out = drop_truncated_ending(audio, sr, min_keep_s=0.5)
    assert len(out) <= int(sr * 1.05)          # kesik 0.3 sn'lik kuyruk gitti
    assert np.max(np.abs(out[-sr // 4:])) > 0.3  # kalan kısım ilk tonla bitiyor


def test_sessizlikle_biten_kayda_dokunulmaz():
    sr = 24000
    audio = np.concatenate([tone(sr, 1.0), np.zeros(sr // 2, dtype=np.float32)])
    out = drop_truncated_ending(audio, sr)
    assert len(out) == len(audio)


def test_kesik_bitis_min_sure_korumasi():
    # Atınca min_keep_s altına düşecekse dokunulmaz
    sr = 24000
    gap = np.zeros(sr // 4, dtype=np.float32)
    audio = np.concatenate([tone(sr, 0.5), gap, tone(sr, 0.5)])
    out = drop_truncated_ending(audio, sr, min_keep_s=2.0)
    assert len(out) == len(audio)


# --- Noktalamaya duyarlı duraksamalar --------------------------------------------------

def test_bosluk_paragraf():
    assert gap_after_chunk("Cümle bitti.", paragraph_break=True) == 0.80


def test_bosluk_soru_unlem():
    assert gap_after_chunk("Geliyor musun?", False) == 0.55
    assert gap_after_chunk("Harika!", False) == 0.55
    assert gap_after_chunk('Sordu: "Neden?"', False) == 0.55  # tırnak soyulur


def test_bosluk_duz_cumle():
    assert gap_after_chunk("Bugün hava güzel.", False) == 0.40


def test_bosluk_cumle_ici_bolme():
    # Uzun cümleden virgülle kırılan parça — kısa duraksama
    assert gap_after_chunk("madde bir hakkında açıklama,", False) == 0.28
