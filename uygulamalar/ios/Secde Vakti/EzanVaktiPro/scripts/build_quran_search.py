"""Refresh the verbatim QuranEnc offline search corpus; validate every chapter."""
import subprocess, concurrent.futures, hashlib, json, pathlib, time, urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
TARGET=ROOT/'Sekine/Resources/QuranSearch'
KEY='turkish_rwwad'
def get(url):
    for attempt in range(4):
        try:
            return json.loads(subprocess.check_output(["curl", "-L", "--fail", "--max-time", "30", "-s", url]))
        except Exception:
            if attempt==3: raise
            time.sleep(2**attempt)
metadata=next(x for x in get('https://quranenc.com/api/v1/translations/list/tr')['translations'] if x['key']==KEY)
chapters=json.loads((ROOT/'Sekine/Resources/kuran_bilmek_offline.json').read_text())['chapters']
def fetch(chapter):
    sid=chapter['id']
    rows=get(f'https://quranenc.com/api/v1/translation/sura/{KEY}/{sid}')['result']
    assert len(rows)==chapter['verses_count'],sid
    for ayah,row in enumerate(rows,1):
        assert int(row['sura'])==sid and int(row['aya'])==ayah and row['arabic_text'] and row['translation'], (sid,ayah)
    return rows
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    rows=[row for chapter in pool.map(fetch,chapters) for row in chapter]
assert len(rows)==6236 and len({(r['sura'],r['aya']) for r in rows})==6236
TARGET.mkdir(exist_ok=True)
payload={'metadata':metadata,'verses':rows}
raw=json.dumps(payload,ensure_ascii=False,separators=(',',':')).encode()
(TARGET/'quranenc.json').write_bytes(raw)
(TARGET/'SOURCE.txt').write_text(f'''QuranEnc.com — Rowwad Translation Center
Edition: {KEY}, version {metadata['version']}
Source: https://quranenc.com/en/browse/{KEY}
API: https://quranenc.com/en/home/api/
Downloaded: {time.strftime('%Y-%m-%d')}
SHA-256: {hashlib.sha256(raw).hexdigest()}
Arabic text, translation, footnotes and edition metadata are retained verbatim.
Republication terms: retain content unchanged, credit publisher and QuranEnc.com,
state edition/version and retain edition information, report translation observations
to the source, keep up with source updates, and do not display inappropriate ads.
Refresh using scripts/build_quran_search.py before content releases.
''')
print(f'Validated {len(rows)} verses in {len(chapters)} chapters; {len(raw)} bytes; version {metadata["version"]}')
