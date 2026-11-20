JARVIS 4.3.3 (46)

Telefon kontrolü
- Her eylemde uygulamayı tekrar başlatma kaldırıldı; yalnız açık açma talebi uygulamayı öne getirir.
- Erişilebilir ekran kontrollerine gözleme bağlı target kimlikleri eklendi. Metin, açıklama, ipucu, alan türü ayrı okunur; etiketsiz düzenlenebilir alanlar da görünür.
- Eski/değişmiş kontrol kimlikleriyle işlem reddedilir ve yeni ekran döner. Hedef uygulama önde değilken işlem yapılmaz.
- Bir model turunda yalnız bir telefon eylemi uygulanır. Son ekran sonraki karara aktarılır.
- Model isteği boyunca agent arka plan servis nedeni tutulur; başarı/hata/iptal sonrası finally ile bırakılır. Canlı ses veya uyandırma hâlâ etkinse onların servisi korunur.
- Telefon görevlerinde en çok 16 araç turu: arama, doğru sonuç, açma/oynatma ve son durum doğrulaması. Sınırda tamamlanma iddiası yerine eksik sonuç açıklanır.
- Spotify'da/Spotify'dan/Spotify içinde istekleri genel YouTube müzik kısayolundan ayrıldı.
- Sadece araç çağrısı içeren geçerli model yanıtının boş cevap sanılması düzeltildi.

Uyandırma ve asistan
- Hey Jarvis algılayıcısı ayrı bir FlutterEngine içinde JarvisForegroundService tarafından çalıştırılır. AudioRecord ve anahtar sözcük motoru MainActivity yaşam döngüsünden ayrıldı; Activity kapanması bu mikrofonu durdurmaz.
- Mikrofon servisi hazır olmadan algılama başlamaz. Canlı STT/dikte öncesinde wakeWordPause mikrofonu bırakır; görüşme/dikte bitince tercih açıksa servis yeniden başlatılır.
- Bildirimde Durdur seçildiğinde otomatik yeniden dinleme o oturum için engellenir. Uygulamaya dönüşte gerçek servis durumu yeniden okunur.
- İşletim sisteminin süreci zorla kapatmasından veya cihaz yeniden başlamasından sonra kendiliğinden dinleme garantisi verilmez; servis sessizce izinsiz başlatılmaz.
- Uyandırma hatası/dinleme durumu görünür, yeniden başlat düğmesi eklendi.
- Arka plandaki uyandırma, asistan penceresine wake kaynağıyla gider; otomatik asistan dinleme tercihiyle karışmaz.
- Telefondaki güç düğmesi ilk kullanım açıklaması tamamlandı. ADB uzun basma denemesinde JARVIS Canlı Ses / Seni dinliyorum ekranı gözlendi (önceki kurulu sürümde).

Doğrulama ve sınırlar
- Son arka plan uyandırma düzenlemeleriyle tam Flutter paketi: 169 test geçti.
- Son eklenen Spotify yönlendirme testi dahil hedefli paket: 12 test geçti.
- Kod analizi: No issues found. Son Android release APK derlemesi başarılı (88,7 saniye, yaklaşık 55 MB). Sürüm 4.3.3 / 46; SHA-256 dosyası yanında.
- Kullanıcı telefonu kullanmakta olduğunu bildirdi: 4.3.3 henüz kurulmadı. Yeni sürümün gerçek Spotify uçtan uca ve sesli Hey Jarvis denemesi bekliyor.
- Erişilebilirlik izni güncellemeden sonra tekrar kontrol edilmeli. Parola/korumalı ekranlar ve erişilebilir kontrol sunmayan uygulamalarda tam kontrol garantisi yoktur.
- Bu sürümde genel ekran koordinatıyla tıklama veya görüntü üzerinden kontrol eklenmedi. İşlem yeteneği erişilebilir düğme/metin/kaydırma/geri eylemleridir.

Arka plan mimarisi için resmi kaynaklar:
https://api.flutter.dev/javadoc/io/flutter/embedding/engine/FlutterEngine.html
https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
