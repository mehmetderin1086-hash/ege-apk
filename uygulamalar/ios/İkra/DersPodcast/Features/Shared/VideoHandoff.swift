import Foundation
import SwiftData

/// Soru Çöz ve konu videoları bir süre ayrı "Ders Video" uygulamasındaydı (10–16 Eki 2026); kayıtlar iki uygulamanın ortak
/// (App Group) klasörü üzerinden taşınırdı. İkra'da aynı klasör ters yönde kullanılır: eski Ders Video kabından Mac'teki
/// `devicectl` ile bu düzende bırakılan kayıtları `OkuImport` ilk açılışta alır. Klasör düzeni tek yerde dursun.
nonisolated enum VideoHandoff {
    static let group = "group.com.mehmetderin.dersvideo"
    /// Soru arşivinin SwiftData dosyası (yanındaki `-wal` ve `-shm` ile birlikte taşınır).
    static let store = "DersdasQuestions.store"
    static let storeSuffixes = ["", "-wal", "-shm"]
    /// Uygulama Desteği altındaki klasörler: soru görselleri, soru anlatımları, öğretmen sohbeti sesleri, konu videoları ve
    /// indirilmiş MEB kitapları (kitaplar Oku'da da kullanılmayı sürdürür; Ders Video yeniden indirmesin diye bırakılır).
    static let folders = ["QuestionAssets", "QuestionStudio", "QuestionTutor", "TopicVideos", "MEB", "QuestionMemory", "EngineData", "qs-yeniden-cizim"]
    /// Taşınan tercih anahtarlarının önekleri (son ikisi: kitaplarda kalınan sayfalar ve elle girilmiş sunucu adresi).
    static let preferencePrefixes = ["questions.", "qs.", "topic.", "meb.", "dev.apiBaseURL"]
    static let preferencesFile = "ayarlar.plist"
    /// Oku'nun kurulum kimliği: sunucu soru kaynaklarını (yüklenen sayfalar) bu kimliğe bağlar; Ders Video devralmazsa
    /// taşınan sorularda "Kaynak bulunamadı" hatası alır.
    static let installFile = "kurulum-kimligi"
    /// Soru Çöz'den ve konu videolarından Oku'nun defterine eklenmiş tekrar kartları ile yanlışlar (`Study`).
    static let studyFile = "calisma.json"
    /// Eski Ders Video'nun kendi SwiftData deposu (yalnız tekrar kartları ve yanlışlar); varsa kimliğe göre birleştirilir.
    static let studyStore = "DersVideo.store"
    /// Bu dosya varsa bırakılan tercihler buradakileri ezer (eski Ders Video'daki tercihler daha yenidir).
    static let preferencesOverride = "tercihler-ustun"
    /// En son yazılır: klasörün eksiksiz olduğunu gösterir. İçeriği bırakılma anıdır.
    static let marker = "hazir"

    static let folderName = "DersVideoAktarim"
    /// Aktarım klasörü: Mac'ten `devicectl` yalnız uygulamanın kendi kabına güvenilir yazabildiği için önce Uygulama Desteği'ne,
    /// yoksa App Group kabına bakılır. Uygulama içindeki kopya alındıktan sonra silinir (yer tutmasın).
    static var shared: URL? {
        let own = URL.applicationSupportDirectory.appending(path: folderName, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: own.appending(path: marker).path) { return own }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appending(path: folderName, directoryHint: .isDirectory)
    }

    /// Oku: eski kayıtları ortak klasöre bırakır (bir kez). Kayıtlar Oku'dan silinmez; aynı diskte kopya yer tutmaz (APFS).
    /// `from`/`to` testler içindir.
    private static let exporting = NSLock()

    @discardableResult
    static func export(from support: URL = .applicationSupportDirectory, to destination: URL? = shared,
                       preferences: UserDefaults = .standard, installID: UUID = InstallID.current) -> Bool {
        // Açılış görevi yeniden tetiklenirse iki bırakma aynı geçici klasörde çakışmasın.
        guard exporting.try() else { return false }
        defer { exporting.unlock() }
        let files = FileManager.default
        guard let destination else { return false }
        let identity = Data(installID.uuidString.lowercased().utf8)
        if files.fileExists(atPath: destination.appending(path: marker).path) {
            // Kimlik eklenmeden önce bırakılmış klasör: kimlik eklenir ve işaret yenilenir (Ders Video yeniden alır).
            guard !files.fileExists(atPath: destination.appending(path: installFile).path) else { return false }
            do {
                try identity.write(to: destination.appending(path: installFile), options: .atomic)
                try Data(Date.now.ISO8601Format().utf8).write(to: destination.appending(path: marker), options: .atomic)
                return true
            } catch { return false }
        }
        let stores = storeSuffixes.map { store + $0 }.filter { files.fileExists(atPath: support.appending(path: $0).path) }
        let present = folders.filter { files.fileExists(atPath: support.appending(path: $0).path) }
        guard !stores.isEmpty || !present.isEmpty else { return false }
        // Yarım kalmış bir deneme olabilir: geçici klasörde baştan kurulur, sonunda yerine alınır.
        let staging = destination.deletingLastPathComponent().appending(path: destination.lastPathComponent + ".tmp", directoryHint: .isDirectory)
        try? files.removeItem(at: staging)
        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            for name in stores + present { try files.copyItem(at: support.appending(path: name), to: staging.appending(path: name)) }
            let kept = preferences.dictionaryRepresentation().filter { key, _ in preferencePrefixes.contains { key.hasPrefix($0) } }
            try PropertyListSerialization.data(fromPropertyList: kept, format: .binary, options: 0).write(to: staging.appending(path: preferencesFile))
            try identity.write(to: staging.appending(path: installFile))
            try Data(Date.now.ISO8601Format().utf8).write(to: staging.appending(path: marker))
            try? files.removeItem(at: destination)
            try files.moveItem(at: staging, to: destination)
            return true
        } catch {
            try? files.removeItem(at: staging)
            return false
        }
    }

    // MARK: Tekrar kartları ve yanlışlar

    struct StudyCard: Codable, Equatable, Sendable {
        var id: UUID; var episodeID: UUID; var episodeTitle: String; var kindRaw: String; var front: String; var back: String; var sourcePage: Int?
        var ease: Double; var intervalDays: Int; var repetitions: Int; var lapses: Int; var due: Date; var lastReviewed: Date?; var createdAt: Date
    }
    struct StudyMistake: Codable, Equatable, Sendable {
        var id: UUID; var question: String; var myAnswer: String; var correctAnswer: String; var why: String; var source: String
        var episodeTitle: String; var sourcePage: Int?; var createdAt: Date; var reviewedCount: Int; var correctStreak: Int; var resolved: Bool
    }
    struct Study: Codable, Equatable, Sendable { var cards: [StudyCard] = []; var mistakes: [StudyMistake] = [] }
    static let questionCardPrefix = "Soru Çöz · ", questionMistakeSource = "question-solver"

    /// Oku: Soru Çöz ve konu videosu kaynaklı kartları ve yanlışları ortak klasöre bırakır (bir kez; kayıtlar Oku'da da kalır).
    /// Dosya klasöre sonradan eklenirse işaret yenilenir ki Ders Video yeniden alsın. `topicIDs`: konu videosu kimlikleri.
    @MainActor @discardableResult
    static func exportStudy(context: ModelContext, to destination: URL? = shared, topicIDs: Set<UUID>? = nil) -> Bool {
        let files = FileManager.default
        guard let destination, files.fileExists(atPath: destination.appending(path: marker).path),
              !files.fileExists(atPath: destination.appending(path: studyFile).path) else { return false }
        let topics = topicIDs ?? Set(((try? files.contentsOfDirectory(atPath: destination.appending(path: "TopicVideos").path)) ?? []).compactMap(UUID.init(uuidString:)))
        let cards = ((try? context.fetch(FetchDescriptor<ReviewCard>())) ?? []).filter { $0.episodeTitle.hasPrefix(questionCardPrefix) || topics.contains($0.episodeID) }
        let mistakes = ((try? context.fetch(FetchDescriptor<MistakeEntry>())) ?? []).filter { $0.source == questionMistakeSource }
        let study = Study(cards: cards.map { StudyCard(id: $0.id, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, kindRaw: $0.kindRaw, front: $0.front, back: $0.back, sourcePage: $0.sourcePage, ease: $0.ease, intervalDays: $0.intervalDays, repetitions: $0.repetitions, lapses: $0.lapses, due: $0.due, lastReviewed: $0.lastReviewed, createdAt: $0.createdAt) },
                          mistakes: mistakes.map { StudyMistake(id: $0.id, question: $0.question, myAnswer: $0.myAnswer, correctAnswer: $0.correctAnswer, why: $0.why, source: $0.source, episodeTitle: $0.episodeTitle, sourcePage: $0.sourcePage, createdAt: $0.createdAt, reviewedCount: $0.reviewedCount, correctStreak: $0.correctStreak, resolved: $0.resolved) })
        do {
            try JSONEncoder().encode(study).write(to: destination.appending(path: studyFile), options: .atomic)
            try Data(Date.now.ISO8601Format().utf8).write(to: destination.appending(path: marker), options: .atomic)
            return true
        } catch { return false }
    }
    /// Ders Video: bırakılan kartları ve yanlışları kendi defterine ekler; kimliği burada bulunan kayıt yinelenmez.
    @MainActor @discardableResult
    static func importStudy(from source: URL, context: ModelContext) -> (cards: Int, mistakes: Int) {
        guard let data = try? Data(contentsOf: source.appending(path: studyFile)), let study = try? JSONDecoder().decode(Study.self, from: data) else { return (0, 0) }
        return importStudy(study, context: context)
    }

    @MainActor @discardableResult
    static func importStudy(_ study: Study, context: ModelContext) -> (cards: Int, mistakes: Int) {
        let knownCards = Set(((try? context.fetch(FetchDescriptor<ReviewCard>())) ?? []).map(\.id))
        let knownMistakes = Set(((try? context.fetch(FetchDescriptor<MistakeEntry>())) ?? []).map(\.id))
        var added = (cards: 0, mistakes: 0)
        for item in study.cards where !knownCards.contains(item.id) {
            let card = ReviewCard(episodeID: item.episodeID, episodeTitle: item.episodeTitle, kind: ReviewCard.Kind(rawValue: item.kindRaw) ?? .flashcard, front: item.front, back: item.back, sourcePage: item.sourcePage)
            card.id = item.id; card.ease = item.ease; card.intervalDays = item.intervalDays; card.repetitions = item.repetitions; card.lapses = item.lapses
            card.due = item.due; card.lastReviewed = item.lastReviewed; card.createdAt = item.createdAt
            context.insert(card); added.cards += 1
        }
        for item in study.mistakes where !knownMistakes.contains(item.id) {
            let entry = MistakeEntry(question: item.question, myAnswer: item.myAnswer, correctAnswer: item.correctAnswer, why: item.why, source: item.source, episodeTitle: item.episodeTitle, sourcePage: item.sourcePage)
            entry.id = item.id; entry.createdAt = item.createdAt; entry.reviewedCount = item.reviewedCount; entry.correctStreak = item.correctStreak; entry.resolved = item.resolved
            context.insert(entry); added.mistakes += 1
        }
        try? context.save()
        return added
    }
}
