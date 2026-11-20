# KitapKatalog mimarisi

## Değişmezler

KitapKatalog’un ilk beş kuralı OCR güvenilirliğini, v0.7.0 ve v0.8.0 ile
eklenen kurallar ise web/veri/dolaşım yaşam döngüsünü tanımlar:

1. Bir kapak için RapidOCR/PP-OCRv6, Tesseract, EasyOCR, PaddleOCR-VL ve
   Surya’nın tamamı başarılı olmadan uzlaştırma başlamaz.
2. Motor hatası kayıt düşürmez. İlk deneme ve iki yeniden deneme başarısızsa
   kitap hata kuyruğuna geçer.
3. Kapakta görünmeyen bibliyografik değer üretilmez. Bulunamayan alan
   `bilinmiyor` olarak saklanır.
4. Çalışma zamanında ağdan model veya metadata indirilmez. Giriş noktaları dış
   DNS/TCP bağlantısını süreç düzeyinde engeller; yalnız loopback ve Unix
   soketleri açıktır.
5. Otomatik alanın bir görsel kutusu, en az iki bağımsız motor desteği ve
   kalibre edilmiş en az `0,98` güveni olmalıdır.
6. Bir HTTP isteğinin oluşturduğu bileşik katalog değişikliği tek
   transaction'dır; iç içe servis yazımları savepoint'tir. 4xx veya geç hata
   kısmi eser/baskı/ISBN/nüsha bırakamaz.
7. Kullanıcıya gösterilen `copy_count` yalnız aktif fiziksel nüshadır.
   Düşülmüş `copy` satırı ve `discard_record` denetim izi silinmez.
8. Web'den servis edilen kalıcı dosya, o uca ait izinli kökün çözülmüş
   sınırı içinde olmalıdır; sembolik bağla kök kaçışı da reddedilir.
9. Çalışan web sunucusu ancak uygulama kimliği, açılış nonce'u ve
   paket sürümü birlikte eşleşirse yeniden kullanılır.
10. Eski şema, doğrulanmış ve özel izinli yükseltme-öncesi arşivi atomik
    yayımlanmadan açılamaz/migrate edilemez; son doğrulama hatası eski şemaya
    atomik dönüş üretir.
11. Ödünç, iade ve uzatma komutları istemci `request_id` kimliğiyle
    idempotenttir; olay/istek/sonuç append-only dolaşım günlüğünde yaşar.
12. Tarihsel rapor, canlı üye/sınıf satırını JOIN ederek geçmişi yeniden
    yorumlamaz; ödünç anında yazılmış değiştirilemez snapshot’ı kullanır.
13. Aynı üye aynı baskının en çok bir aktif ödüncüne sahip olabilir; bu kural
    servis doğrulaması yanında SQLite trigger’ıyla da korunur.
14. Uygulamanın yarattığı kişisel veri dosyası ilk bayttan `0600`, kendi veri
    dizini `0700` olmalıdır; özel veritabanı için seçilmiş mevcut üst klasörün
    kullanıcı tarafından belirlenmiş modu değiştirilmez.

## Web güvenliği ve süreç yaşam döngüsü (v0.7.0)

Sunucu yalnız loopback'e bağlanır. `LocalAuthMiddleware`, `Host` değerini
loopback adlarıyla sınırlar; yazan API isteklerinde `Origin`, açık sayfanın
şema+host+port birleşimiyle birebir eşleşir. Aynı makinedeki başka bir
localhost portu, tarayıcı çerezi mevcut olsa bile yetkili origin sayılmaz.

Her açılışta rastgele token ve nonce üretilir. Token yalnız ilk `/?token=…`
isteğinin HttpOnly çereze çevrilmesinde kullanılır; token taşıyan URL konsola
veya günlüğe yazılmaz. `web_session.json` aynı dizinde benzersiz geçici dosya,
`flush + fsync + os.replace` sırasıyla yayımlanır ve izinleri `0600`'dır.
Kayıt `port`, `token`, `nonce`, `version`, `pid` ve `started_at` alanlarını
taşır. Sunucu günlüğü de `umask 077` altında `0600` oluşturulur.

Başlatıcı oturum kaydını okuduktan sonra `/health` yanıtında şu üçlüyü tam
eşleştirir:

```text
app == "kitapkatalog"
nonce == session.nonce
version == çalışan paket sürümü
```

`/health` ayrıca gerçek `PRAGMA user_version` değerini `schema_version`
olarak döndürür. Dinleyici var fakat el sıkışması uyuşmuyorsa başlatıcı
`lsof` ve `ps` ile PID'nin aynı kullanıcıya ait tam
`kitapkatalog.webapp.server` komutu olduğunu kanıtlar; yalnız o zaman SIGTERM
gönderir ve hem sürecin hem portun kapandığını bekler. Kimlik güvenle
kanıtlanamazsa mevcut sürece dokunmaz ve ikinci sunucu açmaz.

Hafif macOS başlatıcısının kurulumu da aynı-disk staging dizininde yapılır.
Paket sürümü, çalıştırılabilir dosya ve kod imzası doğrulandıktan sonra eski
ve yeni paket atomik ad değişiklikleriyle yer değiştirir; başarısızlıkta eski
paket geri alınır. Bu başlatıcı kaynak checkout'u ile `.venv`'e bağlıdır;
native, kendi runtime'ını taşıyan yayın hattı ayrı kalır.

## Şema 8, güvenli yükseltme ve dolaşım defteri (v0.8.0)

`open_application` bütün katalog taşıyan giriş noktalarının tek kapısıdır.
Önce bekleyen restore işi uygulama-geneli özel kilitle değerlendirilir. Mevcut
şema güncelse `Database` açılır ve süreç ömrü boyunca paylaşımlı kilit tutulur.
Eski şema varsa aynı kilit özel kalır ve `upgrade.open_database_safely` şu
sırayı uygular:

```text
salt-okunur mevcut dosya + sahiplik/normal-dosya denetimi
  -> application_id + integrity + FK + migration zinciri
  -> SQLite Backup API + yönetilen kapaklarla .kitaparsiv
  -> ZIP üye/boyut/hash doğrulaması + fsync + atomik yayın
  -> Database migration
  -> beklenen user_version + bütünlük + temel tablo sayımları
  -> başarı: güncel Database aç
     hata: özel O_EXCL rollback kopyası + fsync + atomik replace
```

Rollback hedefi `shutil.copyfile` gibi umask’e bağlı bir adla yaratılmaz;
`os.open(O_CREAT|O_EXCL, 0o600)` ile ilk bayttan özeldir. Kopyalama, fsync veya
replace öncesi hata halinde `finally` yarım hedefi siler. Doğrulanmış
`.kitaparsiv` hata raporunda korunur.

Şema 8, `loan` tablosuna üye adı/numarası/sınıfı/türü, öğretim yılı ve
`snapshot_source` ekler. Yeni satır `checkout`, geçişle doldurulan eski satır
`migration-estimate` kaynağını taşır. Gerekli-alan ve immutable trigger’ları
sonradan sessiz tarih yazımını engeller. Sınıf/top-okur raporları yalnız bu
alanları kullanır; kalite ucu ve XLSX Bilgi sayfası tahmini kayıt sayısını
görünür kılar.

`circulation_event`, benzersiz `request_id`, olay türü, loan/copy/member/
edition kimlikleri, kanonik istek JSON’u, sonuç JSON’u ve zamanları tutar.
UPDATE/DELETE trigger’ları olay defterini append-only yapar. Servis bir
transaction başında aynı kimliği arar:

- olay türü ve kanonik istek aynıysa saklanmış sonucu yeniden kurar;
- kimlik aynı, komut farklıysa `StateConflictError` verir;
- kimlik yeni ise dolaşım mutasyonunu ve olay sonucunu aynı transaction’da
  yazar.

Web istemcisi retryable ağ/5xx hatasında aynı `request_id` closure’ını saklar.
Satır iade/uzatma eylemlerinde loan-id bazlı in-flight haritası iki düğmeyi
senkron olarak disable eder; böylece çift tıklama ikinci UUID üretmeden kesilir.
Yanıt kaybında kilit, aynı kimlikle güvenli tekrar terminal olana dek korunur.

Web süreç kimliği, veri kökünde `0600` yazılan kararlı 128-bit
`web_instance_id` ile genişletilmiştir. Dosya yarışında private geçici hedef +
hard-link yayın ve dizin fsync kullanılır. Oturum kaydı bulunmasa bile sağlık
yanıtındaki farklı instance kimliği başka veri kökünün sağlıklı sunucusunu
sonlandırmayı engeller; kimliksiz eski belirsiz süreçte davranış fail-closed’dur.

## Şema 9, dolap hedefli içe aktarma (v0.9.0)

Şema 9 iki sütun ekler: `import_job.location` partinin, `job_item.location`
tek kitabın dolabıdır. Sütun yoklaması `BEGIN IMMEDIATE` sonrasında yapılır ve
DDL aynı transaction'a katılır; aynı v8 kataloğunu aynı anda açan iki süreç
duplicate-column hatasına düşmez, yarıda kalan geçiş yeniden girilebilir.

Zamanlayıcı kataloglamadan hemen önce `job_item.location or (taze okunan)
import_job.location` değerini `CopyInput.location` olarak geçirir. Öğe alındığı
anda okunan iş nesnesi dakikalarca bayat kalabildiği için iş dolabı ikinci kez
okunur. `set_job_location` değişiklikten önce eski dolabı, kataloglanmış ve
terminal öğelerin üzerine sabitler; iş özeti ise kataloglanmış öğe için
`copy.location` değerini okur. Böylece rafta duran kitap, iş dolabı sonradan
değişse bile yeni dolapta sayılmaz.

Web tarafında klasör yüklemesi `webkitRelativePath` üzerinden gelir. Ad
temizliği kayıplı olduğundan staging dizini kaynağın özetini taşır, dolap adı
ise okunur bileşendir; derinlik kırpması en içteki klasörü korur. Eşleştirme
zaten üst klasöre göre grupladığı için klasör başına kitap ve klasör başına
dolap aynı yapıdan çıkar. Çok kitaplı PDF bölünmesi render'dan önce ayrı bir
disk kapısından geçer: kapasite kapısı iş satırından hemen önce çalıştığı için
yüzlerce sayfanın önden yazılması ayrıca sınırlanır.

## Transaction, yükleme ve dosya sınırları (v0.7.0)

`Database.transaction()` etkin bağlantıyı `ContextVar` içinde tutar. Aynı
iş-birimi içindeki bütün okuma/yazma çağrıları bu bağlantıyı görür; iç içe
transaction bir UUID'li `SAVEPOINT` açar ve hata halinde yalnız o seviyeye
`ROLLBACK TO` yapar. En dış katman gerektiğinde `BEGIN IMMEDIATE` kullanır.
Web kitap ekleme/düzenleme yolları sayısal alan, ISBN ve katkı girdilerini
yazmadan önce dönüştürür; ardından katalog servislerini tek dış transaction
içinde çağırır. Toplu kitap eylemlerinde bu atomiklik seçilen her baskı için
ayrı uygulanır; bir baskının hatası başka baskı için başarı diye gizlenmez.

`webapp/uploads.py` bütün dosya-kabul yollarının ortak staging katmanıdır.
Akış 1 MiB parçalara bölünür; dosya kotası, çoklu istekte ortak `UploadBudget`
ve 256 MiB boş-disk rezervi her parçada denetlenir. Güvenli dosya adı ve
uzantıya ek olarak Pillow ile görsel/piksel sınırı, PDF başlığı, ses kapsayıcı
imzası veya zorunlu XLSX ZIP bileşenleri doğrulanır. Sonuç
`flush + fsync + os.replace` ile atomik yayımlanır; bütün hata yolları `.part`
dosyasını, rota işi başlatılamazsa yayımlanmış staging hedefini de
temizler. Bilinçli olarak tutulan yıl-sonu XLSX önizlemesi yalnız uygula,
iptal veya iki saatlik TTL'ye kadar yaşar. Kapak 40 MiB; içe aktarma
512 MiB/dosya, 2.000 dosya ve 8 GiB/grup; tek ses analizi 100 MiB; toplu ses
200 MiB/dosya, 500 dosya ve 2 GiB/grup; XLSX 50 MiB; geri-yükleme arşivi
8 GiB ile sınırlıdır.

Dosya sunma uçları yolu önce `resolve()` eder. OPAC kapakları `assets`,
eşleştirme önizlemeleri veri kökü, inceleme sesi yönetilen ses kökü, dışa
aktarım indirmeleri `exports` altında kalmak zorundadır. Oturumlu yönetim
ekranı, desteklenen reference-mode/Qt kapak yolunu ham olarak döndürmez:
uzantı, 40 MiB, piksel ve Pillow decode kapılarından geçirip `derivatives`
altında betiksiz JPEG üretir ve yalnız bu türevi sunar. İstemciden gelen ad
`Path.name` ile daraltılsa bile yönetilen dosyalarda son karar çözülmüş kök
sınırıdır; kaçan veya sembolik bağlı yol `404` olur.

## Veri akışı

```text
fotoğraf/PDF keşfi
  -> tekli veya toplu ön/ön iç/arka iç/arka eşleştirme
  -> PDF sayfalarını 300 DPI içerik-adresli PNG'ye dönüştürme
  -> yönetilen kopya veya kaynak referansı
  -> EXIF + perspektif + kanonik/CLAHE türevleri
  -> kapak başına 5 zorunlu OCR checkpointi
  -> ZXing barkod + ISBN kontrol basamağı
  -> konumsal/grapheme düzeyinde ROVER-benzeri uzlaştırma
  -> kanıta bağlı Qwen3 alan sınıflandırması
  -> gözlem + çözülmüş alan + katalog baskısı/kopyası
  -> SQLite FTS5 ve akışlı dışa aktarımlar
```

Ön işleme, kaynak SHA-256, kanonik kırpma SHA-256 ve ters homografiyi saklar.
OCR kutuları kanonik görüntü koordinatındadır. Her kanıt poligonu ters
homografiyle özgün fotoğraf koordinatına taşınır ve kanonik poligonla birlikte
saklanır; inceleme ekranı böylece türev görüntü yerine özgün fotoğraf üzerinde
aynı kanıtı gösterebilir.

Her motorun önbellek anahtarı şu değerlerin kararlı JSON birleşiminin
SHA-256’sıdır:

```text
source_sha256
crop_sha256
preprocessing_version
engine_id
engine/model_digest
config_hash
```

Ham sonuçlar içerik adresli `ocr-raw/aa/<hash>.json.zst` dosyalarına önce
benzersiz `.part` adıyla yazılır, ardından atomik olarak yayımlanır. Bir iş
yeniden alındığında geçerli checkpoint doğrudan okunur; ilgili model tekrar
çalıştırılmaz.

## OCR sözleşmesi

`OcrEngineAdapter` ağır kütüphaneleri modül importunda yüklemez. Her adaptör:

- `availability()` ile paket, çalıştırılabilir dosya ve model varlığını
  yan etkisiz denetler;
- yalnız kanonik tam kapağı alan `recognize()` çağrısıyla tek oy üretir;
- NFC metin, token, güven, poligon, satır/paragraf, model sürümü, süre ve uyarı
  döndürür;
- `recognize_many()` ile birden çok kapağı sırayla okuyabilir — varsayılanı
  tek tek `recognize()` çağırmaktır, yani modeli süreçte tutan motorlar için
  davranış değişmez;
- `release()` çağrısında bellekteki modeli bırakır.

RapidOCR ve EasyOCR yerel model yollarıyla ve indirme kapalı çalışır.
RapidOCR-small her tam kapağı zorunlu işler; düşük güvende hash-kilitli
medium detector+recognizer yükseltmesi çalışır ve iki geçiş tek RapidOCR oyu
olarak birleştirilir. Tesseract yalnız paketlenmiş `tur+eng` tessdata ile
çağrılır. PaddleOCR-VL ve Surya, tek istek alan kısa ömürlü JSON-stdio yan
süreçleridir. Paddle’ın düzen/geometri ve Surya’nın uzun metin/okuma sırası
profilleri ayrıdır; yanıt motor kimliği doğrulanır. Yan süreç yerel
`llama-server` çalıştırır ve tek kapaktan sonra çıkar; böylece iki büyük vision
modeli aynı anda bellekte kalmaz. İsteğe bağlı `llama-mtmd-cli` backend’i de
aynı JSON sözleşmesiyle desteklenir.

Model digest’i yalnız ağırlık hash’inden oluşmaz: RapidOCR eşikleri, Tesseract
dil/PSM ayarı, vision motor profili ve prompt protokolü de digest’e girer.
Paketlenmiş Tesseract ve llama.cpp çalıştırılabilir dosyaları da kilit
manifestinde hash’lenir.

### Kitap başına tek model yüklemesi

İki GGUF motorunun maliyetine model yükleme hâkimdir: yan süreç her çıkarım
için yeni bir `llama-server` açıp 1-2 GB’lık ağırlığı sıfırdan yükleyip
kapanıyordu, yani bir kitabın dört yüzü dört yüklemeye mal oluyordu. Boru
hattı bir kitabı işlemeye başlamadan önce `warm_covers` bloğunu açar:
gruplamadan kazanan motorlar (`batches_model_load`) kitabın bütün yüzlerini
tek istekte okur, sonuçlar olağan sonuç deposuna yazılır ve arkasından gelen
yüz-başına döngü onları orada bulur.

Böylece beş-motor kapısı, checkpoint birimi (yüz × motor) ve sonuç doğrulaması
hiç değişmez. Ön ısıtma tamamen isteğe bağlıdır: başarısız olursa olay akışına
not düşülür ve eski yol kendi yeniden denemeleriyle çalışır. Ön ısıtmayla
üretilen sonuçlar önbellek isabeti sayılmaz; “önceki koşumdan yeniden kullanım”
anlamı korunur.

Yan süreç yine grubun sonunda ölür, dolayısıyla iki büyük vision modeli aynı
anda bellekte kalmaz ve `resources` katmanının karşılıklı dışlama sözleşmesi
aynen geçerlidir. Qwen bariyeri de yalnız ağır motorları boşaltır: hafif
in-process motorların bırakılması Qwen’e yer açmaz, yalnızca bir sonraki
kitapta yeniden yüklenmelerine yol açardı.

## Uzlaştırma ve provenance

Satırlar kutu örtüşmesi, düşey yakınlık, açı ve metin benzerliğiyle
kümelenir. Her motor bir kümede en fazla bir kez oy verir. Farklı token
bölünmeleri Unicode grapheme dizileri üzerinde Needleman-Wunsch hizalamasıyla
eşleştirilir.

`O/0`, `I/1/l`, `S/5`, `B/8` yalnız hizalama adayında benzer sayılır; kazanan
karakter oylamasında birbirine dönüştürülmez. Özellikle Türkçe
`I/İ/ı/i`, `ç/ğ/ö/ş/ü` işaretleri sadeleştirilmez.

Vision motorlarından gelen konumsuz bir sözcük, klasik bir OCR motorunun
konumlu kanıtı olmadan otomatik alan olamaz. `ConsensusSpan` seçilen her
grapheme için motor, kaynak token, kaynak karakter, güven ve görsel kanıt
taşır. Bu zincir `FieldObservation` ve `ResolvedField` tablolarına kadar
korunur.

### Kalibrasyon kapısı

Uzlaştırmanın ham güveni ampirik doğruluk olasılığı sayılmaz. Üretimde
`models/calibration/ensemble.json` yolu, eser/baskı/fotoğraf oturumu ayrık
kalibrasyon kümesinden üretilmiş monoton izotonik profili taşır. Profilin
digest’i pipeline yapılandırma hash’ine girer; profil değişirse eski karar
önbelleği yeni kalibrasyonla karıştırılmaz.

Profil hiç yoksa veya yapısal olarak geçerli olduğu hâlde kendi asgari örnek
eşiğini karşılamıyorsa beş OCR, barkod, uzlaştırma ve kanıta bağlı alan
çıkarımı çalışmaya devam eder. Ancak hiçbir alan `auto` kabul edilmez; sonuç
`review` durumuna gider.

Bu, kataloğu kendi kendini besleyen bir döngüye bağlar: profil olmadan her
alan incelemeye düşer, inceleme kararları da profilin ihtiyaç duyduğu
etiketleri üretir. Kullanıcının bıraktığı değer ile modelin önerdiği değer
`(raw_confidence, correct)` çiftini verir; `export-calibration-samples` bunu
çıkarır, `fit-calibration` profili üretir. Paket kendi profilini beyan
etmiyorsa çalışma zamanı veri kökündeki `calibration/ensemble.json`'a düşer —
model dizini imzalı uygulama paketinin içinde salt-okunurdur. Manifestte tanımlı profilin hash’i/şeması bozuksa
paket bütünlüğü fail-closed hata verir. Güvenilir profil varken de otomatik
kabul için birlikte şu koşullar gerekir:

- kalibre edilmiş güven `>=0,98`;
- en az iki bağımsız motor desteği;
- en az bir kaynak-fotoğraf poligonu;
- vision sözcüğü için konumlu klasik OCR desteği;
- ISBN alanında geçerli kontrol basamağı ve destek kuralı.

ISBN-10 ile dönüştürülebilir ISBN-13 aynı baskı kimliğine kanonikleştirilir.
OCR kaynaklı ISBN için iki bağımsız motor gerekir; uzlaştırma metni ayrıca
üçüncü bir motor oyu sayılmaz. Geçerli barkod kanıtı ayrı kaynaktır. Barkod ve
OCR kümeleri kısmen bile çelişirse alan otomatik seçilmez ve incelemeye gider.

## Kalıcı kuyruk

SQLite WAL üzerinde durum zinciri şöyledir:

```text
discovered -> paired -> preprocessed -> 5_ocr_complete
           -> reconciled -> extracted -> review | completed
```

`job_item_engine` yeni kayıtlarda dört yüzün beşer motor durumunu tutar.
`5_ocr_complete` geçişi, yirmi satırın tamamı `completed` değilse veritabanı
tarafından reddedilir.

Eski iki kapaklı kataloglar geriye dönük okunur; bu kayıtlarda etkin iki yüz
için on checkpoint yeterlidir. Yeni `import-single` ve `import-bulk`
akışlarında dört yüz zorunludur.

İşçiler bir öğeyi süreli lease ile alır ve heartbeat ile uzatır. Uygulama
zorla kapanırsa yalnız süresi dolmuş lease yeniden alınabilir. Tamamlanmış
motor checkpointleri silinmez. Eşleştirmesi belirsiz öğeler kullanıcı
onayından önce claim edilemez.

Kuyruk 250 kitaplık transaction parçalarıyla beslenir; işçiler bu parçadan
öğeleri lease ile tek tek alır ve 10.000 kaydı belleğe yüklemez.
`RuntimeLimits.microbatch_pairs=8` işçi havuzu için üst güvenlik sınırı,
`RuntimeLimits.book_workers=2` ise varsayılan gerçek paralelliktir. Pipeline
callback bağlamı işçi thread’ine özeldir; bir kitabın checkpoint/provenance
olayı diğer kitabın veritabanı satırına yazılamaz.

M4/16 GB kaynak kapıları:

- ön işleme: en fazla 2;
- Tesseract: en fazla 2;
- RapidOCR: 1;
- EasyOCR: 1;
- PaddleOCR-VL: 1;
- Surya: 1;
- Qwen: 1.

Her OCR çağrısı kendi motor semaforunu ve bellek kabul kapısını alır. Qwen
aşamasına geçecek işçi önce bütün OCR semafor izinlerini deterministik sırada
geçici olarak alır; bu sırada yeni OCR inference’ı başlayamaz. Devam eden OCR
çağrıları bittikten sonra registry bütün OCR modellerini serbest bırakır ve
Qwen ortak ağır-model kilidi altında çalışır. Qwen çıkınca semaforlar açılır.
Bu bariyer iki kitap işçisi olsa bile vision OCR ile Qwen’in aynı anda bellekte
kalmasını önler.

Ana süreç ve bütün çocukların RSS toplamı 10 GiB’da backpressure uygular;
12 GiB sert sınırı yeni model kabulünü durdurur.

## Katalog katmanları

- `work`: baskılardan bağımsız eser;
- `edition`: kapaktan tanımlanan yayımlanmış baskı;
- `copy`: kullanıcının fiziksel kopyası;
- `contributor` ve `edition_contributor`: kişi ve rol;
- `identifier`: ISBN-10/13 ve diğer tanımlayıcılar;
- `image_asset`: kaynak/yönetilen kapak ve geometri;
- `ocr_engine_run`: tekrarlanabilir motor sonucu;
- `consensus_span`: birleştirilmiş metin ve kaynak bağlantıları;
- `field_observation`: çıkarılmış alan adayı;
- `resolved_field`: otomatik, inceleme veya kullanıcı onaylı seçim;
- `import_job`, `job_item`, `job_item_engine`: devam edebilir iş kuyruğu.

Kanıt sözleşmesi başlık, alt/özgün başlık, yazar, çevirmen, editör, derleyen,
çizer, önsöz yazarı ve diğer katkılar; yayınevi/imprint; seri/cilt; basım
yeri/tarihi, baskı/basım numarası, matbaa; dil, cilt türü, sayfa, boyut, basılı
fiyat/para birimi; tanıtım, ödül ve alıntılar ile kapakta görünen eşlenmemiş
iddiaları kapsar. ISBN-10/13 ve diğer barkod/tanımlayıcılar ayrı `identifier`
kayıtlarıdır. Model yalnız izin listesindeki alanları döndürebilir.

FTS5 başlık, alt/özgün başlık, katkıda bulunanlar, yayınevi, ISBN, tanıtım ve
ham OCR metnini `unicode61 remove_diacritics 0` ile indeksler. Kullanıcı
kilitli bir çözülmüş alanı daha sonraki OCR çalışması değiştiremez.

### Kütüphane otomasyonu katmanı (şema v5-v7)

v5 tabloları: `member`, `loan` (aktif ödünçte kısmi UNIQUE + silme trigger'ı,
başlık/demirbaş anlık görüntüleri), `stocktake_session/scan`, `discard_record`,
`app_setting`, `inventory_sequence`. v6 eklemeleri: `shelf` (raf haritası —
ad `copy.location` serbest metniyle TAM eşleşir, sözde-FK'dır; harita hücresi
kısmi UNIQUE, ad/koordinat/kapasite CHECK'leri) ile `idx_copy_location` ve
`idx_loan_edition` (popülerlik sıralaması + kitap geçmişi) indeksleri.
Migration mevcut konum metinlerinden shelf kaydı ÜRETMEZ: yazım hatalı
değerler kalıcı varlığa dönüşmesin diye eşleştirme kütüphaneciye bırakılır
(haritadaki "eşleşmemiş" paneli + `adopt`). Shelf silinince konum metinleri
korunur; ad değişince `copy.location` aynı transaction'da taşınır.

v7 migration'ı arama ve rapor sorgularının gerçek süzme/sıralama biçimine
uygun şu indeksleri ekler:

- `idx_edition_title_nocase`, `idx_edition_created_id`;
- yayınevi, dil ve kategori için `UNICODE_NOCASE + title + id` bileşik
  indeksleri;
- `idx_edition_review_title` ve geçerli dört haneli başlangıca uygulanan
  kısmi/ifade `idx_edition_publication_year`;
- `idx_copy_edition_status_location` ve `idx_job_item_pair_review`;
- bütün ödünç tarihleri için `idx_loan_loaned_at`, yalnız iade edilmiş
  satırlar için kısmi `idx_loan_returned_at`.

Migration bir defa `import_job` ve `voice_job` toplam/başarılı/hatalı/
inceleme sayaçlarını gerçek öğelerden uzlaştırır. Sonraki olağan
durum geçişleri eski/yeni aşama farkını aynı transaction'da O(1) delta
olarak yazar; bütün öğeleri tarayan `reconcile_*_job_counts` yalnız açık
onarım yoludur.

Katalog listesi ve araması önce yalnız sıralanmış baskı kimliklerini
sayfalar, sonra sayfanın dar baskı sütunlarını ve katkı/tanımlayıcı/nüsha
ilişkilerini toplu sorgularla getirir. Liste sorgusunda `raw_ocr_text` yerine
`NULL` seçilir; bu büyük gövde yalnız tek kitap ayrıntısında okunur. Boş
sorgulu üye ve ödünç listeleri de `COUNT + LIMIT/OFFSET` ile SQL'de
sayfalanır.

Fiziksel nüsha durumunun API anlamı v7'de açıktır: `copy_count` ve konum
toplamları yalnız `copy.status = 'active'` satırlarını kapsar. Ayrıntı
seri hale getiricisi `active_copies`, `discarded_copies` ve
`total_copy_records` sayılarını ayrı verir. `set_copy_count` azaltırken
düşülmüş satıra dokunmaz ve açık ödüncü olan aktif nüshayı silmez;
hedefe inemiyorsa gerçekten ulaşılan aktif sayıyı döndürür.

Serbest barkod çözümleme TEK yerde yaşar: `codes.py::resolve_catalog_code`
(önce demirbaş tam eşleşmesi, sonra 10/13 hane ISBN — yıl+sıra kodları rakam
ayıklanınca ISBN'e benzediği için sıra önemlidir). `loans.py`, `stocktake.py`
ve JS `scanner.js` bu sözleşmeye uyar. Code128 üretimi `barcode128.py`'de
bağımlılıksızdır (set B+C, checksum); doğruluğu teste gömülü bağımsız
çözücüyle gidiş-dönüş olarak doğrulanır. `/print/*` HTML sayfaları öneksiz
router'dadır ve oturum ister (güvenlik muafiyeti yalnız `/opac` + `/static`).

Bilinen borç: `Members.search` ve `Loans.list_loans`, **yalnız serbest metin
sorgusu doluyken** Türkçe İ/I katlaması için filtrelenmiş aday satırları
Python tarafına alır. Sorgusuz olağan listeler SQL'de sayfalanır. Okul
ölçeğinde (≲2 bin üye, yılda birkaç bin ödünç) bu aramalı yol kabul
edilebilir; ölçek büyürse Türkçe katlamayı koruyan ayrı arama indeksi ilk
iyileştirme adayıdır.

## Sesli kayıt katmanı

Fotoğraf yolunun yanında ikinci ve bağımsız bir giriş yolu vardır: konuşmadan
katalog kaydı. Altı modül (`audio.py`, `whisper_runtime.py`,
`voice_protocol.py`, `voice_extractor.py`, `voice_controller.py`,
`voice_scheduler.py`) OCR boru hattına hiç dokunmadan aynı `Catalog` API'sine
yazar.

Akış: `audio.py` girdiyi kanonik WAV'a çevirir ve örnek-hassas dilimler →
`whisper_runtime.py` yerel whisper.cpp sunucusuna Türkçe transkripsiyon
yaptırır → `voice_protocol.py` transkripti alan/değer çiftlerine ayırır
(Türkçe katlamalı anahtar kelime eşleşmesi, en uzun anahtar önce; sayı ve
ISBN birleştirme) → `voice_extractor.py` kural katmanının çözemediği yerde
kanıt-bağlı Qwen yedeğine düşer → `catalog.save_book()`.

Değişmezler OCR yolundakiyle aynı kalır: söylenmeyen alan tahmin edilmez,
Türkçe `I/İ/ı/i` ayrımı korunur, çalışma anı ağ erişimi kapalıdır. Transkript
kaydın kanıtı olarak saklanır ve inceleme ekranında dinlenebilir.

`voice_scheduler.py`, `scheduler.py`'deki dayanıklı kuyruğun ses karşılığıdır:
aynı lease/heartbeat ve checkpoint deseniyle iki fazlı çalışır, duraklatılabilir
ve çökme sonrası kaldığı yerden sürer. İki kuyruk ayrı tablolarda tutulur
(`voice_item`), ağır model kilidi (`resources.py`) ikisi arasında ortaktır.

## Web arayüzü: duyarlılık ve erişilebilirlik (v0.7.0)

Ana kabuk masaüstünde sabit gezinme kullanır; 900 px ve altında menü
butonu, overlay ve odak döngüsü olan bir çekmeceye döner. 600 px ve altında
form/grid bileşenleri tek sütundur. Geniş veri tabloları sayfanın kendisini
taşırmak yerine etiketli, odaklanabilir `table-wrap` içinde yatay kayar.

HTML semantiği ve `ui.js` birlikte şu klavye sözleşmelerini uygular:

- içeriğe-atla bağlantısı ve sayfa değişiminde ana içeriğe odak;
- `tablist/tab/tabpanel`, `dialog`, `status`/`aria-live` ve açık etiketler;
- dialog/çekmecede Tab odak tuzağı, `Escape` ile kapanış ve açan elemana
  odak geri yüklemesi;
- sekmelerde ok tuşları ile dolaşım, `Home`/`End`; satır/kart eylemlerinde
  Enter ve Space;
- `prefers-reduced-motion: reduce` durumunda geçiş/animasyonları kapatma.

Arama/listelerde her yeni istek öncekinin `AbortController`'ını iptal eder ve
yalnız en son istek arayüzü güncelleyebilir. Periyodik yenileme görünmeyen
sayfa/sekmede ve aynı iş zaten sürerken atlanır; böylece uzun açık oturumda
yarışan yanıt ve gereksiz çizim azaltılır.

Bu nitelikler `test_web_ui_contract.py` içindeki statik/semantik regresyon
kapılarıyla korunur. Bu testler bir tarayıcı motoru çalıştırmaz; gerçek
mobil viewport, klavye odağı, dialog davranışı ve uçtan uca iş akışı yayın
kabulünde ayrıca denenir.

## Dışa aktarım ve yedek

Her dışa aktarım varsayılan olarak `review` veya `completed` aşamasına gelmiş
baskıları, tek bir SQLite anlık görüntüsünden okur. XLSX write-only, CSV UTF-8
BOM, JSONL satır akışlıdır; Markdown kitap başına ayrı not üretebilir. Formül
benzeri hücre değerlerinin başına tek tırnak eklenir. Bütün dosya biçimleri
`.part` başarıyla kapandıktan sonra hedef adına taşınır.

`.kitaparsiv`, SQLite backup API ile alınmış WAL-tutarlı veritabanını, sürümlü
manifesti ve isteğe bağlı yönetilen kapakları içerir. Her üyenin SHA-256’sı
doğrulanır; mutlak yol, `..`, ters eğik çizgili yol ve özel dosya türleri
çıkarılmadan önce reddedilir.

Web sunucusundaki `AutoBackup` ilk denetimi kısa bir açılış gecikmesinden
sonra yapar, ardından saatlik uyanır. Günde-bir ve son-N rotasyon kararı
`run_if_due()` içinde kalır. Arşiv, `edition` kapak sütunlarına ek olarak
`image_asset.managed_path` altındaki ve `assets` kökü içinde doğrulanan
yönetilen görselleri de taşır. Sunucu kapanırken scheduler Event ile
uyandırılır; `join` beş saniyeyle sınırlıdır ki takılmış bir disk/arşiv
sürüm el sıkışmasını sonsuza dek kilitlemesin. Tamamlanmayan arşiv atomik
hedefe geçmez; süreçten kalan adı kesin sınırlı `.part` sonraki yedekte silinir.

### Geri yükleme (restore.py, v0.6.0 temel; v0.7/v0.8 sertleştirme)

Üç aşamalıdır ve DEĞİŞİM her zaman uygulama açılışında, veritabanı açılmadan
önce olur (`open_application` kancası — web/CLI/Qt ortak yol):

1. **Hazırlık** (`stage_archive`): 8 GiB yükleme/açılmış boyut,
   20.000 ZIP üyesi ve çıkarma için disk alanı sınırı; hash-doğrulamalı
   güvenli çıkarım; staged DB'de desteklenen `user_version`, **kesin**
   KitapKatalog `application_id`, tam `integrity_check`, `foreign_key_check`
   ve `schema_migration == 1..user_version` tutarlılığı; son olarak sayım
   özeti. Bağlantı `UNICODE_NOCASE` collation'ını kaydeder; bu nedenle
   ifade/indeks kullanan geçerli katalog yanlış bozukluk hatası almaz.
2. **Onay** (`confirm_restore`): staged DB güncel şemaya MİGRATE edilir
   (başarısızlık değişimden önce yakalanır) ve aynı bütünlük kapıları
   güncel şemada yeniden çalıştırılır. Yeni arşivlerde kapak yolu, manifestte
   mutlak yol açıklamayan arşive-özgü tuzlu kaynak-yol parmak iziyle tam
   eşlenir; böylece özel `--asset-root` desteklenirken aynı sonekli haricî yol
   yakalanmaz. Eski arşivler yalnız kanıtlanabilir `assets/<göreli>` güvenli
   sonek uyumluluğunu kullanır. Eşleşen kapaklar çakışmasız
   `assets/geri-yukleme-<id>/` alanına yazılır; karşılığı olmayan veya belirsiz
   yol `NULL` olur. DB içine `restore_id` gömülür, WAL→DELETE ile temiz
   kapatılır; işaret (`geri-yukleme/bekleyen.json`) atomik+fsync yazılır.
3. **Değişim** (`apply_pending_restore`): eşzamanlılık SQLite kilidiyle
   değil UYGULAMA-GENELİ dosya kilidiyle (`uygulama.lock`) çözülür — normal
   süreçler ömür boyu paylaşımlı kilit tutar, değişim özel kilit ister;
   alınamazsa işaret beklemede kalır (hata değildir). Sıra: restore_id
   idempotans denetimi (DB içinden — WAL’a duyarlı dosya hash’i değil) →
   staged sha256 → canlı DB’nin Backup API kopyası (`onceki-catalog-*`) +
   kapaklı güvenlik arşivi (`yedekler/geri-yukleme-oncesi-*`) → kapaklar
   tek dizin rename’iyle ad alanına → TEK atomik `os.replace` → temizlik.
   Hiçbir çökme penceresinde "veritabanı yok" anı oluşmaz; yarım kalan koşum
   idempotan yeniden başlar, hatalı işaret `basarisiz-*`’e taşınır ve
   uygulama MEVCUT veriyle normal açılır.

## Bu kaynak ağacının doğrulama sınırı

Mimari, kuyruk ve güvenlik değişmezleri otomatik testlerle; 10.000 dört-yüzlü
iş öğesi/40.000 yüz,
100.000 FTS kaydı ve 10.000 kayıt dışa aktarımı gerçek SQLite/dışa aktarım
koduyla sentetik olarak sınanır. v0.8 responsive/ARIA/JavaScript, dolaşım
idempotency ve kayıp-değişiklik sözleşmeleri semantik regresyon testlerine
sahiptir; bunlar gerçek tarayıcı layout/odak
kabulü veya native `.app` çalışma kanıtı değildir. Ayrıca bu çalışma
alanında tam beş-model paketi ve 500 etiketli gerçek kitap çifti bulunmaz.
Dolayısıyla beşli gerçek inference, saha doğruluğu, kalibrasyon ECE’si ve
M4 üzerindeki kitap/saat hedefleri bu belgeyle geçmiş ilan edilmez.
