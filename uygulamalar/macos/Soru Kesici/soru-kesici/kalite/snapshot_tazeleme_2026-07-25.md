# Snapshot tazeleme gerekçesi — 2026-07-25

`kalite/once_*.json` referansları 2026-07-21/22 tarihliydi ve V3.3 turundan
önceki motoru yansıtıyordu. Bu yüzden kapı fiilen kapalıydı: örneğin
`once_ygslys.json` 67 anomali gösteriyordu, gerçek değer 3'tü — ygslys 3'ten
60'a fırlasa bile koşum yeşil verirdi.

Tazeleme `--zorla` ile yapıldı; aşağıdaki kırmızı/sarı bulguların her biri
tek tek incelendi ve **meşru iyileşme** olarak doğrulandı.

## Tazeleme öncesi ölçülen durum

| Belge | Anomali | Kutu | Bulgu | Karar |
|---|---|---|---|---|
| 10sb | 4 → 2 | 174 → 172 | — | iyileşme |
| 11fen | 2 → 1 | 47 | — | iyileşme |
| 12meb | 0 → 0 | 60 → **77** | `kutu-artis` | ✅ aşağıda |
| 9konu | 2 → 0 | 62 → 60 | `sayfa-sifirlandi` (örnek 3, 27) | ✅ aşağıda |
| aydin | **25 → 0** | 185 → 188 | — | iyileşme |
| cozumler1 | 5 → 3 | 197 → **256** | `kutu-artis`, `sayfa-kayma` | ✅ aşağıda |
| ygslys | **67 → 0** | 390 → 380 | — | iyileşme |
| cozumyazili | 0 | 27 | — | bu turda düzeltildi (aşağıda) |

Toplam anomali: **10** (README:407'deki iddia doğrulandı).

## İncelenen bulgular

### 9konu — `sayfa-sifirlandi` (örnek sıra 3 ve 27 = sayfa 13 ve 157)
Her iki sayfa da **görsel olarak incelendi** (`sayfa.gorsel()` render'ı):
ikisi de saf **konu anlatımı**, üzerlerinde hiç soru yok. Sayfa 13'teki
`(a) … (g)` işaretleri fotoğraf altı **şekil panel etiketleri**, şık değil.
Eskiden üretilen 1'er kutu **yanlış pozitifti**; V3.3'ün `_sik_harfleri`
düzeltmesi tam bu sınıfı hedefliyordu. Sıfırlanma doğru davranıştır.

### 12meb — `kutu-artis` (60 → 77)
Bu turda düzeltilen format sınıflandırma hatasının sonucu (aşağıya bakınız).
Eşleştirme sayfaları (ör. s186: `a) … h)` seçenek listesi) artık doğru
sınıflanıyor ve daha önce tek bloğa düşen sorular ayrı kesiliyor. Belgenin
anomali sayısı 0'da kaldı.

### cozumler1 — `kutu-artis` (197 → 256), `sayfa-kayma`
V3.3'ün çözüm-çapası (anchor) kuyruk-toleransı düzeltmesinin beklenen
sonucu: daha önce düşen çözüm sütunları kurtarıldı. Anomali 5 → 3 düştü.

### cozumyazili — bu turda düzeltilen gerçek recall kaybı
`_sayfa_formati` (soru_kes.py) çoktan-seçmeli kontrolünü öne alırken kümeyi
`_sik_harfleri` ile hesaplıyordu; bu, yazılı çözüm kâğıtlarındaki
`a. b. c.` **cevap alt maddelerini** şık sanıp sayfayı `coktan_secmeli`
sınıflıyordu. O formatta `blok_gecerli_mi` yazma-alanı kanıtını kabul
etmediği için **düz metin cevaplar tümüyle kaçıyordu** — sayfa 6'da 10
sorudan 5'i (2, 4, 6, 8, 10) hiç kesilmiyordu; belge toplamı 27 → 17.

Düzeltme: erken dönüş yalnız gerçek **büyük A–E** kümesine dayanır. Eşleştirme
listeleri (Türkçe madde harfi `ç)`/`ğ)` veya ≥6 farklı harf) ayrıca ayırt
edilir, böylece 12meb s186 gibi sayfalar açık uçlu sanılmaz.

## Kapı bu vakayı bir daha kaçırmaz

Tazelemeyle birlikte `kalite_kosusu._kayma_degerlendir` devreye girdi: kutu ve
ham aday düşüşü, sayfa sıfırlanması ve anomali TÜRÜ artışı artık kırmızı.
`--guncelle` kırmızı bulgu varken tazelemeyi reddediyor; bu tazeleme bilinçli
olarak `--zorla` ile ve bu belgeyle gerekçelendirilerek yapıldı.
