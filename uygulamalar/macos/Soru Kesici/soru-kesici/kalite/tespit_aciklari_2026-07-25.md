# Tespit açıklarının canlı teşhisi — cozumler1 ve ygslys

**Tarih:** 2026-07-25 · **Faz:** 5 hazırlığı · **Yöntem:** motoru gerçek sayfalarla
koşturup ara çıktıları dökmek. 12meb s186 ayrı belgede
(`12meb_s186_teshis_2026-07-25.md`).

---

## cozumler1 — çözüm sayfası cezası çözüm kitabını yok ediyor

Ölçülen: count_recall **0,600**, otomatik kova **0,175**, s41'de **sıfır kutu**
(yeni `sayim-sifir-sayfa` kuralının koşulsuz kırmızısı).

### Aşama aşama iz

| Sayfa | altın | ham aday | `blok_gecerli_mi` | meta | **teslim** |
|---|---|---|---|---|---|
| s25 | 6 | 6 | — | 6 | 6 |
| **s41** | **11** | **11** | **11/11 GEÇTİ** | **12** | **0** |
| s61 | 12 | 12 | — | 12 | 10 |
| s85 | 11 | 11 | — | 11 | 9 |

Yani s41'de tespit kusursuz: 11 aday bulunuyor, 11 blok geçerli sayılıyor,
12 meta üretiliyor. Çöküş **güven puanlamasında**. Her kutunun kanıt listesi:

```
kanit = ('soru_numarasi', 'yeterli_metin', 'uygun_geometri', 'belge_numara_hizasi')
guven = 0.225        ← GUVEN_INCELE (0,55) altında → hepsi "reddedildi"
```

Mükemmel kanıt, taban güven. Sebep `soru_kes.py:3522-3523`:

```python
if rol in ("kapak", "içindekiler", "çözüm", "cevap_anahtari"):
    puan = min(puan, 0.20); uyarilar.append("soru_disinda_sayfa")
```

Sayfa rolü `çözüm` → güven **0,20'ye tavanlanıyor** → koşulsuz ret. Kural bir
SORU kitabı için doğrudur (çözüm sayfasından soru kesilmemeli); ama bu belge
bir **ÇÖZÜM KİTABIDIR** (`belge_fmt = "cozumlu"`) ve çözümler tam da kesilmek
istenen içeriktir. "Soru dışı sayfa" listesi **belgenin amacına göreli**
olmalı: `fmt == "cozumlu"` iken `çözüm` rolü içerik rolüdür, aykırı rol değil.

Rol tespiti sayfadan sayfaya tutarsız olduğu için (s25/s61/s85'te `çözüm`
çıkmıyor, s41'de çıkıyor) hata belge boyunca rastgele sayfalarda patlıyor —
teşhisi zorlaştıran da bu.

### Ölçülen etki

Yalnız bu kural düzeltilirse (4 altın sayfada, `belge_analiz_et` açık):

| | s25 | s41 | s61 | s85 | **recall** | **oto_recall** |
|---|---|---|---|---|---|---|
| mevcut | 6 | **0** | 10 | 9 | **0,625** | 0,175 |
| düzeltilmiş | 6 | **11** | 10 | 9 | **0,900** | 0,200 |

Sıfır sayfa tamamen ortadan kalkıyor. Kalan açık s61 (2 eksik) ve s85 (2 eksik)
ayrıca incelenmeli.

**Not:** otomatik kova hâlâ 0,200 — teslim edilen 36 kutunun yalnız 8'i
`otomatik`, kalanı `incele`. Çözüm kitaplarında güven puanlaması ayrıca
gözden geçirilmeli; SH-2 (otomatik kovada tam recall) bu belgede en uzak hedef.

---

## ygslys — fazla kutuların hepsi NUMARASIZ, biri otomatik kovada

Ölçülen: count_recall **1,000** (kayıp yok), count_precision **0,906**
(29 gerçek / 32 bulunan). Belge yatay **çift sayfa taraması** (G = 2880,
4 bant = 2 sayfa × 2 sütun).

| Sayfa | altın | teslim | fark | fazla kutuların numarası |
|---|---|---|---|---|
| s11 | 10 | 9 | −1 | — |
| s36 | 10 | 12 | **+2** | `None`, `None` |
| s46 | 9 | 10 | **+1** | `None` |

Üç fazla kutunun **üçü de `numara=None`** — `_blok_segmentasyon`'un "boş bant
kurtarma" yolundan gelen, numarasız bloklar. Biri şu güvenle geldi:

```
no=None  otomatik  g=0.99  bant=3  x=(2163..2880) y=(745..1141)
```

**Numarasız bir kutu, sayfada doğrulanmış numara zinciri varken 0,99 güvenle
otomatik kovaya giriyor.** Bu doğrudan SH-1 ihlalidir: otomatik teslim edilen
kesimlerde sıfır hata hedefi, "kanıtı en zayıf kutu en yüksek güveni alıyor"
durumuyla bağdaşmaz.

**Önerilen kural:** aynı bantta/sayfada ≥2 numaralı kutu varken üretilen
numarasız bir kutu `otomatik` kovaya giremez — en fazla `incele`. Recall'e
zarar vermez (kutu yine teslim edilir, `İncele/` klasörüne düşer), precision'ı
ve SH-1'i doğrudan korur.

### İkincil bulgu: bant kaçağı

Birkaç kutuda `bant_idx` ile x aralığı çelişiyor:

```
s36  no=16 bant=0  x=(814..1496)     ← bant 0 = (0, 857)
s46  no=3  bant=0  x=(843..1518)     ← bant 0 = (0, 888)
```

Kutu, atandığı bandın dışına taşıyor. Boru hattında "bant clamp'i sol+sağ
sütun birleşmesini fiziksel olarak imkânsız kılar" deniyor; bu örnekler
clamp'in her yolda uygulanmadığını gösteriyor. Faz 4'te `_kutu_insa` dışındaki
kutu üretim yollarıyla birlikte ele alınmalı.

---

## Sistemik bulgu: otomatik kova neden her yerde teslimin altında?

Beş sayım-altını belgesinde `otomatik` kovaya girmeyen (incele + reddedildi)
her kutunun uyarıları toplandı:

| Belge | otomatik | incele | reddedildi | baskın uyarı |
|---|---|---|---|---|
| cozumler1 | 7 | 18 | 15 | `soru_disinda_sayfa` (11), uyarısız (18) |
| cozumyazili | 20 | 14 | 0 | **`sutun_uzlasmazligi` (8)** |
| ygslys | 27 | 5 | 0 | `coklu_numara_icerik` (4) |
| aydin | 11 | 0 | 0 | — (temiz) |
| 12meb | 1 | 2 | 3 | uyarısız (4) |

Korpus geneli:

```
<uyarısız>                    28   ← EN BÜYÜK GRUP
soru_disinda_sayfa            11   ← cozumler1 hatası (yukarıda)
sutun_uzlasmazligi             8   ← cozumyazili'nin asıl darboğazı
coklu_numara_icerik            6
yalniz_cozum                   4
soru_modeli_sinir_uyusmazligi  1
tam_sutuna_yakin               1
konu_sayfasinda_aday           1
```

İki çıkarım:

1. **28 kutu hiçbir uyarı taşımadan otomatik kovanın dışında kalıyor.**
   Güven puanı 0,55–0,82 arasında olduğu için `incele`'ye düşüyorlar ama
   *neden* yeterli kanıt toplanamadığı hiçbir yere yazılmıyor. Faz 7 `İncele/`
   klasörüne gerekçe yazmayı öngörüyor — bu kutularda yazacak gerekçe YOK.
   Puanlama, eksik kalan kanıtı da (`kanit_yetersiz: şık yok / gövde yok /
   geometri belirsiz`) kaydetmeli. Hem kullanıcı hem teşhis için gerekli.
2. **`sutun_uzlasmazligi` cozumyazili'nin tek başına en büyük nedeni** (14
   `incele` kutusunun 8'i). Sütun uzlaşması güvensizken güven
   `GUVEN_OTOMATIK − 0,01`'e kırpılıyor (`soru_kes.py:3530-3533`). Kural
   savunulabilir ama bu belgede sistematik ateşliyor: sütun kalibrasyonunun
   neden güvensiz kaldığı ayrıca incelenmeli.

## Faz 5 iş listesi (öncelik sırasıyla, hepsi ölçümle doğrulandı)

| # | Düzeltme | Dosya | Ölçülen kazanç |
|---|---|---|---|
| 1 | `çözüm` rolü cezası belgenin amacına göreli olsun | `soru_kes.py:3522` | cozumler1 0,625 → **0,900**, sıfır sayfa yok olur |
| 2 | Eşleştirme gridi `coktan_secmeli` sayılmasın | `soru_kes.py:2808-2815` | 12meb 3 → **11** teslim |
| 3 | `min_yuk` zincirin çapa aralığından türetilsin | `soru_kes.py:2848-2856` | 12meb 11 → **15** teslim |
| 4 | Hizalama filtresi zincire katılan hizalı kümeyi korusun | `soru_kes.py:4054-4075` | 12meb 15 → **22** (hedef) |
| 5 | Numarasız kutu otomatik kovaya giremesin | `_adaylari_zenginlestir` | ygslys precision 0,906 → hedef 0,99; SH-1 |

**Her biri tek tek ve 44 belgelik korpusun tamamında ölçülerek girmeli.**
Proje kayıtları aynı daraltmanın `ygslys`/`aydin`'da doğru, `cozumler1`'de
yıkıcı olduğunu belgeliyor; TYT kutu-altını (F1 0,9927) bu turda da nöbetçidir.
