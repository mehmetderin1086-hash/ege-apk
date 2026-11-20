"""Loopback-only fixed Python container runner; never executes model shell commands."""
import os,json,hmac,tempfile,subprocess,uuid,resource,shutil
from http.server import BaseHTTPRequestHandler,HTTPServer
import analysis_runner
TOKEN=os.environ['ASISTAN_RUNNER_TOKEN']
ROOT='/run/asistan-runner'
def limits(): resource.setrlimit(resource.RLIMIT_FSIZE,(1048576,1048576))
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def reply(self,code,value):
  raw=json.dumps(value).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
 def do_POST(self):
  if not hmac.compare_digest(self.headers.get('Authorization',''),'Bearer '+TOKEN):self.reply(401,{});return
  if self.path=='/analysis':
   try:
    size=int(self.headers.get('Content-Length','0'))
    if not 0<size<=36*1024*1024:raise ValueError()
    body=json.loads(self.rfile.read(size))
    self.reply(200,analysis_runner.calistir(body,ROOT))
   except (ValueError,KeyError,TypeError):self.reply(400,{'error':'Analiz girdisi veya çalışma ortamı geçersiz.'})
   except Exception:self.reply(503,{'error':'Analiz ortamı kullanılamıyor.'})
   return
  if self.path!='/run':self.reply(404,{});return
  try:
   size=int(self.headers.get('Content-Length','0'))
   if not 0<size<=100000:raise ValueError()
   code=json.loads(self.rfile.read(size))['code']
   if not isinstance(code,str) or len(code.encode())>64000:raise ValueError()
  except (ValueError,KeyError,TypeError):self.reply(400,{'error':'Invalid code'});return
  folder=tempfile.mkdtemp(dir=ROOT);os.chmod(folder,0o755)
  path=os.path.join(folder,'main.py');open(path,'w').write(code);os.chmod(path,0o444)
  name='asistan-'+uuid.uuid4().hex
  cmd=['/usr/bin/docker','run','--rm','--name',name,'--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','65534:65534','--memory','128m','--memory-swap','128m','--cpus','0.5','--pids-limit','32','--log-driver','none','--tmpfs','/tmp:rw,noexec,nosuid,size=16m','--mount','type=bind,src='+folder+',dst=/work,readonly','python:3.12-alpine','python','-I','/work/main.py']
  try:
   with tempfile.TemporaryFile() as log:
    try:
     result=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=25,env={'PATH':'/usr/bin:/bin'},preexec_fn=limits)
     status=result.returncode
    except subprocess.TimeoutExpired:status=124
    log.seek(0);output=log.read(16000).decode(errors='replace')
   self.reply(200,{'exit_code':status,'output':output,'timeout':status==124})
  except Exception:self.reply(500,{'error':'Sandbox could not execute'})
  finally:
   subprocess.run(['/usr/bin/docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
   shutil.rmtree(folder,ignore_errors=True)
if __name__=='__main__':HTTPServer(('127.0.0.1',8053),Handler).serve_forever()
