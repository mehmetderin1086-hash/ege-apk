# Ege 4.4.3 (56)

Ses profili ekranında kalibrasyon sürerken uyandırma motorunun yeniden
başlaması engellendi. Önceki akış `stopLiveSession()` çağrısından 800 ms
sonra `resumeWakeWord()` planlıyordu; `stopWakeWord()` tek başına yeniden
başlatma engeli koymuyordu. Kayıtlar sırasında `LOCAL_FALLBACK` ve PCM
sayacının yeniden başladığı 4.4.2 cihaz kaydında görüldü.

Ekran açıkken yeniden başlatma engeli tutulur ve aktif uyandırma motoru
durdurulur. Çıkışta kullanıcının önceki durdurma tercihi geri yüklenir.
Mevcut genel ses profili varsa ilk ekranda yalnız kısa “Hey Ege” örnekleri
sunulur. Genel profil yenileme ayrı, açık bir düğmeyle başlatılır; yeni
üç örnek doğrulanmadan mevcut kayıt silinmez.

Doğrulama: ses kimliği ve kalibrasyon ekranı için 10 test geçti. Gerçek
kullanıcıyla arka planda uyandırma başarısı henüz doğrulanmış değildir.

ARM64 release derlemesi başarılı (195 sn). USB `install -r` başarılı;
cihazda 17 Kasım 2026 15:58:02 güncelleme zamanı, sürüm 4.4.3 / kod 56
doğrulandı. Düzeltilmiş ekran cihazda açıldı; genel profil korunmuş, kısa
Hey Ege profili henüz kaydedilmemiş olarak gösterildi.

APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.4.3.apk`
(84.628.750 bayt). SHA-256:
`29cd6cf1f006e01182031833ef867f6c92d2db2f8fe3a515f7554ea112aeed12`.
Değişen uygulama dosyasının analizinde hata/uyarı yok (bir mevcut biçim
önerisi); yeni test dosyasının analizi temiz.

Cihazda profil ekranı açıkken son uyandırma PCM kaydı 15:58:37'de kaldı;
ekrandan çıkıldıktan sonra 16:00:20'de yerel uyandırma motoru, 16:00:21'de
PCM yeniden başladı. Kısa kalibrasyon hâlâ 1. örnekte: gerçek ses ile
uyandırma kabulü bu oturumda doğrulanmadı.
