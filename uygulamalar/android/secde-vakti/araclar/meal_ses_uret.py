# Uygulamanın official_meal_audio.json kayıtlarını (başlık: "Bakara suresi") sure numarasına eşler.
# Çıktı: {"okuyucular": [...], "sure": {"2": {"Hakan Vanlı": "https://...mp3", ...}, ...}}
# Kullanım: meal_ses_uret.py girdi.apk cikti.json
import json, sys, unicodedata, zipfile

z = zipfile.ZipFile(sys.argv[1])
ses = json.loads(z.read('assets/flutter_assets/assets/data/official_meal_audio.json'))
bolum = json.loads(z.read('assets/flutter_assets/assets/data/kuran_bilmek_offline.json'))['chapters']


def sade(s):
    s = s.replace('İ', 'i').replace('I', 'ı').lower().replace('ı', 'i')
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(ch for ch in s if not unicodedata.combining(ch))
    for a, b in (('ş', 's'), ('ç', 'c'), ('ğ', 'g'), ('ö', 'o'), ('ü', 'u')):
        s = s.replace(a, b)
    s = s.replace('suresi', '')
    return ''.join(ch for ch in s if ch.isalnum())


ad_no = {}
for b in bolum:
    for ad in (b['translated_name']['name'], b['name_simple']):
        ad_no[sade(ad)] = b['id']
# Mealde farklı yazılan birkaç ad
ek = {'ali imran': 3, 'ala': 87, 'kaf': 50, 'sad': 38, 'tevbe': 9, 'taha': 20, 'yasin': 36, 'mumin': 40,
      'muminun': 23, 'fussilet': 41, 'hamim secde': 41, 'secde': 32, 'insan': 76, 'dehr': 76, 'insirah': 94,
      'sems': 91, 'leyl': 92, 'tin': 95, 'kadr': 97, 'zilzal': 99, 'karia': 101, 'tekasur': 102, 'humeze': 104,
      'kureys': 106, 'maun': 107, 'kafirun': 109, 'tebbet': 111, 'mesed': 111, 'leheb': 111, 'saff': 61}
for k, v in ek.items():
    ad_no.setdefault(sade(k), v)

import re
sure, okuyucular, eslesmeyen, cuz = {}, {}, [], {}
for s in ses:
    m = re.match(r'(\d+)\. Cüz', s['title'])
    if m:
        cuz[m.group(1)] = {'okuyucu': s['voice'], 'url': s['url']}
        continue
    no = ad_no.get(sade(s['title']))
    if not no:
        eslesmeyen.append(s['title'])
        continue
    okuyucu = s['voice']
    okuyucular[okuyucu] = okuyucular.get(okuyucu, 0) + 1
    sure.setdefault(str(no), {})[okuyucu] = s['url']

sira = sorted(okuyucular, key=lambda o: -okuyucular[o])
json.dump({'okuyucular': sira, 'sure': sure, 'cuz': cuz}, open(sys.argv[2], 'w', encoding='utf8'), ensure_ascii=False)
print('meal sesi: %d sure, %d okuyucu, %d cüz, eşleşmeyen %d %s' % (len(sure), len(sira), len(cuz), len(eslesmeyen), sorted(set(eslesmeyen))[:8]))
assert len(sure) >= 110, 'sure eşleşmesi beklenenden az'
