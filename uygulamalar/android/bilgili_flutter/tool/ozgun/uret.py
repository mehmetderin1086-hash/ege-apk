#!/usr/bin/env python3
"""Özgün soru dosyalarından (her alt alan için son.jsonl) Dart veri dosyaları üretir.
usage: python3 tool/ozgun/uret.py <ozgun_klasoru> <alanlar.json> [mevcut_secki.jsonl]
Banka genelinde aynı ya da sözcük kümesi bakımından %25'ten yakın kökler elenir."""
import json,re,sys,os,collections
kok_dir,alan_yol=sys.argv[1],sys.argv[2]; mevcut=sys.argv[3] if len(sys.argv)>3 else None
ALAN=json.load(open(alan_yol,encoding='utf-8'))
kel=re.compile(r'[a-zçğıöşüâîû0-9]+')
def kume(s): return frozenset(w for w in kel.findall(s.lower()) if len(w)>=2)
def duz(s): return re.sub(r'\s+',' ',s.lower()).strip()
ESIK=0.25
gorulen=set(); kumeler=[]; ters=collections.defaultdict(list)
def benzer(k):
    sayac=collections.Counter()
    for w in k:
        for j in ters[w]: sayac[j]+=1
    for j,ort in sayac.items():
        b=kumeler[j]
        if 1-ort/(len(k)+len(b)-ort) < ESIK: return True
    return False
def ekle(k):
    j=len(kumeler); kumeler.append(k)
    for w in k: ters[w].append(j)
if mevcut:
    for l in open(mevcut,encoding='utf-8'):
        r=json.loads(l); gorulen.add(duz(r['soru'])); ekle(kume(r['soru']))
NOT=re.compile(r'\s+\([^()]*\)\s*$')
def notsuz(r):
    # Yalnız bazı seçeneklerin sonundaki parantezli not, doğru yanıtı ele verir.
    d=r['dogru']; w=list(r['yanlis'])
    dn=bool(NOT.search(d)); wn=[bool(NOT.search(x)) for x in w]
    if not dn and any(wn): w2=[NOT.sub('',x) if n else x for x,n in zip(w,wn)]; d2=d
    elif dn and not any(wn): d2=NOT.sub('',d); w2=w
    else: return r, 0
    if len({x.lower() for x in [d2,*w2]})<4 or not all(x.strip() for x in [d2,*w2]): return r, 0
    return {**r,'dogru':d2,'yanlis':w2}, 1
# Anlamsal tekrar taraması kararları: <kok>/tekrar/<topic>/sil.json, secenek.json
SIL=set(); SEC={}
import glob as _g
for f in _g.glob(f'{kok_dir}/tekrar/*/sil.json'):
    for e in json.load(open(f,encoding='utf-8')): SIL.add(e['id'])
for f in _g.glob(f'{kok_dir}/tekrar/*/secenek.json'):
    for e in json.load(open(f,encoding='utf-8')): SEC.setdefault(e['id'],[]).append((e['eski'],e['yeni']))
_geri=f'{kok_dir}/tekrar/geri_al.json'
if os.path.exists(_geri): SIL-=set(json.load(open(_geri,encoding='utf-8')))
def secenek_duzelt(sid,r):
    for eski,yeni in SEC.get(sid,[]):
        w=[yeni if x==eski else x for x in r['yanlis']]
        if w!=r['yanlis'] and len({x.lower() for x in [r['dogru'],*w]})==4: r={**r,'yanlis':w}
    return r
ZOR={'kolay':'easy','orta':'medium','zor':'hard'}
BLOOM={'hatirlama':'hatirlama','anlama':'anlama','uygulama':'uygulama','analiz':'analiz','degerlendirme':'degerlendirme'}
def dq(s): return "'"+s.replace('\\','\\\\').replace("'","\\'").replace('$','\\$').replace('\n','\\n')+"'"
cikti='lib/data/advanced/ozgun'; os.makedirs(cikti,exist_ok=True)
aileler=[]; toplam=0; elenen=0; duzeltilen=0; tekrar_sil=0; rapor=[]
for a in ALAN:
    p=f'{kok_dir}/{a["id"]}/son.jsonl'
    if not os.path.exists(p): rapor.append(f'{a["id"]}: son.jsonl yok'); continue
    gruplar=collections.defaultdict(list)
    for n,l in enumerate(open(p,encoding='utf-8'),1):
        if not l.strip(): continue
        sid=f'{a["id"]}_{n}'
        if sid in SIL: tekrar_sil+=1; continue
        r,dz=notsuz(secenek_duzelt(sid,json.loads(l))); duzeltilen+=dz; k=kume(r['soru']); d=duz(r['soru'])
        if d in gorulen or benzer(k): elenen+=1; continue
        gorulen.add(d); ekle(k)
        gruplar[r.get('zorluk','orta')].append(r)
    for zor,rows in gruplar.items():
        if zor not in ZOR: zor='orta'
        key=f'oz_{a["id"]}_{zor}'; ad=f'oz{a["id"].title().replace("_","")}{zor.title()}'
        bloom=collections.Counter(BLOOM.get(r.get('bloom'),'anlama') for r in rows).most_common(1)[0][0]
        with open(f'{cikti}/{key.lower()}.dart','w',encoding='utf-8') as f:
            f.write(f'// Üretilen dosya: tool/ozgun/uret.py. {a["kategori"]} · {a["alan"]} ({zor}).\n')
            f.write(f'const {ad} = <(String, String, List<String>, String)>[\n')
            for r in rows:
                f.write(f'  ({dq(r["soru"])}, {dq(r["dogru"])}, [{", ".join(dq(x) for x in r["yanlis"])}], {dq(r["aciklama"])}),\n')
            f.write('];\n')
        aileler.append((key,ad,a,zor,bloom,len(rows))); toplam+=len(rows)
with open(f'{cikti}/ozgun.dart','w',encoding='utf-8') as f:
    f.write('// Üretilen dosya: tool/ozgun/uret.py. Elle yazılmış, birbirinden ayrışan özgün\n// çoktan seçmeli sorular; her aile bir alt alanın bir zorluk düzeyidir.\n')
    f.write("import '../common.dart';\n")
    for key,ad,*_ in aileler: f.write(f"import '{key.lower()}.dart';\n")
    f.write('\nAdvancedFamily _aile(String key, String title, Topic topic, Difficulty d, BloomLevel b, List<(String, String, List<String>, String)> v) =>\n    AdvancedFamily(key: key, title: title, topic: topic, level: StudyLevel.lise, count: v.length, difficulty: d, bloom: b,\n        lesson: title, sourceLabel: \'Bilgili · Özgün Soru Bankası\', build: (i) => AdvancedItem(v[i].$1, v[i].$2, v[i].$3, v[i].$4));\n\n')
    f.write('final ozgunAileler = <AdvancedFamily>[\n')
    for key,ad,a,zor,bloom,n in aileler:
        f.write(f"  _aile('{key}', {dq(a['alan'].split(' (')[0])}, Topic.{a['topic']}, Difficulty.{ZOR[zor]}, BloomLevel.{bloom}, {ad}),\n")
    f.write('];\n')
print(f'tekrar taramasında silinen {tekrar_sil}, seçenek düzeltme kaydı {sum(map(len,SEC.values()))}')
print(f'parantez ipucu temizlenen {duzeltilen}')
print(f'aile {len(aileler)}, soru {toplam}, benzer/yinelenen diye elenen {elenen}')
for r in rapor: print(' -',r)
