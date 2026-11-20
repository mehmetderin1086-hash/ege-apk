# Ayet arama

Kur’an → Kelime → büyüteç. Türkçe meal, harekeli/harekesiz Arapça ve `Fatiha 1`, `Bakara 255`, `2:255`, `2/255` referansları desteklenir. Yazarken 350 ms gecikmeli arama yapılır. Sonuçlar sure/ayet sırasındadır.

## Tam çevrimdışı paket

114 sure / 6.236 ayet, QuranEnc.com `turkish_rwwad` v1.0.4, Rowwad Translation Center. Arapça metin, meal, dipnotlar ve sürüm bilgileri API’den değiştirilmeden `Sekine/Resources/QuranSearch/quranenc.json` içine alınmıştır. Tam paket hazırsa aramada ağ isteği yapılmaz; normalize edilmiş indeks yalnız eşleştirme için kullanılır, görüntülenen metin kaynaktaki biçimini korur. Kaynak ve sürüm ekranda ve paylaşılan metinde gösterilir.

Sonuç → Detay Göster: büyük Arapça metin, Türkçe meal, varsa dipnotlar, kaynak bağlantısı, paylaşım, önceki/sonraki ayet. Kaydırma ayet değişiminde başa döner. İlk/son ayette sınır düğmesi pasiftir. Kelime verisi bulunan ayetlerde mevcut kelime okuyucusuna ayrıca geçilebilir; bu okuyucunun Diyanet meali kullandığı açıkça belirtilir. Tam metin paketi tüm ayetler için kelime anlamı/zamanlama verisi sağlamaz.

Kaynak: https://quranenc.com/en/browse/turkish_rwwad
API: https://quranenc.com/en/home/api/
Yenileme: `python3 scripts/build_quran_search.py`. Betik sure başına ayet sayısını, sıra/kimlikleri, boş metinleri ve 6.236 benzersiz kaydı doğrular; sürümü ve SHA-256 özetini SOURCE.txt içine yazar. İçerik sürümlerinden önce kaynağın güncel sürümüyle yenileyin. Kaynağın tekrar yayın koşulları SOURCE.txt içindedir.

## Doğrulama

Birim testleri: Türkçe/Arapça normalizasyonu, referans sınırları, 114 surenin tüm ayet numaraları, Bakara 255/Yasin 9/Nas 6 araması, boş sorgu, yerel sonuç/sayaç temizliği ve önceki/sonraki ayet sınırları. Arayüz testleri: Fatiha sonucu → ayrıntı → kelime okuyucusu; Bakara 255 → 256 → 255. Resmi SQLite paketiyle çapraz kontrolde metinler boşluk normalizasyonundan sonra aynıdır; API metinleri aynen korunur.

Tam paket yüklenemezse önceki seçili sureler paketi (438 ayet) ve çevrimiçi servis geri dönüşü kullanılır; bu sınırlı kapsam ekranda belirtilir.

## Arama kolaylıkları

Sure menüsü aramayı seçili sureyle sınırlar. Sadece `Yasin` gibi sure adı yazılması o surenin ayetlerini listeler. `Ayetel Kürsi` ve `Bakara suresi 255. ayet` doğrudan 2:255'e gider; seçilen sureyle çelişirse sonuç gösterilmez.

Son 12 arama yalnız cihazda saklanır. Ara/klavye onayı, öneri seçimi veya sonuç açma geçmişe ekler; her yazılan ara parça kaydedilmez. Türkçe normalizasyonuyla yinelenen sorgu başa taşınır. Boş sorguda son aramalar görünür ve “Geçmişi temizle” ile silinebilir.
