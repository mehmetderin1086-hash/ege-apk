import SwiftUI
import UniformTypeIdentifiers

nonisolated struct GorunumTercihleri: Codable, Equatable, Sendable {
    enum Tema: String, Codable, CaseIterable { case sistem = "Sistem", acik = "Açık", koyu = "Koyu" }
    /// Eski profil uyumu; okunmaz.
    enum Duzen: String, Codable, CaseIterable { case ses = "Ses odaklı", dengeli = "Dengeli", odak = "Yazı odaklı" }
    enum Gosterge: String, Codable, CaseIterable { case kure = "Küre", halkalar = "Halkalar", cubuklar = "Dalga" }
    /// Eski profil uyumu; okunmaz.
    enum Balon: String, Codable, CaseIterable { case sade = "Sade", yumusak = "Yumuşak", kart = "Kart" }
    /// Eski profil uyumu; okunmaz.
    enum Zemin: String, Codable, CaseIterable { case duz = "Düz", isilti = "Işıltı", noktalar = "Noktalar" }
    var surum = 1
    /// Varsayılan sistem: telefon koyu moddayken sohbet de koyu palete geçer (Claude temasının koyu paleti var).
    var tema: Tema = .sistem
    /// Eski profil uyumu; okunmaz.
    var duzen: Duzen = .ses
    var gosterge: Gosterge = .kure
    /// Eski profil uyumu; okunmaz.
    var balon: Balon = .sade
    /// Eski profil uyumu; okunmaz.
    var zemin: Zemin = .duz
    var renk = "F47863"
    var yaziOlcegi = 1.0
    var kureOlcegi = 1.0
    var hareket = true
    var sik = false
    /// Eski profil uyumu; okunmaz (üst hap artık `SohbetTemasi.baslik`).
    var baslik = false
    /// Eski profil uyumu; okunmaz.
    var durum = false
    /// Eski profil uyumu; okunmaz.
    var hizliKomutlar = false
    /// Sohbet ekranı teması (renkler, balonlar, yazı tipleri, çubuk stilleri). Eski profillerde yoktur → Claude.
    var sohbet: SohbetTemasi?
    var sohbetTemasi: SohbetTemasi {
        get { sohbet ?? .karma }
        set { sohbet = newValue }
    }

    /// Vurgu rengi şeridi; ilki varsayılan Claude turuncusu (seçilip geri dönülebilsin).
    static let paletler: [(String, String)] = [("Claude", "D97757"), ("Mercan", "F47863"), ("Lavanta", "9164E8"), ("Okyanus", "2588C9"), ("Orman", "258D70"), ("Kehribar", "BD801B"), ("Gül", "C4598D")]
    func dogrula() throws {
        guard surum == 1, renk.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) != nil,
              yaziOlcegi.isFinite, (0.9...1.4).contains(yaziOlcegi),
              kureOlcegi.isFinite, (0.7...1.2).contains(kureOlcegi), sohbet?.gecerli() ?? true else { throw ProfilHatasi.gecersiz }
    }
    static func coz(_ data: Data) throws -> Self {
        guard data.count <= 16000 else { throw ProfilHatasi.gecersiz }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.dogrula()
        return value
    }
    func veri() throws -> Data { try dogrula(); let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return try e.encode(self) }
    enum ProfilHatasi: LocalizedError { case gecersiz; var errorDescription: String? { "Bu görünüm profili desteklenmiyor veya geçersiz değerler içeriyor." } }
}

extension GorunumTercihleri {
    var renkSemasi: ColorScheme? { switch tema { case .sistem: nil; case .acik: .light; case .koyu: .dark } }
    var vurgu: Color { Color(hex: renk) }
    /// Metin için sabit parlaklık sınırları; çok açık/koyu özel renkler de okunur kalır.
    func metinRengi(_ koyu: Bool) -> Color {
        let ui = UIColor(vurgu); var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s, koyu ? 0.45 : 0.85), brightness: koyu ? 0.96 : min(b, 0.45))
    }
}
extension Color {
    init(hex: String) {
        let v = UInt32(hex, radix: 16) ?? 0xF47863
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var rgbHex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(min(1,max(0,r))*255), Int(min(1,max(0,g))*255), Int(min(1,max(0,b))*255))
    }
}

struct GorunumBelgesi: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
