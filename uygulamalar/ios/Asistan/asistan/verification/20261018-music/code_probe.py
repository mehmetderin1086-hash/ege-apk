import urllib.request, urllib.error, json, re, uuid, time
from pathlib import Path
s=Path('/etc/caddy/Caddyfile').read_text()
token=re.search(r'@app header X-Personal-Token\s+"?([^"\s]+)',s).group(1)
start=s.rfind('\n}',0,s.index('@claude path'))
host=s[start+2:].strip().split('{')[0].strip().split()[0].rstrip(',')
print('gateway host',host,flush=True)
base='https://'+host+'/dersdas/claude/v1/asistan/jobs'
for url in ['http://127.0.0.1:8052/v1/asistan/jobs',base]:
    for auth in [False,True]:
        try:
            req=urllib.request.Request(url,headers={'X-Personal-Token':token} if auth else {})
            with urllib.request.urlopen(req,timeout=20) as r:print('auth',auth,'status',r.status,'jobs',len(json.load(r)),flush=True)
        except urllib.error.HTTPError as e:print('auth',auth,'status',e.code,flush=True)
for kind,prompt in [('code', 'Python ile bir listedeki sayıların toplamını hesaplayan fonksiyon yaz; [1,2,3] için sonucu test et ve ekrana yazdır.')]:
    req=urllib.request.Request(base,data=json.dumps({'id':str(uuid.uuid4()),'prompt':prompt,'kind':kind}).encode(),headers={'X-Personal-Token':token,'Content-Type':'application/json'})
    with urllib.request.urlopen(req) as r:j=json.load(r)
    print('test job',j['id'],j['status'],flush=True)
    for _ in range(55):
        time.sleep(5)
        with urllib.request.urlopen(urllib.request.Request(base,headers={'X-Personal-Token':token})) as r:items=json.load(r)
        found=next(x for x in items if x['id']==j['id'])
        if found['status'] not in ('queued','running'):
            print(json.dumps(found,ensure_ascii=False),flush=True);break
