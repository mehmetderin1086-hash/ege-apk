import AppIntents
import CoreSpotlight
import SwiftData
import UniformTypeIdentifiers

// #19/#43: bölüm varlığı (Kısayollar + Spotlight), "Bölümü çal", "Not al" ve "Dosyadan podcast üret".

nonisolated struct EpisodeEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Podcast bölümü"
    static let defaultQuery = EpisodeQuery()

    var id: UUID
    var title: String
    var subtitle: String
    var keywords: [String]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.title = title
        attributes.contentDescription = subtitle
        attributes.keywords = keywords
        return attributes
    }
}

extension EpisodeEntity {
    @MainActor init(_ episode: Episode) {
        let chapters = episode.timeline?.chapters.map(\.title) ?? []
        var parts = [episode.duration.minutesText]
        if let series = episode.seriesTitle { parts.insert("\(series) · \(episode.seriesIndex). bölüm", at: 0) }
        if !chapters.isEmpty { parts.append("\(chapters.count) konu") }
        self.init(id: episode.id, title: episode.title, subtitle: parts.joined(separator: " · "),
                  keywords: Array((chapters + episode.sourceNames).prefix(30)))
    }
}

nonisolated struct EpisodeQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [EpisodeEntity] {
        await MainActor.run { EpisodeQuery.ready().filter { identifiers.contains($0.id) } }
    }

    func entities(matching string: String) async throws -> [EpisodeEntity] {
        let needle = string.trimmingCharacters(in: .whitespaces).lowercased(with: Locale(identifier: "tr"))
        return await MainActor.run {
            EpisodeQuery.ready().filter { needle.isEmpty || $0.title.lowercased(with: Locale(identifier: "tr")).contains(needle) }
        }
    }

    func suggestedEntities() async throws -> [EpisodeEntity] {
        await MainActor.run { Array(EpisodeQuery.ready().prefix(20)) }
    }

    /// Hazır bölümler, en son dinlenen önce.
    @MainActor static func ready() -> [EpisodeEntity] {
        let ready = EpisodeStatus.ready.rawValue
        let episodes = (try? AppDataStore.container.mainContext.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.statusRaw == ready }))) ?? []
        return episodes.sorted { ($0.lastPlayedAt ?? $0.createdAt) > ($1.lastPlayedAt ?? $1.createdAt) }.map(EpisodeEntity.init)
    }
}

/// "Bölümü çal": uygulama arka planda çalar.
struct PlayEpisodeIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Bölümü çal"
    static let description = IntentDescription("Seçtiğin podcast bölümünü kaldığı yerden çalar.")
    static let openAppWhenRun = false

    @Parameter(title: "Bölüm", requestValueDialog: "Hangi bölümü çalayım?")
    var episode: EpisodeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$episode) bölümünü çal")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = episode.id
        let message = await MainActor.run { () -> String in
            let context = AppDataStore.container.mainContext
            guard let player = AppState.current?.player else { return "Ders Podcast’i açıp yeniden dene." }
            guard let target = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first,
                  target.status == .ready else { return "Bu bölüm bulunamadı." }
            player.play(target, at: nil, context: context)
            return player.episode?.id == id ? "\(target.title) çalıyor." : "Bölümün sesi bulunamadı."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Spotlight'taki bölüme dokununca uygulamada açar.
struct OpenEpisodeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Bölümü aç"
    static let description = IntentDescription("Podcast bölümünü uygulamada açar.")

    @Parameter(title: "Bölüm")
    var target: EpisodeEntity

    func perform() async throws -> some IntentResult {
        let id = target.id
        await MainActor.run { DeepLink.open(.episode(id, time: nil, play: false)) }
        return .result()
    }
}

/// "Not al": çalan ana metinli not (Siri notu ayrıca sorar; metin ifadeye girmez).
struct TakeNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Podcast'e not al"
    static let description = IntentDescription("Çalan podcast'te şu anki yere not ekler.")
    static let openAppWhenRun = false

    @Parameter(title: "Not", requestValueDialog: "Ne not alayım?")
    var text: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = await MainActor.run { () -> String in
            guard !note.isEmpty else { return "Not boş kaldı." }
            guard let mark = AppState.current?.player.addBookmark(kind: "note", note: note) else { return ListeningHooks.nothingPlaying }
            return "Not eklendi: \(mark.time.clockText)."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

/// Profil seçimi ifadede değil, listeden (DynamicOptionsProvider).
nonisolated struct PodcastProfileOptions: DynamicOptionsProvider {
    func results() async throws -> [String] { PodcastProfiles.all.map(\.name) }
}

/// "Dosyadan podcast üret": profil verildiyse doğrudan sıraya girer, verilmediyse yeni podcast ekranı dosyayla açılır.
/// Kısayol değil, yalnız intent (Kısayollar uygulamasında ve paylaş menüsü otomasyonlarında görünür).
struct GenerateFromFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Dosyadan podcast üret"
    static let description = IntentDescription("PDF, metin ya da fotoğraftan ders podcast'i üretir.")
    static let openAppWhenRun = true

    @Parameter(title: "Dosya", supportedContentTypes: [.pdf, .plainText, .rtf, .image, UTType("org.openxmlformats.wordprocessingml.document")!])
    var file: IntentFile

    @Parameter(title: "Profil", optionsProvider: PodcastProfileOptions())
    var profile: String?

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$file) dosyasından podcast üret") { \.$profile }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let folder = URL.temporaryDirectory.appending(path: "Intent-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: file.filename.isEmpty ? "Belge" : file.filename)
        try file.data.write(to: url)
        let profileName = profile
        let message = try await MainActor.run { () throws -> String in
            guard let app = AppState.current else { return "Ders Podcast’i açıp yeniden dene." }
            if let profileName, let settings = PodcastProfiles.settings(named: profileName) {
                let source = try DocumentLoader.load(url: url)
                app.generator.enqueue(sources: [source], settings: settings, context: AppDataStore.container.mainContext)
                app.selectedTab = .library
                return "\"\(source.name)\" \(profileName) profiliyle sıraya eklendi."
            }
            app.incomingFiles.append(url)
            return "Dosya yeni podcast ekranında açıldı."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
