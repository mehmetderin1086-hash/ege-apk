"""Dosyalı Python analizi. Yalnız ayrı runner hizmetinden çağrılır; kabuk kullanmaz."""
import base64
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import uuid
import zipfile
import resource

EN_FAZLA = 25 * 1024 ** 2
KUTUPHANE_SURUMU = 'asistan-analysis:1'

def dogrula(istek):
    kod = istek.get('code')
    if not isinstance(kod, str) or not kod.strip() or len(kod.encode()) > 64000:
        raise ValueError('Geçersiz analiz kodu.')
    dosyalar = istek.get('files')
    if not isinstance(dosyalar, list) or not 1 <= len(dosyalar) <= 5:
        raise ValueError('Analiz için 1–5 dosya gerekli.')
    sonuc, toplam, adlar = [], 0, set()
    for d in dosyalar:
        if not isinstance(d, dict): raise ValueError('Geçersiz dosya.')
        ad = d.get('name', '')
        if not isinstance(ad, str) or Path(ad).name != ad or '\\' in ad or len(ad) > 100:
            raise ValueError('Geçersiz dosya adı.')
        if Path(ad).suffix.lower() not in ('.csv', '.json', '.xlsx', '.txt') or ad in adlar:
            raise ValueError('Desteklenmeyen veya yinelenen dosya adı.')
        try: veri = base64.b64decode(d['data'], validate=True)
        except (ValueError, TypeError, KeyError): raise ValueError('Geçersiz dosya verisi.')
        toplam += len(veri)
        if not veri or toplam > EN_FAZLA: raise ValueError('Analiz girdisi en fazla 25 MB olabilir.')
        if ad.lower().endswith('.xlsx'):
            try:
                with zipfile.ZipFile(io.BytesIO(veri)) as z:
                    if len(z.infolist()) > 10000 or sum(x.file_size for x in z.infolist()) > 200 * 1024 ** 2:
                        raise ValueError('Açılmış Excel içeriği çok büyük.')
                    if '[Content_Types].xml' not in z.namelist(): raise ValueError('Geçersiz XLSX.')
            except zipfile.BadZipFile: raise ValueError('Geçersiz XLSX.')
        adlar.add(ad); sonuc.append((ad, veri))
    return kod, sonuc


# Üretilen kod ayrı çocuk süreçtedir; raporlayıcı sabit ve salt okunur bağlanır.
RAPORLAYICI = r'''
import subprocess, json, pathlib, base64, os
os.environ['MPLBACKEND'] = 'Agg'
os.environ['MPLCONFIGDIR'] = '/tmp/matplotlib'
with open('/tmp/program.log', 'wb') as log:
    try:
        result = subprocess.run(['python', '-I', '/input/main.py'], cwd='/output', stdout=log, stderr=subprocess.STDOUT, timeout=55)
        status = result.returncode
    except subprocess.TimeoutExpired:
        status = 124
files = []
for p in sorted(pathlib.Path('/output').iterdir()):
    if p.is_symlink() or not p.is_file() or p.suffix.lower() not in ('.png','.csv','.json','.txt','.xlsx'):
        continue
    if p.stat().st_size > 1024 * 1024 or len(files) >= 8:
        continue
    data = p.read_bytes()
    if p.suffix.lower() == '.png' and not data.startswith(b'\x89PNG\r\n\x1a\n'):
        continue
    files.append({'name': p.name, 'data': base64.b64encode(data).decode()})
print(json.dumps({'exit_code': status, 'output': pathlib.Path('/tmp/program.log').read_bytes()[:32000].decode(errors='replace'), 'files': files, 'timeout': status == 124}))
'''


def calistir(istek, kok, docker='/usr/bin/docker'):
    kod, dosyalar = dogrula(istek)
    ad = 'asistan-analysis-' + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(dir=kok) as gecici:
        os.chmod(gecici, 0o755)
        for isim, veri in dosyalar + [('main.py', kod.encode()), ('report.py', RAPORLAYICI.encode())]:
            p = Path(gecici) / isim; p.write_bytes(veri); p.chmod(0o444)
        komut = [docker, 'run', '--name', ad, '--network', 'none', '--read-only', '--cap-drop', 'ALL',
                 '--security-opt', 'no-new-privileges', '--user', '65534:65534', '--memory', '2g', '--memory-swap', '2g',
                 '--cpus', '2', '--pids-limit', '64', '--ulimit', 'fsize=8388608:8388608', '--log-driver', 'none',
                 '--tmpfs', '/tmp:rw,noexec,nosuid,size=32m', '--tmpfs', '/output:rw,noexec,nosuid,size=64m,mode=1777',
                 '--mount', 'type=bind,src=' + gecici + ',dst=/input,readonly',
                 KUTUPHANE_SURUMU, 'python', '-I', '/input/report.py']
        try:
            with tempfile.TemporaryFile() as log:
                sonuc = subprocess.run(komut, stdout=log, stderr=subprocess.STDOUT, timeout=60, env={'PATH': '/usr/bin:/bin'}, preexec_fn=cikti_siniri)
                log.seek(0); ham = log.read(12 * 1024 ** 2)
            if sonuc.returncode != 0: raise ValueError('Yalıtılmış analiz ortamı başlatılamadı.')
            veri = json.loads(ham)
            if not isinstance(veri, dict) or type(veri.get('exit_code')) is not int: raise ValueError('Geçersiz analiz sonucu.')
            return veri
        except subprocess.TimeoutExpired:
            return {'exit_code': 124, 'output': 'Analiz süre sınırına ulaştı.', 'files': [], 'timeout': True}
        finally:
            subprocess.run([docker, 'rm', '-f', ad], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)


def cikti_siniri():
    resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024 ** 2, 16 * 1024 ** 2))
