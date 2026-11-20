# Mehmet Asistan build 33 — Antigravity Gemini Flash Live yedeği

- Live geri dönüş seçimi `gemini-3.8-flash` modelini ilk sıraya alır. iPhone CLIProxy, Antigravity hesabı bağlıyken bu adı Antigravity Gemini 3.8 Flash yoluna yönlendirir.
- İlk fiziksel sabit-metin Live turu `gemini-3.8-flash` ile tamamlandı: ilk ses 6,735 sn, toplam 10,592 sn, hata yok ve mikrofon yeniden dinlemeye döndü.
- İkinci turda otomatik yedek `gpt-6.1-sol` ile tamamlandı: ilk ses 13,722 sn, toplam 15,835 sn, hata yok ve mikrofon yeniden dinlemeye döndü.
- iPhone'da 66 CLIProxy modeli listelendi; Antigravity Claude, Gemini ve GPT-OSS modelleri görünür durumda.
- Simülatörde 143 test / 35 takım geçti. `telefona-kur.sh` build 33'ü ekran paylaşımı açmadan fiziksel iPhone'a kurdu ve başlattı.

Bu kabul sabit test metni kullanır; gerçek kullanıcı sesiyle Hey Asistan uyandırmasını veya gerçek Gemini çift yönlü Live WebSocket'ini doğrulamaz.

## Build 35 — Hey Asistan kısa ifade tanıması

- Uyandırma beklemesi, Apple Speech `phrase` ön ayarını kullanır; normal ve Live diktesi `progressiveShortDictation` olarak kalır.
- Fiziksel iPhone'da build 35 kuruldu. Otomatik testte mikrofon -32,66 dB, dinleyici `dinliyor` ve bekleme etkin kaldı.
- Hoparlörden verilen test cümlesi yalnız `Asistan` olarak tanındı; katı “Hey Asistan” kuralı korunduğu için uyanma olmadı. Bu kontrollü ses kullanıcının gerçek ses kabulü değildir.
- Simülatörde 143 test / 35 takım geçti. Ekran paylaşımı açılmadı.

## Build 38 — Cihaz içi Hey Asistan dil modeli

- `Hey Asistan` ve `Hey Assistant` ifadeleri için küçük cihaz içi Speech dil modeli hazırlanır; hazırlama başarısızsa kısa ifade ön ayarıyla devam edilir.
- Fiziksel iPhone otomatik kabulü: `sonTaninanMetin: Hey asistan`, `ilkUyandi: true`, `uyandi: true`, dinleyici `dinliyor`, giriş −31,38 dB.
- Simülatörde 143 test / 35 takım geçti. Build 38 ekran paylaşımı açılmadan kuruldu.
- Test hoparlörden üretilen ses kullanır; gerçek kullanıcı sesinin ayrı kabulü hâlâ gereklidir.

## 0.16–0.21 son fiziksel paket denetimi

- 18 Ekim 2026'da gerçek iPhone 15 üzerinde `AsistanTests` paketi doğrudan çalıştırıldı: 35 takımda 143 test geçti.
- Aynı turda normal Mehmet Asistan uygulaması yeniden başlatıldı; `devicectl` başlatmayı başarılı bildirdi (işlem kimliği 2531).
- Bu denetimde ekran paylaşımı ya da iPhone ekran yansıtma kullanılmadı.

## Live uç nokta ve güncel Gemini Bidi şeması

- iPhone'daki uzaktan temel URL zaten `/v1` içerdiği halde Live token isteğinin yeniden `v1` eklemesi fiziksel tanıda 404 verdi. Görev, rutin ve Live token için ortak adres üreticisi eklendi; fiziksel iPhone tanısı ardından 200 ve `gemini-3.8-live` döndürdü.
- VPS, mevcut sunucu ortamındaki Gemini anahtarını yalnız çalışma sürecinde kullanacak şekilde güncellendi. Güncel geçici-token gövdesi `bidiGenerateContentSetup`, istemci ilk mesajı ise `generationConfig.responseModalities` kullanır. 14 VPS testi ve 144 iOS testi geçti; yeni Live adresi/Bidi şeması testleri fiziksel iPhone'da da geçti.
- Ham sağlayıcı WebSocket denemesi, istek şeması yerine sağlayıcı hesabının ön ödeme kredisinin tükendiğini bildirdi. Uygulama bu durumda standart sıralı Live'a geri döner; kalıcı anahtar iPhone'a yazılmaz.
