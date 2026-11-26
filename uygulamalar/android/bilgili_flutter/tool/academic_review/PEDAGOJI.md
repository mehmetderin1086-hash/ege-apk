# Bilgili 3.8.0 · Soru bankasının pedagojik incelemesi

Bilgili 3.8.0, 592.093 lise ve 678.346 üniversite sorusu sunuyor. Öğrenci düzeyi, konu, yanıt biçimi ve beklenen düşünme işlemi üzerinden çalışacağı soruları seçebiliyor.

**1.270.439 soru · 383 aile kaydı · 1.078.915 görsel veri içeren soru.**

## Öğrenme görevleri

GPT-6.2 Astra ile hazırlanan ailelerde soru kökü, çözüm yolu, veri aralıkları ve çeldiriciler birlikte tanımlandı. Uygulama bir soruyu açarken ilgili sayısal durumu, veri tablosunu veya kavram seçkisini oluşturuyor. Aynı kimlik her açılışta aynı vakayı getiriyor. Aile sayısına, her biri ayrı bir kayıt olan tekil görsel okuma soruları da dâhildir.

Yaratma görevlerinde öğrenci kendi planını, çözümünü veya tasarımını yazar. Ölçütleri önceden görür ve yanıtını defterine kaydeder. Tur puanını sonraki kontrol sorusu belirler. Yazılı ürünün niteliğini incelemek için ürün ve ölçütler birlikte okunur.

Bloom etiketi sorunun öğrenciden istediği baskın işlemi gösterir. Örneğin bir deney sonucunu ölçütle karşılaştırmak değerlendirme, değişkenleri seçip yeni bir araştırma planı kurmak yaratma görevidir.

### Görsel okuma örnekleri

24 öğretim görseli Higgsfield üzerinden GPT Image 2.6 ile üretildi. Bunlara dayanan 120 tekil görsel okuma sorusu var.

![Taşkın ovası](../../assets/photos/plate01.webp)

**Taşkın ovası**. Öğrenci yay biçimli su alanını ana yatakla karşılaştırarak eski bir menderes olasılığını tartışır. Tasarım görevinde kıyının on yıldaki göçünü ölçmek için sabit referans noktaları ve kesitler seçer.

![Armut ve kumaş](../../assets/photos/plate17.webp)

**Armut ve kumaş**. Öğrenci meyvedeki tarama yoğunluğu ile temas gölgesini inceleyerek hacmi yorumlar. Çalışmayı bakır baskı olarak tanımlayabilmek için özgün eserde hangi fiziksel izlerin aranacağını değerlendirir.

## Bankanın dağılımı

Her soru bir konuya, bir düzeye, bir Bloom basamağına ve bir yanıt biçimine atanır. Grafik, tablo, şema veya levha içeren 1.078.915 sorunun toplam içindeki payı %84,9 düzeyindedir. Görsellik, yanıt biçiminin yanında ayrıca sayılır.

Metin filtresi, görseli ve ayrı bir etkinliği bulunmayan soruları kapsar. Bu tanımla eklenen 1.000.000 sorunun 77.524’ü, yenilenen 270.439 soruyla birlikte tüm bankanın 118.524’ü yalnız metindir. Dinleme ve telaffuz etkinliklerinde cihazın seslendirme ve konuşma tanıma işlevleri kullanılır.

### Düzey

| Dağılım | Soru sayısı |
| --- | ---: |
| Lise | 592.093 |
| Üniversite | 678.346 |

### Bloom basamağı

| Dağılım | Soru sayısı |
| --- | ---: |
| Hatırlama | 32.975 |
| Anlama | 38.646 |
| Uygulama | 745.638 |
| Analiz | 360.917 |
| Değerlendirme | 43.263 |
| Yaratma | 49.000 |

### Yanıt biçimi

| Dağılım | Soru sayısı |
| --- | ---: |
| Çoktan seçmeli | 468.165 |
| Boşluk doldurma | 381.972 |
| Doğru / yanlış | 283.386 |
| Açık uçlu tasarım | 49.000 |
| Eşleştirme | 39.000 |
| Sıralama | 24.000 |
| Dinleme | 15.000 |
| Telaffuz | 5.000 |
| Çoklu seçim | 4.916 |

### Konu

| Dağılım | Soru sayısı |
| --- | ---: |
| Matematik ve Geometri | 200.000 |
| İstatistik ve Veri Bilimi | 133.001 |
| Coğrafya | 125.035 |
| Mühendislik ve Tasarım | 99.835 |
| Fizik ve Astronomi | 98.000 |
| Kimya ve Malzeme | 73.500 |
| Araştırma Yöntemleri | 68.835 |
| Doğa | 57.603 |
| Bilişim ve Algoritmalar | 56.231 |
| Yabancı Dil | 55.000 |
| Biyoloji ve Yaşam Bilimleri | 50.241 |
| Tarih | 50.000 |
| Edebiyat | 45.000 |
| Müzik | 30.000 |
| Spor | 30.000 |
| Ekonomi ve Finans | 26.247 |
| Sanat | 21.020 |
| Toplum ve Sosyal Bilimler | 20.000 |
| Teknoloji | 15.604 |
| Sinema ve TV | 9.000 |
| Bilim | 6.287 |

### Görsel türü

| Dağılım | Soru sayısı |
| --- | ---: |
| Tablo | 651.008 |
| Şema | 197.888 |
| Sütun grafiği | 118.729 |
| Çizgi grafiği | 111.170 |
| Görsel levha | 120 |

## Denetimin kapsamı

1.270.439 vakanın tamamı uygulamanın kullandığı soru üretim yolundan geçirildi. Denetim kimlikleri, düzey ve kategori etiketlerini, seçeneklerin ayrışmasını ve yanıt indekslerini kontrol etti. Boşluk doldurmada kabul edilen anahtar ve reddedilmesi gereken çeldiriciler denendi.

Tekrar taraması, soru kökünü ve öğrenciye sunulan verileri birlikte karşılaştırdı. Şık sırası, geri bildirim ve kayıt kimliği tek başına yeni vaka sayılmadı. Sonuç 1.270.439 farklı vaka imzasıydı. Aynı ailedeki sorular ortak bir düşünme işlemini farklı verilerle çalıştırabilir.

### İçerik denetimlerinden örnekler

**Matematik**. 50 ailedeki 250.000 matematik ve istatistik anahtarı ayrı bir kesin aritmetik hesabıyla yeniden çözüldü. Sonuçlar üretilen anahtarlarla eşleşti.

**Bağımsız çözüm**. Ayrı çözüm denetimi, görünür verilerle 134 aileden 632.000 sayısal ve uygulamalı yanıtı doğruladı. Dil ve edebiyatta 18 aileden 90.000 yanıt için metinler, seslendirme dökümleri ve başvuru listeleri kullanıldı. Bu iki grupta anahtarlarla uyuşmazlık görülmedi.

**Etkileşim ve yerleşim**. Müzik, sanat, sinema ve spor kapsamındaki 90.000 soruda uygulamanın sunduğu yanıt türleri ve etkinlik dizileri sınandı. Bu bölümdeki her görsel aileden bir örnek 320 piksel genişliğinde açılarak yerleşimi kontrol edildi.

**Çoklu seçim**. Hız–zaman grafiği içeren 4.900 vakada dört önermenin her biri ayrıca sınandı. 19.600 önerme kararı doğrulandı ve on farklı doğru seçenek kümesi gözlendi.

**Yazılı yanıt**. İlk kontrolde birbirine çok yakın olasılık kesirlerinde 769 yanlış kabul bulundu. Kesirlerin tam aritmetikle karşılaştırılmasından sonra aynı denetimde bu hatalar giderildi.

**Görsel okuma**. 24 levhaya bağlı 120 tekil sorunun görsel dayanağı ayrıca incelendi. Örneğin akarsu kıvrımının iç kıyısındaki birikime ilişkin ifade, görseldeki konumla uyumlu olacak şekilde netleştirildi.

### Sonuçların yorumu

Bu sürüm için öğrenci yanıtlarından hesaplanmış madde güçlüğü, ayırt edicilik veya test güvenirliği katsayısı raporlanmadı. Düzey ve Bloom etiketleri içerik tasarımındaki sınıflandırmayı gösterir. Benzer varyantları çözen bir öğrencinin beceriyi yeni bir bağlama aktarabildiği, farklı bir aileden görevle ayrıca sınanabilir.

Denetim dosyaları: ozet.json, aile-ornekleri.json ve aile başına sıkıştırılmış soru kayıtları. Kaynak kod: tool/academic_review/review_test.dart ve lib/data/advanced/.
