# Ege 4.4.7+60 — Android STT ile uyandırma kontrolü

4.4.6 cihaz denemesinde PCM ve algılayıcı sayaçları ilerlediği halde KWS adayı oluşmadı. Android Türkçe STT modeli son kontrol sırasında indirme kuyruğundaydı. Bu sürüm, KWS'nin kaçırdığı Türkçe söyleyişleri Android'in cihaz içi STT motoruyla denemek için ikinci bir yol ekler. Gerçek kullanıcı sesiyle başarı henüz doğrulanmadı.

- Servis, mevcut mikrofon akışından kısa konuşma parçaları çıkarır. İkinci mikrofon açmadan Android STT'ye aynı PCM'i verir.
- Yalnız Android'in parçalı, verilen ses kaynağına ait sonuçları kabul edilir; genel mikrofon sonuçlarına veya Whisper'a geçilmez.
- Hey Ege eşleşmesi sonrasında kullanıcının ses filtresi açıksa aynı ses parçası mevcut ses profiliyle doğrulanır. Profil ve eşikler değiştirilmez.
- Dil modeli eksik olduğunda 60 saniye, geçici motor hatalarında 5 saniye beklenir. Sessizlik ve normal sonuçlar yeni konuşmayı geciktirmez.
- İşlem sırasında yalnız en yeni kısa parça tutulur. Eski oturuma ait ya da 8 saniyeden eski parçalar atılır. Canlı konuşmaya geçişte bekleyen Android çözümlemesi iptal edilir.
- Whisper kapalıdır; eski uyandırma çözümleme çağrıları da kaldırılmıştır. Ses kayıtları diske kaydedilmez.

Doğrulama: `:app:testDebugUnitTest` başarılı; 33 test, 0 hata/başarısızlık. Yeni `WakePhoneRetryTest` (2), mevcut `WakeSpeechGateTest` (9) ve `WhisperDisabledTest` (1) dahil. Android kaynakları derlendi. Gerçek cihaz uyandırma başarısı bu testlerden çıkarılamaz; kurulum sonrası kontrol gerektirir.

Cihazın cihaz içi tanıma hizmeti `com.google.android.as/...AiAiSpeechRecognitionService` olarak doğrulandı. Wi-Fi anahtarı bir süre açık olmasına rağmen `cmd wifi status` bağlı ağ göstermedi; son kontrolde yeniden kapalıydı. Dil modelinin `SCHEDULED` durumu başarı/indirildi anlamına gelmez.
