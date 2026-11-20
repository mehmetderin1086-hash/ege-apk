# Ritim 1.10.0 (12) — uygulama durumu

28 Ekim 2026. Bu belge yalnız bu geliştirme turunun kapsamını anlatır; önceki değişiklikler ve cihaz kabulleriyle karıştırılmaz.

## Uygulananlar

- Isınma/düşük güç durumuna göre yeni indirme işlerinin sayısını azaltma; kritik ısıda yeni iş başlatmama ve dönüştürmeyi iptal edilebilir beklemeye alma. Yeni kurulum varsayılanı 10; eski tercih korunur.
- Kullanıcı duraklatması, ses kesintisi, video kumandası ve ilerlemeyen ses oynatmasını ayıran, aynı parçada en fazla bir otomatik kurtarma denemesi. Uyku zamanlayıcısı kalan süreyi gösterir.
- Ayrı indirme aşamaları; sıradaki işe öncelik; seçili işleri tek kayıtla toplu öncelik/iptal/yeniden deneme. Kısa hazır işlerden sonra eski işlere sıra verilir.
- Geçici URLSession bağlantı hatalarında 5/15/45 saniye aralıklarla en fazla üç yeniden deneme; eski görev sonuçlarını reddeden mevcut belirteç kontrolü korunur. Hazır bileşenler yeniden deneme sırasında korunur.
- Doğrudan aktarım ve ön plandaki YouTube kaynak aktarımında ölçülen byte, hız ve yalnız kaynak aktarımına ait tahmini kalan süre. Ses/video ayrı kaynak olarak ölçülür; dönüştürme bu süreye katılmaz. Sistem arka plan aktarımında yeni hız ölçümü yoktur.
- Türkçe çok sözcüklü arama; ayrı sanatçı/albüm/liste sonuçları; tür ve kalite filtreleri; sekme/tema değişiminde arama ve seçim durumunu koruma.
- Toplu beğeni ve sanatçı/albüm düzenleme; liste sabitleme, açıklama ve mevcut parçalardan kapak seçme. Metin biçiminde okunabilen disk/parça metadata bilgileriyle sıralama.
- Çalma sırasında arama, filtrelenen sonuçlardan doğru parçayı kaldırma ve çalan parçayı koruyarak diğerlerini temizleme.
- Asistan öneri dışlamalarını yerelde saklama ve sıfırlama; yeni öneri istekleri dışlamaları uygular.
- Uygulamaya özel, akışla yazılan `.ritimbackup` paketi: yalnız bilgi veya medya dahil tam yedek. Tam yedekte kaynak dosyaları, kapaklar ve kayıtlı sözler; dosya başına SHA-256 doğrulaması. Anahtarlar, bağlantı ayarları, indirme geçici dosyaları ve sohbetler dahil edilmez.
- Geri yükleme öncesi biçim/yol/bütünlük/oynatılabilirlik doğrulaması; mevcut içeriği koruyan birleştirme; aynı medya farklı kimlikle mevcutsa hash eşleşmesiyle tekrar kopyalamama. Bozuk pakette mevcut arşiv değişmez. Yeni dosyalar kayıt başarısızsa geri alınır.
- Eksik/olası yinelenen dosya denetimi ve medya/kapak/söz/indirme ara dosyaları alan raporu. Denetim hiçbir dosyayı silmez.

## Doğrulama

- Son kaynak simülatör turu: 175 test, 172 geçti, 3 isteğe bağlı canlı test atlandı (`/tmp/ritim-upgrade-release-tests.xcresult`). Hız ölçümü değişikliği dahildir.
- Fiziksel iPhone hedefli son veri/indirme turu: 47/47 geçti (`/tmp/ritim-upgrade-final-device.xcresult`). Son hız gösterimi bu turdan sonra eklendi; son simülatör regresyonu ve imzalı cihaz derlemesi geçti.
- Fiziksel yedek/bakım arayüzü geçti. Simülatörde ilk denemede yedek oluşturuldu ancak ekran dışındaki paylaşım düğmesi bulunamadı; kaydırma eklenmiş test tekrarı geçti (`/tmp/ritim-upgrade-backup-retest.xcresult`).
- Simülatörde eşzamanlı iş seçimi, indirme araması/geçmiş onayı ve kitaplık araması/toplu liste akışları geçti. İlk turdaki başarısız yedek görünürlük testi ayrıca korunur; o bütün paket başarılı sayılmaz.
- Fiziksel arka plan dayanıklılık denemesi 75 saniyede `runningForeground` (rawValue 4) gözlendiği için başarısızdır. Bu sonuç uygulamanın kapandığını veya donduğunu kanıtlamaz; arka plan kabulü de sayılmaz.

## Planın açık kalan maddeleri

- Son sürümde 60 dakika gerçek kilitli oynatma, eşzamanlı indirme yükü ve ses çıkışı kesintileriyle birleşik kabul.
- Kontrollü ağda 10 gerçek eşzamanlı aktarım ve 100 dosyalık parti; yeni sürümde canlı kısa/uzun MP3/MP4 ve kilitli bitiş doğrulaması. 5.000 kayıt ve sahte iş testleri bu kanıtın yerine geçmez.
- Sistem arka plan kaynakları için birleşik byte/hız ölçümü; kaynak boyutlarından toplam geçici alan rezervasyonu; HTTP hata sınıflarının tümü için yeniden deneme politikası.
- Bütün büyük JSON kayıtlarının seri arka plan yazıcısına taşınması, arama için kalıcı indeks ve fiziksel cihazda 300 ms performans ölçümü.
- Sürümlemeyi tüm kalıcı veri dosyalarına yayma; ayarları kapsayan yedek/geri yükleme; üretimde sınırlı tanılama günlüğü ve güvenli önbellek temizleme arayüzü.
- Bütün ekranlarda kaydırma konumunu koruma, çalma sırasında çoklu seçim ve tam VoiceOver/Hareketi Azalt/büyük yazı kabul matrisi.

Bu maddeler tamamlanmadan geniş planın bütünü bitmiş veya uzun süreli donma sorunu kesin çözülmüş sayılmaz. Ekran paylaşımı açılmaz; üretim arşivine test kaydı eklenmez.

## Kurulum ve koruma

1.10.0 / yapı 12 fiziksel iPhone’a kuruldu, normal uygulama açıldı. Kurulum öncesi/sonrası 275 parça kimliği ve temel dosya bilgileri, 9 liste ve boş üretim kuyruğu eşleşti. Test müzikleri üretim kitaplığına eklenmedi. Koruma özeti: `/tmp/ritim-upgrade-preservation.json`.
