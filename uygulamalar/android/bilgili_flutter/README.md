# Bilgili 3.9.0

Lise ve üniversite düzeyleri için hazırlanmış çevrimdışı Android soru uygulaması. Bu sürümde 3.8.0 bankasına lise düzeyinde, yalnız metinden oluşan 1.000.000 soru eklendi. Toplam 2.270.439 sorunun (1.592.093 lise, 678.346 üniversite) kalıcı birer kimliği var. Uygulama soru ailelerinden seçilen kaydı cihazda oluşturur. Böylece her oyun açılışında tüm bankayı belleğe alması gerekmez.

## Uygulamada

Akademi bölümünde konu, düzey, Bloom basamağı veya soru türü seçilebilir. Bankada çoktan seçmeli, çoklu seçim, doğru/yanlış, boşluk doldurma, sıralama, eşleştirme, dinleme, telaffuz ve açık uçlu üretim soruları vardır. Üretim görevlerinde öğrenci kendi yanıtını ölçütlere göre yazar. Yanıt çalışma defterine kaydedilir. Oyun bu etkinlikteki ayrı kontrol sorusunu puanlar. Sesli etkinlikler Android cihazın konuşma hizmetlerini kullanır.

Yeni sorular paketler bölümünde “Lise · Metin Soru Bankası” paketinde toplanır. Konu, sınav (TYT, AYT), ders ve “Metin” biçim filtreleriyle de seçilebilirler.

## Lise metin bankası

`lib/data/advanced/lise_metin/` altındaki 10 dosyada 200 aile vardır. Her aile tek bir kazanımı sınar ve 5.000 ayrı soru üretir.

| Alan | Aile | Soru |
| --- | ---: | ---: |
| Temel matematik (TYT) | 20 | 100.000 |
| İleri matematik (AYT) | 20 | 100.000 |
| Geometri ve analitik geometri | 20 | 100.000 |
| Sayma, olasılık, veri, mantık ve finans | 20 | 100.000 |
| Fizik: mekanik, enerji, basınç, ısı | 20 | 100.000 |
| Fizik: elektrik, dalgalar, optik, modern fizik | 20 | 100.000 |
| Kimya | 20 | 100.000 |
| Biyoloji | 20 | 100.000 |
| Coğrafya (12 aile) ve tarih (8 aile) | 20 | 100.000 |
| Türk dili ve edebiyatı (10 aile) ve İngilizce (10 aile) | 20 | 100.000 |

Her vaka soru kökünü, doğru yanıtı, öğrencilerin tipik hatalarından türetilen üç çeldiriciyi ve o vakanın sayılarıyla yazılmış çözümü sıra numarasından hesaplar. Yazım kuralları `tool/lise_metin/YAZIM_KILAVUZU.md` dosyasındadır.

Bankanın denetimi şu adımlardan geçti:

- `tool/lise_metin/denetim.dart` her vakayı açar. Biçimi, kök tekliğini, seçeneklerin değerce farklı olmasını, yazılı yanıt eşdeğerliğini ve doğru/yanlış önermelerini sınar.
- Her aileden alınan örnekler, kodu ve anahtarı görmeyen ayrı çözücülere çözdürüldü ve sonuçlar anahtarla karşılaştırıldı: kimyada bir, diğer alanlarda iki tur, toplam 1.900 örnek. Hiçbirinde anahtar uyuşmazlığı çıkmadı.
- Her alanın kaynağı ayrıca baştan sona incelendi. Gerçekçi olmayan büyüklükler, belirsiz ifadeler, kesin olmayan olgular ve yanlış bir yöntemin tesadüfen doğru yanıtı verdiği parametreler düzeltildi. Düzeltilen ailelerden yeni örnekler yeniden çözüldü.
- Sayısal alanların çoğunda 5.000 vakanın tamamı, kökteki sayılardan bağımsız çözücülerle yeniden hesaplandı.

## Soru üretimi ve pedagojik denetim

GPT-6.2 Astra ile yazılan aileler, hedef kazanım, düzey, Bloom basamağı, çözüm kuralı ve çeldiricileri bir araya getirir. Varyantlarda kullanılan veri, koşul, metin veya görsel kanıt değişir. Aileler `lib/data/advanced/` altındadır. Higgsfield üzerinden GPT Image 2.6 ile üretilen 24 görsel `assets/photos/plate*.webp` dosyalarındadır. Görsel listesi ve üretim kayıtları `tool/academic_review/gorseller.json` dosyasındadır.

Flutter bağımlılıklarını yükledikten sonra şu komutlarla uygulamayı sınayabilir, bankanın tamamını yeniden üretip denetleyebilir ve APK oluşturabilirsiniz.

```sh
flutter pub get
flutter test
flutter test tool/lise_metin/tumu_test.dart
tool/academic_review/run.sh build/academic-review
flutter build apk --release
```

Tam tarama, oyunun sunduğu her soru kimliğini açarak soru kökü, kanıt, cevap anahtarı, seçenekler, yazılı yanıt eşdeğerliği, etkinlik çözümü, görsel varlıklar ve açık uçlu görev ölçütlerini kontrol eder. Aynı kök ve kanıt çiftini yakalamak için şık sırasını ve kimliği tekrar denetiminin dışında tutar. Her aile için sıkıştırılmış JSON Lines kayıtları, dağılımları içeren `ozet.json` ve aile örneklerini içeren `aile-ornekleri.json` üretilir. İçerik incelemesi ve yöntem sınırları `tool/academic_review/PEDAGOJI.md` dosyasındadır; bu belge 3.8.0 bankasını anlatır.

Sürüm kodu 31, paket adı `com.mehmetderin.bilgiarena` olarak ayarlandı. Kaynak arşivi özel imzalama anahtarını içermez. Bu depodaki iş akışının derlediği APK, 3.8.0 teslimiyle aynı sertifikayı taşımaz; telefonda kurulu sürümün üzerine yüklenemez.
