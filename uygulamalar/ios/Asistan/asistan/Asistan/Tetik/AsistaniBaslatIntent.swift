import AppIntents

/// Kontrol Merkezi / Action Button / "Hey Siri, Asistan'ı başlat" → uygulamayı aç ve dinlemeye başla.
struct AsistaniBaslatIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'ı başlat"
    static let description = IntentDescription("Asistan'ı açar ve hemen dinlemeye başlar.")
    static let openAppWhenRun = true
    static let isDiscoverable = true

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://dinle")!))
    }
}
