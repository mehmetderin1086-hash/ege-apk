import Foundation
import FoundationModels
import UIKit

nonisolated struct UygulamaAcAraci: Tool {
    let name = "uygulamaAc"
    let description = "Telefondaki uygulama kataloğunda adla eşleştirir; hazırlanmış kestirmeyi çalıştırır veya ekleme ekranını açar. Bilinen bir uygulamayı ya da web adresini açar. Uygulamalar: ayarlar, kamera, fotograflar, muzik, spotify, youtube, whatsapp, instagram, x, safari, haritalar, mesajlar, mail, notlar, saat, takvim, kisayollar. Ya da tam bir https adresi."

    @Generable
    struct Arguments {
        @Guide(description: "Uygulama adı (küçük harf, Türkçe karaktersiz) ya da https adresi") var hedef: String
    }

    nonisolated static let semalar: [String: String] = [
        "ayarlar": UIApplication.openSettingsURLString, "fotograflar": "photos-redirect://", "muzik": "music://",
        "spotify": "spotify://", "youtube": "youtube://", "whatsapp": "whatsapp://", "instagram": "instagram://",
        "x": "twitter://", "twitter": "twitter://", "safari": "https://www.google.com", "haritalar": "maps://",
        "mesajlar": "sms:", "mail": "message://", "notlar": "mobilenotes://", "saat": "clock-alarm://",
        "takvim": "calshow://", "kisayollar": "shortcuts://",
    ]

    static func onayMetni(_ url: URL) -> String {
        let yol = url.path.removingPercentEncoding ?? url.path
        if url.host?.lowercased() == "open.spotify.com", yol.hasPrefix("/search/") {
            return "Spotify’da ara: " + String(yol.dropFirst("/search/".count).prefix(200)) + "\nopen.spotify.com\nBu bağlantı arama ekranını açar; şarkıyı otomatik çalmayabilir."
        }
        return (url.host ?? "") + "\n" + String((url.absoluteString.removingPercentEncoding ?? url.absoluteString).prefix(280))
    }

    let onay: OnayKapisi

    func call(arguments a: Arguments) async throws -> String {
        let h = TelefonAdresleri.ad(a.hedef)
        if ["dosyalar", "dosyalarim", "files"].contains(h) {
            await MainActor.run { DosyaKitapligi.ortak.ekranAcik = true }
            return "Dosyalarım ekranı açıldı. Bağlı klasörlerde arama ve önizleme yapabilirsin; bağlı klasör yoksa bir klasör seç."
        }
        if h == "kamera" {
            await MainActor.run { NotificationCenter.default.post(name: .asistanKamera, object: nil) }
            return "Asistan'ın fotoğraf çekme ekranı istendi. Fotoğrafı kullanıcı çeker ve paylaşır."
        }
        if let kayit = await TelefonKestirmeleri.ortak.bul(a.hedef) {
            return try await KisayolAraci(onay: onay).call(arguments: .init(ad: kayit.kestirme, girdi: nil))
        }
        if let app = await UygulamaKatalogu.ortak.bul(a.hedef) {
            if let url = await UygulamaKatalogu.ortak.calistirmaURL(app) {
                try Task.checkCancellation()
                let ok = await TelefonAdresleri.ac(url)
                return ok ? "\(app.ad) açılış kestirmesi istendi; uygulamanın açıldığı henüz doğrulanmadı." : "Kestirme açılamadı. Kestirmeler'de ekli olduğunu kontrol et."
            }
            // Yerleşik doğrudan bağlantı varsa import gerektirmeden kullan.
            if Self.semalar[h] == nil {
                await MainActor.run { UygulamaKatalogu.ortak.secilen = app.ad; UygulamaKatalogu.ortak.ekranAcik = true }
                return "\(app.ad) için hazırlanmış kestirme ekleme ekranı açıldı. Bir kez Uygulama Köprüsü’nü Kestirmeler’e ekleyip Köprüyü ekledim’i işaretle; sonra sesle açabilirim. Henüz uygulama açılmadı."
            }
        }
        let web = TelefonAdresleri.web(a.hedef)
        guard let url = web ?? Self.semalar[h].flatMap(URL.init(string:)) else {
            return "'\(a.hedef)' için doğrudan bağlantı yok. Telefon işlemleri ekranında bu uygulamaya bir Kestirme bağlayabilirsin."
        }
        try Task.checkCancellation()
        let ok = await TelefonAdresleri.ac(url)
        if ok, let web, web.host?.lowercased() == "open.spotify.com", web.path.hasPrefix("/search/") { return "Spotify şarkı araması açıldı. Şarkının çalmaya başladığı doğrulanmadı; kullanıcı sonucu seçip oynatabilir." }
        return ok ? (h == "ayarlar" ? "Asistan'ın sistem ayarları açıldı." : "\(a.hedef) açma isteği iOS tarafından kabul edildi.") : "\(a.hedef) açılamadı. Telefon işlemlerinden Uygulamayı Aç kestirmesi bağlayabilirsin."
    }
}

extension Notification.Name {
    static let asistanKamera = Notification.Name("asistan.kamera")
}
