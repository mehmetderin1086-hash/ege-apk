# Asistan — uygulama, üretim dağıtımı ve doğrulama raporu

Tarih: 21 Ekim 2026. Çalışma ağacı: `/Users/mehmetderin/Developer/asistan`, temel commit `b87e305`. Kullanıcının önceden bulunan değişiklikleri korundu; commit veya TestFlight yüklemesi yapılmadı.

Kullanıcı “Evet, yedek alıp kur ve doğrula” diyerek VPS dağıtımına izin verdi. V2 çalışma alanı üretime kuruldu, gerçek hizmetlerle doğrulandı. Son büyük metin araştırması ve akış paketiyle iPhone'a Asistan **0.21.0 (202610210543)** Release kuruldu, sürümü doğrulandı ve uygulama açıldı. Geniş yol haritasının bütün maddeleri tamamlanmış değildir; kalan kapsam aşağıda belirtilmiştir.

Son devam turu: 64 MiB kaynak araştırması, 128 MiB toplam kaynak sınırı, sınırlı bellekle pasaj seçimi ve kaynak konumları; sohbet + menüsünden kasa/araştırma erişimi; SSE bitişi ve ondalık sayı seslendirme düzeltmesi. **1.538 iOS testi, 3 arayüz testi ve 98 sunucu testi geçti**. Canlı 16 MiB kaynak araştırması doğru son pasajı buldu. Ayrıntılar: [Büyük metin araştırması ve akış raporu](ASISTAN_ARASTIRMA_VE_AKIS_2026-10-21.md). Aşağıdaki önceki test sayıları önceki paketlerin tarihsel kanıtıdır.

## Uygulananlar

- Atölye → Çalışma alanı: Tuval, İETT haritası, sunucu görevleri ve çıktılar için ortak giriş.
- Tuval: kalıcı belge, proje bağı, sürüm geçmişi, eski sürümü geri getirme, seçili bölümü değiştirme, kurtarma taslağı, içe/dışa aktarma ve paylaşma. Sürüm çakışmasında metin ezilmez. Başka araç işlemi kullanıcının farklı taslağını silemez.
- HTML önizleme: ayrı geçici WebKit ortamı; dış ağ, resim ve çerçeve engeli; kalıcı çerez veya native mesaj köprüsü yok.
- İETT: yön filtresi, konum haritası, ölçüm zamanı/tazelik, favoriler ve 60 dakikalık yerel durak uyarısı. Eski konum canlı gibi gösterilmez. Kesintisiz sunucu takibi ve gerçek ETA bu sürümde yoktur.
- Yaşam servisleri: boyutu sınırlı disk önbelleği; iptal, eksik polen ve bulunamayan konum durumlarının ayrılması; değiştirilen İETT uyarısını eski kontrolün silmesini engelleme.
- Kaynak kartları, denetim notları ve düzeltme düğmesi gizli. Önceden mevcut bu çalışma ağacı değişiklikleri arayüz testleriyle doğrulandı.
- V2: görev tekilleştirme, atomik işçi sahipliği, iptal nesli, yeniden başlatma sonrası duraklatma, tamamlanan adımlardan devam, olaylar, dosya/çıktı/sürüm API'leri.
- Belge ve kaynak dosyalı araştırma üretimi, soru–cevap öğrenme akışı, ayrı Docker analiz işçisi, mevcut Azure ses köprüsüyle iki konuşmacılı anlatım.
- Kota veya iptal sırasında dosyalar ile adım kaydı birlikte geri alınır. Sert kapanışta kayıtsız dosya korunup kotaya eklenir.
- Ses bekleme süreleri görev bütçesine bağlıdır. Süreyi aşan görev başarı göstermez; hazırlanmış parçalar yeniden kullanılabilir. Azure kataloğu için ilgisiz SesLab bağlantısı beklenmez.
- Yeni ücretli API kullanımı kapalıdır. Mevcut hesaplar ve ses köprüsü kullanıldı; yeni ücretli servis açılmadı.

## Gerçek üretim kabulü

Beş görev türü dış HTTPS üzerinden oluşturuldu, durumları/olayları ve çıktıları kontrol edildi. Yalnız sentetik sınama girdileri kullanıldı.

| Görev | Gerçek sonuç |
|---|---|
| Belge | Metin çıktısı ve kalıcı sürüm üretildi; aynı istek kimliği ikinci görev oluşturmadı |
| Kaynaklı araştırma | Yüklenen su döngüsü kaynağından, kaynak kimliği içeren rapor üretildi |
| Öğrenme | Kısa açıklama ve öğrenci cevabını bekleyen soru üretildi |
| Veri analizi | Modelin ürettiği Python Docker'da çalıştı; x=1,2,3 toplamı 6; gerçek PNG ve CSV indirildi |
| Sesli anlatım | Elif/Aydın sesleriyle MP3 ve transkript üretildi; MP3 indirildi, medya doğrulaması geçti |

- MP3: 171.405 bayt; 14,256 saniye; 24 kHz, tek kanal.
- Analiz çıktıları: PNG 25.765 bayt, CSV 72 bayt; PNG imzası ve indirilen dosya boyutları doğrulandı.
- Bağımsız Docker kabulünde XLSX içindeki 2,4,6 toplamı 12 bulundu. Ağ kapalı, girdi salt okunur; host sır dosyası ve Docker soketi konteynerde yok.
- 62.500 bayt yükleme, iptal, kimliksiz erişimin reddi, V1'in çalışması ve SQLite bütünlüğü doğrulandı.
- Proxy'nin yerel web aracı reddedilince sunucu ücretsiz MediaWiki REST aramasını kullanır; canlı arama üç Türkçe Wikipedia sonucu döndürdü. Bu yedek en çok üç kısa özeti kullanır, tam makale sayfalarını açmaz ve kapsamı Wikipedia ile sınırlar. Ücretli API'ye geçilmez.
- Bu Wikipedia yolu üretimde HTTPS üzerinden ayrıca çalıştırıldı: araştırma görevi tamamlandı, 3 kaynak bağlantısı çıktı ve Wikipedia kapsamı raporda açıklandı.
- Araştırma dosya seçicisinde PDF etkinleştirildi. PDF metni iPhone'da PDFKit ile çıkarılır, sayfa numarası `[Sayfa N]` etiketi korunur ve sunucuya metin olarak gönderilir; 200 sayfa/120.000 karakter sınırı vardır. Metin katmanı olmayan sayfalar açıkça belirtilir; otomatik OCR yapılmaz.
- PDF metin çıkarımı, sayfa numarası, PDFKit çıktısındaki satır düzeni ve bozuk PDF reddi ilgili 13 testlik simülatör grubunda geçti. Uygulama Release 0.21.0 (202610210515) olarak fiziksel iPhone'a kuruldu; kurulum betiği sürümü doğrulayıp uygulamayı başlattı.
- APNs anahtarı yapılandırılmamış: görevler sunucuda tamamlanır ancak telefon kapalıyken push bildiriminin teslimi henüz yoktur.

## Test ve cihaz kanıtları

| Kontrol | Sonuç | Kanıt |
|---|---|---|
| Python sunucu testleri | Yerelde 60, VPS staging'de son dağıtım turunda 60 geçti | `~/Developer/.build/asistan-workspace-python-test.log` |
| Swift birim testleri | 1.521 test, 228 suite başarılı | `~/Developer/.build/asistan-test-tam.log` |
| Tuval oluştur/yaz/kaydet/geçmiş | 1 UI testi geçti | `~/Developer/.build/asistan-tuval-ui-gecti.log` |
| Kaynak kartı ve denetim görünümü | 2 UI testi geçti | `~/Developer/.build/asistan-test-tam.log` |
| HTML gerçek WebKit | Ağ, resim ve çerçeve engelleri doğrulandı | `htmlGercekWebKitAgIstekleriniReddeder` |
| FFmpeg | Sentetik WAV → MP3 ve gerçek Azure MP3 doğrulandı | `test_analysis_audio.py`, `audio-media-acceptance.json` |
| Sert kapanış | Ayrı süreç commit öncesi kesildi; dosya korundu ve kota saydı | `test_workspace.py` |
| Bağımsız inceleme | Bildirilen veri koruma/iptal/süre/kota bulguları düzeltildi; son runtime incelemesinde yeni P1/P2 yok | Swift ve Python incelemeleri |
| Gerçek İETT | 34AS boş dönüşü ardından 34G'den 1 araç alındı; test geçti | `~/Developer/.build/asistan-test-canli.log` |
| Fiziksel iPhone | Release derleme, kurulum, sürüm kontrolü ve açılış başarılı | `~/Developer/.build/asistan-kurulumlar.log`, 04:54:09 kaydı |
| Üretim Docker/Azure/HTTPS | Yukarıdaki beş görev ve indirmeler geçti | `~/Developer/.build/asistan-workspace-staging/verification/` |
| Ücretsiz web yedeği | Production araştırma görevi tamamlandı; 3 Wikipedia bağlantısı ve kapsam notu; ücretli yol kapalı | `mediawiki-public-acceptance.json` |

Tuval UI testinin ortaya çıkardığı klavye odak sorunu, metin alanı yerel UITextView üzerinde yönetilerek giderildi. Geçen testte yazma, kaydetme ve sürüm geçmişine geçiş yürütüldü. Arayüz testleri simülatörde yapıldı; telefon kurulumu ve açılışı, bütün özelliklerin fiziksel cihazda kabulü anlamına gelmez. Gerçek yolculuk, kilitli ekran/push ve bütün Tuval akışlarının fiziksel kabulü açık kalır.

## Dağıtım ve geri alma

- Yedek: VPS'te `/var/backups/asistan-workspace/20261021T015306Z`; kod, tutarlı SQLite yedeği, servis ve Caddy kayıtları. Web araştırma ekinden önceki production `server.py` de `server.before-wikipedia-fallback.py` olarak aynı dizine yedeklendi. Sır içerebilecek yapılandırmalar repoya veya rapora alınmadı.
- Çalışan kod: `/srv/apps/asistan-jobs/`; mevcut `voices.json` korundu.
- Caddy'ye mevcut kimlik doğrulaması altında yalnız V2 yolu eklendi; 52 MB V2 sınırı, V1'in 40 KB sınırı ayrı kaldı. Validate/reload geçti.
- `asistan-jobs`, `asistan-runner` ve Caddy etkin. Analiz/ses açık; bağlantılar/masaüstü/kanallar kapalı.
- Docker imajı: `asistan-analysis:1`, kimlik `sha256:829ac7bdcf96547d6e6d8f2cbcb4d724eab74bc8963c288957919fc3b9ddf2fb`.
- Son paket: `/Users/mehmetderin/Developer/.build/asistan-workspace-staging/asistan-workspace-v2.tar.gz`; 14 dosya, dosya SHA-256 değerlerini içeren `MANIFEST.json`. Üretimdeki mevcut ses kataloğu bu şablonla ezilmez.
- Paket SHA-256 ayrıca aynı dizindeki `asistan-workspace-v2.tar.gz.sha256` dosyasında tutulur.
- Ayrıntılar: [WORKSPACE_ROLLOUT.md](vps/asistan-jobs/WORKSPACE_ROLLOUT.md). Geri almada V2 tabloları ve kullanıcı dosyaları silinmez; DB eski yedekle otomatik ezilmez.

## Kullanım

1. Atölye → Çalışma alanı → Tuval: belge oluştur, düzenle, kaydet; sürüm geçmişinden geri getir veya HTML önizlemesini aç.
2. Çalışma alanında görev türünü seç. Araştırma/ses için TXT veya Markdown; analiz için CSV/JSON/XLSX yükle.
3. Görevi başlat; tamamlanınca çıktıyı Tuval'e al veya üretilen dosyayı aç/paylaş.
4. İETT haritasında hat ve yönü seç; son ölçüm zamanını kontrol et, favori veya süreli durak uyarısı ekle.

## Tamamlanmamış kapsam

Hazır OAuth hesap merkezi, Telegram/Discord kanalları, ayrı kalıcı masaüstü ajanı, tam iddia/kanıt arşivi ve PDF sayfa çıkarımı, kalıcı Python oturumu, öğrenme ustalığı/aralıklı tekrar, ses bölüm zamanları ve ayrıntılı oynatıcı, kesintisiz sunucu İETT takibi, çift yönlü Tuval senkronizasyonu bu paketle tamamlanmadı. Genel amaçlı web kaynaklarının tam sayfalarını arka plan görevi açamıyor; ücretsiz yedek yalnız Wikipedia arama özetleriyle sınırlı. APNs için hesap yapılandırması gerekiyor.

Özellik matrisi ve devam kapsamı: [ASISTAN_KAPSAMLI_GELISTIRME_PLANI.md](ASISTAN_KAPSAMLI_GELISTIRME_PLANI.md).
# Son ek paket: GB dosya kasası, hız ve güvenilirlik

21 Ekim devamında 10 GiB dosya yükleme, 8 MiB parçalar, kaldığı yerden devam, indirme/bütünlük kontrolü ve dosya kasası eklendi. Ortak dosya okuma arayüz dışına taşındı, gereksiz bellek kopyası kaldırıldı, yenileme çağrıları paralelleştirildi ve Ofis arşivlerinin açılma sınırları uygulandı. 1.528 iOS testi ve 77 sunucu testi geçti; gerçek 2 GiB + 17 bayt HTTPS aktarımı/indirme/kayıp yanıt kabulü geçti. Ayrıntılar ve kapsam: [GB dosya ve hız raporu](ASISTAN_BUYUK_DOSYA_VE_HIZ_2026-10-21.md).
