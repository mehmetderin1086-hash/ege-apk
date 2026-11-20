import hashlib
import json
from pathlib import Path
import tempfile
import time
import tracemalloc
import unittest
import uuid
from unittest.mock import patch

import source_retrieval as kaynak
import workspace


class KaynakSecimTestleri(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory()
        self.addCleanup(self.gecici.cleanup)
        self.kok = Path(self.gecici.name)

    def dosya(self, veri, ad='kaynak.txt'):
        if isinstance(veri, str): veri = veri.encode('utf-8')
        kimlik = str(uuid.uuid4()); yol = self.kok / kimlik; yol.write_bytes(veri)
        return {'id': kimlik, 'name': ad, 'size': len(veri), 'sha256': hashlib.sha256(veri).hexdigest()}, yol

    def sec(self, dosyalar, soru='hücre bölünmesi', kontrol=lambda: None):
        return kaynak.kaynak_sec(dosyalar, soru, kontrol)

    def test_buyuk_dosyanin_sonundaki_bulgu_seciliyor(self):
        bilgi, yol = self.dosya('Günlük kayıt ve ilgisiz açıklama.\n' * 15000 + '\nMitokondri üretimi 98765 olarak ölçüldü.\n')
        self.assertGreater(bilgi['size'], 200000)
        sonuc = self.sec([(bilgi, yol)], 'Mitokondri üretimi ne kadar?')
        self.assertTrue(any('98765' in p['text'] for p in sonuc['passages']))
        self.assertTrue(sonuc['partial'])
        self.assertLessEqual(sonuc['selected_chars'], kaynak.BAGLAM_KARAKTER)
        self.assertLessEqual(len(sonuc['passages']), 12)
        self.assertIn('eksiksiz özeti değildir', kaynak.manifest(sonuc))

    def test_turkce_normalizasyon_ve_kisa_terim_tam_sozcuk(self):
        self.assertEqual(kaynak.normalize('IŞIK İÇİN ÖLÇÜM'), 'isik icin olcum')
        self.assertGreater(kaynak._puan('İNSÜLİNİN ölçümü', kaynak._eslesme_kokleri(['insulin'])), 0)
        self.assertEqual(kaynak._puan('adana', kaynak._eslesme_kokleri(['ada'])), 0)

    def test_bayt_satir_ve_utf8_blok_sinirlari(self):
        metin = 'Başlık\r\n' + 'a' * (kaynak.OKUMA_BOYUTU - 11) + 'İğne\nÖlçüm 42\n'
        bilgi, yol = self.dosya(metin)
        parcalar = list(kaynak._parcalar(bilgi, yol, lambda: None))
        veri = yol.read_bytes()
        self.assertEqual(parcalar[0]['byte_start'], 0)
        self.assertEqual(parcalar[-1]['byte_end'], len(veri))
        for p in parcalar:
            self.assertEqual(veri[p['byte_start']:p['byte_end']].decode(), p['text'])
            self.assertEqual(p['line_start'], veri[:p['byte_start']].count(b'\n') + 1)
            self.assertEqual(p['line_end'], p['line_start'] + p['text'].count('\n') - int(p['text'].endswith('\n')))
        for onceki, sonraki in zip(parcalar, parcalar[1:]):
            self.assertLess(sonraki['byte_start'], onceki['byte_end'])
            self.assertGreater(sonraki['byte_end'], onceki['byte_end'])

    def test_sozcuk_parca_sinirinda_bolunmez(self):
        metin = ('x ' * 1497) + 'mitokondri değeri 888\n' + ('y ' * 2000)
        bilgi, yol = self.dosya(metin)
        parcalar = list(kaynak._parcalar(bilgi, yol, lambda: None))
        self.assertTrue(any('mitokondri' in p['text'] for p in parcalar))
        self.assertTrue(all(len(p['text']) <= 3000 for p in parcalar))

    def test_ortusme_sinir_otesindeki_turkce_bilgiyi_korur(self):
        cumle = 'İnsülin üretiminin ölçülen değeri 7381 bulundu.'
        metin = 'x' * 2980 + ' ' + cumle + '\n' + 'y' * 5000
        bilgi, yol = self.dosya(metin)
        parcalar = list(kaynak._parcalar(bilgi, yol, lambda: None))
        self.assertTrue(any(cumle in p['text'] for p in parcalar))
        sonuc = self.sec([(bilgi, yol)], 'insülin üretimi')
        self.assertTrue(any(cumle in p['text'] for p in sonuc['passages']))

    def test_genel_ozet_ornekleme_ve_eslesmeyen_soru_acik(self):
        bilgi, yol = self.dosya('Başlangıç\n' + ' sıradan kayıt' * 20000 + '\nBitiş')
        sonuc = self.sec([(bilgi, yol)], 'Belgeyi genel olarak özetle')
        self.assertEqual(sonuc['query_terms'], [])
        self.assertTrue(any('Başlangıç' in p['text'] for p in sonuc['passages']))
        self.assertTrue(any('Bitiş' in p['text'] for p in sonuc['passages']))
        self.assertIn('orta ve son', kaynak.kapsam_notu(sonuc))
        bulunamadi = self.sec([(bilgi, yol)], 'Kuantum dolaşıklığı')
        self.assertTrue(bulunamadi['no_match'])
        self.assertIn('belgede bulunmadığını kanıtlamaz', kaynak.manifest(bulunamadi))

    def test_on_kaynagin_her_birinden_bolum_korunur(self):
        dosyalar = [self.dosya(('farklı konu ' * 1000) + f'\nHücre {i}', f'{i}.txt') for i in range(10)]
        sonuc = self.sec(dosyalar, 'hücre')
        self.assertEqual({p['file_id'] for p in sonuc['passages']}, {d['id'] for d, _ in dosyalar})
        self.assertLessEqual(len(sonuc['passages']), 12)

    def test_sinirlar_dosya_acilmadan_reddedilir(self):
        bilgi, yol = self.dosya('x')
        with patch.object(kaynak.os, 'open', side_effect=AssertionError('Dosya açılmamalı')):
            with self.assertRaises(workspace.Hata): self.sec([(dict(bilgi, size=kaynak.DOSYA_SINIRI + 1), yol)])
            with self.assertRaises(workspace.Hata): self.sec([(dict(bilgi, size=kaynak.DOSYA_SINIRI), yol)] * 3)
            with self.assertRaises(workspace.Hata): self.sec([(dict(bilgi, name='kitap.pdf'), yol)])

    def test_gecersiz_utf8_ve_ikili_veri_reddedilir(self):
        for veri in (b'a' * 70000 + b'\xff', b'a' * 70000 + b'\0', b'   \n'):
            with self.subTest(son=veri[-2:]):
                with self.assertRaises(workspace.Hata): self.sec([self.dosya(veri)])

    def test_ozet_degismis_kaynak_checkpoint_olamaz(self):
        bilgi, yol = self.dosya('Hücre 42')
        with self.assertRaises(workspace.Hata) as e:
            self.sec([(dict(bilgi, sha256='0' * 64), yol)])
        self.assertEqual(e.exception.kod, 'source_changed')

    def test_sembolik_bag_takip_edilmez(self):
        bilgi, yol = self.dosya('Hücre')
        bag = self.kok / 'bag'; bag.symlink_to(yol)
        with self.assertRaises(OSError): self.sec([(bilgi, bag)])

    def test_tarama_iptali_sonraki_bloklari_okumaz(self):
        bilgi, yol = self.dosya('Hücre\n' * 30000)
        cagrilar = []
        def kontrol():
            cagrilar.append(1)
            if len(cagrilar) == 5: raise workspace.Hata('cancelled', 'İptal')
        with self.assertRaises(workspace.Hata) as e: self.sec([(bilgi, yol)], kontrol=kontrol)
        self.assertEqual(e.exception.kod, 'cancelled')
        self.assertEqual(len(cagrilar), 5)

    def test_bellek_dosya_boyutuyla_buyumez(self):
        yol = self.kok / 'buyuk'; ozet = hashlib.sha256(); boyut = 0
        parca = b'sabit kaynak metni ve uzun belge.\n' * 1024
        with yol.open('wb') as f:
            for _ in range(128): f.write(parca); ozet.update(parca); boyut += len(parca)
        bilgi = {'id': str(uuid.uuid4()), 'name': 'buyuk.txt', 'size': boyut, 'sha256': ozet.hexdigest()}
        tracemalloc.start()
        try:
            sonuc = self.sec([(bilgi, yol)], 'belgeyi özetle')
            _, tepe = tracemalloc.get_traced_memory()
        finally: tracemalloc.stop()
        self.assertGreater(boyut, 4 * 1024 ** 2)
        self.assertLess(tepe, 6 * 1024 ** 2)
        self.assertLessEqual(len(json.dumps(sonuc).encode()), 1000000)


class ArastirmaBaglantiTestleri(unittest.TestCase):
    def setUp(self):
        self.gecici = tempfile.TemporaryDirectory(); self.addCleanup(self.gecici.cleanup)
        self.d = workspace.Depo(Path(self.gecici.name) / 'db'); self.d.kur()

    def gorev(self, metin, soru='Mitokondri sonucunu açıkla.', tur='research'):
        f = self.d.dosya_ekle('kaynak.txt', metin.encode())
        self.d.ekle({'kind': tur, 'input': {'prompt': soru, 'file_ids': [f['id']]}}, str(uuid.uuid4()))
        return self.d.al()

    def test_buyuk_kaynak_model_baglami_manifest_ve_checkpoint(self):
        g = self.gorev('İlgisiz kayıt\n' * 20000 + 'Mitokondri değeri 9973.\n')
        cagrilar = []
        def model(istem, web): cagrilar.append((istem, web)); return 'Bulgu 9973 [K1].'
        sonuc = workspace.calistir(self.d, g, model)
        self.assertEqual(len(cagrilar), 2)
        self.assertTrue(all(not web for _, web in cagrilar))
        self.assertIn('9973', cagrilar[-1][0])
        self.assertLess(len(cagrilar[-1][0]), 50000)
        self.assertIn('## İncelenen kaynak bölümleri', sonuc['content'])
        self.assertIn('bayt [', sonuc['content'])
        with self.d.baglan() as db:
            secim = json.loads(db.execute("SELECT value FROM workspace_steps WHERE job_id=? AND name='Kaynak seçimi'", (g['id'],)).fetchone()[0])
        self.assertEqual(len(secim['sources']), 1)
        self.assertTrue(secim['partial'])

    def test_120k_karakter_ustu_kucuk_dosya_da_secime_girer(self):
        g = self.gorev('sabit bilgi\n' * 12000, 'Genel özet')
        sonuc = workspace.calistir(self.d, g, lambda *a: 'Özet')
        self.assertIn('İncelenen kaynak bölümleri', sonuc['content'])

    def test_kucuk_tam_baglam_davranisi_korunur(self):
        # UTF-8 baytları 120k'yı aşsa da decoded metin 120k altındaysa eski yol korunur.
        g = self.gorev('ğü' * 40000)
        sonuc = workspace.calistir(self.d, g, lambda *a: 'Eski tam bağlam')
        self.assertEqual(sonuc['content'], 'Eski tam bağlam')

    def test_kaynak_secimi_devam_ederken_yeniden_taranmaz(self):
        g = self.gorev('İlgisiz kayıt\n' * 20000 + 'Mitokondri 42')
        yanit = iter(['Plan', RuntimeError('bağlantı')])
        def model(*a):
            deger = next(yanit)
            if isinstance(deger, Exception): raise deger
            return deger
        with self.assertRaises(RuntimeError): workspace.calistir(self.d, g, model)
        self.d.hata(g, RuntimeError()); self.d.durum(g['id'], 'resume'); yeni = self.d.al()
        with patch.object(kaynak, 'kaynak_sec', side_effect=AssertionError('Tekrar taranmamalı')):
            sonuc = workspace.calistir(self.d, yeni, lambda *a: 'Sonuç')
        self.assertIn('İncelenen kaynak bölümleri', sonuc['content'])

    def test_tarama_deadline_asiminda_model_cagrilmaz(self):
        g = self.gorev('İlgisiz kayıt\n' * 20000)
        with self.assertRaises(workspace.Hata) as e:
            workspace.calistir(self.d, g, lambda *a: self.fail('Model çağrılmamalı'), deadline=time.monotonic() - 1)
        self.assertEqual(e.exception.kod, 'resource_limit')
        self.assertEqual(self.d.ciktilar(), [])

    def test_iptal_sirasinda_secim_kaydedilmez(self):
        g = self.gorev('İlgisiz kayıt\n' * 20000)
        asil = self.d.etkinligi_dogrula; cagrilar = []
        def kontrol(gorev):
            cagrilar.append(1)
            if len(cagrilar) == 6: self.d.durum(g['id'], 'cancel')
            asil(gorev)
        with patch.object(self.d, 'etkinligi_dogrula', side_effect=kontrol):
            with self.assertRaises(workspace.Hata): workspace.calistir(self.d, g, lambda *a: self.fail('Model çağrılmamalı'))
        self.assertEqual(self.d.gorev(g['id'])['status'], 'cancelled')
        with self.d.baglan() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM workspace_steps').fetchone()[0], 0)

    def test_diger_gorevlerin_200kb_siniri_degismez(self):
        g = self.gorev('x' * 210000, tur='document')
        with self.assertRaises(workspace.Hata) as e: workspace.calistir(self.d, g, lambda *a: self.fail('Model çağrılmamalı'))
        self.assertEqual(e.exception.kod, 'resource_limit')

    def test_capabilities_arastirma_sinirlarini_ilan_eder(self):
        c = self.d.yetenekler()
        self.assertTrue(c['modules']['source_retrieval'])
        self.assertEqual(c['limits']['research_source_bytes'], 64 * 1024 ** 2)
        self.assertEqual(c['limits']['research_total_bytes'], 128 * 1024 ** 2)


if __name__ == '__main__': unittest.main()
