# Ritim 1.10.0 / 12 — 28 Ekim 2026

- Son simülatör kaynak turu: **172 geçti / 3 isteğe bağlı canlı test atlandı / 0 başarısız**. `/tmp/ritim-upgrade-release-tests.xcresult`.
- Fiziksel iPhone: **47/47** hedefli indirme/veri testleri; önceki aynı turda 16 oynatma testi ve yedek/bakım UI testi geçti. Son hız ölçümü eklemesi simülatör regresyonu ve imzalı cihaz build'iyle sınandı.
- Simülatör iş ayarı, indirme araması/geçmiş onayı ve kitaplık toplu liste akışları geçti. Yedek UI ilk denemesi ekran dışındaki paylaş düğmesini bulamadı; test kaydırması düzeltilerek tekrar geçti. `/tmp/ritim-upgrade-backup-retest.xcresult`.
- **Arka plan dayanıklılık kabulü geçmedi:** 75 saniyede uygulama runningForeground/rawValue4 gözlendi; 150 saniye arka plan veya kapanma kanıtı değildir. 60 dakika kilitli kabul yapılmadı. `/tmp/ritim-upgrade-device-tests.xcresult` başarısız dayanıklılık testini de içerir; bütün paket başarılı değildir.
- 1.10.0/12 iPhone'a kuruldu ve normal uygulama açıldı. 275 parçanın kimlik/temel medya bilgisi, 9 liste ve boş kuyruk öncesi/sonrası eşleşti. Ekran paylaşımı açılmadı.
- Uygulananlar ve geniş planın açık kalan işleri: [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md). Önceki tarihli canlı MP3/MP4 kabulleri bu yeni sürüm için yeniden yapılmış sayılmaz.

# Arka plan YouTube aktarımı — 28 Ekim 2026

- Çözümlenmiş YouTube ses/video kaynakları arka plana geçişte iOS background URLSession görevlerine devredilir. Tamamlanan kaynaklar iş kimliğine bağlı ara kayıtla korunur; süresi dolan veya başarısız aktarım sıraya geri alınır. İşin tamamlanması için MP3/MP4 dönüştürmesi hâlâ gereklidir.
- Tamamlanan veya bekleyen YouTube işlerindeki hazırlama/dönüştürme için BGProcessingTask planlanır. Çalışma zamanını iOS belirler; süre dolarsa işlem iptal edilip iş yeniden sıraya alınır. Kullanıcı uygulamayı zorla kapatırsa sistem görevleri iptal edebilir. Kilitli ekranda bütün kuyruğun veya dönüştürmenin hemen tamamlanması garanti değildir.
- Simülatörde son kaynakla **38 hedefli test geçti**: kuyruk, ses/video handoff, iki bileşeni bekleme, ara kayıt ve bağlantı güvenilirliği. `artifacts/background-youtube-unit-20261028.xcresult`. Önceki fiziksel cihaz hedefli turda **5/5 test geçti**; ağ yanıtları kontrollü fixture idi.
- Gerçek iPhone 15 UI sınamasında herkese açık kısa YouTube kaynağı çözümlendi, Ana Ekran'a geçildi ve uygulama arka plandayken 309.288 baytlık ses kaynağı ara kayda teslim edildiği cihaz dosyasından görüldü. Uygulamaya dönünce MP3 tamamlandı; `artifacts/background-youtube-device-20261028.xcresult` 1/1. Bu test fiziksel kilit ekranı değil, Ana Ekran geçişidir.
- Son sürüm telefona kuruldu ve normal kullanıcı kuyruğundaki 100 kimliğin tamamı korundu. Sonraki gözlemde iOS `passcodeRequired: true` bildirdi; kilit öncesi hazırlanan iki gerçek işin kaynakları ara kayıtta bulundu. Kontrol sırasında 1 iş tamamlanmış ve 99 iş sıradaydı; kilitliyken tam MP3 dönüşümü veya bütün kuyruğun tamamlanması ayrıca kanıtlanmadı. Son kontrolde yeni Ritim CPU-fatal kaydı görülmedi.
- Boş handoff sonrası yeniden planlama için son küçük düzeltme derlenip kuruldu ve iki ilgili test tekrar geçti. Telefon kilitliyken uzaktan başlatma reddedildi; kullanıcı kilidi açıp uygulamayı başlattı. Son kurulan Ritim süreci doğrulandı, 100 kuyruk kimliği korundu ve bir iş aktarıma geçti.
- Kullanıcı telefonu tekrar kilitledikten sonra `passcodeRequired: true` ile kilit doğrulandı. 60 saniyelik canlı kullanıcı kuyruğu gözleminde başlangıç ve bitiş aynıydı: **1 tamamlanmış, 99 sırada, yeni tamamlanan 0**. Dört kaynağın ara dosyaları vardı; yeni Ritim çökme kaydı görülmedi. Bu gözlem, kilitliyken MP3 dönüştürmesinin başarıyla tamamlandığını doğrulamaz ve tek başına gecikmenin nedenini kanıtlamaz.
- Daha sonra kısa arka plan dönüşümü için 25 saniyelik pencere ve açılış geri yüklemesi sonrasında yeniden tetikleme eklendi. Son kaynak derlendi, dört hedefli simülatör testi geçti ve iPhone'a kuruldu. Telefon kilitli olduğu için bu son kurulumun açılışı ve kilitli cihazda tamamlanan MP3 henüz doğrulanmadı.

# Ritim 1.9.1 — YouTube indirme güvenilirliği ve yapay zekâlı YouTube keşfi — 27 Ekim 2026

- **İndirme düzeltmeleri:** Bağlantı kopması (zaman aşımı, bağlantı kaybı, 429/5xx) 2 MB'lık aralık başına 4 denemeye kadar üstel beklemeyle yeniden denenir. Süresi dolan YouTube akış bağlantısı (403/410) yeniden çözümlenir ve aktarım kaldığı baytta sürer; video kaynağı değiştiyse güvenli biçimde durur. Çözümleme sırasında geçici ağ hatası bir kez sessizce yeniden denenir; kalıcıysa anlaşılır Türkçe mesaj gösterilir.
- **Oynatma listesi alanı:** Tek video bağlantısı (`youtu.be/…?si=…`, listeden paylaşılan video dâhil) artık hata vermez; seçili tek satır olarak gösterilir. Doğrudan alanda liste bağlantısı eskisi gibi uyarı verir.
- **Yapay zekâlı YouTube keşfi (İndir sekmesi):** Yazılan arama önce çalışır; yapay zekâ ayrıca 3 benzer arama önerir, sonuçlar tek listede (tekrarsız, kaynak aramaya göre süzülebilir) gelir. Satırlarda küçük resim, süre, "Kitaplıkta" ve yapay zekâ işareti vardır; MP3/MP4 ve kalite seçilip toplu indirilir. Model yoksa veya hata verirse yalnız kullanıcının araması gösterilir ve nedeni söylenir. Asistan sohbetinde "YouTube'da … bul/indir" gibi istekler önerilen aramaları kendiliğinden çalıştırır; sonuç bileşeni ortaktır.
- **Testler:** Simülatör birim 142 test, 0 hata (1 atlandı; yeni: aktarım yeniden deneme/tazeleme, tek video, keşif genişletme, model hatasında geri düşme, sohbetten arama). Fiziksel iPhone 15: `AIExperienceUITests` 4/4 geçti (yeni keşif testi dâhil); canlı MP3+MP4 indirme ve yerel oynatma geçti (`artifacts/v191-device-live3.xcresult`). Telefon kilitlenince iki deneme "cihaz kilitli" ile düştü; kilit açıkken yeniden koşuldu.
- **Not:** Canlı CLIProxy ile yeni `discover` isteğinin kabulü denenmedi (kota harcar); yerel testler sahte istemciyle çalışır.

# Ritim 1.9.0 — Etkin yapay zekâ, animasyon ve görsel turu — 27 Ekim 2026

- **Yapay zekâ:** İsteklere ses dosyası olmadan dinleme bağlamı eklenir (saat/gün bölümü, şimdi çalan, son dinlenenler, sıra, liste adları). Asistan “çal / sıraya ekle” isteklerini doğrulanmış yerel parçalarla kendisi uygular ve ne yaptığını mesajın altında gösterir. Ayrıntılar `AI_INTEGRATION.md` içinde. Yeni özellikler:
  - **AI DJ:** ruh hâline göre set kurar; set bitmeden aynı havada ve tekrarsız uzatır.
  - Oynatıcıda **AI notu:** çalan parça için kısa yorum ve kitaplıktan benzer parçalar.
  - Ana sayfada **günün karışımı:** günde bir kez; hatadan sonra otomatik deneme 30 dakika bekler; ayarlardan kapatılabilir.
  - **Kalıcı sohbet.**
- **Animasyon/görsel:** Oynatıcıda kayan renk alanları, parça değişiminde kapak geçişi ve gölge nabzı, kapak ve mini çalarda kaydırarak parça değiştirme, kayan sekme göstergesi, sembol sıçraması, dokunsal geri bildirim, kademeli kart girişi, grafik çubuklarının büyümesi, yazıyor/parıltı/AI çerçevesi. Sürekli animasyonların tümü `MotionGate` ile yalnız sahne etkin ve Hareketi Azalt kapalıyken çalışır; arka planda ses için UI karesi üretilmez (1.7.1 CPU kapanmasının tekrarını önler). Liste içi çalma göstergesi sistem `symbolEffect` ile; 1.8'deki Canvas titremesi geri getirilmedi.
- **Düzeltmeler:**
  - Mini çalarda kaydırma, düğme dokunuşunu da tetikleyip çaları açıyordu; `highPriorityGesture` ile düzeltildi.
  - Kapakta kaydırma `simultaneousGesture` ve yatay koşul kullanır; dikey kaydırma bozulmaz.
  - `AVAudioSession` her parça değişiminde ana iş parçacığında yeniden etkinleştiriliyordu; artık bir kez etkinleşiyor, kesinti/sıfırlama/durdurmada yenileniyor.
  - Eski arama alanı etiketi testte güncellendi.
  - UI test modunda uygulama dikey konuma kilitlenir; stub model yoksa günün karışımı otomatik kapalıdır, gerçek kota harcanmaz.
- **Codex çapraz incelemesi** 6 bulgu verdi; hepsi düzeltildi ve regresyon testi eklendi:
  - Tek parçalık DJ seti uzamıyordu.
  - Geç gelen DJ yanıtı, bitmiş seti sürdürmüyordu.
  - DJ ile sohbet aynı parçayı yarış hâlinde ekleyebiliyordu.
  - AI notundan sıraya eklenen parça çalınınca DJ duruyordu.
  - Gizlilik metni modele gönderilenleri eksik anlatıyordu.
  - Sohbet geçmişinin yazma/silme hataları sessiz kalıyordu.

## Sonuçlar
- **Başlangıç (değişiklik öncesi) fiziksel iPhone UI turu:** 15 geçti, 4 başarısız, 13 atlandı (`artifacts/v19-baseline-device.xcresult`). Başarısızlardan biri eski arama etiketiydi. Diğerleri çaların açılmasını 3–5 saniyede bulamayan zamanlama hatalarıydı.
- **Simülatör birim:** 133 çalıştı, 132 geçti, 1 atlandı, 0 hata (`artifacts/v19-unit-sim-2.xcresult`). Yeni `AIFeatureTests` 13 testtir.
- **Fiziksel iPhone 15 birim:** 133 çalıştı, 132 geçti, 1 atlandı, 0 hata (`artifacts/v19-device-final.xcresult`).
- **Fiziksel iPhone 15 UI son tur:** 17/17 geçti, 0 hata. Canlı/opsiyonel olduğu için 10 test atlandı (`artifacts/v19-device-ui-final2.xcresult`).
  - Yeni `AIExperienceUITests` (3 test) çevrimdışı stub modelle çalışır: günün karışımı → çal → AI DJ → oynatıcıda DJ → AI notu → sıraya ekle → DJ durdur; asistanın “çal” eylemi ve yeniden açılışta sohbetin korunması; sekme geçişleri, mini çalar ve kapak kaydırması.
  - Dayanıklılık testi geçti: 150 saniye arka planda iki kontrolde de durum `runningBackground` idi; parça geçişleri doğal gerçekleşti.
- **Geçersiz sayılan ara turlar:**
  - Aynı iPhone'da başka bir oturumun İkra canlı UI testi eşzamanlı koştu. Koşucunun dokunuşları Ritim'e düştü: Asistan sekmesi açıldı ve gerçek modelle bir AI DJ başladı (az miktar kota).
  - Bir turda telefon test sırasında elle yatay konuma döndürüldü, bir turda başka uygulama/bildirim öne geldi. Bu turlar başarılı sayılmadı (`v19-device-full`, `v19-device-targeted`, `v19-device-retry`, `v19-device-ui-final`).
  - Bu turlarda Ritim çökme kaydı yok. Aynı saatlerde iki `RitimUITests-Runner` (test koşucusu) raporu oluştu.
- Canlı CLIProxy testleri bu turda koşturulmadı; yeni AI istekleri canlı modelle ayrıca kabul testinden geçmedi. Yanıt biçimi geriye uyumludur: `action` alanı olmayan eski yanıtlar `none` sayılır.
- Gerçek iPhone görüntüleri: `Preview/33`–`36`.

# Ritim 1.8.0 — Şarkı sözleri ve yerel müzik özellikleri — 26 Ekim 2026

- Zaman eşli/düz söz ekranı, satıra dokunarak seek, takip aç/kapat, ±30 saniye ayar, özgün LRC zamanlarını koruyan düzenleyici, TXT/LRC içe aktarma ve onaylı kullanıcı-sözü kaldırma eklendi. LRCLIB otomatik eşleşmesi başlık/sanatçı/süreyi karşılaştırır; canlı/remix gibi sürümler otomatik kabul edilmez. Belirsiz kayıtlarda manuel arama/seçim vardır. Dosyadaki iTunes/ID3 sözleri de okunur.
- Sözler UUID bazında atomik kaydedilir; eski parça/arama yanıtları yeni parçaya yazılmaz. Otomatik kayıtlar 100/16 MiB ile sınırlıdır; kullanıcı sözleri ve bozuk kayıtların kurtarma kopyaları otomatik temizlenmez. İstekler seri, zaman/boyut sınırlı ve Retry-After uyumludur. Söz ekranı arka planda arama/animasyon ve yeni parçanın cache'ini her heartbeat'te okuma yapmaz.
- Optional albüm/kapak alanları eski library JSON'unu açar. Yeni importta gömülü metadata, mevcut arşivde kullanıcı başlatan seri ön plan taraması vardır. 768px JPEG kapak, sınırlı bellek cache'i; başlık/sanatçı/favori/sayaç/listeler korunur. Albüm içi sıra A–Z'dir; katalog albümü veya disk/parça numarası tahmini yoktur.
- Sıradaki çal, karışık çalmada da önceliklidir; mevcut öğeyi taşır, çalan AVPlayerItem'ı değiştirmez. Sona ekleme ve sırayı normal listeye kaydetme vardır. Sana özel ekranı dinlenmeyenler, son 30 günde eklenenler, eski beğeniler ve her parçanın son çalınmasına göre güncellenir. [FEATURE_MATRIX.md](FEATURE_MATRIX.md) kalan kapsamı ve resmi karşılaştırma kaynaklarını içerir.

- Simülatör son özellik turu: **119 birim + 3 UI testi geçti**, sıfır hata; canlı sağlayıcı testi burada isteğe bağlı olduğu için tek atlama vardır. `artifacts/features-180-final-sim.xcresult`: 123 toplam, 122 geçen, 1 atlanan.
- Fiziksel iPhone son birim turu: **120/120 geçti**, atlama yok. Aynı turda düz sözler, kaldırma ve sırayı liste olarak kaydetme UI testi de geçti: `artifacts/features-180-device-retry.xcresult`, 121/121. Gerçek iPhone URLSession ile LRCLIB yanıtı ve ağ kapalı yeni store ile cache'den açılış doğrulandı; test çıktısına sağlayıcının söz metni yazılmadı. Mac'teki ayrı HTTP 200 ölçümü `artifacts/lyrics-provider-live.json` içindedir; iPhone kabulünün yerine sayılmadı.
- Fiziksel ekran kabulünde üç ayrı akış tamamlandı: zamanlı söz/seek/offset/arka plana kısa geçiş/çevrimdışı yeniden açılış; düz söz/kaldırma/sıra kaydetme; akıllı koleksiyonu listeye kaydetme/yeniden açılış/albüm-sanatçı ekranı. Son arka plan cache-okuma düzeltmesinden sonra zamanlı söz testi tekrar geçti: `artifacts/features-180-device-ui-final.xcresult`, 1/1. Bu tekrar ek benzersiz test sayılmadı. Gerçek iPhone görüntüleri `Preview/29`–`32` içinde.
- Cihaz envanteri **1.8.0 / yapı 10** gösterdi; uygulama normal kullanıcı kütüphanesiyle açıldı. **79 parça, 2 liste, 79 dosya / 587.265.329 byte** doğrulandı. Başlangıçtaki tüm parça kimlikleri/içerik bilgileri, eski listelerin sırası ve 10 indirme kaydının kimliği korundu; eski snapshot geri yazılmadı. Kanıt `artifacts/features-180-preservation.json`. Testler ayrı `Caches/RitimUITestFixtures` alanını kullanır.
- İlk turlarda bulunan LRC Türkçe canlı-sürüm filtresi ve SwiftUI zamanlama denetimlerinin erişilebilirlik kimliği sorunu düzeltildi. Eski dört kalite testinin host uygulama durumuna bağımlı fixture'ı açık foreground enjeksiyonuna alındı. Checkpoint testi kütüphane publish'i ile sonraki Combine oturum kaydını karıştırıyordu; başlangıç kaydı tamamlanana kadar beklemesi düzeltildi. Üretim arka plan kısıtı ve 10 saniyelik kayıt aralığı değiştirilmedi.
- İlk fiziksel düz-söz turunda 34 saniyelik otomasyon boşluğundan sonra parça/oynatma durumu değişmişti; bu tur başarılı sayılmadı. Yeniden koşulan test dikey yönü, aynı parçayı ve menü öncesinde duraklatılmış durumu açıkça kontrol etti; otomatik yeniden duraklatma ile hata gizlenmedi ve tam akış geçti.
- Bu sürümde 150 saniyelik arka plan denemesi **tamamlanmadı**: ilk 75 saniyelik bekleme sonunda uygulama durumu `runningForeground / rawValue 4` idi. Kapanma veya ses kesilmesi sonucu olarak yorumlanmadı. Kullanıcının kısa test tercihi nedeniyle uzun tur tekrarlanmadı; saatlerce kesintisiz çalma kabulü iddia edilmez. Önceki 1.7.1'de geçen 150 saniye/5 geçiş sonucu aşağıda tarihsel olarak korunur. İlk fiziksel sonuç paketi `artifacts/features-180-final-device.xcresult` başarısız turları da saklar.

# Ritim 1.7.1 — Arka planda CPU nedeniyle kapanma düzeltmesi — 26 Ekim 2026

- Kullanıcı sürekli kesilen çalmayı bildirdi. Fiziksel iPhone'dan alınan `Ritim.cpu_resource_fatal-2026-10-26-202633.ips` ve `...203306.ips`, **1.7.0/8 işleminin iOS tarafından kapatıldığını** gösterdi: yaklaşık 51 saniyede 48 CPU saniyesi, %93 ortalama; arka plan sınırı 60 saniyede %80. Bu bir ağ veya yalnız oynatıcı duraklaması değildi.
- Mevcut `Ritim.debug.dylib` UUID'si `E99878D9-313C-3EA8-B4C3-C1F994014395` iki raporla eşleşti. `atos` sonucu: `NativeMediaConverter.convert → encodeMP3 → lame_encode_buffer_interleaved_ieee_float → outer_loop`. Özel hata kayıtları ve sembolikleştirme `artifacts/stability-*` içinde; kaynak arşivine girmez.
- Native YouTube işleri arka plana geçer geçmez iptal edilip kalıcı sıraya alınır; iptal temizliği bitmeden aynı iş tekrar başlayamaz. Arka planda sistemin başlattığı uygulama native işi başlatmaz. Doğrudan medya URLSession aktarımları korunur. Dönüşümler tek sıra halinde, küçük iptal edilebilir bloklarla çalışır; geliştirme yapısında da LAME C kodu optimize edilir. Kalite ve bit hızı değiştirilmez.
- Metadata beklemesi sırasında iptal edilen içe aktarma kalıcı parça/listenin yerini tüketmez. İndirme arayüzü, arka planda YouTube işlerinin bekleyeceğini açıklar. Kullanıcının çalma sırası, kalite ve dosyaları değiştirilmez.

- Son kaynakla **91/91 birim testi geçti** (`artifacts/stability-unit.xcresult`). Yeni testler: arka planda hemen iptal; görev daha başlamadan arka plana geçiş; hızlı geri dönüşte eski callback/scratch ayrımı; arka planda açılış ve elle kuyruk duraklatma; doğrudan aktarımın korunması; sıra bekleyen dönüştürmenin iptali; iptal edilen içe aktarmada liste sırasının korunması.
- Fiziksel iPhone'da gerçek medya dönüşümünün altı testi ve iptal edilen içe aktarma testi geçti. 192/320 kbps MP3, 4K MP4, tek dönüştürme yuvası ve iptal temizliği doğrulandı. İlk UI denemesinde Mac CoreDevice bağlantısı koptu; o tur başarılı kabul edilmedi ve tamamlanmamış kayıt saklandı. CoreDevice yenilendikten sonra yeni turda aynı yedi test tekrar geçti.
- İzole özgün demolarla **150 saniye arka planda**, normal hızda **5 doğal parça geçişi** ve tekrar-tümü döngüsü geçti; kullanıcı Çal/İleri düğmesine basılmadı. Tam test 175 saniye sürdü. Saatlerce süre testi olarak sunulmaz.
- Gerçek kitaplık kabulü ayrıca opt-in test olarak eklendi: `ProductionPlaybackStabilityUITests`, `RITIM_UI_TEST_REAL_LIBRARY_STABILITY=1`, varsayılan 600 saniye. Kullanıcı dosyalarını veya kuyruğunu sıfırlamaz; mevcut parçayı sürdürüp tekrar-tümünü açar. Başlangıçta iki gerçek native iş `preparing` durumundaydı; önceki kayıtlı ilerlemeleri yaklaşık 0,75 idi. Home sonrasında ikisi de `queued / 0` oldu. Bu örnek tek başına o anda LAME kodlaması yapıldığının kanıtı değildir; gerçek kodlayıcının iptali ayrı fiziksel testle doğrulandı. Özel yerel kanıtlar `artifacts/stability-live-monitor.json` içinde tutulur.

- Son fiziksel sonuç paketi `artifacts/stability-device-final.xcresult`: **9 geçti, 1 tamamlanmadı/başarısız**. Geçenler: 7 medya/iptal testi, 150 saniyelik arka plan testi ve kalıcı oynatma UI testi. Gerçek kitaplık için istenen 600 saniyelik turda işlem durumu ilk 120 saniye arka plan, 150 saniyelik kontrolde ön plan (`rawValue: 4`) oldu; koşul bu yüzden başarısız. Bunun ardından test koşucusu yeniden başladı. Nedeni kullanıcıya yüklenmedi; 10 dakika geçti denmedi. Kullanıcı “Şimdilik kısa testlerle bitir” dediği için uzun tur tekrarlanmadı.
- Son cihaz envanteri **1.7.1 / yapı 9** gösterdi. Yeni sürüme ait CPU-fatal kaydı yok; 20:26, 20:33 ve 20:43 kayıtlarının tümü önceki 1.7.0/8 sürümüne aittir. Son kitaplık 80 parça/iki liste; başlangıçtaki 76 parçanın kimliği ve içerik bilgisi aynı, 80 dosyanın boyutu doğru (**602.392.315 byte**). On kuyruk kaydının kimlikleri korundu; 8 tamamlanan, 2 bekleyen. Çalışma sırasında tamamlanan yeni parçalar ve dinleme değişiklikleri geri alınmadı. Kanıt `artifacts/stability-preservation.json`.
- Fiziksel görüntü: `Preview/28-iPhone-Arkaplan-Dayaniklilik.png`. Saatlerce kesintisiz çalma, tamamlanmış gerçek süre testi olarak iddia edilmez.

# Ritim 1.7 — Kalıcı oynatma, sıralı indirme ve geniş CLIProxy kataloğu — 26 Ekim 2026

- **1.7.0 / yapı 8:** Son parça, çalma sırası, konum, hız, tekrar ve karıştırma geçmişi cihazda atomik kaydedilir. Açılış duraklatılmıştır; silinmiş/eksik dosyalar atlanır. İleri sarma tamamlanmadan gelen zaman bildirimleri istenen konumu sıfırlamaz. Video oynatıcısının kendi kontrolleri de kayda girer. Oynarken en fazla 10 saniyelik son kayıt aralığı ani kapanmada kaybolabilir; uyku zamanlayıcısı yeniden başlatılmaz.
- Paralel indirmeler oynatma listesinin kaynak sırasını korur. Parça ve liste bağlantıları birlikte kaydedilir. İçe aktarma tamamlandıktan sonra indirme günlüğü yazılamadan kapanma olursa, aynı indirme kimliğine ait kaynak/kalite ve boyutu eşleşen, gerçekten oynatılabilir yerel dosya tekrar indirilmeden kurtarılır. Kullanıcının sonradan listeden kaldırdığı tamamlanmış parçalar geri eklenmez.
- **85/85 birim testi geçti, sıfır hata/atlama.** Yeni oynatma kalıcılığı, hızlı art arda seek, karıştırma geçmişi, eksik dosyalar, bozuk kayıt, 10 saniyelik kayıt aralığı, ters bitiş sıralı iki liste, kapanma aralığı kurtarma, dinamik model kataloğu ve başarıdan sonra 429/402 durumları kapsanır. Kanıt: `artifacts/resume-all-unit-sim.xcresult`. Önce 19 başlangıç testi ve ardından 30 odaklı test de geçti; bunlar ek benzersiz test olarak sayılmaz.
- **4/4 simülatör UI testi geçti:** gerçek oynatma/gezinme, ölçülen dinleme paneli, büyük yazı ve uygulamayı kapatıp açınca aynı parça/konum/sıra/karıştırma/tekrar/hızla sessiz geri yükleme ve devam etme. Kanıt: `artifacts/resume-ui-sim.xcresult`. Büyük yazı ve normal devam kartı ekran görüntüleri sonuç paketinde bulunur.
- Asistanın dört-model allowlist'i kaldırıldı. Geçidin canlı sohbet kataloğu aranabilir sağlayıcı gruplarında gösterilir; eşleştirme dosyası yalnız ad/sağlayıcı metadata'sını sağlar. Görsel/TTS/canlı ses/özel araç modelleri sohbet seçicisinden ayıklanır. Önceki seçim korunur; sessiz model değişimi yoktur. Başarı etiketi ancak aynı modelden geçerli yanıtla gösterilir ve sonraki başarısız istekte temizlenir.
- **Gerçek iPhone 15'te altı farklı UI kabulü geçti.** Bağlantı ayarı testi ilk turda geçti; ardından CoreDevice iletişimi GPT-6.1 Sol yanıtından sonra kesildi. Eski test süreci durduruldu, Mac CoreDeviceService bağlantısı yenilendi ve kalan **5/5 test aynı son kaynakla geçti**, sıfır hata/atlama: `artifacts/resume-device-retry.xcresult`. Kesilmiş tur ayrıca `artifacts/resume-device-acceptance.xcresult` içinde korunur; başarılı sayılmaz.
- Telefonda **on model seçeneği** canlı doğrulandı: GPT-6.1 Sol, GPT-6 Sol, GPT-6 Astra, GPT-6 Luna, Claude Opus 5.5, Claude Sonnet 5.5, Gemini 4 Argon, Gemini 4 Argon High, Gemini 3.8 Flash, Antigravity Claude Opus 5.5. Yeni altı model testinde yanıt modeli birebir kontrol edildi. Kalıcı model seçimi, gerçek liste kaydet/çal ve YouTube araması da geçti. Aynı fiziksel turda YouTube → MP3 ve MP4 → yerel çalma/yeniden açılış; kalıcı çalma sırası, konum, hız, tekrar, karıştırma ve büyük yazıda devam akışları geçti. Görseller: `Preview/24`–`27`.
- **1.7.0 / yapı 8 telefona kuruldu ve normal kullanıcı kütüphanesiyle açıldı.** Başlangıçtaki 66 parçanın tüm kimlikleri, dosya/içerik bilgileri ve 66 parçalı eski liste korundu. Çalışma sırasında, ilk 1.7 telefon testi başlamadan önce altı yeni parça eklenmişti; son karşılaştırma **72 parça, iki liste, 490.415.836 byte** gösterdi ve 72 dosyanın tamamı diskte boyutlarıyla eşleşti. Güncel çalma/favori değişiklikleri korunarak eski yedek geri yazılmadı. Kuyruk geçmişi bu süre içinde 74 kayıttan 7 kayda değişmişti; kalan yedi kimlik başlangıç kuyruğundaydı, ikisi normal açılışta yeniden hazırlanmaya başladı. Bu nedenle kuyruk geçmişinin birebir değişmediği iddia edilmez. Kanıt: `artifacts/resume-production-preservation.json`, özel önce/sonra kopyaları ve dosya envanteri. UI test medyası ayrı `Caches/RitimUITestFixtures` alanındadır.

## Canlı CLIProxy kabulü

**38 sohbet modeline gerçek müzik-listesi isteği gönderildi; son durumda 31'i geçti, 7'si sağlayıcı erişimi nedeniyle geçmedi.** Test, dönen model kimliğinin birebir eşleşmesini, JSON yanıtını ve öneride yalnız verilen iki örnek parça kimliğinin kullanılmasını doğrular. Bu ölçüm Mac üzerinden doğrudan HTTPS geçidine yapılan testtir; iPhone kanıtı ayrıca kaydedilir. Kanıt: `artifacts/expanded-ai-final-report.json`, ilk turlar `expanded-ai-priority-live.json` / `expanded-ai-remaining-live.json`, düzeltilen Sol modellerinin aynı müzik akışı `expanded-ai-sol-music-live.json`.

GPT-6.1 Sol ve GPT-6 Sol için geçitteki iki özel kural yanlışlıkla OpenAI API yolunu seçiyordu. Yalnız bu iki kural aynı model kimlikleri korunarak bağlı ChatGPT/Codex hesabına çevrildi. YAML doğrulaması ve diğer alanların değişmediği kontrol edildi; desteklenen hot-reload olmadığı için CLIProxy kısa süreyle yeniden başlatıldı ve aktif olduğu doğrulandı. İki Sol modeli ile Astra ve Luna doğru model kimlikleriyle HTTP 200 verdi. Geri dönüş kopyası sunucuda `/var/backups/cliproxy-ritim-sol-routing-20261026T170015Z/config.yaml` altındadır. Kimlik bilgileri veya hesap kotaları değiştirilmedi. Kanıt: `artifacts/expanded-ai-sol-routing-repair-live.json`.

Başarılı güçlü seçenekler arasında **GPT-6.1 Sol, GPT-6 Astra, GPT-6 Sol, GPT-6 Luna, Claude Opus 5.5, Claude Sonnet 5.5, Gemini 4 Argon ve high/medium/low seçenekleri, Gemini 3.8 Flash ve seçenekleri, Antigravity Claude Opus/Sonnet 5.5** bulunur. Tam kimlik listesi sonuç JSON'undadır. Katalogda görünen özel Qwen matematik modeli 38 genel model testine dahil değildir.

| Model | Doğrulanan erişim sınırı |
| --- | --- |
| Claude Fable 5.1 / Fable 5 | HTTP 429; bu modeller için kullanım kredisi isteniyor. |
| GPT-5.5 | HTTP 400; bağlı ChatGPT hesabıyla desteklenmediği bildiriliyor. |
| Gemini 3.1 Pro high / low | HTTP 502; köprüde eski kayıtlar var, çalışan resmi hesap kataloğunda bu kimlikler bulunmuyor. Başka model adı altında yanıt verilmedi. |
| Gemini 3.1 Pro Preview / Gemini 3.7 Flash API | HTTP 402; API hesabında ön ödemeli bakiye tükenmiş. |

Bu yedi seçeneğe başarılı etiketi verilmedi; kredi satın alınmadı, farklı model aynı adla sunulmadı. Sağlayıcı erişimi ve kota ileride değişebilir. Mac indirme servisi bağımlılığı geri getirilmedi.

# Ritim 1.6 — Mac bağımsız iPhone indirme ve Asistan — 26 Ekim 2026

- **1.6.0 / yapı 7:** YouTube çözümleme, MP3 kodlama ve MP4 birleştirme iPhone’da yapılır. Swift YouTubeKit yalnız `.local` yöntemini kullanır; URLSession doğrudan YouTube/Googlevideo ile iletişim kurar. Eski `/v1/jobs`, liste çözümleme ve ACK sunucu istemcisi uygulamadan çıkarıldı. Doğrudan medya dosyalarının mevcut arka plan URLSession yolu korunur.
- Mac’in `local.ritim.media-server` LaunchAgent’ı durduruldu ve otomatik başlaması devre dışı bırakıldı. Kabul boyunca 8765 portuna ulaşılamadı. Kanıt: `artifacts/native-mac-service-retirement.json`. Mac’in kendisi test araçları için açıktı; test, indirme servisi kapalıyken yürütüldü.
- **Gerçek iPhone 15’te iki canlı indirme/liste testi geçti:** `jNQXAC9IVRw` MP3 ve MP4 olarak hazırlandı, yerel oynatma süreleri ilerledi ve yeniden açılışta kayıtlar korundu. Kullanıcının `RDEMTPfPURSbYpb0YHCKyIG37Q` Mix bağlantısı doğrudan telefonda tarandı. Kanıt: `artifacts/native-device-accepted.xcresult`. Mix dinamik ve sonsuz liste olduğundan bu test yüzlerce gerçek dosyanın indirildiği anlamına gelmez.
- Telefonun ürettiği dosyalar Mac’e yalnız doğrulama için kopyalandı: MP3 **320.000 bit/s, 44.100 Hz, stereo**; MP4 **H.264 + AAC, 320×240, yaklaşık 18,93 saniye**. Kaynak videonun gerçek çözünürlüğü düşüktür; yapay büyütme yapılmadı. Kanıt: `artifacts/native-phone-files-validation.json`. YouTube biçim etiketi gerçek piksel yüksekliğinden farklı olabildiği için son kaynak, kalite satırını dönüştürülen dosyanın gerçek ölçüsünden yazar.
- **Gerçek iPhone’da beş medya testi geçti:** eşzamanlı gerçek 192/320 kbps MP3, özgün sentetik 3840×2160 H.264 + AAC birleştirme, iptal temizliği, Standart sınırı ve uzak URL reddi. Kanıt: `artifacts/direct-ai-device-accepted.xcresult` içindeki `NativeMediaConverterTests`. Bu 4K testi YouTube’dan 4K indirme iddiası değildir; uygun yerel kaynakların telefonda birleştirilebildiğini doğrular.
- **Doğrudan Asistan kabulü 3/3 geçti:** HTTPS bağlantı ayarı/model kataloğu, GPT-6 Astra / Claude Sonnet 5.5 / Gemini 3.8 Flash canlı yanıtları ve kalıcı seçim; GPT-6 Luna ile liste önerisi, açık kaydet/çal eylemleri ve doğrudan YouTube araması. Kanıt: `artifacts/direct-ai-device-retry.xcresult`, `artifacts/direct-ai-device-summary.json`. Kişisel geçit anahtarı adrese bağlı ayrı Keychain kaydında; sağlayıcı anahtarları uzaktaki CLIProxy geçidinde. Asistan çevrimdışı dil modeli değildir, internet ister.
- **Simülatörde 69/69 birim testi, ardından son düzeltmelerde 30/30 hedefli test geçti.** İkinci tur yeni açılışta geçici dosya temizliği testini de ekler (toplam 70 farklı birim testi). Katalog sayfalama, JSON kaçışları, byte-range doğrulaması, 1.000 kayıt, 2/4/6 iş sınırı, iptal/yeniden deneme yarışları, kalite/göç ve kütüphane korunması kapsanır. Kanıt: `native-unit-final-sim.xcresult`, `native-final-corrections-sim.xcresult`.
- **Altı simülatör UI regresyonu geçti:** 500 bağlantı kalıcılığı/tekilleştirme, eşzamanlı indirme ayarı, Mac ayarı olmadan indirme ekranı, ortak kalite tercihi ve iki panel/erişilebilirlik akışı. Kanıt: `artifacts/native-ui-regression-sim.xcresult`.
- İlk telefon UI turu klavyenin altındaki başlat düğmesine erişemedi; görünür “Bitti” eylemi eklendi. Sonraki testte dosya tamamlandığı halde lazy kuyruk satırı ekran dışında kaldığı için test kaydırması düzeltildi. Bu kesilmiş turlar ayrı tutulur. İlk AI turunda medya testleri ve bağlantı ekranı geçtikten sonra Xcode uzak test süreci bağlantısı kesildi; sonraki üç AI testi aynı telefonda tamamen geçti.
- Son çözünürlük ve açılış temizliği düzeltmesinden sonra fiziksel indirme/oynatma/yeniden açılış testi **1/1 tekrar geçti**: `artifacts/native-final-device-live.xcresult`. Son MP4 satırı gerçek 240p yüksekliğini gösterir; son MP3 yine 320.000 bit/s. Kanıt: `artifacts/native-phone-final-files-validation.json`.
- Uygulama test kipinden çıkartılıp **normal kütüphaneyle açıldı**. 66 parça kimliği, içerik bilgileri, bir çalma listesi ve 66 tamamlanan kuyruk kaydı korundu; 66 dosyanın tamamı kalıcı `Documents/Media` içinde boyutlarıyla eşleşti (400.800.170 byte). Üç parçanın yalnız çalma sayısı/son çalınma zamanı ilerlemişti; bu güncel kullanım bilgisi geri alınmadı. Kanıt: `artifacts/native-production-preservation.json` ve özel dosya envanteri. Test MP3/MP4’leri yalnız Caches altındaki ayrı kitaplıkta oluşturuldu.
- Sınırlar: en iyi **cihazla uyumlu AAC/MP4** kaynak seçilir. iPhone 15’te bazı videolar 1080p H.264 ile sınırlıdır; WebM/VP9/Opus ve HDR dönüştürme yoktur. MP3 320 kbps çıkış kodlaması düşük kaliteli kaynağı iyileştirmez. Kaynak parça/çıktı başına 512 MiB sınırı; büyük kuyruklarda uygulama ön planda tutulur. iOS arka plan süresi dolarsa yarım YouTube işi sıraya döner ve gerekirse baştan indirilir.

Aşağıdaki bölümler önceki sürümlerin tarihsel kabul kayıtlarıdır; Mac servisi gerektiren ifadeler v1.5 ve öncesine aittir.

# Mac olmadan çevrimdışı oynatma — 26 Ekim 2026

- İndirilmiş **66/66 gerçek dosya iPhone’un kalıcı Documents/Media klasöründe bulundu**; her dosyanın gerçek boyutu kitaplık kaydıyla aynı, toplam 400.800.170 byte. Kanıt: `artifacts/offline-local-files-validation.json` ve özel `offline-device-files.json`.
- **Fiziksel iPhone’da sunucuya erişilemezken MP3 ve MP4 oynatma testi geçti.** İzole test ortamında sunucu iPhone loopback adresindeki kapalı porta (`http://127.0.0.1:1`) ayarlandı; Ayarlar bağlantı kontrolü başarısız oldu. Ardından yerel ses ve video açıldı, gerçek oynatma sürelerinin ilerlemesi ve duraklatma doğrulandı. Kanıt: `artifacts/offline-device-acceptance.xcresult`, `artifacts/offline-device-summary.json` (1/1, sıfır hata/atlama).
- Test dosyaları önceki canlı örnek MP3’ten ve özgün 4K MP4 testinden 30 saniyelik yerel fixture olarak hazırlanmıştır; yalnız Caches/RitimUITestFixtures kullanıldı. Telefonun tüm interneti/uçak modu kapatılmadı: uzak test bağlantısı açık kaldı. Bu kabul sunucu bağımsız oynatmayı kanıtlar; kaynak incelemesi AVPlayer’ın HTTP yerine yalnız yerel file URL açtığını ayrıca doğrular.
- Uygulama kodunda yeni bir çevrimdışı anahtarı gerekmiyordu: LibraryStore dosyayı Documents/Media içine kopyalar ve PlaybackStore yalnız bu yerel yolu oynatır. Yeni YouTube dosyası hazırlama ve Asistan bağlantı gerektirir; önceden indirilmiş ses/video ve listeler gerektirmez.
- Testten sonra gerçek Mac bağlantı ayarı geri getirildi ve uygulama normal kullanıcı kitaplığıyla açıldı. Önceki ve sonraki gerçek library.json birebir aynı; kullanıcı verisi değiştirilmedi. Kaynak arşivine özel kitaplık, test medyası veya anahtar eklenmedi.

# Ritim 1.5 doğrulaması — 26 Ekim 2026

- **Kişisel panel, yerel dinleme istatistikleri ve oynatıcı animasyonları eklendi; 1.5.0 / yapı 6 gerçek iPhone’a kuruldu.** 7/30 günlük grafik, bugünkü süre, kütüphane/favori/ses/video/alan bilgileri, etkin/tamamlanan/hatalı indirme sayıları, filtreli kitaplık sayfaları ve Asistan kısayolu gerçek uygulama verilerini kullanır.
- **52 iOS birim testi ve dört simülatör UI testi geçti (56/56, sıfır atlanan).** Yeni 10 sayaç testi gerçek oynatma durumunu, duraklama/bekleme/arama dışlamasını, kalıcılığı, gece yarısını, yaz saati sınırını, saat değişimini, 366 günlük saklamayı, bozuk geçmişi korumayı ve izole kitaplıkları kapsar. Kanıt: `artifacts/dashboard-simulator-acceptance.xcresult`, `artifacts/dashboard-simulator-summary.json`.
- **İlk fiziksel kabulde 3/3 UI testi geçti:** çok büyük yazı boyutu, gerçek dinleme süresi → duraklama → yeniden açılışta kalıcılık → 30 günlük görünüm → filtreli kitaplık/indirme/Asistan eylemleri; ayrıca uzun başlıklı tam oynatıcı ve çevrimdışı oynatma. Kanıt: `artifacts/dashboard-device-acceptance.xcresult`, `artifacts/dashboard-device-summary.json`.
- Panel ekran dışında kaldığında animasyonların durması için dış yığın lazy yapıldı. Bu sürümde hem simülatörde hem telefonda iki panel testi tekrar geçti: `artifacts/dashboard-simulator-final.xcresult`, `artifacts/dashboard-device-final.xcresult`.
- Görsel incelemede erişilebilirlik boyutunda alt sekme yazılarının fazla alan kapladığı görüldü; gezinme etiketlerine tek satır ve sınırlı ölçek uygulandı. Mini oynatıcı ve parça menüsündeki fazladan sistem düğme arka planları da düzeltildi. **Bu son kaynakta simülatörde 3/3 panel/oynatıcı testi geçti:** `artifacts/dashboard-release-simulator.xcresult`, `artifacts/dashboard-release-simulator-summary.json`.
- Son cihaz turunda yeni alt menü yüksekliği/sınır kontrolü dahil büyük yazı testi geçti. İkinci test dinleme, duraklama ve yeniden açılış aşamalarını geçtiği sırada CoreDevice/Mercury bağlantısı kesildi. Son tur tamamlanmış kabul sayılmaz; tamamlanmamış sonuç paketi yerine `artifacts/dashboard-release-device.log` hatayı korur. Kullanıcı telefonu şarja bağlayıp kilidini açtı; Mac CoreDeviceService bağlantısı yenilendikten sonra erişim düzeldi. **Son kaynakla 3/3 fiziksel test yeniden geçti**, sıfır hata/atlama: `artifacts/dashboard-device-accepted.xcresult`, `artifacts/dashboard-device-accepted-summary.json`. Ardından uygulama normal kullanıcı kütüphanesiyle açıldı.
- Testler yalnız `Library/Caches/RitimUITestFixtures` içindeki verilerle çalışır. Güncelleme öncesi ve son normal açılış sonrası **66 parça kimliği, bir çalma listesinin içeriği ve tamamlanmış 66 kuyruk kaydı aynı kaldı**: `artifacts/dashboard-device-preservation.json`. Özel yedekler kaynak arşivine dahil değildir.
- Ölçüm yalnız AVPlayer gerçekten oynarken geçen monoton süreye dayanır; geçmiş çalma sayısından dakika üretilmez. Ölçülemeyen 10 saniyeden uzun sistem boşlukları eklenmez; nadir uzun kesintiler eksik sayılabilir. Kayıt 15 saniyede bir ve duraklama/arka plan geçişinde yapılır. iOS’un eski AVAudioSession ana iş parçacığı uyarısı test kayıtlarında sürer; bu değişiklikte oluşan test hatası yoktur.
- Yeni sayaç için PrivacyInfo.xcprivacy içinde SystemBootTime / 35F9.1 kullanım nedeni eklendi. Gerekçe, uygulama içindeki olaylar arasında geçen süreyi ölçmektir: [Apple API kullanım nedeni belgesi](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
- Son arayüzün simülatör ekranları: `Preview/18-Panel-Simulator.png`, `Preview/19-Panel-Istatistikler-Simulator.png`, `Preview/20-Panel-Buyuk-Yazi-Simulator.png`. Son fiziksel ekranlar: `Preview/21-iPhone-Panel.png`, `Preview/22-iPhone-Panel-Istatistikler.png`, `Preview/23-iPhone-Panel-Buyuk-Yazi.png`. Kaynaklarda gerçek erişim anahtarı taraması sıfır eşleşme verdi.

# Ritim 1.4 doğrulaması — 26 Ekim 2026

- **1.4.0 / yapı 5 gerçek iPhone 15’e yüklendi ve normal kullanıcı kütüphanesiyle açıldı.** İmzalı cihaz ve simülatör derlemeleri başarılı. Yeni indirmelerde En yüksek kalite varsayılan; 320 kbps MP3 ve kaynağında varsa 4K SDR / 60 fps MP4.
- **42 iOS birim testi ve bir simülatör arayüz testi geçti.** Kalite göçü/kalıcılığı, kuyruğa eklenirken tercihin sabitlenmesi, eski dosyayı koruyan tekilleştirme, doğrudan dosya geçişi, sunucu yetenek kontrolü ve düşük kalite döndüren işi reddetme dahil. Kanıt: `artifacts/quality-simulator-acceptance.xcresult`, `artifacts/quality-simulator-summary.json`.
- **Gerçek iPhone’da üç ilgili UI testi geçti:** YouTube MP3/MP4 indirme → yerel kütüphane → video oynatma; tüm indirme modlarında ortak kalite ve ayar kalıcılığı; ayrıca özgün 8 saniyelik 3840×2160 H.264/AAC test videosunu açma, arama ve oynatma süresinin ilerlemesi. 4K test dosyası yalnız izole test kütüphanesindedir. Kanıt: `artifacts/quality-device-acceptance.xcresult`, `artifacts/quality-device-4k.xcresult` ve ilgili summary JSON dosyaları.
- **54/54 sunucu testi geçti.** Gerçek FFmpeg/FFprobe ile 320 kbps MP3, 4K yatay/dikey akış koruma ve küçük videoyu büyütmeme doğrulandı. Akış kopyalanan 4K videoların çözülmüş kare hashleri kaynakla aynı. yt-dlp seçicisi HDR, 8K ve 120 fps örnekleri yerine sınırlar içindeki SDR seçeneğini seçti. Kanıt: `artifacts/quality-server-all.log`.
- Bağımsız canlı YouTube denemesinde MP3 **320.000 bit/sn, 44.100 Hz**; MP4 **1920×1080 H.264/AAC**, kaynak çözünürlüğü korunarak çıktı. İki dosya tamamen çözüldü ve aktarım onayı sonrası sunucu temizliği doğrulandı. Bu örnek 1080p’dir; 4K telefon kabul testi ayrı özgün dosyayla yapıldı. Kanıt: `artifacts/quality-live-validation.json`.
- **Kullanıcının indirdiği 66 parçanın tüm kimlikleri, mevcut çalma listesi ve tamamlanmış 66 indirme kaydı korundu.** Son kitaplıkta 66 parça vardır; önceki 69 kayıttaki üç özgün demo artık yoktur, yeniden eklenmedi. UI testleri yalnız önbellekteki izole klasörde çalıştı. Kanıt: `artifacts/quality-device-preservation.json`.
- Canlı Mac servisi API1.4, `download_quality`, standard/highest profilleri ve dört hazırlama çalışanıyla doğrulandı. FFprobe doğrulanmış runtime aracı olarak kuruldu; kimlik bilgileri Git dışındadır.
- Fiziksel ekranlar: `Preview/16-iPhone-En-Yuksek-Kalite.png`, `Preview/17-iPhone-4K-Oynatma.png`. Kalite kaynakla sınırlıdır; MP3 kayıplıdır, düşük çözünürlük büyütülmez. Mevcut 512 MiB dosya sınırı korunur; HDR dönüştürme desteklenmez.

# Ritim 1.3 doğrulaması — 26 Ekim 2026

- **CLIProxy entegrasyonu kuruldu; sürüm 1.3.0 / yapı 4 gerçek iPhone 15'e yüklendi ve normal kullanıcı kütüphanesiyle açıldı.** İmzalı cihaz ve simülatör derlemeleri başarılı.
- Mevcut bağlı hesaplarla **GPT-6 Luna, GPT-6 Astra, Claude Sonnet 5.5 ve Gemini 3.8 Flash** gerçek yanıt üretti. Her model Ritim'in `/v1/ai/chat` ucundan çağrıldı; dönen model kimliği seçilenle eşleşti ve iki mevcut parçalık liste doğrulandı. Kanıt: `artifacts/ai-api-live.json`, `artifacts/ai-proxy-schema-probes.json`.
- Büyük önerilerin JSON çıktısının kesilmemesi için yanıt bütçesi 6.000 token olarak ayarlandı. **100 parçalık gerçek Luna çağrısı 100/100 UUID'yi doğru sırayla döndürdü (17,7 sn).** Son ayarla 49 sunucu testi tekrar geçti. Kanıt: `artifacts/ai-100-track-proposal.json`.
- **31 farklı iOS birim testi doğrulandı:** önce 25 mevcut + 5 AI testi (30/30), ardından null katalog varsayılanını kapsayan altıncı AI testi dahil 6/6 odaklı test geçti. Geçersiz parça kimliği, kullanıcı eyleminden önce kitaplığın değişmemesi, atomik liste kaydı, model seçimi kalıcılığı, iptal edilmiş yanıt ve kota/model hatalarında geçiş olmaması sınandı. Kanıt: `artifacts/ai-unit-summary.json`, `artifacts/ai-simulator-retest-summary.json`.
- **Sunucuda 49/49 test geçti.** Kimlik doğrulama, gövde sınırları, geçersiz model/JSON/UUID, kimliği eksik veya farklı model yanıtını reddetme, kota hatasında tek çağrı, yönlendirme/anahtar koruması, iki AI isteği sınırı ve YouTube arama subprocess sınırları; önceki medya/liste testleriyle birlikte. Kanıt: `artifacts/ai-server-tests.log`.
- **Simülatörde üç ilgili UI akışı geçti:** Claude/Gemini canlı yanıt ve model seçimi kalıcılığı; ChatGPT liste önerisi/kayıt/çalma ve gerçek YouTube sonuçları; mevcut uzun başlıklı oynatma/gezinme. İlk arama testi görünür indirme düğmesini erişilebilirlik ağacında bulamadı; kart `.contain` ile düzeltildi ve ilgili akış tekrar geçti. Kanıt: `artifacts/ai-simulator-summary.json`, `artifacts/ai-simulator-retest-summary.json`.
- **Gerçek iPhone'da iki AI UI akışı geçti:** Claude/Gemini yanıt ve kalıcı seçim; ChatGPT önerisi, liste kaydı, oynatma ve sekiz gerçek YouTube sonucu ile MP3/MP4 seçim kontrolleri. Aynı erişilebilirlik düzeltmesinden sonra arama akışı tekrar geçti. İlk denemedeki başarısız sonuç gizlenmedi: `artifacts/ai-device-summary.json`; son başarılı arama: `artifacts/ai-device-retest-summary.json`. Cihazdaki izole test kütüphanesi ayrıca okunarak üç demo ve iki parçalı “Telefon Listesi” doğrulandı.
- **Üretim verileri korundu:** güncelleme öncesi/sonrası 69 parça, bir mevcut çalma listesi ve tamamlanmış 66 indirme kaydı; tüm özgün kimlikler ve liste içeriği aynı. Kanıt: `artifacts/ai-device-preservation.json`. UI testleri yalnız kendi önbellek klasöründe çalıştı.
- CLIProxy anahtarı yalnız sunucudaki Git dışı, 0600 izinli yapılandırmada kaldı; iOS paketine veya kaynaklara eklenmedi. Kaynak dosyalarında gerçek anahtar taraması sıfır eşleşme verdi. Mac servisi boş medya kuyruğunda geçmiş yedeklenerek yeniden başlatıldı; API1.3 ve dört medya çalışanıyla açık.
- Cihaz ekranları: `Preview/13-AI-iPhone-Liste.png`, `Preview/14-AI-iPhone-Gemini.png`, `Preview/15-AI-iPhone-YouTube.png`. Kullanım ve sınırlar: [AI_INTEGRATION.md](AI_INTEGRATION.md).

Aşağıdaki bölümler önceki sürümlerin doğrulama kayıtlarıdır.

# Ritim 1.2 doğrulaması — 26 Ekim 2026

- Oynatıcıdaki otomatik düğme boşlukları kaldırıldı; içerik ekran genişliğiyle sınırlandı. Uzun başlık, paylaş/beğen/tekrar/sıra düğmeleri ve kalan süre için yatay ekran sınırı kontrolü gerçek iPhone'da ve simülatörde geçti. Fiziksel ekran: `Preview/11-iPhone-Oynatici-Duzeltme.png`.
- Eşzamanlı indirme tercihi **2 / 4 / 6**, varsayılan **4**. Eski ayarlar 4'e geçer. Sayıyı artırma, sürmekte olan dosyaları iptal etmeden azaltma, duraklatmayı koruma ve kalıcı tercih testleri geçti.
- **25 birim testi geçti.** Simülatörde uzun başlıklı oynatma ve gerçek ayar menüsünden 2→4→6 / yeniden açılış kontrolü de geçti. İlk menü testi kontrolü fazla kaydırdığı için başarısız oldu; yalnız testin kaydırma yardımcısı düzeltilerek tekrar geçti. Sonuçlar: `artifacts/concurrency-summary.json`, `artifacts/concurrency-setting-retest-summary.json`.
- **Gerçek iPhone'da 2/2 ilgili UI testi geçti:** oynatma/sınır kontrolleri ve 2/4/6 seçim kalıcılığı. Kanıt: `artifacts/concurrency-device-acceptance.xcresult`, `artifacts/concurrency-device-summary.json`.
- **Sunucuda 33/33 test geçti:** dört gerçek paralel alt süreç, tek iş iptalinin diğerlerini koruması, toplam disk sınırı, diğer işler sürerken ACK ve yeniden başlatmada aktif işlerin korunması dahil. Ayrıntı: `server/VALIDATION.md`.
- Kullanıcının gerçek kuyruğu yeniden açıldığında **aynı anda dört canlı hazırlama/indirme işi** gözlendi. Kanıt: `artifacts/concurrency-live-12-final.json`.
- Canlı servis API1.2 / `worker_limit:4` olarak çalışıyor. Güncelleme sırasında aktif sunucu işleri tamamlandıktan sonra SIGTERM ile düzgün kapatıldı; geçmiş yedeklendi ve LaunchAgent yeni sürümü açtı.
- Güncelleme öncesi iPhone'daki29 parçanın tüm kimlikleri son kontrolde46 parça içinde bulundu. Önceki çalma listesi ve tüm66 kuyruk kaydı da kimlik bazında korundu; son telefondaki durum43 tamamlanan,4 aktarılan,19 bekleyen. Kullanıcının dosyaları, çalma listesi ve kuyruk korunuyor. Özel journal kopyaları yalnız `artifacts/` altında tutulur ve kaynak ZIP'e girmez.
- Oynatma ve menü testleri izole fixture kütüphanesi kullanır; uzun başlık testi yerel demo sesini yeniden adlandırır. Test sonrası gerçek kullanıcı kütüphanesiyle uygulama açıldı.
- Son paket1.2.0 / yapı3; ek olarak sürüm metni Info.plist'ten okunur ve ilk ekran açılışında indirme sırasında ekranı açık tutma kuralı uygulanır.

Aşağıdaki bölüm1.1 kapsamının önceki tam kabul testlerini kaydeder; 1.2 için ilgili değişiklik testleri yukarıdadır.

# Ritim 1.1 teslim doğrulaması — 26 Ekim 2026

## Sonuçlar

- **iOS simülatörü: 29/29 test geçti, 0 başarısız, 0 atlanan.** 23 birim testi ve 6 arayüz testi. Kanıt: `artifacts/bulk-final-acceptance.xcresult`, `artifacts/bulk-final-summary.json`.
- **Gerçek iPhone 15: 6/6 arayüz testi geçti, 0 başarısız, 0 atlanan.** Kanıt: `artifacts/bulk-device-acceptance.xcresult`, `artifacts/bulk-device-summary.json`.
- **Python servis: 27/27 test geçti.** Ayrıntı ve canlı servis sonucu: `server/VALIDATION.md`, `server/validation_bulk_live.json`.
- Xcode 27.1 (27A9275), iOS 17+ hedefi: simülatör ve fiziksel iPhone için imzalı derlemeler başarılı. Sürüm etiketi 1.1.0 / yapı 2; test sonrası yalnızca sürüm metadata alanları düzeltilerek cihaz paketi yeniden derlendi.

## Toplu indirme kanıtı

- Birim testi 1.000 kaydı ekleme, kalıcı sırayı yeniden yükleme, 1.000 sınırını aşanları sayma, tekilleştirme, MP3/MP4 ayrımı ve FIFO düzenini doğruladı.
- Gerçek iPhone ve simülatör arayüzünde 500 bağlantı ekleme, aynılarını tekrar eklememe, uygulama kapatılıp açıldığında 500 kaydı ve duraklatmayı koruma, toplu iptal geçti.
- İki hazırlama/aktarım hattı sınırı, duraklatırken mevcut dosyaların tamamlanması, yeniden deneme ve hazırlama iptal edilirken anında yeniden deneme test edildi.
- Eski geçmiş uyumluluğu, bozuk dosya/yazma hatası koruması, 500 parçalık liste çözümleme, çözümleme iptali/hatası ve kütüphanedeki mevcut parçayı tekrar indirmeden yeni listeye bağlama test edildi.
- Dosya telefonda doğrulanıp kalıcı kaydedildikten sonra sunucu temizliği; geçici hata sonrası tekrar onay; eski sunucu veya 404 iş kaydının yeni dosyaların temizliğini engellememesi test edildi. Eski sunucuya güncel erişim anahtarı gönderilmez.

## Gerçek YouTube ve iPhone akışı

Kullanıcının `RDEMTPfPURSbYpb0YHCKyIG37Q` bağlantısı **Mix - Adele** olarak çözümlendi. 1.000 üst sınırıyla canlı servis taraması 4,31 saniyede 66 öğe döndürdü; o sonuçta atlanan veya sınırdan kesilen öğe yoktu. Mix dinamik olduğu için sonraki taramalarda sayı ve sıra değişebilir.

Bu bağlantı gerçek iPhone uygulamasında ve simülatörde tarandı; listede arama, tümünü seç/seçimi temizle, iki parçayı seçip duraklatılmış kuyruğa ekleme ve aynı adlı yerel çalma listesini oluşturma geçti. Bu liste testi metadata ve seçim testidir; Adele listesinin tamamı indirilmedi.

Herkese açık kısa `gHKT4uU8Zng` örneği uygulama içinden **hem MP3 hem MP4** olarak indirildi, yerel kitaplığa eklendi ve video oynatıldı. Aynı akış fiziksel iPhone'da ve simülatörde geçti. Servisin bağımsız testinde MP3 123.000 byte, H.264/AAC MP4 24.267 byte; her iki dosya FFmpeg ile tamamen çözüldü. Aktarım onayı sonrası sunucu dosyası temizlendi (ack 200, dosya 410).

500/1.000 öğe testleri kuyruk ölçeği ve kalıcılığı sınar; yüzlerce gerçek medya dosyası indirilmiş olduğu iddia edilmez. UI testleri yalnızca `Caches/RitimUITestFixtures` alanını kullanır; kullanıcının gerçek kütüphanesi korunur.

## Kurulum ve ekranlar

`com.mehmetderin.ritim` bağlı iPhone 15'e kuruldu ve açıldı. Kurulum kaydı: `artifacts/bulk-device-installed.json`. Son sürüm metadata düzeltmesi sonrası kurulum: `artifacts/bulk-device-installed-final.json`.

`Preview/06`–`10` görselleri fiziksel iPhone'da başarılı testlerin ekran görüntüleridir. Diğer görseller önceki simülatör akışındandır; tasarım maketi değildir.

Mac servisi `http://Mehmet-Mac-mini.local:8765` adresinde çalışır. `local.ritim.media-server` LaunchAgent'ı 1.1 API ile yeniden başlatıldı; `/health` ve kimlik doğrulamalı `/v1/status`, `playlist_resolve` / `job_ack` yeteneklerini doğruladı. Eski iş geçmişi yeniden başlatma öncesinde özel runtime klasöründe yedeklendi. Mac oturum açılışında otomatik başlar.

İndirme hazırlanırken Mac açık/uyanık ve iPhone ile aynı ağda olmalıdır. Büyük kuyruklar için uygulamayı açık tutma önerilir; iOS askıya aldığında yeni hazırlık bekleyebilir. Telefona kaydedilen dosyalar sonrasında bağımsız çalar.

## Sınırlar

- 1.000 tamamlanmamış kuyruk öğesi ve iki eşzamanlı telefon hattı; sunucuda tek dönüştürme çalışanı. Varsayılan dosya/süre/depolama sınırları `server/README.md` içinde.
- Tüm YouTube video/hesap/bölge koşulları veya otomatik Mix içerikleri garanti edilmez. Erişim gerektiren öğeler açıklamalı hata gösterebilir.
- AirPlay, Bluetooth kulaklık kumandaları ve kilit ekranında uzun süreli oynatma donanımla ayrıca sınanmadı.
- App Store/TestFlight yayını yapılmadı.
- iOS 27, AVAudioSession etkinleştirme sırasında ana iş parçacığı uyarısı veriyor; testlerde takılma oluşmadı.
- Kaynak ZIP, erişim anahtarı, indirilen medya, runtime geçmişi ve cihaz yedeklerini içermez.

## Tekrar çalıştırma

Xcode'da Ritim şemasının testlerini çalıştır. Canlı UI testlerinden önce `scripts/pair_device.py` ile geliştirme derlemesini servise bağla. Liste testi için test çalıştırıcısının `RITIM_UI_TEST_PLAYLIST_URL` ortam değişkenine herkese açık liste URL'si ver. iOS simülatöründeki Keychain testleri için varsayılan ad-hoc imzalamayı koru. Fiziksel test başlarken telefonun kilidi açık olmalıdır.

## 2026-10-29 — Background timeout recovery

Native background delegate errors now retain their Error type and use the existing bounded 5/15/45-second retry policy instead of opening a global alert and immediately requeueing. The failed generation journal is removed before cancelling sibling transfers, preventing stale callbacks from consuming retries. Completed checkpoints remain available; exhausted/permanent errors appear on the download row.

Simulator NativeScratchTests + DownloadPolicyTests: 13 passed, 2 optional live tests skipped, zero failures (`/tmp/ritim-timeout-tests.xcresult`). Added regression covers timeout backoff, retry exhaustion/persistence, checkpoint retention, and stale cancellation callbacks. Signed device build succeeded; installed and launched on the connected iPhone 15. Before/after reads retained all 280 track IDs, 10 playlist IDs and 12 download IDs. No live locked-network timeout was induced in this run. Existing unrelated working-tree changes were retained.
