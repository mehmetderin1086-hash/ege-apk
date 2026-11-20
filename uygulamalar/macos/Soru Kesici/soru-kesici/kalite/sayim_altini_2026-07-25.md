# Sayım-altını ölçümü ve çözüm-formatı düzeltmesi (2026-07-25)

Önceki turda zincir çapası kuralı `fmt != "coktan_secmeli"` ile daraltılmıştı;
bunun `cozumler1`, `ygslys`, `aydin`, `12meb` üzerindeki kutu düşüşünün
yanlış-pozitif temizliği mi gerçek kayıp mı olduğu **ölçülmemişti**. Bu belge
o soruyu kapatır.

## Yöntem

`altin_sayim.py` ile **kör sayım**: çıplak sayfa render'ı okundu, motorun
kutuları görülmeden soru sayıldı. Tabakalı örneklem: daraltmadan **etkilenen**
sayfalar + kontrol sayfaları. Kısmi örneklem `sampling.kapsam = "kismi"` ile
işaretli — metrik doğru, ama belge genelini temsil etmez.

## Bulgu: daraltma iki belgede doğru, birinde yıkıcıydı

| Belge | Sayfa | Gerçek | Daraltma ÖNCE | Daraltma SONRA |
|---|---|---|---|---|
| cozumler1 | 85 | 11 | 11 ✅ | 1 ❌ |
| cozumler1 | 61 | 12 | 12 ✅ | 3 ❌ |
| cozumler1 | 25 | 6 | 6 ✅ | 4 |
| cozumler1 | 41 (kontrol) | 11 | 11 ✅ | 11 ✅ |
| ygslys | 11 | 10 | 12 | 10 ✅ |
| ygslys | 36 | 10 | 14 | 12 |
| ygslys | 46 | 9 | 12 | 10 |
| aydin | 31 | 6 | 7 | 5 |
| aydin | 211 | 6 | 8 | 6 ✅ |

`cozumler1`'de daraltma `count_recall`'ü **1,00 → 0,475**'e düşürdü (40 çözümün
21'i kayboldu). `ygslys`/`aydin`'da tersine precision'ı iyileştirdi.

## Kök neden: çözüm sayfaları "çoktan seçmeli" sanılıyordu

`cozumler1` bir **çözüm kitabıdır**; her blok `Soru N :` başlığıyla başlar ve
gövdesi düz açıklama metnidir. Ama gövdelerde "Cevap B", "(A)", "A →" gibi şık
harfleri bolca geçtiği için `_sayfa_formati` sayfayı `coktan_secmeli`
sınıflıyordu — oysa aynı sayfalarda 6–12 adet **çözüm çapası** vardı:

| Sayfa | Çözüm çapası | Büyük şık | Eski format |
|---|---|---|---|
| 85 | 11 | 5 | coktan_secmeli ❌ |
| 61 | 12 | 5 | coktan_secmeli ❌ |
| 25 | 6 | 5 | coktan_secmeli ❌ |
| 41 | 11 | 0 | cozumlu ✅ |

Yani ayrım tesadüfen sayfada şık harfi bulunup bulunmamasına bağlıydı.

**Düzeltme:** `_sayfa_formati` artık ≥3 çözüm çapası (`COZUM_NO_DESENI`) gören
sayfayı şık kontrolünden ÖNCE `cozumlu` sayar. Böylece `blok_gecerli_mi`'nin
mevcut çözüm yolu ve zincir çapası devreye girer; TYT gibi gerçek çoktan
seçmeli sayfalar etkilenmez (orada çözüm çapası yoktur).

## Sonuç

| Belge | count_recall | count_precision | gerçek / bulunan |
|---|---|---|---|
| cozumler1 | **1,000** | **1,000** | 40 / 40 |
| ygslys | **1,000** | 0,906 | 29 / 32 |
| aydin | 0,917 | **1,000** | 12 / 11 |
| cozumyazili | 0,897 | **1,000** | 39 / 35 |
| 12meb | 0,227 | 0,833 | 22 / 6 |

TYT altın verisi bozulmadı: F1 0,975 / F1@0,75 0,958.

## Kalan en büyük açık: 12meb s186

22 sorudan 6'sı bulunuyor. Sayfa gridli bir **eşleştirme/boşluk-doldurma**
düzeni: üstte 20–26 numaralı doğru-yanlış maddeleri (her biri ayrı satır
kutusunda), ortada a–o kutucuk gridi (ORTAK UYARAN, soru değil), altta 27–41
numaralı sorular. Bu sınıf henüz çözülmedi ve sıradaki iştir.

İkinci açık: `ygslys` precision 0,906 — üç fazla kutu (yatay çift-sayfa
taramada test başlıkları ayrı kutu oluyor olabilir).
