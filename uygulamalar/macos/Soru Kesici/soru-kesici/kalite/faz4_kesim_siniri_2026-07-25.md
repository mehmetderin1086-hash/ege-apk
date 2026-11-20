# Faz 4 — Kesim sınırı kalitesi

**Tarih:** 2026-07-25 · Faz 1'de açılan `kenar_hatalari` ve bölge metrikleri
sayesinde kesim sınırı ilk kez **dört yönlü** teşhis edilebiliyor.

## Düzeltme 1 — Üst pay numara kutusundan türetiliyor

`_kutu_insa`'da üst pay sabit `Y × 0,012` idi (779 pt sayfada **9,35 pt**) —
11 pt'lik bir numara satırının neredeyse yarısı kadar fazla yer alıyordu.
`kenar_hatalari` bunu sayıyla gösterdi: üst kenarda **medyan −5,36 pt**
sistematik sapma (tahmin, altından yukarıda başlıyor).

Yeni: `ust = kutu[1] − min(Y×0,012, numara_yüksekliği × 0,45)`. `min()`
sayesinde pay bugünkü değerini **asla aşamaz** — değişim tek yönlü, daraltma.

Katsayı ölçümle seçildi (kalibrasyon altını, 750 soru):

| katsayı | F1@0,75 | mean IoU | gerekli bölge tam | üst medyan |
|---|---|---|---|---|
| eski (`Y×0,012`) | 0,9820 | 0,9327 | 1775/1883 | −5,36 |
| 0,35 | 0,9834 | **0,9481** | 1766 (−9) | −0,82 |
| **0,45** ✓ | **0,9834** | **0,9434** | **1774** | −2,19 |
| 0,55 | 0,9834 | 0,9386 | 1775 | −3,57 |

0,45 IoU kazancını gerekli-bölge kapsamasıyla dengeliyor.

**Etki (9 kutu-altınlı belge):** tyt1 F1@0,75 0,9820 → 0,9834 · tytbiyo
0,983 → 0,9916 · cikmistyt 0,980 → 0,9804 · tyt2 0,990 → 0,9902 · aytsay
0,967 → 0,9672 · cikmisayt 0,903 → 0,9032 · ykstyt2026 0,448 → 0,480 ·
yksayt2026 0,536 → 0,566. **Hiçbirinde gerileme yok.**

## Düzeltme 2 — ÖSYM 2026'daki çöküş ALTIN KUSURUYDU

Faz 2'de ÖSYM 2026 kitapçıklarının F1@0,75'i 0,448/0,536 çıkmış ve
"motorun gerçek açığı" olarak kaydedilmişti. **Bu tespit yanlıştı.**

`kenar_hatalari` alt kenarda **medyan −46,13 pt** gösterdi (sağlıklı tyt2'de
−0,10). İzleme:

* Motor kutusu q1 için `(45,4 · 144,6 · 283,4 · 346,7)`, altın
  `(39,4 · 144,7 · 316,5 · 392,8)`.
* Sol sütunda y 342,4 ile 396,9 arasında **hiç metin yok** — yani altının
  46 pt'lik fazlası içerikten gelmiyor.
* `page.get_text("words")` ile bakıldığında o aralıkta tek bir şey var:
  **`'Y'` harfi, bbox `(207,4 · 273,5 · 396,4 · 462,5)`** — sayfayı çapraz
  kesen "ÖSYM … Bu dokümanın telif hakları …" filigranının bir glifi.
  Döndürülmüş olduğu için bbox'ı 189×189 pt ve merkezi sol sütuna düşüyor;
  `_govde_kutusu` onu içerik sanıp soru kutusunu aşağı uzatıyordu.

**Düzeltme:** `altin_pdf_katmani._filigran_kelimesi_mi` — bir kelime kutusu
sayfa yüksekliğinin %5'ini aşıyorsa **veya** sütun genişliğinden genişse
gövde metni sayılmaz.

**Sonuç (motor kodunda tek satır değişmeden):**

| Belge | F1 | F1@0,75 | alt kenar medyanı |
|---|---|---|---|
| ykstyt2026 | 0,8640 → **0,8720** | 0,4800 → **0,6240** | −46,13 → **−7,63** |
| yksayt2026 | 0,8253 → **0,8434** | 0,5663 → **0,6747** | — |

**Referans korundu:** `tyt1_2026_calibration` filtreyle yeniden üretildiğinde
**750 sorunun 750'sinde kutular birebir aynı** — filtre yalnız filigranlı
kitapları etkiliyor.

## Ders

Bir ölçüm kötü sonuç verdiğinde önce **altının** doğruluğu sınanmalı. Faz 2'de
altını görsel olarak denetlemiştim (kutular sayfa görüntüsünde soruları tam
sarıyordu) ama 46 pt'lik bir alt-kenar şişmesi sayfa ölçeğinde gözle fark
edilmiyor. Sayısal teşhis (`kenar_hatalari`) gözle denetimin göremediğini
gösterdi — Faz 1'in asıl kazancı bu.

## Kalan açıklar

1. **ÖSYM 2026'da alt kenarda uzun kuyruk**: medyan −7,63 pt iyi ama
   p95 = 236 pt ve ortalama −51,9 pt. Bir grup soru hâlâ ciddi biçimde
   kısa kesiliyor; gerekli bölge kapsaması 228/315 (%72). Muhtemelen ortak
   uyaranlı (paylaşılan metin) sorular.
2. **Sağ kenar sözleşme farkı**: altın sütunun tam genişliğini alıyor
   (`sutun["x1"]`), motor metin sınırına traşlıyor → `sag` medyanı sistematik
   −6…−11 pt. Kesim açısından motorun davranışı daha iyi; ölçüm haksız
   ceza veriyor. Ya altın metin sınırına çekilmeli ya da bu fark IoU'dan
   düşülmeli.
3. **Taşma kurtarmaları** (`ml_sekil`, `gomulu_gorsel`, `yazma_alani`) yalnız
   `son_metin` dalında çalışıyor. Plan bunu kusur sayıyordu; incelemede
   **kusur olmadığı görüldü**: diğer dallarda alt sınır zaten bir sonraki
   çapanın hemen üstüdür, yani kurtarılacak yer yoktur.
4. **`kanitsiz_kutu_orani` = 7/753 (%0,93)** TYT'de. Küçük ama sıfır değil.
