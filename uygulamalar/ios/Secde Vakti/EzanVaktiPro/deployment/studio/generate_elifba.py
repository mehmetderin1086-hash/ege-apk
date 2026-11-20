"""Bundle reproducible neural letter-name examples for offline Elif Ba practice."""
import json, pathlib, re, time, urllib.request, urllib.error, subprocess
root = pathlib.Path(__file__).resolve().parents[2]
out = root/'Sekine/Resources/ElifBaAudio'; out.mkdir(exist_ok=True)
source = (root/'Sekine/Features/LearnQuran/ElifBaView.swift').read_text()
letters = re.findall(r'\.init\(id: "([^"]+)", arabic: "([^"]+)", name: "([^"]+)", spokenName: "([^"]+)"', source)
assert len(letters)==28
manifest=[]
for key, arabic, name, spoken in letters:
    dest=out/(key+'.mp3')
    if not dest.exists():
        req=urllib.request.Request('https://xn--cumhuriyetanadolulisesiktphanesi-vmdb.com.tr/secde-studio/speech',data=json.dumps({'voice':'arabic','text':spoken}).encode(),headers={'Content-Type':'application/json'})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req,timeout=240) as r: data=r.read()
                if len(data)<1000 or not (data[:3]==b'ID3' or data[0]==255): raise ValueError('not MP3')
                dest.write_bytes(data);break
            except urllib.error.HTTPError as e:
                if e.code not in (429,503) or attempt==3:raise
                time.sleep(10)
    info=subprocess.check_output(['/usr/bin/afinfo',str(dest)],text=True)
    duration=float(re.search(r'estimated duration:\s*([\d.]+)',info).group(1))
    assert 0.1<duration<30
    manifest.append({'id':key,'letter':arabic,'name':name,'spokenText':spoken,'voice':'ar-SA-HamedNeural','synthetic':True,'durationSeconds':duration})
    print(key,round(duration,2),flush=True)
(out/'sources.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
