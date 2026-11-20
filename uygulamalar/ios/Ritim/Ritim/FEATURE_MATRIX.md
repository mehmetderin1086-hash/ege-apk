# Müzik deneyimi kapsamı — 1.8.0

26 Ekim 2026 karşılaştırması. Amaç mevcut yerel Ritim arşivinde kullanılabilen eksikleri tamamlamak; başka bir servisin bütün ürününü veya abonelik kataloğunu sunduğunu iddia etmek değildir. Çalıştırma sonuçları [VALIDATION.md](VALIDATION.md) içinde tutulur.

| Özellik | Ritim karşılığı | Sınır |
| --- | --- | --- |
| Zaman eşli ve düz şarkı sözleri | LRCLIB, gömülü sözler, LRC/TXT, elle düzenleme; satır takibi, satıra gitme, ±30 sn düzeltme, cihazda kayıt | Her parçada eşleşme yok; çeviri/telaffuz yok |
| Albüm kapağı ve albüm/sanatçı gezinmesi | Dosyanın gömülü bilgileri; eski dosyalar için iptal edilebilir, sıralı ön plan taraması | 1.10: metin metadata içinde bulunan disk/parça numarası okunur; tüm parçalar numaralıysa numara sırası, aksi durumda A–Z. Çevrimiçi kapak kataloğu veya otomatik albüm tahmini yok |
| Sıradaki çal ve sona ekle | Karışık sıra dahil öncelik; mevcut öğeyi taşıma, oturum kaydında koruma | Aynı parça sırada bir kez bulunur; tek-parça tekrarı seçiliyse otomatik tekrar geçerlidir |
| Sırayı liste olarak kaydetme | Seçili sıra düzeniyle normal yerel çalma listesi | Ortak çevrimiçi liste değil |
| Akıllı koleksiyonlar | Dinlenmeyenler, son 30 gün, eski beğeniler, son çalınma sırası; değişen kütüphaneden hesaplama | Öneriler yerel kurallara dayanır; tüm dinleme olaylarının gün/saat günlüğü değil |
| Çevrimdışı çalma, kuyruk düzenleme, AirPlay, uyku zamanlayıcısı | Önceki sürümde mevcut; korunur | İndirme/dönüştürme arka plan kısıtları README'de |
| Gapless / crossfade / EQ / CarPlay | Bu sürümün dışında | Kararlı çalma motoru ayrı performans doğrulaması olmadan değiştirilmedi |
| Apple Music / Spotify / YouTube Music kataloğu, hesap, bulut eşitleme | Bu sürümün dışında | Sağlayıcı yetkisi, ilgili API ve katalog kullanım hakları gerektirir |

## Karşılaştırılan resmi kaynaklar

- [Apple Music şarkı sözleri](https://support.apple.com/en-us/105076): zaman eşli/düz sözler, uygun parçalarda çeviri/telaffuz.
- [Spotify sözler](https://support.spotify.com/us/article/lyrics/): uygun parçalarda zaman eşli söz deneyimi.
- [YouTube Music kişiselleştirme](https://support.google.com/youtubemusic/answer/6313542?hl=en): albüm/sanatçı kategorileri, söz ve öneri özellikleri.
- [Spotify geçiş seçenekleri](https://support.spotify.com/us/article/tracks-transitions/): crossfade, gapless ve Automix ayrı yeteneklerdir.
- [YouTube Music çalma listeleri](https://support.google.com/youtubemusic/answer/7205933?hl=en): düzenleme, sıralama ve ortak liste özellikleri.
- [LRCLIB API](https://lrclib.net/docs): Ritim'in çevrimiçi söz sağlayıcısı; ses dosyasını yüklemez.
- [MusicKit](https://developer.apple.com/musickit/) ve [Spotify iOS SDK](https://developer.spotify.com/documentation/ios): katalog/hesap entegrasyonları için ayrı sağlayıcı akışları.

Uygulama paketine üçüncü taraf şarkı sözü koleksiyonu eklenmez. Otomatik testlerde yalnız bu proje için yazılmış özgün kısa dizeler kullanılır.
