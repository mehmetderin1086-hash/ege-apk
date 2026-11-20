import AppIntents

/// Birleşik arama için Kestirmeler/Siri eylemi (yalnız uygulama hedefi).
/// AppShortcut listesi dolu (10/10): Kestirmeler uygulamasından ve "Hey Siri, <kestirme adı>" ile çalışır.
struct AsistandaAraIntent: AppIntent {
    static let title: LocalizedStringResource = "Asistan'da her yerde ara"
    static let description = IntentDescription("Tuval, sohbet, hafıza, dosya ve görevlerde arama ekranını açar.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "asistan://ara")!))
    }
}
