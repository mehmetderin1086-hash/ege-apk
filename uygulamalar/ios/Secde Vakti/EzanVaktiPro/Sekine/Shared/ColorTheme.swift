import Foundation

/// Okuma ve arayüz renk temaları — app ve widget arasında paylaşılır (accent/gold token'ları).
/// `zumrut` ücretsiz varsayılan. Seçim app-group defaults'ta saklanır.
enum ColorTheme: String, CaseIterable, Identifiable {
    case zumrut, geceMavisi, visne, colAltini, menekse, ayasofya, turkuaz, gulBahcesi, toprak, geceSiyahi, deniz, inci

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zumrut: return "Zümrüt"
        case .geceMavisi: return "Gece Mavisi"
        case .visne: return "Vişne"
        case .colAltini: return "Çöl Altını"
        case .ayasofya: return "Ayasofya"
        case .turkuaz: return "Turkuaz"
        case .gulBahcesi: return "Gül Bahçesi"
        case .toprak: return "Toprak"
        case .geceSiyahi: return "Gece Siyahı"
        case .deniz: return "Deniz"
        case .inci: return "İnci"
        case .menekse: return "Menekşe"
        }
    }

    var isPremium: Bool { false }

    /// accent (light, dark)
    var accent: (UInt, UInt) {
        switch self {
        case .zumrut:     return (0x1F6E5C, 0x4FB89E)
        case .geceMavisi: return (0x2A5C8F, 0x6FA8D8)
        case .visne:      return (0x8E2D3C, 0xC96A78)
        case .colAltini:  return (0x9C6B1F, 0xD7A24B)
        case .ayasofya: return (0x516431, 0xB9CB8A)
        case .turkuaz: return (0x06686F, 0x63CED0)
        case .gulBahcesi: return (0x903D65, 0xE89DBD)
        case .toprak: return (0x885136, 0xD8AD8B)
        case .geceSiyahi: return (0x3C4854, 0xBBD0E5)
        case .deniz: return (0x235B99, 0x93BFF4)
        case .inci: return (0x58596D, 0xC7C6E3)
        case .menekse:    return (0x6A4C93, 0xA88BD0)
        }
    }

    /// gold / ikincil vurgu (light, dark)
    var gold: (UInt, UInt) {
        switch self {
        case .zumrut:     return (0xB5893C, 0xD9B76A)
        case .geceMavisi: return (0xB08A4A, 0xE0C079)
        case .visne:      return (0xB5893C, 0xD9B76A)
        case .colAltini:  return (0x7A5B2A, 0xC9A15A)
        case .ayasofya: return (0x8B6829, 0xE5C786)
        case .turkuaz: return (0x8B6829, 0xE5C786)
        case .gulBahcesi: return (0x8B6829, 0xE5C786)
        case .toprak: return (0x8B6829, 0xE5C786)
        case .geceSiyahi: return (0x8B6829, 0xE5C786)
        case .deniz: return (0x8B6829, 0xE5C786)
        case .inci: return (0x8B6829, 0xE5C786)
        case .menekse:    return (0xB5893C, 0xD9B76A)
        }
    }

    /// Aktif satır/kart yumuşak zemini (light, dark).
    var accentSoft: (UInt, UInt) {
        switch self {
        case .zumrut:     return (0xEAF2EE, 0x24322B)
        case .geceMavisi: return (0xE7EEF6, 0x1E2A38)
        case .visne:      return (0xF4E9EB, 0x33232A)
        case .colAltini:  return (0xF3ECDD, 0x2E2718)
        case .ayasofya: return (0xF6F4E7, 0x171C13)
        case .turkuaz: return (0xEFF8F7, 0x102123)
        case .gulBahcesi: return (0xFCF1F5, 0x25141D)
        case .toprak: return (0xFAF2E9, 0x241B16)
        case .geceSiyahi: return (0xF0F3F6, 0x000000)
        case .deniz: return (0xEFF5FC, 0x111C2C)
        case .inci: return (0xFAFAFC, 0x1B1B24)
        case .menekse:    return (0xEFEAF6, 0x271E33)
        }
    }

    var background: (UInt, UInt) {
        switch self {
        case .ayasofya: return (0xF6F4E7, 0x171C13)
        case .turkuaz: return (0xEFF8F7, 0x102123)
        case .gulBahcesi: return (0xFCF1F5, 0x25141D)
        case .toprak: return (0xFAF2E9, 0x241B16)
        case .geceSiyahi: return (0xF0F3F6, 0x000000)
        case .deniz: return (0xEFF5FC, 0x111C2C)
        case .inci: return (0xFAFAFC, 0x1B1B24)
        case .zumrut: return (0xF4F7F1, 0x121C17)
        case .geceMavisi: return (0xF1F4FA, 0x111A29)
        case .visne: return (0xFBF1F2, 0x23161A)
        case .colAltini: return (0xFAF4E6, 0x241E12)
        case .menekse: return (0xF5F1FA, 0x1E1727)
        }
    }
    var hero: (UInt, UInt) {
        switch self {
        case .ayasofya: return (0x28381E, 0x3D512D)
        case .turkuaz: return (0x093E44, 0x13616A)
        case .gulBahcesi: return (0x4D1F39, 0x73314E)
        case .toprak: return (0x452B20, 0x6B4430)
        case .geceSiyahi: return (0x111821, 0x293545)
        case .deniz: return (0x122D50, 0x265185)
        case .inci: return (0x303043, 0x51536D)
        case .zumrut: return (0x123F35, 0x255F4E)
        case .geceMavisi: return (0x142E50, 0x2C527C)
        case .visne: return (0x4B1B2A, 0x762F44)
        case .colAltini: return (0x483313, 0x71531F)
        case .menekse: return (0x352342, 0x59406F)
        }
    }
    static var preferences: UserDefaults { UserDefaults(suiteName: AppGroup.identifier) ?? .standard }
    static var patternEnabled: Bool { preferences.object(forKey: "appearance.pattern") as? Bool ?? true }
    static var cardStyle: String { preferences.string(forKey: "appearance.cardStyle") ?? "soft" }
    static var highContrast: Bool { preferences.bool(forKey: "appearance.highContrast") }

    static var current: ColorTheme {
        let raw = (UserDefaults(suiteName: AppGroup.identifier) ?? .standard)
            .string(forKey: "settings.colorTheme") ?? ""
        return ColorTheme(rawValue: raw) ?? .zumrut
    }
}
