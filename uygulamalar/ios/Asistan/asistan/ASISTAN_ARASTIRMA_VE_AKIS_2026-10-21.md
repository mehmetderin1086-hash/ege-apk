# Büyük metin araştırması ve akış güvenilirliği

21 Ekim 2026 devam paketi. Önceki GB dosya kasası, V2 görevleri ve kullanıcı ayarları korunur.

## Kullanım

Sohbette **+ → Büyük dosya yükle · Dosya kasası** yolunu aç. TXT, Markdown, CSV veya JSON dosyasını yükledikten sonra **Bu dosyayla araştırma başlat** seçeneğine dokun; sorunu yazıp başlat. Çalışma alanından açılan kasada **Çalışmaya kaynak olarak ekle** de kullanılabilir.

- Dosya saklama sınırı 10 GiB olarak kalır.
- Büyük metin araştırması dosya başına **64 MiB**, kaynakların toplamında **128 MiB** destekler. UTF-8 metin gerekir.
- Sunucu bu yeteneği ilan etmezse uygulama eski 200 KB sınırını korur.
- Araştırma, tüm dosyayı belleğe veya model istemine almaz. Metin akışla taranır; Türkçe karakter normalizasyonu ve sözcük/önek eşleşmesiyle ilgili pasajlar seçilir.
- Modele en fazla **12 pasaj / 36.000 karakter** verilir. Kaynak dosya kimliği ve özgün bayt/satır aralıkları raporun sonunda sunucu tarafından eklenir.
- Bölümler örtüşür; sınırdaki kelime ve cümlelerin bağlamı korunur. Dosyanın SHA-256 değeri tarama sonunda yeniden doğrulanır.
- Genel özet veya eşleşme bulunamayan soruda örnek bölümler kullanıldığı açıkça belirtilir. Seçili pasajlar tüm belgenin anlamsal incelemesi veya eksiksiz özeti sayılmaz.
- Kaynak seçimi görev kontrol noktasına yazılır; devam işlemi tamamlanmış taramayı tekrar etmez. İptal, işçi nesli ve süre sınırı tarama sırasında denetlenir.
- Çalışma türünü değiştirince dosya türü/boyutu yeniden kontrol edilir. Uyumsuz kaynakla Başlat kapalıdır; kaynak korunur ve açıklama gösterilir.

Küçük kaynakların mevcut tam metin yolu korunur. Belge/öğrenme/ses için 200 KB ve toplam 120.000 karakter; analiz için 25 MiB; yerel PDF çıkarımı için 25 MiB, 200 sayfa ve 120.000 karakter sınırları devam eder. Ham PDF, taranmış PDF, video ve GB ikili dosyalar bu yeni metin taramasına dahil değildir.

## Sohbet ve ses düzeltmeleri

- Hızlı model yarışında SSE bitiş işareti geldiğinde açık TCP bağlantısının kapanması beklenmez. Son parça korunur; bitmiş yanıt sonradan ağ hatasına dönüşmez.
- Bitiş işareti olmayan yarım yanıt başarı sayılmaz. Son callback sırasında iptal, başarı olarak yayımlanmaz.
- Ses metni `12.` ve `50` olarak farklı parçalarla geldiğinde sayı bölünmez. Akış gerçekten `12.` ile biterse kalan metin yine okunur.

## Doğrulama

- iOS: **1.538 test / 229 grup geçti**. Terminal SSE, son delta, yarım yanıt, iptal, metinsiz bitiş, parçalanmış ondalık sayı ve kaynak uyumluluğu dahil.
- Günlük: `~/Developer/.build/asistan-retrieval-tests.log`.
- **3 arayüz testi geçti:** Atölye üzerinden kasa, sohbetin + menüsünden kasa ve sohbete dönüş, Tuval oluşturma/kaydetme/sürüm geçmişi. Günlük: `asistan-retrieval-ui.log`.
- **98 Python testi geçti**, yerelde ve VPS staging dizininde. Yeni kaynak seçimi testleri; UTF-8 sınırı, örtüşme, tam dosya hash denetimi, iptal/deadline, devam checkpoint’i, eski görev türleri ve sınırlı bellek dahil.
- Bağımsız yerel 64 MiB UTF-8 tarama: **6,433 saniye**, **22,859 MiB tepe RSS**, import sonrası önceki tepeye göre **0,922 MiB artış**. Sondaki tekil bilgi bulundu; 12 pasaj / 34.361 karakter seçildi ve özgün bayt aralıkları doğrulandı. Tek koşudur; disk önbelleği kontrol edilmedi, model/ağ süresini ölçmez. Rapor: `~/Developer/.build/asistan-retrieval-benchmark.json`.
- İki bağımsız kod incelemesinde son değişikliklerde P1/P2 bulgu kalmadı.
- **Canlı üretim kabulü geçti:** genel HTTPS adresinden 16.777.250 bayt sentetik metin yüklendi. Gerçek model, dosyanın sonundaki `982731` değerini doğru [K12] pasajına ve bayt/satır konumuna bağladı. Yükleme, tarama ve iki model adımı toplam **23,28 saniye** sürdü; servis tepe RSS değeri yaklaşık 33,4 MiB'dan 43,7 MiB'a çıktı. V1 sağlığı korundu; yalnız testin ürettiği görev/çıktı/dosya temizlendi. Bu ölçüm VPS'ten genel HTTPS adresine yapılmıştır; telefon veya mobil bağlantı hız ölçümü değildir.
- Canlı çıktı, olaylar, dağıtım ve staging test kanıtları: `~/Developer/.build/asistan-retrieval-verification/`.
- **Fiziksel iPhone:** Asistan **0.21.0 (202610210543)** Release derlendi, kuruldu, telefondaki build numarası doğrulandı ve uygulama açıldı. Kurulum 129 saniye sürdü. Günlük: `~/Developer/.build/asistan-retrieval-device.log`. Büyük kaynakla araştırmanın dokunmatik uçtan uca akışı ve canlı ses düzeltmesi telefonda ayrıca ölçülmedi; bunlar sunucu/simülatör testlerinden ayrı kabul adımlarıdır.

## Üretim dağıtımı

Önceden verilen “yedek alıp kur ve doğrula” onayı kapsamında kod ve SQLite yedeği alındı: `/var/backups/asistan-workspace/retrieval-20261021T024415Z`.

`server.py`, `workspace.py`, `source_retrieval.py` birlikte kuruldu. Yükleme/analiz/ses modülleri ve mevcut ses kataloğu korundu; Caddy ve servis yapılandırması değiştirilmedi. Yetenek kontrolü yeni araştırma sınırlarını döndürdü; `paid_enabled=false` kaldı. Staging testleri için mevcut `voices.json` yalnız staging dizinine kopyalandı; üretim kataloğu paket şablonuyla ezilmedi.

Dağıtım kanıtı: `~/Developer/.build/asistan-retrieval-deployment.log`. Geri almada bu üç kod dosyası yedek sürümlerine döndürülür; yeni modül önceki sürümde yoktur. Kullanıcı dosyaları ve veritabanı eski yedekle otomatik değiştirilmez.

## Sınırlar ve devam kapsamı

Bu paket sözcük eşleştirmesi kullanır; anlamsal embedding araması veya GB boyutlu kalıcı indeks içermez. Büyük dosyaları parçalara ayırıp tümünü özetleme, PDF OCR, genel web tam sayfa toplama, arka plan aktarımı, APNs ve kapsamlı gerçek cihaz gecikme karşılaştırması açık kalır. Yeni ücretli API veya servis etkinleştirilmez.
