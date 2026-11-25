# Bilgili 3.17.0

3.17.0 sürümünde 23 kategoriye 51.995 yeni, elle yazılmış özgün çoktan seçmeli soru eklendi. Her kategoride 5 yeni alt alan açıldı (toplam 115 yeni alt alan, 345 yeni aile). Banka artık 224.144 soru içeriyor (215.753 özgün soru ve 8.391 seçki sorusu).

- Mevcut 966 özgün ailenin tamamı ve tüm soru kimlikleri korundu; 3.16.0 üzerindeki kayıtlı ilerleme ve istatistikler bozulmadan taşınır.
- Yeni 51.995 sorunun tamamı hem mevcut 172.149 soruluk bankaya hem kendi aralarına karşı tam metin, sayıdan arındırılmış iskelet ve %25 Jaccard sözcük uzaklığı süzgecinden geçirildi; ayrıca soru içi biçim, çapraz atıf ve aşırı uzun şık ipucu denetimleri uygulandı.
- 23 kategorinin her biri 2.049 ile 2.449 arasında yeni özgün soruyla dengeli biçimde genişletildi.

## 3.16.0

3.16.0 sürümünde 23 kategoriye 112.792 yeni, elle yazılmış özgün çoktan seçmeli soru eklendi. Her kategoride 9 yeni alt alan açıldı (toplam 207). Banka artık 172.149 soru içeriyor (163.758 özgün soru ve 8.391 seçki sorusu).

- Her soru, cevap anahtarını görmeyen ayrı bir çözücü tarafından çözüldü. Uyuşmazlıklar ve kusur notları hakem incelemesinden geçti.
- Yeni sorular hem birbirleriyle hem bankadaki sorularla karşılaştırıldı. Aynı bilgiyi soranlar, zamanla eskiyebilecek olanlar ve aynı anlama gelen seçenekler ayıklandı.
- `tool/ozgun/uret.py` içindeki benzerlik denetimi önek süzgeciyle hızlandırıldı. Sonuç aynı kaldı, süre saatlerden saniyelere indi.

## 3.15.1

3.15.1: Sürüm derlemesindeki kaynak küçültme, koddan adıyla çağrılan `res/raw` ses dosyalarını siliyordu; `res/raw/keep.xml` ile korundu. Menü ve oyun müzikleri de bu sürümden itibaren APK'da yer alır.

## 3.15.0

3.15.0 sürümünde Zirve Merdiveni'ne özgün müzik ve ses efektleri eklendi. Bütün sesler `tool/ses/zirve_sesleri.py` ile sentezlenir (hazır kayıt yok) ve `res/raw/zirve_*.ogg` olarak gelir:

- Müzik: açılış teması ve üç gerilim döngüsü (kolay, orta ve zor basamaklar; son basamaklarda kalp atışı).
- Efektler: yeni soru, kesin cevap bekleyişi, doğru, yanlış, baraj, zirve zaferi, joker ve çekilme.
- Ayarlar'daki oyun müziği ve ses efekti anahtarlarına uyar. Yarışma açılış ekranıyla başlar.

## 3.14.0

3.14.0 sürümünde **Gece Stüdyosu** teması (lacivert sahne, altın vurgular; yeni kurulumlarda varsayılan) ve **Zirve Merdiveni** modu eklendi:

- 15 soru: ilk 5 kolay, sonraki 5 orta, son 5 zor; 100 puandan 1.000.000 puana uzanan ödül merdiveni.
- 5. ve 10. basamaklar baraj: geçildikten sonra yanlış cevapta baraj puanıyla ayrılırsın.
- "Kesin cevabın mı?" onayı, gerilimli açıklama, istenen anda çekilme.
- Dört joker: Yarı Yarıya (50:50), Salon Oylaması, Danışman, Soru Değiştir.
- Süre: ilk 5 soru 30 sn, sonraki 5 soru 45 sn, son 5 soru süresiz. En iyi kazanç kaydedilir.

## 3.13.0

3.13.0 sürümünde yeni **Lavanta** teması (mor geçiş, yeşil vurgular; yeni kurulumlarda varsayılan) ve oyun salonu eklendi:

- **Çok Oyunculu › Bire Bir / Çoklu:** bilgisayar rakiplerine (1 ya da 4) karşı aynı sorularda yarış; oyun sırasında canlı sıralama, sonda kürsü.
- **Özel Oda:** kategori, 7/14/21 soru ve 20/40 sn süre seçilir; altı haneli oda numarası bu ayarları ve soruları taşır. Numarayı kopyala ya da paylaş; arkadaşların "Oda No Gir" ile aynı soruları kendi telefonlarında çözer. Odaya 10 oyuncuya kadar ad eklenirse aynı telefonda sırayla oynanır.
- **Etkinlikler:** her gün yeni bir konu etkinliği başlar, 1–3 gün sürer; sabit soru sayısı, sınırlı deneme hakkı, geri sayım ve en iyi puan. "Gelecek" bölümünde yaklaşan etkinlikler görünür.

Uygulama çevrimdışı çalışır; gerçek zamanlı internet eşleşmesi yoktur.

## 3.12.0

3.12.0 sürümünde 23 kategoriye toplam 50.966 yeni, elle yazılmış özgün çoktan seçmeli soru eklendi. Banka artık 59.357 soru içeriyor. Her soru, cevap anahtarını görmeyen ayrı bir çözücü tarafından çözüldü; uyuşmazlıklar ve kusur notları hakem incelemesinden geçti. Ardından her kategoride aynı bilgiyi farklı cümleyle soran sorular, zamanla eskiyebilecek sorular ve aynı anlama gelen seçenekler ayıklandı. Veri `tool/ozgun/uret.py` ile `lib/data/advanced/ozgun/` altına üretilir.

## 3.11.0

Lise öğrencileri için hazırlanmış çevrimdışı Android soru uygulaması. Bu sürümde banka baştan ayıklandı: üniversite soruları ve çoktan seçmeli olmayan soru türleri (doğru/yanlış, boşluk doldurma, sıralama, eşleştirme, dinleme, telaffuz, açık uçlu görev, çoklu seçim) kaldırıldı. Kalan 8.391 sorunun hepsi lise düzeyinde, dört seçenekli ve birbirinden belirgin biçimde ayrışıyor.

## Seçki

Her soru ailesi tek bir kalıptan binlerce vaka üretebilir; bunların çoğu yalnız sayıları ya da birkaç sözcüğü değişen kopyalardır. `tool/secki/` araçları her aileden yalnız birbirinden ayrışan vakaları seçer ve `lib/data/advanced/secki.g.dart` dosyasına yazar:

- Kökler sözcük kümelerine çevrilir (sayılar atılır). En uzak nokta yöntemiyle her aileden, seçilenlere en az %20 uzak en çok 50 vaka alınır. Yalnız sayısı değişen kopyalar elenir.
- Başka bir ailedeki seçilmiş soruya benzeyen ya da aynı olan kökler de elenir.
- Seçkideki 8.443 sorunun tamamı, anahtarı görmeyen çözücülere tek tek çözdürüldü. Uyuşmazlık ya da kusur notu taşıyan 362 soruyu hakem editörler anahtar ve çözümle birlikte yeniden çözdü. Kusurlu bulunan 52 soru (`tool/secki/elenen.txt`) bankadan çıkarıldı.
- Soru kimlikleri özgün vaka numarasını korur; kayıtlı istatistikler aynı sorulara bağlı kalır.

Seçkiyi yeniden üretmek için:

```sh
flutter test --no-pub tool/secki/secki_uret_test.dart
```

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

Sürüm kodu 33, paket adı `com.mehmetderin.bilgiarena` olarak ayarlandı. Kaynak arşivi özel imzalama anahtarını içermez. İş akışı, sürüm APK'sını önbellekte saklanan sabit bir anahtarla imzalar (`BILGILI_IMZA_DOSYASI`); 3.10.0 ve sonraki sürümler birbirinin üzerine kurulur. 3.9.0 ve önceki APK'lar farklı anahtarlar taşıdığından onların üzerine kurulamaz.
