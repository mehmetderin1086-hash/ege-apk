# Bilgi Arenası 2.7.0 geliştirme kapsamı

| Özellik | Uygulama |
|---|---|
| iPhone CLI Proxy hesapları | Ortak Keychain, aynı ProxyKit motoru, uygulama içinden doğrudan sağlayıcı |
| VPS kullanmama | Uygulamaya özel filtrelenmiş kasa, kapalı remote/fallback, sağlayıcı alan adı kontrolü |
| Model seçimi | Bağlı yerel modellerin tamamı, aile/arama, sohbet ve diğer yetenek ayrımı |
| Model takımı | Seçilen metin modelleriyle 5'li paketleri sırayla üretme |
| Model denetimi | Gerçek küçük istek, sonuç/zaman, iptal edilebilir toplu test |
| Oyun kipleri | Klasik, süresiz öğrenme, 7 saniyelik hız turu |
| Öğrenme | Yanlış sorular, aralıklı tekrar, AI koç, isteğe bağlı ikinci model kontrolü |
| İçerik | İndirilen AI paketleri çevrimdışı, günün turu, tekrar soruları dışlama |
| Başlangıç havuzu | 174 hazır soru; dokuz kategori ve üç zorluk |
| Günlük otomatik havuz | Her kategoriden 50, toplam 450 hedef; üç seviyeye 16–17 dağılım |
| Çoklu model üretimi | Aileler ve modeller arasında sıra, ayrı sağlayıcılara öncelik, hatada 30 dakika bekletme |
| Kalıcı havuz | SQLite, paket başına işlem, günler arası benzersizlik, oynanmamış sorulara öncelik |
| Arka plan | BGProcessingTask, süre sonu iptal ve yeniden planlama; iOS günlük tamamlanmayı garanti etmez |
| Havuz yönetimi | Arama, kategori/zorluk, cevap/açıklama, deftere kayıt, cihazda sorun işaretleme/gizleme ve geri alma |
| İlerleme | XP, seviye, kategori başarısı, rozet, tur geçmişi |
| Eksik sosyal özellikler | Canlı çok oyunculu oda ve bulut sıralaması bu sürüm kapsamında değil |

| Görsel sorular | 5 tür, 12 örnek, üç yerel fotoğraf, çevrimdışı çizim, erişilebilir veri ve 1–3× büyütme |
| Soru biçimi | Karma/Görsel/Metin; AI doğrulama ve günlük görsel/karma dönüşümü |
| Tur süreleri | 1–30 dakika, seçilebilir soru süresi, saklanan saat, mola/cevapta durma |
| Yeni modlar | Dakika Turu, üç etaplı tur; Keşif/Kısa Tur/Maraton ön ayarları |
| Oyun sesi | Yedi yerel efekt, isteğe bağlı Türkçe konuşma, ayrı anahtarlar ve ses denemesi |
| Yeni soru türleri | Dinleme, sıralama, eşleştirme, yabancı dil söyleme; 12 örnek, AI üretimi ve filtreler |
| Sesli cevap | Yerel WhisperKit small; metin önizlemesi ve onay, 12 saniye kayıt, çevrimdışı çözümleme |
| Söyleme alıştırması | Hedef kelime karşılaştırması ve tekrar; aksan/fonem puanı yok |
| Ders seçimi | TYT/AYT/KPSS/LGS + ders; alt konu/ünite yok |
| Paylaşım | Tek soru, filtre veya tüm havuz; JSON, yerel iOS paylaşım/Dosyalar |
| Toplu içe aktarma | Çoklu dosya, önizleme, 100'lük kalıcı gruplar; 100 MB/100.000 sınır, tekrar/geçersiz sayımı ve geri alma |
| Yeni kayıt benzersizliği | Modelden bağımsız anahtar ve yakın metin denetimi; eski havuzu tarama yok |

| Soru sesi API'leri | Doğrudan Azure HD / Google Chirp 3 HD; CLI Proxy speech; dil/ses seçimi ve 100 MB cihaz önbelleği |
| Canlı sesli tur | Havuzdan süresiz tur; okuma → dinleme → 3 sn iptal edilebilir önizleme → sonuç → sonraki soru |
| Asistan ses yolları | Seçili Azure/Chirp/iPhone sesi + yerel Whisper; ChatGPT Realtime ve Gemini Live API bağlantıları |
| Canlı API durumu | iPhone testinde ChatGPT kredi tükenmesi, Gemini WS 1011; ses üretimleri doğrulanmadı, görünür sıralı yedek yol |
| Sesli tur güvenliği | Belirsiz yanıtta puan yok; sessizlikte kayıt sonu, 12 sn kayıt sınırı, arka planda duraklatma, kanonik cevaptan puan |

| Mikrofon/Whisper görünürlüğü | Kaydırmada kalan sabit alt çubuk, gerçek kayıt/çözümleme ayrımı, izin ön kontrolü, düşük ses ve HFP girişi |

| Ayarlar sekmesi | Ses/uyarı, titreşim, konuşma hızı, soru sesi, sesli yanıt, canlı tur, havuz, veri ve hakkında bölümleri |
| Sesli yanıt ayarları | Otomatik dinleme, sessizlikte bitirme (0,8/1,2/2 sn), en uzun kayıt (8/12/20 sn), geri sayımlı onaysız gönderim |
| Whisper model yönetimi | Durum, disk boyutu, indir/yükle/sil |
| Yanıt anlama | Dolgu sözü soyma, sıra sözcükleri, harf okunuşları, tek ve açık ara en yakın seçenek |
| Veri yönetimi | Ses önbelleği temizleme, onaylı ilerleme ve ayar sıfırlama |

