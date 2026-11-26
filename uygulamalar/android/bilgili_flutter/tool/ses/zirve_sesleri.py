#!/usr/bin/env python3
"""Zirve Merdiveni için özgün müzik ve ses efektleri üretir.

Bütün sesler bu betikte sentezlenir (hazır kayıt kullanılmaz). Döngü müzikleri
dairesel efektlerle üretildiği için başı ve sonu boşluksuz birleşir.
Çıktı: android/app/src/main/res/raw/zirve_*.ogg

Kullanım: python3 tool/ses/zirve_sesleri.py
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
RNG = np.random.default_rng(20261122)
CIKTI = os.path.join(os.path.dirname(__file__), '..', '..', 'android', 'app', 'src', 'main', 'res', 'raw')


def nota(ad):
    """'D3', 'F#4' gibi bir nota adını frekansa çevirir."""
    adlar = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
             'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
    isim, oktav = ad[:-1], int(ad[-1])
    yari = adlar[isim] + (oktav + 1) * 12
    return 440.0 * 2 ** ((yari - 69) / 12)


def zaman(sure):
    return np.arange(int(SR * sure)) / SR


def zarf(n, atak=0.01, birak=0.2, sus=1.0):
    e = np.full(n, sus)
    a = max(1, int(SR * atak))
    r = max(1, int(SR * birak))
    e[:a] = np.linspace(0, sus, a)
    if r < n:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def testere(f, t, harmonik=12):
    """Bant sınırlı testere dişi: yumuşak, yaylı benzeri ton."""
    s = np.zeros_like(t)
    for k in range(1, harmonik + 1):
        if f * k > SR / 2.2:
            break
        s += np.sin(2 * np.pi * f * k * t) / k
    return s


def ped(frekanslar, sure, ses=0.18, harmonik=8, detune=0.004):
    t = zaman(sure)
    s = np.zeros_like(t)
    for f in frekanslar:
        for d in (-detune, 0, detune):
            s += testere(f * (1 + d), t + RNG.random() * 0.01, harmonik)
    s /= max(1, len(frekanslar) * 3)
    return s * ses * zarf(len(t), atak=0.35, birak=0.5)


def pluck(f, sure, ses=0.25):
    t = zaman(sure)
    s = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(4 * np.pi * f * t) + 0.15 * np.sin(6 * np.pi * f * t)
    return s * ses * np.exp(-t * 6)


def davul(sure=0.9, f0=110, f1=45, ses=0.8):
    t = zaman(sure)
    f = f1 + (f0 - f1) * np.exp(-t * 18)
    faz = 2 * np.pi * np.cumsum(f) / SR
    govde = np.sin(faz) * np.exp(-t * 4.5)
    gurultu = RNG.standard_normal(len(t)) * np.exp(-t * 30) * 0.25
    return (govde + gurultu) * ses


def kalp(sure=0.5, ses=0.7):
    t = zaman(sure)
    f = 40 + 30 * np.exp(-t * 25)
    faz = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(faz) * np.exp(-t * 14) * ses


def tik(ses=0.12):
    t = zaman(0.05)
    return np.sin(2 * np.pi * 3200 * t) * np.exp(-t * 120) * ses


def huu(sure, f0=300, f1=4000, ses=0.25):
    """Gürültü süpürmesi (whoosh)."""
    t = zaman(sure)
    g = RNG.standard_normal(len(t))
    # Basit tek kutuplu alçak geçiren süzgeç, kesim frekansı zamanla değişir.
    kesim = f0 * (f1 / f0) ** (t / sure)
    a = np.exp(-2 * np.pi * kesim / SR)
    y = np.zeros_like(g)
    for i in range(1, len(g)):
        y[i] = (1 - a[i]) * g[i] + a[i] * y[i - 1]
    return y / (np.max(np.abs(y)) + 1e-9) * ses * zarf(len(t), atak=sure * 0.6, birak=sure * 0.4)


def ekle(hedef, parca, saniye, dairesel=False):
    i = int(saniye * SR)
    n = len(parca)
    if dairesel:
        idx = (np.arange(n) + i) % len(hedef)
        np.add.at(hedef, idx, parca)
    else:
        son = min(len(hedef), i + n)
        hedef[i:son] += parca[: son - i]


def yanki(s, gecikme=0.32, geri=0.35, tekrar=5, dairesel=False):
    out = s.copy()
    d = int(gecikme * SR)
    for k in range(1, tekrar + 1):
        if dairesel:
            out += np.roll(s, d * k) * geri ** k
        else:
            kay = np.zeros_like(s)
            if d * k < len(s):
                kay[d * k:] = s[: len(s) - d * k]
            out += kay * geri ** k
    return out


def normalle(s, tepe=0.89):
    return s / (np.max(np.abs(s)) + 1e-9) * tepe


def yaz(ad, s, dongu=False):
    os.makedirs(CIKTI, exist_ok=True)
    s = normalle(s)
    if not dongu:
        # Tek seferlik efektlerin sonu tıklamasın diye kısa bir sönümleme.
        n = int(SR * 0.12)
        s[-n:] *= np.linspace(1, 0, n) ** 2
        s[:64] *= np.linspace(0, 1, 64)
    sag = np.roll(s, 37) if dongu else np.concatenate([np.zeros(37), s[:-37]])
    stereo = np.stack([s, sag], axis=1)
    veri = (stereo * 32767).astype('<i2')
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, ad + '.wav')
        with wave.open(wav, 'wb') as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(veri.tobytes())
        hedef = os.path.join(CIKTI, ad + '.ogg')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '4', hedef], check=True)
    print(ad, f'{len(s) / SR:.1f} sn', os.path.getsize(hedef) // 1024, 'KB')


# --- Müzik döngüleri ---------------------------------------------------------

def giris():
    """Açılış teması: Re minör, 100 vuruş/dk, 8 ölçü."""
    vurus = 60 / 100
    olcu = vurus * 4
    sure = olcu * 8
    s = np.zeros(int(SR * sure))
    akorlar = [['D3', 'F3', 'A3'], ['Bb2', 'D3', 'F3'], ['F2', 'A2', 'C3'], ['C3', 'E3', 'G3'],
               ['D3', 'F3', 'A3'], ['G2', 'Bb2', 'D3'], ['A2', 'C#3', 'E3'], ['A2', 'C#3', 'E3']]
    for i, a in enumerate(akorlar):
        ekle(s, ped([nota(x) for x in a] + [nota(a[0][:-1] + '2')], olcu + 0.4, ses=0.35), i * olcu, True)
        ekle(s, davul(f0=90, f1=40, ses=0.9), i * olcu, True)
        # Yükselen arpej
        notalar = [nota(x) * 2 for x in a] + [nota(a[0]) * 4]
        for k in range(8):
            ekle(s, pluck(notalar[k % 4], 0.5, ses=0.16), i * olcu + k * vurus / 2, True)
    # Melodi
    melodi = [('A4', 0, 2), ('D5', 2, 2), ('F5', 4, 1.5), ('E5', 5.5, 0.5), ('D5', 6, 2),
              ('C5', 8, 2), ('A4', 10, 2), ('G4', 12, 2), ('A4', 14, 2),
              ('F5', 16, 2), ('A5', 18, 2), ('G5', 20, 1.5), ('F5', 21.5, 0.5), ('E5', 22, 2),
              ('D5', 24, 2), ('F5', 26, 2), ('E5', 28, 4)]
    for n, bas, uz in melodi:
        t = zaman(uz * vurus + 0.3)
        f = nota(n)
        ton = (testere(f, t, 6) * 0.5 + np.sin(2 * np.pi * f * t)) * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))
        ekle(s, ton * 0.12 * zarf(len(t), atak=0.05, birak=0.25), bas * vurus, True)
    return yanki(s, 0.36, 0.3, 4, dairesel=True)


def gerilim(seviye):
    """Soru arkası gerilim döngüsü. Seviye büyüdükçe tempo ve yoğunluk artar."""
    bpm = [92, 108, 72][seviye]
    vurus = 60 / bpm
    olcu = vurus * 4
    sure = olcu * 4
    s = np.zeros(int(SR * sure))
    kok = ['D2', 'E2', 'C2'][seviye]
    ust = [['D3', 'A3', 'F4'], ['E3', 'B3', 'G4'], ['C3', 'G3', 'Eb4']][seviye]
    ekle(s, ped([nota(x) for x in ust], sure + 0.6, ses=0.22 + 0.06 * seviye, harmonik=6), 0, True)
    for b in range(16):
        zaman_ = b * vurus
        if seviye == 0:
            ekle(s, pluck(nota(kok), 0.6, ses=0.35), zaman_, True)
            ekle(s, tik(0.06), zaman_ + vurus / 2, True)
        elif seviye == 1:
            for k in range(2):
                ekle(s, pluck(nota(kok) * (2 if k else 1), 0.35, ses=0.32), zaman_ + k * vurus / 2, True)
            ekle(s, tik(0.08), zaman_, True)
        else:
            ekle(s, kalp(ses=0.9), zaman_, True)
            ekle(s, kalp(ses=0.6), zaman_ + 0.22, True)
            if b % 4 == 3:
                ekle(s, pluck(nota('Eb5'), 0.8, ses=0.08), zaman_, True)
    if seviye >= 1:
        t = zaman(sure)
        titrek = np.sin(2 * np.pi * nota(ust[-1]) * 2 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * t))
        s += titrek * 0.03 * seviye
    return yanki(s, vurus * 0.75, 0.25, 3, dairesel=True)


# --- Efektler ----------------------------------------------------------------

def sec():
    """Kesin cevap: alçak vuruş ve yükselen bekleyiş tonu."""
    sure = 2.6
    s = np.zeros(int(SR * sure))
    ekle(s, davul(1.2, 70, 35, 1.0), 0)
    t = zaman(sure)
    f = nota('A3') * (1 + 0.06 * t / sure)
    faz = 2 * np.pi * np.cumsum(f) / SR
    s += (np.sin(faz) + 0.5 * np.sin(2 * faz) + 0.3 * np.sin(1.5 * faz)) * 0.18 * zarf(len(t), atak=0.4, birak=0.6)
    return yanki(s, 0.25, 0.3, 3)


def dogru():
    sure = 2.2
    s = np.zeros(int(SR * sure))
    for i, n in enumerate(['D4', 'F#4', 'A4', 'D5']):
        ekle(s, pluck(nota(n), 1.6, ses=0.4), i * 0.09)
    ekle(s, ped([nota(x) for x in ['D4', 'F#4', 'A4', 'D5']], 1.8, ses=0.5, harmonik=10), 0.36)
    t = zaman(1.4)
    pirilti = sum(np.sin(2 * np.pi * nota(n) * 4 * t) for n in ['D4', 'A4']) * np.exp(-t * 3) * 0.05
    ekle(s, pirilti, 0.4)
    ekle(s, davul(0.8, 140, 60, 0.5), 0.36)
    return yanki(s, 0.22, 0.28, 3)


def yanlis():
    sure = 2.2
    s = np.zeros(int(SR * sure))
    ekle(s, davul(1.4, 60, 28, 1.0), 0)
    for i, (a, b) in enumerate([('A3', 'Eb4'), ('F3', 'B3')]):
        t = zaman(1.0)
        ton = (testere(nota(a), t, 8) + testere(nota(b), t, 8)) * 0.18 * zarf(len(t), atak=0.02, birak=0.5)
        ekle(s, ton, 0.05 + i * 0.45)
    return yanki(s, 0.3, 0.25, 3)


def baraj():
    sure = 3.6
    s = np.zeros(int(SR * sure))
    sira = [(['D4', 'F#4', 'A4'], 0), (['G4', 'B4', 'D5'], 0.35), (['A4', 'C#5', 'E5'], 0.7), (['D5', 'F#5', 'A5', 'D4'], 1.05)]
    for akor, bas in sira:
        ekle(s, ped([nota(x) for x in akor], 2.4 if bas > 1 else 0.6, ses=0.55, harmonik=10), bas)
        ekle(s, davul(0.7, 120, 50, 0.6), bas)
    for i in range(12):
        ekle(s, pluck(nota(['D6', 'A5', 'F#6', 'D6'][i % 4]), 0.4, ses=0.08), 1.05 + i * 0.08)
    return yanki(s, 0.28, 0.3, 4)


def zafer():
    sure = 6.0
    s = np.zeros(int(SR * sure))
    sira = [(['D4', 'F#4', 'A4'], 0, 0.5), (['B3', 'D4', 'G4'], 0.5, 0.5), (['C#4', 'E4', 'A4'], 1.0, 0.5),
            (['D4', 'F#4', 'A4', 'D5'], 1.5, 0.4), (['G4', 'B4', 'D5'], 1.9, 0.4), (['A4', 'C#5', 'E5'], 2.3, 0.5),
            (['D4', 'F#4', 'A4', 'D5', 'F#5'], 2.8, 3.0)]
    for akor, bas, uz in sira:
        ekle(s, ped([nota(x) for x in akor] + [nota(akor[0][:-1] + '2')], uz + 0.3, ses=0.6, harmonik=12), bas)
        ekle(s, davul(0.9, 110, 45, 0.7), bas)
    for i in range(24):
        ekle(s, pluck(nota(['D6', 'F#6', 'A6', 'D7'][i % 4]), 0.5, ses=0.06), 2.8 + i * 0.07)
    return yanki(s, 0.33, 0.32, 5)


def joker():
    sure = 1.0
    s = np.zeros(int(SR * sure))
    ekle(s, huu(0.5, 400, 6000, 0.35), 0)
    for i, n in enumerate(['A5', 'D6', 'F#6']):
        ekle(s, pluck(nota(n), 0.5, ses=0.18), 0.45 + i * 0.06)
    return yanki(s, 0.18, 0.25, 2)


def soru():
    sure = 1.0
    s = np.zeros(int(SR * sure))
    ekle(s, huu(0.45, 200, 3000, 0.3), 0)
    ekle(s, davul(0.6, 100, 45, 0.6), 0.42)
    ekle(s, pluck(nota('D4'), 0.5, ses=0.2), 0.42)
    return yanki(s, 0.2, 0.2, 2)


def cekil():
    sure = 2.6
    s = np.zeros(int(SR * sure))
    ekle(s, ped([nota(x) for x in ['F3', 'A3', 'C4', 'F4']], 1.0, ses=0.4), 0)
    ekle(s, ped([nota(x) for x in ['D3', 'F3', 'A3', 'D4']], 1.6, ses=0.45), 0.9)
    return yanki(s, 0.3, 0.3, 3)


if __name__ == '__main__':
    yaz('zirve_giris', giris(), dongu=True)
    for i in range(3):
        yaz(f'zirve_gerilim_{i + 1}', gerilim(i), dongu=True)
    yaz('zirve_sec', sec())
    yaz('zirve_dogru', dogru())
    yaz('zirve_yanlis', yanlis())
    yaz('zirve_baraj', baraj())
    yaz('zirve_zafer', zafer())
    yaz('zirve_joker', joker())
    yaz('zirve_soru', soru())
    yaz('zirve_cekil', cekil())
