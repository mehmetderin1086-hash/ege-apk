"""Secde Vakti speech gateway. Credentials remain in the server environment."""
import hashlib, json, os, sqlite3, threading, time, urllib.request, urllib.error
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.sax.saxutils import escape

CACHE = Path(os.environ.get('STUDIO_CACHE', '/srv/apps/secde-studio/cache'))
CACHE.mkdir(parents=True, exist_ok=True)
VOICES = {'aydin': 'tr-TR-Aydın:MAI-Voice-2-Flash', 'elif': 'tr-TR-Elif:MAI-Voice-2-Flash', 'arabic': 'ar-SA-HamedNeural'}
LOCK = threading.Lock()
WAITERS = threading.BoundedSemaphore(8)

def synthesize(text, voice):
    key = hashlib.sha256(('v1|' + voice + '|' + text).encode()).hexdigest()
    path = CACHE / (key + '.mp3')
    if path.exists(): return path.read_bytes()
    locale = 'ar-SA' if voice == 'arabic' else 'tr-TR'
    words = escape(text)
    if voice != 'arabic': words = '<mstts:express-as style="serious">' + words + '</mstts:express-as>'
    body = f'<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="{locale}"><voice name="{VOICES[voice]}"><prosody rate="-5%">{words}</prosody></voice></speak>'
    url = 'https://' + os.environ['AZURE_SPEECH_REGION'] + '.tts.speech.microsoft.com/cognitiveservices/v1'
    req = urllib.request.Request(url, data=body.encode(), headers={'Ocp-Apim-Subscription-Key': os.environ['AZURE_SPEECH_KEY'], 'Content-Type': 'application/ssml+xml', 'X-Microsoft-OutputFormat': 'audio-24khz-160kbitrate-mono-mp3', 'User-Agent': 'SecdeVakti'})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r: audio = r.read()
            if len(audio) < 1000 or not (audio.startswith(b'ID3') or audio[0] == 255): raise ValueError('invalid audio')
            files = sorted(CACHE.glob('*.mp3'), key=lambda p:p.stat().st_mtime)
            size = sum(p.stat().st_size for p in files)
            for old in files:
                if size + len(audio) <= 512 * 1024 * 1024: break
                size -= old.stat().st_size
                old.unlink()
            temp = path.with_suffix('.tmp'); temp.write_bytes(audio); temp.replace(path)
            return audio
        except urllib.error.HTTPError as e:
            if e.code not in (429, 500, 502, 503) or attempt == 3: raise
            try: delay = min(30, max(1, int(e.headers.get('Retry-After', 2 ** attempt))))
            except ValueError: delay = 5
            time.sleep(delay)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass # Never log spoken content or credentials.
    def reply(self, status, data, kind='application/json'):
        self.send_response(status); self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(data)))
        if status == 429: self.send_header('Retry-After', '30')
        self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        self.reply(200 if self.path == '/health' else 404, b'{"service":"secde-studio","version":1}')
    def do_POST(self):
        if self.path != '/speech': return self.reply(404, b'{}')
        try:
            size = int(self.headers.get('Content-Length', '0'))
            if not 0 < size <= 12000: return self.reply(413, b'{}')
            value = json.loads(self.rfile.read(size))
            text, voice = value.get('text'), value.get('voice')
            if not isinstance(text, str) or not 1 <= len(text.strip()) <= 1200 or voice not in VOICES:
                return self.reply(400, b'{}')
            text = text.strip()
            if not WAITERS.acquire(blocking=False): return self.reply(429, b'{}')
            try:
                with LOCK:
                    # Persist daily cost limits; Caddy overwrites X-Real-IP.
                    client = hashlib.sha256(self.headers.get('X-Real-IP', self.client_address[0]).encode()).hexdigest()
                    day = time.strftime('%Y-%m-%d', time.gmtime())
                    with sqlite3.connect(CACHE / 'quota.sqlite') as db:
                        db.execute('CREATE TABLE IF NOT EXISTS quota(day TEXT, client TEXT, chars INTEGER, PRIMARY KEY(day,client))')
                        db.execute('DELETE FROM quota WHERE day < ?', (day,))
                        for who, limit in ((client, 30000), ('global', 200000)):
                            used = db.execute('SELECT chars FROM quota WHERE day=? AND client=?', (day,who)).fetchone()
                            if (used[0] if used else 0) + len(text) > limit: return self.reply(429, b'{}')
                        for who in (client, 'global'):
                            db.execute('INSERT INTO quota VALUES(?,?,?) ON CONFLICT(day,client) DO UPDATE SET chars=chars+excluded.chars', (day,who,len(text)))
                    audio = synthesize(text, voice)
                self.reply(200, audio, 'audio/mpeg')
            finally: WAITERS.release()
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception: self.reply(503, b'{"error":"speech_unavailable"}')

if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', 8796), Handler)
    server.timeout = 120
    server.serve_forever()
