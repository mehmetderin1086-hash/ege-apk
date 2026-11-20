import Foundation

/// Kâğıt'ın bütün katmanlarında kullanılan, Türkçe açıklamalı hata türü.
public enum KagitHata: LocalizedError, Equatable, Sendable {
    case acilamadi(String)
    case parolaGerekli
    case parolaYanlis
    case kaydedilemedi(String)
    case dogrulamaBasarisiz(String)
    case gecersizAralik(String)
    case bosGirdi
    case desteklenmiyor(String)
    case iptal
    case sunucu(String)
    case yapayZeka(String)
    case pdfium(String)
    case genel(String)

    public var errorDescription: String? {
        switch self {
        case .acilamadi(let ad): "“\(ad)” açılamadı. Dosya bozuk ya da PDF değil."
        case .parolaGerekli: "Bu PDF parola korumalı. Parolayı girin."
        case .parolaYanlis: "Parola yanlış."
        case .kaydedilemedi(let neden): "Kaydedilemedi: \(neden)"
        case .dogrulamaBasarisiz(let neden): "Kaydedilen dosya doğrulanamadı: \(neden). Özgün dosyaya dokunulmadı."
        case .gecersizAralik(let metin): "Sayfa aralığı anlaşılamadı: “\(metin)”. Örnek: 1-3, 5, 8-"
        case .bosGirdi: "İşlenecek dosya ya da sayfa yok."
        case .desteklenmiyor(let ne): "Desteklenmiyor: \(ne)"
        case .iptal: "İşlem iptal edildi."
        case .sunucu(let neden): "Sunucu hatası: \(neden)"
        case .yapayZeka(let neden): "Yapay zekâ hatası: \(neden)"
        case .pdfium(let neden): "PDF motoru hatası: \(neden)"
        case .genel(let neden): neden
        }
    }
}

/// Uzun işlemlerin ilerleme bildirimi (0...1). Herhangi bir iş parçacığından çağrılabilir.
public typealias Ilerleme = @Sendable (_ oran: Double) -> Void

/// İptal denetimi: uzun döngüler her adımda çağırır.
@inline(__always)
public func iptalDenetle() throws {
    if Task.isCancelled { throw KagitHata.iptal }
}
