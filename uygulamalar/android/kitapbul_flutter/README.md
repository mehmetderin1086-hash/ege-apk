# Kitap Bul — Android (Flutter)

Telefondaki `com.mehmetderin.kitapbul_flutter` 1.0.0 APK'sından kurtarılıp derlenebilir hâle getirilmiş proje.

## Kaynak
- `lib/` — 44 Dart dosyası; debug APK'nın `kernel_blob.bin` dosyasından birebir çıkarıldı (değiştirilmedi, yalnız `main.dart` tema/dil eklendi).
- `android/app/src/main/java/...` — yerel köprü. JADX çıktısı derlenmediği için (93 hata) aynı kanal adları,
  yöntemler, sınırlar ve Türkçe metinlerle **temiz Java olarak yeniden yazıldı**. JADX çıktısı başvuru için `kurtarilan/jadx-java/` altında.
- Paket sürümleri APK'dakiyle aynı: mobile_scanner 7.5.0, archive 3.6.1, barcode 2.2.9, crypto 3.0.6, path_provider 2.1.5.

## Kanallar
`kitapbul/camera`, `kitapbul/ocr` (ML Kit, çevrimdışı), `kitapbul/loan_reminders`, `kitapbul/notifications`, `kitapbul/files`
(CSV, JSON/ZIP yedek, iPhone arşivi içe aktarma, katalog/envanter/öğrenci kartı/sertifika/ders kitabı PDF'leri, XLSX).

## 1.0.0'a göre düzeltilenler
- Açık ve koyu tema (sistem ayarını izler), iPhone'daki İndigo ana renk.
- Türkçe yerelleştirme (tarih seçiciler artık Türkçe).
- Yatay fotoğraflarda örnekleme yalnız yüksekliğe bakıyordu → uzun kenara göre (bellek taşması önlendi).
- Release derleme: 130 MB debug yerine ~101 MB release APK.
- Birim testleri: `test/temel_mantik_test.dart` (ISBN, Türkçe arama).

## 1.1.0 Yenilikleri (Amazon, Kitapyurdu, Hızlı Kayıt ve Envanter Sayımı)
- **Amazon ISBN Künye ve Kapak Çekme (`lib/book_lookup.dart`, `lib/cover_fetch.dart`)**: ISBN-10 / ISBN-13 barkodlarından `amazon.com.tr` (ve `amazon.com` yedeği) üzerinden başlık, asıl yazar (`Çevirmen`/`Editör` ayrımıyla), yayınevi, baskı, yayın yılı, sayfa sayısı, dil, okuma yaşı, kategori ve yüksek çözünürlüklü kapak görseli çekme; paralel çoklu kaynak birleştirme (`Amazon + Google Books + Open Library`).
- **Kitapyurdu Başlık / Yazar / Yayınevi Arama (`lib/kitapyurdu_search_dialog.dart`)**: Kitap adı, yazar ve yayınevi alanlarıyla (YKY, İş Bankası, TÜBİTAK gibi kısaltma eşleştirmeleri dâhil) Kitapyurdu araması yapma; seçilen baskının JSON-LD `Book` şemasından ISBN, sayfa sayısı, yayın yılı, dil, baskı, kategori ve kapak görselini tek dokunuşla forma aktarma.
- **Kütüphane Hızlı Kayıt Ekranı (`lib/quick_register_page.dart`)**: Varsayılan raf/konum seçimi, otomatik artan demirbaş numarası üretimi (fiziksel nüsha kaydıyla), mükerrer ISBN nüsha birleştirme, kesintisiz seri kamera barkod okuyucu ve Kitapyurdu üzerinden hızlı kayıt.
- **Eksik Künye ve Kapak Tamamlama (`lib/data_quality_page.dart`)**: Katalogdaki eksik ISBN, yazar, yayınevi, kategori, sayfa sayısı ve kapak görsellerini Amazon ve Kitapyurdu kaynaklarından toplu olarak tamamlama.
- **Gelişmiş Envanter Sayımı (`lib/inventory_page.dart`, `lib/inventory_session.dart`, `lib/continuous_scanner_page.dart`)**: Ana ekrandan doğrudan erişim, canlı ilerleme çubuğu ve özet istatistik kartı, seri barkod tarama modu (flaş, kamera değiştirme, ses/titreşim, geri alma), durum filtreleri (`Tümü`, `Eksikler`, `Hiç sayılmayanlar`, `Fazlalar`, `Tamamlananlar`), `+1 Say` / `-1 Azalt` kontrolleri ve sayımda çıkan **tanınmayan barkodları** çevrimiçi künye çekerek doğrudan kataloğa ve aktif sayıma ekleme.

## 1.2.0 Yenilikleri (Modern Görsel Arayüz, Büyük Kapaklar, Animasyonlar ve Excel Tablo)
- **Baştan Tasarlanan Görsel Arayüz ve 3B İllüstrasyonlar (`lib/book_visuals.dart`, `lib/catalog_views.dart`, `assets/images/`)**: Canlı sayaçlı akıllı kütüphane üst paneli, yay (spring) ölçeklemeli dokunsal gradyan işlem butonları, kademeli (staggered) giriş animasyonları ve 3B boş katalog / tarayıcı görselleri.
- **Büyük Yüksek Çözünürlüklü 3B Kitap Kapakları ve Tam Ekran İnceleyici**: 2 sütunlu **Vitrin** görünümünde dev `126×180` kapaklar, **Büyük Kart** görünümünde `96×142` 3B cilt sırtı gölgeli kapaklar, fotoğrafı olmayan kitaplar için otomatik estetik cilt tasarımı ve iki parmakla yakınlaştırmalı (pinch-to-zoom) tam ekran buzlu cam kapak inceleyicisi (`Ön Kapak`, `Arka Kapak`, `Künye` ve tek dokunuşla internetten kapak indirme).
- **Uygulama İçi Excel Tablo Görünümü ve Çok Sayfalı `.xlsx` Dışa/İçe Aktarım (`lib/catalog_xlsx.dart`)**: Sütun başlığına göre sıralanabilir, sabit başlıklı ve kapak önizlemeli uygulama içi **Excel Tablo** görünümü; `Kitap Listesi`, `Ödünçteki Kitaplar` ve `Raf Özeti` sayfalarından oluşan renkli/filtreli `.xlsx` dışa aktarım ve mevcut `.xlsx` kitap listelerini doğrudan kataloğa içe aktarma.

## Derleme
```
C:\src\flutter\bin\flutter.bat pub get
C:\src\flutter\bin\flutter.bat test
C:\src\flutter\bin\flutter.bat build apk --release
```

## Bilinen sınırlar (iPhone'da olup Android'de olmayanlar)
Gemini yapay zekâ asistanı ve sesli giriş, Face ID rolleri, sırt etiketi/QR kart baskısı,
ana ekran widget'ı, Siri/Spotlight, tanıtım ve "Yenilikler" ekranları.

## İmza
Telefondaki 1.0.0 başka bir bilgisayarın debug anahtarıyla imzalı. Bu APK farklı anahtarla imzalı olduğundan
üzerine güncelleme olarak kurulamaz: önce uygulama içinden **ZIP yedek alın**, eskisini kaldırın, yenisini kurup yedeği geri yükleyin.
