# Ege Google hesap bağlantısı

Kod Gmail okuma/gönderme, Drive listeleme/metadata/yükleme ve Google Takvim listeleme/etkinlik oluşturma/güncelleme araçlarını içerir. Google Cloud kaydı ve kullanıcının telefondaki izni tamamlanmadan bağlı değildir.

## Android OAuth kaydı

17 Kasım 2026: telefondaki Chrome üzerinden `dauntless-motif-515011-s9`
projesinde Ege branding (External / Testing) ve `Ege Android` istemcisi
oluşturuldu. Android istemci kimliği (sır değildir):
`REPLACE_WITH_GOOGLE_OAUTH_CLIENT_ID`.
Kullanıcının oturum açtığı destek hesabı test kullanıcısı olarak kaydedildi.
Bu kayıt tek başına telefonda hesap bağlantısının doğrulandığı anlamına gelmez.

Aynı gün Gmail, Drive ve Calendar API'leri etkinleştirildi. Test kullanıcısı
listesinde hesabın yer aldığı görüldü. Ege 4.4.1'de üç hizmet için izin akışı
tamamlandı ve her birinin okuma isteği sonrası arayüzde “Bağlı / Bağlantı
doğrulandı” durumu gözlendi. Gerçek mail veya takvim yazma testi yapılmadı.

- Paket: `com.jarvis.assistant.jarvis_mobile`
- Geçerli APK imza SHA-1: `93:56:5C:C7:CB:1E:94:41:9E:D4:42:63:36:FF:2A:BE:03:0C:14:7E`
- İmza SHA-256: `28:19:7C:B4:FB:BC:3C:F7:69:2C:8B:42:F2:DA:C7:26:51:F8:B6:16:F2:DA:74:AA:61:81:46:01:44:B5:2F:77`
- Uygulama hâlen mevcut debug imzasıyla güncelleniyor; imza değiştirilirse OAuth kaydı da güncellenmeli. İmzayı değiştirerek mevcut kurulumu/verileri kaybetme.

Chrome'da https://console.cloud.google.com/ açılır. Ege için proje oluşturulur veya kullanıcının uygun projesi seçilir. Gmail API, Google Drive API ve Google Calendar API etkinleştirilir. Google Auth Platform → Branding bölümünde Ege adı ve gerçek destek/iletişim hesabı girilir; Audience → External / Testing seçilir ve kullanıcının Google hesabı test kullanıcısı eklenir. Clients → Android istemcisi yukarıdaki paket/SHA-1 ile oluşturulur. Gerçek dış kullanıcılara yayınlama, doğrulama ve gerekli politika URLleri ayrı yayın aşamasıdır; kişisel test kurulumu tamamlandı diye herkese açık doğrulanmış uygulama sayılmaz.

Android AuthorizationClient paket/imza kaydını kullanır; APK içine istemci sırrı, servis hesabı veya refresh token konmaz. Telefonda Ayarlar → Google hesapları → istenen hizmet → Bağlan açılır. Kullanıcı hesap/izin ekranını tamamlar. Ege ilgili API'ye bir okuma isteği yaparak bağlantıyı doğrulamadan “bağlı” kaydetmez.

## İzinler

- Gmail: `gmail.readonly`, `gmail.send`.
- Drive: `drive.readonly`, `drive.file` (tüm izinli dosyaların okunabilir metadatası ve Ege dosyalarını yükleme; mevcut tüm dosyalara yazma/silme yetkisi yok).
- Takvim: `calendar.events`, `calendar.calendarlist.readonly`.

Yetkiler hizmet bazında istenir. Erişim tokenları yalnız uygulama belleğinde HTTP isteği için kullanılır; sohbet, Obsidian veya ayarlara yazılmaz. Arka plan aracında yeni izin gerekiyorsa izin penceresini kendiliğinden açmaz; kullanıcıyı ayarlara yönlendirir. Ege'de bağlantıyı kapatma uygulamanın kullanmasını durdurur; Google hesabındaki üçüncü taraf izni ayrıca Google hesabından kaldırılabilir.

## Sınırlar ve doğrulama

Gerçek hesap bağlantısı üç hizmet için doğrulandı; gerçek mail gönderimi test edilmedi. Birim testlerinde sahte HTTP yanıtları kullanılır; gerçek kişilere mail gönderilmez ve takvime deneme etkinliği eklenmez. Drive doğrudan yüklemesi 5 MB ile sınırlıdır; büyük dosyalarda sohbet kartı → Paylaş → Drive kullanılabilir. `google_drive_read` metadata döndürür; tam dosya okunduğu iddia edilmez. Gönderim/ağ zaman aşımı otomatik tekrarlanmaz.

Kaynaklar: [Android Google yetkilendirme](https://developer.android.com/identity/authorization), [Gmail gönderim](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.messages/send), [Drive yükleme](https://developers.google.com/workspace/drive/api/guides/manage-uploads), [Takvim etkinlikleri](https://developers.google.com/workspace/calendar/api/v3/reference/events/insert).
