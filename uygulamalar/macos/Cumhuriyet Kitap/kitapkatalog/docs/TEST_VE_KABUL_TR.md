# Test ve kabul protokolü

## Etiketli veri

En az 500 gerçek dört-yüzlü kitap kümesi aşağıdaki düzeylerde etiketlenir:

- özgün fotoğrafta metin poligonları;
- satır ve okuma sırası;
- birebir görünen metin;
- başlık, yazar, çevirmen, yayınevi, baskı ve ISBN gibi alanlar;
- barkod okunabilirliği;
- parlama, perspektif, bulanıklık, küçük yazı ve stilize yazı etiketleri.

Aynı eser, baskı ve fotoğraf oturumu tek bir `group_key` alır.
`deterministic_split()` bu grubu `%60 eğitim`, `%20 kalibrasyon`,
`%20 kör test` bölümlerinden yalnız birine koyar. Kör test değeri ayar veya
prompt seçmek için kullanılmaz.

Kalibrasyon profilinin üretim yolu
`models/calibration/ensemble.json` dosyasıdır. Profil yalnız kalibrasyon
bölümünden üretilir; kör test sonuçlarından fit edilmez. Profil bulunmazsa
veya kendi asgari örnek sayısını karşılamazsa test sistemi OCR sonuçlarını
değerlendirebilir, ancak üretim pipeline’ı hiçbir alanı otomatik kabul etmez.

Etiketli örnek dosyası `raw_confidence`/`confidence` ve boolean `correct`
alanlarıyla `fit-calibration` komutuna verilir:

```bash
.venv/bin/kitapkatalog fit-calibration kalibrasyon.jsonl \
  model-kaynagi/calibration/ensemble.json \
  --version "calibration-v1" \
  --minimum-samples 200
```

Komut sonucu model paketi oluşturulurken `optional_artifacts` altında
hash-kilitlenir. Profil digest’i, veri bölümü kimliği ve örnek sayısı kabul
raporuna yazılır.

### Kataloğun kendi incelemelerinden profil üretme

Etiketli örnek dosyasını elle hazırlamak zorunlu değildir. Kullanıcının
inceleme ekranında bıraktığı değer ile modelin önerdiği değer, kalibrasyonun
istediği `(raw_confidence, correct)` çiftinin ta kendisidir. Bu eşleşme
`resolved_field` (yalnız `user_locked = 1`) ile `field_observation` arasında
`(edition_id, field_path)` üzerinden kurulur; kullanıcı düzenlemesi
`observation_id`'yi boşalttığı için bağ o sütundan kurulamaz.

```bash
.venv/bin/kitapkatalog export-calibration-samples ornekler.jsonl
.venv/bin/kitapkatalog fit-calibration ornekler.jsonl \
  ~/Library/Application\ Support/KitapKatalog/calibration/ensemble.json \
  --version "inceleme-v1"
```

Aynı işi arayüzden de yapabilirsiniz: **Kitap Bilgisi İncelemesi** sekmesindeki
panel kaç örnek biriktiğini gösterir ve eşik dolunca profili üretir.

Böyle üretilen profil model paketinin içine değil, veri kökündeki
`calibration/ensemble.json` dosyasına yazılır: model paketi imzalı `.app`
içinde salt-okunurdur ve yerel profilin paket hash kilidine karşı
doğrulanacak bir şeyi yoktur. Paket kendi profilini beyan ediyorsa o
önceliklidir.

Karşılaştırma NFC + kırpma ile yapılır, **büyük/küçük harf katlanmaz**:
Türkçe `I/İ/ı/i` ayrımı bu kataloğun saklamayı reddettiği hata sınıfıdır,
katlamak gerçek bir hatayı doğru okuma diye etiketlerdi.

## Ölçüler

`kitapkatalog.evaluation` şu ölçüleri referans uygulama olarak hesaplar:

- Unicode/NFC karakter hata oranı (CER);
- otomatik alan precision;
- otomatik alanlarda görsel provenance kapsamı;
- güven kalibrasyonu ECE;
- Türkçe ayırt edici karakter hata sayısı;
- okunabilir barkod ISBN recall ve yanlış pozitif;
- en iyi tek motor ile ensemble göreli CER iyileşmesi.

Kabul kapıları:

```text
temel otomatik alan precision   >= 0.99
provenance kapsamı              = 1.00
ECE                             <= 0.03
okunabilir barkod ISBN recall   >= 0.99
otomatik ISBN yanlış pozitif    = 0
ensemble göreli CER iyileşmesi  >= 0.15
```

Her motorun beşli ablation raporu ayrıca tutulur. Bir bağlamda kalibre edilmiş
ağırlığı sıfıra yaklaşan motor yine bütün kapaklarda çalıştırılır; ablation
hiçbir zaman üretimde motor atlama gerekçesi değildir.

## Dayanıklılık

Aşağıdaki testler sürüm kapısıdır:

1. 10.000 kitap/40.000 görsel tek işe 250’lik transaction parçalarıyla eklenir.
2. Her motor sonucundan sonra süreç öldürülür; yeniden açılışta bitmiş motor
   çağrı sayısı sıfır kalır.
3. Lease sahibi süreç kaybolur; süre dolmadan başka işçi öğeyi alamaz, sonra
   alabilir.
4. Bir motor ilk deneme + iki yeniden denemede hata verir; kayıt dört motorla
   uzlaştırılmaz.
5. Yirmi OCR checkpointinden biri eksikken veritabanı `5_ocr_complete` geçişini
   reddeder.
6. Aynı kaynak/config/model yeniden işlendiğinde sonuç aynı olur ve OCR
   adaptörüne çağrı yapılmaz.
7. Yarım XLSX/CSV/JSON yazımı hedef dosyayı değiştirmez ve `.part` temizlenir.
8. Bozuk JPEG/HEIC, bozuk zstd, bozuk arşiv, hash uyuşmazlığı ve yetersiz disk
   açık hata verir.
9. Ağ soketi ve DNS engellenmiş ortamda model yöneticisi yalnız yerel
   artifact’larla hazır olur.
10. 100.000 baskıda FTS arama, filtreleme ve sayfalama ölçülür.

### v0.7.0 veri, yükleme ve yaşam döngüsü regresyonları

Aşağıdaki maddeler v0.7.0 yayınının ek otomatik kapılarıdır:

Bu liste beklenen regresyon davranışını tanımlar; bir maddenin burada yer
alması herhangi bir yayın adayında “geçti” anlamına gelmez. Sonuç ancak aynı
commit'teki koşum kaydıyla raporlanır.

1. Kitap oluşturma/güncellemede erken 4xx ve son servis çağrısına enjekte
   edilen hata sonrası eser, baskı, ISBN, yazar, konum veya nüsha kalmaz.
   İç içe transaction aynı bağlantıyı kullanır; yakalanan iç hata yalnız
   savepoint'i, dış hata bütün iş-birimini geri alır.
2. Kapak, fotoğraf/PDF, ses, XLSX ve geri-yükleme yüzeylerinde uzantı-
   içerik uyuşmazlığı, dosya/adet/grup kotası ve disk rezervi denenir.
   `413`/`507` veya içerik hatasından sonra yayımlanmış hedef, `.part`
   ya da kişisel ses staging'i kalmaz; XLSX önizleme iptali dosyayı siler.
3. Yönetim/OPAC kapağı, eşleştirme görseli, inceleme sesi ve dışa
   aktarım indirmesi için izinli kök dışı gerçek yol ve sembolik bağ
   kaçışı `404` verir.
4. `Origin` aynı şema+host+port için kabul edilir; farklı port, farklı şema,
   haricî origin ve loopback olmayan `Host` reddedilir.
5. `web_session.json` atomik, `0600` ve tüm alanlarıyla yazılır; eşleşen
   oturum token yazdırmadan yeniden kullanılır. Boş porttaki eski kayıt
   temizlenir; sürüm uyuşmazlığı yalnız doğrulanmış aynı-kullanıcı
   sunucusunu sonlandırır; doğrulanamayan dinleyici ikinci sunucuyu engeller.
6. `/health` çalışan paket sürümünü ve gerçek `PRAGMA user_version`
   değerini döndürür. Otomatik yedek scheduler'ı gecikmeli ve tekrar eden
   denetim yapar; kapanış Event'iyle temiz sonlanır. Takılmış yedek için
   bekleme sınırlıdır ve adı kesin otomatik-yedek `.part` kalıntısı sonraki
   koşumda temizlenir.
7. Geri yükleme; yabancı anahtar bozukluğu, yanlış `application_id`, eksik/
   fazla `schema_migration` ve `user_version` tutarsızlığını değişimden
   önce reddeder. Arşiv üyesi olmayan mutlak kapak yolu onayda `NULL` olur.
8. Şema 7'de beklenen indeks adları ve kritik `EXPLAIN QUERY PLAN` sonuçları
   sabittir. Liste/arama ham OCR sütununu okumaz; tek kitap ayrıntısı okur.
   İçe aktarma/ses terminal sayaçları review/retry/cancel geçişlerinde tam
   uzlaştırma çağırmadan delta ile değişir; açık reconcile bozuk sayacı
   onarır ve v6→v7 migration'ı bir defa uzlaştırır.
9. Aktif/düşülmüş nüsha sayıları API'de ayrıdır. `set_copy_count`,
   düşülmüş `copy` ile `discard_record` satırını ve aktif ödünçteki
   nüshayı korur; azaltma sonucu ulaşılabilen aktif sayıyla aynıdır.
10. Semantik web sözleşmesi; geçerli ARIA hedefleri, mobil breakpoint'ler,
    yerel tablo kaydırma, dialog odak/Escape, sekme ok/Home/End tuşları,
    canlı bölgeler, latest-wins `AbortController`, görünürlük/busy kapıları
    ve statik JavaScript parse kontrolüyle korunur.

### v0.8.0 yükseltme, dolaşım ve veri-kaybı regresyonları

Aşağıdaki kapılar v0.7 sözleşmelerine eklenir; eski kapılar kaldırılmaz:

1. Gerçek v7 katalog web, CLI ve Qt girişlerinden açıldığında migration’dan
   önce tek bir `surum-yukseltme-oncesi-v7-v8-*` arşivi oluşur. Arşiv
   `0600`, üye kümesi manifestle birebir, SQLite/hash doğrulaması başarılı ve
   yönetilen kapak kapsamı eksiksiz olmalıdır. Yedek üretimi enjekte edilen
   hatada migration çağrılmamalıdır.
2. Migration veya son doğrulama hatasında temel tablo sayımlarıyla birlikte
   v7 dosyası atomik geri gelmelidir. Rollback geçici hedefi ilk bayttan
   `O_EXCL + 0600` olmalı; ENOSPC/I/O fault injection sonrası `.rollback-*`
   kalmamalı ve canlı dosya değişmemelidir.
3. Şema 8 migration’ı v4/v5/v6/v7 örneklerinden ve yarıda kalmış v8
   durumundan tekrar çalıştırılabilir olmalıdır. `schema_migration=1..8`,
   `user_version=8`, `integrity_check=ok` ve boş `foreign_key_check`
   birlikte doğrulanır.
4. Ödünç, barkodla iade, satırdan iade ve uzatma aynı `request_id` ile tekrar
   çağrıldığında aynı sonucu döndürmeli; `loan`, `renewal_count` ve
   `circulation_event` bir kez değişmelidir. Aynı kimliği farklı parametre
   veya olay türünde kullanmak 409 üretmelidir. Olay satırı UPDATE/DELETE
   trigger’larıyla değiştirilemez olmalıdır.
5. Sunucunun mutasyonu tamamlayıp istemcinin yanıtı kaybettiği gerçek Chromium
   senaryosunda arayüz aynı kimlikle **güvenle yeniden dene** sunmalı ve
   uzatma sayacı yalnız bir artmalıdır. Aynı Uzat düğmesine hızlı çift tık
   tek oturum günlüğü satırı, tek ağ mutasyonu ve tek sayaç artışı bırakmalı;
   pending satırın İade/Uzat düğmeleri devre dışı olmalıdır.
6. `edition_id`, açık `isbn`, `copy_id` veya `code` seçicilerinden tam biri
   kabul edilmelidir. Sıfır veya birden fazlası servis ve Pydantic API
   katmanında reddedilir. ISBN ve edition yolları gerçek checkout ile
   çalıştırılır; aynı üyenin aynı baskıdan ikinci aktif nüshası servis yarışına
   ve doğrudan SQL yazımına karşı engellenir.
7. Yeni ödünçte ad/numara/sınıf/tür/öğretim yılı snapshot’ları yazılır,
   sonradan üye değişse bile raporlar aynı kalır ve alanlar UPDATE trigger’ıyla
   değiştirilemez. v7 satırı `migration-estimate`, yeni satır `checkout`
   kaynağıyla sayılır; API, web uyarısı ve XLSX Bilgi sayfası kesin/tahmini
   sayıları aynı verir.
8. Geç iade kapatıldıktan sonra `overdue=false`, fakat `days_overdue` gerçek
   iade tarihi–son gün farkı olarak sıfırdan büyük kalmalıdır. API ve banko
   sonucu gecikmeyi “Zamanında” diye yanlış etiketlememelidir.
9. Yıl sonu önizleme/uygulamada yeni listede olmayan açık-ödünçlü öğrenci
   pasifleştirilmez, `needs_resolution` içinde açık kitap sayısıyla görünür.
   Güvenli değişiklikler uygulandıktan sonra çözüm uyarısı kaybolmamalıdır.
10. Web’de kitap/üye/hızlı kayıt/onay/ayar taslağıyla sayfa değişiminde Kal ve
    Vazgeç yolları gerçek tarayıcıda denenir. Ayarlar ilk yüklemede `inert` ve
    `aria-busy` olmalı; gecikmiş eski yanıt formu ezmemelidir. Qt kitap ayrıntı
    taslağı başka satır, sekme ve `closeEvent` için Cancel’da korunmalıdır.
11. Farklı veri kökleri aynı makinede eşzamanlı kimlik üretir; private
    `web_instance_id` kararlı ve yarışta tek tam 32-hex değer olmalıdır.
    Eksik oturum kaydında sağlık yanıtındaki farklı `instance_id` süreci
    sonlandırılmamalı; bozuk UTF-8 `0600` oturum kontrollü LifecycleError
    üretmeli ve traceback sızdırmamalıdır.
12. CLI, web ve Qt kapaklı arşivleri aynı kolektörü kullanmalıdır. Yalnız
    `edition.front_path` ve yalnız `image_asset.managed_path` örneklerinin her
    biri arşivlenir. Özel `--asset-root` tam stage+confirm+apply turunda doğru
    kapağı yeni güvenli ad alanına taşır; aynı sonekli haricî DB yolu `NULL`
    kalır. Arşiv/manifest üye ve açılmış-boyut sınırları hash turundan önce
    uygulanır.

### v0.9.0 dolaba göre içe aktarma regresyonları

Aşağıdaki kapılar v0.8 sözleşmelerine eklenir; eski kapılar kaldırılmaz
(`tests/test_imports_dolap.py`):

1. Şema 9 geçişi v8 veritabanına `import_job.location` ve `job_item.location`
   ekler; sütun yoklaması yazma kilidinden SONRA yapılır, böylece aynı anda
   açan iki uygulama duplicate-column hatası almaz. Yarıda kalmış bir sürüm
   sıfırlamasından sonra v9'a yeniden girilebilmelidir.
2. Parti dolabı işe, klasörden türetilen dolap öğeye yazılır; kataloglama
   anında öğe dolabı partininkini ezer ve iş dolabı TAZE okunur (OCR sürerken
   değişen dolap bayat kayıttan alınmamalıdır). Uçtan uca kapı, sahte motorlu
   zamanlayıcı turunda `copy.location` değerini doğrular.
3. İşin dolabı değişince kataloglanmış kitaplar eski dolabında kalır; iş özeti
   o kitapları `copy.location` üzerinden sayar, iş dolabından değil.
4. Sayfa sayısı dördün katı olan PDF o kadar kitaba bölünür ve her kitap ayrı
   eşleştirme anahtarı alır. Bölme, render'dan ÖNCE disk kapısından geçer;
   yetersiz alanda hiç sayfa yazılmaz ve dosya açık gerekçeyle reddedilir.
5. Tek kitap ucu dört sayfalık tek belgeyi ve dört ayrı yüzü kabul eder; başka
   sayfa/dosya sayısı Türkçe gerekçeyle `400` döner.
6. Yüklemede göreli klasör yolu staging kökünden çıkamaz; sanitize sonrası aynı
   ada inen iki klasör aynı dizinde birleşmez ve derinlik kırpması en içteki
   klasörü korur.
7. `_safe_stem` çakışması (ör. `kitap 1.pdf` ile `kitap_1.pdf`) sayfayı sessizce
   ezmez; ikinci kaynak ayrı bir dizine alınır.
8. İş silme kapısı üç koşulu birlikte arar: iş durmuş olmalı, canlı kiralama
   bulunmamalı ve iş kataloğa kitap yazmamış olmalı. Toplu yeniden deneme iptal
   edilmiş ya da duraklatılmış işi çalışır hale getirmez ve kalan hatalı öğe
   sayısını döndürür (sessiz kırpma yok).
9. Çok parçalı gövdedeki dosyalar Starlette `UploadFile` taban sınıfıyla
   süzülür. İçe aktarma reddi bekleyen testler durum kodunun yanında ret
   gerekçesini de doğrular; "dosya hiç görülmedi" regresyonu aynı `400` altında
   saklanamaz.

## Performans ölçümü

İlk 200 gerçek dört-yüzlü kitapta aşağıdaki süreler ayrı kaydedilir:

- eşleştirme ve hash;
- perspektif/ön işleme;
- beş motorun her biri;
- uzlaştırma;
- barkod;
- Qwen alan çıkarımı;
- SQLite yazımı.

M4/16 GB hedefi en az 60 kitap/saat, en çok 12 GiB süreç-ağacı RSS ve
10.000 kitapta yedi günden kısa toplam süredir. Bu değerler gerçek model
paketi ve gerçek kitap korpusu olmadan “başarılı” ilan edilmez.

Ölçüm için ayrı bir enstrümantasyon gerekmez: `ocr_engine_run.duration_ms`
zaten her koşumda yazılıyor. `kitapkatalog perf-report` bunu motor bazında
özetler ve iki ayrı üst sınır hesaplar — kitap işçisi sayısının izin verdiği
hız ve ağır modellerin süreçler arası kilitle serileştirilmesinden gelen
tavan. **Gerçek sınır ikincisidir**; kitap işçisi sayısını artırmak onu
yükseltmez.

İlk gerçek kitapta ölçülen değerler (M4, tek kitap, dört yüz):

| Motor | Ortalama | Medyan | Model yükleme payı |
|---|---:|---:|---:|
| surya | 20.791 ms | 20.013 ms | 8.811 ms |
| easyocr | 10.303 ms | 10.263 ms | 495 ms |
| paddleocr_vl | 7.699 ms | 7.273 ms | 2.097 ms |
| rapidocr_ppocrv6 | 1.736 ms | 840 ms | 3.587 ms |
| tesseract | 890 ms | 765 ms | 538 ms |

Bu tek kitaplık ölçüm 31,6 kitap/saat veriyor — kapının yarısı. Darboğaz
surya; süresinin yalnız bir bölümü model yüklemesi, gerisi gerçek çıkarım.
Kitabın dört yüzünü tek model yüklemesiyle okumak (bkz. `warm_covers`)
tahminen 44,3 kitap/saate çıkarır, yani **tek başına kapıyı geçirmez**.
Kalan açık için ya ağır modellerin karşılıklı dışlamasını gevşetmek ya da
görsel motorların çıkarım maliyetini düşürmek gerekir; ikisi de gerçek
model paketiyle ölçülmeden karara bağlanmamalıdır.

Dışa aktarım hedefleri 10.000 tamamlanmış kayıt için CSV/JSON en çok 60 saniye,
XLSX en çok 180 saniye ve 750 MB’den az ek bellektir. Sonuç raporunda makine,
işletim sistemi, model digestleri, config hash ve commit kimliği bulunur.

## Paralellik ve bellek kabulü

Varsayılan iki kitap işçisiyle ayrıca şu koşullar sınanır:

1. İki ayrı öğe aynı anda ilerleyebilir ve thread’e özgü callbackler birbirinin
   checkpoint/provenance satırına yazmaz.
2. RapidOCR, EasyOCR, PaddleOCR-VL ve Surya için eşzamanlı inference sayısı
   biri; Tesseract için ikiyi geçmez.
3. Qwen bariyeri yeni OCR çağrısını durdurur, mevcut bütün OCR izinlerini
   toplar ve registry modelleri serbest bırakmadan alan çıkarımı başlamaz.
4. Qwen çıkarken hata oluşsa bile bütün semaforlar geri verilir; kuyruk
   deadlock olmadan devam eder.
5. 10 GiB yumuşak sınır backpressure, 12 GiB sert sınır yeni model reddi
   üretir; tamamlanmış checkpoint kaybolmaz.

## v0.8.0 gerçek yayın kabul kapısı

Otomatik regresyon koşumu aynı commit'te, temiz bir süreçte yapılır:

```bash
.venv/bin/python -m pytest
```

Komutun test sayısı bu kalıcı belgeye yazılmaz. Geçen/atlanan/başarısız
sayılar, commit kimliği ve komut çıktısı yalnız o yayın adayının kabul
tutanağına kaydedilir. `test_web_ui_contract.py` bir tarayıcı motoru
çalıştırmadığından aşağıdaki gerçek tarayıcı kapısının yerine geçmez.

### Yalıtılmış gerçek tarayıcı kabulü

Her koşum için boş, geçici bir `KITAPKATALOG_DATA_DIR` kullanılır; mevcut
okul kataloğu kopyalanmaz veya değiştirilmez. En az bir masaüstü ve bir
≤900 px mobil viewport'ta, fare ve yalnız klavye yollarıyla şunlar kanıtlanır:

1. Sürüm/şema bilgisi görünür; içeriğe-atla, mobil menü, sekmeler,
   dialog/çekmece odak tuzağı, `Escape`, odak geri dönüşü ve tablo
   yatay kaydırma gerçekten çalışır.
2. Gerçekçi bir kitap başlık+yazar+ISBN+konum+çoklu nüsha ile eklenir,
   aranır, düzenlenir ve kapak yüklenir. Son alanda bilerek hatalı bir form
   gönderilip katalog/API tekrar okunarak hiçbir kısmi kayıt kalmadığı
   kanıtlanır.
3. Geçerli dört-yüz fotoğraf/PDF ve bozuk/sahte içerik örnekleri yüklenir;
   başarılı eşleştirme/inceleme görseli açılır, reddedilen dosya katalogda
   iz bırakmaz. Tam beş-model paketli kabulde en az bir iş gerçekten
   çalıştırılır ve checkpoint'ten devam da denenir.
4. e-Okul biçimli gerçek XLSX ile üye içe aktarımı/önizleme/vazgeç,
   ödünç verme-iade-uzatma, raf değişikliği, sayım ve düşüm akışları
   tamamlanır. Düşülmüş nüsha adetten ayrı kalır ve tutanak izi
   adet azaltıp artırdıktan sonra da görülür.
5. CSV/XLSX ve kapaklı `.kitaparsiv` indirilir. Arşiv temiz veri dizinine
   geri yüklenip yeniden açılır; kitap/üye/ödünç/kapak sayıları karşılaştırılır.
   Ayrı bozulmuş arşivin FK/uygulama-kimliği/şema kapısında, canlı DB
   değişmeden reddedildiği gösterilir.
6. Sunucu çalışırken uygulama ikinci kez çağrılır ve eşleşen oturumun
   aynı sürümle yeniden kullanıldığı görülür. Ardından normal kapat/aç
   ve sürüm/nonce uyuşmazlığı kontrollü yeni başlangıç veya güvenli
   engel üretir. Konsol ve `web.log` taranıp token bulunmadığı, oturum/log
   izinlerinin yalnız kullanıcıya açık olduğu denetlenir.

### macOS paket kabulü

İki paket türü birbirine karıştırılmaz. Kaynak checkout'undaki hafif
`KitapKatalog.app` için staged kurulum, sürüm/ikili/imza kontrolü, atomik
değişim ve yapay hata altında rollback sınanır; bu paket bağımsız native
yayın diye etiketlenmez.

Dağıtılabilir native `.app` için ayrıca:

- `CFBundleShortVersionString` ve `CFBundleVersion` proje sürümüyle eşleşir;
- ana ikili ve gömülü runtime hedef mimaridedir (macOS ARM64 yayınında
  `arm64`), `codesign --verify --deep --strict` geçer;
- temiz makine/temiz veri dizininde `--runtime-smoke` başarılı olur;
- Finder'dan açılan uygulamanın gerçek süreci ve loopback dinleyicisi vardır,
  `/health` uygulama+sürüm+şema el sıkışmasını verir ve yukarıdaki temel
  kitap/üye/ödünç akışı paket içinden tamamlanır.

Kabul kanıtı; commit, macOS/tarayıcı sürümü, veri dizini izolasyonu, paket
hash'i, komut çıktıları ve kritik ekran/istek kayıtlarını taşır. Bunlar
toplanmadan v0.8.0 gerçek tarayıcı veya native paket için “geçti” denmez.

## Doğrulama durumunun raporlanması

Sonuçlar beş ayrı sınıfta raporlanır:

| Sınıf | Ne kanıtlar | Ne kanıtlamaz |
|---|---|---|
| Otomatik testler | Durum makinesi, cache, transaction, yükleme, şema/sorgu planı, dosya ve yaşam-döngüsü güvenliği | Gerçek kapak doğruluğu veya görsel tarayıcı davranışı |
| Semantik UI sözleşmesi | HTML/ARIA hedefleri, CSS breakpoint'leri ve JavaScript'teki klavye/asenkron koruma yapıları | Tarayıcının gerçek layout, odak ve cihaz davranışı |
| Gerçek tarayıcı/native runtime | Görünür mobil+klavye akışı, canlı süreç/port ve paket içi işlev | Kilitli beş-model korpus doğruluğu (ayrı kör test yoksa) |
| Sentetik ölçek | Gerçek SQLite/FTS5/export kodunun büyük kayıt hacmindeki davranışı | OCR throughput, CER veya alan precision |
| Gerçek kör test | Kilitli beş-model paketiyle saha doğruluğu, kalibrasyon ve performans | Başka model digestleri/platformlar |

Bu kaynak ağacında otomatik ve semantik UI test altyapısı ile ayrı sentetik
ölçek raporu vardır. Bunlar tek başına gerçek tarayıcı/native runtime
kabulüne kanıt değildir. Tam beş-model paketi ile 500 etiketli gerçek çift
bulunmadığından gerçek kör test de tamamlanmış değildir. Bu eksikler
giderilmeden şu maddeler “geçti” olarak yayımlanmaz:

- beş motorun birlikte dört gerçek kitap yüzünde inference’ı;
- temel alan precision `>=%99`, ECE `<=0,03` ve ensemble iyileşmesi;
- okunabilir barkodlarda ISBN recall ve sıfır otomatik yanlış pozitif;
- M4/16 GB üzerinde `>=60 kitap/saat` ve 10.000 kitapta `<=7 gün`;
- gerçek kapaklarda tepe RSS ve ilk 200 çift aşama süreleri.

Sentetik olarak ölçülmüş kuyruk, FTS5 ve dışa aktarım sonuçları
[ayrı raporda](SENTETIK_OLCEK_RAPORU_TR.md) yer alır; bu sayılar OCR başarısı
olarak yeniden etiketlenmez.
