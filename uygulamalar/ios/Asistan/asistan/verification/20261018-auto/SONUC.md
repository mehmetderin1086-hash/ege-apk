# Mehmet Asistan 0.4.0 (5) — 18 Ekim 2026

## Eklenenler
- Özgün 1024×1024, opak M uygulama simgesi; Mehmet Asistan uygulama adı.
- Otomatik Atölye: sınırlı açık komutlar/bağlam devamı yerelde, diğerleri bağlı modelle anlam sınıflandırması; 20 saniyelik kaynak zaman aşımı. Manuel kip korunur. Dosya içeriği sınıflandırıcıya gönderilmez.
- Dost adı ve dört konuşma tarzı; mevcut hafıza/gerçek ses altyapısıyla birlikte.
- SMS/iMessage MessageUI taslağı: gönder/iptal/hata gerçek sistem sonucu. WhatsApp uluslararası numara, güvenli URL kodlaması ve hazır metin; son gönderim kullanıcıda. Gelen mesajlar kullanıcı paylaştığında yanıt hazırlanır.
- Saatlik hava kartı, kaynak/zaman; gerçek araç yaşam döngüsü görünümü.
- İsteğe bağlı kalıcı sunucu görevleri; normal sohbet/telefon işleri iPhone'da. Sunucuya yalnız açıkça istenen metin/araştırma/kod taslağı gönderilir.

## Kanıt
- `tests-final.log`: 64 geçti, 10 koşullu donanım/canlı testi atlandı (Swift Testing toplam 74).
- `server-tests.log`: 5 test geçti; aynı UUID tekrarının tek göreve gitmesi, kuyruk sınırı, iptal, yeniden başlama ve gerçek web çağrısı/kaynak koşulları.
- `iphone-routing-deadline.json`: 9/9 gerçek iPhone yönlendirmesi, GPT-6.1-Sol bağlı hesap. Kod devamı, yazı devamı, olumsuz görsel isteği, yeni telefon isteği, arşiv dahil. Tam yazı yanıtı, 12 saatlik canlı İstanbul hava verisi ve saat aracının günlüğü geçti.
- Sonraki küçük değişiklik: açık ‘...araştır’ komutu yerelde yönlendirilir (birim testi geçti); Siri örnek metninde yeni uygulama adı.
- `iphone-server.json`: iPhone görevi kuyruğa verdi, sunucu tamamladı, telefon sonucu tekrar aldı: ‘Merhaba Mehmet!’.
- `server-live-final.log`: localhost ve HTTPS kimliksiz istek 401, kimlikli liste 200. Metin ve Apple kaynaklı gerçek araştırma tamamlandı. Son ayrıştırıcı yalnız atıf bağlantılarını tercih eder.
- `simulator-mehmet.png`: ana ekran görsel kontrolü. iPhone ekran yansıtması kapalı tutuldu.
- `device-build.log`: gerçek cihaz imzalı derleme. Son adımda paket kuruldu ve test argümanı olmadan açıldı.

## Sınırlar
- Uygulama içi SMS/WhatsApp akışı gerçek bir alıcıya mesaj gönderilerek sınanmadı; kullanıcı onayında gerçek gönderim yapılır.
- Hücresel aramaları devralma, mesaj kutusu okuma veya tüm Siri özel yetkilerini kopyalama yok. Siri/erişilebilirlik yolu açıklanır.
- Grok hesabı bağlı değil; video üretimi eklenmedi. Önceki görsel denemelerindeki kota/erişim engelleri çözülmüş sayılmaz.
- Sunucu kod taslağı üretir; terminal veya uzaktan bilgisayar kontrolü çalıştırmaz. Push bildirim yok; sonuç Atölye > Sunucu görevleri içinde yenilenir. Mevcut OpenAI API hesabı sunucu araştırmasında dar yetenek fallback'i olarak kullanılabilir ve ücret doğurabilir.
- İlk sınıflandırıcı sürümü 8/9 verdi; kanıt dosyaları korunuyor. Kaynak süre sınırı ve bağlam yönlendirmesi sonrası 9/9, gelecekteki bütün istemler için garanti değildir.
