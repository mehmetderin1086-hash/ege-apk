import json,re,urllib.request
from pathlib import Path
s=Path('/etc/caddy/Caddyfile').read_text(); part=s[s.index('@claude path'):]
token=re.search(r'@app header X-Personal-Token\s+"?([^"\s]+)',part).group(1)
start=s.rfind('\n}',0,s.index('@claude path'));host=s[start+2:].strip().split('{')[0].strip().split()[0].rstrip(',')
body={'model':'claude-opus-5-5','max_tokens':512,'stream':False,'messages':[
 {'role':'user','content':"Barış Manço'dan Gülpembe şarkısını aç"},
 {'role':'assistant','content':[{'type':'thinking','thinking':'synthetic protocol test','signature':'opaque-test-signature'}, {'type':'tool_use','id':'call_music_test','name':'uygulamaAc','input':{'hedef':'https://open.spotify.com/search/Baris%20Manco%20Gulpembe'}}]},
 {'role':'user','content':[{'type':'tool_result','tool_use_id':'call_music_test','content':'Spotify arama ekranı açıldı. Şarkının çalmaya başladığı doğrulanmadı.'}]}]}
r=urllib.request.Request('https://'+host+'/dersdas/claude/v1/messages',data=json.dumps(body).encode(),headers={'X-Personal-Token':token,'Content-Type':'application/json'})
try:
 with urllib.request.urlopen(r,timeout=100) as response:
  d=json.load(response)
  print(json.dumps({'http':response.status,'stop_reason':d.get('stop_reason'),'text':[b.get('text') for b in d.get('content',[]) if b.get('type')=='text']},ensure_ascii=False))
except urllib.error.HTTPError as e:
 print(json.dumps({'http':e.code,'error':json.loads(e.read()).get('error',{}).get('message','')},ensure_ascii=False))
