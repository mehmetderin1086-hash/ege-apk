# Ege 4.4.9+62 — Canlı mod ve dikte, Android Türkçe modeli olmadan da çalışır

## Sorun

4.4.6'dan beri konuşma tanıma yalnız Android'in cihaz içi (çevrimdışı) Türkçe
modeline bağlıydı. Bu model telefonda kurulu değil (`ERROR_13`, indirme
`SCHEDULED`; telefon mobil veride olduğu için Google indirmeyi başlatmıyor).
Sonuç: Canlı mod her turda "Android yerel STT hazır değil" deyip kapanıyor,
dikte çalışmıyor ve Android'in "Türkçe (Türkiye) güncellemesini indir"
penceresi her açılışta ve her denemede yeniden çıkıyordu.

## Değişiklikler

- **Bulut çözümleme yedeği (Whisper değil):** Android yerel STT hata verirse
  kayıt Gemini'ye (`gemini-3.5-flash-lite`, yedek `gemini-2.5-flash-lite`)
  yazdırılır. Gerçek API ile Türkçe örnek kayıtta 1,9 sn'de doğru metin
  döndü. Gemini anahtarı yoksa eski hata metni gösterilir.
- **Canlı mod ve dikte:** telefon STT'si `ERROR`/`UNAVAILABLE` dönerse aynı
  tur kayıt + sessizlik algılama moduna geçer; oturum kapanmaz. Hata bir kez
  görüldükten sonra uygulama kapanana kadar bozuk motor yeniden denenmez.
- **İndirme penceresi:** otomatik model indirme isteği haftada en çok bir kez
  yapılır (kalıcı kayıt). Ayarlar ve Tanılama'daki düğme her zaman ister.
  Model indirilirse Android yerel STT yeniden ilk tercih olur.
- **Canlı ekran:** durum rozeti (Hazır/Dinliyor/Düşünüyor/Konuşuyor), duruma
  göre renk değiştiren küre ve halkalar, etiketli düğmeler, SEN/EGE ayrımlı
  konuşma kartı, son tanıma motoru ve süresi.
- Ayarlardaki STT açıklamaları yeni davranışa göre düzeltildi.

## Doğrulama

- Yeni `test/ege_449_test.dart`: 6/6.
- Tüm paket: 328 başarılı, 5 başarısız. Bu 5 test değişiklik öncesi 4.4.8
  kopyasında da aynı şekilde başarısız (SMS, hafıza, Whisper kartı,
  "Canlı ses" ayar başlığı, model seçici `claude-sonnet-5-5`); bu sürümde
  dokunulmadı.
- Gerçek telefonda sesli deneme yapılmadı (derleme sırasında telefon USB'de
  değildi). "Hey Ege" uyandırması bu sürümde değiştirilmedi.
