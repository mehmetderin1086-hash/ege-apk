import json
import tempfile
import threading
import unittest
from unittest.mock import patch
import uuid
import hashlib
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer
import server
import workspace

class HTTPTestleri(unittest.TestCase):
    def setUp(self):
        # Disk kotası ayrı testte sınanır; işlev testleri geliştirici diskinin boşluğuna bağlı değildir.
        disk = patch('uploads.shutil.disk_usage')
        disk.start().return_value.free = 100 * 1024 ** 3
        self.addCleanup(disk.stop)
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.eski = server.TOKEN, server.WORKSPACE
        server.TOKEN = 'yalniz-test'
        server.WORKSPACE = workspace.Depo(Path(self.tmp.name) / 'test.db'); server.WORKSPACE.kur()
        self.http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True); self.thread.start()
        self.root = 'http://127.0.0.1:' + str(self.http.server_port) + '/v2/asistan/'

    def tearDown(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join()
        server.TOKEN, server.WORKSPACE = self.eski

    def cagir(self, yol, veri=None, token=True, headers=None):
        h = {'Content-Type': 'application/json'}
        if token: h['X-Personal-Token'] = 'yalniz-test'
        h.update(headers or {})
        with urlopen(Request(self.root + yol, data=None if veri is None else json.dumps(veri).encode(), headers=h), timeout=5) as r:
            return json.load(r)

    def test_yetkisiz_ve_kabiliyet(self):
        with self.assertRaises(HTTPError) as e: self.cagir('capabilities', token=False)
        self.assertEqual(e.exception.code, 401)
        self.assertTrue(self.cagir('capabilities')['modules']['canvas'])

    def test_create_poll_cancel(self):
        k = str(uuid.uuid4())
        body = {'kind': 'document', 'input': {'prompt': 'İstanbul'}, 'limits': {'allow_paid': False}}
        g = self.cagir('jobs', body, headers={'Idempotency-Key': k})
        self.assertEqual(self.cagir('jobs', body, headers={'Idempotency-Key': k})['id'], g['id'])
        self.assertEqual(self.cagir('jobs/' + g['id'])['status'], 'queued')
        self.assertEqual(self.cagir('jobs/' + g['id'] + '/cancel', {})['status'], 'cancelled')
        self.assertEqual(len(self.cagir('jobs/' + g['id'] + '/events?after=0')), 2)

    def test_invalid_body_structured_error(self):
        with self.assertRaises(HTTPError) as e: self.cagir('jobs', [])
        body = json.loads(e.exception.read())
        self.assertEqual(body['code'], 'invalid_input'); self.assertIn('request_id', body)

    def test_parcali_yukleme_http_surdur_tamamla_indir_sil(self):
        veri = b'HTTP aktarim\n' * 1000; ident = str(uuid.uuid4())
        r = self.cagir('uploads', {'name': 'deneme.bin', 'size': len(veri), 'sha256': hashlib.sha256(veri).hexdigest()}, headers={'Idempotency-Key': ident})
        self.assertEqual(self.cagir('uploads')[0]['id'], ident)
        for bas, son in [(0, 333), (333, len(veri))]:
            parca = veri[bas:son]
            req = Request(self.root + 'uploads/' + ident, method='PUT', data=parca, headers={
                'X-Personal-Token': 'yalniz-test', 'Upload-Offset': str(bas), 'X-Chunk-SHA256': hashlib.sha256(parca).hexdigest()})
            with urlopen(req, timeout=5) as yanit: self.assertEqual(json.load(yanit)['offset'], son)
            self.assertEqual(self.cagir('uploads/' + ident)['offset'], son)
        self.assertEqual(self.cagir('uploads/' + ident + '/complete', {})['id'], ident)
        with urlopen(Request(self.root + 'files/' + ident, headers={'X-Personal-Token': 'yalniz-test'})) as yanit:
            self.assertEqual(yanit.read(), veri)
        with urlopen(Request(self.root + 'files/' + ident, method='DELETE', headers={'X-Personal-Token': 'yalniz-test'})) as yanit:
            self.assertTrue(json.load(yanit)['deleted'])
        self.assertEqual(self.cagir('files'), [])

    def test_yukleme_ucu_yetki_ve_bellek_siniri(self):
        with self.assertRaises(HTTPError) as h: self.cagir('uploads', {}, token=False)
        self.assertEqual(h.exception.code, 401)
        req = Request(self.root + 'uploads/' + str(uuid.uuid4()), data=b'', method='PUT', headers={
            'X-Personal-Token': 'yalniz-test', 'Content-Length': str(8 * 1024 ** 2 + 1)})
        with self.assertRaises(HTTPError) as h: urlopen(req, timeout=5)
        self.assertEqual(h.exception.code, 413)
