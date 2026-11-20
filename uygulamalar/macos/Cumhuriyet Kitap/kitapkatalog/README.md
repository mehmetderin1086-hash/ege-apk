# KitapKatalog

KitapKatalog, okul kütüphaneleri için Türkçe öncelikli ve çalışma zamanında
tamamen çevrimdışı bir **kütüphane otomasyonu**dur: kitap kaydı (kapak
fotoğrafı OCR, sesli anlatım, barkodlu hızlı giriş), üye yönetimi (e-Okul
listesi + yıl sonu sınıf atlatma), ödünç verme/iade (gecikme kuralları),
envanter sayımı (USB barkod okuyucuyla adet mutabakatı), düşüm defteri (MEB
tutanağı), okuma raporları, OPAC öğrenci arama ekranı ve otomatik
`.kitaparsiv` yedekleme içerir. 10.000+ kitaplık koleksiyonlar için
ölçülmüştür (arama ~2 ms, sayım raporu ~21 ms).

Masaüstünden `KitapKatalog.app` çift tıklamayla açılır: çalışan sunucu varsa
tarayıcıda yeniden kullanılır, yoksa arka planda başlatılır
(`scripts/build_launcher_app.py` ile üretilir). Demirbaş numaraları yıl+sıra
biçiminde otomatik atanır (örn. `2026-000001`).

**v0.9.0**, içe aktarmayı rafın kendisine bağlar: bir parti kitabı doğrudan bir
dolaba aktarabilir ya da klasör başına bir dolap seçerek tek geçişte birden çok
dolabı doldurabilirsiniz. Tek kitap artık dört ayrı yüz yerine dört sayfalık tek
belgeden de alınır ve sayfa sayısı dördün katı olan bir PDF o kadar kitaba
bölünür — bir tarayıcı oturumu tek dosyada taşınır. Bu sürüm ayrıca web
arayüzünden yapılan bütün içe aktarmaları sessizce reddeden bir hatayı düzeltir
(çok parçalı yükleme türü kontrolü); yükleme sonrası kalıcı bir aktarım raporu,
kuyrukta iş iptali/silme ve toplu yeniden deneme eklenir.

**v0.8.0**, okul dolaşım verisini ve sürüm yükseltmesini veri kaybına karşı
sertleştirir. Şema 8; ödünç anındaki üye adı, numarası, sınıfı, türü ve öğretim
yılını değiştirilemez tarihsel anlık görüntü olarak saklar; her ödünç, iade ve
uzatma isteğini benzersiz `request_id` ile append-only olay günlüğüne yazar.
Sunucu yanıtı kaybolsa bile aynı işlem güvenle yeniden oynatılır ve iki kez
uygulanmaz. v7→v8 geçişi canlı veriyi değiştirmeden önce doğrulanmış,
kapakları da içeren `.kitaparsiv` oluşturur; geçiş veya son doğrulama
başarısızsa katalog atomik olarak eski sürüme döner. Web ve Qt formlarında
kaydedilmemiş değişiklik koruması, banko “Son İşlemler” günlüğü, yıl sonunda
açık ödünçlü öğrenciler için çözüm listesi ve rapor veri-kalitesi uyarısı da
bu sürümdedir.

Kayıt tarafında kalıcı SQLite kuyruğu, beş zorunlu OCR motoru, kanıta bağlı
alan çıkarımı, eşleştirme ve bilgi inceleme ekranları ile
XLSX/CSV/JSON/JSONL/Markdown çıktıları vardır.

## Güvenlik ilkeleri

- Tanımlı dört yüzün her biri RapidOCR/PP-OCRv6, Tesseract, EasyOCR, PaddleOCR-VL ve
  Surya’dan geçmeden kitap uzlaştırılmaz.
- Bir motor ilk deneme ve iki yeniden denemeden sonra hâlâ başarısızsa kayıt
  dört motorla sessizce tamamlanmaz; hata kuyruğuna gider.
- Qwen3 OCR yapmaz. Yalnız OCR/barkod kanıtına bağlı görünen metni
  bibliyografik alanlara ayırır.
- Kapakta bulunmayan değer tahmin edilmez; `bilinmiyor` olarak saklanır.
- Türkçe `I/İ/ı/i`, `ç/ğ/ö/ş/ü` karakterleri sadeleştirilmez.
- `models/calibration/ensemble.json` profili hiç yoksa OCR çalışmaya devam
  eder fakat otomatik alan kabulü kapanır; sonuçlar kullanıcı incelemesine
  yönlendirilir. Var olduğu hâlde hash’i/şeması bozuk profil paket hatasıdır.
- Çalışma zamanı ağ erişimi süreç düzeyinde kapalıdır. Uygulama model veya
  metadata indirmez ve telemetri göndermez.
- Yerel web API’sinde `Host` yalnız loopback adlarını kabul eder; tarayıcı
  `Origin` değeri şema+host+port olarak açık sayfanın origin’iyle birebir
  eşleşmelidir. Başka bir localhost portu aynı oturum çerezini kullanamaz.
- Ses, içe aktarma önizlemesi ve dışa aktarım dosyaları yalnız kendi
  yönetilen köklerinden servis edilir; çözülmüş bir sembolik bağ bu köklerin
  dışına çıkıyorsa istek `404` olur. OPAC yalnız yönetilen kapağı görür;
  oturumlu yönetim ekranındaki eski/reference kapak ise ham dosya olarak değil,
  boyut/içerik denetimli JPEG türevi üretilerek veri kökünden sunulur.

## Beş OCR ve barkod

| Motor | Yerel görev |
|---|---|
| RapidOCR + PP-OCRv6 small/medium | Genel Türkçe/İngilizce metin; düşük güvende medium yükseltmesi |
| Tesseract 5 + `tessdata_best tur+eng` | Yoğun arka kapak metni, küçük yazı ve rakamlar |
| EasyOCR 1.7.2 + CRAFT/`latin_g2` | Stilize ve doğal sahne niteliğindeki kapak yazısı |
| PaddleOCR-VL 1.6 | Karmaşık düzen, perspektif ve metin gruplama |
| Surya OCR 2 | Uzun paragraflar ve okuma sırası |

PP-OCRv6 small ve gerekirse medium aynı RapidOCR oyu içinde birleştirilir;
medium ayrı bir altıncı oy değildir. ZXing-C++ barkod okuyucu beş OCR’dan
ayrıdır. ISBN-10/13 kontrol basamakları doğrulanır ve barkod/OCR çelişkileri
incelemeye gönderilir.

## Ölçek ve devam edebilme

Tek işe 10.000 kitap/40.000 yüz eklenebilir. Kuyruk SQLite WAL üzerinde
250 kitaplık dayanıklı parçalarla tutulur; bütün kayıtlar belleğe yüklenmez.
Varsayılan çalışma profili aynı anda iki kitap işçisi kullanır
(`RuntimeLimits.book_workers=2`). Motor semaforları Tesseract’ı en fazla iki,
diğer OCR motorlarını birer örnekle sınırlar. Qwen aşamasında OCR kabulü
geçici olarak durur ve ağır OCR modelleri boşaltılır.

Her motor sonucu tamamlandığı anda kalıcı checkpoint yazılır. Uygulama
kapanırsa yalnız süresi dolan lease geri alınır; değişmemiş görüntü, model ve
yapılandırma için bitmiş OCR aşamaları yeniden çalıştırılmaz.

## Gereksinimler

- Python 3.12
- macOS arm64, Windows x64 veya uyumlu bir Linux geliştirme ortamı
- Uygulama bağımlılıkları
- Hazırlanmış ve hash-kilitli yerel model paketi
- Model paketi ve fotoğraflar için yeterli disk alanı

Model ağırlıkları lisans ve boyutları nedeniyle kaynak arşivine gömülü
değildir. Tam macOS yayını bu paketi taşınabilir `.app` içine gömebilir.
Eksik modelle katalog arama, elle kayıt, inceleme, dışa aktarım ve
yedekleme kullanılabilir; beş-OCR işleme ise eksik pakette fail-closed durur.

## Kaynaktan kurulum

Proje kökünde:

```bash
uv sync \
  --extra ui \
  --extra vision \
  --extra rapidocr \
  --extra easyocr \
  --frozen
```

Geliştirme, test ve yerel paketleme araçları da gerekiyorsa:

```bash
uv sync --all-extras --frozen
```

Kurulum sırasında bağımlılıkların yerel önbellekte veya kurumun izin verdiği
paket kaynağında bulunması gerekir. Uygulamanın çalışma zamanı hiçbir dosya
indirmez.

İlk katalog ve veri dizinlerini oluşturun:

```bash
.venv/bin/kitapkatalog --json init
```

Windows PowerShell karşılığı `.venv\Scripts\kitapkatalog.exe` yoludur.

Test ve statik denetim:

```bash
PYTHONPATH=src .venv/bin/python -m pytest -q
.venv/bin/ruff check .
```

Deterministik kaynak arşivi ve yalnız üzerinde çalışılan platforma ait yerel
uygulama paketi:

```bash
.venv/bin/python scripts/build_release.py source \
  /hedef/KitapKatalog-source-v0.9.0.zip

.venv/bin/python scripts/build_release.py native macos-arm64 \
  /hedef/KitapKatalog-macos-arm64

# Nuitka/PySide deploy yerine doğrulanmış PyInstaller arka ucu:
.venv/bin/python scripts/build_release.py native macos-arm64 \
  /private/tmp/KitapKatalog-macos-arm64 \
  --backend pyinstaller
```

Windows x64 paketi yalnız Windows x64 üzerinde `windows-x64` hedefiyle
üretilir. Build aracı mevcut hedefin üzerine yazmaz ve internetten bağımlılık
indirmez. macOS’ta iCloud Drive/File Provider tarafından yönetilen Documents
ve Desktop klasörleri imza öncesi dosyalara `com.apple.provenance` özniteliğini
yeniden ekleyebilir. Yerel uygulamayı `/private/tmp` veya bulut eşitlemesi
dışındaki bir klasörde derleyip doğrulandıktan sonra ZIP’e koyun.

Yerel paketteki çalışma zamanı bağımlılıklarını model ağırlıklarını yüklemeden
doğrulamak için:

```bash
/private/tmp/KitapKatalog-macos-arm64/dist/KitapKatalog.app/Contents/MacOS/KitapKatalog \
  --runtime-smoke
```

Komut, ağ koruması etkin halde PySide6, OpenCV, ONNX Runtime, RapidOCR,
EasyOCR, Torch/TorchVision, ZXing, HEIF, PDFium, OpenPyXL ve Zstandard’ı paket içinden
yükler; herhangi biri eksikse sıfırdan farklı kodla biter.

## Model paketini bağlama

Tam macOS uygulamasında paket `.app/Contents/Resources` altında otomatik
bulunur. Kaynaktan çalıştırırken model paketini varsayılan veri dizinindeki
`models/` klasörüne koyun veya
mutlak yolu ortam değişkeniyle verin:

```bash
export KITAPKATALOG_MODEL_DIR="/mutlak/yol/KitapKatalog-models"
.venv/bin/kitapkatalog --json engine-status
```

Özel bir veri kökü için:

```bash
export KITAPKATALOG_DATA_DIR="/mutlak/yol/KitapKatalog-Verisi"
```

Windows PowerShell’de `export` yerine
`$env:KITAPKATALOG_MODEL_DIR="C:\...\KitapKatalog-models"` kullanılır.
Model dizilimi, hash kilidi ve platform paketleri
[model paketi kılavuzunda](docs/MODEL_PAKETI_TR.md) açıklanır.

Etiketli, ayrık kalibrasyon örnekleri hazırsa izotonik profil model kaynağına
şöyle üretilir; daha sonra model paketleme aracı bu dosyayı doğrular ve
hash-kilitler:

```bash
.venv/bin/kitapkatalog fit-calibration kalibrasyon.jsonl \
  model-kaynagi/calibration/ensemble.json \
  --version "kalibrasyon-2026-07"
```

## Web arayüzü

Varsayılan arayüz tarayıcıda açılan yerel web uygulamasıdır:

```bash
.venv/bin/kitapkatalog-web            # 8080-8090 aralığında ilk boş portta açılır
scripts/launch_kitapkatalog.command   # aynısı; çalışan sunucu varsa yeni pencere açar
scripts/launch_kitapkatalog.command --qt   # eski PySide masaüstü arayüzü
```

Sunucu yalnız `127.0.0.1`'i dinler; her açılışta rastgele bir oturum anahtarı
üretilir, tarayıcı `/?token=…` bağlantısıyla açılır ve anahtar HttpOnly çereze
yazılır. Token içeren bağlantı günlük veya konsola basılmaz. 0600 izinli,
atomik `web_session.json`; port/token/nonce yanında uygulama sürümü, PID,
başlangıç zamanı ve veri köküne özgü, gizli yol içermeyen `instance_id`
değerini taşır. `/health` aynı `instance_id` ile birlikte `app`, açılışa özgü
`nonce`, uygulama `version` değeri ve gerçek SQLite `schema_version` değerini
döndürür. Böylece farklı veri kökleriyle çalışan iki yerel kurulum birbirinin
sürecini eski/bozuk oturum sanıp sonlandıramaz.
Başlatıcı yalnız `app + nonce + version` tam eşleşirse sunucuyu yeniden
kullanır. Uyuşmayan dinleyiciyi ancak aynı kullanıcıya ait
`kitapkatalog.webapp.server` süreci olduğu `lsof` ve `ps` ile doğrulanırsa
SIGTERM ile kapatıp süreç ve portun kapanmasını bekler; doğrulayamazsa ikinci
sunucu açmak yerine anlaşılır hata verir. Web arayüzü Genel
Bakış, Kütüphane (arama/düzenleme/toplu işlem), İçe Aktarma (sürükle-bırak),
Sesli Kayıt (tarayıcı mikrofonu), Onay Merkezi (eşleştirme + bilgi
incelemesi + kalibrasyon), Dışa Aktarım ve Motor Durumu bölümlerini içerir.
Tarayıcı kaydının mikrofon izni macOS'ta KitapKatalog'a değil kullanılan
tarayıcıya verilir. Uzun işler (5 OCR koşusu, toplu ses, dışa aktarım)
sunucuda tek yuvalı iş olarak koşar ve arayüz iki saniyede bir durum yoklar;
sunucu kapansa bile OCR/ses kuyrukları kalıcı checkpoint'lerinden devam eder.

## v0.10.0+ büyük tur sözleşmeleri (OCR, ses, otomasyon)

- **cover-v2 ön işleme:** perspektif düzeltme artık dört basamaklı bir
  fallback zinciri (ham köşe arama → aydınlatma düzleştirme → minAreaRect
  döndürme → Hough metin deskew); klasik OCR motorları düşük güvenli sayfada
  `canonical → gray_clahe → binarized` varyant merdivenini tırmanır ama
  consensus'a her motor yine TEK oy verir. `PREPROCESSING_VERSION="cover-v2"`
  tüm OCR önbelleğini yeniler; kalibrasyon ≥200 yeni etiketle yeniden
  eğitilmelidir.
- **Türkçe diakritik hakemi:** grafem oylaması ancak birinci ve ikinci seçenek
  yalnız diakritik farkıyla ayrışıp oy marjı ≤1 ise paketli frekans sözlüğüne
  danışır; sözlük hiçbir zaman motorlarca gözlemlenmemiş bir form üretemez ve
  güven değerini yükseltmez.
- **Yükleme ön-kontrolü ve ZIP:** fotoğraflar yükleme anında bulanıklık/ışık
  raporundan geçer (`preflight` bayrağı kuyruğa almadan rapor döndürür); toplu
  aktarma zip arşivi kabul eder (zip-slip/bomba/şifreli üye reddi, cp437 Türkçe
  ad onarımı, zip içi klasör = dolap).
- **Sesli kayıtta yabancı dil:** whisper dili ayarlanabilir (`tr/auto/en`);
  başlık/yazar dilimleri ikinci geçişte ayrı dille yeniden okunur ve yalnız
  ÖNERİ olarak sunulur — transkript kanıt sözleşmesi (`raw_value ==
  text[start:end]`) bozulmaz, öneri ancak kullanıcı onayıyla form üzerinden
  kayda girer. Sesli düzeltme sözlüğü (`voice_alias`) ve katalog-destekli
  öneri çipleri aynı fail-open ilkesiyle çalışır.
- **Rezervasyon defteri:** iade, aynı transaction'da en eski aktif rezervasyonu
  "hazır"a taşır; hazır nüsha yalnız sahibine verilebilir, süresi dolan
  rezervasyon sıradakine devreder. Rezervasyon idempotency'si kendi
  `request_id` sütunundadır; `circulation_event` defterine dokunulmamıştır.
- **Yasak/af:** parasal ceza defteri bilinçli olarak yoktur; gün bazlı ödünç
  yasağı `member_block` kayıtlarıyla (elle blok + af/waiver) yönetilir.
- **Çevrimdışı ilke değişmedi:** ana süreçler (web/GUI/CLI işleme) süreç-geneli
  ağ kilidiyle açılır. Tek istisna ayrı `kitapkatalog online-oneri` sürecidir:
  yalnız OpenLibrary/Google Books'a (80/443) açık allowlist kilidi kurar,
  sonuçları `external_suggestion` tablosuna `pending` yazar; hiçbir alan
  otomatik kabul edilmez, reddedilen öneri yeniden sorguda diriltilmez.
- **Kâğıt kanallar:** veli mektubu (`/print/letters`), ayırma fişi
  (`/print/hold-slip`), MEB tarzı demirbaş defteri (`/print/inventory-ledger`)
  ve yıl sonu istatistik raporu (`/print/annual-report`) — hepsi oturum
  zorunlu, `no-store`, tüm kullanıcı verisi kaçışlanır.

## v0.9.0 dolaba göre içe aktarma sözleşmeleri

- **Partinin ya da klasörün dolabı:** içe aktarma işi (şema 9) bir dolap
  hedefi taşır; o partiden kataloğa giren her kitabın nüshası o dolaba yazılır.
  “Klasör adını dolap say” seçeneğiyle her kitabın dolabı, dosyalarının
  bulunduğu klasörün adı olur — `Kütüphane/Dolap 1/…`, `Kütüphane/Dolap 2/…`
  ağacı tek geçişte birden çok dolabı doldurur. Kayıtlı olmayan bir ad
  verilirse dolap kaydı açılır, böylece Raf Haritası eksik kalmaz. CLI'da
  `--dolap` ve `--klasor-dolap`.
- **Dolap geçmişi bozulmaz:** işin dolabı sonradan değiştirilebilir ama yalnız
  işlenmeye başlamamış kitaplara uygulanır. Kataloğa girmiş kitap eski
  dolabında kalır ve iş özeti onu gerçek `copy.location` değerinden okur; ekran
  rafta olmayan bir kitabı yeni dolapta göstermez.
- **Tek kitap, tek belge:** bir kitap dört ayrı yüz dosyasıyla ya da dört
  sayfalık tek belgeyle alınır (sayfa sırası ön, ön iç, arka iç, arka).
- **Çok kitaplı PDF:** toplu aktarımda sayfa sayısı dördün katı olan PDF o
  kadar kitaba bölünür (tek PDF'te en fazla 400 kitap). Bölme, render'dan önce
  ayrı bir disk kapısından geçer ve iş ayrıntısında kalıcı olarak görünür;
  başka sayfa sayıları sessizce kesilmez, açık gerekçeyle reddedilir.
- **Klasör yüklemesi karışmaz:** tarayıcıdan seçilen klasör yapısı staging'de
  korunur. Ad temizliği kayıplı olduğu için dizin adı kaynağın özetini taşır;
  benzer adlı iki dolabın dosyaları birleşmez, derinlik kırpması en içteki
  (dolabı veren) klasörü korur.
- **Kuyruk yönetimi:** iş iptali, iş silme ve toplu yeniden deneme uçları.
  Silme iki adımlıdır: çalışan iş önce iptal edilir; kataloğa kitap yazmış iş
  hiç silinmez (silinseydi o kitapların OCR kanıtı da giderdi) ve bir işçi
  kitabın içindeyken silinemez. Yeniden deneme iptal edilmiş ya da duraklatılmış
  işi sessizce çalışır hale getirmez, kalan hatalı öğe sayısını bildirir.
- **Kalıcı aktarım raporu:** kaç kitap kuyruğa girdi, hangi dolaba, hangi PDF
  kaça bölündü, hangi dosyalar eşleşmedi ya da reddedildi — geçici bildirim
  yerine ekranda kalan bir kart.
- **Düzeltilen hata:** çok parçalı gövdedeki dosyalar Starlette'in `UploadFile`
  taban sınıfıyla gelir; kod FastAPI'nin alt sınıfına karşı `isinstance`
  kontrolü yaptığı için web arayüzünden yapılan **her** içe aktarma “dosya
  yüklenmedi” diye reddediliyordu. Ret gerekçesini de doğrulayan regresyon
  testleri eklendi.

## v0.8.0 dolaşım, yükseltme ve arayüz sözleşmeleri

- **Yedek zorunlu şema geçişi:** web, CLI ve Qt aynı `open_application`
  girişini kullanır. Mevcut katalog v1–v7 ise süreç önce uygulama-geneli özel
  kilidi alır; `integrity_check`, yabancı anahtarlar, uygulama kimliği ve
  eksiksiz migration dizisini doğrular. Ardından `0600` izinli
  `surum-yukseltme-oncesi-vN-v8-*.kitaparsiv` üretip hash’lerini yeniden
  denetler. Yalnız bundan sonra migration koşar. Şema ve temel tablo sayımları
  son kontrolden geçmezse özel izinli geçici dosya üzerinden atomik geri dönüş
  yapılır; yarım rollback dosyası hata halinde temizlenir.
- **İdempotent banko işlemleri:** web istemcisi ödünç, barkodla iade, satırdan
  iade ve uzatma için bir `request_id` üretir. Şema 8’deki
  `circulation_event` aynı kimliğin istek ve sonucunu değiştirilemez biçimde
  tutar. Aynı kimlik+aynı komut eski sonucu döndürür; aynı kimliği farklı bir
  komutta kullanmak reddedilir. Ağ/5xx hatasında “Aynı işlemi güvenle yeniden
  dene” düğmesi aynı kimliği kullanır. Aynı üye aynı baskının ikinci aktif
  nüshasını alamaz.
- **Tarihsel rapor doğruluğu:** yeni ödünçte üye adı, okul numarası, sınıf,
  tür ve `YYYY-YYYY` öğretim yılı snapshot’ı yazılır ve trigger ile
  değiştirilemez. Sınıf veya üye daha sonra güncellense bile eski dönem raporu
  değişmez. v8 öncesi satırlar geçiş anındaki üye kaydından
  `migration-estimate` olarak doldurulur; Raporlar ekranı ve XLSX “Bilgi”
  sayfası kesin/tahmini adetleri açıkça ayırır.
- **Güvenli yıl sonu:** yeni e-Okul listesinde bulunmayan fakat üzerinde açık
  kitap olan öğrenci pasifleştirilmez. `needs_resolution` listesinde ad,
  numara, sınıf ve açık kitap sayısıyla görünür; güvenli değişiklikler
  uygulandıktan sonra da uyarı ekranda kalır. Kitaplar iade edildikten sonra
  üye ayrıca pasifleştirilebilir.
- **Kaydedilmemiş değişiklik ve banko geri bildirimi:** kitap, üye, hızlı
  kayıt, onay ve ayar formları sayfa değişiminden önce “Kal/Vazgeç” kararı
  ister. Ayarlar yüklenirken form `inert` olur; eski ağ yanıtı yeni ziyareti
  veya kullanıcı düzenlemesini ezemez. Qt kitap ayrıntısı başka satır, sekme
  veya pencere kapanışında aynı kayıp-değişiklik korumasını uygular. Banko
  işlemleri son 30 sonucu kod, üye, zaman ve başarı/hata durumuyla gösterir;
  barkod alanının odağı işlemden sonra korunur.
- **Özel dosya izinleri ve arşiv kapsamı:** uygulamanın oluşturduğu veri
  klasörleri `0700`; SQLite, WAL/SHM, oturum, staging ve arşivler `0600` olur.
  Kullanıcının açıkça verdiği mevcut üst klasörün izinleri değiştirilmez. CLI,
  web ve Qt yedekleri aynı toplayıcıyla dört `edition` kapak sütununu ve
  `image_asset.managed_path` kayıtlarını birlikte alır. Özel `--asset-root`
  yolları arşivde ham mutlak yol yayınlanmadan, tuzlu kaynak-yol parmak iziyle
  kesin eşlenir; haricî aynı-sonekli yol taşınmaz.

## v0.7.0 veri bütünlüğü ve kullanım sözleşmeleri

- **Atomik form işlemleri:** kitap oluşturma/düzenleme, ISBN, yazar, konum ve
  aktif nüsha değişiklikleri önce bütünüyle doğrulanır, sonra tek dış
  transaction içinde yazılır. Aynı istek içindeki katalog çağrıları
  `ContextVar` ile aynı SQLite bağlantısını görür; iç içe çağrılar savepoint
  kullanır. Geç bir hata dahil başarısız istek kısmi kitap bırakmaz.
- **Aktif/düşülmüş nüsha ayrımı:** arayüzdeki `Adet` ve API’deki
  `copy_count`, dolaşımdaki `active` nüsha sayısıdır. Düşülmüş nüsha satırı ve
  `discard_record` denetim izi korunur; adet azaltma bunu silmez. Ayrıntı API’si
  `active_copies`, `discarded_copies` ve `total_copy_records` değerlerini ayrı
  verir. Aktif ödünçteki nüsha da adet azaltmak için silinmez; bu durumda
  ulaşılabilen güvenli adet döner.
- **Sınırlı web yüklemeleri:** görsel/PDF, ses, XLSX ve `.kitaparsiv`
  dosyaları 1 MiB
  parçalarla benzersiz `.part` dosyasına akar; dosya ve grup kotası, en az
  256 MiB boş-disk rezervi, güvenli ad, uzantı ve içerik imzası doğrulanır.
  Başarıda `fsync + os.replace`, hatada staging temizliği uygulanır. Kesin
  kotalar kullanım kılavuzundadır.
- **Şema 7:** başlık/oluşturulma, yayınevi/dil/kategori, inceleme durumu,
  basım yılı, aktif nüsha-konum, eşleştirme incelemesi ve ödünç tarihleri için
  bileşik/kısmi indeksler ekler. İçe aktarma ve ses işi
  başarılı/hatalı/inceleme sayaçları normal geçişlerde bütün öğeleri yeniden
  taramak yerine aynı transaction içinde O(1) delta ile güncellenir; yalnız
  migration veya açık onarım yolu tam uzlaştırma yapar.
- **Duyarlı ve erişilebilir web kabuğu:** 900 px altında açılır yan menü,
  600 px altında tek sütunlu formlar ve yerel yatay tablo kaydırma kullanılır.
  İçeriğe-atla bağlantısı, ARIA tab/dialog/live-region sözleşmeleri, odak
  tuzağı ve geri yükleme, Escape/ok/Home/End klavye davranışı ve
  `prefers-reduced-motion` desteği vardır. Bu sözleşmeler WCAG uygunluğu
  iddiası değil, gerçek klavye/tarayıcı kabulünün otomatik regresyon tabanıdır.
- **Uzun yaşayan sunucu:** otomatik yedek denetimi açılıştan kısa süre sonra
  başlar, ardından saatlik uyanır; mevcut günde-bir/rotasyon politikası ikinci
  yedeği engeller. Yedek, yönetilen kapakları da içerir. Kapanış Event ile
  scheduler’ı uyandırır; takılmış arşiv sürüm yükseltmeyi sonsuza dek
  engellemesin diye bekleme beş saniyeyle sınırlıdır. Atomik hedef yayımlanmaz;
  yarım otomatik-yedek `.part` dosyası sonraki denemede temizlenir.

## Hızlı başlangıç

Fotoğrafları/PDF’leri mümkünse aynı kitap anahtarını ve açık yüz rolünü taşıyacak
biçimde adlandırın:

```text
000001_front.jpg  000001_front_inside.jpg  000001_back_inside.jpg  000001_back.jpg
000002_on.jpg     000002_on_ic.jpg         000002_arka_ic.jpg     000002_arka.jpg
```

Tek kitabı sıralı dört belgeyle veya tek dört sayfalı PDF ile ekleyin:

```bash
.venv/bin/kitapkatalog import-single \
  kitap_on.jpg kitap_on_ic.jpg kitap_arka_ic.jpg kitap_arka.jpg
.venv/bin/kitapkatalog import-single kitap-dort-sayfa.pdf
```

Bir klasörü dört yüzlü toplu modda içe aktarın:

```bash
.venv/bin/kitapkatalog import-bulk "/mutlak/yol/kitap-belgeleri" \
  --name "Temmuz kitapları"
```

Yalnız özgün dosya yoluna başvurmak için `--reference` ekleyin. Bu modda
kaynak fotoğrafları taşımamak, yeniden adlandırmamak ve silmemek gerekir.
İçe aktarma yazılmadan önce model, kopya, türev, OCR kanıtı, veritabanı ve
acil durum payı için kapasite hesaplanır; disk yetersizse iş oluşturulmaz.

Dosya adıyla kesin belirlenemeyen dört-yüzlü kitap kümeleri OCR’a verilmeden önce
onaylanır:

```bash
.venv/bin/kitapkatalog pair-reviews
.venv/bin/kitapkatalog pair-review 42 --approve
# veya:
.venv/bin/kitapkatalog pair-review 42 --reject
```

Beş motor ve Qwen paketi hazırsa kuyruğu çalıştırın:

```bash
.venv/bin/kitapkatalog run
```

Yalnız belirli bir işi çalıştırmak için `run İŞ_KİMLİĞİ` kullanılır. İş
durumu ve yönetim komutları:

```bash
.venv/bin/kitapkatalog jobs
.venv/bin/kitapkatalog job İŞ_KİMLİĞİ
.venv/bin/kitapkatalog pause İŞ_KİMLİĞİ
.venv/bin/kitapkatalog resume İŞ_KİMLİĞİ
.venv/bin/kitapkatalog retry ÖĞE_NUMARASI
```

Masaüstü arayüzünü açmak için:

```bash
.venv/bin/kitapkatalog-gui
# veya:
.venv/bin/kitapkatalog gui
```

Arayüz sekiz sekme içerir: Kütüphane, İçe Aktarma ve Kuyruk, Sesli Kayıt,
Eşleştirme Onayı, Kitap Bilgisi İncelemesi, Dışa Aktarım, 5 OCR Durumu ve
İstatistik.

## Sesli kitap kaydı

Kitaplar fotoğraf yerine sesle de kataloglanabilir: konuşma yerel
whisper.cpp ile yazıya çevrilir, alanlar deterministik Türkçe ayrıştırıcıyla
(gerekirse kanıt-bağlı Qwen yedeğiyle) çıkarılır. Çalışma anı tamamen
çevrimdışıdır; yalnız kurulum sırasında model bir kez indirilir.

Tek seferlik kurulum:

```bash
# 1) Whisper modeli (~550 MB, SHA-256 yan dosyasıyla doğrulanır)
.venv/bin/python scripts/fetch_whisper_model.py
# 2) whisper-server: brew install whisper-cpp  (veya kaynaktan derleyip
#    model dizinindeki whisper/bin/ altına koyun; KITAPKATALOG_WHISPER_SERVER
#    ortam değişkeni de kabul edilir)
```

Konuşma kılavuzu (alan adı + değer; sıra serbesttir):

> "Yeni kitap. ISBN dokuz yedi sekiz, dokuz yedi beş, sıfır yedi, bir sekiz
> beş üç, üç. Başlık Kar. Yazar Orhan Pamuk. Yayınevi İletişim. Yıl iki bin
> iki. Sayfa dört yüz yirmi sekiz. Dil Türkçe. Kategori roman. Üç adet."

- Kitaplar arasında **"yeni kitap"** (veya "sıradaki kitap" / "kitap bitti")
  deyin; ayraç yoksa bölütleme yapılmaz, şüpheli bloklar incelemeye düşer.
- ISBN'i tek tek rakam okuyun; sağlaması geçmeyen ISBN asla yazılmaz,
  kayıt inceleme kuyruğuna düşer (uydurma yok ilkesi).
- Toplu kayıtlarda dosya başına 25-100 kitap önerilir.

Canlı mod (GUI → Sesli Kayıt): **F2** bas-konuş, **Enter** kaydet-ve-sıradaki,
**F4** yeniden söyle, **F6** atla. "Sessizlikte otomatik durdur" + "Hızlı mod"
birlikte eller-serbest zincir kurar; otomatik kaydedilenler güvenlik ağı
olarak inceleme durumunda kalır. Toplu mod telefon kayıtlarını (m4a/mp3/wav)
kuyruğa alır; işleme kalıcı SQLite kuyruğuyla çökme sonrası kaldığı yerden
sürer.

```bash
.venv/bin/kitapkatalog voice add raf1.m4a          # kuyruğa al
.venv/bin/kitapkatalog voice run                   # işle (kesilirse: tekrar run)
.venv/bin/kitapkatalog voice jobs                  # durum
.venv/bin/kitapkatalog voice retry <öğe-no>        # hatalıyı yeniden dene
```

## Arama ve dışa aktarım

```bash
.venv/bin/kitapkatalog search "İstanbul" --publisher "Yapı Kredi"
.venv/bin/kitapkatalog export katalog.xlsx
.venv/bin/kitapkatalog export katalog.csv
.venv/bin/kitapkatalog export katalog.json
.venv/bin/kitapkatalog export katalog.jsonl
.venv/bin/kitapkatalog export KitapKatalog-Notlari --format markdown
```

XLSX dosyası `Özet`, `Kitaplar`, `Katkıda Bulunanlar`,
`Tanımlayıcılar`, `Ayrıntılı Alanlar`, `İnceleme Gerekenler` ve `Hatalar`
sayfalarını içerir. CSV UTF-8 BOM’ludur. JSON tam hiyerarşiyi, JSONL akışlı
büyük veri biçimini, Markdown ise kitap başına ayrı notu destekler. Kapak
görselleri Excel’e gömülmez; yolları yazılır. Formül gibi başlayan hücreler
etkisizleştirilir ve bütün çıktılar önce `.part` olarak yazılıp başarıyla
kapandıktan sonra atomik yayımlanır.

Yerel CSV, JSON, JSONL veya güvenli ONIX XML metadata kataloğu da içe
aktarılabilir:

```bash
.venv/bin/kitapkatalog import-metadata yerel-katalog.jsonl
```

## Yedekleme

Veritabanının WAL-tutarlı anlık görüntüsünü yedekleyin:

```bash
.venv/bin/kitapkatalog archive create KitapKatalog.kitaparsiv
```

Yönetilen kapakları da eklemek için `--include-covers` kullanın. Arşiv
bütünlüğünü kontrol etme ve boş bir klasöre güvenli çıkarma:

```bash
.venv/bin/kitapkatalog archive inspect KitapKatalog.kitaparsiv
.venv/bin/kitapkatalog archive extract KitapKatalog.kitaparsiv \
  "/mutlak/yol/boş-hedef"
```

Çıkarma komutu etkin kataloğu otomatik değiştirmez. Doğrulanan
`catalog/catalog.sqlite3` dosyasını kullanma kararı kullanıcıya bırakılır.

Web geri yükleme hazırlığı v0.8’de yalnız ZIP/hash denetimiyle yetinmez:
SQLite `integrity_check`, `foreign_key_check`, kesin `application_id` ve
`user_version`/`schema_migration` tutarlılığı geçmelidir. Arşivde tekil
karşılığı olmayan mutlak, göreli veya belirsiz kapak yolları yeni kataloğa
taşınmaz; `NULL` yapılır. Yeni arşivlerde özel varlık kökü, ham kaynak yolu
açıklanmadan tuzlu parmak iziyle kesin eşlenir. Başlatıcı açık eski sürümü
güvenle sonlandırmadan şema değişimine geçmez.

## Doğrulama durumu

Kaynak kod; kuyruk, checkpoint/cache, ISBN, uzlaştırma, provenance, yerel
içe/dışa aktarım, arşiv güvenliği, kapasite hesabı ve PySide arayüzü için
otomatik testler içerir. v0.8 için ayrıca yedek-zorunlu şema yükseltmesi ve
rollback, idempotent dolaşım günlüğü/tarihsel snapshot’lar, veri-kalitesi ve
yıl-sonu çözüm sözleşmeleri, özel dosya izinleri ve form kayıp koruması;
v0.7’den devralınan transaction rollback/savepoint,
yükleme kotaları ve staging temizliği, dosya-kökü hapsi, Origin port ayrımı,
session/sürüm yaşam döngüsü, şema 7 sorgu planları/sayaç deltaları ve semantik
responsive/ARIA sözleşmeleri regresyon kapısıdır. Ayrıca gerçek
SQLite/FTS5/dışa aktarım koduyla
10.000/100.000 kayıtlık sentetik ölçek testi yapılmıştır.

Otomatik semantik HTML/JS testleri gerçek tarayıcı kabulü sayılmaz. Yayın
adayı; yalıtılmış veri dizininde gerçek tarayıcıyla klavye+mobil görünüm,
kitap/üye/ödünç/sayım/düşüm, hatalı ve büyük yükleme, yedek geri dönüşü ve
yeniden başlatma akışlarından; macOS paketi ise ayrıca plist sürümü, mimari,
imza, `--runtime-smoke` ve canlı `/health` sürüm/şema kapılarından geçmelidir.
Nihai test sayısı yalnız aynı commit üzerindeki son koşumdan sonra yayın
notuna yazılır.

Bu çalışma alanında lisanslı tam beş-model paketi ve 500 etiketli gerçek kitap
çifti yoktur. Bu nedenle beş motorun birlikte gerçek kapak inference’ı,
`≥60 kitap/saat`, alan precision/CER/ECE ve yedi günlük 10.000 kitap hedefi
tamamlanmış kabul testi olarak sunulmaz. Ayrıntılar
[test ve kabul protokolünde](docs/TEST_VE_KABUL_TR.md) ve
[sentetik ölçek raporunda](docs/SENTETIK_OLCEK_RAPORU_TR.md) bulunur.

## Belgeler

- [Ayrıntılı kullanım kılavuzu](docs/KULLANIM_KILAVUZU_TR.md)
- [Çevrimdışı model paketi](docs/MODEL_PAKETI_TR.md)
- [Mimari ve veri güvenliği](docs/ARCHITECTURE_TR.md)
- [Test ve kabul protokolü](docs/TEST_VE_KABUL_TR.md)
- [Sentetik ölçek raporu](docs/SENTETIK_OLCEK_RAPORU_TR.md)

## Lisans

Uygulama kaynak kodu MIT lisanslıdır. OCR/VLM ağırlıkları, Tesseract
verileri, llama.cpp runtime’ı ve diğer üçüncü taraf bileşenlerin lisansları
ayrıdır. Bir modeli indirme hakkı, onu yeniden dağıtma veya ticari kullanma
hakkı anlamına gelmez; yayın öncesinde kullanılan kesin artifact sürümleri
için lisans envanteri hazırlanmalıdır.
