# JARVIS 4.3: Android ajanı, konuşma ve indirme mimarisi

İnceleme tarihi: 17 Kasım 2026. Bu rapor resmî belgeler ile mevcut JARVIS kaynak kodunun karşılaştırmasıdır. Hermes'in bütün özelliklerinin tamamlandığı veya tüm Android uygulamalarının kontrol edilebildiği anlamına gelmez.

## 1. Araştırmanın sonucu

Hermes'in araç kaydı web, dosya/terminal, tarayıcı, hafıza, beceriler, zamanlama ve ajan orkestrasyonunu kapsıyor. Bunlar tek bir mobil SDK'dan ibaret değil: çalışma ortamı, yetkilendirilmiş bağlantılar ve araç sunucuları gerekiyor. JARVIS'in mevcut `agent_core.dart`, `jarvis_controller_agent.dart`, `work_hub.dart` ve PC köprüsü bu başlıkların bir bölümünü zaten karşılıyor. Bu çalışmada mevcut altyapı korunarak telefonun dış uygulamalarını gözlemleyen ve kullanan Android katmanı eklendi. [Hermes araçları](https://hermes-agent.nousresearch.com/docs/user-guide/features/tools/)

Resmî Android/Termux sayfası inceleme tarihinde paketin çalışmadığına ilişkin bir uyarı içeriyor. Ayrıca Android paketinde masaüstü Chromium, Electron ve bilgisayar kontrol araçlarının bulunmadığı açıklanıyor. Bu nedenle telefona masaüstü kurulum betiği çalıştırmak veya Hermes'i APK içine eksiksiz gömmek uygulanabilir bir entegrasyon olarak kabul edilmedi. [Android/Termux](https://hermes-agent.nousresearch.com/docs/getting-started/termux)

Hermes'in bilgisayar kontrolü, platformun erişilebilirlik ve girdi katmanlarına bağlanan `cua-driver` üzerinden çalışıyor. Resmî belgede Android dağıtımı bulunmadığı açıkça belirtiliyor. Android için karşılığı `AccessibilityService` tabanlı, kullanıcı tarafından etkinleştirilen bir servistir. Bu servis Chrome'u kendi Android etkinliğinde açar; bir WebView içinde Chrome taklidi oluşturmaz. [Computer Use](https://hermes-agent.nousresearch.com/docs/user-guide/features/computer-use)

## 2. Uygulanan telefon kontrolü

`JarvisAppControl.kt` erişilebilirlik servisi, `AppControlScreen` kullanıcı arayüzü ve `phone_*` ajan araçları birlikte çalışır:

1. `list_apps` ile telefondaki başlatılabilir uygulamaların gerçek paket adları bulunur.
2. `phone_open_app` seçilen Android uygulamasını açar, ekranın hedef pakete ait olmasını bekler ve erişilebilir kontrolleri döndürür.
3. `phone_snapshot` öndeki ekranı okur. Parola alanları ve görünmeyen düğümler dışarıda bırakılır; içerik kalıcı olarak kaydedilmez.
4. `phone_action` gözlenen etikete göre dokunma, metin doldurma, aşağı kaydırma veya geri işlemi yapar.
5. İşlem sonrası ekran yeniden okunur; ajana sonuç verilir. Birden fazla eşleşme varsa rastgele seçim yapılmaz.

Telefon işlemleri aynı ekran üzerinde yarışmaması için sıralı çalıştırılır. Alt ajanların ve öğrenme döngüsünün telefon ekranını bağımsız olarak değiştirmesi engellenir. Kullanıcı sohbeti durdurduğunda bekleyen sonraki araç çağrıları yürütülmez. Ekrandaki içerik, kullanıcı talimatı olarak kabul edilmemesi gereken gözlem verisi olarak işaretlenir.

Bu yaklaşım Android izinlerini veya uygulama korumalarını aşmaz. Kilit ekranı, bazı bankacılık ekranları, oyun/canvas kontrolleri ve erişilebilir etiket vermeyen uygulamalar çalışmayabilir. Android servis iznini kullanıcı sistem ayarından açmalıdır. Kontrol mevcut ekrana uygulanır; gizli bir ikinci Android masaüstüsü oluşturulmaz. İşlemin Android tarafından kabul edilmesi, örneğin bir satın almanın sunucuda tamamlandığı anlamına gelmez; son ekran ayrıca değerlendirilir.

## 3. Hermes özellik eşlemesi

| Özellik | JARVIS durumu | Kapsam / eksik |
|---|---|---|
| Kalıcı kullanıcı ve iş hafızası | Önceden mevcut | Bütçeli metin hafızası; Honcho entegrasyonu değildir |
| Sohbet geçmişinde arama | Önceden mevcut | Uygulamanın kendi oturumları |
| Beceriler / SKILL.md | Önceden mevcut | Oluşturma, okuma, düzenleme ve kullanım; tüm Hermes eklentileriyle çalışma garantisi yok |
| Görev planı / alt ajanlar | Önceden mevcut | Sınırlı tur ve alt görev sayısı |
| Zamanlanmış görevler | Önceden mevcut | Android arka plan ve pil sınırlamalarına bağlı |
| Web arama / araştırma | Önceden mevcut | Kaynak okuma ve araştırma işleri; bağlantı/model gerekir |
| PDF, Word, Excel üretimi | Önceden mevcut | `start_work` ve Çalışmalar merkezi; her biçim için mevcut üretici kullanılır |
| Düz metin dosyası üretimi | Yeni ajan aracı | txt/md/csv/json/html; Download/JARVIS; dizin dışına yazma reddedilir |
| Dış Android uygulama kontrolü | Bu sürümde eklendi | İzinli erişilebilirlik servisi; gözlem, açma, dokunma, yazma, kaydırma, geri |
| PC terminal/dosya araçları | Önceden mevcut | Eşlenmiş PC köprüsü gerekir; telefonun Linux terminali değildir |
| MCP sunucuları | Henüz genel istemci yok | Kimlik doğrulama, araç keşfi ve bağlantı yönetimi ayrıca gerekir |
| Hermes gateway / 20+ kanal | Tam entegrasyon yok | WhatsApp bildirim paneli, tüm Hermes mesajlaşma gateway'iyle eşdeğer değildir |
| Docker/SSH/Daytona/Modal ortamları | Mobil çalışma ortamı olarak yok | Ayrı sunucu ve hesap bağlantıları gerekir |
| Masaüstü cua-driver | Android'de kullanılmıyor | Yerine yerel erişilebilirlik katmanı geliştirildi |
| Honcho / RL / eğitim dışa aktarımı | Yok | Bu mobil sürümün teslimatı değil |

Hermes becerileri aşamalı yüklenen yöntem belgeleridir. JARVIS'in beceri dizini ve `skill_view` yaklaşımı bu modele benzer; yöntem belgesini içe almak, onun gerektirdiği Python araçlarını veya üçüncü taraf hesaplarını otomatik sağlamaz. [Skills](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills/)

MCP gelecekteki genel bağlantı katmanı için uygun adaydır: Hermes hem stdio hem HTTP araç sunucularını destekler. Telefonda uzak HTTP istemcisi daha uygun olabilir; fakat bağlantı kurulması, kimlik doğrulama ve araç yetkileri gerçek bir entegrasyon gerektirir. Bu sürümde çalışan bir Hermes MCP bağlantısı varmış gibi gösterilmez. [MCP](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp/)

## 4. Yerel canlı konuşma

Gemini Live ve OpenAI Realtime seçenekleri arayüzden ve etkin konuşma akışından kaldırıldı. Eski ayarlar JARVIS'in `turn_based` akışına taşınır. Yeni sıra telefonun tanıma servisi, normal sohbet modeli ve Android TTS'dir. `PhoneSpeech` tek bir tanıma isteğini yönetir; iptal/zaman aşımı ve eski geri çağrılar yeni oturumu bitiremez. JARVIS'in kendi Whisper RecognitionService'i telefon STT sağlayıcı listesinden dışlanır; böylece aynı motor yanlışlıkla kendisine yönlendirilmez.

Telefon STT kullanılamazsa WAV kaydı yeniden başlar ve yerel Whisper öncelikli yedek olur. İlk konuşma kaydı telefonun tanıma motorundan alınamadığı için bu geçişte kullanıcı yeniden konuşur. İzin reddi farklı ele alınır; başka bir motorla izin aşılmaya çalışılmaz. Sessizlikte boş komut gönderilmez. Telefon STT sağlayıcısı kendi ağ hizmetini kullanabilir; “telefon motoru” her cihazda “internetsiz” demek değildir. Model telefonda mevcutsa Whisper çevrimdışı çalışabilir. Seçili normal sohbet modeli buluttaysa yanıt için internet gerekir. [Android SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)

## 5. İndirme motoru

IDM'nin ayırt edici başlıkları kuyruk, devam ettirme, hız yönetimi, zamanlama ve tarayıcı entegrasyonudur. Windows tarayıcı eklentisini Android Chrome'a taşımak mümkün bir kısayol değildir; Android'de bağlantı paylaşımı, doğrudan URL ve erişilebilirlik üzerinden dış tarayıcı kullanılmalıdır. [IDM özellikleri](https://www.internetdownloadmanager.com/features2.html), [IDM zamanlayıcı](https://www.internetdownloadmanager.com/articles/scheduler.html)

Mevcut DownloadManager geçmişi korunur. Yeni indirmeler `ManagedDownloads` kuyruğuna gider. Kuyruk disk üzerinde tutulur; yarım dosyalar özel depoda kalır, tamamlanan dosya ortak Download/JARVIS klasörüne yayınlanır. 1–3 eşzamanlı dosya, dosya başına hız sınırı, Wi-Fi tercihi, duraklat/devam et, yeniden dene, iptal, aç ve paylaş desteklenir. Süreç öldürülürse yarım işler duraklatılmış olarak geri gelir ve kullanıcı devam ettirebilir. Ön plan indirme bildirimi uygulama ekranı kapalıyken çalışmayı sürdürür; işletim sistemi arka plan sınırları geçerlidir.

Devam ettirme `Range` ve `If-Range` ile yapılır. Güçlü ETag veya Last-Modified yoksa eski parça yeni yanıtla körlemesine birleştirilmez. HTTP 200 gelirse dosya baştan yazılır. HTTP 206 için başlangıç, bitiş, toplam ve Content-Length tutarlılığı kontrol edilir. Yanlış aralık veya hata sayfası tamamlanmış dosya olarak yayınlanmaz. Bu kurallar ayrı JVM testleriyle doğrulanır. [HTTP aralık standardı](https://www.rfc-editor.org/rfc/rfc9110.html)

Bu sürüm IDM'nin birebir tamamı değildir: çok parçalı tek-dosya hızlandırması, site oturum çerezlerini taşıma, tarayıcı uzantısıyla tüm trafiği yakalama, FTP, site aynalama ve DRM akış çözme uygulanmış sayılmaz. Var olan medya keşfi ve isteğe bağlı Termux/yt-dlp entegrasyonu ayrı yeteneklerdir. Bağlantısı bulunamayan video için indirme başarısı iddia edilmez.

## 6. Doğrulama ve devam kriterleri

Flutter testleri: telefon STT başarılı/erişilemez/izin reddi; ayar göçü; belirsiz uygulama seçimi; dosya yolu doğrulaması; 320 px canlı ekran; tek ayar merkezi; mevcut ses yaşam döngüsü testleri. Android JVM testleri: doğru ve yanlış HTTP aralıkları. APK derlemesi native servislerin entegrasyonunu doğrular. Önizlemeler test verisiyle üretilir.

Fiziksel cihazda ayrıca mikrofon tanıma kalitesi/gecikmesi, erişilebilirlik izni sonrası Chrome akışı, ağ kesintili indirme ve pil kısıtları denenmelidir. Birim testi bu gerçek kullanım sonuçlarının yerine geçmez. İleride MCP, genel Hermes gateway ve isteğe bağlı uzak terminal bağlanırken her biri için ayrı doğrulanabilir kabul ölçütü gerekir.
