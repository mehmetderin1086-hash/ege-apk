# Ege 4.4.1 (54)

## Değişiklikler

- Canlı Ses küresi görünüm ayarındaki gerçek boyutu kullanır ve ayar değişikliği ekranda hemen uygulanır. Mavi konuşma ışıkları tüm ekran kenarını boyar; yalnız asistan sesi çalarken görünür.
- Telefon STT seçiliyken Whisper kurulu olsa da telefonun tanıyıcısı önce denenir. Desteklenen cihazlarda Android yerel tanıyıcısı tercih edilir. Kişisel ses filtresi açıksa konuşmacıyı doğrulamak için ses kaydı/Whisper yolu korunur; telefon tanıyıcısı ham ses sağlamaz.
- Konuşma bittiğinde gereksiz çift yönlü mikrofon kaydı bırakılmaz; normal sonraki tur telefon STT'sine döner. Kullanıcı araya girmişse başlamış kaydı korur.
- HYG, kullanıcının belirttiği “Hey Ege” telaffuzuyla eşleşir. Ölçülen “Hey, egg” varyantı yerel anahtar sözcüklere eklendi. Tanılama artık kişisel ses filtresinin kabul/ret gerekçesini gösterir; ses profili kontrolü atlanmaz.
- Araştırma sonuçlarından doğrulanmış kaynaklarla XLSX, DOCX, PDF, TXT/Markdown dosyaları üretilebilir. Araçlar gerçek dosyayı yazar; hayali ek satır üretmez. Webden bilgi isteyen işler araştırma araçlarına gider.
- Üretilen dosyalar işi başlatan sohbetin içinde Aç/Paylaş kartı olarak kalıcı kaydedilir; Çalışmalar ekranına geçmek gerekmez. Kullanıcı mesajlarındaki web/mail/telefon bağlantıları da tıklanabilir.
- Gmail, Google Drive ve Google Takvim için hizmet bazlı bağlantı ekranı ve araçlar eklendi. Gerçek bağlantı için Google Cloud Android OAuth kaydı ve telefonda kullanıcı izni gerekir; bunlar tamamlanmadı. Ayrıntılar: [Google kurulumu](GOOGLE_ACCOUNT_SETUP.md).

## Doğrulama

- Genel Flutter test turu: 216 başarılı (son Google/bağlantı eklemelerinden önce).
- Dosya, Google, canlı ses ve görünüm odaklı testler: 32 başarılı.
- Android JVM testleri: 29 başarılı, hata yok.
- Dart analizinde hata veya uyarı yok; 40 bilgi düzeyinde stil önerisi var.
- 17 Kasım 2026, 13:56: USB üzerinden `adb install -r` başarılı; cihazda versionName 4.4.1 / versionCode 54 doğrulandı. Uygulama açıldı; seçili mavi tema ve 150 dp küre gerçek ekranda görüldü.
- Ek sohbet bağlantısı testleri: 2 başarılı. Son dosya/Google testleri: 9 başarılı.
- Gerçek ses denemelerinde kişisel ses filtresi 0.42–0.60 benzerlikle bazı denemeleri reddetti (eşik 0.65). 13:59:08'de yerel Whisper ifadesi + ses doğrulama kabul edildi; HIT → SHOW_ASSISTANT → SESSION_SHOW → ACTIVITY_LAUNCH kaydedildi ve canlı dinleme ekranda görüldü. Bu kesintili sonuç kalıcı çözüm olarak raporlanmadı; 4.4.2 için kısa uyandırma kalibrasyonu hazırlanıyor.
- Azure oynatımı sırasında kenar ışıkları ve gerçek barge-in bu oturumda henüz cihaz üzerinde doğrulanmadı.

## Bilinen sınırlar

- Google hesabı henüz bağlı değildir; Chrome kurulumu kullanıcı isteğiyle bekletildi. Testler gerçek mail göndermedi ve takvime etkinlik yazmadı.
- Drive okuma aracı dosya metadatasını okur; doğrudan yükleme 5 MB ile sınırlıdır. Büyük dosya karttan Paylaş ile gönderilebilir.
- Telefon STT'sinin gerçekten çevrimdışı çalışabilmesi cihazın yüklü Türkçe modeline ve sistem tanıyıcısına bağlıdır.
