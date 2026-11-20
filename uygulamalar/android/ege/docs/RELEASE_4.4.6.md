# Ege 4.4.6 (59)

Son kullanıcı talebi: “Whisper'ı kullanma.” Önceki yedek motor isteğinin
yerine geçer. Ana konuşma çözümlemesi, hata/iptal/eksik dil modeli durumları,
uyandırma yedeği ve eski tanılama girişleri Whisper çalıştırmaz. Eski ayarda
Whisper seçilmiş olsa da STT Android yerel motora gider. Otomatik Whisper
model indirme ve ön ısıtma kapalıdır. Ayarlardaki Whisper seçenekleri kaldırıldı.
Var olan model dosyaları ve anahtarlar silinmez.

4.4.5 gerçek cihaz kaydında Android yerel STT üç kez önce denendi
(`START engine=phone_local source=verified_pcm`), ancak 66–111 ms sonra
`ERROR_13` döndü. Android API'de bu, istenen dilin desteklendiği ancak
şu anda kullanılabilir olmadığı anlamına gelir; örneğin model indirilmemiş
olabilir. Telefonun STT seçiminin açık olduğu UI'da da doğrulandı.

Android-first modunda açılışta Türkçe cihaz içi dil desteği kontrol edilir.
Dil destekleniyor ancak kurulu değilse Android model indirme API'si çağrılır.
Çalışma sırasında hata 13 gelmesi de bu hazırlığı başlatır. İstekler
sınırlandırılır; ilerleme sonucunda hazır/kuyrukta/hata durumları metin veya
ses içermeyen tanılama kayıtlarına yazılır. Android indirme için kendi
onay ekranını gösterebilir. Android hazır değilse hata bildirilir; başka
STT motoruna geçilmez. Hey Ege'nin yerel anahtar sözcük algılayıcısı korunur.

Canlı dinleme ve STT ayarlarında eski, her durumda Whisper kullanıldığını
söyleyen açıklamalar düzeltildi. Kısa uyandırma sesi ve Android-first aynı
kayıt yönlendirmesi 4.4.5'ten korunur.

Kaynak: [Android SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer#ERROR_LANGUAGE_UNAVAILABLE)
ve [model indirme API'si](https://developer.android.com/reference/android/speech/SpeechRecognizer#triggerModelDownload(android.content.Intent)).

Android-only testleri eski Whisper seçimi, hatalar, iptal, otomatik indirme
ve eski tanılama yollarında Whisper'ın çağrılmadığını kapsar. Native test
eski transcribe girişinin modeli yüklemeden reddedildiğini denetler.
30 odaklı Flutter testi geçti. Android `:app:testDebugUnitTest` başarılı;
WhisperDisabledTest dahil. Bilgisayardaki yoğunluk ve yeni Gradle süreci
nedeniyle native görev 16 dakika 30 saniye sürdü. Dart analizinde hata yok;
bulunan iki kullanılmayan import kaldırıldı, biçim önerileri bırakıldı.
Release APK 814,9 saniyede başarıyla derlendi. Kaynak özetleri derleme
başında ve sonunda aynıydı. USB `install -r` başarılı; cihaz sürümü
4.4.6 / 59, güncelleme zamanı 17 Kasım 2026 17:23:02.

APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.4.6.apk` (84.628.526 bayt).
SHA-256: `b3478fc85204351b8b4b46b9087d7b25c5d5be357cf4b6ce68952464ee15269b`.

Yeni süreçte `LOCAL_FALLBACK disabled_by_user; engine=keyword_spotter`
ve devam eden PCM/decoder sayaçları doğrulandı. Android Türkçe dil kontrolü
`MODEL language=tr-TR status=SCHEDULED` döndü; hazır olduğu henüz doğrulanmadı.
Google Android System Intelligence model indirme işlerinde `NOT_METERED`
ağ koşulu ve karşılanmayan `CONNECTIVITY` görüldü; telefon mobil veri
bağlantısında. Kullanıcıdan Wi-Fi bağlantısı ve ayrı bir gerçek Hey Ege
denemesi istendi. Bekleyen modelin hazır olduğu veya uyandırmanın başarılı
olduğu varsayılmadı. Whisper'a geri dönüş yapılmadı.
Gerçek kullanıcı sesiyle başarılı Hey Ege uyandırması henüz doğrulanmadı.
