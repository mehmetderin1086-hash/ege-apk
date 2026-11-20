# Bilgi Arenası 2.7.0

Türkçe SwiftUI iPhone bilgi yarışması. iOS 18 ve üzeri. CLI Proxy iPhone uygulamasının bağlı hesaplarını kullanır. Reklam ve uygulama içi satın alma bulunmaz.

## Telefonda bağlantı

Bilgi Arenası, CLI Proxy'nin ortak Keychain kasasını okuyup aynı ProxyKit motorunu kendi uygulama sürecinde çalıştırır. CLI Proxy'nin arka planda açık kalması gerekmez. İstek yolu **iPhone → model sağlayıcısı**dır. Model bulutta çalışır; bu bir çevrimdışı dil modeli değildir.

Uygulamaya özel kasa görünümünde VPS adresleri, sunucu yedeklemesi ve sunucudan OAuth eşitlemesi kapalıdır. Ağ katmanı yalnız tanımlı sağlayıcıların HTTPS alan adlarına izin verir; yönlendirmeler reddedilir. Ortak kasanın sunucu ayarları değiştirilmez. Telefonun sahip olduğu OAuth oturumlarının yenilenen belirteçleri ortak güvenli kasaya yazılır. Eski sunucu yönetimli oturumlar geçerli olduğu sürece doğrudan kullanılır; süreleri dolarsa CLI Proxy uygulamasında telefondan yeniden giriş yapılmalıdır. Sağlayıcı kota ve yetkileri geçerlidir.

**Modeller** sekmesinden hesap ve model listesini yenile. Model veya aile adıyla ara, tek bir model seç veya model takımını kullan. Görsel, ses ve gömme modelleri katalogda ayrıca görülebilir; metin sorusu üreticisi olarak kullanılmaz. Gerçek küçük istekle tek model veya tüm metin modelleri test edilebilir; sonucun tarihi ve süresi gösterilir. Listelenmek kullanılabilir kota kanıtı değildir.

## Oyun ve öğrenme

- **Canlı sesli tur:** Soruyu ve şıkları dinle, yanıtını söyle. Yanıt 3 saniye gösterilir; iptal edip yeniden söyleyebilirsin. Sonuç/açıklama okunur ve sıradaki soruya geçilir. Ana ekranda **Canlı sesli yarışma → Canlı turu başlat**; açık bir turda **Bu turu sesli sürdür**.
- **Klasik:** 10 saniyelik sorular, puan/seri, 50:50, +15 saniye ve geçme jokeri.
- **Öğren:** Süresiz soru çözme, açıklamalar, bilgi defteri ve AI koç.
- **Hız Turu:** Soru başına 7 saniye.
- **Günün turu:** Gün için sabit 10 hazır soru.
- **Model takımı:** Seçilen modeller her beş soruda sırayla üretim yapar. Başarılı turlardan sonra başlangıç sırası ilerler; sonraki turlarda diğer modeller kullanılır. İlk 2.0 kurulumunda daha önce gerçek yanıt veren modellerden takım hazırlanır; kullanıcı seçimi korunur.
- **İkinci kontrol:** Üretimden ayrı bir model soruların tek doğru yanıt ve tutarlılık kontrolünü yapar. Onaylanmayan paket oynatılmaz. Bu işlem bağımsız kaynak doğrulaması değildir.
- **Üretimi sürdürme:** Her beş soruluk bölüm cihazda saklanır. İptal veya bağlantı hatasından sonra aynı konu/ayarlarla yeniden üretim başlatıldığında tamamlanan bölümler korunur.
- **Akademi:** Üretilen paketler otomatik kaydedilir ve çevrimdışı tekrar oynanır. JSON paketleri paylaşılabilir ve içe aktarılabilir.
- **Aralıklı tekrar:** Yanlış/boş sorular tekrar defterine girer. Doğru cevapla tekrar aralığı uzar; yanlış cevapla bir güne iner.
- **AI koç:** Cevaptan sonra daha basit açıklama, örnek, hafıza ipucu veya özel soru istenebilir.
- **İlerleme:** XP/seviye, rozetler, kategori başarısı, son oyunlar ve kaydedilen bilgi kartları.

Başlangıç havuzu dokuz kategoride, kolay/orta/zor seviyelerinde 174 hazır soru içerir. Manuel AI üretiminde 10/20/30 soru seçilebilir. Havuzdan oyunda kategori ve zorluk seçimi uygulanır; hiç oynanmamış, ardından en uzun süre önce oynanmış sorular önceliklidir. Doğru şıkkın yeri oynanırken yeniden karıştırılır. Bilgiler model tarafından yanlış üretilebilir; önemli bilgileri güvenilir kaynaklardan doğrula.

Arka plana geçişte oynanan tur duraklar; yeniden açılınca devam edilebilir. Manuel tur üretimi ve model testleri için uygulamayı önde tut. Günlük havuz üretimi ayrı bir BGProcessingTask isteğiyle planlanır. iOS uygulamayı askıya alırsa tamamlanan üretim bölümleri korunur.

## Her gün büyüyen soru havuzu

Ana ekrandaki **Büyüyen soru havuzun** veya **Akademi → Havuz** üzerinden izlenir. Kullanıcının onayladığı otomatik hedef **9 kategori × 50 = günde 450 yeni soru**dur. Bilim, Tarih, Coğrafya, Sanat, Spor, Genel Kültür, Sinema ve TV, Yabancı Dil ve Sınav Hazırlık kategorileri kullanılır. Her kategori kolay/orta/zor arasında 16–17 soruya bölünür; 16 soruluk seviyenin sırası günler arasında değişir. Karma, bu kategorilerin tamamından soru seçer; konusu belirtilmeyen Özel Konu günlük planda yoktur.

Üretim beş veya daha az soruluk paketlerle tek sırada ilerler. Tüm bağlı metin modelleri aileler arasında dönüşür; başarılı bağlantı kayıtları ve mümkün olduğunda ayrı yerel sağlayıcı hesapları önce kullanılır. Aynı model iki paralel günlük işte çalıştırılmaz. Hata veren model 30 dakika bekletilir ve sıradaki modele geçilir. Ortak hesap/provider kotaları ortadan kalkmaz. Oyun veya manuel üretim başlayınca günlük üretim bekler.

Her geçerli kısmi paket SQLite işleminde kalıcı yazılır; soru metninin normalize edilmiş benzersiz anahtarı günler arasında aynı sorunun yeniden eklenmesini engeller. Metin benzerliği kontrolü yakın kopyaları da azaltır; anlamsal tekrarları bütünüyle yakalama garantisi yoktur. Günlük sayımlar veritabanından okunur, kapatılıp açılınca tekrar sıfırlanmaz. Yeni gün yeni 450 hedefi başlatır; önceki gün eksik kalan kota birikerek büyümez. Önceki günlerin tamamlanmış soruları havuzda kalır. Günlük yapay zekâ soruları kaynak taraması veya bağımsız denetçi kontrolü yapılmış kabul edilmez.

Yabancı dil üretimi beş dili; sınav üretimi TYT, AYT, KPSS ve LGS ders konularını dönüşümlü kullanır. Havuzda metin arama, kategori/zorluk filtresi, cevabı açma ve deftere kaydetme vardır. **Sorunu işaretle** ile hatalı/belirsiz soru sonraki havuz, paket ve tekrar oyunlarından gizlenir; bildirimler yalnız cihazda tutulur ve Havuz ekranından geri alınabilir.

Arka plan isteği internet bağlantısı gerektirir; iOS uygun gördüğünde başlatır. Kesin saatte çalışma veya her gün 450 soruya ulaşma garantisi yoktur. Uygulama önde ve boşta olduğunda da devam eder. iOS süreyi bitirdiğinde iş iptal edilir, kaydedilmiş sorular korunur ve yeniden planlanır. Kullanıcı otomatik üretimi Havuz ekranından kapatabilir. Teknik dayanak: [Apple Background Tasks](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app).

Bu sürüm tek oyunculudur. Canlı eşleştirme, ortak oda ve bulut liderlik tablosu bulunmaz.

### 2.6 canlı sesli yarışma

Asistan uygulamasındaki ses yolları bu uygulamanın soru/puan motoruna uyarlandı:

- **Asistan · Sıralı sesli:** Ayarlardaki Azure Elif/Aydın, Google Chirp veya iPhone sesi soruyu okur; cihazdaki Whisper yanıtı çözer. Mikrofon kaydı sağlayıcıya gönderilmez. Bulut seslendirmede soru metni sağlayıcıya gider; iPhone sesi cihazda çalışır.
- **ChatGPT Realtime / Gemini Live:** CLI Proxy'nin iPhone ortak kasasındaki doğrudan sağlayıcı API hesabıyla WebSocket bağlantısı kurulur; VPS kullanılmaz. Bu seçeneklerde mikrofon sesi ilgili sağlayıcıya gider. OAuth metin aboneliğinin canlı ses API yetkisi verdiği varsayılmaz. Bağlantı veya ilk seslendirme başarısızsa sıralı yol açık bildirimle kullanılır.

Gerçek iPhone kontrolünde Chirp + Whisper aynı deneme turunu tamamladı. ChatGPT Realtime hesabı `credit_balance_exhausted`, Gemini Live ise WebSocket 1011 bağlantı kapanması döndürdü; bu iki yerel API yolu ses üretmiş sayılmaz. Güncel kanıtlar `VALIDATION.md` içindedir.

Tur kategori, zorluk, ders ve biçim filtreleriyle havuzdan açılır ve süresizdir. Dinleme/söyleme alıştırması, sıralama/eşleştirme ve görsellerin erişilebilir verileri seslendirmeye dahildir. Yanıtı uygulamanın mevcut doğru cevabı değerlendirir; canlı model puan veya çözüm üretmez. Söyleme alıştırması kelime eşleşmesidir, fonetik/aksan puanı değildir. Yabancı dil hedefi kendi dilinde okunur.

Sıralı modda konuşma sonrası yaklaşık 1,2 saniye sessizlikte kayıt tamamlanır; 6 saniye hiç ses yoksa tekrar istenir, kayıt en çok 12 saniyedir. Belirsiz/duyulmayan yanıt otomatik yanlış sayılmaz. `Tekrar oku`, `dur` ve `geç` komutları yanıt sırası açıkken anlaşılır. Okunurken **Durdur** düğmesi sesi keser; okuma sırasında sözlü araya girme bu sürümde etkin değildir. Mikrofon, sağlayıcı metnini okurken ağa gönderilmez. Arka plana geçiş turu duraklatıp sesi/mikrofonu kapatır; geri dönünce elle devam edilir. Mikrofon izni tur başlamadan önce istenir; izin sonrası yalnız uygulama öndeyse başlanır. Açık bir telefon/VoIP görüşmesi mikrofonu engelleyebilir.

Ses PCM altyapısı yerel Asistan kaynağındaki `Asistan/Ses/CanliSesIO.swift` üzerinden uyarlandı. Protokol referansları: [OpenAI Realtime](https://developers.openai.com/api/docs/guides/realtime), [Realtime konuşmaları](https://developers.openai.com/api/docs/guides/realtime-conversations), [Gemini Live](https://ai.google.dev/gemini-api/docs/live).

## Geliştirme

`BilgiArena.xcodeproj` hazırdır. `project.yml` XcodeGen kaynağıdır. Sabit ProxyKit kaynak kopyası `Vendor/ProxyKit` içindedir; kaynak bilgisi `Vendor/ProxyKit/ORIGIN.md` dosyasındadır. Hesaplar ve anahtarlar proje veya uygulama paketinde bulunmaz. Aynı geliştirme takımı ve ortak Keychain yetkisiyle imzalanmalıdır.

`scripts/pair.py DEVICE_UDID` yalnız uygulamayı açar. VPS yapılandırması veya anahtar aktarmaz. Ayrı bağlantı formuna gerek yoktur; CLI Proxy uygulamasında telefondan bağlı hesap olmalıdır.

Test kanıtları ve gerçek iPhone kabulü `VALIDATION.md` içindedir.

### 2.0.1 düzeltmesi

Eksik veya farklı JSON biçimindeki model yanıtında geçerli sorular korunur; eksikler aynı modelden sınırlı denemeyle tamamlanır. Aynı konu, zorluk ve soru sayısında model değiştirildiğinde de hazırlanan sorular kaybolmaz. Tamamlanamayan durumda kaç sorunun korunduğu belirtilir.

### 2.1 görsel yenileme

Lacivert geçişli zemin, kategoriye özel renkli kartlar, hareketli bilgi yörüngesi ve XP madalyonu eklendi. Soru ekranında süre halkası, cevapların sıralı girişi, doğru cevap parıltısı ve yanlış cevap sallanması bulunur. Yeni soruda ekran otomatik yukarı döner. Sonuç ekranı kupa, kısa konfeti ve artan puan sayacıyla açılır; yeni oyun düğmesi altta sabittir. Bilgi molası, Akademi ve rozetler aynı görsel dili kullanır.

Hareketi Azalt etkin olduğunda dekoratif hareketler, sallanma ve konfeti kapatılır. Yörünge çizimi ekran dışında veya uygulama arka plandayken durur; konfeti 2,8 saniye sonra biter. Çizimler SwiftUI/Canvas ile oluşturulur.


### 2.3–2.4 görsel sorular, süre ve ses

Şekil, resim, tablo, sütun grafik ve çizgi grafik soruları soru ekranında, havuzda ve kaydedilen paketlerde görüntülenir. **Görsel keşif turu** 12 örneği süresiz açar. Büyütme görünümünde 1–3 kat yakınlaştırılabilir; görseli incelerken oyun saati durur. Görsellerin metin açıklaması ve tablo/grafik verileri erişilebilirdir. Karma/Görsel/Metin seçimi yerel ve AI üretiminde çalışır. Bozuk veya eksik görsel verisi kabul edilmez. Günlük üretim görsel, dinleme, sıralama, eşleştirme, söyleme ve karma paketler arasında dönüşür.

Tablo, şekil ve grafikler veriden cihazda çizilir. Resimli sorular şimdilik üç özgün, uygulamaya gömülü fotoğrafı kullanır (keman, bisiklet, yaprak); çalışma anında sınırsız fotoğraf üretimi yoktur. Hepsi çevrimdışı açılır. [Görsel dosyaları, üretim yöntemi ve tam istemler](docs/QUESTION_IMAGES.md).

**Dakika Turu**: 1–30 dakika ortak tur saati. **Etaplı Tur**: soru listesini üç bölüme ayırır; Isınma, Odak ve Finalde metin sorularının varsayılan süresi 20/15/10 saniyedir. Etaplar zorluk seviyesini değiştirmez; seçtiğin seviyedeki sorularla oynanır. Geçişte bilgi molası açılır. Keşif, Kısa Tur ve Maraton düğmeleri hazır ayarları uygular: süresiz 10 soru, 2 dakika/10 soru, 10 dakika/30 soru ve etaplar. Havuzdaki uygun soru sayısı azsa tur kısalır.

**Süre ve ses ayarları** altında toplam dakika ve soru başına süre (5–120 saniyelik seçenekler) seçilir; moda göre süre seçeneği de vardır. Öğrenme daima süresizdir. Görseller için klasik/etaplı en az 25, hız turunda en az 15 saniye ayrılır. Toplam saat yalnız cevapsız soru açıkken işler; açıklama, mola, büyütme, duraklatma ve arka planda durur. Süre bitince o anki soru boş kaydedilir ve tur biter; görülmeyen sorular yanlış sayılmaz. +15 saniye jokeri mevcut saatleri bir kez uzatır. Saatler ve ayarlar cihazda saklanır; eski turlar okunur.

Yedi kısa ses efekti cihazda üretilir. Türkçe konuşmalı uyarılar isteğe bağlıdır; ses efektleri ve konuşma ayrı anahtarlardır. Başlangıç, doğru/yanlış, süre sonu, son beş saniye, etap/mola ve sonuç duyurulur. **Sesi dene** ayarları kontrol eder. Arka plana geçiş/duraklatma sesi keser. VoiceOver açıkken ek konuşma yapılmaz. Sessiz mod ve cihaz sesi [Apple ambient ses oturumu](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/ambient) kurallarıyla geçerlidir. Bunlar oyun içi uyarılardır; arka plan push bildirimi değildir. Dinleme ve söyleme soruları aşağıdaki ayrı oynatma akışını kullanır.


### 2.5 yeni soru türleri, cihazda Whisper ve dosya aktarımı

**Yeni soru türlerini dene** düğmesi 12 örnekle açılır: üç dinleme, üç sıralama, üç eşleştirme ve üç yabancı dil söyleme sorusu. **Soru biçimi** menüsünden her tür ayrıca seçilebilir. Dinleme sorusunda ses bitene veya erişilebilir metin açılana kadar saat ve seçenekler bekler. Tekrar dinlerken de saat durur. Sıralama ve eşleştirmede yanıtı tamamlayıp onaylarsın; yarım seçimler turla birlikte saklanır. Bu türlerde klasik/etaplı soru süresi en az 30, hız turunda 20 saniyedir.

**Sesli cevap ver** oyun saatini durdurup cihazdaki WhisperKit ekranını açar. İlk hazırlamada model mevcutsa kullanılır; yoksa yaklaşık 470 MB model indirilir. Model yüklendikten sonra sesin yazıya çevrilmesi çevrimdışıdır, CLI Proxy veya VPS üzerinden ses gönderilmez. Mikrofon izni kayıt düğmesinde istenir; kayıt en fazla 12 saniyedir ve işlem bitince geçici dosya silinir. Algılanan metin düzenlenebilir; seçilen yanıtı göndermek için ayrıca onay gerekir. Şık harfi/şık metni veya sıralama-eşleştirme için dört numara söylenebilir. Model, uygulama paketinde değildir; kaynak lisansı `Vendor/ArgmaxOSS/ORIGIN.md` ve `Sources/Resources/ThirdPartyNotices.txt` içindedir.

**Söyle ve dene**: yabancı dilde örneği dinle, ifadeyi söyle, algılanan metni kontrol et, yeniden dene. Karşılaştırma hedef kelimelerin tanınmasına dayanır; fonem, aksan veya klinik telaffuz puanı üretmez. Konuşma tanıma hatası nedeniyle doğru söylenen ifade de farklı anlaşılabilir.

**Sınav Hazırlık → Sınav ve ders** seçimi TYT/AYT/KPSS/LGS ve Matematik, Biyoloji, Kimya gibi dersleri içerir. Alt konu/ünite ayrımı yoktur. Yeni sorularda `study` etiketi üretim, oyun, havuz filtresi ve JSON aktarımında korunur. Eski sorular yeniden taranıp derslere atanmaz; ders filtresi yalnız etiketli kayıtları getirir. Günlük sınav kategorisi yine toplam 50 sorudur; her ders için ayrıca 50 değildir.

**Havuz → Paylaşım ve toplu içe aktarma**: tek soruda **Soruyu paylaş**, havuzda **Filtredeki soruları** veya **Tüm havuzu indir / paylaş**. iOS paylaşım menüsünden Dosyalar'a Kaydet kullanılabilir. Görünen ilk 100 satır dışa aktarımı sınırlamaz. Gizli sorular isteğe bağlıdır. Dosya formatı sürümlü UTF-8 **JSON**; uygulama içi kalıcı saklama SQLite içinde JSON + arama alanlarıdır. [Biçim rehberi](docs/QUESTION_FORMAT.md), [örnek dosya](docs/sample-import.json).

Bir veya birden fazla JSON dosyasını seçip önizlemeyi onaylayarak 1.000 ve daha çok soru toplu alınabilir (toplam sınır 100 MB / 100.000 aday). Kayıtlar 100'lük işlemlerde yazılır; yeni/tekrar/geçersiz sayıları ayrı gösterilir. İptal tamamlanan grupları korur; dosyayı tekrar seçmek aynı soruları çoğaltmaz. Son aktarımı geri almak yalnız o işlemle yeni eklenen kayıtları kaldırır; önceki sorulara dokunmaz. Aktarım hesap bilgisi, geçmiş veya ham ses kaydı içermez; fotoğraflar katalog kimliğiyle taşınır, PNG dosyaları JSON'a gömülmez.

Yeni eklenen sorular ortak veritabanında modelden bağımsız denetlenir. Şık/öğe sırası, model adı veya cevap değiştirmek yeni kimlik üretmez; etkinliğin dinleme metni/öğeleri de kimliğe dahildir. Yeni kayıtlar için kategori başına yakın tarihli 2.000 imzada yakın metin denetimi yapılır. Önceki havuz topluca taranmaz veya temizlenmez. Bu yöntem yakın kopyaları azaltır; farklı sözcüklerle kurulmuş her anlamsal tekrarı yakalama garantisi yoktur.


**Soru sesi API'leri**: Sesler yapay zekâ tarafından üretilir. **Oyna → Süre ve ses ayarları → Dinleme ve telaffuz sesi** altında Google Chirp 3 HD (30 ses: Kore/Puck ve diğerleri), Azure HD, CLI Proxy ses modeli veya iPhone sesi seçilir. Chirp Türkçe/İngilizce dahil sorunun dilindeki sesi ister. Azure Türkçede İkra'daki Elif/Aydın MAI-Voice-2-Flash, İngilizcede Ava/Andrew kullanır; Türkçe ses İngilizce diye etiketlenmez. CLI Proxy seçimi OpenAI uyumlu sağlayıcıda `/v1/audio/speech`, Gemini yerel sağlayıcıda `generateContent` AUDIO yolunu kullanır. 13 OpenAI ve 30 Gemini/Chirp sesi seçilebilir; model ve sağlayıcı yetkisi gerekir. Ses modellerinin listelenmesi kota veya tüm seslerle uyumluluk garantisi değildir.

Chirp aynı Google CLI OAuth hesabını ve Cloud TTS proje kotasını; Azure ayrı Speech anahtarı ve bölgesini kullanır. Bu bağlantılar iPhone'dan doğrudan resmi sağlayıcıya gider; çalışma anında VPS gerekmez. Azure anahtarı iPhone'un uygulamaya özel Anahtar Zinciri'ndedir. Ses üretim metni ilgili sağlayıcıya gider; mikrofon yanıtı Whisper'da cihazda kalır. İlk API isteği internet ve sağlayıcı kotası kullanır; üretilmiş aynı ses dil/motor/model/ses/metin kimliğiyle cihazda tekrar açılır. Önbellek 100 MB'la sınırlıdır; eski sesler temizlenebilir. Kota/ağ hatası başarı gibi gösterilmez, yeniden deneme veya metinle devam sunulur. iPhone sesi ayrı çevrimdışı seçenektir.

Teknik kaynaklar: [Google Chirp 3 HD](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd), [Azure REST konuşma sentezi](https://learn.microsoft.com/azure/ai-services/speech-service/rest-text-to-speech), [Azure dil/ses kataloğu](https://learn.microsoft.com/azure/ai-services/speech-service/language-support?tabs=tts).


### 2.6.1 mikrofon ve Whisper durumu

Canlı turda sabit alt çubuk; soru kaydırılsa da mikrofon açılışı, gerçek kayıt/ses düzeyi, Whisper çözümlemesi, yanıt önizlemesi ve hata görünür. Kayıt başlatılmadan 'mikrofon açık' gösterilmez; çözümleme sırasında kayıt bitmiştir. **Bitir**, **Durdur** ve **Devam** alt çubuktan kullanılabilir. Mikrofon izni soru okumadan önce istenir. Bluetooth HFP girişi ve düşük ses algılama eşiği iyileştirildi. Aktif telefon/VoIP görüşmesi varsa görüşmeyi bitirip Bilgi Arenası'nı önde açmak gerekir; yeniden başlatmak ilk çözüm değildir. Gerçek iPhone mikrofonuyla iki ardışık soru tamamlandı: Whisper iki Mars yanıtını çözdü, önizleme ve sesli geri bildirim sonrası 2/2 doğruyla tur bitti. Bu denemede hazır ses dosyası kullanılmadı.


### 2.7 Ayarlar sekmesi ve sesli yanıt

Alt çubuğa **Ayarlar** sekmesi eklendi. Ana ekranda yalnız tur süresi kalır; ses ve yanıt ayarları tek yerde toplanır:

- **Ses ve uyarılar:** ses efektleri, Türkçe sesli uyarılar, titreşim anahtarı, iPhone sesi konuşma hızı (Yavaş/Biraz yavaş/Normal/Hızlı), sesi dene.
- **Soru sesi:** Chirp/Azure/Proxy/iPhone sesi, örnek dinleme ve ses API bağlantısı.
- **Sesli yanıt (cihazda Whisper):** model durumu ve diskteki boyutu, modeli indir/yükle/sil. Ayrıca şunlar ayarlanır:
  - **Pencere açılınca dinlemeye başla** (varsayılan açık; model indirilmemişse ilk indirme dokunuş bekler).
  - **Susunca kaydı bitir** (0,8 / 1,2 / 2 sn sessizlik).
  - **En uzun kayıt** (8 / 12 / 20 sn).
  - **Kesin yanıtı onaysız gönder** (varsayılan kapalı). Açıkken yanıt 2 saniyelik geri sayımla gider ve Vazgeç ile durdurulabilir; söyleme alıştırması her zaman elle kaydedilir.
- **Canlı sesli tur:** motor seçimi, göndermeden önce bekleme (hemen / 2 / 3 / 5 sn), açıklamayı sesli okuma. Sıralı yol, sessizlik ve kayıt süresini sesli yanıt ayarlarından alır.
- **Soru havuzu:** otomatik üretim anahtarı ve günlük sayım.
- **Veri:** ses önbelleği boyutu ve temizleme, ilerlemeyi sıfırlama (XP, geçmiş, istatistik, tekrar defteri; havuz, paketler ve kaydedilen kartlar kalır), ayarları varsayılana döndürme. İki sıfırlama da onay ister.
- **Hakkında:** sürüm, gizlilik özeti, üçüncü taraf lisansları.

Sesli yanıt artık şu söyleyişleri de anlar:

- Dolgu sözleri: "Bence C şıkkı olsun", "Sanırım cevap B'dir".
- Sıra sözcükleri: "ikinci seçenek", "dördüncü şık", "ilk şıkkı seçiyorum".
- "Ce", "Be" gibi harf okunuşları.

Seçenek metni sayıysa söylenen sayı şık sırası değil, metin olarak eşleşir. Whisper'ın küçük yazım hatası ("Jupiterr") yalnız tek ve açık ara en yakın seçenekte kabul edilir; birbirine benzeyen iki seçenekte yanıt belirsiz sayılır. Canlı turda "atla", "sonraki soru", "bir daha oku", "bekle" komutları da anlaşılır.

