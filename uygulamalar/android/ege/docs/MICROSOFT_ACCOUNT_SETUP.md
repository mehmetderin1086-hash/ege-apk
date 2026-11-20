# Ege Microsoft hesap bağlantısı

Uygulamadaki **Ayarlar → Bağlı hesaplar** bölümünde Outlook/Hotmail, OneDrive (Word/Excel) ve Microsoft Takvim ayrı bağlanır. Android MSAL 8.7.0 kullanılır; kişisel hesaplar ile iş/okul hesapları desteklenecek şekilde yapılandırılmıştır. Gerçek uygulama kaydı henüz yapılmadı; boş istemci kimliğiyle Bağlan, kurulumu beklediğini açıkça bildirir. Bağlı durumu yalnız API okuma kontrolü başarılı olduktan sonra kaydedilir.

## Bir defalık geliştirici kaydı

1. Microsoft Entra uygulama kayıtlarında Ege oluştur. Desteklenen hesap türünü **Accounts in any organizational directory and personal Microsoft accounts** seç.
2. Android platformu ekle. Paket `com.jarvis.assistant.jarvis_mobile`; imzanın SHA-1 değeri `93:56:5C:C7:CB:1E:94:41:9E:D4:42:63:36:FF:2A:BE:03:0C:14:7E`. İmza hashinin Base64 biçimi ve dönüş URI'si `android/app/src/main/res/values/microsoft.xml` ile AndroidManifest'teki BrowserTabActivity filtresiyle eşleşmeli. İmzayı değiştirirsen her ikisini ve Entra kaydını birlikte güncelle.
3. Microsoft Graph **delegated** izinleri: User.Read, Mail.Read, Mail.Send, Files.ReadWrite, Calendars.ReadWrite. Uygulama hizmetleri ayrı yetkilendirir. Kurum politikasına bağlı olarak yönetici izni gerekebilir.
4. Uygulama (client) kimliğini Gradle'ın `egeMicrosoftClientId` özelliği olarak ver (ör. kullanıcının yerel Gradle özellikleri). Bu herkese açık uygulama kimliğidir; istemci sırrı oluşturma ve APK'ya koyma. Ardından APK'yı derle/yükle.
5. Kullanıcı Ege'de ilgili **Bağlan** düğmesine dokunarak resmi Microsoft giriş ekranını ve izinleri tamamlar. Şifre uygulamadan okunmaz. MSAL erişim/yenileme anahtarlarını kendi korumalı önbelleğinde tutar; sohbet veya Obsidian'a yazılmaz.

## Davranış ve sınırlar

- Hesap hizmet bazında seçilir; sonraki araç çağrıları o hesabı kullanır. Yeni izin gerektiğinde arka plan aracı kendi kendine giriş ekranı açmaz.
- Bağlantıyı kapat, Ege'nin o hizmete erişimini kapatır. Diğer bağlı hizmetler aynı hesabı kullanabilir; sağlayıcının hesap uygulama izinleri ayrıca iptal edilebilir.
- Outlook gönderiminde HTTP 202 yalnız isteğin kabulüdür, teslim onayı değildir. Ağ zaman aşımında aynı mesaj otomatik yeniden gönderilmez.
- OneDrive aracı dosya listesi/metadata/web bağlantısı ve en fazla 5 MB Ege dosyası yüklemesi sağlar. Aynı isimli mevcut dosyayı sessizce değiştirmez. Word/Excel için ayrı hesap gerekmez. Bu sürüm mevcut çalışma kitaplarının hücrelerini Graph üzerinden düzenlediğini iddia etmez.
- Takvim oluşturma/güncelleme açık saat dilimi ister. Mail gönderimi, takvim yazma ve dosya yükleme yalnız açık kullanıcı talimatıyla kullanılır. Uzak içerikler komut olarak ele alınmaz.
- Gerçek hesaba giriş ve gerçek API işlemleri, kayıt tamamlanmadan doğrulanmış sayılmaz. Testlerde gerçek mesaj gönderilmez.

## Resmi kaynaklar

- [MSAL Android](https://github.com/AzureAD/microsoft-authentication-library-for-android)
- [Token alma](https://learn.microsoft.com/en-us/entra/msal/android/acquire-tokens)
- [MSAL yapılandırma](https://learn.microsoft.com/en-us/entra/msal/android/msal-configuration)
- [Graph izinleri](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Outlook gönderimi ve HTTP 202 anlamı](https://learn.microsoft.com/en-us/graph/api/user-sendmail?view=graph-rest-1.0)
- [OneDrive dosya yükleme](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content?view=graph-rest-1.0)
