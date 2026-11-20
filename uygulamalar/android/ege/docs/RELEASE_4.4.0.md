# Ege 4.4.0 (53)

## Canlı ses

- Yerel Whisper modeli hazırken canlı konuşma Android SpeechRecognizer'ı her turda yeniden açmaz. Böylece sistemin başlangıç/bitiş tonları bu akışta kullanılmaz. Normal dikte, ses profili filtresi kapalıyken telefon STT ayarını korur.
- Yanıt sesi başlamadan hemen önce VOICE_COMMUNICATION mikrofonu açılır. Donanım yankı giderme açıksa kullanıcı konuşması algılandığında ses kesilir. 400 ms ön tampon ilk heceleri korur. Yanıt doğal olarak bitince aynı mikrofon kullanıcı turuna geçer.
- Sessizlik eşiği 800 ms yerine 560 ms. Kısa donanım yankı kuyruğu için doğal bitişte 160 ms koruma vardır.
- Yalnızca Ege konuşurken mavi dalgalı kenar ışıkları gösterilir. Konuşma küresi varsayılan 132 piksel; görünüm ayarlarından boyut ve renk değişir.
- Uyandırma onay tonu 70 yerine 12 ses düzeyinde, 160 yerine 55 ms çalar.
- Eski turdan gelen olaylar, durdurma ve dokunarak kesme yeni bir mikrofon turu başlatamaz.

## Yalnızca benim sesim

Ayarlar → Yalnızca benim sesim ekranında üç ayrı ses örneği kaydedilir. Kayıt bitmeden bu filtre etkin değildir. Profil sahibi henüz kaydedilmediğinden gerçek kullanıcı kabul/red başarısı doğrulanmış sayılmaz.

Model telefonda çalışır. Ham kayıtlar kalıcı saklanmaz; ses vektörleri Android'in yedeklenmeyen özel uygulama dizinine yazılır. Obsidian, sohbet arşivi ve indirme klasörüne aktarılmaz. Profil silinebilir.

Filtre hem KWS hem yerel Whisper uyandırma yolunda, sesli komutlar yazıya dönüştürülmeden önce ve konuşarak araya girme adaylarında uygulanır. Araya girme doğrulaması yaklaşık 1,4 saniyelik ses örneği toplar; bu ayar açıkken kesme daha geç olabilir. Ses filtresi kimlik doğrulama veya kayıt/taklit seslere karşı koruma değildir. Gürültü, çok kısa ifadeler ve eşzamanlı konuşmalar reddedilebilir.

Model kaynağı ve ölçütler: [SPEAKER_MODEL.md](SPEAKER_MODEL.md).

## Ekran, Türkçe ve indirmeler

- Resim/fotoğraf/PDF indirme istekleri Play Store kısayoluna düşmez. Mağaza indirme kısayolu açıkça uygulama indirme isteği gerektirir.
- Ekran okuması güncel dış uygulamaya döner; eski bir ekran görüntüsünü yeniden kullanmaz. Desteklenen ekranlarda erişilebilirlik görüntüsü, diğer durumlarda mevcut erişilebilir metin kullanılır.
- Satır/sütun, etiket ve yakın öğe bağlamı korunur. Sayılar belirsizken tahmin etmemesi için yönergeler eklendi.
- Saat, tarih, Türk lirası/kuruş, yüzde ve süreler seslendirmeden önce Türkçe ifadeye çevrilir. Örnek: `19:30` → “saat on dokuz otuz”; `5 dk` → “beş dakika”.
- Güncel ve doğrulanmış hedef üzerinde uzun basma; sayfadaki gerçek resim bağlantılarını açıklamalarıyla bulma. HTML sayfası resim dosyası olarak kuyruğa alınmaz.
- Yeni indirmeler ve oluşturulan belgeler İndirilenler/Ege altında tutulur. Önceki JARVIS dosyaları silinmez/taşınmaz.

## Sohbet, hafıza ve görünüm

- Kullanıcı mesajı dış işlem başlamadan kaydedilir. 60 sohbet ve sohbet başına 300 mesaj saklama sınırı kaldırıldı; eşzamanlı kayıtlar sıraya alınır.
- Yanıtlar, bu sırada başka sohbet açılsa bile özgün sohbetlerine yazılır.
- Ege Hafıza için Markdown kasa eşitlemesi; tam sohbet arşivi, profil, beceri notları ve kaynağı belirtilen çıkarımlar. Çıkarımlar en az iki ayrı kullanıcı mesajından birebir kanıt gerektirir. Harici not düzenlemeleri çakışma yedeğiyle korunur.
- Açık/koyu/sistem teması, vurgu rengi ve canlı küre boyutu ayarları.

## Doğrulama

- 208 Flutter testi geçti.
- 29 Android JVM testi geçti.
- `dart analyze lib test`: sorun yok.
- APK ve gerçek cihaz kontrollerinin sonuçları kurulumdan sonra eklenecek.

## Sınırlar / devam eden işler

Donanım AEC kullanılabilirliği ve gerçek sesle araya girme telefonda ayrıca ölçülmelidir. Donanım AEC yoksa dokunarak kesme ve sessiz sıra geçişi kullanılabilir. Yerel Whisper modeli yoksa telefon STT geri dönüşünde cihazın kendi tonları duyulabilir. Model/AI/TTS yanıt süreleri cihaz ve hizmet bağlantısına bağlıdır; bu sürüm bütün gecikmeyi ortadan kaldırmaz.

MCP sunucusu bağlantısı ve uygulama iş akışlarının daha gelişmiş otomatik öğrenimi bu sürümde tamamlanmış sayılmaz. Mevcut beceri/ajan araçları korunur. Obsidian klasör seçimi ve gerçek kullanıcı ses profili kaydı cihazda tamamlanmalıdır.
