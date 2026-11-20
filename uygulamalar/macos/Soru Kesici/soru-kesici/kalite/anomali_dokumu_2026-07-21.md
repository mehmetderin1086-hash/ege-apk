# Anomali Dökümü — 2026-07-21 (tür / sayfa / konum düzeyi)

Kaynak: `kalite_kosusu.py` çalışma kopyası (baseline ile aynı kod, commit b956d9a +
commit'lenmemiş değişiklikler). Detaylar `dogrula._metrikleri_hesapla`'dan üretildi;
o fonksiyonun çıktısındaki `anomaliler` listesi normalde `[:24]` ile kırpıldığı için
(sadece `anomali_sayisi` tam sayıdır), döküm için fonksiyonun kaynağı runtime'da alınıp
kırpma kaldırılarak TAM liste çıkarıldı. **Diskteki motor koduna dokunulmadı** — salt-okunur analiz.

> **Not — "soru no" hakkında:** Anomali kayıtları soru-id taşımaz; motor onları
> **sayfa + kutu konumu** düzeyinde işaretler. Bu yüzden aşağıda "konum" kolonu
> kullanıldı: `sutun-tasma`/`bos-sutun` için kutunun/bandın yatay aralığı `x∈[x0..x1]`,
> `minik`/`birlesme` için alan oranı. İlgili soru, o sayfada o x-aralığındaki kutudur.

## Anomali türleri (sözlük)

| Tür | Anlamı | Motor koşulu (özet) | `detay` |
|---|---|---|---|
| **sutun-tasma** | Sütun-taşma = **birleşme** (yan yana sütunların tek kutuda birleşmesi) | Kutu ≥2 yatay bandı, genişliğinin >%20'siyle örtüyor | `[x0, x1]` (kutu yatay aralığı) |
| **bos-sutun** | Kaçan soru sütunu (gerçek eksik) | Geniş bantta (>%14 en) hiç kutu yok ama ≥3 farklı şık kanıtı var | `[a, b]` (boş bandın aralığı) |
| **birlesme** | Dikey birleşme (üst üste iki sorunun tek kutuda birleşmesi) | Kutu > medyan alanın 4.5×'i ve içinde ≥2 dikeyde ayrık numara adayı | `[alan_orani, numara_adedi]` |
| **minik** | Aşırı-bölünme / gürültü parçası | Kutu < medyan alanın %6'sı | `alan/medyan` oranı |
| **komsu-dusuk** | Komşulara göre ani kutu düşüşü (olası kaçırma) | 0 < kutu < medyan·0.4 ama ≥ medyan·2 şık kanıtı | `[kutu, medyan]` |
| **tespit-basarisiz** | Sayfada hiç kutu üretilememiş | toplam_kutu == 0 | `"0 kutu"` |

> **`yarim_soru` ayrı bir sinyaldir:** `anomali_sayisi`'na (122) **girmez**. Bandın son
> kutusu beklenen şık kümesinin bir kısmını içerip bant dibine ulaşıyorsa "soru sonraki
> sütuna taşmış olabilir" göstergesidir. Sayfa + bant indeksiyle konumlanır. Bu koşumda
> toplam **68** adet (aşağıda belge başına özetlendi) — sütun/bölünme düzeltmelerinin
> ikincil hedefi.

---

## Belge başına döküm

### 10sb — 7 anomali (174 kutu, çoktan_seçmeli)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| sutun-tasma | 31 | 1 | kutu x∈[181..1357] |
| sutun-tasma | 36 | 2 | kutu x∈[0..1431] ×2 |
| sutun-tasma | 41 | 2 | kutu x∈[0..1359] ×2 |
| minik | 71 | 1 | alan/medyan=0.007 (neredeyse nokta boyutu parça) |
| minik | 101 | 1 | alan/medyan=0.039 |

yarim_soru (11): s31·b0, s41·b0, s76·b1, s101·b0, s111·b0, s121·b0, s131·b0, s141·b0, s151·b0, s181·b1, s186·b1

### 10sinif — 1 anomali (6 kutu, çoktan_seçmeli)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| sutun-tasma | 2 | 1 | kutu x∈[0..1654] (tek belge, max_sayfa=2) |

### 11fen — 2 anomali (47 kutu, karışık)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| birlesme | 73 | 1 | alan=6.73×medyan, 5 numara adayı (dikey birleşme) |
| sutun-tasma | 103 | 1 | kutu x∈[80..509] |

### 12meb — 0 anomali (60 kutu, karışık)

Anomali yok. yarim_soru (4): s61·b0, s86·b0, s106·b0, s136·b0

### 9konu — 2 anomali (62 kutu, karışık)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| bos-sutun | 43 | 1 | boş bant x∈[1676..2657] (sağ sütun kaçmış) |
| bos-sutun | 73 | 1 | boş bant x∈[1765..2657] (sağ sütun kaçmış) |

yarim_soru (5): s25·b1, s31·b1, s91·b1, s139·b1, s157·b0

### 9pdf — 3 anomali (77 kutu, açık_uçlu)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| birlesme | 29 | 1 | alan=5.63×medyan, 8 numara adayı |
| birlesme | 65 | 1 | alan=4.53×medyan, 6 numara adayı |
| sutun-tasma | 133 | 1 | kutu x∈[0..298] |

yarim_soru (2): s73·b0, s101·b1

### aydin — 35 anomali (190 kutu, çoktan_seçmeli)

Baskın örüntü: **tam-genişlik `x∈[0..2117]` kutu** (sayfa eni ≈2117), 22 sayfada tekrarlıyor
→ tek bir sistematik neden (2 sütunlu düzende tüm satırı kaplayan kutu).

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| sutun-tasma | 31 | 1 | x∈[0..2117] (tam genişlik) |
| sutun-tasma | 37 | 1 | x∈[0..2117] |
| sutun-tasma | 49 | 3 | x∈[0..1067]; x∈[579..2117]; x∈[579..1361] |
| minik | 49 | 1 | alan/medyan=0.058 |
| sutun-tasma | 55 | 4 | x∈[0..2117]; x∈[0..1066] ×3 |
| sutun-tasma | 61 | 1 | x∈[0..2117] |
| bos-sutun | 73 | 1 | boş bant x∈[550..1048] |
| sutun-tasma | 73 | 1 | x∈[0..1048] |
| bos-sutun | 79 | 1 | boş bant x∈[544..1046] |
| sutun-tasma | 79 | 3 | x∈[0..2117]; x∈[0..1046]; x∈[0..976] |
| sutun-tasma | 85 | 1 | x∈[0..2117] |
| bos-sutun | 91 | 1 | boş bant x∈[1063..2117] |
| sutun-tasma | 91 | 1 | x∈[0..2117] |
| minik | 91 | 1 | alan/medyan=0.04 |
| sutun-tasma | 103 | 1 | x∈[0..2117] |
| sutun-tasma | 109 | 1 | x∈[0..2117] |
| sutun-tasma | 115 | 1 | x∈[0..2117] |
| sutun-tasma | 127 | 1 | x∈[0..2117] |
| sutun-tasma | 139 | 1 | x∈[0..2117] |
| sutun-tasma | 151 | 1 | x∈[0..2117] |
| sutun-tasma | 163 | 1 | x∈[0..2117] |
| sutun-tasma | 175 | 1 | x∈[0..2117] |
| sutun-tasma | 181 | 1 | x∈[0..2117] |
| sutun-tasma | 187 | 1 | x∈[0..2117] |
| minik | 187 | 1 | alan/medyan=0.031 |
| sutun-tasma | 193 | 1 | x∈[0..2117] |
| sutun-tasma | 217 | 1 | x∈[0..2117] |
| sutun-tasma | 229 | 1 | x∈[0..2117] |

Tür dağılımı: sutun-tasma 29, bos-sutun 3, minik 3.
yarim_soru (5): s49·b1, s97·b0, s103·b0, s187·b0, s205·b1

### cozumler1 — 5 anomali (197 kutu, çözümlü)

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| sutun-tasma | 13 | 1 | kutu x∈[0..740] |
| sutun-tasma | 17 | 1 | kutu x∈[0..737] |
| birlesme | 17 | 2 | alan=37.62×medyan, 6 num. adayı; alan=43.54×medyan, 5 num. adayı (çok büyük birleşme) |
| sutun-tasma | 153 | 1 | kutu x∈[33..280] |

yarim_soru (3): s13·b0, s21·b0, s77·b1

### cozumyazili — 0 anomali (27 kutu, çoktan_seçmeli)

Anomali yok. yarim_soru (3): s1·b0, s3·b1, s6·b0

### ygslys — 67 anomali (390 kutu, çoktan_seçmeli)

Neredeyse tamamı **sutun-tasma** (66/67). aydin'in aksine tam-genişlik değil, çoğu
**kısmi sütun örtüşmesi** (ör. `x∈[515..1400]`, `x∈[1214..2880]`) — sütun sınırı kaymış/
kutu iki komşu sütuna yayılıyor. 15 sayfada ≥3 taşma → sistematik sütun-tespit sorunu.

| Tür | Sayfa | Adet | Konum / not |
|---|---|---|---|
| bos-sutun | 16 | 1 | boş bant x∈[1191..1880] |
| sutun-tasma | 16 | 4 | x∈[0..768]; x∈[515..1400]; x∈[515..1392]; x∈[1191..2880] |
| sutun-tasma | 21 | 1 | x∈[538..1421] |
| sutun-tasma | 26 | 2 | x∈[0..802]; x∈[266..1197] |
| sutun-tasma | 31 | 3 | x∈[0..1210]; x∈[0..802]; x∈[578..1430] |
| sutun-tasma | 36 | 5 | x∈[0..793] ×2; x∈[0..785]; x∈[553..1425]; x∈[553..1434] |
| sutun-tasma | 41 | 3 | x∈[0..1256]; x∈[544..1438]; x∈[283..1256] |
| sutun-tasma | 46 | 5 | x∈[0..823]; x∈[0..1212]; x∈[592..1455]; x∈[1212..2880] ×2 |
| sutun-tasma | 56 | 1 | x∈[1500..2880] |
| sutun-tasma | 61 | 1 | x∈[0..823] |
| sutun-tasma | 66 | 3 | x∈[0..1214]; x∈[1214..2880] ×2 |
| sutun-tasma | 71 | 4 | x∈[550..1438]; x∈[550..1446]; x∈[550..1450]; x∈[0..1210] |
| sutun-tasma | 81 | 4 | x∈[0..818]; x∈[0..823]; x∈[1522..2133]; x∈[1522..2011] |
| sutun-tasma | 86 | 2 | x∈[555..1442]; x∈[1208..2880] |
| sutun-tasma | 96 | 5 | x∈[0..1216]; x∈[548..1450]; x∈[548..1392]; x∈[548..1446]; x∈[1538..2880] |
| sutun-tasma | 101 | 3 | x∈[0..814]; x∈[582..1430]; x∈[1216..2137] |
| sutun-tasma | 106 | 3 | x∈[557..1446]; x∈[1237..2133] ×2 |
| sutun-tasma | 121 | 4 | x∈[199..1206]; x∈[544..1446]; x∈[544..1442]; x∈[1206..2880] |
| sutun-tasma | 126 | 4 | x∈[835..1442]; x∈[1214..2880] ×3 |
| sutun-tasma | 141 | 4 | x∈[0..810]; x∈[590..1442]; x∈[590..1446]; x∈[1210..2880] |
| sutun-tasma | 146 | 1 | x∈[1467..2880] |
| sutun-tasma | 171 | 4 | x∈[538..1861]; x∈[538..1438]; x∈[1199..2880] ×2 |

Tür dağılımı: sutun-tasma 66, bos-sutun 1.
yarim_soru (35): s16·b0,1 · s21·b1,2,3 · s26·b2 · s31·b1,2 · s36·b0,3 · s41·b0 · s46·b2 ·
s51·b0 · s56·b1,3 · s66·b0,2 · s76·b3 · s81·b0,2 · s86·b0 · s96·b0,2 · s101·b2 · s116·b2 ·
s121·b1 · s126·b1 · s136·b3 · s141·b0 · s146·b2 · s161·b2 · s166·b0 · s176·b0 · s186·b1 · s196·b0

---

## Tür bazında toplam sayım

| Tür | Toplam | Belgeler (dağılım) |
|---|---:|---|
| **sutun-tasma** | **106** | ygslys 66, aydin 29, 10sb 5, cozumler1 3, 10sinif 1, 11fen 1, 9pdf 1 |
| bos-sutun | 6 | aydin 3, 9konu 2, ygslys 1 |
| birlesme | 5 | cozumler1 2, 9pdf 2, 11fen 1 |
| minik | 5 | 10sb 2, aydin 3 |
| komsu-dusuk | 0 | — |
| tespit-basarisiz | 0 | — |
| **TOPLAM** | **122** | |

Belge başına toplam: 10sb 7, 10sinif 1, 11fen 2, 12meb 0, 9konu 2, 9pdf 3, aydin 35,
cozumler1 5, cozumyazili 0, ygslys 67.

Ayrıca (122'ye dahil DEĞİL) **yarim_soru: 68** → ygslys 35, 10sb 11, 9konu 5, aydin 5,
12meb 4, cozumler1 3, cozumyazili 3, 9pdf 2, 10sinif 0, 11fen 0.

## Baseline (122) doğrulaması

Her belgenin `anomali_sayisi`'sı `baseline_2026-07-21.md`'deki "Anomali (güncel)" kolonuyla
**birebir tuttu** (7, 1, 2, 0, 2, 3, 35, 5, 0, 67 = **122**). Sapma yok. Tür sayımlarının
toplamı da her belgede `anomali_sayisi`'na eşit (assert ile doğrulandı).

## En çarpıcı örüntüler (düzeltme hedefleri)

1. **`sutun-tasma` = %87 (106/122).** Baseline'da hedef "`birlesme` türünü 0'a indirmek"
   yazıyor ama literal `birlesme` türü yalnızca **5** adet. Motorun sözlüğü sütun-taşmayı
   da açıkça "birleşme" sayıyor (`dogrula.py` docstring: "sütun-taşma = birleşme"). Faz 1-2
   "birleşme" hedefi bu geniş aileyi (sutun-tasma + birlesme = 111/122 = **%91**)
   kapsamıyorsa, işin asıl kütlesini kaçırır. **Birinci hedef `sutun-tasma` olmalı.**

2. **Yük iki belgede yoğun: ygslys (66) + aydin (29) = 95/106 sutun-tasma.** Kalan 8 belge
   toplam 11. Yani sutun-tasma düzeltmesini bu iki düzende doğrulamak, işin %90'ını kapatır.

3. **aydin ve ygslys FARKLI kök nedene işaret ediyor** — tek "sütun düzeltmesi" ikisini de
   çözmeyebilir:
   - **aydin:** 22 taşma `x∈[0..2117]` = **tam-genişlik kutu** (sayfa eni ≈2117). Kutular
     tüm satırı kaplıyor → sütun ayrımı hiç uygulanmamış gibi. Kök neden: 2-sütun düzeninin
     yanlış tek-sütun sanılması.
   - **ygslys:** taşmalar **kısmi örtüşme** (`x∈[515..1400]`, `x∈[1214..2880]` gibi) →
     sütun sınırı var ama kaymış/kutular sınırı ~%20+ aşıyor. Kök neden: sütun sınırı
     konumlandırma hatası / bant eşiği.

4. **`bos-sutun` (6) küçük ama gerçek veri kaybı** (kaçan soru sütunu): 9konu s43/s73 (sağ
   sütun), aydin s73/s79/s91, ygslys s16. Bunlar sutun-tasma ile aynı sütun-tespit
   zayıflığının diğer yüzü olabilir — düzeltme ikisini birlikte etkileyebilir.

5. **`yarim_soru` (68, 122'ye dahil değil) aynı sorunun ölçeğini büyütüyor.** En yoğun
   ygslys (35) — sutun-tasma'nın en yoğun olduğu belge. Sütun/taşma düzeltmesi bu
   ikincil sinyali de büyük olasılıkla azaltacaktır; Faz 1-2 sonrası regresyon kontrolünde
   `yarim_soru` sayısını da izlemek işe yarar.

6. **`minik` (5) ve `birlesme` (5) marjinal.** `minik` iki belgede (10sb, aydin) aşırı-
   bölünme parçaları; `birlesme` cozumler1 s17'de çok büyük (37×, 43× medyan) — bunlar
   nokta düzeltmeler, öncelik değil.
