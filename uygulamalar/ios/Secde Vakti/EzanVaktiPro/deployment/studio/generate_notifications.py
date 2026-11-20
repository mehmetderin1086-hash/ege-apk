"""Generate notification CAFs through the deployed studio voice (no embedded key)."""
import json, pathlib, urllib.request, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parents[2]
sounds = root / 'Sekine/Resources/Sounds'
manifest = json.loads((sounds / 'NotificationSoundSources.json').read_text())
endpoint = 'https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/secde-studio/speech'
for identifier, title, text in manifest['reminders']:
    request = urllib.request.Request(endpoint, data=json.dumps({'voice':'aydin', 'text':text}).encode(), headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request, timeout=240) as response: data = response.read()
    with tempfile.TemporaryDirectory() as tmp:
        mp3 = pathlib.Path(tmp) / 'source.mp3'; mp3.write_bytes(data)
        caf = pathlib.Path(tmp) / 'sound.caf'
        subprocess.run(['/usr/bin/afconvert', '-f', 'caff', '-d', 'LEI16@24000', str(mp3), str(caf)], check=True)
        # iOS custom notification sounds must be strictly shorter than 30 seconds.
        info = subprocess.check_output(['/usr/bin/afinfo', str(caf)], text=True)
        import re
        duration = float(re.search(r'estimated duration:\s*([\d.]+)', info).group(1))
        if duration >= 29: raise RuntimeError(f'{identifier}: {duration}s exceeds notification budget')
        (sounds / ('notify-' + identifier + '.caf')).write_bytes(caf.read_bytes())
        print(identifier, round(duration, 2), 's', flush=True)
manifest['spokenVoice'] = 'Azure tr-TR-Aydın:MAI-Voice-2-Flash; AI-generated studio narration; 24 kHz PCM CAF'
(sounds / 'NotificationSoundSources.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
