# Asistan

Türkçe sesli iPhone asistanı. CLIProxy'nin canlı model listesinden Claude, ChatGPT/Codex ve Gemini modelleri seçilebilir; bağlıysa Grok da listelenir. Telefon ve belge işlemleri için yerel araçlar, kaynaklı araştırma için web aracı kullanır. iOS 27 ve üstü.

## Kullanım

1. iPhone'da CLI Proxy hesabının bağlı olması gerekir. Asistan aynı Keychain grubunu okur; anahtar kopyalamaya gerek yoktur.
2. Asistan'ı aç, **Konuşmaya başla** düğmesine bas ve mikrofon/konuşma izinlerini ver.
3. “YouTube'u aç”, “5 dakikalık zamanlayıcı başlat”, “Pilimin durumu nedir?”, “Yarın saat dokuzda su içmemi hatırlat” gibi komutlar söyle.
4. Ayarlar'dan **Sürekli konuşma** açılırsa yanıtın ardından yeniden dinler. Dinleme düğmesiyle kapatılır.
5. **Telefon işlemleri** ekranında herhangi bir uygulamaya veya otomasyona Kestirme bağlanabilir. Kestirmeler'de akış önce oluşturulmalı; uygulamadaki eşleştirme kendiliğinden kestirme kurmaz.
6. Siri'ye **“Asistan ile konuş”** de veya Kontrol Merkezi'ne Asistan kontrolünü ekle. iPhone 15'te Action Button yoktur; Arkaya Dokun ile kestirme atanabilir.
7. **Atölye**: Sesli asistan, Araştırma, Kod yardımcısı ve Yazı atölyesi kipleri. Uzun yazı/kod yanıtları otomatik seslendirilmez; kopyalanabilir ve paylaşılabilir.
8. Sohbette **+**: DOCX, XLSX, PPTX, PDF, metin, CSV, JSON veya kod dosyası ekle. PDF'de ilk 20 sayfa ve 50.000 karakter, dosyada 20 MB sınırı vardır. Metni olmayan PDF sayfaları cihazda OCR ile okunur. Bir ofis dosyasını ekleyip istediğin değişikliği yazarsan özgün dosyayı koruyarak yeni kopya üretir. Fotoğraf/kamera desteği ayrıca bulunur.
9. **Atölye → Sohbet arşivi** geçmiş sohbetleri açar ve başlıkla arar. **Görsel üret** modelin desteklediği görsel uç noktasını çağırır; erişim ve kota gerekir.
10. **Menü → Gelen Kutusu**: **Kestirmeler Otomasyonlarını aç** ile iOS'un kişisel otomasyon ekranına geç. Bu iPhone'da WhatsApp, Mail ve Mesajlar bildirim otomasyonları kurulmuş ve etkinleştirilmiştir. Kaynak adı istemeyen ayrı hazır kayıt eylemleri; diğer uygulamalar için genel **Gelen iletiyi kaydet** eylemi vardır. Aktarılan iletiler aranır, sesle okunur/özetlenir ve yanıt taslağına çevrilir. Eski içerikler Kopyala/Paylaş ile eklenir.

### Mikrofon ve ekran yansıtma

Bu iPhone 15 / iOS 27.0.1'de Device Hub ekran paylaşımı açıkken mikrofon izni açık olmasına rağmen bütün ses örnekleri sıfır geldi. Paylaşım durdurulduktan sonra aynı uygulama ve aynı giriş gerçek ses almaya başladı. Sesli kullanımda Mac'teki ekran yansıtmasını kapalı tutun. Tam sıfır giriş 4 saniye sürerse Asistan dinlemeyi durdurup açıklama ve **Mikrofonu yeniden başlat** düğmesini gösterir. Normal oda sessizliği ve düşük ses bu hatayı tetiklemez.

## Bağlantı

`../cliproxy-ios/ProxyKit` uygulamanın içinde çalışır. CLI Proxy ve İkra'nın ortak Keychain grubundaki hesapları kullanır; CLI Proxy uygulamasının ön planda kalması gerekmez. Yerel HTTP köprüsü yalnız `127.0.0.1:18317` üzerinde, kimlik doğrulamayla dinler. Model çağrıları internet gerektirir; bu kurulum cihaz içi LLM değildir. Sunucu yenileme/yedek davranışı mevcut CLI Proxy ayarlarından gelir.

Hiçbir API anahtarı Info.plist'e veya kaynak koda gömülmez. Eski Secrets.xcconfig artık derlemeye dahil değildir. Ayarlar'daki bağlantı sınaması yalnız model listesini doğrular; gerçek model ve araç sınaması ayrı yapılır.

## Yapabildikleri ve sınırlar

Saat, takvim listeleme/ekleme, hatırlatıcılar, kişiler, arama/mesaj taslağı, harita, hava durumu, müzik, alarm/zamanlayıcı, el feneri, parlaklık, pil/depolama, HomeKit, fotoğraf yorumlama, hafıza, Kestirmeler ve otomasyonla aktarılan bildirim/ileti gelen kutusu.

iOS izinleri gerektiğinde istenir. Diğer uygulamaların arayüzünü serbestçe yönetemez, korumalı verilerini okuyamaz, kapalıyken özel bir uyandırma kelimesi dinleyemez. Bildirim Merkezi geçmişini veya WhatsApp/Mail özel gelen kutularını topluca tarayamaz; yalnız kullanıcının seçtiği Kestirmeler otomasyonunun yeni olayda aktardığı ya da Paylaş/Kopyala ile verilen metni görür. Arama/mesaj kullanıcı onayıyla ilerler. Kullanıcının tercihiyle URL, video, uygulama ve kestirme açmada ek uygulama onayı yoktur. URL açma başarısı, kestirme içindeki işin tamamlandığı anlamına gelmez.

Model erişimi, ChatGPT/Grok/Gemini/Claude Code ürünlerindeki bütün abonelik özelliklerini sağlamaz. Kodlama otomatik VPS CLIProxy’ye yönlenir; Python standart kütüphanesi ağsız, salt okunur, süre/bellek sınırlı Docker ortamında çalıştırılır. Diğer diller yalnız kod üretir. Web aracı, CLIProxy üzerinden ChatGPT Responses bağlantısıyla araştırma yapar; açık araştırma isteği sonuçları doğrudan kaynaklarıyla gösterir; karma telefon komutlarında sohbet modeli web aracını kullanır. Sağlayıcıdan gerçek web çağrısı ve kaynak bağlantısı gelmedikçe sonuç doğrulanmış sayılmaz. Claude sunucu web aracı bu hesapta boş yanıt/zaman aşımı verdiği için devre dışıdır. Grok için mevcut CLIProxy hesabında model görünmelidir. E-posta, X ve Drive gibi hesaplara kendiliğinden erişim yoktur.

Bağlantı düzeltmeleri `../cliproxy-ios/ProxyKit` içindedir: OpenAI'nin Anthropic uyumlu araç istekleri Responses API'ye çevrilir; Gemini araç imzası yalnız işlem belleğinde, model ve çağrı kimliğiyle saklanıp bir sonraki turda geri iletilir. Gizli imzalar günlük/disk kaydına yazılmaz. İmza önbelleği sınırlıdır; eski çok uzun oturumlarda yeni sohbet gerekebilir.

## Geliştirme

`~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate`

`xcodebuild -project Asistan.xcodeproj -scheme Asistan -destination 'platform=iOS Simulator,name=Ikra Tasarim' -collect-test-diagnostics never test`

Telefona kurulum: `./telefona-kur.sh`. Debug açılış argümanı `--asistan-sinama`, ortak hesaplarla gerçek model/araç sınaması yapar; kişisel hafızayı değiştirmeden sonucu `Documents/asistan-sinama.json` dosyasına yazar. Bu sınama model kullanım kotası tüketebilir.

Ek geliştirme sınamaları: `--asistan-modeller-sinama` her model ailesinden bir adayın gerçek saat aracını; `--asistan-atolye-sinama` sohbet üzerinden araştırmayı ve bir görsel üretimini sınar; `--asistan-web-yeni` web bağlantısını doğrudan sınar. Sonuçlar aynı adlarla uygulamanın Documents klasörüne JSON olarak yazılır. Kişisel sohbet ve hafızayı değiştirmezler.

Kaynak yedeği ve doğrulama: `verification/20261018/`. Eski `PLAN.md`, 14 Ekim tasarım notudur; güncel bağlantı yukarıdadır.

## Mehmet Asistan 0.4.0

- Uygulama adı ve özgün M simgesi yenilendi.
- Atölye varsayılan olarak otomatik: yazılı/sesli isteğin anlamına ve devam bağlamına göre sohbet, kod, yazı, araştırma veya görsel ekranını seçer. Elle seçim korunur.
- Ayarlar > Dostunu kişiselleştir: ad ve dört konuşma tarzı. Mevcut hafıza ve sesli sohbet devam eder.
- Telefon işlemleri: telefon/FaceTime açılışı; uygulama içi sistem SMS/iMessage taslağı ve gerçek gönder/iptal sonucu; WhatsApp ülke kodlu alıcı ve URL kodlanmış hazır metin. WhatsApp son Gönder adımı kullanıcıdadır. Gelen mesajlar otomatik okunmaz; kullanıcı metni/görüntüyü paylaşabilir.
- Gelen hücresel aramayı uygulama devralmaz; Siri Aramaları Duyur ve erişilebilirlik ayarlarının kurulum yolu gösterilir.
- Hava durumu artık saatlik sıcaklık/yağış/rüzgâr kartı ve kaynak/zaman etiketiyle gösterilir.
- Kullanılan araçların başlama/yanıtlama/hata/durdurma durumu işlem günlüğünde görünür. Araç yanıtı dış işlemin tamamlandığı anlamına gelmez.
- Ana kullanım iPhone'da, isteğe bağlı uzun işler Atölye > Sunucu görevleri üzerinden mevcut VPS'te sürer. Metin, kaynaklı araştırma, kod üretimi ve izole Python çalıştırma; genel terminal ve push yok. [Servis ayrıntıları](vps/asistan-jobs/README.md).
- Grok hesabı yok; önceki canlı görsel denemeleri kota/erişim hatası verdi. Video üretimi ve ürünlerin tüm kapalı araçları aktarılmış değildir.

## 0.4.1 ses ve gecikme

- Atölye sınıflandırması cihaz içinde; sınıflandırma için ayrı model isteği kaldırıldı. Kullanıcının açık model seçimi korunur.
- Azure HD Elif kadın sesi varsayılan. Ayarlar → Ses: İkra sunucusundan 111 bulut ses seçeneği ve kurulu Türkçe Apple sesleri. Katalog önbelleklenir. İkra'nın Piper/Supertonic indirilebilir modelleri bu sürüme taşınmadı.
- Bulut TTS mevcut İkra servisi üzerinden kimlik doğrulamalı `/v1/asistan/speak` ile cümle cümle oynatılır. Durdurmak bekleyen yanıtların sesini iptal eder. Azure sırası sunucuda ortaktır; Azure anahtarı telefona verilmez.
- Canlı Elif/Aydın ve ChatGPT Marin sesleri geçti. Chirp 502, Gemini 402 döndürdü; katalogda bulunmaları kullanılabilirlik garantisi değildir. Başarısız ses sessizce başka sağlayıcıya değiştirilmez.
- Anthropic thinking/redacted_thinking içerikleri VPS kanonik dönüştürücüsünde sıradan metne çevrilmeden atlanır; komşu araç çağrıları ve sonuçları korunur.

### Kullanıcının son model tercihi

Son tercih (18 Ekim 2026): modele göre sabit Opus zorunluluğu kaldırıldı. Ayarlar → Model → İşe göre otomatik model varsayılan açık. Claude, ChatGPT ve Gemini arasında isteğin zorluğu/türü, gerçek ilk yanıt süreleri ve kota/erişim beklemesi değerlendirilir. Kolay iş havuzu Haiku/Sonnet/GPT/Flash; zor iş havuzu Opus/GPT/Pro. Çeviri/görsel Gemini, matematik/kod GPT önceliği taşır; ölçülen hız seçim puanını değiştirir. Kesin kalite garantisi değil, yerel kurallardır. Günlük işler iPhone CLIProxy, kodlama sunucu CLIProxy kullanır. Kalan kota yüzdesi bildirilmezse tahmin edilmez; gerçek 429, sağlayıcı hesap bekleme süresi ve geçici erişim hataları kullanılır. Model değiştirmek için ayrı ağ isteği yoktur.

## 0.5.0 · Hey Asistan ve uygulamalar arası erişim

- Uygulama ön plandayken varsayılan açık yerel uyandırma: “Hey Asistan” veya “Hey Asistan, komut”. Başında tam ifade olmayan sesler modele gönderilmez. Ayarlar > Tetikleyiciler > Hey Asistan ekranından kapatılır; mikrofon düğmesi oturumluk beklemeyi durdurur. Arka plana geçerken yalnız uyandırma dinleyicisi kapanır.
- iOS Sesli Kestirmeler için kurulum rehberi eklendi. Başka uygulamadayken sistemin ifadeyi dinlemesi, kullanıcının Ayarlar > Erişilebilirlik > Sesli Kestirmeler'de kendi sesiyle kurulum yapmasını gerektirir. Eylem: Asistan'ı başlat veya Siri İsteği “Mehmet Asistan ile konuş”; ifade: “Hey Asistan”. Siri'nin özel sistem yetkileri veya diğer uygulamaların üzerine serbest pencere sağlanmaz.
- `AsistanaAktarIntent`: Kestirmeler/Paylaşım kestirmesinden metni Asistan taslağında açar; harici URL içeriği kendiliğinden komut olarak yürütülmez. Asıl Paylaş menüsü kestirmesini kullanıcı kurar; bu native Share Extension değildir.
- Güncel iPhone kataloğu 66 model; Grok sohbet modeli ve GPT-4o sohbet modeli yok (`gpt-4o-mini-tts` yalnız ses modelidir). Grok Bot/Dost ürününün özel hesap/araç hakları kopyalanmış değildir. Sesli sohbet, hafıza, belge/fotoğraf analizi ve araştırma mevcut uygulama işlevleridir.
- Doğrulama: 79 toplam test (10 canlı/donanım koşullu hariç); uyandırma ifadesi ayrıştırma 3 yeni test. Cihazda model kataloğu ve ayrıştırma doğrulandı. Gerçek “Hey Asistan” mikrofon tetiklemesi ve OS Sesli Kestirmeler kaydı kullanıcı sesiyle henüz doğrulanmadı. Simülatör harici URL açılışı sistem onayında kaldı; paylaşım uçtan uca kanıtı sayılmaz.

## 0.5.1 · Her çağrıda tek komut

- “Hey Asistan” öncesinde yalnız cihaz içi uyandırma algılaması yapılır. Bekleme konuşmaları komut olarak gönderilmez, ekranda veya tanı kayıtlarında yazıya dökülmüş olarak gösterilmez. Enerji denetiminin geçici ses tamponu en fazla 3 saniyedir; dinleme kapanınca temizlenir.
- Uyandırma sonrası tek komut kabul edilir. Yanıt sonrasında yeniden uyandırma beklenir; eski sürekli konuşma ayarı bu akışı açamaz. 12 saniye yeni konuşma sonucu gelmezse komut penceresi kapanır. Arka plana geçerken bekleme ve açık komut penceresi kapanır.
- Uyandırma akışındaki ses tamponu Whisper'a gönderilmez: yalnız cihaz içi Apple metni komut olur. Elle mikrofonla başlatılan akışta seçili Whisper seçeneği kullanılabilir.
- Eski sürekli konuşma ayarı bir kez kapatılır. Kullanıcı bunu sonradan elle başlatılan konuşmalar için tekrar açabilir.
- Mikrofon hatası bekleme durumunu da kapatır; yinelenen veya kapandıktan sonra gelen konuşma sonuçları komut başlatmaz.
- Doğrulama: 86 test, 10 canlı/donanım koşullu atlandı; kalan 76 geçti. iPhone derleme, yükleme ve ekran paylaşımı olmadan gerçek mikrofon sinyali doğrulandı. Kullanıcının sesiyle uyandırma/tek komut kabul testi sonucu ayrıca bekleniyor. Kanıt: `verification/20261018-single-command/`.
- Device Hub/iPhone ekran paylaşımı kullanıcının açık izni olmadan açılmaz.

## 0.6.0 · Mercan küre ve Live

- Referans görünüme uygun beyaz ana ekran, sade menü/ayarlar düğmeleri, mercan küre ve alt giriş kapsülü. Sohbet başladığında küre alt tarafa küçülür. Atölye, geçmiş, telefon işlemleri ve dosya/fotoğraf ekleme menülerden erişilebilir.
- Küre yüzeyi Canvas/TimelineView ile hareket eder. Dalga büyüklüğü komut dinlerken gerçek mikrofon dB değerinden, Azure/bulut yanıtı oynarken AVAudioPlayer ölçümünden gelir. Beklemede yalnız dekoratif yavaş hareket; ortam sesi ekrana yazılmaz. Hareketi Azalt ve arka plan durumu gözetilir. Apple sistem TTS için çıkış dB ölçümü yoktur; konuşma hareketi gösterilir.
- Giriş alanındaki mercan dalga düğmesi **Live** açar. Opus 5.5 + Azure Elif ile yanıt sonrası mikrofon yeniden açılır, konuşma bağlamı korunur. Live sırasında sesli yanıt ayarı kapalı olsa da seslendirilir. Konuşma sonu beklemesi 800 ms; kısa sesli yanıt istemi kullanılır. `Söz al` yanıtı kesip mikrofonu açar. Bu akış sıralı STT/metin/TTS'dir; eşzamanlı konuşarak söz kesme henüz yoktur.
- Mikrofon/kapat düğmesi Live'ı kapatır; kendiliğinden tekrar açmaz. Uygulama arka plana geçince Live kapanır. Live kapalıyken “Hey Asistan” tek komut akışı korunur. `asistan://live` açık bir Live başlatma isteğidir.
- Mikrofon yeniden başlatması eski SpeechAnalyzer kapanışını bekler. İptalde tamamlanmamış metin işlenmez; eski sonuçlar nesil denetimiyle reddedilir. Böylece önceki kapanışın yeni açılan dinleyiciyi kapatması engellenir.
- 86 test: 76 geçti, 10 canlı/donanım koşullu atlandı. İki sabit girişli gerçek iPhone/Opus/Azure turunda bağlam korundu, ses çıktı ve mikrofon yeniden açıldı. İlk sesler 4.03/3.00 sn; toplam 7.08/4.99 sn. Bu süreler test örneğidir, hız garantisi değildir.
- Fiziksel ses tanıma denemesinde beklenen test kaydı yerine mikrofondan “Beni duyuyor musun” tanındı ve gerçek sesli yanıt sonrası dinleme açıldı; kontrollü iki turlu ses kabul testi sayılmaz. Kullanıcı “Hey Asistan” denemesinin çalışmadığını bildirdi; son mikrofon yaşam döngüsü düzeltmesinden sonra kişisel uyandırma henüz doğrulanmadı.
- Görsel kontrol: simülatörde `verification/20261018-coral/home.png` ve `chat.png` (sohbet görseli yalnız DEBUG önizleme verisi). Fiziksel iPhone ekran paylaşımı açılmadı.

## 0.6.1 · Azure ve ses ön hazırlığı

- Kullanıcı EMA geçişinden vazgeçti; Azure HD Elif seçili kaldı. Güncel aynı cümleli sunucu kontrolünde Azure 0.914 sn, Chirp Kore 1.037 sn ve ikisi de başarılı. Bu tek örnek sağlayıcı ölçümüdür.
- Konuşma sürerken en fazla bir sonraki ses parçası hazırlanır. Tamamlanma denetimi hazır parçayı da kapsar; durdurma hem bekleyen üretimi hem hazır parçayı iptal eder. Azure sunucu genelindeki tek sıra değişmedi.
- 0.6.1 build 11 fiziksel iPhone'a yüklendi, testten sonra normal uygulama açıldı. 86 test: 76 geçti, 10 koşullu atlandı. Gerçek cihaz Azure denemesi: 2 parça oynatıldı, 1 geçişte sonraki ses hazırdı, hata yok; ilk ses 1.810 sn. Bu TTS testinde model yanıt süresi yoktur; toplam konuşma gecikmesiyle karıştırılmamalıdır.
- Kanıt: `verification/20261018-voice-speed/providers.json`, `phone-result.json`, `tests.log`, `final-launch.log`.

### 0.7.1 · Otomatik model vitesi ve hız

- Telefon model seçimi `ModelVitesi`: çaba düzeyine ayrı gecikme ortalaması; hesap/token içermeyen yerel istatistik; kalıcı model bekleme süreleri. Elle seçim kapatılmaz. En çok üç deneme; yanıtın bir kısmı görünmüşse veya herhangi bir telefon aracı başlamışsa otomatik yeniden yürütme yoktur.
- Araştırma doğrudan streaming Responses web_search kullanır. Deltalar ve `response.output_item.done` desteklenir; boş final output varsa tamamlanmış öğeler birleştirilir. Gerçek tamamlanmış arama ve kaynak olmadan başarı verilmez. Tam araç geçmişi sonraki modele taşınır. Live araştırma sesi doğrulama bittikten sonra okunur; kaynak URL'leri seslendirilmez.
- Tam “Saat kaç?” sorusu cihaz saatinden gelir; karma/şehirli sorular araçlı modelde kalır. Yazılan mesajların sesli yanıtı da cümle akışıyla başlar. Azure HD Elif korunur.
- VPS kodlama normalde GPT-6 Luna, yüksek çabada GPT-6 Astra; uygun Claude/Gemini yedekleri. Sunucuda GPT-6.1 Sol API sağlayıcısına yönlendiği için Codex native reasoning kontrolü bu modelde kullanılamaz; paylaşılan başka uygulamaların routing ayarları değiştirilmedi. Runner başarısızlığı model yeniden denemesini tetiklemez.
- Kanıtlar: `verification/20261018-speed-routing/`. Model karşılaştırması küçük sabit örneklerdir; uzun görevlerde aynı hız veya eşdeğer yanıt kalitesi garantisi değildir. Fiziksel ekran paylaşımı açılmaz.

### 0.8.0 — Uygulama köprüsü ve Dosyalarım

Menü → Telefon işlemleri → Telefondaki uygulamalar: 18 Ekim 2026 cihaz listesindeki 86 uygulama, tek imzalı `Mehmet Uygulama Koprusu` kestirmesiyle açılır. Bu iPhone'da köprü kuruldu ve etkinleştirildi. Yeni kurulumlarda aynı ekrandan dosyayı Kestirmeler’e eklemek ve kuruldu işaretini açmak gerekir. Yeni yüklenen uygulamalar mevcut elle kestirme bağlama alanından eklenir. Uygulama içinde serbest ekran otomasyonu sağlamaz; özel işlemler Uygulama bağlantıları alanında uygulamanın desteklediği Kestirme eylemine bağlanır.

Dosyalarımda ara → Klasör bağla: Dosyalar/iCloud Drive'da seçilen klasörlerin ad ve metin/PDF içeriği yerel aranır, sonuçlar önizlenir. Sohbette `Dosyalarımda kalıtım ara` veya bulunan belgeyi özetleme isteği kullanılabilir. Klasör bağlantısını kaldırmak belgeyi silmez. İçerik/dosya/sayfa sınırları ekranda gösterilir; indirilmemiş ve taranmış PDF içerikleri aranmaz. WhatsApp gönderim köprüsü isteğe bağlı mevcut bir kestirmeye bağlanır; bağlı değilse hazır sohbet ekranında kullanıcı Gönder’e dokunur.

Kabul kanıtı: `verification/20261018-app-files/RESULT.md`.

### 0.9.0 — Sade ses modları

Ana ekrandan **Normal / Eller serbest / Live** seçilir. Normal'de yuvarlağa dokun, konuş, tekrar dokunarak gönder. Eller serbest uygulama ön plandayken “Hey Asistan” ile tek komut alır. Live konuşma sonunu otomatik algılar ve sesli yanıt sonrası yeniden dinler. Her modda konuşma sırasında yuvarlak gönderir; yanıt sırasında dokunmak sözü kullanıcıya geçirir. X oturumu durdurur. Başka uygulamadan sesle açmak için iOS Sesli Kestirmeler kurulumu ayrı kalır.

Kabul kanıtı: `verification/20261018-voice-modes/RESULT.md`. Kontrollü gerçek mikrofon/test sesiyle iki Live turu ve Hey Asistan uyanması geçti; kullanıcının kendi sesiyle kabul ayrı doğrulanmalı.

### 0.10.0 — iPhone indirmeleri ve Kepçe

Menü → **İndirmeler** (veya mesaj yanındaki + → Bağlantı indir): HTTPS bağlantısı, Dosya/Video/Ses seçimi. Doğrudan dosya ve medya URL'leri iOS arka plan URLSession ile Asistan'ın Documents/Indirmeler alanına iner; ilerleme, iptal, yeniden deneme, Quick Look ve Kaydet/paylaş bulunur. En fazla 10 etkin iş ve dosya başına 1 GB. Liste kalıcıdır; tamamlanan indirmeyi kaydırarak silmek yerel kopyayı da siler. Uygulamayı zorla kapatma iOS aktarımını kesebilir. Duraklat/devam ve çok parçalı IDM hızlandırması bu sürümde yoktur.

Web sayfası/YouTube video ve ses istekleri, kurulu **Kepçe** uygulamasına `kepce://indir?url=…&tur=video|ses` ile aktarılır. Kepçe'nin mevcut gömülü Python/yt-dlp/JavaScriptCore ve yerel aktarım motoru kullanılır; Asistan içine motor kopyalanmadı. İndirme ve dosya kütüphanesi Kepçe'dedir. Asistan, aktarım kaydını tamamlanmış indirme olarak göstermez. Kepçe kurulu değilse uygulama içi WebKit sayfasından erişilebilir doğrudan medya URL'leri bulunabilir; parçalı/korumalı akışlar bu basit yedekte desteklenmez.

**İndirme için VPS/CLIProxy veya başka indirme sunucusu kullanılmaz.** İçerik kaynağına iPhone bağlanır. Sesli komutların normal model işlemesi mevcut asistan model yönlendirmesine tabidir. `indirmeler` aracı ekle/listele/iptal/ac işlemlerini sunar. Örnek: “Bu bağlantıyı video olarak indir: …” veya “Bu bağlantının sesini indir: …”. Her site ve her YouTube içeriği için başarı garantisi yoktur; site/motor hatası Kepçe'de görünür.

### 0.11.0 — iPhone web veri çıkarma

İndirmeler ekranındaki **Bu web sayfasından veri çıkar** seçeneği sayfayı geçici, uygulama içi tarayıcıda açar. Başlık/açıklama, görünür metin, bağlantı, görsel, doğrudan ses-video, belge, altyazı, tablo satırları ve JSON-LD verileri çıkarılır. Sonuçlar tür ve sözcükle filtrelenebilir; seçilen en fazla 10 doğrudan dosya iPhone indirme kuyruğuna eklenebilir. Tüm rapor JSON veya CSV olarak Dosyalar'a kaydedilip paylaşılabilir. Bir taramada en fazla 1.200 öğe ve 2 MB sonuç işlenir.

Bu özellik iPhone üzerinde çalışır ve indirme sunucusu kullanmaz. Sayfanın tarayıcıya yüklediği veriyi okur; başka sayfalara kendiliğinden gitmez, oturum/DRM/CAPTCHA aşmaz ve parçalı medya akışını birleştirmez. Dinamik sayfalarda kullanıcı içeriği yüklemek için sayfayı kaydırıp yeniden tarayabilir. YouTube ve desteklenen medya sitelerinde video/ses indirme Kepçe üzerinden devam eder.

Doğrulama: `verification/20261018-downloads/`. Fiziksel ekran paylaşımı kullanılmadı.

### 0.12.0 — Ofis dosyaları ve hızlı katalog Excel'i

- Sohbetten gerçek DOCX, XLSX, PPTX ve PDF; ayrıca TXT, Markdown, CSV ve JSON oluşturulur. Çıktılar iPhone'daki **İndirmeler** ekranına eklenir; Quick Look ile açılır ve Dosyalar'a kaydedilip paylaşılabilir.
- **+ → Ofis, PDF, metin veya kod ekle** ile DOCX/XLSX/PPTX/PDF okunur. İstenen düzenleme yeni dosya olarak üretilir; özgün dosyanın üzerine yazılmaz. Parolalı/eski DOC-XLS-PPT biçimleri önce güncel biçime dönüştürülmelidir.
- “Kitapyurdu'da Simyacı'nın bütününü bul Excel dosyasında ver” isteği genel web modelini beklemeden iPhone'da salt okunur katalog taraması yapar. Fiziksel kabulde 40 ürün, başlıkla 41 XLSX satırı ve 40 gerçek bağlantı doğrulandı.
- 0.12.0 build 20 fiziksel iPhone'a kuruldu. 126 birim test geçti. DOCX/XLSX/PPTX ZIP bütünlüğü, PDF imzası ve cihazda dört biçimin yeniden okunması doğrulandı. Ekran paylaşımı açılmadı.

Kabul kanıtı: `verification/20261018-office/` ve `verification/20261018-last-request-fix/`.

### 0.12.1 — Dosyalar arası dönüşüm

Menüden veya **+ → Dosyayı başka biçime dönüştür** yolundan kaynak dosyayı seçip DOCX, XLSX, PPTX, PDF, CSV, Markdown, TXT ya da JSON hedefini seçebilirsin. Dönüşüm iPhone üzerinde yapılır, özgün dosya korunur ve sonuç İndirmeler'e eklenir. Word/PDF/PowerPoint → Excel dönüşümünde paragraflar numaralı satırlara; Excel → Word/PDF/PowerPoint dönüşümünde okunabilen hücreler belge içeriğine çevrilir. Sohbete bir dosya ekleyip “Excel'e dönüştür” gibi bir komut vermek de desteklenir.

Karmaşık sayfa tasarımı, makro, animasyon, formül, gömülü medya ve özgün yazı tipi görünümü biçimler arasında birebir taşınmaz. Güncel DOCX/XLSX/PPTX biçimleri kullanılır; eski veya parolalı dosyalar önce dönüştürülmelidir.

Fiziksel iPhone kabulünde DOCX→XLSX/PDF/PPTX/CSV ve XLSX→DOCX çıktılarının beşi de üretildi ve tekrar okundu. 0.12.1 build 21 kuruldu; 127 test geçti. Kanıt: `verification/20261018-office/conversion-device-result.json`.

### 0.13.0 — ZIP ve RAR

Menüden veya **+ → ZIP oluştur veya RAR aç** yolundan arşiv ekranı açılır. ZIP dosyaları oluşturulur ve açılır; RAR4/RAR5 dosyaları, isteğe bağlı parolayla, iPhone üzerinde açılır. Çıkarılan dosyalar Quick Look ile görüntülenip paylaşılabilir. Yol geçişi ve sembolik bağlantı reddi, 1.000 öğe ve 1 GB açılmış veri sınırı uygulanır.

RAR oluşturma uygulamada yoktur. RAR sıkıştırma algoritması kapalı/lisanslıdır ve UnRAR lisansı, kodun RAR uyumlu sıkıştırıcı üretmek için kullanılmasını yasaklar; oluşturma için ZIP kullanılır. Fiziksel iPhone gerçek ZIP üretip iki dosyayı geri açtı ve gerçek RAR5 örneğini çıkardı. Kanıt: `verification/20261018-office/archive-device-result.json`.

### 0.14.0 — Grok Bot benzeri uzmanlar, beceriler ve rutinler

**Atölye → Uzmanlar ve beceriler** bölümünde Araştırmacı, Yazar, Kodcu, Denetçi, Ofis Uzmanı ve Koordinatör hazırdır. En fazla 6 uzman birlikte seçilebilir; `@Araştırmacı` gibi bir etiket o isteği belirli uzmana yönlendirir. Özel uzman oluşturma, çoğaltma ve gizli bilgi içermeyen JSON profilini paylaşma vardır. Uzmanlar iPhone'daki aynı gerçek araç ve model yönlendirmesini kullanır; ayrı dış hesap veya erişim uydurulmaz.

Beceri kütüphanesi hazır ve özel tekrar kullanılabilir istemleri saklar. Zamanlanmış rutinler metin, kaynaklı araştırma veya kod işini 5 dakika ile 7 gün arasındaki aralıklarla mevcut özel VPS kuyruğunda çalıştırır; iPhone kapalıyken sürer, duraklatılır/sürdürülür/silinir ve sonuçları Sunucu görevlerinde görünür. Sesli/yazılı istekler `rutinler` aracıyla da yönetilebilir.

Rutin servisi canlı oluşturma/listeleme/duraklatma/silme kabulünden geçti. Fiziksel iPhone 6 uzmanı, 4 beceriyi ve rutin yaşam döngüsünü doğruladı. 132 iOS testi / 32 paket ve 13 sunucu testi geçti. 0.14.0 build 23 iPhone'a kuruldu; ekran paylaşımı açılmadı. Kanıt: `verification/20261018-office/grok-device-result.json` ve `all-tests-0140-final.log`.

### 0.16.0 — Sağlık ve hız merkezi

Ayarlar → **Sağlık ve hız merkezi**, iPhone CLIProxy, bağlı hesaplar, mikrofon izni, cihaz içi Türkçe konuşma tanıma, bulut ses kataloğu ve kodlama sunucusunu birlikte denetler. Modelin ilk metni ve toplam yanıtı, Whisper çözümü ve TTS üretimi için ortalama/p95 süre ile başarı oranını gösterir. En son 160 ölçüm cihazda tutulur; istem, yanıt, konuşma, kişi, hesap ve anahtar kaydedilmez.

### 0.17.0 — Gerçek zamanlı Live temeli

Live açıldığında uygulama önce kısa ömürlü sunucu anahtarıyla `gemini-3.8-live` WebSocket ses oturumunu dener. Mikrofon 16 kHz PCM olarak sürekli gider, modelin 24 kHz PCM sesi anında oynar; sunucu VAD konuşma sonunu ve araya girmeyi yönetir. Giriş/çıkış yazıları ve gerçek ses seviyeleri mevcut mercan kürede gösterilir. Kalıcı Gemini anahtarı iPhone'a konmaz. Live hesabı, kota veya endpoint hazır değilse çalışan sıralı STT → otomatik model → Azure Live akışı kendiliğinden kullanılır.

VPS endpoint'i dağıtıldı ve erişim denetimi doğrulandı. Gerçek Gemini Live için VPS environment'ında Gemini Live anahtarının bulunması gerekir; bulunmadığında geri dönüş akışı kullanılır. 0.17.0 build 27 fiziksel iPhone'a ekran paylaşımı açılmadan kuruldu. 138 iOS birim testi geçti. Kanıt: verification/20261018-v017/RESULT.md.

### 0.18.0 — Sistem girişleri

Kestirmeler ve Denetim Merkezi'nde Canlı konuşma, Atölye, indirmeler, telefon işlemleri, dosya dönüştürme ve arşiv için doğrudan açılışlar bulunur. Tüm girişler aynı asistan bağlantı yönlendiricisine gider; dışarıdan gönderilen soru yazı alanına taslak olarak gelir. Dinamik Mehmet Uygulama Köprüsü, Kestirme girdisindeki uygulama paket kimliğini Open App eylemine verir; Apple imzalı dosya uygulama içinde yeni kurulum için paylaşılabilir.

### 0.19.0 — Bağlantı merkezi

Telefon işlemleri → Uygulama bağlantıları, Uygulama Köprüsü, bağlı Kestirme sayısı ve WhatsApp gönderim köprüsünü birlikte gösterir. Aynı uygulama eylemini yeniden kaydetmek eski kaydı günceller. Bu durum yalnız Asistan'ın kayıtlı Kestirmeyi çağırabildiğini gösterir; üçüncü taraf uygulama içindeki işlemin bitişini veya özel verisini doğrulamaz.

### 0.20.0 — Kişisel alan yedeği

Kişisel Alan ekranından hızlı komutlar ve kaydedilen yanıtlar JSON dosyasına aktarılabilir veya geri yüklenebilir. Yükleme; sürüm, boyut, sayı, metin uzunluğu ve yinelenen kimlik sınırlarını doğrular. Geçersiz yedek mevcut içeriği değiştirmez. Sohbet geçmişi, hesaplar ve anahtarlar bu yedeğe dahil edilmez.

### 0.21.0 — Üretkenlik çalışma alanı

Menüden veya Üretkenlik Kestirmesinden dosya dönüştürme, ZIP/RAR ve sonuç dosyaları tek ekranda açılır. DOCX, XLSX, PPTX, PDF, CSV, Markdown, metin ve JSON dönüşümleri yerelde yapılır. Özgün dosyalar korunur; RAR açılır, RAR oluşturma için ZIP kullanılır.

### Build 33 — Antigravity Gemini Flash Live yedeği

Gerçek Gemini Live WebSocket hesabı yapılandırılmadığında Live modu, iPhone CLIProxy'de bağlı Antigravity hesabının `gemini-3.8-flash` yolunu ilk sırada dener. Erişim veya kota hatasında ölçülen hızlı yedek modele geçer. Gerçek iki yönlü ses WebSocket'i için Antigravity Code Assist metin akışı yeterli değildir; mevcut geçici Gemini Live anahtarı yolu yapılandırılırsa uygulama onu öncelikle kullanır.

Fiziksel iPhone'da sabit metinli Live kabulünde ilk tur Gemini 3.8 Flash ile 6,74 saniyede ilk sese ulaştı ve yeniden dinlemeye döndü. İkinci tur otomatik olarak GPT-6.1 Sol yedeğine geçti, 13,72 saniyede ilk sese ulaştı ve yeniden dinlemeye döndü. Bu, kullanıcı sesi veya tam çift yönlü Gemini Live kabulü değildir.

Build 35, yalnız uyandırma beklemesinde Apple Speech'in kısa ifade ön ayarını kullanır; normal ve Live diktesi değişmez. Fiziksel hoparlör testi mikrofonun canlı olduğunu ve beklemenin etkin kaldığını doğruladı, fakat tanıma yalnız “Asistan” döndürdü. “Hey” olmadan tetikleme eklenmedi; gerçek kullanıcı sesiyle kabul hâlâ gereklidir.

Build 38'de “Hey Asistan” için cihaz içi özel dil modeli eklendi. Fiziksel iPhone kontrollü testinde ifade eksiksiz tanındı, uyandırma penceresi açıldı ve mikrofon dinlemede kaldı. Bu sonuç hoparlör testidir; gerçek kullanıcının ses kabulü ayrıca yapılmalıdır.

### Live bağlantısı düzeltmesi

Uzak CLIProxy temel adresi zaten `/v1` içerdiğinde Live, görev ve rutin uç noktaları sürümü ikinci kez eklemez. Gemini Live geçici tokenı güncel `bidiGenerateContentSetup` şemasıyla sunucuda oluşturulur; iPhone ilk WebSocket mesajında `generationConfig.responseModalities` kullanır. Geçici token iPhone'a döner, kalıcı Gemini anahtarı dönmez. Sağlayıcı hesabında Live kotası yoksa uygulama hata vermeden sıralı Live'a döner.

### Build 40 — Live gecikmesi ve ardışık tur kararlılığı

Araç gerektirmeyen kısa Live sohbetleri doğrudan iPhone'daki ProxyEngine üzerinden Antigravity Gemini 3.8 Flash'a gider; yerel HTTP köprüsü, araç planlayıcısı ve ağır FoundationModels oturumu bu yolda beklenmez. İki hızlı sağlayıcı dört saniyelik sınırlar içinde yanıt vermezse 30 saniyelik ağır modele düşmek yerine kısa bağlantı yanıtı okunur ve mikrofon yeniden açılır. Telefon işlemleri, dosyalar ve kaynaklı araştırma araçlı akışta kalır.

SpeechAnalyzer kapanışı ana aktörü tutmaz; yeni dinleyici, normalde kısa süren önceki kapanışa en fazla 700 ms verir. Fiziksel iPhone kontrollü kabulünde iki ardışık tur Antigravity hesabıyla tamamlandı, bağlamdaki “mercan” doğru hatırlandı, ilk ses 3,41 ve 2,56 saniyede başladı ve iki turdan sonra mikrofon dinlemeye döndü. Ayrı uyandırma kabulünde ifade “Hey asistan” olarak tanındı, uyandırma beklemesi kapandı ve komut mikrofonu açık kaldı. Bunlar hoparlörle kontrollü cihaz testidir; kişisel ses ve başka uygulamadaki iOS Sesli Kestirmeler kaydı kullanıcı tarafından yapılır.

Son tam simülatör koşusunda 160 birim testi ile 7 arayüz testi geçti; 4 yalnız fiziksel kurulum testi atlandı. Güncel sürüm fiziksel iPhone'a ekran paylaşımı açılmadan kuruldu.

### Build 41 — Live zaman aşımı temizliği

Live hızlı yolunda sağlayıcı dört saniyede dönmezse kullanıcı akışı gecikmeden yedeğe geçer. Yanıt kapısı kapandıktan sonra artık kullanılamayacak ağ görevi de iptal edilir; bağlantı kesintilerinde 600 saniyeye kadar arkada istek birikmez. Taşıyıcıya iptal ulaştığını doğrulayan regresyon testi eklendi. Hızlı yanıt ve ses modu paketinde 24/24, fiziksel iPhone ses hattında 4/4 test geçti.

Build 41 fiziksel Live kabulünde iki ardışık araçsız konuşma Antigravity Gemini Flash ile tamamlandı. “Mercan” bağlamı ikinci turda korundu; ilk ses 2,99 sn ve 2,78 sn, toplam tur 6,17 sn ve 5,10 sn sürdü. Her iki turdan sonra mikrofon yeniden dinlemeye döndü. Kanıt: `asistan-live-sinama-latest.json`; sabit test metni kullanıldığı için gerçek kullanıcının konuşma tanıma başarısını temsil etmez.

Ek fiziksel uyandırma kabulünde test sesiyle “Hey Asistan” algılandı, uyandırma beklemesi kapandı ve komut penceresi açıldı. Bu yalnız uygulama ön plandayken çalışan mikrofon uyandırmasıdır; iOS'un uygulama dışı kişisel Sesli Kestirme kaydı kullanıcı tarafından Ayarlar'da tamamlanır.
