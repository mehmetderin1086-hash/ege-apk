"""GB dosyalarını sabit bellekle, doğrulanmış parçalarla ve kalıcı ofsetle saklar."""
import contextlib
import fcntl
import hashlib
import os
import re
import shutil
import time
from pathlib import Path
from workspace import Hata, kimlik, metin


class Yuklemeler:
    parca = 8 * 1024 ** 2

    def __init__(self, depo):
        self.depo = depo
        self.dizin = Path(str(depo.dizin) + '.uploads')
        self.sinir = int(os.environ.get('ASISTAN_FILE_MAX_BYTES', 10 * 1024 ** 3))
        self.disk_yedegi = 2 * 1024 ** 3

    @contextlib.contextmanager
    def kilit(self, ident):
        # Ayrı HTTP iş parçacıkları ve yeniden başlayan süreçler aynı kilidi kullanır.
        with open(self.dizin / (kimlik(ident) + '.lock'), 'a+b') as f:
            os.chmod(f.name, 0o600)
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            yield

    def _satir(self, db, ident):
        satir = db.execute('SELECT * FROM workspace_uploads WHERE id=?', (kimlik(ident),)).fetchone()
        if not satir: raise Hata('not_found', 'Yükleme bulunamadı.', 404)
        return dict(satir)

    def durum(self, ident):
        with self.depo.baglan() as db:
            r = self._satir(db, ident)
            r['chunk_bytes'] = self.parca
            return r

    def bekleyenler(self):
        with self.depo.baglan() as db:
            return [dict(r, chunk_bytes=self.parca) for r in db.execute("SELECT * FROM workspace_uploads WHERE status='uploading' ORDER BY created")]

    def baslat(self, girdi, anahtar):
        ident = kimlik(anahtar)
        ad = metin(girdi.get('name'), 160)
        boyut, ozet = girdi.get('size'), girdi.get('sha256')
        if Path(ad).name != ad or '\\' in ad or any(ord(c) < 32 for c in ad):
            raise Hata('invalid_input', 'Geçersiz dosya adı.')
        if type(boyut) is not int or not 1 <= boyut <= self.sinir:
            raise Hata('resource_limit', 'Dosya izin verilen yükleme sınırını aşıyor.', 413)
        if not isinstance(ozet, str) or not re.fullmatch('[a-f0-9]{64}', ozet):
            raise Hata('invalid_input', 'Dosyanın SHA-256 özeti gerekli.')
        with self.kilit(ident), self.depo.baglan() as db:
            db.execute('BEGIN IMMEDIATE')
            eski = db.execute('SELECT * FROM workspace_uploads WHERE id=?', (ident,)).fetchone()
            if eski:
                if (eski['name'], eski['size'], eski['sha256']) != (ad, boyut, ozet):
                    raise Hata('idempotency_conflict', 'Bu yükleme başka bir dosyaya ait.', 409)
                if eski['status'] == 'cancelled': raise Hata('cancelled', 'Yükleme iptal edilmiş.', 410)
            else:
                if (self.depo.dizin / ident).exists() or db.execute('SELECT 1 FROM workspace_files WHERE id=?', (ident,)).fetchone() or db.execute('SELECT 1 FROM workspace_orphans WHERE id=?', (ident,)).fetchone():
                    raise Hata('idempotency_conflict', 'Bu kimlik mevcut bir dosyaya ait.', 409)
                if db.execute("SELECT COUNT(*) FROM workspace_uploads WHERE status='uploading'").fetchone()[0] >= 3:
                    raise Hata('quota_exceeded', 'En fazla üç yarım yükleme tutulabilir. Birini tamamlayın veya silin.', 409)
                self.depo.alan_kontrol(db, boyut)
                bekleyen = db.execute("SELECT COALESCE(SUM(size-offset),0) FROM workspace_uploads WHERE status='uploading'").fetchone()[0]
                if shutil.disk_usage(self.dizin).free - bekleyen - boyut < self.disk_yedegi:
                    raise Hata('insufficient_storage', 'Sunucuda bu dosya için yeterli boş alan yok.', 507)
                simdi = time.time()
                db.execute('INSERT INTO workspace_uploads(id,name,size,sha256,created,updated) VALUES (?,?,?,?,?,?)', (ident, ad, boyut, ozet, simdi, simdi))
        return self.durum(ident)

    def ekle(self, ident, ofset, veri, ozet):
        ident = kimlik(ident)
        if type(ofset) is not int or ofset < 0 or not 1 <= len(veri) <= self.parca:
            raise Hata('invalid_input', 'Parça boyutu veya konumu geçersiz.')
        if hashlib.sha256(veri).hexdigest() != ozet:
            raise Hata('checksum_mismatch', 'Parça bütünlük kontrolünden geçmedi.', 422)
        with self.kilit(ident), self.depo.baglan() as db:
            db.execute('BEGIN IMMEDIATE')
            r = self._satir(db, ident)
            if r['status'] != 'uploading': raise Hata('upload_closed', 'Yükleme açık değil.', 409)
            if ofset != r['offset']: raise Hata('offset_conflict', 'Kaydedilmiş konum değişti; yüklemeyi yenileyin.', 409)
            if ofset + len(veri) > r['size']: raise Hata('resource_limit', 'Parça dosya boyutunu aşıyor.', 413)
            if shutil.disk_usage(self.dizin).free - len(veri) < self.disk_yedegi:
                raise Hata('insufficient_storage', 'Sunucu diski doldu. Kaydedilmiş parçalar korundu.', 507)
            yol = self.dizin / ident
            with open(yol, 'r+b' if yol.exists() else 'w+b') as f:
                os.chmod(yol, 0o600)
                if os.fstat(f.fileno()).st_size < ofset: raise Hata('storage_error', 'Kaydedilmiş parça eksik.', 409)
                # fsync sonrası commit öncesi kapanışta yalnız DB'nin onayladığı baytlar kalır.
                f.truncate(ofset); f.seek(ofset); f.write(veri); f.flush(); os.fsync(f.fileno())
            db.execute('UPDATE workspace_uploads SET offset=?,updated=? WHERE id=?', (ofset + len(veri), time.time(), ident))
        return self.durum(ident)

    def bitir(self, ident):
        ident = kimlik(ident)
        with self.kilit(ident):
            r = self.durum(ident)
            if r['status'] == 'completed': return self.depo.dosya(ident)[0]
            if r['status'] != 'uploading' or r['offset'] != r['size']:
                raise Hata('incomplete_upload', 'Dosyanın bütün parçaları henüz yüklenmedi.', 409)
            gecici, hedef = self.dizin / ident, self.depo.dizin / ident
            # rename sonrası DB commit'ten önce sert kapanış da yeniden tamamlanabilir.
            yol = gecici if gecici.exists() else hedef
            h = hashlib.sha256()
            with yol.open('rb') as f:
                while parca := f.read(1024 ** 2): h.update(parca)
            if yol.stat().st_size != r['size'] or h.hexdigest() != r['sha256']:
                raise Hata('checksum_mismatch', 'Dosya doğrulanamadı. Yüklemeyi silip yeniden başlatın.', 422)
            with self.depo.baglan() as db:
                db.execute('BEGIN IMMEDIATE')
                if db.execute('SELECT 1 FROM workspace_files WHERE id=?', (ident,)).fetchone():
                    raise Hata('idempotency_conflict', 'Mevcut dosya üzerine yazılamaz.', 409)
                if gecici.exists() and hedef.exists():
                    raise Hata('idempotency_conflict', 'Dosya hedefi dolu; mevcut veri korundu.', 409)
                if gecici.exists(): os.replace(gecici, hedef)
                # Dizin girdisi de elektrik kesilmesinden önce kalıcı olsun.
                fd = os.open(self.depo.dizin, os.O_RDONLY)
                try: os.fsync(fd)
                finally: os.close(fd)
                db.execute('INSERT INTO workspace_files VALUES (?,?,?,?,?)', (ident, r['name'], r['size'], r['sha256'], time.time()))
                db.execute("UPDATE workspace_uploads SET status='completed',updated=? WHERE id=?", (time.time(), ident))
        return self.depo.dosya(ident)[0]

    def iptal(self, ident):
        ident = kimlik(ident)
        with self.kilit(ident), self.depo.baglan() as db:
            db.execute('BEGIN IMMEDIATE')
            r = self._satir(db, ident)
            if r['status'] == 'completed': raise Hata('upload_closed', 'Tamamlanmış dosyayı dosya listesinden silin.', 409)
            (self.dizin / ident).unlink(missing_ok=True)
            # Yalnız bu oturumun commit edilmemiş tamamlama dosyası.
            if not db.execute('SELECT 1 FROM workspace_files WHERE id=?', (ident,)).fetchone():
                (self.depo.dizin / ident).unlink(missing_ok=True)
            db.execute("UPDATE workspace_uploads SET status='cancelled',updated=? WHERE id=?", (time.time(), ident))
        return {'cancelled': True}

    def liste(self):
        with self.depo.baglan() as db:
            return [dict(r) for r in db.execute('SELECT * FROM workspace_files ORDER BY created DESC LIMIT 200')]

    def sil(self, ident):
        ident = kimlik(ident)
        with self.kilit(ident), self.depo.baglan() as db:
            db.execute('BEGIN IMMEDIATE')
            if not db.execute('SELECT 1 FROM workspace_files WHERE id=?', (ident,)).fetchone():
                raise Hata('not_found', 'Tamamlanmış dosya bulunamadı. Yarım yüklemeyi kendi listesinden iptal edin.', 404)
            def ayni(deger):
                try: return kimlik(deger) == ident
                except Hata: return False
            referanslar = db.execute("SELECT f.value FROM workspace_jobs j,json_each(j.request,'$.input.file_ids') f UNION ALL SELECT f.value FROM workspace_steps s,json_each(s.value,'$.files') f")
            if db.execute('SELECT 1 FROM workspace_artifact_files WHERE file_id=?', (ident,)).fetchone() or any(ayni(r[0]) for r in referanslar):
                raise Hata('file_in_use', 'Dosya bir çalışmaya bağlı; silinmedi.', 409)
            (self.depo.dizin / ident).unlink(missing_ok=True)
            db.execute('DELETE FROM workspace_files WHERE id=?', (ident,))
            db.execute("UPDATE workspace_uploads SET status='cancelled',updated=? WHERE id=?", (time.time(), ident))
        return {'deleted': True}
