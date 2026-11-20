import AppIntents
import Foundation

/// P4.2 bas-konuş: uygulamayı öne getirmeden tek sesli komut alır, yanıtı sesli söyler (Action Button, kilit ekranı
/// kontrolü, Siri kısayolu). Bu dosya hem uygulamaya hem kontrol uzantısına (AsistanKontrol) derlenir.
/// AudioRecordingIntent kuralı: perform dönmeden bir Live Activity açılmış olmalı (`SesOturumu.basKonusBaslat` açar).
struct AsistanBasKonusIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Bas konuş"
    static let description = IntentDescription("Uygulamayı açmadan tek sesli komut alır ve yanıtı sesli söyler.")
    static let openAppWhenRun = false
    static let isDiscoverable = true

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        // Kanca yalnız uygulama sürecinde kurulur (AsistanApp.init). Uzantı sürecinde ya da uygulama hazır değilken
        // hata verilmez; uygulama açılıp olağan dinleme başlar (iOS 18.2+ `result(opensIntent:)` tek sonuç türü verir).
        if try await BasKonusKoprusu.baslat() { return .result() }
        return .result(opensIntent: OpenURLIntent(URL(string: "asistan://dinle")!))
    }
}

/// Uygulama süreci ile bas-konuş intent'i arasındaki köprü (IsKoprusu deseni). Kanca dinlemeyi başlatıp hemen döner;
/// komut bekleme, gönderim ve vazgeçme kancanın açtığı görevde sürer (intent zaman aşımına düşmesin).
@MainActor
enum BasKonusKoprusu {
    static var kanca: (@MainActor () async throws -> Void)?

    /// Kanca kuruluysa çalıştırır ve true döner; kurulmamışsa false (çağıran uygulamayı açar).
    static func baslat() async throws -> Bool {
        guard let k = kanca else { return false }
        try await k()
        return true
    }
}
