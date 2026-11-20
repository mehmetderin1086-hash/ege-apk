# KitapKatalog ayrıntılı kullanım kılavuzu

Bu kılavuz kaynak paketini çalıştıran kullanıcılar içindir. Kaynak kurulumunda
model paketi uygulamadan ayrıdır; OCR işlemine başlamadan önce
[model paketi kılavuzunu](MODEL_PAKETI_TR.md) uygulayın.
Tam macOS yayını modelleri `.app` içine gömülü getirir.

## 1. Veri dizini ve çevrimdışı çalışma

KitapKatalog ilk açılışta veri kökü altında şu dizilimi oluşturur:

```text
KitapKatalog/
├── catalog.sqlite3
├── assets/
├── derivatives/
├── ocr-raw/
├── models/
├── exports/
├── web_uploads/
├── yedekler/
├── logs/
└── web_session.json
```

`web_uploads/`, `yedekler/` ve `web_session.json` ilgili web işlevi ilk kez
çalıştığında oluşur. Sunucu olağan kapandığında kendine ait oturum
dosyasını siler; çökmeden kalan kayıt sonraki başlangıçta PID/port/sağlık
el sıkışmasıyla güvenle uzlaştırılır.

macOS’ta varsayılan kök kullanıcı uygulama-verisi dizinindedir; Windows ve
Linux’ta `platformdirs` tarafından platforma uygun kullanıcı dizini seçilir.
Kesin yolu görmek için:

```bash
.venv/bin/kitapkatalog --json init
```

Özel kök ve model yolu tanımlanabilir:

```bash
export KITAPKATALOG_DATA_DIR="/mutlak/yol/veri"
export KITAPKATALOG_MODEL_DIR="/mutlak/yol/KitapKatalog-models"
```

İşlem giriş noktaları dış DNS/TCP bağlantısını engeller. Yalnız Qwen ve
vision sidecar’larının makine içindeki iletişimi için loopback/Unix soketleri
açıktır. Çalışma zamanında model, Python paketi, metadata veya kapak
gönderilmez/indirilmez.

## 2. Fotoğrafları hazırlama

Desteklenen dosya türleri:

```text
JPG/JPEG, PNG, HEIC/HEIF, WEBP, TIFF, BMP, PDF
```

HEIC/HEIF için `pillow-heif`, barkod için `zxing-cpp` kurulmuş olmalıdır;
önerilen `vision` bağımlılık grubu ikisini de getirir.

Yeni kayıtların her kitap için yüz sırası değişmez:

1. ön kapak;
2. ön iç kapak (ön kapağın hemen sonraki sayfası);
3. arka iç kapak (arka kapağın hemen önceki sayfası);
4. arka kapak.

En güvenilir toplu eşleştirme için aynı kitabın dört belgesine aynı temel adı
ve açık rol eki verin:

```text
000001_front.jpg
000001_front_inside.jpg
000001_back_inside.jpg
000001_back.jpg

000002_on.jpg
000002_on_ic.jpg
000002_arka_ic.jpg
000002_arka.jpg
```

Türkçe ve İngilizce rol adları NFC/case kurallarına göre tanınır. Aynı anahtar
için dört rolün her biri tam bir kez bulunduğunda eşleştirme doğrudan kabul edilir.

Rol eki yoksa dosyalar klasör, EXIF çekim zamanı ve ardışık dosya adına göre
dörderli ve yukarıdaki sırada önerilir; bu kümeler otomatik onaylanmaz.
Kaynakları düzeltene veya Eşleştirme Onayı
ekranında karar verene kadar OCR işçisi bunları alamaz.

Tek dört sayfalı PDF doğrudan bu dört role açılır. Toplu aktarımda sayfa
sayısı dördün katı olan PDF, dörder sayfalık kitaplara bölünür: 4 sayfa bir,
40 sayfa on kitap eder; böylece bir tarayıcı oturumu tek dosyada taşınabilir
(tek PDF'te en fazla 400 kitap). Dört ayrı PDF kullanılırsa her biri tek
sayfalı olmalı ve dosya adı rol ekini taşımalıdır. Başka sayfa sayısındaki
PDF’ler sessizce kesilmez; hata/inceleme listesine alınır.

Fotoğraf önerileri:

- Kapağı kadraja bütünüyle alın; dört köşe görünür olsun.
- Yansımayı azaltın ve yazıları hareket bulanıklığı olmadan çekin.
- Dört yüzü ön, ön iç, arka iç, arka sırasıyla peş peşe çekin.
- Aynı klasörde ilgisiz görseller bulundurmayın.
- Kaynak fotoğrafları içe aktarma ve yönetilen kopya tamamlanana kadar
  silmeyin.

## 3. İçe aktarma ve kapasite

### Yönetilen kopya

Varsayılan moddur. İşçi kaynak dosyayı içerik hash’iyle `assets/` altına
atomik olarak kopyalar. Aynı içerik yeniden gelirse kopya çoğaltılmaz.
Kaynağı daha sonra taşıyabilmek ve `.kitaparsiv` yedeğine kapak ekleyebilmek
için önerilir.

Tek kitap:

```bash
.venv/bin/kitapkatalog import-single \
  on.jpg on_ic.jpg arka_ic.jpg arka.jpg
.venv/bin/kitapkatalog import-single kitap-dort-sayfa.pdf
.venv/bin/kitapkatalog import-single kitap-dort-sayfa.pdf --dolap "Dolap 3"
```

Toplu kitap:

```bash
.venv/bin/kitapkatalog import-bulk "/mutlak/yol/kitap-belgeleri"
```

### Dolaba göre içe aktarma

İçe aktarma işi bir dolap (raf) hedefi taşıyabilir; o partiden kataloğa giren
her kitabın nüshası o dolaba yazılır. İki kullanım vardır:

```bash
# Bütün parti tek dolaba
.venv/bin/kitapkatalog import-bulk "/yol/dolap-3-fotograflari" --dolap "Dolap 3"

# Her kitabın dolabı, dosyalarının bulunduğu klasörün adı olsun
.venv/bin/kitapkatalog import-bulk "/yol/kutuphane" --klasor-dolap
```

`--klasor-dolap` ile `kutuphane/Dolap 1/…`, `kutuphane/Dolap 2/…` gibi bir ağaç
tek geçişte birden çok dolabı doldurur. Seçim kökünde duran dosyalar kökün
adını miras almaz; onlar `--dolap` değerine kalır. Web arayüzünde aynı iki
seçenek Toplu aktarım kartındaki **Dolap** kutusu ve **Klasör adını dolap say**
onay kutusudur; **📁 Klasör seç** düğmesi klasör yapısını koruyarak yükler.

Dolap adı `copy.location` serbest metniyle birebir eşleşir. Kayıtlı olmayan
bir ad verilirse dolap kaydı otomatik oluşturulur; böylece Raf Haritası eksik
kalmaz. İşin dolabı sonradan kuyruk ekranındaki iş ayrıntısından
değiştirilebilir; değişiklik yalnız işlenmeye başlamamış kitaplara uygulanır,
kataloğa girmiş kitaplar eski dolaplarında kalır.

İş silme iki adımlıdır: çalışan ya da sıradaki bir iş önce **İptal** edilir,
sonra silinebilir. Kataloğa kitap yazmış iş hiç silinmez — silinseydi o
kitapların OCR kanıtı ve kaynak izi de gidecekti; o işler kayıtta kalır.

### Yalnız kaynak dosyasına başvuru

Fotoğrafı çoğaltmaz:

```bash
.venv/bin/kitapkatalog import-bulk "/mutlak/yol/kitap-belgeleri" --reference
```

Kaynak yol kalıcı sözleşmenin parçasıdır. Dosyanın silinmesi, taşınması,
yeniden adlandırılması veya içeriğinin değiştirilmesi devam/yeniden çalışma
işlemini bozar; bu modda kapaklar taşınabilir yedeğe eklenmez.

### Kapasite kapısı

İş satırı yazılmadan önce program şunlar için muhafazakâr alan ayırır:

- yönetilen kopya seçildiyse özgün görüntülerin toplamı;
- kanonik/perspektif düzeltilmiş ve CLAHE türevleri;
- kapak başına beş sıkıştırılmış ham OCR kanıtı;
- SQLite, FTS5, WAL ve `.part` dosyaları;
- eksikse yaklaşık 10 GiB model bütçesi;
- en az 5 GiB veya hesaplanan alt toplamın `%10`u kadar güvenlik payı.

Alan yetersizse içe aktarma fail-closed biter ve yarım iş oluşturulmaz.

Mevcut muhafazakâr formül şöyledir:

```text
yönetilen kopya = kaynak baytları (reference modunda 0)
türevler         = max(görsel sayısı × 1 MiB, kaynak baytları × 3)
OCR kanıtı       = max(görsel sayısı × 5 × 128 KiB, kaynak baytları / 4)
veritabanı       = max(görsel sayısı × 96 KiB, 32 MiB)
eksik model      = max(0, 10 GiB - kurulu model dizini)
güvenlik payı    = max(5 GiB, yukarıdaki alt toplamın %10'u)
```

Bu bir kota değil, içe aktarma öncesi güvenli alt sınır tahminidir. Gerçek
telefon fotoğrafı ve yoğun arka kapak kanıtı daha fazla/az yer kaplayabilir;
işletim sistemi boş alanını ayrıca izleyin.

### Web yükleme sınırları (v0.7.0)

Tarayıcıdan gelen dosyalar belleğe bir defada alınmaz; 1 MiB parçalarla
benzersiz `.part` dosyasına yazılır. Her parçada dosya ve grup kotası ile
en az 256 MiB boş-disk rezervi denetlenir. Dosya adı/uzantısına ek olarak
görsel, PDF, ses ve XLSX içerik imzası da denetlenir; görsel açıldığında
100 milyon pikseli aşamaz. Başarılı dosya `fsync` sonrası atomik ad
değişikliğiyle yayımlanır; hata veya iptal halinde yarım staging dosyası
temizlenir.

| Yükleme yüzeyi | Dosya sınırı | Grup sınırı | Dosya adedi |
|---|---:|---:|---:|
| Kitap kapağı | 40 MiB | — | 1 |
| Tek/toplu fotoğraf veya PDF içe aktarma | 512 MiB | 8 GiB | topluda en çok 2.000 |
| Tek ses analizi | 100 MiB | — | 1 |
| Toplu ses kuyruğu | 200 MiB | 2 GiB | en çok 500 |
| Üye/sınıf XLSX | 50 MiB | — | 1 |
| `.kitaparsiv` geri yükleme | 8 GiB | — | 1 |

XLSX ile oluşturulan yıl-sonu önizlemesi iki saat sonra temizlenir; kullanıcı
**Vazgeç** derse beklemeden silinir. Onaylanmamış mikrofon kaydı iptal
edildiğinde ses dosyası da silinir. Kota aşımı `413`, güvenli disk rezervinin
altına düşülmesi `507` hatasıdır; bunlar kataloğa kısmi kayıt yazmaz.

İsteğe bağlı parametreler:

```bash
.venv/bin/kitapkatalog import-bulk KLASÖR \
  --name "Depo A" \
  --idempotency-key "depo-a-2026-07"
```

`--no-recursive` alt klasör taramasını, `--no-sequence` ise rol etiketi
olmayan dosyalardan sıralı dört-yüz önerisini kapatır. Aynı
`--idempotency-key` yeniden verilirse yeni iş yerine mevcut iş döner.

## 4. Eşleştirme onayı

Bekleyen dört-yüzlü eşleştirmeleri listeleyin:

```bash
.venv/bin/kitapkatalog pair-reviews
.venv/bin/kitapkatalog pair-reviews --job-id İŞ_KİMLİĞİ
```

Dört önizlemeyi ve rollerini kontrol ettikten sonra:

```bash
.venv/bin/kitapkatalog pair-review ÖĞE_NUMARASI --approve
.venv/bin/kitapkatalog pair-review ÖĞE_NUMARASI --reject
```

Onay öğeyi işlenebilir `paired` aşamasına alır. Ret öğeyi açıklamalı biçimde
hata kuyruğuna taşır; fotoğraf sessizce kaybolmaz.

## 5. Model denetimi ve kalibrasyon

```bash
.venv/bin/kitapkatalog --json engine-status
```

Rapor tam beş OCR kimliğini, Qwen alan çıkarıcısını, model sürümlerini,
artifact hash/boyutlarını ve yerel runtime’ları gösterir. `five_ocr_ready`
`false` ise `run` başlamaz.

Üretim otomatik kabulü için ayrıca şu profil gerekir:

```text
models/calibration/ensemble.json
```

Profil, eser/baskı/fotoğraf oturumu ayrık kalibrasyon verisinden monoton
izotonik yöntemle üretilmiş olmalı ve kendi `minimum_samples` güven eşiğini
karşılamalıdır. Profilin içeriği pipeline yapılandırma hash’ine katılır.
Dosya hiç yoksa veya geçerli olup istatistiksel olarak yetersizse OCR
sonuçları yine üretilir ve saklanır; `auto` alan kararı verilmez. Manifestte
tanımlı dosyanın hash’i/şeması bozuksa paket bütünlüğü hatası verilir ve profil
düzeltilmeden işleme başlamaz. Profili elle yüksek güven değerleri yazarak
oluşturmak güvenlik kapısını geçerli kılmaz.

Kalibrasyon komutu CSV, JSON veya JSONL kaynağında her örnek için
`raw_confidence` (veya `confidence`) ile boolean `correct` alanını bekler:

```json
{"raw_confidence": 0.973, "correct": true}
```

Komuta yalnız `%20` kalibrasyon bölümünün etiketli örneklerini verin; eğitim
ve kör test örneklerini karıştırmayın:

```bash
.venv/bin/kitapkatalog fit-calibration \
  /veri/kalibrasyon.jsonl \
  /model-kaynagi/calibration/ensemble.json \
  --version "kalibrasyon-2026-07" \
  --minimum-samples 200
```

Komut profil digest’ini, örnek sayısını, güvenilirlik ve otomatik-kabul
durumunu raporlar. Asgari sayının altında da profil dosyası üretir fakat
`trusted=false` olur ve otomatik kabul açılmaz. Profili doğrudan önceden
kilitlenmiş son model dizinine eklemeyin. Önce model kaynak dizinine üretin,
sonra `prepare_offline_bundle.py` ile yeni hedef paket oluşturun; böylece
`optional_artifacts` içinde SHA-256 ve boyut kilitlenir.

## 6. Kuyruğu çalıştırma

Bütün hazır işleri çalıştırın:

```bash
.venv/bin/kitapkatalog run
```

Yalnız bir iş:

```bash
.venv/bin/kitapkatalog run İŞ_KİMLİĞİ
```

Varsayılan profil aynı anda iki kitap işçisi açar. Bu değer
`RuntimeLimits.book_workers` ile tanımlıdır. Yeni her kitap için dört yüzün
her birinde beşer, toplam yirmi OCR checkpointi tamamlanır. İşçiler paralel
olsa da kaynak kapıları şöyledir:

| Kaynak | Aynı anda en fazla |
|---|---:|
| Ön işleme | 2 |
| Tesseract | 2 |
| RapidOCR | 1 |
| EasyOCR | 1 |
| PaddleOCR-VL | 1 |
| Surya | 1 |
| Qwen alan çıkarımı | 1 |

Qwen başlayacağı zaman scheduler yeni OCR kabulünü durdurur, çalışan OCR
izinlerinin dönmesini bekler ve yüklü OCR modellerini boşaltır. Qwen bittikten
sonra OCR izinleri yeniden açılır. Süreç ağacı RSS değeri 10 GiB’a yaklaşınca
backpressure uygulanır, 12 GiB sert sınırında yeni ağır model kabulü durur.

Durum zinciri:

```text
discovered -> paired -> preprocessed -> 5_ocr_complete
           -> reconciled -> extracted -> review | completed
```

Her iş öğesi lease/heartbeat taşır. Normal kapatma veya çökme sonrasında
yalnız lease süresi dolan öğeler alınır. Tamamlanmış motorların
`source_sha256 + crop_sha256 + preprocessing_version + model_digest +
config_hash` checkpointleri korunur.

İş yönetimi:

```bash
.venv/bin/kitapkatalog jobs
.venv/bin/kitapkatalog job İŞ_KİMLİĞİ
.venv/bin/kitapkatalog pause İŞ_KİMLİĞİ
.venv/bin/kitapkatalog resume İŞ_KİMLİĞİ
.venv/bin/kitapkatalog cancel İŞ_KİMLİĞİ
.venv/bin/kitapkatalog retry ÖĞE_NUMARASI
```

Motor ilk deneme ve iki yeniden denemeden sonra başarısızsa öğe hata
kuyruğuna geçer. `retry` yalnız seçilen başarısız öğeyi yeniden açar;
geçerli checkpointler tekrar kullanılır.

### Hızı ölçme

Her motor koşumunun süresi zaten kaydediliyor; `perf-report` bunu okur:

```bash
.venv/bin/kitapkatalog --json perf-report
```

Rapor motor başına ortalama/medyan/p95 süreyi, darboğaz motoru, kitap/saat
tahminini ve 10.000 kitabın kaç gün süreceğini verir. İki ayrı üst sınır
hesaplanır: kitap işçisi sayısının izin verdiği hız (`books_per_hour_worker_bound`)
ve ağır modellerin süreçler arası kilitle serileştirilmesinden gelen tavan
(`books_per_hour_heavy_ceiling`). Gerçek sınır ikincisidir; kitap işçisi
sayısını artırmak onu yükseltmez.

## 7. Masaüstü arayüzü

```bash
.venv/bin/kitapkatalog-gui
```

Özel katalog:

```bash
.venv/bin/kitapkatalog-gui \
  --database "/mutlak/yol/catalog.sqlite3"
```

Sekiz sekme vardır:

1. **Kütüphane:** başlık, yazar, yayınevi, ISBN ve ham OCR metninde FTS5
   araması; 14 sütunlu tablo, kapak küçük resimleri ve durum/dil/kategori/
   eksik-alan filtreleri. Seçili kaydın detay panelinden bütün alanlar
   düzenlenebilir, nüsha adedi ve **dolap (raf konumu)** değiştirilebilir.
   Çoklu seçimle toplu onay, kategori/dolap/adet atama ve silme yapılır.
   1000'den fazla kayıtta sayfalama görünür.
2. **İçe Aktarma ve Kuyruk:** ayrı `Tek Kitap` ve `Toplu Kitap` eylemleri,
   fotoğraf/PDF seçimi, saklama modu, kapasite özeti,
   çoklu iş listesi, motor sayaçları, hız, kalan süre, duraklat/devam ve seçili
   hatayı yeniden deneme.
3. **Sesli Kayıt:** mikrofonla canlı kayıt veya ses dosyalarının toplu
   kuyruğu; ayrıntılar aşağıdaki *Sesli kitap kaydı* alt bölümünde.
4. **Eşleştirme Onayı:** belirsiz dört-yüzlü öneriler, dört görsel önizlemesi,
   eşleştirme yöntemi/güveni ve onay/ret.
5. **Kitap Bilgisi İncelemesi:** dört yüz önizlemesi, kanıtlı alanları düzeltme
   ve kullanıcı değeri olarak kilitleme. Kayıt sesle girildiyse transkript
   kanıtı da gösterilir ve dinlenebilir.
6. **Dışa Aktarım:** XLSX/CSV/JSON/JSONL/Markdown, tamamlanmış kayıt filtresi
   ve kapakları isteğe bağlı taşıyan `.kitaparsiv` yedeği.
7. **5 OCR Durumu:** beş OCR ile Qwen artifact/runtime hazır olma denetimi.
8. **İstatistik:** toplam kayıt özeti ile kategori, dil, yayınevi ve durum
   dağılım tabloları. Yalnız sekme görünürken yenilenir.

Arayüzdeki uzun işler arka planda yürür. Kapatma tamamlanmış checkpointleri
silmez; sonraki açılışta süre dolmuş iş devam eder.

### Sesli kitap kaydı

Kitaplar fotoğraf yerine sesle de kataloglanabilir. Konuşma yerel whisper.cpp
sunucusuyla yazıya çevrilir, alanlar deterministik Türkçe ayrıştırıcıyla
(gerekirse kanıt-bağlı Qwen yedeğiyle) çıkarılır. OCR yolundan bağımsızdır ve
çalışma anında yine tamamen çevrimdışıdır.

İki kullanım biçimi vardır:

- **Canlı kayıt.** Mikrofon aygıtını seçin, `F2` ile kaydı başlatıp bitirin.
  Anlaşılmayan bir alanı `F4` ile yeniden söyleyebilir, `F6` ile atlayabilir,
  `Enter` ile kaydedebilirsiniz. Hızlı modda kayıt tamamlanınca bir sonraki
  kitabın kaydı kendiliğinden başlar; böylece kitap yığını eller serbest
  işlenebilir.
- **Toplu ses kuyruğu.** Hazır ses dosyalarını sekmenin alt bölümüne sürükleyip
  bırakın veya dosya seçiciyle ekleyin. Kuyruk OCR kuyruğuyla aynı dayanıklı
  yapıyı kullanır: duraklatılabilir, çökme sonrası kaldığı yerden sürer.

Konuşma protokolü alan adını söyleyip değerini vermeye dayanır. Tanınan on bir
alan ve örnek anahtar kelimeleri:

| Alan | Söylenebilecek anahtar kelimeler |
|---|---|
| ISBN | `isbn`, `ısbn numarası` |
| Başlık | `kitabın adı`, `kitap adı`, `başlık`, `adı`, `ismi` |
| Yazar | `yazar`, `yazarı`, `yazarlar` |
| Çevirmen | `çevirmen`, `çevirmeni`, `çeviren` |
| Yayınevi | `yayınevi`, `yayın evi`, `yayıncı`, `yayıncısı` |
| Basım yılı | `basım yılı`, `baskı yılı`, `yayın yılı`, `yıl` |
| Sayfa sayısı | `sayfa sayısı`, `sayfası`, `sayfa` |
| Dil | `dil`, `dili` |
| Kategori | `kategori`, `kategorisi`, `tür`, `türü`, `raf` |
| Dolap | `dolap`, `dolabı`, `dolap numarası`, `raf numarası` |
| Adet | `adet`, `tane`, `kopya`, `nüsha` |

Anahtar kelimeler Türkçe büyük/küçük harf ve aksan farklarına duyarsız eşleşir;
uzun olan kısa olandan önce denenir, böylece `raf numarası` (dolap) ile `raf`
(kategori) karışmaz. ISBN rakam rakam okunabilir; sayılar ve ayraçlar Türkçe
ayrıştırıcıyla birleştirilir. Söylenmeyen alan tahmin edilmez, boş bırakılır.

Dolap (raf konumu) değeri **yapışkandır**: form temizlendiğinde korunur, çünkü
aynı raftaki kitaplar arka arkaya kaydedilir. Aynı ISBN'e sahip bir kayıt zaten
varsa uygulama "adet artır / yeni kayıt / vazgeç" diye sorar.

Sesle girilen kayıtlar da **Kitap Bilgisi İncelemesi** sekmesine düşer; orada
transkript kanıt olarak gösterilir ve ses dinlenebilir.

## 8. Arama, inceleme ve yerel metadata

Katalog sözleşmesi şu görünen bilgileri saklayabilir:

- başlık, alt başlık ve özgün başlık;
- yazar, çevirmen, editör, derleyen, çizer, önsöz yazarı ve diğer katkılar;
- yayınevi, imprint/marka, seri ve cilt;
- basım yeri/tarihi, baskı, basım numarası ve matbaa;
- ISBN-10/13, GTIN ve görünen diğer tanımlayıcılar;
- dil, cilt türü, sayfa sayısı ve fiziksel boyut;
- basılı fiyat/para birimi, tanıtım yazısı, ödül ve alıntılar;
- izinli bir standart alana oturmayan fakat kapakta açıkça görünen diğer iddia.

Alan çıkarıcı yüz rolünü kanıtın parçası olarak kullanır:

| Yüz | Öncelikli alanlar |
|---|---|
| Ön kapak | Başlık, alt başlık, yazar, çevirmen, yayınevi, seri |
| Ön iç kapak | Basım yılı/yeri, baskı ve basım numarası, matbaa, telif/imprint, katkılar |
| Arka iç kapak | Sayfa sayısı, fiziksel boyut ve görünen üretim bilgisi |
| Arka kapak | ISBN-10/13, barkod, fiyat, tanıtım, ödül ve alıntılar |

Bu tablo bir tahmin izni değildir. Örneğin sayfa sayısı arka iç kapakta
okunmuyorsa başka baskıdan tamamlanmaz; `bilinmiyor` kalır. Bir alan farklı
yüzde açıkça görünüyorsa yine kanıtıyla aday olabilir.

Bir alan görünmüyorsa Qwen tamamlamaz. Alan adayının kapak rolü, kaynak token
kimlikleri, motor desteği, kanonik ve özgün-fotoğraf poligonu ile güveni
`field_observation` içinde; seçilen/kilitlenen değeri `resolved_field` içinde
korunur.

ISBN-10/13 kontrol basamağı geçersiz değer katalog tanımlayıcısı olmaz.
Birbirine dönüştürülebilen ISBN-10 ve ISBN-13 aynı baskı kimliği sayılır. OCR
ISBN’si için iki bağımsız motor kanıtı gerekir; consensus metni ek motor oyu
değildir. Geçerli barkod ile OCR adayları kısmen bile uyuşmazsa kayıt
incelemeye gider.

Tam metin arama:

```bash
.venv/bin/kitapkatalog search "Kürk Mantolu Madonna"
.venv/bin/kitapkatalog search "" \
  --publisher "Yapı Kredi" \
  --language tr \
  --review-status review \
  --identifier 9789753638029 \
  --limit 50 \
  --offset 0
```

İncelenecek kayıtlar:

```bash
.venv/bin/kitapkatalog review
.venv/bin/kitapkatalog review --id 17
.venv/bin/kitapkatalog review --id 17 \
  --set "title=Kürk Mantolu Madonna" \
  --set "publisher=Yapı Kredi Yayınları" \
  --approve
```

Kullanıcının düzelttiği alan kilitlenir; sonraki OCR çalışması bu değeri
sessizce değiştiremez.

Yerel katalog içe aktarımı:

```bash
.venv/bin/kitapkatalog import-metadata katalog.csv
.venv/bin/kitapkatalog import-metadata katalog.json
.venv/bin/kitapkatalog import-metadata katalog.jsonl
.venv/bin/kitapkatalog import-metadata katalog.xml
```

XML yalnız güvenli ONIX ürün alanları için desteklenir; `DOCTYPE` ve `ENTITY`
içeren dosyalar reddedilir. ISBN aynı baskıyı eşleştirmede kullanılır.
`--fail-fast` ilk hatalı satırda işlemi durdurur; varsayılan davranış hatayı
raporlayıp sonraki satıra geçmektir. Hiçbir çevrimiçi katalog sorgulanmaz.

## 9. Dışa aktarım

```bash
.venv/bin/kitapkatalog export /hedef/kitaplar.xlsx
.venv/bin/kitapkatalog export /hedef/kitaplar.csv
.venv/bin/kitapkatalog export /hedef/kitaplar.json
.venv/bin/kitapkatalog export /hedef/kitaplar.jsonl
.venv/bin/kitapkatalog export /hedef/notlar --format markdown
```

Varsayılan olarak yalnız son kullanıcıya sunulabilir `review`/`completed`
kayıtların tutarlı SQLite anlık görüntüsü dışa aktarılır. Tanılama amacıyla
`--include-incomplete` kullanılabilir.

| Biçim | Özellik |
|---|---|
| XLSX | Write-only; yedi sayfa; kapak yolu; formül enjeksiyonu koruması |
| CSV | Düz kitap görünümü; UTF-8 BOM; formül enjeksiyonu koruması |
| JSON | Katkılar, tanımlayıcılar ve nüshalarla tam hiyerarşi |
| JSONL | Büyük kataloglar için satır başına bir kitap |
| Markdown | Hedef klasörde kitap başına güvenli adlı ayrı not |

XLSX sayfaları:

```text
Özet
Kitaplar
Katkıda Bulunanlar
Tanımlayıcılar
Ayrıntılı Alanlar
İnceleme Gerekenler
Hatalar
```

Bütün dosya çıktıları aynı hedefte `.part` olarak tamamlanır ve sonra atomik
ad değişikliğiyle yayımlanır. İşleme sürerken alınan çıktı, snapshot
başlangıcındaki tutarlı kayıtları gösterir.

## 10. `.kitaparsiv` yedeği

Yalnız veritabanı:

```bash
.venv/bin/kitapkatalog archive create /hedef/KitapKatalog.kitaparsiv
```

Yönetilen kapaklarla:

```bash
.venv/bin/kitapkatalog archive create /hedef/KitapKatalog.kitaparsiv \
  --include-covers
```

Özel yönetilen varlık kökü varsa `--asset-root` verilebilir. Arşiv, SQLite
backup API ile alınan WAL-tutarlı veritabanını, sürümlü manifesti ve her
üyenin SHA-256/boyutunu taşır.

Doğrulama:

```bash
.venv/bin/kitapkatalog --json archive inspect \
  /hedef/KitapKatalog.kitaparsiv
```

Güvenli çıkarma yalnız boş hedefe yapılır:

```bash
.venv/bin/kitapkatalog archive extract \
  /hedef/KitapKatalog.kitaparsiv \
  /hedef/boş-klasör
```

Mutlak yol, `..`, ters eğik çizgili kaçış, özel dosya türü veya hash
uyuşmazlığı varsa çıkarma başlamaz. Komut mevcut kataloğun üzerine yazmaz.

## 10a. Kütüphane otomasyonu (v0.4.0)

Web arayüzü (masaüstündeki **KitapKatalog.app** ya da
`scripts/launch_kitapkatalog.command`) okul kütüphanesi işletimi için şu
modülleri içerir:

**Hızlı Kayıt** — USB barkod okuyucuyla ISBN okutun: kitap kayıtlıysa tek
tuşla +1 nüsha eklenir, değilse kısa form açılır. Demirbaş numaraları
yıl+sıra biçiminde otomatik atanır (örn. `2026-000001`) ve elle
değiştirilebilir.

**Üyeler** — e-Okul'dan alınan sınıf listesi (.xlsx) toplu içe aktarılır;
başlık satırı otomatik bulunur, tekrar eden/numarasız satırlar raporlanır.
Yıl sonunda yeni listeyi **Yıl Sonu Sınıf Atlatma** sihirbazına verin:
önizleme hiçbir kaydı değiştirmez; onaylayınca sınıflar güncellenir,
listede olmayan öğrenciler pasife alınır. Emniyet: boş/bozuk dosya ya da
aktif öğrencilerin yarısından fazlasını pasifleştirecek liste reddedilir.

**Ödünç** — üye seçip barkod okutarak verin; iade için üye seçmeye gerek
yok, kitabın barkodu yeter. Süre ve azami kitap sayısı öğrenci/personel
için ayrı ayrı Ayarlar'dan belirlenir. Gecikmiş kitabı olan üye (ayar
açıksa) yeni kitap alamaz; istenirse geç iadeye gecikme günü kadar bekleme
cezası uygulanır.

**Sayım** — oturum açın (tüm kütüphane ya da tek dolap/raf) ve kitapların
ISBN barkodunu okutun. Etiket gerekmez: program okutma adedini kayıtlı
nüsha sayısıyla karşılaştırır; ödünçteki kitaplar kayıp sayılmaz. Aynı
demirbaşın ikinci okutması ve kapsam dışı demirbaş sayılmaz (uyarı
gösterilir). ISBN'siz kitaplar "elle sayım gerekir" listesine düşer.
Oturum günlerce açık kalabilir; kapatınca eksik/fazla raporu ve Excel
çıktısı alınır.

**Düşüm** — yıpranmış/kayıp kitabı demirbaştan düşün (kayıt silinmez,
deftere işlenir; yanlış düşüm geri alınabilir). Sayım raporundaki
**Kayıpları Düşüme Aktar** düğmesi yalnız kapalı oturumda çalışır ve
eksikleri işlem anında yeniden doğrular. MEB biçimli düşüm tutanağı
Excel olarak indirilir.

**Raporlar** — en çok okuyanlar, sınıf bazında ödünç, popüler kitaplar ve
aylık seri; dönem süzgeci ve Excel çıktısıyla.

**Öğrenci Ekranı (OPAC)** — `http://127.0.0.1:<port>/opac` adresi oturum
gerektirmez; öğrenciler kitap arayıp "rafta/ödünçte" durumunu görür,
yönetim işlemlerine erişemez. Kütüphane bilgisayarında ayrı bir pencerede
açık bırakılabilir.

**Otomatik yedek** — sunucu her gün ilk açılışta `.kitaparsiv` yedeği alır
(varsayılan `veri kökü/yedekler`, son 10 dosya saklanır; Ayarlar'dan klasör
ve adet değiştirilebilir).

## 10b. v0.5.0 yenilikleri

**Okul numarasıyla ödünç** — Ödünç ekranındaki üye kutusuna okul numarasını
okutun/yazıp Enter'a basın: tam eşleşen üye anında seçilir ve odak kitap
alanına geçer (üye kartı basıldıysa karttaki barkodu okutmak yeterli).
Numara bulunamazsa ada göre arama sürer. Aynı üyeye arka arkaya kitap
verilebilir; işiniz bitince **Üyeyi bırak** düğmesiyle sıfırlayın.
Dikkat: üye kartı ÜYE kutusuna, kitap barkodu KİTAP kutusuna okutulur —
alanlar karışırsa hata mesajı hangi alanın beklendiğini söyler.

**Raf Haritası** — kütüphanenin dolap düzenini ızgara üzerinde gösterir:
her dolapta nüsha/eser sayısı, ödünçteki adet ve (kapasite girildiyse)
doluluk çubuğu. Dolaba tıklayınca Kütüphane sayfası o dolabın kitaplarıyla
açılır. Dolap kaydı ad + satır/sütun + kapasite + renk alır; ad değişince
kitapların konum metni otomatik taşınır. "Haritada olmayan konumlar"
paneli, nüshalarda geçen ama dolap kaydı olmayan (çoğu zaman yazım
varyantı) konumları listeler: tek tıkla dolap yapın ya da mevcut dolaba
taşıyıp birleştirin. Kitap detayındaki nüsha listesinden tek nüshanın
dolabı ayrıca değiştirilebilir; formdaki "Dolap (tüm nüshalar)" alanı ise
baskının tamamını günceller.

**Gelişmiş arama** — Kütüphane filtre çubuğuna dolap, müsaitlik
(rafta / tümü ödünçte), basım yılı aralığı ve sıralama (başlık, yıl,
eklenme, popülerlik) eklendi. OPAC'ta kategori süzgeci, "yalnız rafta
olanlar" kutusu ve **Yeni Gelenler** / **Popüler** sekmeleri var; öğrenci
ekranı yine yalnız katalog bilgisi görür.

**Yazdır** — üç çıktı türü, hepsi tarayıcının yazdırma penceresinden:
- *Demirbaş etiketleri*: Code128 barkodlu A4 etiket sayfası (3 sütun).
  Kapsam: tüm katalog ya da tek dolap; kitap detayından tek kitabın
  etiketleri de açılır. Etikette yalnız demirbaş numarası olan nüshalar
  basılır — **1) Kod ver** düğmesi kapsamdaki kodsuz nüshalara sıradaki
  numaraları verir, sonra **2) Etiketleri aç**.
- *Üye kartları*: okul adı + ad-soyad + sınıf + okul numarası barkodu
  (2×4 kart). Sınıf seçilerek basılır; kart, ödünç ekranında üye kutusuna
  okutulur.
- *Gecikme listeleri*: sınıf başına ayrı sayfa, sınıf öğretmenine teslim
  formatı. Ödünç sayfasının Gecikenler sekmesinden de açılır.

**Üye özeti** — Üyeler tablosunda satıra tıklayın: üzerindeki kitaplar,
gecikmeler, okuma geçmişi, toplam/geç iade sayıları ve (ceza ayarı
açıksa) bekleme cezasının bitiş günü tek çekmecede. Kitap detayında da
"Ödünç geçmişi" bölümü kimin ne zaman aldığını gösterir (yalnız yönetim
ekranında).

**Pano** — Genel Bakış'a bugün verilen/iade alınan sayaçları ve son 30
günün popüler 5 kitabı eklendi.

## 10c. v0.6.0 yenilikleri

**Yedekten Geri Yükleme** — Dışa Aktarım sayfasındaki "Yedekten Geri Yükle"
kartına bir `.kitaparsiv` dosyası yükleyin: içerik doğrulanır ve özet
gösterilir (kaç kitap/nüsha/üye/ödünç kaydı, yedek tarihi, okul adı).
**Onayla**'dıktan sonra değişiklik, uygulamayı TAMAMEN kapatıp yeniden
açınca uygulanır (başka bir KitapKatalog penceresi/süreci açıksa bir
sonraki tek başına açılışa ertelenir). Güvenlik: mevcut katalogun ham
kopyası `geri-yukleme/onceki-catalog-*` olarak, kapaklı tam yedeği de
`yedekler/geri-yukleme-oncesi-*.kitaparsiv` olarak otomatik alınır; yanlış
yüklemede bu dosyayla geri dönülebilir. Bekleyen geri yükleme **Vazgeç**
ile iptal edilebilir. Daha yeni sürümle alınmış yedek daha yüklerken
reddedilir; eski sürüm yedeği açılışta otomatik güncellenir.

**Satır işlemleri** — Kütüphane tablosunda her satırda ✏️ Düzenle ve
🗑️ Sil; Adet sütununda kaç nüshanın ödünçte olduğu görünür. Üyeler
tablosunda Düzenle / Pasifleştir-Aktifleştir / Sil. Üye silme yalnız hiç
ödünç izi olmayan kayıtlarda çalışır; geçmişi olan üye için program
pasifleştirmeyi önerir (kayıtlar korunur).

**Uzatma sınırı** — Ayarlar'a "Azami uzatma sayısı" eklendi (varsayılan 2,
0 = sınırsız). Davranış değişikliği: GECİKMİŞ bir ödünç uzatılırsa yeni
son gün eski tarihten değil, bugünden itibaren hesaplanır (eskiden geçmişte
kalabiliyordu).

**OPAC kapakları** — öğrenci arama ekranındaki kartlarda kitabın ön kapak
küçük görseli gösterilir (kapak yoksa 📕 simgesi). Kapak ucu yalnız küçük
boy servis eder ve veri kökü dışındaki yollara asla dokunmaz.

**Arayüz** — sayfa/çekmece/pencere geçişleri ve buton-kart etkileşimleri
hafif animasyonlarla yumuşatıldı (sistemde "hareketi azalt" açıksa tümü
kapanır). Genel Bakış'a hızlı eylem kısayolları, Raporlar'a aylık ödünç
çizgi grafiği eklendi.

## 10d. v0.7.0 yenilikleri

**Güvenli web yaşam döngüsü** — sunucu, 0600 izinli ve atomik yazılan
`web_session.json` içinde port, token, nonce, sürüm, PID ve başlangıç
zamanını yayımlar. Başlatıcı mevcut sunucuyu ancak `/health` yanıtındaki
`app + nonce + version` birebir eşleşirse kullanır. Eski/uyumsuz dinleyiciyi
yalnız aynı kullanıcının gerçek `kitapkatalog.webapp.server` süreci olduğunu
doğrulayabildiğinde kapatır; aksi halde ikinci sunucu açmadan hata verir.
Oturum tokeni konsol veya `web.log` içine yazılmaz. `/health`, uygulama
sürümüyle birlikte gerçek `schema_version` değerini de gösterir.

**Atomik katalog formları** — kitap ekleme/düzenleme önce tüm girdileri
doğrular, ardından tek transaction içinde başlık, ISBN, yazar, konum ve aktif
nüshayı yazar. Toplu eylemde aynı atomiklik seçilen her kitap için ayrı
uygulanır ve kitap-bazlı hatalar ayrı raporlanır. İç içe servis çağrıları
savepoint kullanır. Geç bir hata bile o iş-birimini tümden geri alır;
yarım kitap, ISBN veya nüsha bırakmaz.

**Aktif ve düşülmüş nüsha ayrımı** — arayüzdeki **Adet** ve API'deki
`copy_count` yalnız `active` nüshaları sayar. Düşülmüş fiziksel nüsha
satırı ve `discard_record` denetim izi korunur; adet değişikliği bunları
silmez veya yeniden etkinleştirmez. Ayrıntıda `active_copies`,
`discarded_copies` ve `total_copy_records` ayrı gösterilir. Aktif ödünçteki
nüsha azaltma için silinmez; istenen sayı güvenle sağlanamıyorsa ulaşılan
aktif adet döner. “Dolap (tüm nüshalar)” da yalnız aktif nüshaları taşır.

**Hız ve şema 7** — başlık/eklenme, yayınevi, dil, kategori, inceleme,
basım yılı, aktif nüsha-konum, eşleştirme incelemesi ve ödünç tarihleri
için yeni bileşik veya kısmi indeksler kullanılır. Liste uçları önce
yalnız sayfa kimliklerini/dar alanları alır; kitap ayrıntısı istenmedikçe
ham OCR metni ve ağır ilişkiler taşınmaz. İçe aktarma ve ses kuyruğu
sayaçları her normal durum geçişinde aynı transaction içinde sabit-zamanlı
delta ile güncellenir; tam tarama yalnız migration/açık onarım yoludur.

**Dosya ve istek sınırları** — yukarıdaki web yükleme kotaları bütün
dosya kabul yüzeylerinde uygulanır. OPAC küçük resmi, içe aktarma inceleme
görseli, ses ve dışa aktarım indirmesi yalnız kendisine ayrılan yönetilen
kökten servis edilir; kök dışına çözülen sembolik bağ `404` olur. Oturumlu
yönetim ekranı, reference-mode veya eski Qt ile seçilmiş dış kapakları
ham sunmak yerine sınırlı JPEG türevine çevirir. `Origin` denetimi
şema+host+port olarak birebirdir; başka bir
localhost portundan gelen istek kabul edilmez.

**Mobil ve klavye kullanımı** — 900 px altında yan menü çekmeceye, 600 px
altında formlar tek sütuna döner; geniş tablolar kendi alanında yatay kayar.
**İçeriğe atla** bağlantısı, ARIA sekme/dialog/canlı bölge etiketleri,
modal odak tuzağı ve odak geri yüklemesi vardır. `Escape`, ok tuşları,
`Home`/`End` ve klavyeyle satır eylemleri desteklenir; hareketi azalt tercihi
korunur. Otomatik yenilemeler görünmeyen sekmeyi gereksiz yere çizmez ve
eski ağ yanıtının yeni sonucu ezmesini engeller.

**Yedekleme ve geri yükleme** — otomatik yedek denetimi açılıştan kısa
süre sonra ve ardından saatte bir çalışır; günde-bir/rotasyon politikası
aynı günde ikinci arşivi engeller. Yönetilen kapaklar yedeğe dahildir.
Geri yükleme hazırlığı `integrity_check`, `foreign_key_check`, kesin
uygulama kimliği ve migration/`user_version` tutarlılığını denetler.
Arşivde tekil karşılığı olmayan mutlak, göreli veya belirsiz kapak yolu
yeni katalogda `NULL` yapılır.

**macOS başlatıcı güncellemesi** — hafif `KitapKatalog.app`, aynı disk
üzerindeki staging dizininde kurulur; paket sürümü, ikili dosyası ve kod
imzası doğrulandıktan sonra atomik yeniden adlandırılır. Değişim
başarısızsa önceki uygulama geri alınır. Bu hafif başlatıcı kaynak ağacı
ile `.venv`'e bağlıdır; bağımsız native yayın değildir.

## 10e. v0.8.0 güvenli yükseltme ve günlük kullanım

### İlk v0.8 açılışı

Mevcut katalog şeması v1–v7 ise web, komut satırı ve Qt aynı güvenli açılış
yolunu kullanır. Program önce başka bir KitapKatalog sürecinin kataloğu açık
tutmadığını özel uygulama kilidiyle doğrular. Canlı dosyada bütünlük, yabancı
anahtar, uygulama kimliği ve migration sırası denetlenir; denetim başarısızsa
katalog değiştirilmez.

Denetim geçerse veri kökündeki `yedekler/` klasörüne şu biçimde bir arşiv
yazılır:

```text
surum-yukseltme-oncesi-v7-v8-YYYYMMDDTHHMMSS-ffffffZ.kitaparsiv
```

Arşiv, SQLite’ın WAL-tutarlı anlık görüntüsünü ve bulunan tüm yönetilen
kapakları içerir. Tamamlanmış ZIP üye kümesi, boyutları ve SHA-256 değerleri
yeniden doğrulanmadan migration başlamaz. Geçişten sonra şema v8 ve temel
`work/edition/copy/member/loan/import_job` sayımları yeniden okunur. Bu son
kontrol başarısız olursa uygulama özel izinli geçici dosyadan atomik olarak
eski veritabanına döner ve kullanıcıya güvenli yedeğin yerini bildirir.
Yedek üretilemeyen, disk alanı yetmeyen veya rollback doğrulanamayan durumda
“başarılı yükseltme” mesajı verilmez.

### Bankoda güvenli yeniden deneme

Ödünç ekranındaki **Son İşlemler** alanı yalnız bu tarayıcı oturumunda yapılan
son 30 ödünç, iade ve uzatmayı gösterir. Her satırda işlem türü, kitap/demirbaş
kodu, üye, saat ve sonuç bulunur. Barkod okuyucuyla seri çalışmada aktif giriş
alanı işlem tamamlandıktan sonra yeniden odaklanır.

Her mutasyon için istemci bir `request_id` üretir. Sunucu bu kimliği, isteği ve
sonucu `circulation_event` günlüğüne aynı transaction içinde yazar. İstek
sunucuda tamamlanıp ağ yanıtı kaybolursa satır **Başarısız** görünebilir; ağ
hatası veya 5xx için görünen **Aynı işlemi güvenle yeniden dene** düğmesine
basın. Düğme yeni kimlik üretmez: sunucu önceki sonucu döndürür, kitabı ikinci
kez vermez/iade etmez ve uzatma sayısını ikinci kez artırmaz. Doğrulama/iş
kuralı hatalarında (örneğin 409) otomatik güvenli-deneme düğmesi gösterilmez;
önce belirtilen sorunu düzeltin.

Bir üye aynı baskının iki farklı fiziksel nüshasını eşzamanlı alamaz. İade
edildikten sonra yeniden alabilir. Geç iade yanıtında kayıt artık kapalı olsa
bile `days_overdue`, gerçek iade günü ile son gün arasındaki farkı korur;
banko “Zamanında iade” yerine gecikme gününü gösterir.

### Tarihsel raporlar ve veri-kalitesi uyarısı

v8’den sonra verilen her kitapta aşağıdaki alanlar ödünç anında sabitlenir:

- üyenin görünen adı;
- okul/personel numarası;
- sınıfı;
- öğrenci/personel türü;
- ödünç gününün içinde bulunduğu `YYYY-YYYY` öğretim yılı.

Üyenin adı/sınıfı daha sonra düzenlense veya katalogdaki canlı üye kaydı
pasifleştirilse bile geçmiş dönem raporu değişmez. Raporlar ekranı ve indirilen
XLSX dosyasının **Bilgi** sayfası `Kesin v8 dolaşım kaydı` ile `v8 öncesi
tahmini kayıt` sayılarını ayrı gösterir. v7 ve daha eski ödünçler bu alanlara
sahip olmadığından geçiş anındaki canlı üye kaydıyla doldurulur ve
`migration-estimate` olarak işaretlenir; bu satırlar tarihsel olarak kesinmiş
gibi sunulmaz.

### Yıl sonu açık kitap çözüm listesi

**Üyeler → Yıl Sonu Sınıf Atlatma** ekranında yeni e-Okul XLSX dosyasını
önizleyin. Yeni listede bulunmayan öğrenci üzerinde açık ödünç yoksa olağan
pasifleştirme planına girer. Üzerinde kitap varsa program öğrenciyi aktif
tutar ve **İşlem bekleyen açık ödünçler** uyarısında ad, numara, sınıf ve açık
kitap sayısıyla listeler.

**Uygula** yalnız güvenli sınıf/pasifleştirme değişikliklerini gerçekleştirir;
çözüm listesi uygulamadan sonra kaybolmaz. Listelenen kitapları bankodan iade
alın, sonra üyeyi gerektiğinde ayrıca pasifleştirin. Böylece yıl sonu işlemi
açık ödüncün üyesini görünmez hale getirmez ve dolaşım izi korunur.

### Kaydedilmemiş form koruması

Kütüphane ayrıntısı, yeni kitap, üye, hızlı kayıt, onay ve ayar formlarında
bir alan değişmişse başka ana sayfaya geçiş **Kal / Vazgeç** kararı ister.
**Kal**, sayfayı ve yazılan değerleri korur; **Vazgeç**, taslağı bırakıp hedef
sayfaya geçer. Ayarlar formu sunucudan ilk değerleri alırken geçici olarak
`inert` olur; önceki ziyaretin gecikmiş ağ yanıtı yeni düzenlemeyi ezemez.

Qt arayüzünde kitap ayrıntısı kirliyken başka kitap satırı veya ana sekme
seçmek ve pencereyi kapatmak da aynı korumaya tabidir. **İptal** seçilirse eski
sekme/form ve uygulama kilidi açık kalır; **Vazgeç** seçilirse form kayıtlı
değerle yeniden doldurulur.

### Özel dosya izinleri ve kapaklı arşiv

KitapKatalog’un oluşturduğu veri dizinleri yalnız kullanıcıya açık `0700`,
SQLite/WAL/SHM, oturum, staging, rollback ve `.kitaparsiv` dosyaları `0600`
izinle yayımlanır. `--database` ile mevcut bir ortak üst klasör seçilmişse
program o klasörün önceden var olan izinlerini sessizce `0700` yapmaz; yalnız
kendi oluşturduğu alt dizin ve dosyaları özel tutar.

CLI, web ve Qt kapaklı yedekleri aynı kapsamı kullanır: baskının ön/ön-iç/
arka-iç/arka kapak sütunları ile iş hattının `image_asset.managed_path`
görselleri birlikte toplanır. CLI’da özel bir kapak kökü gerekiyorsa:

```bash
.venv/bin/kitapkatalog archive create okul.kitaparsiv \
  --include-covers \
  --asset-root "/mutlak/özel-kapak-kökü"
```

Arşiv manifesti mutlak kaynak yolunu açık metin olarak taşımaz. Arşive özgü
tuz ve her kapak için kaynak-yol parmak izi, geri yüklemede doğru özel kökü
kesin eşlemek için kullanılır. Aynı dosya adına/soneke sahip haricî bir yol
eşleşmez ve staged veritabanında `NULL` yapılır.

## 10f. v0.10.0+ büyük tur: OCR doğruluğu, yabancı dilli sesli kayıt, tam otomasyon

### İçe aktarmada yenilikler

- **Kalite ön-kontrolü:** Tek kitap yüklerken "Önce kaliteyi kontrol et"
  kutusunu işaretlerseniz fotoğraflar kuyruğa alınmadan bulanıklık/ışık
  raporu gelir; uyarı varsa yeniden çekme şansınız olur. Toplu yüklemede
  rapor bilgilendirme amaçlıdır, yükleme durmaz.
- **ZIP arşivi:** Toplu içe aktarmaya `.zip` verebilirsiniz; arşiv içindeki
  klasörler dolap adı sayılır (klasör=dolap). Şifreli/şüpheli üyeler tek tek
  reddedilir ve raporda gerekçesiyle listelenir.
- **cover-v2:** Eğik/parlamalı fotoğraflarda perspektif düzeltme artık çok
  basamaklı; düşük güvenli sayfalarda motorlar kontrast/binarize türevlerini
  de dener. Sürüm yükseltmesinden sonraki İLK işlemede tüm kitaplar yeniden
  OCR'lanır — bu beklenen davranıştır.
- **İnceleme ekranı:** Düşük güvenli kitaplarda artık "neden incelemede"
  çipleri, her alan için motor alternatifleri (tıklayınca forma yazılır) ve
  🔍 ile kanıt kırpıntısı önizlemesi vardır.

### Sesli kayıtta yabancı kitap adları

- Ayarlar → Sesli Kayıt bölümünden tanıma dili (`tr/auto/en`) ve **ikinci
  geçiş** seçilebilir. İkinci geçiş açıkken başlık/yazar bölümleri ayrı dille
  yeniden dinlenir ve form altında öneri çipi olarak görünür — çipe
  tıklamadıkça hiçbir öneri kayda girmez.
- **Düzeltme sözlüğü:** Kayıt sırasında düzelttiğiniz bir değer için
  "sözlüğe ekle?" önerisi çıkar; kabul ederseniz aynı yanlış duyum bir
  sonraki kayıtta otomatik öneriye dönüşür. Sözlük Ayarlar sayfasından
  yönetilir.
- Alan yanındaki 🎤 düğmesiyle yalnız o alanı yeniden söyleyebilirsiniz.

### Dolaşım: rezervasyon, bildirim, af

- **Rezervasyon:** Tüm nüshaları ödünçte olan kitap için kitap detayından
  "Sıraya ekle" kullanılır. Kitap iade edilince sıradaki üye için ayrılır,
  bildirim düşer ve banko ekranı "Ayırma fişi yazdır" önerir. Süresi içinde
  alınmazsa sıradakine devreder. Ayarlardan kapatılabilir
  (`hold_enabled`), bekleme süresi ve üye başına sınır değiştirilebilir.
- **Bildirim merkezi:** Üstteki zil simgesi gecikme, hazır rezervasyon ve
  yedekleme hatalarını toplar.
- **Af:** Üye kartındaki "Af" düğmesi o anki gecikme cezasını gerekçeli
  olarak söndürür; af SONRASI oluşan yeni gecikmeler normal ceza işletir.
  Gerekirse elle yasak da eklenebilir.

### Okuma listeleri ve yarışma

- **Okuma Listeleri** sayfasından liste kurulur, kitap ve üye atanır;
  ilerleme üyenin iade ettiği farklı kitaplardan otomatik hesaplanır.
  "100 Temel Eser" düğmesi katalogla eşleşen başlıkları tek tıkla ekler.
  OPAC'ta görünür yapılan listeler öğrenci ekranında vitrin olur.
- **Okuma Yarışması** sayfasında dönem hedefi tanımlanır; sınıf ligi ve ilk
  10 otomatik güncellenir (aynı kitabı tekrar almak puan saymaz).
  `/print/certificate` ile süslü A4 sertifika basılır.

### Kâğıt çıktılar

- Veli mektubu: `Yazdır` sayfası / `/print/letters` — geciken her üye için
  ayrı sayfada, okul adıyla.
- MEB tarzı demirbaş defteri: `/print/inventory-ledger?year=2026` (yatay A4).
- Yıl sonu istatistik raporu: `/print/annual-report` (dönem verilmezse
  eğitim-öğretim yılı varsayılır).

### Çevrimiçi ISBN önerisi (isteğe bağlı, ayrı komut)

Ana uygulama tamamen çevrimdışı kalır. İnternetten künye önerisi istenirse
uygulama KAPALIYKEN ayrı bir terminalde:

```bash
.venv/bin/kitapkatalog online-oneri            # eksik künyeli kitaplar için
.venv/bin/kitapkatalog online-oneri --isbn 9789750718533
```

Komut yalnız OpenLibrary/Google Books'a çıkabilen özel bir ağ kilidiyle
çalışır; bulduklarını "bekleyen öneri" olarak yazar. Hiçbir alan otomatik
kabul edilmez — öneriler Onay Merkezi'nde görünür, siz onaylarsanız kayda
girer, reddettiğiniz öneri yeniden sorguda geri gelmez.

## 11. Makine-okunur CLI ve hata kodları

`--json` genel seçeneği alt komuttan önce yazılır:

```bash
.venv/bin/kitapkatalog --json jobs
.venv/bin/kitapkatalog \
  --database "/mutlak/yol/catalog.sqlite3" \
  --json search "Anadolu"
```

Başarılı komut `0`, kullanıcı girdisi/model/disk/veritabanı gibi denetimli
hatalar `2` çıkış kodu verir. Hata metni stderr’e yazılır.

## 12. Sorun giderme

### “Beş OCR paketi tamamlanmamış”

`engine-status` çalıştırın. Eksik model, Python paketi, Tesseract/llama
çalıştırılabilir dosyası, hash veya boyut raporda tek tek görünür. Uygulama
eksik dosyayı indirmez; kilitli paketi yeniden hazırlayın.

### Her sonuç incelemeye gidiyor

Bu, `calibration/ensemble.json` yoksa veya geçerli profil kendi
`minimum_samples` eşiğini karşılamıyorsa beklenen güvenli davranıştır. OCR
kaybolmaz. Hash/şema bozukluğu ise inceleme modu değil açık paket hatasıdır.

Bunu açmak için etiketli veriyi elle hazırlamanız gerekmez: incelediğiniz
alanlar zaten etiket üretir. **Kitap Bilgisi İncelemesi** sekmesinin altındaki
panel kaç örnek biriktiğini gösterir; eşik dolunca “Profili Üret ve Otomatik
Kabulü Aç” düğmesi etkinleşir. Komut satırından aynısı:

```bash
.venv/bin/kitapkatalog --json export-calibration-samples ornekler.jsonl
.venv/bin/kitapkatalog fit-calibration ornekler.jsonl \
  ~/Library/Application\ Support/KitapKatalog/calibration/ensemble.json \
  --version "inceleme-v1"
```

Profil devreye girdikten sonra kanıtı güçlü alanlar otomatik kabul edilmeye
başlar; zayıf olanlar yine incelemeye düşer. `kitapkatalog --json evaluate`
o noktada precision/recall/ECE kapılarının nerede durduğunu raporlar.

### Fotoğraflar eşleşmiyor

Dosyaları aynı temel adla `_front/_back` veya `_on/_arka` olarak yeniden
adlandırın. Sıralı eşleştirme açıksa rol etiketi olmayan önerileri
Eşleştirme Onayı sekmesinden inceleyin.

### Kaynak kapak bulunamadı

`--reference` işinde dosya yolu değişmiştir. Kaynağı özgün yoluna döndürün
veya yeni yönetilen-kopya işi oluşturun.

### Bellek sınırı nedeniyle bekliyor

Backpressure hata değildir. Diğer ağır motorun/Qwen’in belleği bırakmasını
bekler. Sert sınırda yeni model işi kabul edilmez; işletim sisteminde başka
yüksek bellekli uygulamaları kapatıp devam edin.

### Kapanıştan sonra öğe hemen başlamıyor

Başka işçinin geçerli lease’i henüz dolmamış olabilir. Bu koruma aynı kitabın
iki kez nihai yazılmasını engeller. Lease süresi dolunca öğe yeniden alınır.

### “Başka/uyumsuz KitapKatalog sunucusu çalışıyor”

v0.7.0 başlatıcısı porttaki sürecin kimliğini güvenle kanıtlayamazsa onu
kapatmaz ve aynı veri dizini için ikinci sunucu açmaz. Açık KitapKatalog
pencerelerini normal yoldan kapatın; gerekirse Etkinlik Monitörü'nde kendi
kullanıcınıza ait eski `kitapkatalog.webapp.server` sürecini denetleyin.
`web_session.json` dosyasını rastgele silmek portu kullanan süreci durdurmaz.

### Yükleme `413` veya `507` ile reddediliyor

`413`, dosya/adet/grup kotalarından birinin aşıldığını; `507`, yazma
sırasında 256 MiB güvenli boş-disk rezervinin korunamadığını bildirir.
Dosyayı/grubu küçültün veya veri diski açın. Hatalı isteği aynı formda
tekrar göndermeden önce arayüzdeki seçimi kontrol edin; yarım `.part` dosyası
uygulama tarafından temizlenir.

### Tam doğruluk/performance sonucu nerede?

Bu kaynak paketinde tam beş-model artifact seti ve 500 çiftlik etiketli gerçek
korpus bulunmaz. Sentetik ölçek ölçümleri OCR doğruluğu/hızı değildir.
[Test ve kabul protokolü](TEST_VE_KABUL_TR.md) gerçek paket ve kör test
gereksinimlerini tanımlar.
