# Korpus geometri sondası — otomatik altın nereye kadar genelleşir?

**Tarih:** 2026-07-25 · **Faz:** 2 hazırlığı · **Yöntem:** projeden bağımsız `fitz` sondası
(sayfa dikdörtgeni, numara kelimelerinin `x0` histogramı, bölüm/deneme desenleri;
her kitaptan 24 eşit aralıklı sayfa örneklendi).

`altin_pdf_katmani.py` motoru hiç kullanmadan PDF kelime koordinatlarından
kutu-altını üretiyor, ama beş sabit varsayıma yaslı — en kritiği
`SUTUNLAR = (sol capa 36.0, sağ capa 287.7)`. Soru: bu varsayım kaç kitapta tutuyor?

## ÖSYM ailesi — varsayım şaşırtıcı derecede iyi genelleşiyor

| Kitap | sayfa | rect | baskın x0 modları | aralık | deneme |
|---|---|---|---|---|---|
| tyt-1 (1) | 398 | 552,8 × 779,5 | **36**, **288** | 3 | 23 |
| tyt-2 | 348 | 552,8 × 779,5 | **36**, 90, 318, **288** | 4 | 0 |
| ayt-say | 424 | 552,8 × 779,5 | **36**, 206, 318, **288** | 0 | 15 |
| ayt-ea | 436 | 552,8 × 779,5 | **36**, **288**, 204, 320 | 0 | 14 |
| tyt-biyo | 74 | 552,8 × 779,5 | **36**, **288**, 478 | 0 | 0 |
| CIKMIS_TYT_1 | 372 | 552,8 × 779,5 | **36**, **288** | 0 | 0 |
| CIKMIS_AYT_EA_1 | 208 | 552,8 × 779,5 | **36**, **288** | 0 | 0 |
| yks_tyt_2026 | 45 | 595,3 × 864,6 | **44**, **320** | 1 | 0 |
| yks_ayt_2026 | 50 | 595,3 × 864,6 | **44**, **320** | 0 | 0 |
| tyt | 650 | 552,8 × 779,5 | 284, 448, 408, 52 | 3 | 22 |

**Sonuç: iki profil, dokuz kitap.**

* **`mebi-2col`** (rect 552,8 × 779,5 · çapalar 36 / 288) — **7 kitap**, mevcut
  `SUTUNLAR` sabitiyle birebir uyumlu. tyt-1 dışındaki 6'sı bugüne kadar hiç
  kullanılmamış: tyt-2, ayt-say, ayt-ea, tyt-biyo, CIKMIS_TYT_1, CIKMIS_AYT_EA_1.
* **`osym-2026`** (rect 595,3 × 864,6 · çapalar 44 / 320) — **2 kitap**
  (yks_tyt_2026, yks_ayt_2026). ÖSYM orijinali; ayrı profil yeterli.
* **`tyt.pdf`** (650 sayfa) uymuyor — x0 modları dağınık (284/448/408/52).
  Kendi profili gerekiyor veya karışık düzenli; Faz 2'de ayrıca incelenecek.

**Ama beklenen adet ve deneme deseni genelleşmiyor:** `DENEME_DESENI`
(`[1-8]. deneme`) tyt-2, tyt-biyo, CIKMIS ve yks_2026'da hiç yok;
`ARALIK_DESENI` ayt-say/ayt-ea/CIKMIS/tyt-biyo'da yok; `KONULAR` beklenen
adetleri (40/25/40/20) yalnız TYT denemelerine özgü. Bu yüzden
`_capalari_sec`'in "beklenen adet tutmazsa hata fırlat" davranışı bir
**`--serbest`** kipiyle gevşetilmeli: zincir doğrulanır, adet dayatılmaz.
Y sınırları da sabit 68,0–730,0 yerine `page.rect` oranına çevrilmeli —
ölçülen numara y aralıkları 21,1 ile 758,7 arasında değişiyor.

## Yayınevi kitapları — kısmen uygulanabilir

| Kitap | rect | baskın x0 modları | numaralı sayfa | değerlendirme |
|---|---|---|---|---|
| Palme 11. SB | 637,8 × 793,7 | **50** (49), **330** (44) | 21/24 | temiz 2 sütun → otomatik altın adayı |
| PRF-TYT-AYT | 640,6 × 796,5 | 162, 36, 266, 392 | 23/24 | 3-4 sütun/karışık, zor |
| 11 meb | 552,8 × 779,5 | 56 (20), 438 (10) | 24/24 | tek sütun + sağ kenar öğesi |
| 12.pdf | 552,8 × 779,5 | 54 (24), 462 (22) | 24/24 | tek sütun + sağ kenar öğesi |
| 12 meb | 552,8 × 779,5 | 54 (15), zayıf | 10/24 | çapalar zayıf — bilinen en kötü belge |
| biyoloji-9 | 552,8 × 779,5 | 42/56/60/46 dağınık | 17/24 | tek sütun, bulanık |
| Çözümler_1 | 569,8 × 796,5 | yok denecek kadar az | 2/24 | `N.` deseni yok; çözüm sayfaları `Soru 5 :` kipinde |

`Çözümler_1`'in yalnız 2/24 sayfasında serbest `N.` kelimesi bulunması,
motorun bu belgede neden **zincir çapasına** muhtaç olduğunu doğruluyor:
çözüm gövdeleri düz metindir, numara ayrı bir kelime olarak durmaz.

## En değerli varlık: `_Searchable` ikizi — HİZA DOĞRULANDI

`10. Sınıf Biyoloji Soru Bankası.pdf` (taranmış) ↔
`10. Sınıf Biyoloji Soru Bankası_Searchable.pdf` (OCR katmanlı):

* sayfa sayısı **224 = 224**
* rect **956,35 × 1190,37** — ikisinde de aynı
* 5 örnek sayfada (6, 41, 91, 141, 201) render edilmiş **piksel verisi SHA-256
  birebir aynı**; taranmışta 0 kelime, Searchable'da 64–327 kelime.

Yani `_Searchable`, aynı PDF'in üzerine OCR metin katmanı eklenmiş hâli.
Koordinatlar 1:1 taşınır. **Faz 3 uygulanabilir** ve şunu mümkün kılar:
metin katmanından insan emeği olmadan kutu-altını üret → aynı koordinatları
taranmış ikize uygula → taranmış/OCR yolunun kesim kalitesi ilk kez ölçülür,
üstelik iki yolun F1 farkı tam olarak **OCR'ın yol açtığı hatayı** izole eder.

## Faz 2 için çıkan iş listesi

1. `kalite/altin_profil/profiller.json`: `mebi-2col`, `osym-2026` ve
   (incelemeden sonra) Palme profili.
2. `altin_pdf_katmani.py`: `SUTUNLAR`/`KONULAR`/`DENEME_DESENI`/y sınırları
   profile taşınır; `--serbest` kipi eklenir; çapalar `x0` histogramından
   türetilebilir hâle gelir.
3. Otomatik kutu-altını: **9 kitap** (bugün 1). Kabaca 6 000+ soru, insan emeği 0.
4. `tyt.pdf` (650 sayfa) ve PRF ayrıca incelenir.
