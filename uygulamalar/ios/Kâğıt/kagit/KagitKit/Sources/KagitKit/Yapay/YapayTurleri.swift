import Foundation

/// Sohbet iletisi (kullanıcı ya da asistan).
public struct YapayMesaj: Sendable, Codable, Hashable {
    public enum Rol: String, Sendable, Codable { case kullanici = "user", asistan = "assistant" }
    public var rol: Rol
    public var icerik: String

    public init(_ rol: Rol, _ icerik: String) {
        self.rol = rol
        self.icerik = icerik
    }
    public static func kullanici(_ s: String) -> YapayMesaj { YapayMesaj(.kullanici, s) }
    public static func asistan(_ s: String) -> YapayMesaj { YapayMesaj(.asistan, s) }
}

/// Bir yapay zekâ isteği: sistem yönergesi + ileti geçmişi.
public struct YapayIstek: Sendable {
    public var sistem: String
    public var mesajlar: [YapayMesaj]
    public var azamiToken: Int
    public var sicaklik: Double?

    public init(sistem: String = "", mesajlar: [YapayMesaj], azamiToken: Int = 4096, sicaklik: Double? = nil) {
        self.sistem = sistem
        self.mesajlar = mesajlar
        self.azamiToken = azamiToken
        self.sicaklik = sicaklik
    }

    public init(sistem: String = "", kullanici: String, azamiToken: Int = 4096, sicaklik: Double? = nil) {
        self.init(sistem: sistem, mesajlar: [.kullanici(kullanici)], azamiToken: azamiToken, sicaklik: sicaklik)
    }
}

/// Yanıt ve hangi kaynaktan geldiği.
public struct YapayYaniti: Sendable, Hashable {
    public var metin: String
    /// "claude-sonnet-5-5" ya da "Apple Intelligence".
    public var model: String
    /// Arayüzde gösterilen etiket: "Claude (bulut)" / "Cihaz".
    public var kaynakEtiketi: String

    public init(metin: String, model: String, kaynakEtiketi: String) {
        self.metin = metin
        self.model = model
        self.kaynakEtiketi = kaynakEtiketi
    }
}

/// Akış sırasında gelen metin parçası bildirimi.
public typealias YapayAkisi = @Sendable (String) -> Void

/// Metin üreten bir yapay zekâ kaynağı (cihaz modeli, bulut vekili ya da test saplaması).
public protocol YapayKaynak: Sendable {
    /// Ekranda gösterilen kaynak adı.
    var etiket: String { get }
    /// Tek istekte güvenle verilebilecek yaklaşık girdi büyüklüğü (karakter).
    var baglamSiniri: Int { get }
    func yanit(_ istek: YapayIstek, akis: YapayAkisi?) async throws -> YapayYaniti
}

public extension YapayKaynak {
    func yanit(_ istek: YapayIstek) async throws -> YapayYaniti { try await yanit(istek, akis: nil) }
}

/// Kaynak seçimi tercihi (Ayarlar).
public enum KaynakTercihi: String, CaseIterable, Codable, Sendable, Identifiable {
    case otomatik, yalnizCihaz, yalnizBulut
    public var id: String { rawValue }
    public var ad: String {
        switch self {
        case .otomatik: "Otomatik"
        case .yalnizCihaz: "Yalnız cihaz"
        case .yalnizBulut: "Yalnız bulut"
        }
    }
}

/// Vekilde kullanılabilen modeller. Sıralama, hata durumunda geri düşme sırasıdır.
public enum YapayModeller {
    public static let varsayilan = "claude-sonnet-5-5"
    public static let secenekler: [(kod: String, ad: String)] = [
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("gemini-3.8-flash", "Gemini 3.8 Flash"),
        ("gpt-5.5", "GPT-5.5"),
    ]

    /// Seçili model başta, diğerleri varsayılan sırayla ardından.
    public static func siralama(secili: String) -> [String] {
        let hepsi = secenekler.map(\.kod)
        guard hepsi.contains(secili) else { return [secili] + hepsi }
        return [secili] + hepsi.filter { $0 != secili }
    }
}
