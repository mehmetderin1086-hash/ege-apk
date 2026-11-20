import json,urllib.request
from pathlib import Path
token=Path('/etc/asistan-runner.env').read_text().strip().split('=',1)[1]
code="""import os,socket
assert sum([1,2,3]) == 6
assert not os.path.exists('/etc/asistan-jobs.env')
assert not os.path.exists('/var/run/docker.sock')
assert not any(x in os.environ for x in ('ASISTAN_TOKEN','ASISTAN_PROXY_KEY','ASISTAN_RUNNER_TOKEN','OPENAI_IMAGE_FALLBACK_KEY'))
s=socket.socket();s.settimeout(1)
try:
 s.connect(('1.1.1.1',443))
 raise AssertionError('network should be blocked')
except OSError:pass
print('Arithmetic, secret isolation, Docker socket isolation and network isolation passed')
"""
req=urllib.request.Request('http://127.0.0.1:8053/run',data=json.dumps({'code':code}).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+token})
with urllib.request.urlopen(req,timeout=40) as r:print(r.read().decode())
