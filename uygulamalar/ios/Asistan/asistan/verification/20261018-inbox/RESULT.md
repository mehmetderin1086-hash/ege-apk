# Mehmet Asistan 0.15.0–0.15.1 · Aktarılan Bildirim ve İleti Gelen Kutusu

Tarih: 18 Ekim 2026

## Sonuç

- Menü ve Telefon işlemleri içine yerel Gelen Kutusu eklendi.
- `Gelen iletiyi kaydet` App Intent'i Kestirmeler içinde kullanılabilir; uygulamayı açmadan kaynak, gönderen ve içerik kaydeder.
- iOS 27 Bildirim tetikleyicisiyle WhatsApp, Mail ve Mesajlar'ın yeni bildirimleri kaynaklarına özel App Intent eylemlerine aktarılır.
- Arama, kaynak filtresi, okundu/yeni, silme, ayrıntı, özet ve yanıt taslağı vardır. En fazla 500 ileti ve ileti başına 12.000 karakter tutulur. Veri `completeFileProtection` ile iPhone Documents alanına atomik yazılır.
- Asistan `gelenKutusu` aracıyla yalnız aktarılmış içerikleri listeler ve okur. Bildirim Merkezi geçmişi veya özel uygulama gelen kutusu erişimi iddia edilmez.

## Doğrulama

- Simülatör: 136 Swift testi / 33 suite geçti; 7 XCUITest geçti.
- Fiziksel iPhone 15: 0.15.0 build 24 imzalandı, kuruldu ve normal başlatıldı.
- Fiziksel kabul: Mail ve WhatsApp örnekleri kaydedildi; kaynaklar doğru sınıflandı; okundu durumu ve diskten yeniden yükleme geçti. `device-result.json`: `tamamlandi=true`, `kalici=true`, `okunmamis=1`.
- App Intents derleme metadata'sında `GelenIletiKaydetIntent` keşfedilebilir, `openAppWhenRun=false`; `GelenKutusunuAcIntent` ve iki Türkçe App Shortcut cümlesi bulundu.
- 0.15.1 build 25 ile kurulum sadeleştirildi: `WhatsApp bildirimini kaydet`, `Mail iletisini kaydet` ve `Mesajlar iletisini kaydet` ayrı hazır eylemler olarak metadata'da doğrulandı. Gelen Kutusu kurulum ekranı doğrudan `shortcuts://automations` adresini açar. Son derleme fiziksel iPhone'a kuruldu; 136 Swift testi yeniden geçti.
- Kullanıcının açık izniyle fiziksel iPhone'da üç kişisel otomasyon kuruldu ve etkinleştirildi: `WhatsApp bildirimi aldığımda → WhatsApp bildirimini kaydet 2`, `Mail bildirimi aldığımda → Mail iletisini kaydet`, `Mesajlar bildirimi aldığımda → Mesajlar iletisini kaydet`. Üç tetikleyicinin `Bildirim` sihirli değişkeni kayıt eyleminin metin girişine bağlandı.
- Son idempotent cihaz doğrulamasında üç otomasyon da Kestirmeler listesinde `value: 1` olarak bulundu; test 1/1 geçti. İlk keşifte oluşan eksik E-posta taslağı silindi. Kalıcı özet: `automation-device-final.txt`. Ayrıntılı çalışma günlükleri: `/tmp/shortcuts-install-all.log`, `/tmp/shortcuts-final-verify2.log`, `/tmp/shortcuts-cleanup.log`; Xcode sonuç paketi: `Test-Asistan-2026.10.18_13-19-18-+0300.xcresult`.
- Bu kurulum sırasında kullanıcının bu iş için verdiği açık izinle Device Hub paylaşımı kısa süre açıldı; fiziksel cihazda dokunma desteği olmadığı görülünce kapatıldı. Otomasyonlar ekran paylaşımı olmadan fiziksel XCUITest ile kuruldu. Paylaşım kapalı bırakıldı.

## Platform sınırı

Kişisel otomasyonu iOS, Kestirmeler'in cihaz yerel verisi olarak saklar; üçüncü taraf uygulama bunu App Intent içinden sessizce oluşturamaz ve kişisel otomasyonlar paylaşılabilir `.shortcut` dosyası değildir. Bu telefondaki kurulum, kullanıcının açık yetkisiyle fiziksel UI otomasyonu üzerinden bir defa yapıldı. Yeni bildirim olayı aktarılabilir. Eski Bildirim Merkezi geçmişi ve WhatsApp/Mail özel kutusunun tamamı uygulama tarafından doğrudan taranamaz.
