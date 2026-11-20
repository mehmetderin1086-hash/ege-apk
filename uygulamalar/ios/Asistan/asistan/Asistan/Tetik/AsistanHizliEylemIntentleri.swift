import AppIntents

/// Uygulama dışından açılan eylemler, uygulamanın kendi `asistan://` bağlantısına gider.
/// Böylece Kestirmeler ve Denetim Merkezi aynı davranışı paylaşır.

struct AsistanCanliBaslatIntent: AppIntent {
    static let title: LocalizedStringResource = "Canlı konuşmayı başlat"
    static let description = IntentDescription("Asistan'ı canlı sesli konuşma modunda açar.")
    static let openAppWhenRun = true
    static let isDiscoverable = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://live")!))
    }
}

struct AsistanAtolyeAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan Atölyesini aç"
    static let description = IntentDescription("Araştırma, yazı ve kod Atölyesini açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://atolye")!))
    }
}

struct AsistanIndirmeleriniAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan indirmelerini aç"
    static let description = IntentDescription("İndirilen dosya ve medya listesini açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://indirmeler")!))
    }
}

struct AsistanTelefonIslemleriniAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Telefon işlemlerini aç"
    static let description = IntentDescription("Uygulama, arama ve mesaj eylemlerini açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://telefon")!))
    }
}

struct AsistanDosyaDonusturIntent: AppIntent {
    static let title: LocalizedStringResource = "Dosya dönüştür"
    static let description = IntentDescription("Asistan dosya dönüştürücüsünü açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://donustur")!))
    }
}

struct AsistanArsivleriniAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan arşivini aç"
    static let description = IntentDescription("Sohbet ve yerel arşivi açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://arsiv")!))
    }
}

struct AsistanUretkenligiAcIntent: AppIntent {
    static let title: LocalizedStringResource = "Üretkenliği aç"
    static let description = IntentDescription("Dosya üretme, dönüştürme ve arşiv çalışma alanını açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://uretkenlik")!))
    }
}

struct AsistanaTaslakIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'a taslak gönder"
    static let description = IntentDescription("Soruyu Asistan'ın yazı alanına yerleştirir.")
    static let openAppWhenRun = true
    @Parameter(title: "Soru") var soru: String
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        var bilesen = URLComponents(string: "asistan://taslak")!
        bilesen.queryItems = [URLQueryItem(name: "metin", value: String(soru.prefix(8_000)))]
        return .result(opensIntent: OpenURLIntent(bilesen.url!))
    }
}
