# Bilgili 3.10.0

Lise ve üniversite düzeyleri için hazırlanmış çevrimdışı Android soru uygulaması. 3.9.0 sürümünde 3.8.0 bankasına lise düzeyinde, yalnız metinden oluşan 1.000.000 soru eklenmişti; bu sürümde 1.000.000 soru daha eklendi. Toplam 3.270.439 sorunun (2.592.093 lise, 678.346 üniversite) kalıcı birer kimliği var. Uygulama soru ailelerinden seçilen kaydı cihazda oluşturur. Böylece her oyun açılışında tüm bankayı belleğe alması gerekmez.

## Uygulamada

Akademi bölümünde konu, düzey, Bloom basamağı veya soru türü seçilebilir. Bankada çoktan seçmeli, çoklu seçim, doğru/yanlış, boşluk doldurma, sıralama, eşleştirme, dinleme, telaffuz ve açık uçlu üretim soruları vardır. Üretim görevlerinde öğrenci kendi yanıtını ölçütlere göre yazar. Yanıt çalışma defterine kaydedilir. Oyun bu etkinlikteki ayrı kontrol sorusunu puanlar. Sesli etkinlikler Android cihazın konuşma hizmetlerini kullanır.

Lise metin soruları paketler bölümünde “Lise · Metin Soru Bankası” paketinde toplanır. Konu, sınav (TYT, AYT), ders ve “Metin” biçim filtreleriyle de seçilebilirler.

## Lise metin bankası

`lib/data/advanced/lise_metin/` altındaki 20 dosyada 400 aile vardır. Her aile tek bir kazanımı sınar ve 5.000 ayrı soru üretir.

| Alan | Sürüm | Aile | Soru |
| --- | --- | ---: | ---: |
| Temel matematik (TYT) | 3.9.0 | 20 | 100.000 |
| İleri matematik (AYT) | 3.9.0 | 20 | 100.000 |
| Geometri ve analitik geometri | 3.9.0 | 20 | 100.000 |
| Sayma, olasılık, veri, mantık ve finans | 3.9.0 | 20 | 100.000 |
| Fizik: mekanik, enerji, basınç, ısı | 3.9.0 | 20 | 100.000 |
| Fizik: elektrik, dalgalar, optik, modern fizik | 3.9.0 | 20 | 100.000 |
| Kimya | 3.9.0 | 20 | 100.000 |
| Biyoloji | 3.9.0 | 20 | 100.000 |
| Coğrafya (12 aile) ve tarih (8 aile) | 3.9.0 | 20 | 100.000 |
| Türk dili ve edebiyatı (10 aile) ve İngilizce (10 aile) | 3.9.0 | 20 | 100.000 |
| Sayılar ve cebir (TYT) | 3.10.0 | 20 | 100.000 |
| Trigonometri, logaritma, türev ve integral (AYT) | 3.10.0 | 20 | 100.000 |
| Geometri: açılar, üçgenler, dörtgenler, çember, katı cisimler | 3.10.0 | 20 | 100.000 |
| Bilişim: sayı tabanları, mantık kapıları, algoritmalar | 3.10.0 | 20 | 100.000 |
| Fizik: vektörler, çarpışmalar, Kepler, görelilik, atom, alternatif akım | 3.10.0 | 20 | 100.000 |
| Kimya: temel kanunlar, adlandırma, çözünürlük, asit-baz, denge, organik | 3.10.0 | 20 | 100.000 |
| Biyoloji: hücre, sistemler, soy ağacı, bitki biyolojisi | 3.10.0 | 20 | 100.000 |
| Coğrafya: güneş ışınları, saat dilimleri, iklim, yer şekilleri, Türkiye | 3.10.0 | 20 | 100.000 |
| Tarih (12 aile) ve felsefe-mantık (8 aile) | 3.10.0 | 20 | 100.000 |
| Türk dili (10 aile) ve İngilizce (10 aile) | 3.10.0 | 20 | 100.000 |

Her vaka soru kökünü, doğru yanıtı, öğrencilerin tipik hatalarından türetilen üç çeldiriciyi ve o vakanın sayılarıyla yazılmış çözümü sıra numarasından hesaplar. Yazım kuralları `tool/lise_metin/YAZIM_KILAVUZU.md` dosyasındadır.

Bankanın denetimi şu adımlardan geçti:

- `tool/lise_metin/denetim.dart` 2.000.000 vakanın her birini açar. Biçimi, kök tekliğini (alanlar arasında da), seçeneklerin değerce farklı olmasını, yazılı yanıt eşdeğerliğini ve doğru/yanlış önermelerini sınar.
- 3.10.0 ailelerinin yazarları her ailenin 5.000 vakasını kökteki verilerden bağımsız çözücülerle yeniden hesapladı. Kodu ve anahtarı görmeyen çözücüler her alandan iki tur örnek çözdü, editörler uyuşmazlıkları ve kaynak kodu inceledi, düzeltilen ailelerden yeni örnekler yeniden çözüldü (toplam 2.335 örnek). Çıkan iki uyuşmazlık, doğru sayılabilecek bir çeldiricinin bulunduğu bir İngilizce cümleydi; cümle değiştirildi.
- `tool/lise_metin/ipucu.dart` bilgisiz bir öğrencinin yalnız seçeneklerin biçiminden anahtarı bulup bulamayacağını ölçer: öge ve konum çoğunluğu, sözcük benzerliği, en uzun seçenek ve sayısal seçeneklerde anahtarın değer sırası. 3.9.0 ailelerinin bir bölümünde bu yollar anahtarı vakaların tamamında buluyordu (örneğin ölçek sorularında anahtar hep ikinci en küçük değerdi). Bu sürümde 400 ailenin çeldiricileri, kökler ve anahtarlar değişmeden yeniden seçildi; hiçbir ailede hiçbir yol %40'tan fazla başarı sağlamaz (rastgele seçim %25). Değişen ailelerden alınan yeni örnekler yeniden kör çözüldü.

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

Tam tarama, oyunun sunduğu her soru kimliğini açarak soru kökü, kanıt, cevap anahtarı, seçenekler, yazılı yanıt eşdeğerliği, etkinlik çözümü, görsel varlıklar ve açık uçlu görev ölçütlerini kontrol eder. Aynı kök ve kanıt çiftini yakalamak için şık sırasını ve kimliği tekrar denetiminin dışında tutar. Her aile için sıkıştırılmış JSON Lines kayıtları, dağılımları içeren `ozet.json` ve aile örneklerini içeren `aile-ornekleri.json` üretilir. İçerik incelemesi ve yöntem sınırları `tool/academic_review/PEDAGOJI.md` dosyasındadır; bu belge 3.8.0 bankasını anlatır. Seçenek biçiminden ipucu taraması `flutter test tool/lise_metin/ipucu_test.dart` ile çalışır.

Sürüm kodu 32, paket adı `com.mehmetderin.bilgiarena` olarak ayarlandı. Kaynak arşivi özel imzalama anahtarını içermez. İş akışı, sürüm APK'sını önbellekte saklanan sabit bir anahtarla imzalar (`BILGILI_IMZA_DOSYASI`); 3.10.0'dan sonraki sürümler bunun üzerine kurulur. 3.9.0 ve önceki APK'lar farklı anahtarlar taşıdığından onların üzerine kurulamaz.
