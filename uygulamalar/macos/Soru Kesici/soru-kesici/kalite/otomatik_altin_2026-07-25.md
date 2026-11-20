# Otomatik kutu-altını: 1 kitaptan 9 kitaba (insan emeği sıfır)

**Tarih:** 2026-07-25 · **Faz:** 2 · `altin_pdf_katmani.py` + `kalite/altin_profil/profiller.json`

`altin_pdf_katmani.py` motoru (`soru_kes`/`dogrula`) **hiç kullanmadan**, PDF'in
kendi kelime koordinatlarından kutu-altını üretir; bir test bu bağımsızlığı
koruyor. Ama beş varsayım modül sabiti olarak gömülüydü ve araç yalnız TEK bir
PDF'te çalışıyordu. Üç profile ayrıldı:

| | `mebi-tyt-deneme` | `mebi-2col` | `osym-2026` |
|---|---|---|---|
| sayfa | 552,8×779,5 | 552,8×779,5 | 595,3×864,6 |
| çapa hizası | `x0` | `x0` | **`x1` (sağa hizalı)** |
| çapa toleransı | 6,0 | 4,0 | 1,5 |
| bölüm kipi | `konu` (beklenen adet) | `dizi` | `dizi` |
| deneme deseni | `[1-8]. deneme` | yok | yok |

Bayraksız çağrı **birebir eski davranış** (bir testle kilitli). `--serbest`
beklenen adet dayatmasını kaldırır; `_zinciri_denetle` numara zincirindeki
boşlukları `stderr` ve `*.audit.json`'a yazar — sessiz kalmaz.

**Ölçülmüş iki kritik ayrım:**
* ÖSYM 2026'da `1.` (x0 49,4) ile `10.` (x0 44,4) aynı **x1 = 56,9**'da biter.
  Sol kenara bakan çapa test yönergesinin `1.`/`2.` maddelerini de soru sanıyordu.
* MEBİ ailesinde dizgi 2,5 pt kayabiliyor; `AÇIKLAMA` sayfalarındaki madde
  numaraları toleransla değil `atlanacak_sayfa_deseni` ile eleniyor.

## Üretilen altınlar — 8/8, atlanan yok

| Kitap | profil | sayfa | soru | **F1** | **F1@0,75** |
|---|---|---|---|---|---|
| tytbiyo | mebi-2col | 40 | 119 | **1,000** | 0,983 |
| cikmistyt | mebi-2col | 40 | 102 | **1,000** | 0,980 |
| cikmisayt | mebi-2col | 40 | 124 | 0,992 | 0,903 |
| tyt2 | mebi-2col | 40 | 102 | 0,990 | 0,990 |
| aytsay | mebi-2col | 40 | 119 | 0,975 | 0,967 |
| aytea | mebi-2col | 40 | 108 | 0,969 | 0,969 |
| **ykstyt2026** | osym-2026 | 45 | 125 | **0,848** | **0,448** |
| **yksayt2026** | osym-2026 | 50 | 166 | **0,819** | **0,536** |

**965 yeni altın soru, 2167 required + 772 forbidden bölge, insan emeği 0.**
Kutu-altını artık 1 değil **11** belgede (3 TYT dilimi + 8 yeni).

## Yeni ve önemli açık: ÖSYM 2026 kitapçıkları

F1@0,75 = **0,448 / 0,536** — kampanyanın ilk kez gördüğü bir kesim-sınırı
çöküşü. Altın **görsel olarak denetlendi** (kutular soruları tam sarıyor,
gerekli/yasak bölgeler yerinde) — yani bu bir altın hatası değil, motorun
gerçek açığı. Ham aday 278/352'ye karşı kutu 125/166: motor aşırı aday
üretip gevşek kutu kuruyor. Bu sayfalarda büyük çapraz **ÖSYM filigranı** var;
satır/sütun analizini bozuyor olması muhtemel kök neden. Faz 4'ün hedefi.

## Yol boyunca çıkan ölçüm bulgusu

`dogrula._ornek_indeksleri`, `bas` verilmemiş ve `N > 2·max_sayfa` olan
belgelerde sayfaları **belge boyunca eşit aralıklı** örnekler (tyt-2 için
1, 9, 17, …, 313) — ilk 40'ı DEĞİL. Altın ilk turda 1-40 için üretilince F1
0,07-0,11 çıktı; örneklenen sayfa kümesine göre yeniden üretilince 0,97-1,00'e
yükseldi. **Altın üretimi ile ölçüm örneklemi aynı sayfa kümesine bakmak
zorunda.** Kalıcı çözüm koleksiyona `bas`/`son` eklemek.

## Bilinen sınırlar

1. `osym-2026` toleransı 1,5 pt; başka bir kitapçıkta dizgi kayarsa çapa kaçar
   (zincir denetimi `stderr` + audit ile bildirir, sessiz kalmaz).
2. `mebi-2col`'de `numara_azami_hane: 3` — 3 haneli bir sayı çapa hizasına
   denk gelirse soru sanılabilir (bugünkü 8 koşumda olmadı).
3. Seyrek örneklem zincir denetimini zayıflatıyor: atlanan sayfalar "eksik
   numara" gibi görünüyor, gerçek kaçırma ile ayırt edilemiyor.
4. `cikmistyt`/`cikmisayt`'ta hiç `sekil` bölgesi üretilmedi (dekoratif
   çerçeveler sütun gövdesi dışına taştığı için süzülüyor) → bu iki kitapta
   şekil kırpma ölçülmüyor.

## Korpus ölçüm kapsamı (2026-07-25 sonu)

```
koleksiyon      44 belge
kutu-altını     11 belge   (F1 / F1@0,75 / kenar hataları / bölge kapsaması)
sayım-altını    12 belge   (count_recall / precision / otomatik kova)
eşikli          22 belge
hiç ölçülmeyen  21 belge   (yayınevi kitapları — sıradaki kör sayım turu)
```
