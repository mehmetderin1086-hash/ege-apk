import hashlib
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
import workspace


class BuyukYuklemeTestleri(unittest.TestCase):
    def setUp(self):
        # Disk kotası ayrı testte sınanır; işlev testleri geliştirici diskinin boşluğuna bağlı değildir.
        disk = patch('uploads.shutil.disk_usage')
        disk.start().return_value.free = 100 * 1024 ** 3
        self.addCleanup(disk.stop)
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.depo = workspace.Depo(Path(self.tmp.name) / 'test.db'); self.depo.kur()
        self.y = self.depo.yuklemeler
        self.veri = 'İstanbul büyük dosya içeriği'.encode() * 100

    def baslat(self, veri=None, ad='deneme.bin', anahtar=None):
        veri = self.veri if veri is None else veri
        return self.y.baslat({'name': ad, 'size': len(veri), 'sha256': hashlib.sha256(veri).hexdigest()}, anahtar or str(uuid.uuid4()))

    def parca(self, ident, ofset, veri):
        return self.y.ekle(ident, ofset, veri, hashlib.sha256(veri).hexdigest())

    def test_kesinti_yeniden_acilis_idempotent_bitir_ve_indir(self):
        r = self.baslat(); self.parca(r['id'], 0, self.veri[:70])
        self.depo.kur()
        self.assertEqual(self.y.durum(r['id'])['offset'], 70)
        self.assertEqual(self.baslat(anahtar=r['id'])['id'], r['id'])
        self.parca(r['id'], 70, self.veri[70:])
        f = self.y.bitir(r['id'])
        self.assertEqual(self.y.bitir(r['id']), f)
        self.assertEqual(self.depo.dosya(f['id'])[1].read_bytes(), self.veri)
        self.assertEqual(self.y.liste()[0]['sha256'], hashlib.sha256(self.veri).hexdigest())

    def test_hash_ofset_eksik_bitir_ve_asim_reddi(self):
        r = self.baslat()
        with self.assertRaises(workspace.Hata) as h: self.y.ekle(r['id'], 0, b'abc', '0' * 64)
        self.assertEqual(h.exception.kod, 'checksum_mismatch')
        with self.assertRaises(workspace.Hata): self.parca(r['id'], 1, b'abc')
        with self.assertRaises(workspace.Hata): self.y.bitir(r['id'])
        with self.assertRaises(workspace.Hata): self.parca(r['id'], 0, self.veri + b'!')
        self.assertEqual(self.y.durum(r['id'])['offset'], 0)

    def test_ayni_parcanin_eszamanli_tekrari_tek_yazim(self):
        r = self.baslat()
        def yaz(_):
            try: return self.parca(r['id'], 0, b'abc')['offset']
            except workspace.Hata as h: return h.kod
        with ThreadPoolExecutor(max_workers=2) as e: sonuc = list(e.map(yaz, range(2)))
        self.assertCountEqual(sonuc, [3, 'offset_conflict'])

    def test_rezervasyon_kotayi_doldurur_iptal_serbest_birakir(self):
        self.depo.kota = len(self.veri)
        r = self.baslat()
        with self.assertRaises(workspace.Hata): self.baslat(b'ab')
        with self.assertRaises(workspace.Hata): self.depo.dosya_ekle('kucuk.txt', b'x')
        self.parca(r['id'], 0, b'abc'); self.y.iptal(r['id'])
        self.assertFalse((self.y.dizin / r['id']).exists())
        self.assertTrue(self.baslat(b'ab')['id'])

    def test_disk_dolu_ve_10gb_ust_sinir(self):
        with patch('uploads.shutil.disk_usage') as alan:
            alan.return_value.free = self.y.disk_yedegi + 5
            with self.assertRaises(workspace.Hata) as h: self.baslat()
            self.assertEqual(h.exception.http, 507)
        with self.assertRaises(workspace.Hata):
            self.y.baslat({'name': 'buyuk.bin', 'size': self.y.sinir + 1, 'sha256': '0' * 64}, str(uuid.uuid4()))
        # 32 bit taşması olmadan gerçek GB boyutu rezervasyonu; veri ayırmaz.
        r = self.y.baslat({'name': 'gb.bin', 'size': 3 * 1024 ** 3, 'sha256': '0' * 64}, str(uuid.uuid4()))
        self.assertEqual(r['size'], 3 * 1024 ** 3)
        self.y.iptal(r['id'])

    def test_yanlis_tam_hash_ve_farkli_dosya_ayni_istek(self):
        r = self.baslat()
        with self.assertRaises(workspace.Hata): self.baslat(b'diger', anahtar=r['id'])
        self.parca(r['id'], 0, b'!' * len(self.veri))
        with self.assertRaises(workspace.Hata) as h: self.y.bitir(r['id'])
        self.assertEqual(h.exception.kod, 'checksum_mismatch')
        self.assertEqual(self.y.liste(), [])

    def test_crash_commit_edilmemis_fazla_bayt_kesilir(self):
        r = self.baslat(); self.parca(r['id'], 0, self.veri[:50])
        with (self.y.dizin / r['id']).open('ab') as f: f.write(b'commit edilmedi')
        self.parca(r['id'], 50, self.veri[50:]); self.y.bitir(r['id'])
        self.assertEqual(self.depo.dosya(r['id'])[1].read_bytes(), self.veri)

    def test_crash_rename_sonrasi_kayit_oncesi_kurtarilir(self):
        r = self.baslat(); self.parca(r['id'], 0, self.veri)
        (self.y.dizin / r['id']).rename(self.depo.dizin / r['id'])
        self.depo.kur()
        with self.depo.baglan() as db: self.assertEqual(db.execute('SELECT COUNT(*) FROM workspace_orphans').fetchone()[0], 0)
        self.assertEqual(self.y.bitir(r['id'])['id'], r['id'])

    def test_silme_aktif_gorev_kaynagini_korur(self):
        r = self.baslat(ad='kaynak.txt'); self.parca(r['id'], 0, self.veri); self.y.bitir(r['id'])
        self.depo.ekle({'kind': 'document', 'input': {'prompt': 'özetle', 'file_ids': [r['id']]}}, str(uuid.uuid4()))
        with self.assertRaises(workspace.Hata) as h: self.y.sil(r['id'])
        self.assertEqual(h.exception.kod, 'file_in_use')
        s = self.baslat(b'sil'); self.parca(s['id'], 0, b'sil'); self.y.bitir(s['id']); self.y.sil(s['id'])
        self.assertEqual(len(self.y.liste()), 1)

    def test_yol_gecisi_ve_gecersiz_veri(self):
        for ad in ['../x', 'a/b', 'a\\b', 'a\0b']:
            with self.assertRaises(workspace.Hata): self.baslat(ad=ad)
        with self.assertRaises(workspace.Hata): self.baslat(b'')

    def test_mevcut_dosya_kimligi_yuklemeyle_ezilemez(self):
        eski = self.depo.dosya_ekle('koru.txt', b'korunan')
        with self.assertRaises(workspace.Hata): self.baslat(anahtar=eski['id'])
        self.assertEqual(self.depo.dosya(eski['id'])[1].read_bytes(), b'korunan')

    def test_yarim_oturumlar_kurtarilir_ve_dosya_yolundan_silinmez(self):
        r = self.baslat(); self.parca(r['id'], 0, b'abc')
        self.assertEqual(self.y.bekleyenler()[0]['offset'], 3)
        with self.assertRaises(workspace.Hata) as h: self.y.sil(r['id'])
        self.assertEqual(h.exception.http, 404)
        self.assertEqual(self.y.durum(r['id'])['status'], 'uploading')
        self.assertTrue((self.y.dizin / r['id']).exists())

    def test_checkpoint_ciktisi_silinemez(self):
        self.depo.ekle({'kind': 'document', 'input': {'prompt': 'hazırla'}}, str(uuid.uuid4()))
        g = self.depo.al()
        sonuc = self.depo.dosyali_adim(g, 'ara çıktı', lambda: {'markdown': 'hazır', 'files': [{'name': 'sonuc.txt', 'data': b'koru'}]})
        with self.assertRaises(workspace.Hata): self.y.sil(sonuc['files'][0])

    def test_gorev_ekleme_sirasinda_silinmis_kaynak_reddi(self):
        f = self.depo.dosya_ekle('kaynak.txt', b'kaynak')
        def oku_ve_sil(ident):
            sonuc = workspace.Depo.dosya(self.depo, ident)
            self.y.sil(ident)
            return sonuc
        with patch.object(self.depo, 'dosya', side_effect=oku_ve_sil):
            with self.assertRaises(workspace.Hata):
                self.depo.ekle({'kind': 'document', 'input': {'prompt': 'özetle', 'file_ids': [f['id']]}}, str(uuid.uuid4()))
        self.assertEqual(self.depo.gorevler(), [])

    def test_alternatif_uuid_yazimindaki_kaynak_silinemez(self):
        f = self.depo.dosya_ekle('kaynak.txt', b'kaynak')
        self.depo.ekle({'kind': 'document', 'input': {'prompt': 'özetle', 'file_ids': [uuid.UUID(f['id']).hex]}}, str(uuid.uuid4()))
        with self.assertRaises(workspace.Hata) as h: self.y.sil(f['id'])
        self.assertEqual(h.exception.kod, 'file_in_use')
