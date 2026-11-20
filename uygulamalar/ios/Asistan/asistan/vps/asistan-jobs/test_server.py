import tempfile, unittest, uuid, os
import server
class JobsTest(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();server.DB=os.path.join(self.t.name,'test.db');server.init()
    def tearDown(self): self.t.cleanup()
    def job(self): return {'id':str(uuid.uuid4()),'prompt':'Bir metin yaz','kind':'text'}
    def test_idempotency_and_collision(self):
        p=self.job(); self.assertEqual(server.submit(p),server.submit(p)); p['prompt']='farklı'
        with self.assertRaises(ValueError): server.submit(p)
    def test_cancelled_not_restart(self):
        j=server.submit(self.job()); self.assertEqual(server.cancel(j['id'])['status'],'cancelled');server.init()
        self.assertEqual(server.cancel(j['id'])['status'],'cancelled')
    def test_restart_and_limits(self):
        j=server.submit(self.job())
        with server.connect() as db: db.execute("UPDATE jobs SET status='running'")
        server.init()
        with server.connect() as db: self.assertEqual(db.execute('SELECT status FROM jobs').fetchone()[0],'failed')
        for _ in range(10):server.submit(self.job())
        with self.assertRaises(ValueError):server.submit(self.job())
    def test_research_requires_tool_and_citations(self):
        d={'status':'completed','output':[{'type':'message','content':[{'text':'Yanıt','annotations':[{'url':'https://example.com/cited'}]}]}]}
        with self.assertRaises(ValueError): server.parse_output(d,'research')
        d['output'].append({'type':'web_search_call','status':'completed','action':{'sources':[{'url':'https://example.com/uncited'}]}})
        self.assertIn('/cited',server.parse_output(d,'research'))
        self.assertNotIn('/uncited',server.parse_output(d,'research'))
        d['status']='incomplete'
        with self.assertRaises(ValueError): server.parse_output(d,'research')
    def test_no_shell_kind(self):
        p=self.job();p['kind']='shell'
        with self.assertRaises(ValueError):server.submit(p)
    def test_workspace_azure_catalog_has_no_unrelated_network_wait(self):
        from unittest.mock import patch
        with patch.object(server,'speech_request',side_effect=AssertionError('Ağ isteği yapılmamalı')):
            voices=server.voice_catalog(azure_only=True)
        self.assertTrue(voices)
        self.assertTrue(all(v['engine']=='azure' for v in voices))
    def test_workspace_web_capability_failure_never_calls_paid_api(self):
        import io
        from urllib.error import HTTPError
        from unittest.mock import patch
        messages = ('unsupported_capability', 'native reasoning options require the matching provider',
                    "'openai-api' sağlayıcısı 'tool_choice' yeteneğini desteklemiyor")
        for message in messages:
            for key in ('', 'yalniz-test-anahtari'):
                with self.subTest(message=message, key_present=bool(key)):
                    error=HTTPError('test',400,'bad request',{},io.BytesIO(message.encode()))
                    with patch.dict(os.environ,{'OPENAI_IMAGE_FALLBACK_KEY':key}), patch.object(server,'urlopen',side_effect=error) as call:
                        with self.assertRaises(server.workspace.Hata) as result:
                            server.generate_text({'kind':'research','prompt':'Test','allow_paid':False},'gpt-6.1-sol')
                    self.assertEqual(result.exception.kod,'provider_unavailable')
                    self.assertIn('TXT/Markdown',str(result.exception))
                    self.assertIn('ücretli API kullanımı kapalı',str(result.exception))
                    call.assert_called_once()
                    self.assertTrue(call.call_args.args[0].full_url.startswith('http://127.0.0.1:8317/'))
    def test_free_web_fallback_uses_bounded_search_snippets_and_citations(self):
        import io, json
        from unittest.mock import patch
        html={'pages':[{'key':'İstanbul_tarihi','title':'İstanbul tarihi','excerpt':'Kısa <span>özet</span>.'}]}
        metinler=[]
        prompt='Araştırma sorusu '+chr(10)+'Konu: İstanbul tarihi'+chr(10)+'Plan: kısa'
        with patch.object(server,'urlopen',return_value=io.BytesIO(json.dumps(html).encode())) as ag:
            sonuc=server.ucretsiz_web_arastir(prompt,lambda job: metinler.append(job) or 'Özet [1].')
        self.assertEqual(ag.call_count,1)
        self.assertIn('tr.wikipedia.org/w/rest.php/v1/search/page',ag.call_args.args[0].full_url)
        self.assertIn('yalnız aşağıdaki web arama sonuçlarının',metinler[0]['prompt'].lower())
        self.assertIn('Hedef sayfalar açılmadı',metinler[0]['prompt'])
        self.assertIn('Wikipedia araması',metinler[0]['prompt'])
        self.assertIn('İstanbul tarihi',sonuc)
        self.assertIn('https://tr.wikipedia.org/wiki/%C4%B0stanbul_tarihi',sonuc)
    def test_code_requires_valid_json_and_does_not_execute_other_languages(self):
        with self.assertRaises(ValueError): server.finish_code('plain code')
        result=server.finish_code('{"language":"swift","code":"print(1)","summary":"Swift"}')
        self.assertIn('çalıştırılmadı',result)
    def test_python_reports_actual_runner_result(self):
        import io,json
        from unittest.mock import patch
        response=io.BytesIO(json.dumps({'exit_code':1,'output':'assertion failed','timeout':False}).encode())
        with patch.object(server,'urlopen',return_value=response):
            result=server.finish_code('{"language":"python","code":"assert False"}')
        self.assertIn('çıkış kodu 1',result)
        self.assertIn('assertion failed',result)
    def test_effort_persisted_validated_and_idempotent(self):
        p=self.job(); p['effort']='high'
        self.assertEqual(server.submit(p)['effort'],'high')
        self.assertEqual(server.submit(p),server.submit(p))
        p['effort']='low'
        with self.assertRaises(ValueError): server.submit(p)
        p=self.job(); p['effort']='auto'
        with self.assertRaises(ValueError): server.submit(p)
    def test_native_effort_for_all_routes(self):
        for effort in ('low','medium','high'):
            for kind in ('text','code','research'):
                path,body=server.generation_request({'prompt':'Test','kind':kind,'effort':effort})
                if kind=='research' or kind=='code' or effort=='high':
                    self.assertEqual(path,'/v1/responses')
                    self.assertEqual(body['reasoning']['effort'],effort)
                else:
                    self.assertEqual(path,'/v1/messages')
                    self.assertEqual(body['output_config']['effort'],effort)
                    self.assertEqual(body['model'],'claude-sonnet-5-5')
    def test_quota_fallback_and_no_repeat_of_runner(self):
        from unittest.mock import patch
        from urllib.error import HTTPError
        server.MODEL_COOLDOWNS.clear()
        job={'prompt':'Test','kind':'code','effort':'medium'}
        quota=HTTPError('test',429,'quota',{},None)
        with patch.object(server,'generate_text',side_effect=[quota,'code']) as gen, patch.object(server,'finish_code',return_value='done') as runner:
            self.assertEqual(server.generate(job),'done')
            self.assertEqual([c.args[1] for c in gen.call_args_list],['gpt-6-luna','claude-sonnet-5-5'])
            runner.assert_called_once()
        server.MODEL_COOLDOWNS.clear()
        with patch.object(server,'generate_text',return_value='code') as gen, patch.object(server,'finish_code',side_effect=quota):
            with self.assertRaises(HTTPError): server.generate(job)
            gen.assert_called_once()
        server.MODEL_COOLDOWNS.clear()

    def test_native_completion_and_truncation(self):
        import io,json
        from unittest.mock import patch
        job={'prompt':'Test','kind':'text','effort':'low'}
        data={'type':'message','stop_reason':'end_turn','content':[{'type':'thinking','thinking':'private'},{'type':'text','text':'Yanıt'}]}
        with patch.object(server,'urlopen',return_value=io.BytesIO(json.dumps(data).encode())):
            self.assertEqual(server.generate(job),'Yanıt')
        data['stop_reason']='max_tokens'
        with patch.object(server,'urlopen',return_value=io.BytesIO(json.dumps(data).encode())):
            with self.assertRaises(ValueError): server.generate(job)
    def test_old_database_migration(self):
        with server.connect() as db:
            db.execute('DROP TABLE jobs')
            db.execute('CREATE TABLE jobs (id TEXT PRIMARY KEY, prompt TEXT, kind TEXT, status TEXT, result TEXT, error TEXT, created REAL, updated REAL)')
            db.execute("INSERT INTO jobs VALUES ('old','test','text','done','answer','',0,0)")
        server.init(); server.init()
        with server.connect() as db:
            row=db.execute("SELECT * FROM jobs WHERE id='old'").fetchone()
            self.assertEqual(row['effort'],'medium'); self.assertEqual(row['result'],'answer')
    def test_routine_schedule_pause_and_due_job(self):
        from unittest.mock import patch
        p={'id':str(uuid.uuid4()),'name':'Günlük özet','prompt':'Özet hazırla','kind':'text','interval_minutes':5}
        r=server.routine_submit(p); self.assertEqual(r['enabled'],1)
        self.assertEqual(server.routine_toggle(r['id'],False)['enabled'],0)
        self.assertEqual(server.routine_toggle(r['id'],True)['enabled'],1)
        with server.connect() as db: db.execute('UPDATE routines SET next_run=0 WHERE id=?',(r['id'],))
        server.enqueue_due_routines()
        with server.connect() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM jobs').fetchone()[0],1)
            self.assertGreater(db.execute('SELECT next_run FROM routines WHERE id=?',(r['id'],)).fetchone()[0],0)
        self.assertIsNotNone(server.routine_delete(r['id']))
    def test_live_token_uses_current_constrained_setup_schema(self):
        body=server.live_token_body(0)
        self.assertEqual(body['uses'],1)
        self.assertNotIn('liveConnectConstraints',body)
        setup=body['bidiGenerateContentSetup']
        self.assertEqual(setup['model'],'models/gemini-3.8-live')
        self.assertEqual(setup['generationConfig']['responseModalities'],['AUDIO'])
        self.assertEqual(setup['generationConfig']['speechConfig']['languageCode'],'tr-TR')
    def test_direct_live_switch_defaults_to_enabled_and_can_be_disabled(self):
        old=os.environ.get('ASISTAN_DIRECT_LIVE')
        try:
            os.environ.pop('ASISTAN_DIRECT_LIVE',None)
            self.assertTrue(server.direct_live_etkin())
            os.environ['ASISTAN_DIRECT_LIVE']='0'
            self.assertFalse(server.direct_live_etkin())
        finally:
            if old is None: os.environ.pop('ASISTAN_DIRECT_LIVE',None)
            else: os.environ['ASISTAN_DIRECT_LIVE']=old

class PushTest(unittest.TestCase):
    """P4.6: cihaz kaydı ve APNs bildirimi (ağsız; gönderici sahte)."""
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();server.DB=os.path.join(self.t.name,'test.db');server.init()
        self.env={k:os.environ.pop(k) for k in ('APNS_KEY_PATH','APNS_KEY_ID','APNS_TEAM_ID','APNS_TOPIC') if k in os.environ}
        server._JWT_CACHE.clear()
    def tearDown(self):
        for k in ('APNS_KEY_PATH','APNS_KEY_ID','APNS_TEAM_ID','APNS_TOPIC'): os.environ.pop(k,None)
        os.environ.update(self.env); server._JWT_CACHE.clear(); self.t.cleanup()
    def tokens(self):
        with server.connect() as db: return [r[0] for r in db.execute('SELECT token FROM devices')]
    def fake_key(self):
        path=os.path.join(self.t.name,'key.pem')
        os.environ['APNS_KEY_PATH']=path; os.environ['APNS_KEY_ID']='ABC123DEFG'
        with open(path,'w') as f: f.write('sahte')
        return path
    def test_device_validation(self):
        for bad in ('abc','z'*64,'a'*63,'a'*201):
            with self.assertRaises(ValueError): server.device_register({'token':bad,'ortam':'development'})
        with self.assertRaises(ValueError): server.device_register({'token':'a'*64,'ortam':'test'})
        self.assertTrue(server.device_register({'token':'AB'*32,'ortam':'development','paket':'com.mehmetderin.asistan'})['ok'])
        self.assertEqual(self.tokens(),['ab'*32])
        server.device_register({'token':'ab'*32,'ortam':'production'})
        self.assertEqual(len(self.tokens()),1)
    def test_at_most_five_devices(self):
        import itertools, types
        from unittest.mock import patch
        sayac=itertools.count(1000)  # saat çözünürlüğüne bağlı olmayan, kesin artan sahte zaman
        with patch.object(server,'time',types.SimpleNamespace(time=lambda: float(next(sayac)))):
            for i in range(7):
                server.device_register({'token':f'{i:x}'*64,'ortam':'production'})
        kalan=self.tokens(); self.assertEqual(len(kalan),5)
        self.assertNotIn('0'*64,kalan); self.assertIn('6'*64,kalan)
    def test_device_endpoint_rejects_bad_token(self):
        import io,json
        from unittest.mock import MagicMock
        old=server.TOKEN; server.TOKEN='gizli'
        try:
            def call(method,path,body=b''):
                h=server.Handler.__new__(server.Handler)
                h.command=method; h.path=path; h.headers={'X-Personal-Token':'gizli','Content-Length':str(len(body))}
                h.rfile=io.BytesIO(body); h.reply=MagicMock(); h.handle_request(); return h.reply.call_args.args[0]
            self.assertEqual(call('POST','/v1/asistan/devices',json.dumps({'token':'kisa','ortam':'production'}).encode()),400)
            self.assertEqual(call('POST','/v1/asistan/devices',json.dumps({'token':'g'*64,'ortam':'production'}).encode()),400)
            self.assertEqual(call('POST','/v1/asistan/devices',json.dumps({'token':'a'*64,'ortam':'production'}).encode()),200)
            self.assertEqual(call('DELETE','/v1/asistan/devices/xyz'),400)
            self.assertEqual(call('DELETE','/v1/asistan/devices/'+'a'*64),200)
            self.assertEqual(self.tokens(),[])
            self.assertEqual(call('DELETE','/v1/asistan/devices/'+'a'*64),404)
            h=server.Handler.__new__(server.Handler)
            h.command='DELETE'; h.path='/v1/asistan/devices/'+'b'*64; h.headers={'X-Personal-Token':'gizli','Content-Length':'0'}
            h.rfile=io.BytesIO(b''); h.reply=MagicMock(); h.handle_request()
            self.assertEqual(h.reply.call_args.args,(404,{'error':'Bulunamadı'}))
        finally: server.TOKEN=old
    def test_payload_truncation_and_titles(self):
        p=server.apns_payload({'id':'x','prompt':'ç'*300+'\n','status':'done'})
        self.assertEqual(len(p['aps']['alert']['body']),120); self.assertEqual(p['aps']['alert']['title'],'Sunucu görevi bitti')
        self.assertEqual(p['gorev'],'x'); self.assertEqual(p['aps']['sound'],'default')
        self.assertEqual(server.apns_payload({'id':'y','prompt':'a  b','status':'failed'})['aps']['alert'],{'title':'Sunucu görevi tamamlanamadı','body':'a b'})
    def test_no_config_means_no_push(self):
        server.device_register({'token':'a'*64,'ortam':'production'})
        from unittest.mock import MagicMock
        sender=MagicMock(return_value=(200,''))
        self.assertEqual(server.notify_finished({'id':'x','prompt':'p'},'done',sender=sender),0)
        sender.assert_not_called()
        os.environ['APNS_KEY_ID']='ABC'; os.environ['APNS_KEY_PATH']=os.path.join(self.t.name,'yok.p8')
        self.assertEqual(server.notify_finished({'id':'x','prompt':'p'},'done',sender=sender),0)
        sender.assert_not_called()
    def test_gone_token_deleted(self):
        self.fake_key()
        server.device_register({'token':'a'*64,'ortam':'production'})
        server.device_register({'token':'b'*64,'ortam':'development'})
        server.device_register({'token':'c'*64,'ortam':'development'})
        cevap={'a'*64:(410,'{"reason":"Unregistered"}'),'b'*64:(400,'{"reason":"BadDeviceToken"}'),'c'*64:(200,'')}
        sent=server.notify_finished({'id':'x','prompt':'p'},'done',sender=lambda t,e,p,c: cevap[t])
        self.assertEqual(sent,1); self.assertEqual(self.tokens(),['c'*64])
    def test_rejection_logged_without_token_and_expired_jwt_cache_cleared(self):
        import io, contextlib
        self.fake_key(); server.device_register({'token':'a'*64,'ortam':'production'})
        server._JWT_CACHE['k']=(0,'jwt')
        hata=io.StringIO()
        with contextlib.redirect_stderr(hata):
            sent=server.notify_finished({'id':'x','prompt':'p'},'done',sender=lambda t,e,p,c: (403,'{"reason":"ExpiredProviderToken"}'))
        self.assertEqual(sent,0); self.assertEqual(server._JWT_CACHE,{})
        self.assertIn('HTTP 403 ExpiredProviderToken',hata.getvalue()); self.assertNotIn('a'*64,hata.getvalue())
    def test_one_failing_device_does_not_stop_the_rest(self):
        self.fake_key()
        server.device_register({'token':'a'*64,'ortam':'production'}); server.device_register({'token':'b'*64,'ortam':'production'})
        def gonder(t,e,p,c):
            if t=='a'*64: raise OSError('ağ yok')
            return 200,''
        self.assertEqual(server.notify_finished({'id':'x','prompt':'p'},'done',sender=gonder),1)
    def test_finish_job_background_notifies_off_the_worker_thread(self):
        import threading
        from unittest.mock import patch
        j=server.submit({'id':str(uuid.uuid4()),'prompt':'Arka plan','kind':'text'})
        with server.connect() as db: db.execute("UPDATE jobs SET status='running' WHERE id=?",(j['id'],))
        with server.connect() as db: row=db.execute('SELECT * FROM jobs WHERE id=?',(j['id'],)).fetchone()
        gelen=threading.Event(); kimlik=[]
        def bildir(*a): kimlik.append(threading.current_thread()); gelen.set()
        with patch.object(server,'notify_finished',side_effect=bildir):
            self.assertTrue(server.finish_job(row,'done','sonuç','',arka_plan=True))
            self.assertTrue(gelen.wait(2))
        self.assertIsNot(kimlik[0],threading.current_thread()); self.assertTrue(kimlik[0].daemon)
    def test_sender_error_swallowed(self):
        self.fake_key(); server.device_register({'token':'a'*64,'ortam':'production'})
        def patla(*a): raise OSError('ağ yok')
        self.assertEqual(server.notify_finished({'id':'x','prompt':'p'},'done',sender=patla),0)
    def test_cancelled_job_not_notified(self):
        from unittest.mock import patch
        j=server.submit({'id':str(uuid.uuid4()),'prompt':'Bir metin yaz','kind':'text'})
        with server.connect() as db: db.execute("UPDATE jobs SET status='running'")
        with server.connect() as db: row=db.execute('SELECT * FROM jobs WHERE id=?',(j['id'],)).fetchone()
        server.cancel(j['id'])
        with patch.object(server,'notify_finished') as n:
            self.assertFalse(server.finish_job(row,'done','sonuç',''))
            n.assert_not_called()
        j2=server.submit({'id':str(uuid.uuid4()),'prompt':'İkinci','kind':'text'})
        with server.connect() as db: db.execute("UPDATE jobs SET status='running' WHERE id=?",(j2['id'],))
        with server.connect() as db: row2=db.execute('SELECT * FROM jobs WHERE id=?',(j2['id'],)).fetchone()
        with patch.object(server,'notify_finished') as n:
            self.assertTrue(server.finish_job(row2,'done','sonuç',''))
            n.assert_called_once(); self.assertEqual(n.call_args.args[1],'done')
    def test_send_push_parses_status_and_keeps_jwt_off_argv(self):
        import subprocess
        from unittest.mock import patch
        cfg={'path':'x','kid':'k','team':'t','topic':'com.mehmetderin.asistan'}
        sonuc=subprocess.CompletedProcess([],0,stdout=b'{"reason":"BadDeviceToken"}\n400',stderr=b'')
        with patch.object(server,'apns_jwt',return_value='GIZLI.JWT.IMZA'), patch.object(server.subprocess,'run',return_value=sonuc) as run:
            code,body=server.send_push('a'*64,'development',{'aps':{}},cfg)
        self.assertEqual(code,400); self.assertIn('BadDeviceToken',body)
        argv=run.call_args.args[0]
        self.assertNotIn('GIZLI',' '.join(argv)); self.assertIn('https://api.sandbox.push.apple.com/3/device/'+'a'*64,argv)
        self.assertTrue(server.token_invalid(code,body))
        with patch.object(server,'apns_jwt',return_value='j'), patch.object(server.subprocess,'run',return_value=subprocess.CompletedProcess([],0,stdout=b'\n200',stderr=b'')) as run:
            self.assertEqual(server.send_push('a'*64,'production',{},cfg),(200,''))
        self.assertIn('https://api.push.apple.com/3/device/'+'a'*64,run.call_args.args[0])
    def test_der_to_raw(self):
        der=bytes([0x30,0x08,0x02,0x02,0x00,0x81,0x02,0x02,0x01,0x02])
        raw=server.der_to_raw(der)
        self.assertEqual(len(raw),64); self.assertEqual(raw[31],0x81); self.assertEqual(raw[62:],b'\x01\x02')
        with self.assertRaises(ValueError): server.der_to_raw(b'\x31\x00\x00\x00\x00\x00\x00\x00')
    def test_jwt_header_claims_signature(self):
        import base64,json,subprocess,shutil
        if not shutil.which('openssl'): self.skipTest('openssl yok')
        key=os.path.join(self.t.name,'k.pem'); pub=os.path.join(self.t.name,'p.pem')
        try:
            subprocess.run(['openssl','ecparam','-name','prime256v1','-genkey','-noout','-out',key],check=True,capture_output=True)
            subprocess.run(['openssl','ec','-in',key,'-pubout','-out',pub],check=True,capture_output=True)
        except (subprocess.CalledProcessError,OSError): self.skipTest('EC anahtarı üretilemedi')
        os.environ['APNS_KEY_PATH']=key; os.environ['APNS_KEY_ID']='KEY1234567'
        jwt=server.apns_jwt(now=1000)
        h,c,s=jwt.split('.')
        dec=lambda x: base64.urlsafe_b64decode(x+'='*(-len(x)%4))
        self.assertEqual(json.loads(dec(h)),{'alg':'ES256','kid':'KEY1234567'})
        self.assertEqual(json.loads(dec(c)),{'iss':'838FF89FZ8','iat':1000})
        raw=dec(s); self.assertEqual(len(raw),64)
        def der_int(b):
            b=b.lstrip(b'\x00') or b'\x00'
            if b[0]&0x80: b=b'\x00'+b
            return bytes([0x02,len(b)])+b
        body=der_int(raw[:32])+der_int(raw[32:]); der=bytes([0x30,len(body)])+body
        sig=os.path.join(self.t.name,'s.der')
        with open(sig,'wb') as f: f.write(der)
        v=subprocess.run(['openssl','dgst','-sha256','-verify',pub,'-signature',sig],input=(h+'.'+c).encode(),capture_output=True)
        self.assertEqual(v.returncode,0,v.stdout+v.stderr)
        # 50 dk önbellek: aynı belirteç; sonrasında yenisi.
        self.assertEqual(server.apns_jwt(now=1000+49*60),jwt)
        self.assertNotEqual(server.apns_jwt(now=1000+51*60),jwt)
if __name__=='__main__': unittest.main()
