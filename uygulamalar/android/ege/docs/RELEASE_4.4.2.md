# Ege 4.4.2 (55)

## Değişiklikler

- Kendi sesini tanıma için genel konuşma profiline ek olarak üç kısa “Hey Ege”
  örneğiyle ayrı uyandırma kalibrasyonu. Benzerlik eşiği düşürülmedi; genel
  ses profili korunur. Sessiz başlangıç/bitiş, kısa örneklerin karşılaştırmasını
  bozmasın diye yalnız dış sessizlik kırpılır.
- Bağlı hesaplar tek ayar bölümünde: Google ve Microsoft hizmetleri.
  Microsoft için MSAL tarayıcı giriş köprüsü, Outlook okuma/gönderme,
  OneDrive listeleme/metadata/yükleme ve Takvim araçları eklendi.
  Microsoft uygulama kaydı ve client ID henüz yapılandırılmadığından gerçek
  Microsoft hesabı bağlı değildir; arayüz bunu kurulum eksikliği olarak gösterir.
- Koyu temada canlı mikrofon simgesinin görünürlüğü düzeltildi.
  Canlı ekrana yazıyla komut verildiğinde uyandırma mikrofonu duraklatılır.
- MSAL/Nimbus kripto bağımlılıkları APK içine dahil edildi; R8 hataları
  bastırılmadı. Bouncy Castle lisans kaynakları paketlemede birleştirilir.

## Doğrulama

- 48 odaklı Flutter testi geçti (ses profili, canlı yaşam döngüsü, hesaplar,
  sohbet dosyaları, görünüm ve ilgili regresyonlar).
- Android debug birim testi görevi başarılı.
- Dart analizi: hata/uyarı yok, 53 bilgi düzeyi öneri.
- ARM64 release APK başarıyla derlendi.
- APK: `../dist/Ege-4.4.2.apk` (84.628.750 bayt).
- SHA-256: `e5c0275f19007d297d434b6bf4427ce65f88106cc2d3d395405aeef2b96b1351`.

## Gerçek cihaz sınırları

4.4.1 kayıtlarında “Hey Ege” kısa sözü birkaç kez ses kimliği filtresinden
geçemedi (0,42–0,60 / 0,65); bir denemede doğrulanıp canlı ekran açıldı.
Bu nedenle 4.4.2'nin ayrı kısa örnek kalibrasyonu eklendi. Kullanıcının kendi
sesiyle üç örnek kaydı ve uygulama içi/dışı tekrarlı test henüz tamamlanmadı.
Gmail, Drive ve Google Takvim, kişisel Google Cloud test kaydı kurulduktan sonra 4.4.1'de
gerçek okuma isteğiyle bağlandı. Gerçek mail gönderimi veya takvim yazması
test amacıyla yapılmadı.

4.4.2 USB kurulumu bağlantı kesildiği için başarısız oldu; `adb devices`
listesi boş. Son doğrulanan kurulu sürüm 4.4.1 (54). 4.4.2'nin cihazda
çalıştığı veya ses kalibrasyonunun tamamlandığı iddia edilmemelidir.
APK kullanıcının Drive'ına yüklendi ve metadata okumasıyla adı/boyutu
doğrulandı: https://drive.google.com/file/d/15gQjbKVQ5QGsibp5pQ8nH9YKMTuy8W6N/view?usp=drivesdk

Sonraki cihaz kontrolü (17 Kasım 15:47): telefon yeniden USB'de görüldü.
`dumpsys package` kurulu sürümü 4.4.2 (55), güncelleme zamanını 14:48:15
olarak doğruladı. Uygulama açıldı; mikrofon PCM verisi ve yerel denetimler
çalışıyor. Ses profili ekranı açıldığında genel profil kayıtlıydı, kısa
uyandırma profili kayıtlı değildi; kullanıcı üç kısa örnek için yönlendirildi.

Kaynaklar: [Tink Android sürümü](https://github.com/tink-crypto/tink-java/releases/tag/v1.24.0),
[Bouncy Castle dağıtımları](https://www.bouncycastle.org/download/bouncy-castle-java/).
