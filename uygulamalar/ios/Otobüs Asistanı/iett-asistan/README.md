# Otobüs Asistanı (İETT)

İstanbul İETT otobüsleri için iPhone uygulaması: canlı araç takibi, durağa kaç dakikada geleceği, planlı kalkışlar, duyurular ve yapay zekâ asistanı.

- **Veri:** İBB açık veri SOAP servisleri (`api.ibb.gov.tr/iett`): hat, durak, canlı konum (`GetHatOtoKonum_json`), planlı sefer saati, duyuru. Anahtar gerekmez.
- **Güzergâh:** `DurakDetay_GYY_wYonAdi` ile hattın sıralı durakları (yön adlarıyla) hat başına diske alınır; tüm hatlar bir kez arka planda indirilir ve "durağa uğrayan hatlar" dizini kurulur.
- **Varış süresi:** Araç hat çizgisine izdüşürülür; durağa kalan yol ÷ hız (ölçülen ve hat ortalaması karışımı). Yön araç güzergâh kodundan (G/D) bellidir, durağı geçen araç elenir, "N durak kaldı" verilir. Güzergâh yoksa kuş uçuşu tahmine (`~`) düşer. Tahmindir.
- **Alarm:** Takipteki durak için "X dk kala bildirim" (uygulama çalışırken/arka planda kısa süre; uygulama sonlandırılmışsa sunucu olmadığı için gelmez).
- **Yapay zekâ:** Apple Intelligence (cihaz içi, `FoundationModels`) + araçlar; kapalıysa Türkçe kural tabanlı asistan.
- **Derleme:** `xcodegen generate` → `IETTAsistan.xcodeproj`. Testler: `xcodebuild test -scheme IETTAsistan` (canlı API testleri ağ ister).
- Debug bayrakları: `-openTab=N`, `-openLine=500T`.

## Canlı konum kotası
İBB canlı konum servisi (`FiloDurum`) **saatte 100 istek** ile sınırlıdır; aşılınca `Rate limit exceeded` ile bir süre kapanır (VPN yalnız ayrı bir kota verir, çözüm değildir). `FleetBudget` saatte 90 çağrıyı App Group'ta sayar (uygulama+widget ortak), hat başına önbellek tutar, yenileme aralığını etkin hat sayısına böler ve ETA'yı çağrılar arasında kendiliğinden geri sayar. Testlerdeki canlı çağrılar kotadan yer: `-skip-testing:IETTAsistanTests/LiveAPITests`.

## Gezinme ve ekranlar
`Route` enum'u bütün hedefleri tanımlar; her sekme kendi `Navigator` yığınına sahiptir (yüzen geri/ileri/ana sayfa çubuğu, kenardan kaydırma ileri listesini besler). Asistan cevaplarındaki eylem çipleri, widget ve bildirimler aynı rotaları açar. Yakınımda sekmesi: Liste / Harita / Rota planla (aktarmasız hat bulucu, `TripPlanner`). Hatlar: Canlı / Sefer saatleri kipi, sabit ve son bakılan hatlar. Debug bayrakları: `-openTab=N`, `-openRoute=line:500T|timetable:500T|info:500T|stop:CODE|settings|notes`, `-demo`.

## Rota, kayıtlı yolculuk, bağlantılar
`TripPlanner.direct` aktarmasız, `TripPlanner.withTransfer` en çok tek aktarmalı seçenek bulur (aktarma aynı durak kodunda, bekleme 6 dk varsayımı). Yolculuklar kaydedilir ve Takip sekmesinde canlı özetlenir. `iettasistan://line/500T?stop=ID`, `…://stop/ID`, `…://timetable/500T` bağlantıları widget dokunuşuyla ilgili ekranı açar.

## Ekran sekmesi (akıllı durak panosu)
Seçilen duraktan geçen hatların sıradaki geçişi tarifeden (kotasız), en yakın 3 hat için canlı konumdan hesaplanır; süreler saniye saniye geri sayılır, 7'den fazla satır otomatik sayfa döner, duyurular kayan bantta akar. Sağ üstteki düğme gerçek tam ekran (kiosk) kipini açar: ekran uyumaz, dokununca kapatma düğmesi çıkar. Debug: `-openTab=4 [-kiosk] [-demo]`.
