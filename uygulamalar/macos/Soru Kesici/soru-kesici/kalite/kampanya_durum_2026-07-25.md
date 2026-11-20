# Sıfır Hata Kampanyası — durum (2026-07-25)

Fazlar 0, 1, 2, 4, 5 tamamlandı. 426 otomatik test yeşil.

## Ölçüm kapsamı: 5 belge → 23 belge

| | kampanya öncesi | şimdi |
|---|---|---|
| koleksiyon | 10 belge | **44 belge / 12 aile** |
| kutu-altını (F1, IoU, kenar, bölge) | 1 PDF (3 dilim) | **11 belge**, 2215+965 soru |
| sayım-altını (recall/precision) | 5 belge / 18 sayfa / 142 soru | **12 belge / 60 sayfa / 243 soru** |
| eşikli (kapı gerçekten bakıyor) | 2 belge | **22 belge** |
| hiç ölçülmeyen | 5 (korpusun yarısı) | 21 (hepsi yeni eklenen yayınevi kitapları) |

## Motor sonuçları

### Tespit (sayım-altını)

| Belge | count_recall | otomatik kova |
|---|---|---|
| **12meb** | 0,154 → **0,846** | 0,077 → **0,577** |
| **cozumler1** | 0,437 → **0,845** | 0,113 → 0,127 |
| **cozumyazili** | 0,872 | 0,513 → **0,744** |
| 9pdf | 0,444 | 0,278 → **0,389** |
| 9konu / aydin / ygslys / 10sb / 11fen / 10sinif | değişmedi | değişmedi |
| campbell (negatif kontrol) | 1,000 | 1,000 |

`cozumler1`'in **üç sıfır sayfası** (41, 57, 157) tamamen kayboldu.

### Kesim (kutu-altını)

| Belge | F1 | F1@0,75 | mean IoU |
|---|---|---|---|
| tyt1_2026_calibration | 0,9927 | 0,9820 → **0,9834** | 0,9327 → **0,9434** |
| tytbiyo | 1,0000 | 0,983 → **0,9916** | — |
| cikmistyt | 1,0000 | 0,980 → **0,9804** | — |
| tyt2 | 0,9902 | **0,9902** | — |
| cikmisayt | 0,9919 | 0,903 → **0,9032** | — |
| aytsay / aytea | 0,975 / 0,969 | 0,9672 / 0,9686 | — |
| ykstyt2026 | 0,848 → **0,8720** | 0,448 → **0,6240** | — |
| yksayt2026 | 0,819 → **0,8434** | 0,536 → **0,6747** | — |

Üst kenar sapması **−5,36 → −2,19 pt**. Komşu soru sızıntısı **0/436**
(hiç yok). Gerekli bölge kapsaması 1774/1883.

## Kampanyanın ürettiği yedi kalıcı bulgu

1. **Ölçüm defekti**: `dogrula.belge_isle` reddedilen kutuları da sayıyordu →
   `count_recall`, `count_precision` ve kapının 8 kayma sinyalinin tamamı
   teslim edilmeyen bir kümeyi ölçüyordu. cozumler1 "1,000" görünüyordu,
   gerçek 0,600'dü.
2. **Sayfa yüzdesi eşikleri yoğun dizgide yanılıyor** — üç ayrı yerde aynı
   sınıf hata: `min_yuk` (0,022·Y = 17,15 pt vs satır aralığı tam 17,0 pt),
   `asiri_kucuk` (h < 0,025), `uygun_geometri` (h ≥ 0,035, hâlâ açık).
3. **"Soru dışı sayfa" cezası belgenin amacına göreli olmalı** — çözüm
   kitabında çözüm sayfası içeriktir.
4. **Zincir üyeliği bağımsız bir güven kanıtıdır** — ama üç koruma şart:
   ≥5 hizalı üye, kutu kimliğiyle eşleşme (mükerrer kutu kanıt almasın),
   ve etkinlik sayfası vetosu.
5. **Filigran altını bozar**: tek bir döndürülmüş glif (189×189 pt) altın
   kutusunu 46 pt şişiriyor, motor haksız yere cezalandırılıyordu.
6. **Kısmi örneklem örtüşmesi sessiz bir tuzak**: ikiz belgede 8 altın
   sayfasından 1'i örtüşünce recall/precision/otomatik hepsi 1,000 çıktı.
   Artık `pages_overlap_ratio < 0,8` koşulsuz kırmızı.
7. **Raster/OCR yolu suçlu değil**: piksel-birebir ikizde metin yolu 0,442 vs
   raster yolu 0,462 — kayıp tespit mantığında.

## Kapı bugün ne görüyor

* 8 kayma sinyali + `sayim-dusus-*` (9.) + `sayim-sifir-sayfa` (koşulsuz
  kırmızı) + `sayim-ortusme-dusuk` + `sayim-degerlendirme-hatasi`
* 22 belgede mutlak taban (F1/P/R/F1@0,75 ve count_*), tek yönlü ratchet
* `--kapsam A|B|C` (10 / 41 / 44 belge), `--rapor`, `--kiyas`, aile bazlı
  toplam satırı
* Sayım metrikleri snapshot'a gömülü → `--guncelle` gerilemede bloklar

## Kalan kırmızılar (gerçek, gizlenmiş değil)

* **3 sıfır sayfa**: 10sb s141, 9konu s103, 9pdf s89 — altında soru var,
  motor 0 kutu.
* **9pdf s69** ("11. Etkinlik") 6 yanlış-pozitif; **s113** aynı soru iki
  kutuya bölünüyor.
* **cozumler1 otomatik kovası 0,127** — 280 kutunun 257'si `incele`.
* **ÖSYM 2026 F1@0,75 0,62/0,67** — alt kenarda uzun kuyruk (p95 236 pt).
* **`once_*.json` snapshot'ları eski ölçü birimine ait** — her belgede yapay
  `kutu-dusus` kırmızısı üretiyorlar. Tazelenmeleri kullanıcı kararına bağlı;
  mutlak eşikler bu arada gerçek korumayı sağlıyor.

## Sıradaki fazlar

* **Faz 3** — ikiz kalibrasyonu: hiza doğrulandı (piksel birebir) ama
  `_Searchable`'ın OCR katmanı kutu-altını türetmeye çok zayıf; ikizin değeri
  raster-yolu maliyetini izole etmek oldu ve o soru yanıtlandı.
* **Faz 6** — sadeleştirme (sihirli sabitler, kopya fonksiyon, geniş except).
* **Faz 7** — `İncele/` klasörü + `--sert` disiplini.
* **Faz 8** — ML modelinin 965 gerçek altın kutuyla yeniden eğitimi.
* **Kör sayım turu 3** — ölçülmeyen 21 yayınevi kitabı.
