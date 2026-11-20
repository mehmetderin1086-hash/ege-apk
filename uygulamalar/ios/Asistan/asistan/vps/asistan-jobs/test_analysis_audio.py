import ast
import base64
import io
import json
import shutil
import tempfile
import time
import unittest
import uuid
import wave
from pathlib import Path
from unittest.mock import patch
import analysis_runner
import audio_workspace
import workspace

class AnalizSesTestleri(unittest.TestCase):
    def test_analiz_girdi_sinirlari(self):
        veri = {'code': 'print(1)', 'files': [{'name': 'data.csv', 'data': base64.b64encode(b'a,b\n1,2').decode()}]}
        self.assertEqual(analysis_runner.dogrula(veri)[1][0][0], 'data.csv')
        veri['files'][0]['name'] = '../data.csv'
        with self.assertRaises(ValueError): analysis_runner.dogrula(veri)

    def test_png_imzasi_ve_raporlayici_derlenir(self):
        tree = ast.parse(analysis_runner.RAPORLAYICI)
        baytlar = [n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, bytes)]
        self.assertIn(bytes([137,80,78,71,13,10,26,10]), baytlar)

    def test_uydurma_senaryo_dayanagi_reddedilir(self):
        k = [{'id': '1', 'text': 'Hücre yaşamın birimidir.'}]
        s = {'segments': [{'speaker': 0, 'text': 'Anlatalım.', 'source_id': '1', 'source_quote': 'kaynakta yok'}]}
        with self.assertRaises(workspace.Hata): audio_workspace.senaryo_coz(json.dumps(s), k)

    @unittest.skipUnless(shutil.which('ffmpeg'), 'FFmpeg gerekli')
    def test_iki_ses_parcasi_gercek_mp3_uretir_ve_checkpoint_korunur(self):
        with tempfile.TemporaryDirectory() as d:
            depo = workspace.Depo(Path(d) / 'test.db'); depo.kur()
            with patch.dict('os.environ', {'ASISTAN_AUDIO_ENABLED': '1'}):
                depo.ekle({'kind': 'audio', 'input': {'prompt': 'Anlat.'}}, str(uuid.uuid4()))
            g = depo.al(); kaynaklar = [{'id': '1', 'text': 'Hücre yaşamın birimidir.'}]
            script = json.dumps({'segments': [{'speaker': i, 'text': 'Hücre yaşamın birimidir.', 'source_id': '1', 'source_quote': 'Hücre yaşamın birimidir.'} for i in (0, 1)]})
            buf = io.BytesIO()
            with wave.open(buf, 'wb') as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(b'\0' * 3200)
            cagrilar = []
            def ses(yol, body, timeout): cagrilar.append(body['voice']); return {'audio': base64.b64encode(buf.getvalue()).decode()}
            katalog = [{'engine': 'azure', 'voice': 'Elif'}, {'engine': 'azure', 'voice': 'Diger'}]
            r = audio_workspace.calistir(depo, g, kaynaklar, lambda *a: script, katalog, ses, time.monotonic()+120)
            self.assertEqual(len(cagrilar), 2)
            _, yol = depo.dosya(r['files'][0]); self.assertGreater(yol.stat().st_size, 100)
            audio_workspace.calistir(depo, g, kaynaklar, lambda *a: self.fail('Senaryo tekrarlandı'), katalog, lambda *a: self.fail('Ses tekrarlandı'), time.monotonic()+120)

    def test_gec_gelen_ses_saklanir_fakat_tamamlanmaz(self):
        with tempfile.TemporaryDirectory() as d:
            depo = workspace.Depo(Path(d) / 'test.db'); depo.kur()
            depo.ekle({'kind': 'document', 'input': {'prompt': 'Anlat.'}}, str(uuid.uuid4()))
            g = depo.al(); kaynaklar = [{'id': '1', 'text': 'Kaynak metin.'}]
            script = json.dumps({'segments': [{'speaker': 0, 'text': 'Anlat.', 'source_id': '1', 'source_quote': 'Kaynak metin.'}]})
            saat = [0]
            def ses(yol, body, timeout):
                self.assertEqual(timeout, 5)
                saat[0] = 6
                return {'audio': base64.b64encode(b'x' * 44).decode()}
            with patch.object(audio_workspace.time, 'monotonic', side_effect=lambda: saat[0]):
                with self.assertRaises(workspace.Hata) as e:
                    audio_workspace.calistir(depo, g, kaynaklar, lambda *a: script, [{'engine': 'azure', 'voice': 'Elif'}], ses, 5)
            self.assertEqual(e.exception.kod, 'resource_limit')
            self.assertEqual(len(list(depo.dizin.iterdir())), 1)
            self.assertEqual(depo.ciktilar(), [])
