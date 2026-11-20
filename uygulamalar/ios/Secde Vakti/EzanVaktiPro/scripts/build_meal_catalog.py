"""Import downloadable tracks from the publisher's public catalog; no guessed URLs."""
import json,re,subprocess,html,hashlib,concurrent.futures
from pathlib import Path
from html.parser import HTMLParser
ROOT=Path(__file__).resolve().parents[1]
voices={'ali-gul':'Ali Gül','atilla-olgac':'Atilla Olgaç','ayhan-kahya':'Ayhan Kahya','ercan-demirel':'Ercan Demirel','hakan-vanli':'Hakan Vanlı','ibrahim-sadri':'İbrahim Sadri','kaya-akarsu':'Kaya Akarsu','mazlum-kiper':'Mazlum Kiper','nuvit-candaner':'Nüvit Candaner','turgay-tanulku':'Turgay Tanülkü'}
def fetch(slug):
 url=f'https://www.vavtv.com.tr/podcast/meal-sure/{slug}/'
 raw=subprocess.check_output(['curl','-fLsS','--retry','3','--retry-all-errors','--max-time','30',url]).decode()
 tracks=[]
 for tag in re.findall(r'<a\b[^>]*podcast-url[^>]*>',raw):
  attrs=dict((k,html.unescape(v)) for k,v in re.findall(r'([\w-]+)="([^"]*)"',tag))
  media=attrs.get('podcast-url','');title=attrs.get('data-episode-title','')
  if not media.startswith('https://') or '.mp3' not in media or not title:continue
  tracks.append(dict(id='vav-'+slug+'-'+hashlib.sha256(media.encode()).hexdigest()[:12],title=title,voice=voices[slug],provider='Vav Radyo',url=media,sourceURL=url))
 print(slug,len(tracks),flush=True)
 return tracks
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
  tracks=[t for group in pool.map(fetch,voices) for t in group]
 target=ROOT/'Sekine/Resources/official_meal_audio.json'
 target.write_text(json.dumps(tracks,ensure_ascii=False,indent=2))
 print('TOTAL',len(tracks),flush=True)
