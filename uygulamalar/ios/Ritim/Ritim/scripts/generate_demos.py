#!/usr/bin/env python3
"""Generate three original, deterministic 32-second instrumental demos.

No third-party samples or recordings. Re-run with Python 3 and ffmpeg.
"""
import array
import math
import pathlib
import shutil
import subprocess
import tempfile
import wave

ROOT = pathlib.Path(__file__).resolve().parents[1]
RATE = 22050
SECONDS = 32
FFMPEG = shutil.which('ffmpeg') or str(pathlib.Path.home() / '.local/bin/ffmpeg')

def frequency(note):
    return 440 * 2 ** ((note - 69) / 12)

def render(name, root, beat):
    samples = array.array('h')
    progressions = [[0, 3, 7, 10], [-4, 0, 3, 7], [-2, 2, 5, 9], [-5, 0, 2, 7]]
    for i in range(RATE * SECONDS):
        t = i / RATE
        chord = progressions[int(t / 8) % 4]
        fade = min(1, t / 1.5, (SECONDS - t) / 3)
        phase = (t % beat) / beat
        kick = math.sin(2 * math.pi * (45 * t + 5 * (1 - math.exp(-phase * 18)))) * math.exp(-phase * 17) * .10
        bass = math.sin(2 * math.pi * frequency(root - 12 + chord[0]) * t) * (.08 + .025 * math.cos(t))
        left, right = kick + bass, kick + bass
        for j, interval in enumerate(chord):
            f = frequency(root + interval)
            envelope = .055 * (.8 + .2 * math.sin(t * .7 + j))
            left += envelope * math.sin(2 * math.pi * f * t)
            right += envelope * math.sin(2 * math.pi * f * 1.001 * t + .25)
        step = int(t / (beat / 2))
        note = chord[step % 4] + 12 + root
        arp_age = t % (beat / 2)
        pluck = .06 * math.exp(-arp_age * 8) * math.sin(2 * math.pi * frequency(note) * t)
        left += pluck * (.7 + .3 * math.sin(t)); right += pluck * (.7 - .3 * math.sin(t))
        samples.extend([int(max(-1, min(1, left * fade)) * 32767), int(max(-1, min(1, right * fade)) * 32767)])
    with tempfile.TemporaryDirectory() as tmp:
        wav = pathlib.Path(tmp) / 'demo.wav'
        with wave.open(str(wav), 'wb') as f:
            f.setnchannels(2); f.setsampwidth(2); f.setframerate(RATE); f.writeframes(samples.tobytes())
        out = ROOT / 'Ritim/Resources' / (name + '.m4a')
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(wav), '-c:a', 'aac', '-b:a', '128k', '-metadata', 'artist=Ritim Studio', str(out)], check=True)
        print(out.name, out.stat().st_size)

if __name__ == '__main__':
    for spec in [('gece-yolu', 48, .5), ('kiyi', 53, .6666667), ('yorunge', 55, .4)]:
        render(*spec)
