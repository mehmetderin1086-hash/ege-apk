#!/usr/bin/env python3
"""Asistan'ın tüm test katmanlarını çalıştırır; sonuç ve atlamalar ayrı kaydedilir."""
import argparse, datetime, fcntl, json, os, pathlib, re, signal, subprocess, sys, time
KOK = pathlib.Path(__file__).resolve().parents[2]
CIKTI = pathlib.Path.home() / 'Developer/.build/asistan-test-merkezi'
ASAMALAR = ['birim', 'arayuz', 'sunucu', 'otomasyon', 'canli', 'cihaz']

def komutlar(ad):
    temel = ['xcodebuild', 'test', '-project', 'Asistan.xcodeproj', '-scheme', 'Asistan', '-destination',
             'platform=iOS Simulator,id=' + os.environ.get('ASISTAN_SIM_UDID', 'B3D3ABF3-2FE1-4EEA-8896-8386034F6802'),
             '-parallel-testing-enabled', 'NO']
    if ad == 'birim': return [(temel + ['-testPlan', 'Tam', '-skip-testing:AsistanUITests'], KOK, 1200)]
    if ad == 'arayuz': return [(['zsh', 'araclar/test-merkezi/cihaz-ui.sh'], KOK, 5400)]
    if ad == 'canli':
        plan = json.loads((KOK/'Planlar/Canli.xctestplan').read_text())
        siniflar = next(t['selectedTests'] for t in plan['testTargets'] if t['target']['name'] == 'AsistanTests')
        # Swift Testing sınıfları bu Xcode sürümünde plan seçimiyle sıfır test
        # çalıştırabiliyor. CLI seçimiyle ayrı koş; UI başarısı bunu örtemesin.
        return [(['env', 'ASISTAN_TEST_PLANI=Tam', 'zsh', 'araclar/test-merkezi/cihaz-ui.sh', 'ASISTAN_CANLI=1']
                 + ['-only-testing:AsistanTests/'+s for s in siniflar], KOK, 5400),
                (['env', 'ASISTAN_TEST_PLANI=Canli', 'zsh', 'araclar/test-merkezi/cihaz-ui.sh',
                  '-only-testing:AsistanUITests', 'ASISTAN_CANLI=1'], KOK, 1800)]
    if ad == 'sunucu': return [([sys.executable, '-m', 'unittest', 'discover', '-p', 'test_*.py', '-v'], KOK / 'vps/asistan-jobs', 900)]
    if ad == 'otomasyon':
        return [([sys.executable, '-I', 'araclar/testler/test_kabul_karsilastir.py'], KOK, 120)] + [(['zsh', str(p)], KOK, 180) for p in sorted((KOK/'araclar/testler').glob('*.sh'))]
    # Cihaz testleri kendi koşu kimliğini, kurulum kilidini ve rapor dosyalarını doğrular.
    if ad == 'cihaz': return [(['zsh', 'araclar/cihaz-kabul.sh', '--yalniz',
        'live-sinama,ses-sinama,ses-akis-sinama,ofis-sinama,donusturme-sinama,arsiv-sinama,hiz-kabul,ilk-metin-sinama,kazima-sinama,sinama,gelen-kutusu-sinama,indirme-sinama,atolye-sinama,live-baglanti-sinama,sunucu-sinama,web-yeni'], KOK, 4200)]
    raise ValueError(ad)

def ozet(metin):
    return [s.strip()[:800] for s in metin.splitlines() if re.search(r'✘|skipped| skipped | failed|error:|FAILED|SUCCEEDED|Test run with|Executed \d+|^Ran \d+|^OK|^FAIL|hata|başarısız', s, re.I)][-150:]

def test_sayilari(metin):
    yollar = re.findall(r"^\s*(/[^\n\r]+\.xcresult)\s*$", metin, re.M)
    if yollar:
        try:
            ham = subprocess.check_output(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', yollar[-1]], timeout=30)
            d = json.loads(ham)
            return {k:d.get(k, 0) for k in ['totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures']} | {'xcresult':yollar[-1]}
        except (OSError, ValueError, subprocess.SubprocessError): pass
    m = re.search(r'Ran (\d+) tests?', metin)
    if m: return {'totalTestCount':int(m[1]), 'passedTests':int(m[1]) if re.search(r'^OK$', metin, re.M) else None}
    return {}

def katman_durumu(kodlar, sayilar, xcode=False):
    if not kodlar or any(k != 0 for k in kodlar) or any(x.get('failedTests', 0) for x in sayilar): return 'Başarısız'
    if xcode and (not sayilar or any(not x.get('passedTests', 0) for x in sayilar)): return 'Doğrulanamadı'
    if any(x.get('skippedTests', 0) for x in sayilar): return 'Kısmen geçti'
    return 'Geçti'

def yaz(rapor):
    gecici = CIKTI/'sonuc.tmp'
    gecici.write_text(json.dumps(rapor, ensure_ascii=False, indent=2))
    gecici.replace(CIKTI/'sonuc.json')
    satirlar = ['ASISTAN TEST SONUÇLARI', 'Başlangıç: '+rapor['baslangic'],
                'Durum: '+('Çalışıyor: '+rapor['etkin'] if rapor['calisiyor'] else 'Tur bitti'), '']
    for katman in rapor['katmanlar']:
        satirlar.append(katman['ad']+': '+katman['durum'])
        for sayi in katman.get('testSayilari', []):
            if sayi:
                satirlar.append('  Geçti: %s | Başarısız: %s | Atlandı: %s' %
                                (sayi.get('passedTests', '?'), sayi.get('failedTests', '?'), sayi.get('skippedTests', '?')))
        if katman.get('gunlukKlasoru'): satirlar.append('  Kanıt: '+katman['gunlukKlasoru'])
    satirlar += ['', 'KABUL SINIRLARI'] + rapor['sinirlar']
    (CIKTI/'sonuc.txt').write_text('\n'.join(satirlar)+'\n')

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--asama', default=','.join(ASAMALAR))
    p.add_argument('--birim-gunlugu', help='Bu oturumda önceden koşulan birim testinin günlüğünü rapora al')
    a=p.parse_args()
    secilen=a.asama.split(',')
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    if any(x not in ASAMALAR for x in secilen): p.error('Bilinmeyen test katmanı')
    CIKTI.mkdir(parents=True, exist_ok=True)
    kilit=open(CIKTI/'calisma.kilit','w')
    try: fcntl.flock(kilit, fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError: print('Test turu zaten çalışıyor.'); return 75
    tur=CIKTI/datetime.datetime.now().strftime('%Y%m%d-%H%M%S');tur.mkdir()
    rapor={'baslangic':datetime.datetime.now().isoformat(), 'calisiyor':True, 'pid':os.getpid(), 'etkin':'',
           'katmanlar':[], 'testDosyalari':[str(x.relative_to(KOK)) for d in ['AsistanTests','AsistanUITests'] for x in sorted((KOK/d).glob('*.swift'))],
           'sinirlar':['Atlanan testler geçti sayılmaz.', 'Birim testleri fiziksel donanım kabulü değildir.',
           'Siri, Bluetooth, kilit ekranı, kimlik doğrulama ve dış uygulamada teslim ayrıca gerçek cihaz kabulü gerektirir.',
           'Canlı servis hataları mevcut servis durumunu gösterir; model yanıt kalitesinin tüm olası girdilerini kanıtlamaz.']}
    yaz(rapor)
    try:
        for ad in ASAMALAR:
            if ad not in secilen:
                rapor['katmanlar'].append({'ad':ad,'durum':'Koşulmadı','ozet':[]});yaz(rapor);continue
            rapor['etkin']=ad;yaz(rapor);print('Çalışıyor: '+ad, flush=True)
            bas=time.monotonic();sonuclar=[];satirlar=[];sayilar=[]
            if ad=='birim' and a.birim_gunlugu:
                metin=pathlib.Path(a.birim_gunlugu).read_text(errors='replace')
                sonuclar=[0 if '** TEST SUCCEEDED **' in metin else 1];satirlar=ozet(metin)
                (tur/'birim-0.log').write_text(metin);sayilar.append(test_sayilari(metin))
            else:
                for i,(komut,dizin,sinir) in enumerate(komutlar(ad)):
                    gunluk=tur/f'{ad}-{i}.log'
                    with gunluk.open('w') as f:
                        islem=subprocess.Popen(komut,cwd=dizin,stdout=f,stderr=subprocess.STDOUT,start_new_session=True)
                        try: kod=islem.wait(timeout=sinir)
                        except subprocess.TimeoutExpired:
                            os.killpg(islem.pid,signal.SIGTERM)
                            try: islem.wait(timeout=15)
                            except subprocess.TimeoutExpired: os.killpg(islem.pid,signal.SIGKILL);islem.wait()
                            kod=124;f.write('\nZaman sınırı aşıldı; test başarılı sayılmadı.\n')
                        except BaseException:
                            os.killpg(islem.pid,signal.SIGTERM);islem.wait(timeout=15);raise
                    sonuclar.append(kod);metin=gunluk.read_text(errors='replace');satirlar+=ozet(metin);sayilar.append(test_sayilari(metin))
            rapor['katmanlar'].append({'ad':ad,'durum':katman_durumu(sonuclar, sayilar, ad in ['birim', 'arayuz', 'canli']),
                'kodlar':sonuclar,'testSayilari':sayilar,'sureSn':round(time.monotonic()-bas,1),'ozet':satirlar,'gunlukKlasoru':str(tur)})
            yaz(rapor)
    except BaseException as hata:
        rapor['katmanlar'].append({'ad':rapor['etkin'] or 'tur', 'durum':'Yarıda kaldı', 'ozet':[type(hata).__name__]})
        raise
    finally:
        rapor['calisiyor']=False;rapor['etkin']='';rapor['bitis']=datetime.datetime.now().isoformat();yaz(rapor)
        (tur/'sonuc.json').write_text(json.dumps(rapor,ensure_ascii=False,indent=2))
    return int(any(x['durum'] in ['Başarısız', 'Yarıda kaldı', 'Doğrulanamadı'] for x in rapor['katmanlar']))
if __name__=='__main__': sys.exit(main())
