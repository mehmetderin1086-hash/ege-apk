# Bilgili 3.8.0

Lise ve üniversite düzeyleri için hazırlanmış çevrimdışı Android soru uygulaması. Bu sürümde 3.7.1 bankasındaki 270.439 sorunun yerine akademik içerik yazıldı ve 1.000.000 soru eklendi. Toplam 1.270.439 sorunun kalıcı birer kimliği var. Uygulama soru ailelerinden seçilen kaydı cihazda oluşturur. Böylece her oyun açılışında tüm bankayı belleğe alması gerekmez.

## Uygulamada

Akademi bölümünde konu, düzey, Bloom basamağı veya soru türü seçilebilir. Bankada çoktan seçmeli, çoklu seçim, doğru/yanlış, boşluk doldurma, sıralama, eşleştirme, dinleme, telaffuz ve açık uçlu üretim soruları vardır. Üretim görevlerinde öğrenci kendi yanıtını ölçütlere göre yazar. Yanıt çalışma defterine kaydedilir. Oyun bu etkinlikteki ayrı kontrol sorusunu puanlar. Sesli etkinlikler Android cihazın konuşma hizmetlerini kullanır.

## Soru üretimi ve pedagojik denetim

GPT-6.2 Astra ile yazılan aileler, hedef kazanım, düzey, Bloom basamağı, çözüm kuralı ve çeldiricileri bir araya getirir. Varyantlarda kullanılan veri, koşul, metin veya görsel kanıt değişir. Aileler `lib/data/advanced/` altındadır. Higgsfield üzerinden GPT Image 2.6 ile üretilen 24 görsel `assets/photos/plate*.webp` dosyalarındadır. Görsel listesi ve üretim kayıtları `tool/academic_review/gorseller.json` dosyasındadır.

Flutter bağımlılıklarını yükledikten sonra şu komutlarla uygulamayı sınayabilir, bankanın tamamını yeniden üretip denetleyebilir ve APK oluşturabilirsiniz.

```sh
flutter pub get
flutter test
tool/academic_review/run.sh build/academic-review
flutter build apk --release
```

Tam tarama, oyunun sunduğu her soru kimliğini açarak soru kökü, kanıt, cevap anahtarı, seçenekler, yazılı yanıt eşdeğerliği, etkinlik çözümü, görsel varlıklar ve açık uçlu görev ölçütlerini kontrol eder. Aynı kök ve kanıt çiftini yakalamak için şık sırasını ve kimliği tekrar denetiminin dışında tutar. Her aile için sıkıştırılmış JSON Lines kayıtları, dağılımları içeren `ozet.json` ve aile örneklerini içeren `aile-ornekleri.json` üretilir. İçerik incelemesi ve yöntem sınırları `tool/academic_review/PEDAGOJI.md` dosyasındadır.

Sürüm kodu 30, paket adı `com.mehmetderin.bilgiarena` olarak ayarlandı. Yayımlanan 3.8.0 APK’sı, önceki 3.7.1 teslimiyle aynı sertifikayla imzalandı. 3.7.0 APK’sı farklı bir sertifika taşır. Kaynak arşivi özel imzalama anahtarını içermez.
