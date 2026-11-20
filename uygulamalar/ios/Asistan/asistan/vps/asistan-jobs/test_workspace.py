import concurrent.futures
import json
import tempfile
import subprocess
import sys
import unittest
import uuid
from pathlib import Path
from unittest.mock import patch
import workspace


class CalismaTestleri(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory()
        self.addCleanup(self.gecici.cleanup)
        self.d = workspace.Depo(Path(self.gecici.name) / 'jobs.sqlite3')
        self.d.kur()

    def istek(self, tur='document', dosyalar=None):
        return {'kind': tur, 'input': {'prompt': 'Türkçe bir rapor hazırla.', 'file_ids': dosyalar or []}, 'limits': {'allow_paid': False}}

    def ekle(self, istek=None):
        return self.d.ekle(istek or self.istek(), str(uuid.uuid4()))

    def test_ayni_istek_tek_is_farkli_icerik_409(self):
        k = str(uuid.uuid4()); g = self.d.ekle(self.istek(), k)
        self.assertEqual(g['id'], self.d.ekle(self.istek(), k)['id'])
        with self.assertRaises(workspace.Hata) as e:
            self.d.ekle(self.istek('research'), k)
        self.assertEqual(e.exception.http, 409)

    def test_ucretli_istek_ve_bagli_hesap_sessiz_gecilmez(self):
        i = self.istek(); i['limits']['allow_paid'] = True
        with self.assertRaises(workspace.Hata): self.ekle(i)
        i = self.istek(); i['input']['connection_ids'] = [str(uuid.uuid4())]
        with self.assertRaises(workspace.Hata): self.ekle(i)
        self.assertFalse(self.d.yetenekler()['paid_enabled'])

    def test_eszamanli_tek_sahip(self):
        self.ekle()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as e:
            alinan = list(e.map(lambda _: self.d.al(), range(4)))
        self.assertEqual(sum(g is not None for g in alinan), 1)

    def test_yeniden_baslama_kontrol_noktasini_korur(self):
        self.ekle(); g = self.d.al(); self.d.adim(g, 'plan', lambda: 'hazır')
        self.d.kur()
        self.assertEqual(self.d.gorev(g['id'])['status'], 'paused')
        self.d.durum(g['id'], 'resume'); yeni = self.d.al()
        self.assertEqual(self.d.adim(yeni, 'plan', lambda: self.fail('Tamamlanan adım tekrarlandı')), 'hazır')
        with self.assertRaises(workspace.Hata): self.d.bitir(g, 'Eski işçi', 'yanlış')
        self.d.bitir(yeni, 'Rapor', 'doğru')
        self.assertEqual(self.d.gorev(g['id'])['status'], 'completed')

    def test_iptal_sirasinda_cikti_yayinlanmaz(self):
        self.ekle(); g = self.d.al()
        def model():
            self.d.durum(g['id'], 'cancel')
            return 'iptalden sonra dönen yanıt'
        with self.assertRaises(workspace.Hata): self.d.adim(g, 'cevap', model)
        self.d.hata(g, RuntimeError('secret'))
        self.assertEqual(self.d.gorev(g['id'])['status'], 'cancelled')
        self.assertEqual(self.d.ciktilar(), [])

    def test_surum_cakismasi_ve_buyuk_harf_uuid(self):
        b = self.d.olustur('Başlık', 'Türkçe')
        yeni = self.d.surum_ekle(b['id'].upper(), b['current_revision'].upper(), 'Yeni')
        self.assertEqual(yeni['content'], 'Yeni')
        with self.assertRaises(workspace.Hata) as e:
            self.d.surum_ekle(b['id'], b['current_revision'], 'Eski istemci')
        self.assertEqual(e.exception.kod, 'stale_revision')
        self.assertEqual(len(self.d.surumler(b['id'])), 2)

    def test_buyuk_harf_uuid_iptal(self):
        g = self.ekle()
        self.assertEqual(self.d.durum(g['id'].upper(), 'cancel')['status'], 'cancelled')

    def test_dosya_adi_kota_ve_buyuk_harf_kimlik(self):
        with self.assertRaises(workspace.Hata): self.d.dosya_ekle('../secret', b'abc')
        f = self.d.dosya_ekle('ödev.txt', 'Türkçe'.encode())
        _, p = self.d.dosya(f['id'].upper())
        self.assertEqual(p.read_text(), 'Türkçe')
        self.d.kota = 1
        with self.assertRaises(workspace.Hata): self.d.dosya_ekle('x.txt', b'abc')
        self.assertEqual(p.read_text(), 'Türkçe')

    def test_kaynakli_arastirma_iki_adim_ve_ucretsiz(self):
        f = self.d.dosya_ekle('kaynak.txt', 'Ölçülen sonuç 42.'.encode())
        self.ekle(self.istek('research', [f['id']])); g = self.d.al(); cagrilar = []
        def model(istem, web):
            cagrilar.append((istem, web))
            return 'Kaynaklı yanıt'
        b = workspace.calistir(self.d, g, model)
        self.assertEqual(b['content'], 'Kaynaklı yanıt')
        self.assertEqual(len(cagrilar), 2)
        self.assertTrue(all(not web for _, web in cagrilar))
        self.assertIn('Ölçülen sonuç 42.', cagrilar[-1][0])
        self.assertEqual(len(self.d.gorev(g['id'])['artifact_ids']), 1)

    def test_olay_sirasi_artimli(self):
        g = self.ekle(); self.d.al()
        olaylar = self.d.olaylar(g['id'])
        self.assertEqual(len(olaylar), 2)
        self.assertEqual(len(self.d.olaylar(g['id'], olaylar[0]['seq'])), 1)
        self.assertEqual(self.d.olaylar(g['id'], olaylar[-1]['seq']), [])

    def test_ham_hata_sir_sizdirmaz(self):
        self.ekle(); g = self.d.al(); self.d.hata(g, RuntimeError('PASSWORD=private'))
        self.assertNotIn('private', json.dumps(self.d.gorev(g['id'])))

    def test_desteksiz_pdf_analiz_edildi_sayilmaz(self):
        f = self.d.dosya_ekle('kitap.pdf', b'%PDF-1.7')
        self.ekle(self.istek('research', [f['id']])); g = self.d.al()
        with self.assertRaises(workspace.Hata): workspace.calistir(self.d, g, lambda *a: self.fail('Model çağrılmamalı'))
        self.assertEqual(self.d.ciktilar(), [])

    def test_iptal_edilen_is_yeniden_baslatilmaz(self):
        g = self.ekle(); self.d.durum(g['id'], 'cancel')
        with self.assertRaises(workspace.Hata): self.d.durum(g['id'], 'resume')

    def test_kota_on_is(self):
        for _ in range(10): self.ekle()
        with self.assertRaises(workspace.Hata) as e: self.ekle()
        self.assertEqual(e.exception.http, 429)

    def test_resume_kotasi(self):
        g = self.ekle(); self.d.hata(self.d.al(), RuntimeError())
        for _ in range(10): self.ekle()
        with self.assertRaises(workspace.Hata): self.d.durum(g['id'], 'resume')

    def test_belge_ve_surum_kotasi(self):
        b = self.d.olustur('Başlık', 'ilk')
        self.d.kota = 5
        with self.assertRaises(workspace.Hata): self.d.surum_ekle(b['id'], b['current_revision'], 'yeni sürüm')
        self.assertEqual(self.d.cikti(b['id'])['content'], 'ilk')

    def test_dosyali_checkpoint_tumu_ya_da_hic(self):
        self.ekle(); g = self.d.al(); self.d.kota = 200
        cikti = {'markdown': 'rapor', 'files': [{'name': 'a.csv', 'data': b'a' * 100}, {'name': 'b.csv', 'data': b'b' * 100}]}
        with self.assertRaises(workspace.Hata): self.d.dosyali_adim(g, 'analiz', lambda: cikti)
        self.assertEqual(list(self.d.dizin.iterdir()), [])
        self.d.kota = 10000
        r = self.d.dosyali_adim(g, 'analiz', lambda: cikti)
        self.assertEqual(len(r['files']), 2)
        self.assertEqual(self.d.dosyali_adim(g, 'analiz', lambda: self.fail('Tekrar çalıştı')), r)

    def test_iptal_dosyali_checkpoint_yazamaz(self):
        self.ekle(); g = self.d.al()
        def uret():
            self.d.durum(g['id'], 'cancel')
            return {'markdown': 'x', 'files': [{'name': 'a.csv', 'data': b'1'}]}
        with self.assertRaises(workspace.Hata): self.d.dosyali_adim(g, 'analiz', uret)
        self.assertEqual(list(self.d.dizin.iterdir()), [])

    def test_ilan_edilmeyen_kaynak_siniri_kabul_edilmez(self):
        i = self.istek(); i['limits']['max_sources'] = 8
        with self.assertRaises(workspace.Hata): self.ekle(i)

    def test_sert_kapanista_kayitsiz_dosya_korunur_ve_kotaya_girer(self):
        kod = '''
import contextlib, os, uuid, workspace
d = workspace.Depo(%r); d.kur()
d.ekle({'kind': 'document', 'input': {'prompt': 'Rapor'}}, str(uuid.uuid4()))
g = d.al(); asil = d.baglan
@contextlib.contextmanager
def kesilen():
    with asil() as db:
        yield db
        if db.execute('SELECT COUNT(*) FROM workspace_steps').fetchone()[0]: os._exit(9)
d.baglan = kesilen
d.dosyali_adim(g, 'cikti', lambda: {'markdown': 'rapor', 'files': [{'name': 'rapor.txt', 'data': b'korunan veri'}]})
''' % self.d.veritabani
        r = subprocess.run([sys.executable, '-c', kod], timeout=10, capture_output=True)
        self.assertEqual(r.returncode, 9)
        self.d.kur()
        self.assertEqual(len(list(self.d.dizin.iterdir())), 1)
        with self.d.baglan() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM workspace_files').fetchone()[0], 0)
            self.assertEqual(db.execute('SELECT SUM(size) FROM workspace_orphans').fetchone()[0], len(b'korunan veri'))
            self.d.kota = db.execute('SELECT length(CAST(request AS BLOB)) FROM workspace_jobs').fetchone()[0] + len(b'korunan veri')
            self.d.alan_kontrol(db, 0)
            with self.assertRaises(workspace.Hata): self.d.alan_kontrol(db, 1)


if __name__ == '__main__': unittest.main()
