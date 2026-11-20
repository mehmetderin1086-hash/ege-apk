# Ritim — iPhone müzik ve video oynatıcı

**1.10.0**, Türkçe SwiftUI arayüzlü bir iPhone/iPad uygulamasıdır. YouTube bağlantısını çözümleme, dosya indirme, MP3 hazırlama ve MP4 birleştirme doğrudan iPhone’da yapılır. **İndirme ve çalma için Mac servisi gerekmez.** iOS 17 ve üzerini destekler.

Asistan, iPhone’dan internet üzerindeki HTTPS CLIProxy geçidine bağlanır. Mac kapalıyken kullanılabilir; model yanıtları için internet ve yapılandırılmış geçit erişimi gerekir. İndirilmiş müzik ve videolar tamamen çevrimdışı çalar.

## Kullanım

1. **İndir:** Tek YouTube bağlantısı, satır satır birden fazla bağlantı veya oynatma listesi ekle. MP3 / MP4 ve kaliteyi seç. Liste önizlemesinde tüm parçaları ya da istediklerini kuyruğa al.
2. **Kitaplığım:** Tamamlanan müzik ve videoları çal; ara, filtrele, sırala, favorilere veya çalma listelerine ekle. Oynatma listesi indirmeleri aynı adlı yerel listede toplanır.
3. **Keşfet → Dosya ekle:** Dosyalar uygulamasından MP3, M4A, WAV, AAC, AIFF, CAF, MP4 veya MOV içe aktar. Dosyanın kopyası Ritim’e kaydedilir.
4. **Alt oynatıcı:** Tam oynatıcıyı aç; karıştırma, tekrar, çalma sırası, 0,5–2× hız, uyku zamanlayıcısı ve AirPlay kullan. Video dosyalarının görüntüsü de oynatılır. Arka plan sesi ve kilit ekranı kumandaları desteklenir.
5. **Asistan:** Model seçip soru sor veya kitaplığından çalma listesi iste. Öneriyi çal/kaydet; yeni parça önerilerini YouTube’da ara, seçtiklerini indir. Asistan kendi başına dosya indirmez veya kitaplığı değiştirmez.

Doğrudan HTTPS medya bağlantıları özgün dosya biçiminde indirilir. MP3/MP4 dönüştürme seçimi YouTube içindir.

## Şarkı sözleri, albümler ve sana özel koleksiyonlar

**Alt oynatıcı → Şarkı sözleri:** Dosyaya gömülü sözler veya LRCLIB eşleşmesi açılır. Zamanlı sözlerde satıra dokunarak o konuma gidebilir, takibi açıp kapatabilir ve **Zamanlama** ile ±30 saniye düzeltme yapabilirsin. Düz metinler için zaman uydurulmaz. Bulunan sözler cihazda saklanır ve sonraki açılışta internet istemez. Otomatik söz önbelleği en fazla 100 kayıt / 16 MiB tutar; kendi eklediğin sözler bu temizlikten etkilenmez. Her parçada söz bulunmayabilir; **Eşleşme ara**, **Söz ekle** veya **LRC / TXT içe aktar** kullanılabilir. Düzenleyici özgün LRC zamanlarını korur. Arama için parça başlığı, sanatçı ve süre LRCLIB'e gönderilir; ses dosyası gönderilmez. Sözlerin bulunamaması müziği durdurmaz.

**Kitaplığım → Albüm / Sanatçı:** Sanatçıya ve albüme göre gezin. Yeni dosyalarda gömülü albüm/kapak okunur. Eski dosyalar için **Bilgileri tara** kullanılır; tarama sırayla ve ön planda yapılır, başlık/sanatçı düzeltmelerini değiştirmez. Dosyada kapak yoksa Ritim'in mevcut görseli kalır.

**Kitaplığım → Sana özel:** Henüz dinlemediklerin, son 30 günde eklenenler, 14 gündür dinlemediğin beğeniler ve her parçanın son çalınmasına göre sıralanan müzikler. Koleksiyonlar yerel kütüphaneye göre güncellenir. **Liste olarak kaydet**, o anki parçaları normal bir listeye kopyalar.

**Parça seçenekleri → Sıradaki çal / En sona ekle:** Mevcut parçayı kesmeden sırayı değiştirir; sıradaki seçim karışık çalmada da önceliklidir. Zaten sıradaki bir parça taşınır, kopyası eklenmez. **Tam oynatıcı → Çalma sırası → Liste olarak kaydet** tüm sırayı saklar.

Karşılaştırma ve kapsam: [FEATURE_MATRIX.md](FEATURE_MATRIX.md). Apple Music, Spotify ve YouTube Music hesap/katalog akışları bu yerel özelliklerden ayrıdır; bu sürüm abonelik kataloglarını bağlamaz.

## Mac ve internet olmadan çalma

**Kitaplığım → parça veya video → Çal.** Tamamlanan dosyalar iPhone’un kalıcı `Documents/Media` klasöründedir. Mac, Wi-Fi, hücresel internet veya ayrıca açılması gereken bir çevrimdışı düğmesi yoktur. Yerel çalma listeleri de aynı dosyaları kullanır; açılışta sunucu yanıtı beklenmez.

Yeni YouTube indirmesi ve araması internet ister; indirme sunucusu istemez. Asistan internet üzerindeki seçili sağlayıcıyı kullanır. Çevrimdışı oynatma bu bağlantılardan bağımsızdır. Eski sürümlerde Mac üzerinden indirilmiş dosyalar ve mevcut listeler korunur.

Uzun dinlemede listenin sonunda yeniden başlamak için tam oynatıcıda **Tekrar → Tümü** seç; uyku zamanlayıcısı açıksa belirlenen saatte çalma durur.

## Kaldığın yerden devam

Uygulama yeniden açıldığında son parça, çalma sırası ve konumu geri gelir. Karıştırma, tekrar ve hız tercihi de korunur. **Keşfet → Kaldığın yerden → Dinlemeye devam et** ile sürdürebilirsin. Açılışta kendiliğinden ses başlamaz; devam etmek için çalma düğmesine dokun.

Kayıt cihazda tutulur. Duraklatma, konum değiştirme ve arka plana geçişte güncellenir; oynarken 10 saniyede bir kaydedilir. Ani kapanmada son kayıt aralığı kaybolabilir. Silinmiş veya dosyası eksik parçalar geri yüklenen sıraya alınmaz. Uyku zamanlayıcısı yeniden açılışta başlatılmaz.

## Ses ve video kalitesi

**En yüksek** yeni indirmelerde varsayılandır. Ses, iPhone’da çözülebilen en yüksek bit hızlı AAC kaynağından **320 kbps MP3** olarak kodlanır. **Standart**, **192 kbps MP3** hazırlar. Kaynak daha düşük kaliteliyse 320 kbps seçmek kaybolmuş ayrıntıyı geri getirmez. Bu sürüm YouTube’un WebM/Opus sesini dönüştürmez.

Video için **En yüksek**, cihazın desteklediği SDR MP4 kaynağını **en fazla 4K** olacak şekilde seçer; **Standart** üst sınırı **1080p** yapar. Uyumlu video ve ses, AVFoundation ile MP4 içinde yeniden sıkıştırılmadan birleştirilir. Görüntü yapay olarak büyütülmez. H.264 ve cihazın donanımı uygunsa 8 bit SDR AV1 kullanılabilir; WebM/VP9 veya HDR dönüştürme bu sürümde yoktur.

**Her videoda 4K garanti edilmez.** Örneğin iPhone 15’te bazı YouTube videolarının uyumlu H.264 kaynağı 1080p ile sınırlıdır. İndirme satırında seçilen gerçek çözünürlük gösterilir; kaynakta daha yüksek çözünürlük olup cihazla uyumlu değilse açıklama eklenir.

Kalite seçimi tek bağlantı, toplu indirme, oynatma listesi ve Asistan indirmelerinde ortaktır. Kuyruğa eklenmiş işin kalitesi sonradan tercih değiştirilince değişmez. Eski dosyalar silinmez; aynı YouTube bağlantısını farklı kaliteyle eklemek ayrı kopya oluşturabilir. Bütün arşiv otomatik yeniden indirilmez.

Her YouTube ses/video kaynak parçası ve hazırlanmış çıktı için üst sınır **512 MiB**’dir; arayüzde 512 MB olarak gösterilir. Ses, video, geçici dönüştürme dosyaları ve kalıcı kopya için ek boş alan gerekir.

## Toplu indirme ve uygulamanın arka plana geçmesi

- Kuyrukta **5.000 tamamlanmamış dosya** tutulabilir. Ayarlar’dan **2 / 4 / 6 / 10 / 20 / 50 / 100 eşzamanlı iş** seçilir; yeni kurulumlarda varsayılan 10, mevcut kurulumlarda kayıtlı tercih korunur. Bu sayı gerçek eşzamanlı ağ bağlantısı garantisi değildir. Isınmada yeni iş sınırı 2'ye, düşük güç modunda en fazla 4'e iner; kritik ısıda yeni işler bekler. Dönüştürme tek sıra halinde yürür.
- Sınırı artırmak yeni işleri başlatır; azaltmak başlamış işleri iptal etmez. **Kuyruğu duraklat** yeni işlerin başlamasını durdurur, başlamış işler tamamlanır. Toplu iptal, devam ettirme ve başarısızları yeniden deneme vardır.
- Aynı YouTube bağlantısı, biçim ve kalite birlikte tekilleştirilir. MP3 ve MP4 ayrı indirmelerdir. Önceden indirilmiş eşleşen parça yeni listeye tekrar indirilmeden bağlanır.
- Oynatma listeleri, dosyalar farklı zamanlarda tamamlansa da kaynak sırasını korur. Aynı parça farklı listelerin kendi sırasına yerleşir. Kütüphaneye kaydedilmesiyle indirme günlüğünün tamamlanması arasında uygulama kapanırsa, geçerli yerel dosya açılışta bulunur ve tekrar indirilmez.
- Herkese açık oynatma listeleri ve otomatik Mix bağlantıları doğrudan YouTube’dan okunur. Mix dinamiktir; o anda sunulan ve tekrarlanmayan parçalar alınır, her Mix yüzlerce sonuç döndürmeyebilir.
- Çözümlenmiş YouTube kaynakları iOS arka plan aktarımına devredilebilir. Tamamlanan bileşenler ara kayıtta korunur; devam eden işlem ve arka plan görevleri uygun olduğunda MP3 hazırlama/MP4 birleştirme sürer. iOS çalışma zamanını belirler; kilitliyken bütün kuyruğun kesintisiz bitişi garanti değildir. Ekranı açık tutma ayarı yalnız ön planda etkindir.
- Kuyruk diskte saklanır. Uygulamanın kapanması tamamlanmış kütüphane dosyalarını silmez. İptal edilen veya yarım kalan işe ait geçici dosyalar temizlenir; eski Mac kuyruğunun tamamlanmamış işleri yerel akışa taşınır.

YouTube’un kaldırılmış, özel, üyelik veya yaş doğrulaması isteyen videoları indirilemeyebilir. Hesap çerezi veya DRM çözme akışı bulunmaz. YouTube’un sayfa/oynatıcı yapısı değiştiğinde çözümleyici güncellemesi gerekebilir.

## Asistan bağlantısı

İstek yolu **iPhone → HTTPS CLIProxy geçidi → seçilen sağlayıcı** şeklindedir. Model işlemi internet üzerindeki sağlayıcıda çalışır. **Asistan → model adına dokun → model veya sağlayıcı ara** yoluyla canlı katalogdaki sohbet modelleri seçilir. Önceki dört model sınırı kaldırıldı; ChatGPT, Claude, Gemini ve geçidin sunduğu diğer sohbet modelleri görünür. Görsel, seslendirme, canlı ses ve özel araç uçları sohbet listesine karıştırılmaz.

Modelin katalogda olması hesabın o anda yanıt verebildiği anlamına gelmez. “Yanıt doğrulandı” yalnız bu oturumda aynı modelden gerçek, geçerli yanıt alındıktan sonra gösterilir; hata durumunda güncellenir. Kullanılabilirlik hesaba, kotaya ve sağlayıcıya bağlıdır. Seçilen model hata verirse başka modele sessizce geçilmez.

Asistan’ın dişlisinden HTTPS adresi ve erişim biçimi ayarlanır. Kişisel geçit erişim anahtarı iOS Keychain’de, bağlandığı adrese özel saklanır. Asıl sağlayıcı kimlik bilgileri uzaktaki geçitte kalır. Medya dosyaları modele gönderilmez; öneriler için sınırlı kitaplık bilgisi ve sohbet bağlamı kullanılır. Ayrıntılar: [AI_INTEGRATION.md](AI_INTEGRATION.md).

Geliştirme kurulumunda, Git dışında tutulan yapılandırma dosyasından eşleştirme yapılabilir:

```sh
python3 scripts/pair_assistant.py IPHONE_UDID --config /guvenli/yol/ai-proxy.json
# Simülatör: aynı komuta --simulator ekle.
```

[scripts/pair_assistant.py](scripts/pair_assistant.py) anahtarı yalnız geliştirme başlatma ortamına iletir; uygulama Keychain’e kaydeder. Kaynak koda, uygulama paketine, test ayar dosyasına veya konsola anahtar yazılmaz. Eşleştirmeden sonra normal kullanımda Mac gerekmez. Eski `scripts/pair_device.py`, v1.5 indirme servisine aittir; v1.6 indirmeleri için kullanılmaz.

## Kişisel panel ve istatistikler

**Keşfet**, bugünkü/son yedi günlük dinleme süresini, **7 / 30 gün** grafiğini, parça/favori/ses/video sayılarını, medya alanını ve indirme kuyruğunu gösterir. Güne dokunarak süreyi görebilirsin. Kütüphane kartları ilgili filtreyi, indirme ve Asistan kartları ilgili sekmeyi açar.

Dinleme süresi yalnız AVPlayer gerçekten oynarken geçen süreyi sayar. İleri sarma, duraklatma ve bekleme eklenmez; oynatma hızı sayacı hızlandırmaz. Önceki çalma sayılarından geçmiş süre üretilmez. İstatistikler cihazdaki `listening.json` dosyasında en fazla 366 gün tutulur; 15 saniyede bir ve duraklama/arka plana geçişte kaydedilir. Ani kapanmada son kayıt aralığı kaybolabilir.

Oynatıcıdaki çalma, beğenme ve kapak geçişleri hareketlidir. **Hareketi Azalt** etkinse dekoratif hareketler durur. Panel büyük erişilebilirlik yazı boyutlarına uyum sağlar.

## Kaynaktan derleme

`Ritim.xcodeproj` dosyasını Xcode 27.1 veya üzeriyle aç, **Ritim** şemasını ve cihazını seç. Signing & Capabilities bölümünde kendi geliştirme takımını ayarlayıp çalıştır. İlk paket çözümlemesi için internet gerekir; kurulmuş uygulamanın çalışması Xcode’a bağlı değildir.

```sh
open Ritim.xcodeproj
```

Proje tanımı [project.yml](project.yml) içindedir. Target veya kaynak yapısı değişirse [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile `xcodegen generate` çalıştırılabilir; mevcut projeyi açmak için XcodeGen gerekmez.

Bağımlılıklar sabittir:

- [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit), MIT, `89854c93207ad0d2b3d78d6f1aea24595ca66552` commit’i. SwiftPM indirir. Yalnız yerel çıkarım kullanılır; uzaktan çözümleme yedeği açılmaz.
- [LAME 4.0](https://lame.sourceforge.io/), LGPL 2 veya sonrası. Kullanılan kodlayıcı C kaynakları, başlıkları ve SwiftPM yapılandırması [Vendor/Lame](Vendor/Lame) içinde bulunur; önceden derlenmiş bir kodlayıcı indirilmez. Tam [COPYING](Vendor/Lame/COPYING), [LICENSE](Vendor/Lame/LICENSE), [kaynak arşivi özeti](Vendor/Lame/UPSTREAM.sha256) ve [derleme bilgisi](Vendor/Lame/INTEGRATION.md) dahildir.

YouTubeKit’in JavaScript yardımcıları dahil atıflar ve lisanslar [ThirdPartyNotices.md](ThirdPartyNotices.md) dosyasındadır. LAME değiştirilerek uygulama aynı kaynaklarla yeniden derlenebilir.

## Doğrulama

```sh
xcodebuild -project Ritim.xcodeproj -scheme Ritim \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO -collect-test-diagnostics never test
```

Birim testleri kütüphane koruması, medya dönüştürme, kalite tercihleri, 5.000 kayıtlık kuyruk, eşzamanlı iş sınırları, iptal/yeniden deneme yarışları, eski Mac kayıtlarının göçü, doğrudan YouTube katalog yanıtları ve Asistan bağlantısını kapsar. UI testleri gezinme, yerel çalma, panel, kuyruk ve indirme ayarlarını kontrol eder.

Canlı YouTube indirme testi için test çalıştırıcısına `RITIM_UI_TEST_NATIVE=1`; canlı Asistan testi için `RITIM_UI_TEST_AI=1`; hazırlanmış yerel dosyalarla çevrimdışı oynatma testi için `RITIM_UI_TEST_OFFLINE=1` verilir. Testler kullanıcının gerçek `Documents` kütüphanesinden ayrı önbellek alanını kullanır. Birim testinin geçmesi gerçek iPhone kabulünün yerine sayılmaz; güncel çalıştırmalar ve sınırlar [VALIDATION.md](VALIDATION.md) içindedir.

## Kaynak düzeni

| Yol | İçerik |
| --- | --- |
| `Ritim/Core` | Kütüphane, oynatıcı, istatistik, yerel YouTube çözümleme/katalog/indirme, medya dönüştürme, doğrudan Asistan bağlantısı |
| `Ritim/Views` | Türkçe SwiftUI ekranları |
| `Vendor/Lame` | Derlemeye dahil MP3 kodlayıcısı kaynakları ve lisansları |
| `RitimTests`, `RitimUITests` | Birim ve kullanıcı akışı testleri |
| `scripts` | Demo/ikon üretimi ve geliştirme Asistan eşleştirmesi |
| `server` | Önceki sürümün yt-dlp/FFmpeg Mac servisi; v1.6 uygulama akışında kullanılmaz |

`server` klasörü geçmiş kaynak olarak korunur; normal kullanım için kurmak veya başlatmak gerekmez. Oradaki eski çalıştırma/test yönergeleri güncel iPhone akışını tarif etmez. Üç demo ses `scripts/generate_demos.py`, ikon `scripts/generate_icon.swift` ile üretilmiştir.

Bu sürüm Spotify katalog/hesap entegrasyonu, ekolayzır, crossfade, CarPlay veya App Store yayını içermez.

## 1.10 geliştirmeleri

- **İndir:** Aşama açıklaması, sıradaki işe öncelik verme, seçili işleri toplu iptal/yeniden deneme ve geçici ağ hatalarında en fazla üç otomatik deneme. Doğrudan medya aktarımında alınan/toplam byte gösterilir. YouTube ilerlemesi kaynak ve dönüştürmeyi kapsayan genel işlem ilerlemesidir.
- **Kitaplığım:** Türkçe çok sözcüklü arama, tür ve kaliteyi birlikte filtreleme, toplu beğeni ve sanatçı/albüm düzenleme. Boş düzenleme alanları mevcut bilgiyi korur. Listeler sabitlenebilir, adı/açıklaması düzenlenebilir ve bir parçanın kapağı liste kapağı seçilebilir.
- **Ara:** Parça sonuçlarının yanında sanatçı, albüm ve liste sonuçları. Sekme/tema değişiminde arama ve kitaplık seçimleri saklanır.
- **Çalma sırası:** Arama, filtrelenen sonuçlardan doğru parçayı silme, çalan parçayı koruyarak diğerlerini temizleme. Uyku zamanlayıcısı kalan süreyi gösterir. Ses oynatması gerçekten ilerlemiyorsa tek kurtarma denemesi yapılır; kullanıcı duraklatması ve sistem kesintisi sırasında otomatik başlatılmaz.
- **Asistan:** Öneri kartındaki “Bu parçaları tekrar önerme” tercihi cihazda saklanır; Ayarlar’dan sıfırlanabilir.
- **Ayarlar → Yedek ve bakım:** Bilgi yedeği veya medya dahil `.ritimbackup` dosyası oluşturma, Dosyalar'a kaydetme, doğrulanmış yedeği mevcut kitaplığa birleştirme ve eksik/olası yinelenen dosya denetimi. Tam yedek medya, mevcut kapak ve kayıtlı söz dosyalarını kapsar. Bilgi yedeği başka cihazda medya oluşturmaz. Anahtarlar, Asistan bağlantısı ve indirme geçici dosyaları pakete alınmaz. Mevcut listeler/tercihler üzerine yazılmaz. Paket uygulamaya özel biçimdedir, ZIP değildir.

Son doğrulama ve açık kabul maddeleri: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md).
