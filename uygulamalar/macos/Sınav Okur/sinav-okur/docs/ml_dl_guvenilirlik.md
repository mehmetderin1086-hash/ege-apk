# Siyah kurşun kalem için ML/DL güvenilirlik tasarımı

## Üretimde çalışan katmanlar

Sistem artık yalnız basılı sınav ile öğrencinin siyah kurşun kalem yazısını
varsayar. Renkli pikseller silinmez; beklenmedik renk bir girdi anomalisi olarak
otomatik kararı durdurur.

- **Apple Vision:** macOS üzerinde yerel, doğru metin tanıma; Türkçe dil
  düzeltmesi, rubrikten özel sözcükler, satır kutuları, güven ve üç aday.
- **TrOCR:** görüntü kodlayıcı + metin çözücü Transformer. Yerel Türkçe model
  varsa ikinci bağımsız HTR motorudur; Apple Silicon'da PyTorch MPS kullanır.
- **Keras CNN–BiLSTM–CTC:** izinli gerçek satır verisiyle eğitilebilen alternatif
  yerel model. Model kurulmadan üretim kanıtı sayılmaz.
- **Topluluk/uzlaşma:** aynı motorun beş görüntü varyantı bağımsız oy sayılmaz.
  Motor sayısı, metin uzlaşması, birinci–ikinci aday marjı ve varyant kararlılığı
  ayrı ölçülür.
- **Güven kalibrasyonu:** ham model güveni Platt ölçekleme ile doğruluk
  olasılığına çevrilir. Kalibrasyon dosyası yoksa muhafazakâr hazır eğri
  kullanılır.
- **Seçici karar (abstention):** iki bağımsız motor, yeterli bölgesel kalite,
  yüksek OCR/puan güveni ve onaylı anahtar birlikte yoksa puan yalnız öneridir.

## Kurşun kalem görüntü boru hattı

1. Orijinal görüntü kanıt olarak korunur.
2. Büyük ölçekli aydınlatma bölünerek kamera gölgesi düzleştirilir.
3. CLAHE ile soluk grafit çizgileri yerel olarak güçlendirilir.
4. Bilateral filtre kâğıt gürültüsünü azaltırken çizgi kenarını korur.
5. Orijinal, gölge-düzeltilmiş, yumuşak kontrast, uyarlanır eşik ve keskin
   görünümler ayrı okunur.
6. Her cevap bölgesinde netlik, çizgi kontrastı, ön plan yoğunluğu ve aydınlatma
   tekdüzeliği ölçülür.

## Gerçek doğrulama ve eğitim protokolü

Başarı oranı yalnız gerçek, izinli ve kimliksiz kâğıtlarda ölçülmelidir.
Öğrenci/yazar aynı anda iki veri bölümünde bulunmamalıdır:

- eğitim %70,
- doğrulama %10,
- kalibrasyon %10,
- kilitli yazar-ayrık test %10.

Fotoğraf artırımı; gölge, perspektif, hafif bulanıklık, JPEG, kâğıt tonu ve
soluk grafiti kapsamalı; karakterin anlamını değiştiren ağır bozulma
kullanılmamalıdır. Öğrenci adı/numarası eğitim dışa aktarımında tutulmaz.

Yayın kapıları:

- HTR: CER, WER, tam cevap doğruluğu ve Türkçe karakter hata matrisi,
- kimlik: alan bazlı tam doğruluk ve yanlış öğrenci eşleme oranı,
- puan: MAE, soru bazlı sapma ve kısmi puan tutarlılığı,
- güven: ECE ve Brier skoru,
- güvenlik: **yanlış otomatik kabul oranı** ile **otomatik kapsama** birlikte.

Hedef, kilitli testte yanlış otomatik kabulü sıfıra yaklaştırmaktır. “Sıfır hata”
garantisi gerçek el yazısı ve fotoğraf değişkenliğinde bilimsel olarak
verilemez; eşik yükseldikçe yanlış kabul azalır fakat insan incelemesi artar.

## Kalibrasyon

Doğrulanmış her OCR sonucu için aşağıdaki biçimde JSONL hazırlanır:

```json
{"ham_guven": 0.91, "dogru": true}
{"ham_guven": 0.76, "dogru": false}
```

Ardından:

```bash
uv run python scripts/ocr_kalibrasyonu_egit.py veri/ocr_kalibrasyon.jsonl
```

Üretilen `modeller/ocr_kalibrasyon.json` sonraki uygulama başlangıcında
otomatik yüklenir. Kalibrasyon ve karar eşikleri yalnız kilitli test sonucu
iyileşiyorsa sürümlenmelidir.

## Seçici kabul kapısı — üç modlu çalışma

Kapı (`sinav_okur/guvenlik_kapisi.py`) `SINAV_OKUR_GUVENLIK_KAPISI` ortam
değişkeniyle üç modda çalışır:

- **`kapali`** — her kutu incelemeye düşer (kapı hiç çağrılmaz).
- **`golge`** (varsayılan) — kapı çağrılır, kararı `kutu.kararlar_json` ve
  kâğıt başına `denetim_kaydi`'na yazılır, **ama uygulanmaz**: davranış `kapali`
  ile birebir aynıdır. Amaç, davranışı değiştirmeden telemetri biriktirmektir.
- **`aktif`** — kapı kararı `incele` bayrağını belirler; bütün kanıtlar yeterli
  kutular otomatik kabul edilir.

### Aktivasyon kriteri

Kapıyı `aktif`'e almadan önce gölge telemetrisi
(`Depo.guvenlik_kapisi_ozeti`) şu koşulları sağlamalıdır:

1. En az ~300 kapılı (değerlendirilmiş) kutu birikmiş olmalı,
2. `golge_yanlis_kabul` ≈ 0 (kapının otomatik kabul edilebilir gördüğü ama
   öğretmenin sonradan metnini/puanını değiştirdiği kutu sayısı),
3. Kalibrasyon eğitilmiş olmalı — **kritik**: varsayılan muhafazakâr eğriyle
   ham 0.90 kanıt ≈ 0.864 kalibre güven üretir; bu, kapının 0.90 OCR eşiğini
   geçemeyeceği anlamına gelir. Yani kalibrasyon eğitilene kadar kapı pratikte
   hiçbir kutuyu kabul etmez ve gölge istatistiği ancak kalibrasyondan sonra
   anlamlıdır.

Aktivasyon: `SINAV_OKUR_GUVENLIK_KAPISI=aktif`. Acil geri dönüş: ortam
değişkenini `golge` veya `kapali` yapmak yeterlidir; DB'de geri alınacak bir
şey yoktur (onay akışı değişmez).

