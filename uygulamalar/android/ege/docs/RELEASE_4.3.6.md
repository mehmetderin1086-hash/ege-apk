JARVIS 4.3.6 (49) — telefon, web ve iletişim kontrolü

Ortak kontrol katmanı
- Tüm erişilebilir uygulamalarda işlem öncesi sabit 600 ms ve işlem sonrası sabit 1000 ms bekleme kaldırıldı. Hedef uygulama, görünür kontroller, ekran değişimi ve yükleme göstergesi 100 ms aralıklarla gözlenir. Değişmiş ve 200 ms kararlı ekran, en erken 250 ms sonra döner; değişmeyen ekran belirsiz olarak bildirilir. Yükleme/hareket için 3 saniyelik sınır sonunda başarı varsayılmaz.
- Eski hedef kimliği, farklı paket/pencere, değişmiş etiket/konum, kapalı veya belirsiz kontrollerde işlem reddedilir. Birden fazla kaydırma alanında ilk alan rastgele seçilmez. İşlem süresi yalnız eylem adı ve süreyle kaydedilir; ekran/metin günlüklenmez.
- Tam paket adıyla her tıklamada tüm uygulama envanterini yeniden okuma kaldırıldı; native katmanda kurulu uygulama ve ön plan doğrulaması korunur.
- phone_open_app query ile YouTube/Spotify arama bağlantısını veya destekleyen uygulamaların Android arama intent'ini kullanır. Desteklenmiyorsa gerçek uygulama ekranına dönüp görünür aramayla devam edilir. İçerik seçimi ve oynatma doğrulaması atlanmaz.

Web ve formlar
- phone_open_app url ile belirtilen tarayıcıda http/https sayfa açar. Başka uygulamaya sessiz geçiş, javascript/file adresi ve URL içine yazılmış kimlik bilgileri kabul edilmez.
- Erişilebilir form alanlarını doldurma, bağlantı/düğme tıklama, iki yönde kaydırma ve desteklenen alanda klavye gönderimi (submit) eklendi/geliştirildi.
- Checkbox, seçili seçenek, odak, alan türü, durum ve canSubmit bilgileri ekrana dahil edilir. Formu doldurmak/gönderim yapmak/sonuç doğrulamak ayrı adımlardır. CAPTCHA, özel canvas ve erişilemeyen alanlar için başarı garantisi yoktur.

Arama ve mesajlaşma
- Eksik olan endCall eklendi: Android telefon izinleriyle bir kapatma isteği gönderir; çağrının sona erdiğini en fazla 2,5 saniye gözler. İstek reddedilirse veya sonuç belirsizse kapandı demez ve yeniden denemez. İzin denetimi Asistan ve Arka Plan ayarındadır.
- Uygulama içi görüşmeler Android telefon API'sinin kapsamına girmeyebilir; ajan ilgili uygulamanın çağrı ekranındaki kapatma kontrolüyle ilerler.
- Benzer kişi adlarında ilk numarayı arama kaldırıldı; benzersiz kişi/numara gerekir. Arama başlatma hatası artık çevirici açıldı diye bildirilmez.
- SMS/WhatsApp/Telegram gönderme, okuma ve uygulama içi arama talepleri (ajan açıkken) yalnız taslak açan yerel kısayollarda durmaz. Güncel sohbet ve alıcı doğrulamasıyla telefon ajanına gider. Gönderim, teslim ve okunma farklı durumlardır; belirsiz gönderim tekrarlanmaz.
- contact_search ve izinli message_notifications araçları eklendi. Bildirim sonucu tüm mesaj geçmişi olarak sunulmaz. Mesaj işlemini iptal etme sonraki adımları ve seslendirmeyi durdurur; gönderilmiş mesajı geri aldığını iddia etmez.

Hey Jarvis
- Cihazda PCM/decoded sayaçları artarken silenced=false ve 8,4 saniyeye varan yerel çözümleme gözlendi; bu olay mikrofonun başka uygulamada olmasına bağlanmadı.
- Yerel yedekte her parçadan sonra 2 saniye ses atılması kaldırıldı. ASR meşgulken bir sonraki en güncel parça sınırlı kuyrukta saklanır. Oturum değişiminde veya eski parçada sonuç kullanılmaz.
- Uzun konuşmalarda 800 ms örtüşme, sabit ortam gürültüsü kalibrasyonu, klibin ortasında başlayan açık Hey Jarvis ifadesini tanıma eklendi. Yerel metin filtresi cümle içindeki sıradan Jarvis anmalarını reddeder; hızlı KWS ayrıca Jarvis anahtar sözcüğünü dinlemeye devam eder. Base modeli önceliği korunur.
- Başlangıçtaki 1,5 saniyelik tetikleme engeli 300 ms oldu. Durmuş PCM/algılayıcı akışını gözeten ve sınırlı yeniden başlatan sağlık kontrolü eklendi. Android başka uygulama nedeniyle mikrofonu susturduğunda yeniden başlatma döngüsü uygulanmaz.
- Dikte hata yollarında uyandırma yeniden devreye alınır. Ses diske veya ağa gönderilmez; yalnız kısa, sınırlı parçalar bellektedir.

Doğrulama
- Native JVM: 22 test geçti (ekran hazırlığı, belirsiz sonuç, form hedefi, arama kapatma doğrulaması, uyandırma kuyruğu/örtüşmesi/gürültüsü/sağlığı ve indirme politikası).
- Hedefli Flutter testleri: 26 test geçti. Tam paket eylemi, sorgu ve form metnini koruma, URL doğrulama, mesaj yönlendirme, olumsuz kapatma komutu, belirsiz rehber kişisi ve izin reddi kapsandı.
- Tam Flutter paketi: 181 test geçti. flutter analyze: No issues found.
- Telefonda salt okunur intent çözümlemesi: Spotify arama URI'si SpotifyMainActivity'ye, web URI'si Chrome IntentDispatcher'a eşleşti. Bu kontrol içeriğin açıldığı veya oynatıldığı kanıtı değildir.
- Otomatik onay denetimi örnek YouTube aramasını açma testini engelledi; ayrıntılı gerekçe verilmedi. Aynı eylem başka yoldan denenmedi. Gerçek uçtan uca süre, gerçek arama kapatma/mesaj gönderimi ve kullanıcının sesiyle güvenilir uyandırma ayrıca doğrulanmalıdır.

Teknik kaynaklar
- Android uygulama içi arama: https://developer.android.com/develop/ui/views/search/search-dialog
- Google SearchIntents: https://developers.google.com/android/reference/com/google/android/gms/actions/SearchIntents
- Spotify URI kaydı: https://www.iana.org/assignments/uri-schemes/prov/spotify
- Android TelecomManager (izinler, endCall ve uygulama içi çağrı kısıtları): https://developer.android.com/reference/android/telecom/TelecomManager
