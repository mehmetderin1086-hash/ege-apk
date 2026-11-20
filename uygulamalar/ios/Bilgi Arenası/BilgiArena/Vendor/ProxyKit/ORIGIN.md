# ProxyKit kaynak bilgisi

29 Ekim 2026 tarihinde `/Users/mehmetderin/Developer/cliproxy-ios/ProxyKit` çalışma kopyasının Swift kaynaklarından alınmıştır. Derleme çıktısı, hesap kasası, kimlik doğrulama dosyaları ve runtime yapılandırması içermez. Bilgi Arenası bu sabit kopyayı derler; telefon hesaplarını CLI Proxy uygulamasının ortak Keychain grubundan okur. VPS engeli uygulamaya ait `Sources/PhoneGateway.swift` katmanındadır.

2.5 yerel ek: `OAuthClient.refreshedGoogleAccount` Google Cloud Chirp için aynı, dönmeyen Google OAuth belirtecini yeniler. Google kimliği yalnız cihazdaki ortak kasadan gelir; sunucu eşitlemesi eklenmez.
