"""Mac'te motoru JavaScriptCore'un JIT'siz kipiyle dener (telefondaki koşula en yakın)."""
import json, os, subprocess, sys, tempfile, time
sys.path[:0] = [os.path.expanduser('~/Developer/kepce/python'), os.path.expanduser('~/Developer/.build/kepce-deps/src')]
import kepce_motor

JSC = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc'
times = []

def evaluate(script):
    with tempfile.TemporaryDirectory() as d:
        a, b = os.path.join(d, 'a.js'), os.path.join(d, 'b.js')
        open(a, 'w').write(script)
        open(b, 'w').write('print(__kepceOut.join("\\n"));')
        t = time.time()
        out = subprocess.run([JSC, '--useJIT=false', a, b], capture_output=True, text=True)
        times.append(round(time.time() - t, 2))
        if out.returncode:
            raise RuntimeError(out.stderr[-500:] or out.stdout[-500:])
        return out.stdout

kepce_motor.set_evaluator(evaluate)
kepce_motor.configure(os.path.expanduser('~/Developer/.build/kepce-deps/cache'))
print(kepce_motor.version())
url = sys.argv[1] if len(sys.argv) > 1 else 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'
t = time.time()
r = json.loads(kepce_motor.extract(url, json.dumps({'playlist': '--list' in sys.argv, 'flat': '--list' in sys.argv, 'clients': os.environ.get('KC','').split(',') if os.environ.get('KC') else None})))
print('süre', round(time.time() - t, 1), 'jsc', times)
if r['kind'] == 'error':
    print(r['error']); print('\n'.join(r['log'])); print(r['trace'][-1500:]); sys.exit(1)
if r['kind'] == 'playlist':
    print(r['title'], len(r['entries'])); [print(e) for e in r['entries'][:5]]; sys.exit()
print(r['title'], r.get('duration'), len(r['formats']))
for f in r['formats']:
    print(f['format_id'], f.get('ext'), f.get('vcodec'), f.get('acodec'), f.get('height'), f.get('filesize') or f.get('filesize_approx'), f.get('protocol'), 'frag' if f.get('fragments') else '')
print('subs', list(r['subtitles'])[:5], list(r['automatic_captions'])[:5])
print('\n'.join(r['log'][-12:]))
