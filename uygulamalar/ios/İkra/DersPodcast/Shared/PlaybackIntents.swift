import AppIntents
import Foundation

/// #19: Siri, Arkaya Dokunma ve Denetim Merkezi komutları (uygulama ve widget eklentisi birlikte derler).
/// Asıl iş uygulama sürecinde `PlaybackCommandCenter.handler` ile yürür; eklentide işleyici yoktur.
nonisolated enum PlaybackCommand: String, Sendable, CaseIterable {
    case bookmark, back15, nextChapter, resume
}

enum PlaybackCommandCenter {
    /// Uygulama açılırken `ListeningHooks.install()` kurar. Dönen metin Siri'nin söyleyeceği cevaptır.
    static var handler: ((PlaybackCommand) async -> String)?

    static func run(_ command: PlaybackCommand) async -> String {
        guard let handler else { return "Ders Podcast’i açıp yeniden dene." }
        return await handler(command)
    }
}

struct BookmarkPlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Podcast'te işaretle"
    static let description = IntentDescription("Çalan podcast'te şu anki yere yer imi koyar.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await PlaybackCommandCenter.run(.bookmark)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct SkipBack15Intent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "15 saniye geri"
    static let description = IntentDescription("Çalan podcast'i 15 saniye geri alır.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        _ = await PlaybackCommandCenter.run(.back15)
        return .result()
    }
}

struct NextChapterIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Sonraki konu"
    static let description = IntentDescription("Çalan podcast'te sonraki konuya geçer.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await PlaybackCommandCenter.run(.nextChapter)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// "Son podcast'imi çal": çalan yoksa son dinlenen bölümü kendisi yükler.
struct ResumePlaybackIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Podcast'i sürdür"
    static let description = IntentDescription("En son dinlediğin ders podcast'ini kaldığı yerden çalar.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await PlaybackCommandCenter.run(.resume)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
