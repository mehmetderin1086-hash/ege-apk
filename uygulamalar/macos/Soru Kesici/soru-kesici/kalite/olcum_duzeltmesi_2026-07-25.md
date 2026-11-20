# Ölçüm defekti: metrikler teslim edilmeyen kutuları sayıyordu

**Tarih:** 2026-07-25 · **Faz:** 0 (Sıfır Hata Kampanyası) · **Motor mantığı değişmedi.**

## Bulgu

`dogrula.belge_isle` sayfa başına kutu listesini şöyle kuruyordu:

```python
kutular = [m.kutu for m in meta if not m.devam_aday]      # ← reddedilenler DAHİL
```

Motorun gerçek teslim yolu ise reddedilenleri dışlıyor
(`soru_kes.sorulari_tespit`, `soru_kes._aday_ciktiya_girer`). Bu `kutular` listesi
iki yere birden besleniyordu:

* `dogrula._metrikleri_hesapla` → `toplam_kutu`, `sayfa_soru`, anomali sayımları
  → kalite kapısının **8 kayma sinyalinin tamamı**
* `altin_sayim.sayim_degerlendir` → **`count_recall` / `count_precision`**

Yani kapı, kullanıcının hiçbir zaman göremeyeceği kutuları "bulundu" sayıyordu.
`reddedildi` bir ara etiket değil, nihai karardır: güven puanı
`GUVEN_INCELE = 0.55` altında kalan her aday oraya düşer ve hiçbir kalite
kipinde (legacy dahil) çıktıya yazılmaz.

## Düzeltme

Tek doğruluk kaynağı olarak `soru_kes.aday_tespit_edildi(m)` eklendi; hem motor
hem ölçüm artık onu çağırıyor. Ayrıca `soru_kes.aday_otomatik_teslim(m)` eklendi
— "sıfır hata" hedefinin tanımlı olduğu, insan bakmadan teslim edilen alt küme.

`altin_sayim.sayim_degerlendir` artık İKİ kovayı ayrı ölçüyor:

| Kova | Kapsam | Neyi ölçer |
|---|---|---|
| **TESLİM** (`count_recall`) | otomatik + incele | Soru bulundu mu? `incele` kutusu da bulunmuştur. |
| **OTOMATİK** (`count_recall_auto`) | insan bakmadan teslim edilen | SH-1/SH-2'nin asıl hedefi. |

## Etki — sayım metrikleri

| Belge | count_recall (eski → gerçek) | count_precision (eski → gerçek) | **otomatik recall** |
|---|---|---|---|
| cozumler1 | 1,000 → **0,600** | 1,000 → 1,000 | **0,175** |
| ygslys | 1,000 → 1,000 | 0,906 → 0,906 | 0,897 |
| aydin | 0,917 → 0,917 | 1,000 → 1,000 | 0,917 |
| cozumyazili | 0,897 → **0,872** | 1,000 → 1,000 | **0,513** |
| 12meb | 0,227 → **0,136** | 0,833 → **1,000** | **0,045** |

Precision her yerde yükseldi (yanlış-pozitiflerin çoğu zaten reddediliyordu),
recall düştü. `cozumler1` s41'de motor **hiç kutu üretmiyor** (altında 11 soru
var) — yeni `sayim-sifir-sayfa` kuralı bunu koşulsuz kırmızı sayıyor.

## Etki — proxy (kutu sayısı) metrikleri

| Belge | kutu (eski → gerçek) |
|---|---|
| cozumler1 | 334 → 67 |
| 9konu | 93 → 34 |
| 9pdf | 114 → 44 |
| 11fen | 55 → 24 |
| 10sb | 172 → 147 |
| 12meb | 102 → 74 |
| ygslys | 380 → 378 |
| aydin | 188 → 188 |

`bos-sutun` anomalileri arttı: reddedilen kutular bir sütunu "dolu" gösteriyordu.
Bu artış da gerçek — daha önce gizlenmiş bir kayıptı.

## Kutu-altını (TYT) etkilenmedi

Altın F1 yolu `final_cuts` üzerinden gider ve `kirpma_seti`'nin gerçek çıktısını
kullanır; bu düzeltmeden etkilenmez. Kalibrasyon ölçümü:

**F1 0,9927 / P 0,9907 / R 0,9947 / F1@0,75 0,9820 / mean IoU 0,9327**

(Önceki kayıt f1 0,975 / f1@0,75 0,958 idi; aradaki fark commit edilmemiş
motor çalışmasından geliyor — blok-sınır vetosu, model birleşme koruması,
hizalı çapa filtresi. Bu ölçümle Faz 4'ün F1@0,75 ≥ 0,975 hedefi zaten aşıldı;
Faz 4 hedefi ≥ 0,99'a çekilmelidir.)

## Snapshot tazeleme gerekçesi

`kalite/once_*.json` anlık görüntüleri eski (şişik) kutu kümesine göre
alınmıştı, dolayısıyla her belgede yapay `kutu-dusus` kırmızısı üretiyorlar.
Snapshot'lar `--guncelle --zorla` ile bu yeni ve **daha dürüst** tabana
tazelendi. Bu bir regresyon gizleme değil, ölçü biriminin düzeltilmesidir:
motor mantığında tek satır değişmedi.

## Kapıya eklenenler

1. `kalite_kosusu._sayim_kosusu` — sayım-altını artık kapının parçası
   (ikinci motor koşumu gerekmez, aynı `veriler`/`ornek_no` kullanılır).
2. `_altin_kapisi` — `count_recall_min`, `count_precision_min`,
   `count_recall_auto_min`, `page_exact_min` tabanları + ratchet.
3. `_kayma_degerlendir` 9. sinyal — `sayim-dusus-<ölçüt>` (eşikten bağımsız,
   iki koşum arası doğrudan karşılaştırma).
4. `sayim-sifir-sayfa` — altında soru olan sayfada 0 kutu → koşulsuz kırmızı.
5. `_ikili_kosu` artık `altin=True` — model açık/kapalı farkı F1 ve sayım
   metriklerinde görünüyor (eskiden yalnız anomali sayısına bakıyordu).
6. Snapshot'lara `sayim` bloğu gömüldü → `--guncelle` sayım gerilemesinde de
   bloklar.
