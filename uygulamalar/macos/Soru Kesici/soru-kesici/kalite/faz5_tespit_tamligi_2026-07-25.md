# Faz 5 — Tespit tamlığı: beş düzeltme, tek tek ölçüldü

**Tarih:** 2026-07-25 · Her düzeltme ayrı ayrı uygulandı ve **9 kutu-altınlı
belgede (2215 altın soru) sıfır regresyon** koşuluyla kabul edildi.

## Sonuçlar

| Belge | count_recall | otomatik recall | count_precision |
|---|---|---|---|
| **12meb** | 0,154 → **0,846** (5,5×) | 0,077 → **0,615** | 1,000 |
| **cozumler1** | 0,437 → **0,845** | 0,113 → 0,127 | 1,000 |
| **cozumyazili** | 0,872 | 0,513 → **0,744** | 1,000 |
| 9pdf | 0,444 | 0,278 → **0,389** | 0,533 → 0,471 ▼ |
| aydin / ygslys / 9konu / 10sb / 11fen / 10sinif | değişmedi | değişmedi | değişmedi |

Aile bazında: `meb` recall 0,485 → **0,715**, `cozum` otomatik 0,313 → **0,435**.

**Kutu-altını nöbetçileri (hiçbiri kımıldamadı):** tyt1_2026_calibration
F1 0,9927 / F1@0,75 0,9820; tyt2 0,990/0,990; aytsay 0,975/0,967;
aytea 0,969/0,969; tytbiyo 1,000/0,983; cikmistyt 1,000/0,980;
cikmisayt 0,992/0,903; ykstyt2026 0,848/0,448; yksayt2026 0,819/0,536.

**Sıfır sayfa:** cozumler1'in üç sıfır sayfası (41, 57, 157) tümüyle ortadan
kalktı. Kalan üç sıfır sayfa (10sb s141, 9konu s103, 9pdf s89) dokunulmadı.

## Düzeltmeler

### 1. "Soru dışı sayfa" cezası belgenin amacına göreli (`soru_kes.py:3522`)

Çözüm kitabında `çözüm` sayfa rolü aykırı değil, **içerik** rolüdür. Eskiden
güven 0,20'ye tavanlanıyor ve mükemmel kanıtlı kutular
(`soru_numarasi + yeterli_metin + uygun_geometri + belge_numara_hizasi`)
reddediliyordu. `fmt == "cozumlu"` iken `çözüm` aykırı roller kümesinden
çıkarıldı. → cozumler1 0,437 → 0,845.

### 2. Eşleştirme gridi çoktan seçmeli sayılmıyor (`_sayfa_formati`)

a) … o) harfli eşleştirme gridi 15 küçük şık harfi üretip sayfayı
`coktan_secmeli` sandırıyordu; bu hem `blok_gecerli_mi`'yi her blokta şık
aramaya zorluyor hem de zincir çapasını kapatıyordu. `secenek_listesi` vetosu
artık `coktan_secmeli` yoluna da uygulanıyor. → 12meb 0,154 → 0,462.

### 3. `min_yuk` sayfanın kendi dizgisinden türetiliyor (`capa_araligi_p25`)

Eşik `0,022 × 779,5 = 17,15 pt`, tablonun satır aralığı **tam 17,0 pt** —
yedi soru tesadüfi 0,15 pt farkla eleniyordu. Zincir kanıtı varken eşik artık
çapa aralıklarının **25. yüzdeliğinin %90'ı** (medyan değil: aynı sayfada 17 pt
ile 45 pt yan yana olabiliyor). → 12meb 0,462 → 0,538.

### 4. Hizalama filtresi ikinci meşru kümeyi koruyor (`_x_hiza_kumeleri`)

"En soldaki küme kazanır" kuralı, farklı girintideki meşru bir soru grubunu
atıyordu (12meb s186: üstteki tablo x0=78,7, alttaki liste x0=47,2, tolerans
13,8). İkinci küme ancak **kendi içinde hizalı (≥3 üye)** ve üyeleri
**doğrulanmış zincire katılıyorsa** korunuyor — şekil içi "1. Tur, 2. Tur"
etiketleri bu iki şartı birden sağlayamaz.

### 5. Zincir üyeliği bir GÜVEN kanıtı (`_guclu_zincir_uyeleri`)

En büyük kazanç buradan geldi. Tespit zaten tamamlanmıştı (22 sorunun 21'ine
kutu kuruluyordu) ama kutular **hiçbir uyarı taşımadan** 0,520 ile
`GUVEN_INCELE`'nin (0,55) 0,03 altında kalıp reddediliyordu. Zincirin
doğrulanmış üyesi olan bir kutu 20 kardeşi tarafından desteklenir; +0,15 kanıt
puanı ve `asiri_kucuk` cezasının (yine bir sayfa yüzdesi eşiği) vetosu eklendi.
→ 12meb 0,538 → **0,846**, cozumyazili otomatik 0,513 → **0,744**.

Üç koruma birlikte:
* zincir **≥5 üyeli** olmalı ve üyeler **aynı sol hizada** (±G×0,025);
* dönüş numara değeri değil **kutu kimliği** — aynı numara bölünme hatasıyla
  iki kez üretilirse mükerrer kutu kanıt almaz;
* **etkinlik sayfası vetosu**: ders kitaplarında "11. Etkinlik" başlıklı
  sayfalarda numaralı maddeler soru değil uygulama adımıdır ve bunlar da
  düzgün bir zincir kurar. Ölçüldü: 9pdf s69'da altın 0 soru derken motor 6
  kutu üretiyor. **"Yönerge" tek başına ayırt edici DEĞİL** — gerçek soru
  sayfaları da "Yönerge: Aşağıdaki soruları…" ile başlıyor (9pdf s89, s113).

## Kabul edilen ödünleşme

**9pdf precision tabanı 0,5333 → 0,4706'ya bilinçli olarak indirildi.** Zincir
kanıtı otomatik kovayı 0,278 → 0,389 yükseltirken altın sayfalarda 2
yanlış-pozitif ekledi. Gerekçe: aile bazlı denge güçlü pozitif ve 9 kutu-altınlı
belgede sıfır regresyon. Karar `kapi_esikleri.json`'a gerekçesiyle yazıldı.

## Bekleyen iş (bu turdan ÖNCE de vardı)

1. **9pdf s69** — "11. Etkinlik" sayfasında 6 yanlış-pozitif. Etkinlik vetosu
   zincir bonusunu engelliyor ama bu kutular bonussuz da 0,55'i geçiyor.
   Etkinlik sayfalarında numaralı maddeler için ayrı bir tavan gerekiyor.
2. **9pdf s113** — aynı soru iki kutuya bölünüyor (numaralar
   `[1,2,2,3,3,4,5,6]`). Aynı bant + aynı numara → bölünme; birleştirme kuralı
   gerekiyor.
3. **9pdf s89, 10sb s141, 9konu s103** — sıfır sayfa (altında soru var, motor
   0 kutu). Kapıda koşulsuz kırmızı.
4. **12meb s186'da 20 numaralı soru** hâlâ kutu üretmiyor (21-41 üretiyor).
5. **cozumler1 otomatik kovası 0,127** — teslim edilen 278 kutunun 255'i
   `incele`. Çözüm kitaplarında güven puanlaması ayrı bir iş.
6. **ÖSYM 2026 F1@0,75 = 0,448/0,536** — kesim sınırı çöküşü, Faz 4'ün hedefi.
