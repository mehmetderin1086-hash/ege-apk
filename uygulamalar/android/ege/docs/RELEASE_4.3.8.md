# Ege 4.3.8 (51)

Asistanın görünen adı Ege, uyandırma sözü **Hey Ege** oldu. Ana ekran, ayarlar, canlı ses, bildirimler ve asistan kimliği güncellendi. Android paket kimliği ve veri anahtarları korunur; güncelleme mevcut uygulamaya kurulur. Eski kişilik metnindeki Jarvis adı Ege'ye taşınır, model/anahtar/geçmiş tercihleri korunur.

## Uyandırma değişikliği

- Önceki 4.3.6 sürümünde gerçek kullanıcı iki denemede de Hey Jarvis ile açılmadığını bildirdi. PCM ve çözümleme sayaçlarının artması, başarılı uyandırma olarak değerlendirilmedi.
- Mevcut İngilizce KWS modelinde doğrudan HEY EGE yazımı dört Türkçe yapay ses örneğinin hiçbirini yakalamadı. Aynı modelin fonetik çıktıları ölçülerek AGA/AGAIN yolları seçildi; kullanıcıya gösterilen söz Hey Ege olarak kaldı.
- Tek model üzerinde doğal ses ve seviyesi artırılmış ses için iki akış çalışır. Algılama tek olay olarak bildirilir; her iki akış birlikte sıfırlanır ve kapatılır. Sessiz ünsüzlerde kazanç hemen düşürülmez; uzun sessizlikte normale döner. Dijital sessizlik sıfır kalır.
- Varsayılan duyarlılık 0,5 için skor 2,0 ve eşik 0,08 kullanıldı. Skor 2,5 / eşik 0,06 denemesi eski Hey Jarvis örneklerinde yanlış tetiklediği için kullanılmadı. Daha yüksek duyarlılık seçimi aynı yanlış tetikleme riskini taşıyabilir.
- Yerel Whisper yedeği Hey Ege ve ölçülen yakın yazımlarını kabul eder; tek başına Ege, Ege bölgesi, Hey gece/Ece ve eski Hey Jarvis ifadesi kabul edilmez.
- Ayarlara 30 saniyelik tanılama eklendi. Ses seviyesi, Android mikrofon susturması, algılama sayısı ve yerel TR/EN çözümleyicinin duyduğu metin görünür. Bu testte canlı ekran açılmaz. Ses diske/ağa yazılmaz; tanılama metni yalnız bellektedir ve pencere kapanınca temizlenir.

## Doğrulama

- Tam Flutter paketi: **184 test geçti**. Ayar taşıma, ad/komut sınırları, tanılama penceresi ve ses seviyesi işlemleri dahil.
- `flutter analyze --no-pub`: sorun bulunmadı.
- Native JVM: **22 test geçti**; uyandırma eşleştirmesi, kuyruk ve sağlık denetimi dahil.
- Yapay Türkçe kadın/erkek sesleri, aynı model ve üretimdeki normalleştirme ile masaüstünde denendi. Normal genlikte 4/4, genliğin onda birinde 4/4, yüzde birinde 3/4 algılandı. 15 negatif örneğin üç seviyedeki toplam 45 denemesinde tetikleme görülmedi. Negatifler farklı cümleler, oda gürültüsü ve eski Hey Jarvis örneklerini içerir. Bu sınırlı sentetik örnekler gerçek kullanıcı sesinin veya telefon mikrofonunun yerine geçmez.
- Kanıt günlükleri geliştirme bilgisayarında: `C:/tmp/kws/ege-dual.log`, `ege-sensitive.log`, `ege-asr.log`, `C:/tmp/ege-438-final-tests.log`, `C:/tmp/ege-438-jvm.log`.

## Devam eden doğrulama

Kullanıcının gerçek sesiyle, uygulama içinde ve başka uygulama açıkken Hey Ege denemesi gereklidir. 4.3.6'daki uygulama/web/iletişim düzeltmeleri bu sürümde korunur; kapsam ve sınırlamalar için `RELEASE_4.3.6.md` dosyasına bakın.

## Telefon kurulumu — 17 Kasım 2026

- ARM64 release APK başarıyla derlendi. Paket incelemesi: uygulama adı Ege, versionName 4.3.8, versionCode 51. `adb install -r` başarılı; telefonun paket yöneticisinde aynı sürüm doğrulandı. Ana ekran ve mevcut sohbet geçmişi görüldü.
- APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.3.8.apk`
- SHA256: `AA13D89787C2BD379AAD0D833387BFABA52223107C688CA6D02562E462C4B93C`
- 10:58:44'te mikrofon açıldı (`silenced=false`). 10:58:46'da `HIT source=kws`, `SHOW_ASSISTANT accepted=true`, `SESSION_SHOW source=wake` ve `ACTIVITY_LAUNCH source=wake` kaydedildi. Sonraki UI incelemesinde Canlı Ses ekranı ve “Saat 10:58, efendim.” yanıtı görüldü. Bu olayın kullanıcının kasıtlı sözüyle başladığı ve arka planda tekrarlanabildiği henüz kullanıcı tarafından doğrulanmadı; yanlış tetikleme olasılığı dışlanmış değildir.
- Foreground mikrofon servisi, asistan ve erişilebilirlik servisleri bağlı. Telefon araması sonlandırma izinleri daha önce verilmemişti; izin akışı ve gerçek çağrı kapatma ayrıca doğrulanmalıdır.
- Ekrana müdahale edilmeden sonraki gözlemde Spotify ve Mesajlar ön planda görüldü. 11:01:26'da dinleme yeniden başladı; 11:01:31'de 51 PCM parçasına karşılık 80.000 örnek çözülmüştü (`silenced=false`). Çift akışın bu beş saniyelik kesitte gerçek zamana yetiştiği görüldü; bu kısa gözlem pil tüketimi veya uzun süreli arka plan kararlılığı testi değildir. Günlük: `C:/tmp/ege-438-device-wake.log`.
