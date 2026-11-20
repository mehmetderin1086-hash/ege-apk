# Ege 4.6.1+65 (4.6.0 dahil) — Hey Ege ölçülerek iyileştirildi, kişisel ayar, Canlı Ses teşhisi

## Hey Ege: neden çalışmıyordu

Telefondaki kayıtlarda algılayıcının hiç isabet (`HIT`) üretmediği görüldü;
sorun sonraki adımlarda değil doğrudan algılamadaydı. "Hey Ege"yi dinleyen
model İngilizce verilerle eğitilmiş küçük bir modeldir (sherpa-onnx
GigaSpeech KWS 3.3M) ve "Ege"yi İngilizce heceler gibi duyar. İkinci
denetleyici olan Android Türkçe modeli telefonda kurulu değil.

## Ölçüm düzeneği (PC)

Uygulamadaki modelin aynısı, uygulamadaki çift akışla (ham + ses
yükseltici) Python'da çalıştırıldı (`C:\tmp\kwstest`):

- Olumlu: 2 Türkçe ses (Ahmet, Emel) × 3 hız × 3 perde × 5 cümle; her biri
  temiz / kısık / gürültülü / kısık+gürültülü → 360 deneme.
- Olumsuz: 120 genel + 80 zorlayıcı cümle ("hey abi", "Ege denizi",
  "eğer", "heykel", "egzoz"…) aynı dört koşulda → 440+ deneme.
- Doğrulama: ayarda hiç kullanılmayan 6 farklı konuşmacı.

| Ayar | Ayar sesleri | Görülmemiş 6 ses | Kısık | Kısık+gürültü | Yanlış alarm (584) |
|---|---|---|---|---|---|
| 4.5.0 (eşik 0,08, 3 yol) | %72 | — | %84 | %59 | — |
| 4.6.0 (eşik 0,011, 3 yol) | %83 | %33 | %77 | %63 | 13 |
| **4.6.1 (eşik 0,011, 10 yol)** | **%89** | **%83** | **%97** | **%80** | 39 → bulutta elenir |

Yanlış alarmların neredeyse tamamı "Hey Engin/Emre/Elif", "hediye",
"heyecanlı", "heykel" gibi sesçe çok yakın sözlerden geliyor. Bunları küçük
İngilizce model tek başına ayıramaz; 4.6.1'de isabet anında bulut doğrulaması
eklendi. Gemini'nin gerçek "Hey Ege" kayıtları için yazdıkları ("Hey Ege.",
"heyege", aksanlı seslerde "Hey Edge", "Ey ego", "Hey Ece") kabul, yukarıdaki
olumsuzlar ret ediliyor (`test/wake_verifier_test.dart`, 30 durum).

**Dürüst sınır:** Sentezlenmiş seslerde temiz konuşmada %90, kısık seste %97;
gürültülü ortamda %80–83. %90–95'in gerçek sesinde tutması için
"Hey Ege'yi sesime göre ayarla" kalibrasyonu yapılmalı. Asıl kalıcı çözüm
Android'in Türkçe modelinin bir kez Wi-Fi'de inmesidir.

## Değişiklikler

- Varsayılan duyarlılıkta eşik 0,08 → 0,011, puan 2 → 3 (ölçülen en iyi
  nokta). Duyarlılık kaydırıcısı artık 0,06 (sıkı) – 0,004 (en duyarlı)
  aralığında.
- **Hey Ege'yi sesime göre ayarla** (Ayarlar → asistan kartı): 5 kısa kayıt
  cihazdaki aynı modelle 12 eşik ve 13 söyleniş yolunda denenir; senin
  söyleyişini yakalayan yollar kişisel ayar olarak kaydedilir. Kayıtlar
  telefondan çıkmaz. "Varsayılan ayara dön" ile silinir.
- **Bulut doğrulaması (4.6.1):** yerel algılayıcı isabet verdiğinde yalnız
  son ~2,5 sn Gemini'ye yazdırılır ve "Hey Ege" mi diye bakılır. Sürekli
  dinleme buluta gitmez. İnternet/anahtar yoksa, 3,5 sn'de cevap gelmezse ya
  da kota dolarsa (429) telefonun kararı geçerli olur. Ayarlar → "Hey Ege'yi
  bulutta doğrula" ile kapatılabilir.
- **Canlı Ses teşhis kaydı:** her tur için tanıma motoru, süre, yanıt ve
  seslendirme adımları `[Ege] canlı:` etiketiyle kayda geçer.
- **Ses kimliği döngüsü:** filtre sesini art arda 3 kez reddederse Canlı Ses
  sessizce dönmek yerine durur ve ne yapılacağını söyler.
- **Türkçe model uyarısı:** Android'in Türkçe modeli yoksa Canlı Ses
  ekranında açıklama ve "Modeli indir" düğmesi görünür.

## Doğrulama

- Tüm paket: 377 başarılı, 1 atlandı, 5 başarısız (4.4.8'den kalan aynı 5
  test). Yeni: `wake_verifier_test` (33), `wake_word_test` (4), Canlı Ses
  model uyarısı testi.
- Gerçek telefonda gerçek sesle Hey Ege oranı ölçülmedi; kayıtlarda
  `[Ege] uyandırma doğrulama` satırları görülecek.

## 4.6.2 — Ses kimliği filtresi kalibre edildi

Telefon kayıtları (4.6.1, 14:51–14:53) iki sorunun aynı kaynaktan geldiğini
gösterdi: "Hey Ege" algılayıcısı ifadeyi **yakaladı** (3 isabet) ama ses
kimliği filtresi sahibinin sesini reddetti (0,53 / 0,56 / 0,51; eşik 0,65).
Canlı Ses'te de turların çoğu aynı filtrede durdu; filtrenin kabul ettiği
turlarda Gemini STT 1,8 sn, yanıt ve seslendirme sorunsuz çalıştı.

- Yeni sesi kabul eşiği 0,65 → 0,45 (`SpeakerIdentity.matchThreshold`;
  profil örneklerinin en az ikisiyle). Kayıt sırasındaki tutarlılık şartı
  0,65'te kaldı.
- Her kararın skoru `[Ege] ses kimliği` satırıyla kayda yazılır.

## 4.6.3 — Bulut doğrulaması esnetildi

4.6.1 telefon kaydı (14:56): ses filtresi kapatıldıktan sonra Canlı Ses üç
tur üst üste sorunsuz çalıştı (tanıma → yanıt → seslendirme). "Hey Ege"
yakalandı ama Gemini sesi "Hey ya, ya." yazdığı için doğrulayıcı reddetti.
"Hey"den sonra gelen, farklı bir sözcüğe işaret eden harf (n, m, r, l, b…)
içermeyen 3 harfe kadar heceler artık kabul ediliyor; "Hey Engin", "Hey
yavrum", "Hey abi", "hediye" yine reddediliyor (`wake_verifier_test`, 35 durum).

## 4.6.4 — Ölü yedek model değiştirildi, doğrulayıcı genişletildi

Telefon kaydı (15:19–15:20): bulut doğrulamasının ilk modeli
(`gemini-3.5-flash-lite`) aralıklı olarak yanıt vermedi; yedek
`gemini-2.5-flash-lite` yeni kullanıcılara kapatıldığı için HTTP 404 döndü ve
doğrulama yerel karara düştü. Aynı liste Canlı Ses'in bulut tanımasında da
kullanılıyordu.

- Yedek modeller: `gemini-3.1-flash-lite`, `gemini-flash-lite-latest`
  (bu anahtarla 200 döndükleri doğrulandı; kotaları ayrı).
- Hata kaydı artık her modelin hatasını sırayla yazar.
- Doğrulayıcı: `ə` → `e`; tek ve kısa birleşik yazımlar ("Həcə", "Hege")
  kabul. Gerçek yanlış alarmlar ("şurada çok tatlı pembe", "Burası
  gelmiyor", "Hey gidi.") reddediliyor.
