# Ege 4.4.5 (58)

## Uyandırma sesinin kırpılması

4.4.4'te kısa Hey Ege kalibrasyonu tamamlandıktan sonraki gerçek cihaz
denemesinde KWS tetiklendi ancak `KWS_SPEAKER accepted=false` ve
`En az bir saniye net konuşma gerekli.` kaydı görüldü (17 Kasım 16:22:36).
Bu mesaj, embedding girişinin gerçekte 12000 örnekten (0,75 saniye) kısa
olduğunu belirtiyordu. Dış sessizlik kırpması, yeterince uzun yakalanmış bir
kaydı bu sınırın altına indirebiliyordu.

Kırpılan kısa söz için modelin gerektirdiği 12000 örneklik pencere, kaydın
çevresindeki özgün sesle korunur. Ses tekrarlanmaz, yeni ses üretilmez.
Çok kısa darbeler, boş kayıtlar ve tamamlanmamış yakalamalar reddedilir.
Genel profil, üç kısa uyandırma referansı, 0,65 benzerlik eşiği ve üç
referanstan en az ikisiyle eşleşme koşulu korunur.

Yeni regresyon testleri kaydın başında, ortasında ve sonunda kısa konuşmayı;
özgün konuşma örneklerinin korunmasını; tek darbe ve eksik kaydın reddini
kapsar. Ses kimliği, profil ekranı, uyandırma ve ses normalizasyonu için
19 Flutter testi geçti. Değişen dosyaların analizinde hata veya uyarı yok;
test dosyasında önceden bulunan iki parantez biçim önerisi var.
Cihazda gerçek sesle son doğrulama henüz yapılmadı.

## Android yerel STT önce, yerel Whisper yedek

Kullanıcı isteği üzerine Android-first modunda, ses kimliği açıkken de
doğrulanmış aynı kayıt önce Android'in cihaz içi STT motoruna verilir.
Android 13+ `EXTRA_AUDIO_SOURCE` ile 16 kHz PCM ve segmented session
kullanılır. Yalnız segmented sonuçlar kabul edilir; ses kaynağını yok sayan
bir motorun yeni mikrofon kaydını doğrulanmış kayıt yerine kullanması önlenir.
Destek yoksa, hata/boş sonuç/zaman aşımı olursa özgün WAV yerel Whisper'a
aktarılır. İptal, yedeği başlatmaz. Android-first modunda bulut Whisper
otomatik yedek olarak kullanılmaz; Whisper ön ısıtması Android ile yarışmaz.

API sözleşmesi: [Android RecognizerIntent](https://developer.android.com/reference/android/speech/RecognizerIntent#EXTRA_AUDIO_SOURCE).

STT yönlendirmesi ve canlı ses yaşam döngüsü için 32 test geçti. Değişen
üretim Dart dosyalarında analiz sorunu yok. Android motorunun bu telefondaki
Türkçe ve harici PCM desteği gerçek cihaz testinde ayrıca doğrulanmalı.

Android `:app:testDebugUnitTest` başarılı (68 saniye); yeni yerel STT
köprüsü Kotlin derlemesinden geçti. Genel Android derleme uyarıları dışında
bu değişiklikte derleme hatası yok.

## Kurulum

Son release derlemesi 152 saniyede başarılı oldu; lib/Kotlin/pubspec kaynak
özetleri derleme başı ve sonunda aynıydı. USB `install -r` başarılı.
Cihaz sürümü 4.4.5 / 58, kurulum zamanı 17 Kasım 2026 16:36:06.
APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.4.5.apk` (84.759.858 bayt).
SHA-256: `9f4082384399bb50235f657e1669fefc3e1062d2d02565c1090889d97954159a`.

Yeni süreçte arka plan PCM akışı ve kısa profilin kullanıldığı görüldü.
16:36:22'de bir KWS adayı 0,49 / 0,65 ile reddedildi; bu adayın kullanıcının
kasıtlı denemesi olduğu doğrulanmadı. Başarılı gerçek sesle uyandırma henüz
kanıtlanmadı. Android yerel STT için telefondaki seçim ve çalışma sonucu
ayrıca kontrol edilecek; kullanıcı ekranı kullandığından UI işlemleri durdu.
