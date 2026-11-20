# Bilgi Arenası soru dosyası — JSON v1

Dosya uzantısı `.json`, metin kodlaması UTF-8. Dışa aktarımın kökü:

```json
{"schemaVersion":1,"questions":[...]}
```

[İki soruluk doğrudan içe aktarılabilir örnek](sample-import.json). Uygulamadaki **Örnek JSON ve biçim rehberini indir** seçeneği tüm desteklenen görsel ve etkinlik türlerini içeren dosyayı üretir. Eski `QuestionPack` nesnesinin `questions` dizisi, doğrudan soru dizisi veya tek soru nesnesi de alınır. Desteklenmeyen `schemaVersion` reddedilir.

## Temel alanlar

| Alan | Biçim |
|---|---|
| `text` | Soru metni |
| `category` | Bilim, Tarih, Coğrafya, Sanat, Spor, Genel Kültür, Sinema ve TV, Yabancı Dil, Sınav Hazırlık veya Özel Konu |
| `difficulty` | Kolay, Orta veya Zor |
| `options` | Dört farklı yanıt metni |
| `answer` | Doğru yanıtın sıfırdan başlayan indeksi: 0–3 |
| `explanation` | Doğru yanıtın açıklaması |
| `optionExplanations` | İsteğe bağlı dört şık gerekçesi |
| `study` | Yalnız Sınav Hazırlık için `{"exam":"TYT","lesson":"Biyoloji"}`; ders isteğe bağlı |
| `activity` | Aşağıdaki etkinlik nesnesi; isteğe bağlı |
| `visual` | Görsel nesnesi; isteğe bağlı, `activity` ile aynı soruda bulunamaz |

`study.exam`: TYT, AYT, KPSS veya LGS. Alt konu/ünite alanı yoktur. Dış kaynaklı soru `id`, API anahtarı veya oyuncu geçmişi taşımaz. Kimlik uygulamada içerikten hesaplanır. `modelID`/`reviewedBy` alanları mevcutsa taşınır; kaynak doğruluğu kanıtı değildir.

## Etkinlikler

Tüm etkinlikler `kind` ve `title` içerir. `options`, `answer` ve `optionExplanations` dışarıda hazırlanan sıralama/eşleştirme/söyleme etkinliklerinde atlanabilir; uygulama uyumluluk alanlarını oluşturur. Asıl yanıt aşağıdaki yapılandırılmış çözümle değerlendirilir.

| `kind` | Diğer alanlar |
|---|---|
| `listening` | `transcript` 20–1200 karakter, `language`; normal dört seçenekli yanıt alanları gerekir |
| `pronunciation` | `transcript` 2–160 karakter hedef ifade, `language` (Türkçe hariç) |
| `ordering` | `items`: dört farklı kısa metin, `solution`: doğru sıradaki öğe indeksleri |
| `matching` | `left` ve `right`: dörder farklı kısa metin, `solution`: her sol öğe için doğru sağ öğenin indeksi |

Dil etiketleri: `tr-TR`, `en-US`, `de-DE`, `fr-FR`, `es-ES`, `ar-SA`. Sıralama/eşleştirmede çözüm 0,1,2,3 sayılarının her birini tam bir kez içermelidir. Sıralama etiketi en fazla 35, eşleştirme etiketi en fazla 55 karakterdir. Dinleme sesi kayıttan değil metinden seçilen Azure/Chirp/Proxy API veya iPhone konuşma motoruyla üretilir; harici ses bağlantısı veya base64 kabul edilmez. Söyleme alıştırması yalnız Whisper'ın tanıdığı kelimeleri karşılaştırır.

```json
{"kind":"matching","title":"İngilizce sözcükler","left":["Cat","Book","Water","Sun"],"right":["Su","Güneş","Kedi","Kitap"],"solution":[2,3,0,1]}
```

## Görseller

`kind`: `diagram`, `image`, `table`, `barChart`, `lineChart`. Tümünde `title` ve erişilebilir `summary` açıklaması gerekir. Tam, doğrulanan yapılar için uygulamanın örnek dosyasını esas al. Veri tabloları/çizimler JSON'da bulunur; fotoğraf ise gömülü katalogdaki `imageID` değeridir: `violin`, `bicycle`, `leaf`. Fotoğraf PNG dosyaları JSON içinde bulunmaz; başka yazılımda görüntülemek için ayrıca bu kataloğa ihtiyaç vardır. Bilgi Arenası'na tekrar alınan dosyalar uygulamadaki kataloğu kullanır. Harici URL, ses veya base64 içermez.

## Toplu aktarım ve paylaşım

Birden çok dosya seçilebilir; toplam üst sınır 100 MB ve 100.000 adaydır. Önizleme ilk örnekleri/geçerli-geçersiz sayısını gösterir; kullanıcı onayından sonra 100'lük kalıcı gruplar kaydedilir. Aynı ve yakın kopyalar kayıt sırasında atlanır. Sonuçta eklenen, tekrar ve geçersiz sayıları ayrıdır. İptal tamamlanmış grupları korur; yeniden deneme aynı kayıtları çoğaltmaz. Son aktarımı geri alma yalnız bu aktarımın yeni eklediği havuz kayıtlarını kaldırır.

Tek soru, filtredeki sorular veya tüm havuz aynı dosya ailesini kullanır. Havuz ekranındaki ilk 100 satır sınırı dışa aktarıma uygulanmaz. Gizlenen soruları dahil etmek isteğe bağlıdır. Paylaşım iOS menüsünde Dosyalar'a kaydetmeye veya başka uygulamaya göndermeye izin verir. Kimlik bilgileri, ham mikrofon sesleri ve oyuncu geçmişi paylaşılmaz.

Kalıcı cihaz havuzu SQLite içinde soru JSON'u ve indeksli arama/sınıflandırma alanlarıdır. Kullanıcı bu veritabanını taşımak zorunda değildir; JSON dosyası aktarım biçimidir. Yeni soruların ortak tekrar denetimi eski kayıtları topluca taramaz; yakın metin denetimi tüm anlamsal kopyaları yakalama garantisi vermez. Biçim doğrulaması olgusal doğruluk denetimi değildir.
