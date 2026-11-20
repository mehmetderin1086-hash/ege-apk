#!/bin/zsh
# Asistan için OpenAI ses dökümü aktarıcısını VPS'e kurar (anahtar sunucuda kalır).
# Kullanım (Mac'te):  ~/Developer/asistan/vps/whisper-relay-kur.sh
# Geri alma (VPS'te): bash /srv/apps/cliproxy/GERI-AL-whisper-relay-20261014.txt
set -e
ssh root@82.29.179.131 'set -e; mkdir -p /srv/apps/whisper-relay && cd /srv/apps/whisper-relay
cat > relay.py <<'"'"'EOF'"'"'
"""OpenAI ses dökümü aktarıcısı: anahtar sunucuda kalır; uygulama Caddy'"'"'nin denetlediği X-Personal-Token ile gelir.
Varsayılan model gpt-4o-transcribe (Türkçe'"'"'de whisper-1'"'"'den daha doğru); reddedilirse whisper-1'"'"'e düşer."""
import os
import httpx
from fastapi import FastAPI, File, Form, HTTPException, UploadFile

app = FastAPI()
KEY = os.environ["OPENAI_IMAGE_FALLBACK_KEY"]
UC = "https://api.openai.com/v1/audio/transcriptions"
EN_BUYUK = 25 * 1024 * 1024

@app.get("/health")
async def health():
    return {"ok": True, "servis": "whisper-relay"}

@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...), model: str = Form("gpt-4o-transcribe"),
                     language: str = Form("tr"), prompt: str | None = Form(None)):
    veri = await file.read()
    if not veri:
        raise HTTPException(400, "boş ses")
    if len(veri) > EN_BUYUK:
        raise HTTPException(413, "ses 25 MB sınırını aşıyor")
    son = None
    async with httpx.AsyncClient(timeout=60) as c:
        for m in dict.fromkeys([model, "whisper-1"]):
            alanlar = {"model": m, "language": language, "response_format": "json"}
            if prompt:
                alanlar["prompt"] = prompt[:800]
            r = await c.post(UC, headers={"Authorization": f"Bearer {KEY}"}, data=alanlar,
                             files={"file": (file.filename or "ses.wav", veri, file.content_type or "audio/wav")})
            if r.status_code == 200:
                j = r.json(); j["model"] = m
                return j
            son = r
            if r.status_code not in (400, 404):
                break
    raise HTTPException(son.status_code if son else 502, (son.text[:500] if son else "yanıt yok"))
EOF
cat > /etc/systemd/system/whisper-relay.service <<'"'"'EOF'"'"'
[Unit]
Description=Whisper relay (OpenAI ses dökümü aktarıcısı, 8051)
After=network.target

[Service]
WorkingDirectory=/srv/apps/whisper-relay
EnvironmentFile=/srv/apps/cliproxy/image-fallback.env
ExecStart=/usr/bin/python3 -m uvicorn relay:app --host 127.0.0.1 --port 8051
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now whisper-relay >/dev/null 2>&1; sleep 2; echo "servis: $(systemctl is-active whisper-relay)"; curl -s http://127.0.0.1:8051/health; echo
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-whisper-relay-20261014
python3 - <<'"'"'EOF'"'"'
p="/etc/caddy/Caddyfile"; s=open(p).read()
blok = """                # whisper-relay (14 Eki 2026): Asistan uygulaması Türkçe ses dökümünü OpenAI'"'"'den bu aktarıcıyla alır
                # (/dersdas/claude/v1/whisper/* → 8051); anahtar sunucuda. Geri alma: GERI-AL-whisper-relay-20261014.txt
                handle /v1/whisper/* {
                    uri strip_prefix /v1/whisper
                    request_body {
                        max_size 30MB
                    }
                    reverse_proxy 127.0.0.1:8051 {
                        transport http {
                            response_header_timeout 90s
                        }
                        header_up -X-Personal-Token
                    }
                }
"""
anahtar = "                handle /v1/kaynak/* {"
if "/v1/whisper/*" in s:
    print("Caddy: zaten ekli")
else:
    assert anahtar in s, "Caddyfile düzeni beklenenden farklı"
    s = s.replace(anahtar, blok + anahtar, 1); open(p,"w").write(s); print("Caddy: eklendi")
EOF
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile 2>&1 | tail -1 && systemctl reload caddy && echo "Caddy yeniden yüklendi"
echo "systemctl disable --now whisper-relay; rm /etc/systemd/system/whisper-relay.service; cp /etc/caddy/Caddyfile.bak-whisper-relay-20261014 /etc/caddy/Caddyfile; systemctl reload caddy; rm -rf /srv/apps/whisper-relay" > /srv/apps/cliproxy/GERI-AL-whisper-relay-20261014.txt
echo KURULDU'
