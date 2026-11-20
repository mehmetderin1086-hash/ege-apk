import Foundation
import FoundationModels
import UIKit

nonisolated struct KisayolAraci: Tool {
    let name = "kisayolCalistir"
    let description = "Kısayollar uygulamasındaki bir kısayolu adıyla çalıştırır (örn. 'Ev modu', 'Zamanlayıcı kur'). İsteğe bağlı metin girdisi verilebilir. Doğrudan aracı olmayan işler için köprü."

    @Generable
    struct Arguments {
        @Guide(description: "Kısayolun tam adı") var ad: String
        @Guide(description: "Kısayola gönderilecek metin (isteğe bağlı)") var girdi: String?
    }

    let onay: OnayKapisi

    func call(arguments a: Arguments) async throws -> String {
        guard let url = TelefonAdresleri.kisayol(a.ad, girdi: a.girdi) else { return "Kısayol adı boş olamaz." }
        // Kullanıcının kendi komutunda sorulmaz (Mehmet'in seçimi); dış kaynaklı ya da güvenilmeyen içerik okunmuş turda sorulur.
        guard await onay.disKaynaktaIste(baslik: "Kestirme çalıştırılsın mı: \(a.ad)", ayrinti: String((a.girdi ?? "").prefix(300))) else { return "Kullanıcı onaylamadı; kestirme çalıştırılmadı." }
        try Task.checkCancellation()
        let ok = await TelefonAdresleri.ac(url)
        return ok ? "'\(a.ad)' için çalıştırma isteği Kestirmeler'e iletildi. Kestirmenin varlığı ve tamamlandığı henüz doğrulanmadı." : "Kestirmeler uygulaması açılamadı."
    }
}
