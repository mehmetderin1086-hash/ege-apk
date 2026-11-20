import Charts
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

// MARK: - Öneri 5 + 14: istatistik, seri ve haftalık özet

struct StatsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GenerationCoordinator.self) private var generator
    @AppStorage(WeeklyRecap.enabledKey) private var autoRecap = false
    @State private var recapRunning = false
    @State private var recapError: String?

    private func makeRecap() async {
        recapRunning = true
        recapError = nil
        defer { recapRunning = false }
        do {
            let episode = try await WeeklyRecap.create(context: context, generator: generator)
            AppState.current?.pendingOpenEpisode = episode.id
            dismiss()
        } catch {
            recapError = error.localizedDescription
        }
    }
    @Query(sort: \ListeningDay.day, order: .reverse) private var days: [ListeningDay]
    @Query private var cards: [ReviewCard]
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Tile(value: "\(Self.streak(days))", title: "gün seri", symbol: "flame.fill", color: .orange)
                        Tile(value: minutes(today), title: "dk bugün", symbol: "clock.fill", color: .accentColor)
                        Tile(value: minutes(week), title: "dk bu hafta", symbol: "calendar", color: .green)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                Section("Son 14 gün") {
                    Chart(last14, id: \.day) { item in
                        BarMark(x: .value("Gün", item.label), y: .value("Dakika", item.minutes))
                            .foregroundStyle(Theme.gradient)
                    }
                    .frame(height: 160)
                }
                Section("Haftalık özet") {
                    LabeledContent("Bu hafta dinlenen bölüm", value: "\(weekEpisodes)")
                    LabeledContent("Bu hafta tekrar edilen kart", value: "\(cards.filter { ($0.lastReviewed ?? .distantPast) > weekStart }.count)")
                    LabeledContent("Zayıf kart", value: "\(cards.filter(\.isWeak).count)")
                    let weakest = cards.filter(\.isWeak).sorted { $0.lapses > $1.lapses }.prefix(3)
                    if !weakest.isEmpty {
                        Text("En çok zorlandıkların").font(.subheadline.bold())
                        ForEach(Array(weakest), id: \.id) { Text("• \($0.front)").font(.callout).lineLimit(2) }
                        Text("Tekrar ekranındaki \"Eksik kapatma podcast'i\" bu konulardan kısa bir bölüm üretir.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        Task { await makeRecap() }
                    } label: {
                        HStack { if recapRunning { ProgressView() }; Text("Haftalık tekrar podcast'i oluştur") }
                    }
                    .disabled(recapRunning)
                    Toggle("Her pazar otomatik oluştur", isOn: $autoRecap)
                    if let recapError { Text(recapError).font(.caption).foregroundStyle(.red) }
                } footer: {
                    Text("Bu hafta dinlediğin bölümlerin 10 dakikalık, bağlantıları kuran bir tekrar bölümü.")
                }
                Section("En çok dinlenenler") {
                    ForEach(topEpisodes, id: \.0.id) { episode, count in
                        LabeledContent(episode.title, value: "\(count) gün")
                    }
                }
            }
            .navigationTitle("İstatistik")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        }
    }

    private var weekStart: Date { Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? .now }
    private var today: Double { days.first { $0.day == ListeningDay.key() }?.seconds ?? 0 }
    private var week: Double {
        let keys = Set((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.map { ListeningDay.key(for: $0) })
        return days.filter { keys.contains($0.day) }.reduce(0) { $0 + $1.seconds }
    }
    private var weekEpisodes: Int {
        let keys = Set((0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }.map { ListeningDay.key(for: $0) })
        return Set(days.filter { keys.contains($0.day) }.flatMap(Self.ids)).count
    }
    private var last14: [(day: String, label: String, minutes: Double)] {
        (0..<14).reversed().compactMap { offset -> (String, String, Double)? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now) else { return nil }
            let key = ListeningDay.key(for: date)
            return (key, date.formatted(.dateTime.day().month(.defaultDigits)), (days.first { $0.day == key }?.seconds ?? 0) / 60)
        }.map { (day: $0.0, label: $0.1, minutes: $0.2) }
    }
    private var topEpisodes: [(Episode, Int)] {
        var counts: [UUID: Int] = [:]
        for day in days { for id in Self.ids(day) { counts[id, default: 0] += 1 } }
        return counts.sorted { $0.value > $1.value }.prefix(5).compactMap { id, count in episodes.first { $0.id == id }.map { ($0, count) } }
    }

    private func minutes(_ seconds: Double) -> String { "\(Int((seconds / 60).rounded()))" }

    static func ids(_ day: ListeningDay) -> [UUID] { day.episodesData.flatMap { try? JSONDecoder().decode([UUID].self, from: $0) } ?? [] }

    /// Bugünden (ya da bugün henüz dinlenmediyse dünden) geriye, en az 1 dk dinlenen ardışık günler.
    static func streak(_ days: [ListeningDay]) -> Int {
        let active = Set(days.filter { $0.seconds >= 60 }.map(\.day))
        var date = Date.now
        if !active.contains(ListeningDay.key(for: date)) { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date }
        var count = 0
        while active.contains(ListeningDay.key(for: date)) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        }
        return count
    }
}

private struct Tile: View {
    var value: String, title: String, symbol: String, color: Color
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

enum WeeklyDigest {
    /// Her pazar 19:00'da haftalık özet hatırlatması (öneri 14).
    static func ensureScheduled() {
        Task {
            let center = UNUserNotificationCenter.current()
            guard await NotificationGate.request(center, options: [.alert, .sound]) else { return }
            guard !(await center.pendingNotificationRequests()).contains(where: { $0.identifier == "weekly-digest" }) else { return }
            let content = UNMutableNotificationContent()
            content.title = "Haftalık özetin hazır"
            content.body = "Bu hafta en çok zorlandığın konular ve dinleme süren seni bekliyor. Eksik kapatma podcast'i için dokun."
            content.userInfo = ["route": "stats"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 19, minute: 0, weekday: 1), repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "weekly-digest", content: content, trigger: trigger))
        }
    }
}

// MARK: - Öneri 20: belge kütüphanesi

struct DocumentLibraryView: View {
    /// Seçim modu: yeni podcast ekranından açılınca seçilen belgeler kaynak olarak eklenir.
    var onPick: (([SourceDocument]) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SourceDocument.lastUsedAt, order: .reverse) private var documents: [SourceDocument]
    @Query private var episodes: [Episode]
    @Query private var queued: [QueuedRequest]
    @State private var selection: Set<UUID> = []
    @State private var preview: URL?
    @State private var pendingDelete: SourceDocument?

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView("Belge yok", systemImage: "tray",
                                           description: Text("Podcast oluşturduğun belgeler burada saklanır ve yeniden kullanılabilir."))
                } else {
                    let episodeDocs = episodes.map { $0.sourceDocumentIDs ?? [] }
                    let queuedDocs = queued.map(\.documentIDs)
                    let directory = DocumentStore.directory
                    List {
                        ForEach(documents) { doc in
                            let usage = DocumentUsage.count(doc.id, episodeDocs: episodeDocs, queuedDocs: queuedDocs)
                            let fileURL = directory.appending(path: doc.fileName)
                            let missing = doc.fileName.isEmpty || !FileManager.default.fileExists(atPath: fileURL.path)
                            Button {
                                if onPick != nil {
                                    if selection.contains(doc.id) { selection.remove(doc.id) } else { selection.insert(doc.id) }
                                } else if !missing {
                                    preview = DocumentPreview.makeCopy(of: fileURL, name: doc.name)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    if onPick != nil {
                                        Image(systemName: selection.contains(doc.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint)
                                    }
                                    Image(systemName: doc.kindRaw == "pdf" ? "doc.richtext" : doc.kindRaw == "image" ? "photo" : "doc.text")
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.name).foregroundStyle(.primary).lineLimit(2).truncationMode(.middle)
                                            .multilineTextAlignment(.leading)
                                        Text("\(doc.kindRaw == "pdf" ? "\(doc.pageCount) sayfa · " : "")\(doc.lastUsedAt.formatted(date: .abbreviated, time: .omitted))\(DocumentUsage.suffix(usage))")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                        if missing {
                                            Label("Dosya bulunamadı", systemImage: "exclamationmark.triangle.fill")
                                                .font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                            .accessibilityAddTraits(onPick != nil && selection.contains(doc.id) ? .isSelected : [])
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Rol `.destructive` değil: satır onaydan önce listeden düşmesin.
                                Button { pendingDelete = doc } label: { Label("Sil", systemImage: "trash") }
                                    .tint(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Belgelerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                if let onPick {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Ekle (\(selection.count))") {
                            onPick(documents.filter { selection.contains($0.id) })
                            dismiss()
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .quickLookPreview($preview)
            .confirmationDialog("Belge silinsin mi?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible, presenting: pendingDelete) { doc in
                Button("Sil", role: .destructive) {
                    selection.remove(doc.id)
                    DocumentLibrary.delete(doc, context: context)
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { doc in
                let usage = DocumentUsage.count(doc.id, episodeDocs: episodes.map { $0.sourceDocumentIDs ?? [] }, queuedDocs: queued.map(\.documentIDs))
                Text(DocumentUsage.deleteMessage(episodes: usage.episodes, queued: usage.queued))
            }
        }
    }
}

/// Belgenin kaç bölümün kaynağı olduğu ve sıradaki kaç isteğin onu beklediği (satır alt bilgisi ve silme onayı).
nonisolated enum DocumentUsage {
    static func count(_ id: UUID, episodeDocs: [[UUID]], queuedDocs: [[UUID]]) -> (episodes: Int, queued: Int) {
        (episodeDocs.filter { $0.contains(id) }.count, queuedDocs.filter { $0.contains(id) }.count)
    }

    /// Satır alt bilgisine eklenen kullanım (" · 3 bölümde · sırada 1 istek"); kullanılmıyorsa boş.
    static func suffix(_ usage: (episodes: Int, queued: Int)) -> String {
        (usage.episodes > 0 ? " · \(usage.episodes) bölümde" : "") + (usage.queued > 0 ? " · sırada \(usage.queued) istek" : "")
    }

    static func deleteMessage(episodes: Int, queued: Int) -> String {
        var parts: [String] = []
        if episodes > 0 { parts.append("Bu belge \(episodes) bölümün kaynağı; silersen kaynak sayfası açılamaz ve şekil çıkarılamaz.") }
        if queued > 0 { parts.append("Sıradaki \(queued) istek bu belgeyi bekliyor.") }
        parts.append(parts.isEmpty ? "Belge dosyası bu cihazdan kalıcı olarak silinir." : "Silme geri alınamaz.")
        return parts.joined(separator: " ")
    }
}

/// Önizleme belgenin geçici kopyasıyla açılır: Quick Look başlıkta dosya adını gösterir (saklanan ad bir kimliktir)
/// ve önizlemede yapılan işaretleme kaynak belgeye yazılamaz.
nonisolated enum DocumentPreview {
    /// Görünen addan güvenli dosya adı; uzantı saklanan dosyanınkidir (Quick Look türü uzantıdan anlar).
    static func fileName(name: String, storedFileName: String) -> String {
        let ext = (storedFileName as NSString).pathExtension
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines).map { (c: Character) -> Character in
            c == "/" || c == ":" || c == "\\" || c.isNewline ? "-" : c
        }
        var base = String(cleaned.prefix(80))
        if base.isEmpty || base.allSatisfy({ $0 == "." }) { base = "Belge" }
        if ext.isEmpty || base.lowercased().hasSuffix(".\(ext.lowercased())") { return base }
        return "\(base).\(ext)"
    }

    static func makeCopy(of source: URL, name: String) -> URL? {
        let fm = FileManager.default
        let folder = URL.temporaryDirectory.appending(path: "DocPreview", directoryHint: .isDirectory)
        try? fm.removeItem(at: folder)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appending(path: fileName(name: name, storedFileName: source.lastPathComponent))
            try fm.copyItem(at: source, to: target)
            return target
        } catch {
            return nil
        }
    }
}

// MARK: - Öneri 29: tahmini maliyet

enum CostEstimate {
    /// Chirp HD ≈ 30 $/1M karakter. Sunucu sesleri (XTTS), Apple, Supertonic, Piper, Edge ve HF ücretsiz; senaryo abonelik
    /// üzerinden (Claude) yazılır, ek ücret sayılmaz.
    static func monthly(_ episodes: [Episode]) -> (total: Double, lines: [(String, Double)]) {
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
        var chirp = 0.0, minutes = 0.0
        for episode in episodes where episode.createdAt >= start {
            minutes += episode.duration / 60
            if episode.settings?.engine.voicedBy == .chirp { chirp += Double(episode.script?.totalCharacters ?? 0) / 1_000_000 * 30 }
        }
        return (chirp, [("Chirp seslendirme", chirp), ("Bu ay üretilen süre (dk)", minutes)])
    }
}

// MARK: - Öneri 30: yedekleme / geri yükleme (#49: manifest v2, artımlı Mac yedeğiyle ortak dosya listesi)

/// #49: UserDefaults değeri (tür bilgisiyle). Eski `preferences` (yalnız Data) ayrıca korunur.
nonisolated enum PrefValue: Codable, Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case data(Data)

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "string": self = .string(try c.decode(String.self, forKey: .value))
        case "bool": self = .bool(try c.decode(Bool.self, forKey: .value))
        case "int": self = .int(try c.decode(Int.self, forKey: .value))
        case "double": self = .double(try c.decode(Double.self, forKey: .value))
        case "data": self = .data(try c.decode(Data.self, forKey: .value))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Bilinmeyen tercih türü: \(other)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .string(v): try c.encode("string", forKey: .type); try c.encode(v, forKey: .value)
        case let .bool(v): try c.encode("bool", forKey: .type); try c.encode(v, forKey: .value)
        case let .int(v): try c.encode("int", forKey: .type); try c.encode(v, forKey: .value)
        case let .double(v): try c.encode("double", forKey: .type); try c.encode(v, forKey: .value)
        case let .data(v): try c.encode("data", forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    /// UserDefaults nesnesinden (desteklenmeyen tür: nil). NSNumber'da Bool ile sayı ayrımı CF türüyle yapılır.
    static func from(_ object: Any) -> PrefValue? {
        switch object {
        case let s as String: return .string(s)
        case let d as Data: return .data(d)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        default: return nil
        }
    }

    var object: Any {
        switch self {
        case let .string(v): v
        case let .bool(v): v
        case let .int(v): v
        case let .double(v): v
        case let .data(v): v
        }
    }
}

nonisolated struct BackupManifest: Codable {
    struct EpisodeDTO: Codable {
        var id: UUID, createdAt: Date, title: String, sourceNames: [String], statusRaw: String
        var scriptData: Data, settingsData: Data, timelineData: Data?, studyData: Data?
        var duration: Double, lastPosition: Double, isFinished: Bool, lastPlayedAt: Date?
        var seriesID: UUID?, seriesTitle: String?, seriesIndex: Int
        var conceptsData: Data?, visualsData: Data?, rating: Int?, ratingNote: String?
        var sourceDocumentIDs: [UUID]?, slidesData: Data?, verifyData: Data?
        var audioFileName: String?
        var deckData: Data? = nil
        var deckModel: String? = nil
        // v2 (eski yedeklerde yok)
        var courseID: UUID? = nil
        var parentEpisodeID: UUID? = nil
        var derivedKind: String? = nil
        var sourceLessonID: UUID? = nil
        var sourceVideoTime: Double? = nil
        var generationStatsData: Data? = nil
        var audioIssuesData: Data? = nil
        var topicsData: Data? = nil
        var audioRevision: Int? = nil
    }
    struct BookmarkDTO: Codable {
        var id: UUID, episodeID: UUID, episodeTitle: String, time: Double, text: String, note: String, createdAt: Date, audioFileName: String?
        var kind: String? = nil
        var chapterIndex: Int? = nil
    }
    struct CardDTO: Codable {
        var id: UUID, episodeID: UUID, episodeTitle: String, kindRaw: String, front: String, back: String, sourcePage: Int?
        var ease: Double, intervalDays: Int, repetitions: Int, lapses: Int, due: Date, lastReviewed: Date?
        // v2
        var createdAt: Date? = nil
        var clipLessonID: UUID? = nil
        var clipStart: Double? = nil
        var clipEnd: Double? = nil
        var stability: Double? = nil
        var memoryDifficulty: Double? = nil
        var lastLapseAt: Date? = nil
        var episodeTime: Double? = nil
        var figureID: String? = nil
        var origin: String? = nil
        var chapterIndex: Int? = nil
        /// Oku kitap notundan üretilen kartın kaynağı; eski yedeklerde yok.
        var sourceBookID: String? = nil
        var learningSourceJSON: String? = nil
    }
    struct DocumentDTO: Codable {
        var id: UUID, name: String, kindRaw: String, fileName: String, pageCount: Int, addedAt: Date
        /// Eski yedeklerde yok (geri yüklemede `addedAt` kullanılır).
        var lastUsedAt: Date? = nil
    }
    struct CourseDTO: Codable { var id: UUID, name: String, colorHex: String, createdAt: Date }
    struct LessonDTO: Codable { var id: UUID, courseID: UUID, weekday: Int, startMinute: Int, durationMinutes: Int, room: String }
    struct AssignmentDTO: Codable { var id: UUID, courseID: UUID?, title: String, kindRaw: String, dueDate: Date, isDone: Bool, note: String, episodeID: UUID?, createdAt: Date }
    struct SessionDTO: Codable { var id: UUID, startedAt: Date, seconds: Double, courseID: UUID?, episodeID: UUID?, kind: String, completed: Bool }
    struct MistakeDTO: Codable {
        var id: UUID, question: String, myAnswer: String, correctAnswer: String, why: String, source: String, episodeID: UUID?, episodeTitle: String, sourcePage: Int?, courseID: UUID?, createdAt: Date, reviewedCount: Int, resolved: Bool
        // v2
        var correctStreak: Int? = nil
        var videoTime: Double? = nil
        var podcastTime: Double? = nil
        var chapterIndex: Int? = nil
    }
    struct NoteDTO: Codable { var id: UUID, title: String, cues: String, notes: String, summary: String, episodeID: UUID?, courseID: UUID?, createdAt: Date, updatedAt: Date }
    var courses: [CourseDTO]? = nil
    var lessons: [LessonDTO]? = nil
    var assignments: [AssignmentDTO]? = nil
    var sessions: [SessionDTO]? = nil
    var mistakes: [MistakeDTO]? = nil
    var cornellNotes: [NoteDTO]? = nil
    struct VideoLessonDTO: Codable {
        var id: UUID, url: String, videoID: String, title: String, channel: String, duration: Double, thumbnailURL: String?
        var language: String, source: String, createdAt: Date, lastPosition: Double, transcriptData: Data?, episodeIDs: [UUID], favorite: Bool
        /// Eski yedeklerde yok (gömülebilir, ses indirilmemiş sayılır).
        var embeddable: Bool? = nil, audioFileName: String? = nil
        // v2
        var courseID: UUID? = nil
        var tags: [String]? = nil
        /// İzleme ilerlemesi (eski yedeklerde yok: geri sarma noktası yok, hız ayarlanmamış, süre 0 sayılır).
        var rewindTimes: [Double]? = nil
        var playbackRate: Double? = nil
        var watchedSeconds: Double? = nil
    }
    /// YouTube Ders Stüdyosu dersleri (eski yedeklerde yok); kareler "Videos/<id>/" klasöründe.
    var videoLessons: [VideoLessonDTO]? = nil
    /// Koç ayarları (hedef sınav, telaffuz sözlüğü, günlük dakika): UserDefaults anahtar → değer verisi.
    var preferences: [String: Data]? = nil
    static let preferenceKeys = [StudyPlan.key, Pronunciations.key]

    // MARK: v2 (#49): eski yedeklerde yok; hepsi Optional.
    struct ListeningDayDTO: Codable { var day: String, seconds: Double, episodesData: Data? }
    struct TimedNoteDTO: Codable { var id: UUID, lessonID: UUID, time: Double, text: String, photoFileName: String?, createdAt: Date }
    struct FollowedChannelDTO: Codable {
        var id: UUID, url: String, title: String, lastChecked: Date?, knownVideoIDs: [String], autoProcess: Bool, courseID: UUID?, createdAt: Date
    }
    struct RecallAttemptDTO: Codable {
        var id: UUID, createdAt: Date, episodeID: UUID?, episodeTitle: String, chapterIndex: Int?, source: String, question: String
        var choices: [String], chosenIndex: Int?, correctIndex: Int?, answerText: String?, isCorrect: Bool?, score: Double?
        var confidence: Int?, responseSeconds: Double?, daysSinceListen: Int?, conceptKey: String?, cardID: UUID?
    }
    struct EpisodeProbeDTO: Codable {
        var id: UUID, episodeID: UUID?, episodeTitle: String, dueDate: Date, stage: Int, kindRaw: String, createdAt: Date, completedAt: Date?, score: Double?
    }
    struct LiveExchangeDTO: Codable {
        var id: UUID, episodeID: UUID?, episodeTitle: String, createdAt: Date, question: String, answer: String, chapterIndex: Int?, time: Double?, mode: String
    }
    var listeningDays: [ListeningDayDTO]? = nil
    var timedNotes: [TimedNoteDTO]? = nil
    var followedChannels: [FollowedChannelDTO]? = nil
    var recallAttempts: [RecallAttemptDTO]? = nil
    var episodeProbes: [EpisodeProbeDTO]? = nil
    var liveExchanges: [LiveExchangeDTO]? = nil
    /// Türü korunan tercihler (string/bool/int/double/data).
    var preferenceValues: [String: PrefValue]? = nil
    /// Yedeklenen tercih anahtarları; ayrıca `preferencePrefixes` ile başlayan tüm anahtarlar. Yalnız `PrefValue` türleri
    /// taşınır (dizi ve sözlük değerler girmez). Cihaza özgü olanlar (`feed.*` kimlik listeleri, `backup.*`, `dev.*`,
    /// `player.queue`, `youtube.pending*`) bilerek dışarıdadır.
    static let preferenceValueKeys = ["lastSettings", "podcast.profiles", "listening.mode", "pronunciations.v1", "sound.identity",
                                      "podcast.previewBeforeVoicing", StudyPlan.key, "feed.autoPublish",
                                      "lesson.termDictionary", "player.rate", "player.skipSilence", "weeklyRecap.auto",
                                      "autoStudyPack", "autoVerify", "showSlides", "soundDesign", "studyPlan.notify",
                                      "qs.learning.families.v1", "qs.learning.prerequisites.v1", "qs.learning.playback",
                                      "qs.learning.intervalExperiment.enabled", "qs.learning.intervalExperiment.history.v1",
                                      "tutor.writtenExam.draft.v1"]
    static let preferencePrefixes = ["coach.", "tools.", "deck.", "questions.", "reading."]

    static let currentVersion = 2
    var version = BackupManifest.currentVersion
    var createdAt = Date.now
    var episodes: [EpisodeDTO]
    var bookmarks: [BookmarkDTO]
    var cards: [CardDTO]
    var documents: [DocumentDTO]

    static func decode(_ data: Data) throws -> BackupManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupManifest.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Yedeklenecek tercihler (yalnız desteklenen türler).
    static func collectPreferenceValues(_ defaults: UserDefaults = .standard) -> [String: PrefValue] {
        let all = defaults.dictionaryRepresentation()
        var out: [String: PrefValue] = [:]
        for (key, value) in all where preferenceValueKeys.contains(key) || preferencePrefixes.contains(where: { key.hasPrefix($0) }) {
            if let v = PrefValue.from(value) { out[key] = v }
        }
        return out
    }

    /// Yalnız cihazda henüz olmayan tercihleri yazar (mevcut ayarların üzerine yazılmaz).
    static func applyPreferenceValues(_ values: [String: PrefValue], to defaults: UserDefaults = .standard) {
        for (key, value) in values where defaults.object(forKey: key) == nil {
            defaults.set(value.object, forKey: key)
        }
    }
}

/// SwiftUI fileWrapper'ı arka plandan çağırır: tür ana aktöre bağlı olmamalı.
nonisolated struct BackupDocument: FileDocument, @unchecked Sendable {
    static let readableContentTypes: [UTType] = [.folder]
    let wrapper: FileWrapper
    init(wrapper: FileWrapper) { self.wrapper = wrapper }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

enum Backup {
    /// Yedek düzenindeki bir dosya: `path` yedek köküne göre (ör. "Audio/<id>.m4a"), `url` cihazdaki kaynağı.
    nonisolated struct Entry: Hashable, Sendable {
        var path: String
        var url: URL
    }

    /// Yedek düzeninin üst klasörleri (boş olsalar da klasör yedeğinde bulunur).
    static let folders = ["Audio", "EpisodeFiles", "Documents", "VoiceNotes", "Videos", "Tools", "IkraSupport", "QuestionArchive"]

    /// SwiftData ve tercihlerin anlık görüntüsü (dosyalar hariç).
    static func manifest(context: ModelContext) throws -> BackupManifest {
        let episodes = try context.fetch(FetchDescriptor<Episode>()).filter { $0.status == .ready }
        var manifest = BackupManifest(
            episodes: episodes.map { e in
                .init(id: e.id, createdAt: e.createdAt, title: e.title, sourceNames: e.sourceNames, statusRaw: e.statusRaw,
                      scriptData: e.scriptData, settingsData: e.settingsData, timelineData: e.timelineData, studyData: e.studyData,
                      duration: e.duration, lastPosition: e.lastPosition, isFinished: e.isFinished, lastPlayedAt: e.lastPlayedAt,
                      seriesID: e.seriesID, seriesTitle: e.seriesTitle, seriesIndex: e.seriesIndex, conceptsData: e.conceptsData,
                      visualsData: e.visualsData, rating: e.rating, ratingNote: e.ratingNote, sourceDocumentIDs: e.sourceDocumentIDs,
                      slidesData: e.slidesData, verifyData: e.verifyData, audioFileName: e.audioFileName,
                      deckData: e.deckData, deckModel: e.deckModel,
                      courseID: e.courseID, parentEpisodeID: e.parentEpisodeID, derivedKind: e.derivedKind,
                      sourceLessonID: e.sourceLessonID, sourceVideoTime: e.sourceVideoTime,
                      generationStatsData: e.generationStatsData, audioIssuesData: e.audioIssuesData,
                      topicsData: e.topicsData, audioRevision: e.audioRevision)
            },
            bookmarks: try context.fetch(FetchDescriptor<Bookmark>()).map {
                .init(id: $0.id, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, time: $0.time, text: $0.text,
                      note: $0.note, createdAt: $0.createdAt, audioFileName: $0.audioFileName, kind: $0.kind, chapterIndex: $0.chapterIndex)
            },
            cards: try context.fetch(FetchDescriptor<ReviewCard>()).map {
                .init(id: $0.id, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, kindRaw: $0.kindRaw, front: $0.front, back: $0.back,
                      sourcePage: $0.sourcePage, ease: $0.ease, intervalDays: $0.intervalDays, repetitions: $0.repetitions,
                      lapses: $0.lapses, due: $0.due, lastReviewed: $0.lastReviewed,
                      createdAt: $0.createdAt, clipLessonID: $0.clipLessonID, clipStart: $0.clipStart, clipEnd: $0.clipEnd,
                      stability: $0.stability, memoryDifficulty: $0.memoryDifficulty, lastLapseAt: $0.lastLapseAt,
                      episodeTime: $0.episodeTime, figureID: $0.figureID, origin: $0.origin, chapterIndex: $0.chapterIndex,
                      sourceBookID: $0.sourceBookID, learningSourceJSON: $0.learningSourceJSON)
            },
            documents: try context.fetch(FetchDescriptor<SourceDocument>()).map {
                .init(id: $0.id, name: $0.name, kindRaw: $0.kindRaw, fileName: $0.fileName, pageCount: $0.pageCount, addedAt: $0.addedAt,
                      lastUsedAt: $0.lastUsedAt)
            })
        // Oku verileri
        manifest.courses = try context.fetch(FetchDescriptor<Course>()).map { .init(id: $0.id, name: $0.name, colorHex: $0.colorHex, createdAt: $0.createdAt) }
        manifest.lessons = try context.fetch(FetchDescriptor<Lesson>()).map { .init(id: $0.id, courseID: $0.courseID, weekday: $0.weekday, startMinute: $0.startMinute, durationMinutes: $0.durationMinutes, room: $0.room) }
        manifest.assignments = try context.fetch(FetchDescriptor<Assignment>()).map { .init(id: $0.id, courseID: $0.courseID, title: $0.title, kindRaw: $0.kindRaw, dueDate: $0.dueDate, isDone: $0.isDone, note: $0.note, episodeID: $0.episodeID, createdAt: $0.createdAt) }
        manifest.sessions = try context.fetch(FetchDescriptor<StudySession>()).map { .init(id: $0.id, startedAt: $0.startedAt, seconds: $0.seconds, courseID: $0.courseID, episodeID: $0.episodeID, kind: $0.kind, completed: $0.completed) }
        manifest.mistakes = try context.fetch(FetchDescriptor<MistakeEntry>()).map {
            .init(id: $0.id, question: $0.question, myAnswer: $0.myAnswer, correctAnswer: $0.correctAnswer, why: $0.why, source: $0.source,
                  episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, sourcePage: $0.sourcePage, courseID: $0.courseID, createdAt: $0.createdAt,
                  reviewedCount: $0.reviewedCount, resolved: $0.resolved, correctStreak: $0.correctStreak, videoTime: $0.videoTime,
                  podcastTime: $0.podcastTime, chapterIndex: $0.chapterIndex)
        }
        manifest.preferences = Dictionary(uniqueKeysWithValues: BackupManifest.preferenceKeys.compactMap { k in
            UserDefaults.standard.data(forKey: k).map { (k, $0) }
        } + [("coach.dailyGoalMinutes", Data(String(UserDefaults.standard.integer(forKey: "coach.dailyGoalMinutes")).utf8))])
        manifest.cornellNotes = try context.fetch(FetchDescriptor<CornellNote>()).map { .init(id: $0.id, title: $0.title, cues: $0.cues, notes: $0.notes, summary: $0.summary, episodeID: $0.episodeID, courseID: $0.courseID, createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
        manifest.videoLessons = try context.fetch(FetchDescriptor<VideoLesson>()).map {
            .init(id: $0.id, url: $0.url, videoID: $0.videoID, title: $0.title, channel: $0.channel, duration: $0.duration, thumbnailURL: $0.thumbnailURL,
                  language: $0.language, source: $0.source, createdAt: $0.createdAt, lastPosition: $0.lastPosition, transcriptData: $0.transcriptData,
                  episodeIDs: $0.episodeIDs, favorite: $0.favorite, embeddable: $0.embeddable, audioFileName: $0.audioFileName,
                  courseID: $0.courseID, tags: $0.tags,
                  rewindTimes: $0.rewindTimes, playbackRate: $0.playbackRate, watchedSeconds: $0.watchedSeconds)
        }
        // v2
        manifest.listeningDays = try context.fetch(FetchDescriptor<ListeningDay>()).map { .init(day: $0.day, seconds: $0.seconds, episodesData: $0.episodesData) }
        manifest.timedNotes = try context.fetch(FetchDescriptor<TimedNote>()).map {
            .init(id: $0.id, lessonID: $0.lessonID, time: $0.time, text: $0.text, photoFileName: $0.photoFileName, createdAt: $0.createdAt)
        }
        manifest.followedChannels = try context.fetch(FetchDescriptor<FollowedChannel>()).map {
            .init(id: $0.id, url: $0.url, title: $0.title, lastChecked: $0.lastChecked, knownVideoIDs: $0.knownVideoIDs,
                  autoProcess: $0.autoProcess, courseID: $0.courseID, createdAt: $0.createdAt)
        }
        manifest.recallAttempts = try context.fetch(FetchDescriptor<RecallAttempt>()).map {
            .init(id: $0.id, createdAt: $0.createdAt, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, chapterIndex: $0.chapterIndex,
                  source: $0.source, question: $0.question, choices: $0.choices, chosenIndex: $0.chosenIndex, correctIndex: $0.correctIndex,
                  answerText: $0.answerText, isCorrect: $0.isCorrect, score: $0.score, confidence: $0.confidence,
                  responseSeconds: $0.responseSeconds, daysSinceListen: $0.daysSinceListen, conceptKey: $0.conceptKey, cardID: $0.cardID)
        }
        manifest.episodeProbes = try context.fetch(FetchDescriptor<EpisodeProbe>()).map {
            .init(id: $0.id, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, dueDate: $0.dueDate, stage: $0.stage,
                  kindRaw: $0.kindRaw, createdAt: $0.createdAt, completedAt: $0.completedAt, score: $0.score)
        }
        manifest.liveExchanges = try context.fetch(FetchDescriptor<LiveExchange>()).map {
            .init(id: $0.id, episodeID: $0.episodeID, episodeTitle: $0.episodeTitle, createdAt: $0.createdAt, question: $0.question,
                  answer: $0.answer, chapterIndex: $0.chapterIndex, time: $0.time, mode: $0.mode)
        }
        manifest.preferenceValues = BackupManifest.collectPreferenceValues()
        return manifest
    }

    /// Yedeğe giren dosyalar (manifest hariç). Klasör yedeği ve artımlı Mac yedeği aynı listeyi kullanır.
    /// Sahne masterları (SceneMasters) ve sahne WAV'ları girmez: bölüm klasöründen yalnız json/png/jpg alınır.
    static func entries(context: ModelContext) throws -> [Entry] {
        entries(from: try entrySources(context: context))
    }

    /// Yedek dosyası adayı: tek dosya (varsa girer) ya da uzantıya göre taranacak klasör (`prefix/<dosya adı>`).
    nonisolated enum EntrySource: Hashable, Sendable {
        case file(Entry)
        case folder(prefix: String, directory: URL, extensions: Set<String>)
        case tree(prefix: String, directory: URL, extensions: Set<String>)
        case support(name: String, root: URL)
    }

    /// Ana aktörde yalnız kayıtlardan yol üretir (dosya sistemine dokunmaz); tarama `entries(from:)` ile arka planda yapılabilir.
    static func entrySources(context: ModelContext) throws -> [EntrySource] {
        var out: [EntrySource] = []
        let episodes = try context.fetch(FetchDescriptor<Episode>()).filter { $0.status == .ready }
        for e in episodes {
            if let url = e.audioURL { out.append(.file(Entry(path: "Audio/\(e.id.uuidString).m4a", url: url))) }
        }
        // Bölüm klasöründeki küçük dosyalar: kesilmiş şekiller, şekil eşlemesi, etiketler, deste görselleri.
        for e in episodes {
            out.append(.folder(prefix: "EpisodeFiles/\(e.id.uuidString)", directory: e.directory, extensions: ["json", "png", "jpg"]))
        }
        for d in try context.fetch(FetchDescriptor<SourceDocument>()) where !d.fileName.isEmpty {
            out.append(.file(Entry(path: "Documents/\(d.fileName)", url: DocumentStore.directory.appending(path: d.fileName))))
        }
        var seenNotes = Set<String>()
        for b in try context.fetch(FetchDescriptor<Bookmark>()) {
            guard let name = b.audioFileName, seenNotes.insert(name).inserted else { continue }
            out.append(.file(Entry(path: "VoiceNotes/\(name)", url: VoiceNotes.url(name))))
        }
        // YouTube derslerinin kareleri (frame_<id>.jpg), not fotoğrafları, küçük JSON dosyaları ve indirilen ses (audio.m4a).
        for lesson in try context.fetch(FetchDescriptor<VideoLesson>()) {
            out.append(.folder(prefix: "Videos/\(lesson.id.uuidString)", directory: VideoFiles.root.appending(path: lesson.id.uuidString),
                               extensions: ["json", "png", "jpg", "m4a"]))
        }
        // Araç kutusu (deneme, not, alışkanlık, günlük…) ve tahta çizimi.
        out.append(.folder(prefix: "Tools", directory: JSONStoreLocation.defaultDirectory, extensions: ["json", "drawing"]))
        for name in QSBackupSupport.directories {
            out.append(.support(name: name, root: .applicationSupportDirectory))
        }
        let questions = QuestionStore.shared
        if !questions.entries.isEmpty || !questions.sources.isEmpty {
            let snapshot = try questions.exportArchive()
            out.append(.file(Entry(path: "QuestionArchive/questions.dersvideo", url: snapshot)))
        }
        return out
    }

    /// Adayları dosya sisteminde çözer: olmayan dosya atlanır, klasör adına göre sıralı taranır.
    nonisolated static func entries(from sources: [EntrySource]) -> [Entry] {
        let fm = FileManager.default
        var out: [Entry] = []
        for source in sources {
            switch source {
            case let .file(entry):
                if fm.fileExists(atPath: entry.url.path) { out.append(entry) }
            case let .folder(prefix, directory, extensions):
                let files = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                    .filter { extensions.contains($0.pathExtension.lowercased()) }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                out += files.map { Entry(path: "\(prefix)/\($0.lastPathComponent)", url: $0) }
            case let .tree(prefix, directory, extensions):
                out += QSBackupSupport.files(under: directory, extensions: extensions).map {
                    Entry(path: prefix + "/" + $0.path, url: $0.url)
                }
            case let .support(name, root):
                out += QSBackupSupport.exportFiles(name: name, root: root).map { Entry(path: "IkraSupport/" + name + "/" + $0.path, url: $0.url) }
            }
        }
        return out
    }

    static func make(context: ModelContext) throws -> FileWrapper {
        let manifest = try manifest(context: context)
        var tree = WrapperTree()
        tree.add("manifest.json", FileWrapper(regularFileWithContents: try manifest.encoded()))
        for folder in folders { tree.ensureFolder(folder) }
        for entry in try entries(context: context) {
            if entry.path.hasPrefix("QuestionArchive/") || entry.path.hasPrefix("IkraSupport/") {
                tree.add(entry.path, try FileWrapper(url: entry.url))
            } else if let w = try? FileWrapper(url: entry.url) { tree.add(entry.path, w) }
        }
        let root = tree.wrapper()
        root.preferredFilename = "DersPodcast-yedek-\(Date.now.formatted(.iso8601.year().month().day()))"
        return root
    }

    /// Göreli yollardan iç içe FileWrapper ağacı.
    private struct WrapperTree {
        var files: [String: FileWrapper] = [:]
        var folders: [String: WrapperTree] = [:]

        mutating func ensureFolder(_ name: String) { if folders[name] == nil { folders[name] = WrapperTree() } }

        mutating func add(_ path: String, _ wrapper: FileWrapper) {
            let parts = path.split(separator: "/").map(String.init)
            guard let first = parts.first else { return }
            if parts.count == 1 { files[first] = wrapper; return }
            var child = folders[first] ?? WrapperTree()
            child.add(parts.dropFirst().joined(separator: "/"), wrapper)
            folders[first] = child
        }

        func wrapper() -> FileWrapper {
            var children = files
            for (name, tree) in folders { children[name] = tree.wrapper() }
            return FileWrapper(directoryWithFileWrappers: children)
        }
    }

    /// Yedek klasörünü içe aktarır; aynı kimlikli kayıtlar atlanır. Eklenen bölüm sayısını döndürür; sesi yedekte
    /// bulunmayan bölüm varsa (kalan her şey eklendikten sonra) `RestoreWarning` fırlatır.
    static func restore(from folder: URL, context: ModelContext) throws -> Int {
        let summary = try restoreDetailed(from: folder, context: context)
        if summary.skippedEpisodes > 0 { throw RestoreWarning(added: summary.episodes, skipped: summary.skippedEpisodes) }
        return summary.episodes
    }

    /// Geri yüklemede eklenen kayıtlar, tür tür (cihazda bölümler varken yalnız kart ya da not eklenmişse de sonuç görünsün).
    nonisolated struct RestoreSummary: Equatable, Sendable {
        var episodes = 0, cards = 0, bookmarks = 0, notes = 0, lessons = 0, documents = 0, toolItems = 0
        /// Ders programı, ödev, çalışma kaydı, hata defteri, dinleme günü, hatırlama denemesi gibi diğer kayıtlar.
        var other = 0
        var questions = 0, supportFiles = 0, supportConflicts = 0
        var supportNotes: [String] = []
        var cardSourceUpdates = 0, cardSourceConflicts = 0
        /// Ses dosyası yedekte bulunmadığı için eklenmeyen bölümler.
        var skippedEpisodes = 0

        var text: String {
            let counts = [(episodes, "bölüm"), (cards, "kart"), (bookmarks, "bölüm notu"), (notes, "Cornell notu"), (lessons, "video dersi"),
                          (documents, "belge"), (toolItems, "araç kaydı"), (questions, "soru"), (supportFiles, "belge destek dosyası"), (cardSourceUpdates, "kart kaynak bağlantısı"), (other, "diğer kayıt")]
            let parts = counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
            let skipped = skippedEpisodes > 0 ? "\(skippedEpisodes) bölümün ses dosyası yedekte bulunamadığı için atlandı." : nil
            let conflicts = supportConflicts > 0 ? "\(supportConflicts) farklı yerel destek dosyası veya koleksiyonu korundu; gelen kopya yedekte duruyor." : nil
            let cardConflicts = cardSourceConflicts > 0 ? "\(cardSourceConflicts) kartın içeriği veya kaynak bilgisi farklıydı; yerel kart korundu, eski kaynak bağlanmadı." : nil
            if parts.isEmpty {
                let notes = [skipped, conflicts, cardConflicts].compactMap { $0 } + supportNotes
                return notes.isEmpty ? "Yeni kayıt yok; yedektekilerin hepsi cihazda." : (["Yeni kayıt eklenmedi."] + notes).joined(separator: " ")
            }
            return (["\(parts.joined(separator: ", ")) eklendi."] + [skipped, conflicts, cardConflicts].compactMap { $0 } + supportNotes).joined(separator: " ")
        }
    }

    nonisolated struct PartialRestoreFailure: LocalizedError {
        var summary: RestoreSummary
        var completed: [String]
        var stage: String
        var reason: String
        var errorDescription: String? {
            let state = completed.isEmpty ? "Kitaplık veritabanı eklemeleri geri alındı. Daha önce kopyalanan dosyalar veya tercihler korunmuş olabilir."
                : "Tamamlanan bölümler: " + completed.joined(separator: ", ") + ". " + summary.text
            return "Geri yükleme \(stage) aşamasında tamamlanamadı: \(reason). \(state) Kalanlar için aynı yedek yeniden seçilebilir; mevcut kayıtlar korunur."
        }
    }

    /// `restore`'un ayrıntılı hâli: sesi bulunmayan bölüm hata sayılmaz, `skippedEpisodes` olarak döner.
    /// Ana aktörde await'siz çalışır (yetim klasör temizliğiyle iç içe geçmesin).
    static func restoreDetailed(from folder: URL, context: ModelContext, questionStore: QuestionStore? = nil, supportRoot: URL = .applicationSupportDirectory) throws -> RestoreSummary {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let manifest = try BackupManifest.decode(Data(contentsOf: folder.appending(path: "manifest.json")))
        let questionFile = folder.appending(path: "QuestionArchive/questions.dersvideo")
        // Validate the entire question archive before restoring any library records.
        let questionStage = URL.temporaryDirectory.appending(path: "backup-question-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: questionStage) }
        var questionHeader: QSArchiveFile.Header?
        var questionTarget: QuestionStore?
        if FileManager.default.fileExists(atPath: questionFile.path) {
            let header = try QSArchiveFile.stage(questionFile, at: questionStage)
            let target = questionStore ?? QuestionStore.shared
            try target.validateArchiveInstall(sources: header.sources, entries: header.entries, stagedAssets: questionStage, assets: header.assets)
            questionHeader = header; questionTarget = target
        }
        let supportPlan = try QSBackupSupport.preflight(from: folder.appending(path: "IkraSupport"), to: supportRoot)
        let existingEpisodes = Set(try context.fetch(FetchDescriptor<Episode>()).map(\.id))
        var summary = RestoreSummary()
        var added = 0
        var skipped = 0
        var completed: [String] = [], stage = "kitaplık"
        do {
        for dto in manifest.episodes where !existingEpisodes.contains(dto.id) {
            guard let script = try? JSONDecoder().decode(PodcastScript.self, from: dto.scriptData),
                  let settings = try? JSONDecoder().decode(PodcastSettings.self, from: dto.settingsData) else { continue }
            let e = Episode(id: dto.id, script: script, settings: settings, sourceNames: dto.sourceNames, jobToken: "")
            e.createdAt = dto.createdAt
            e.title = dto.title
            e.statusRaw = dto.statusRaw
            e.settingsData = dto.settingsData
            e.timelineData = dto.timelineData
            e.studyData = dto.studyData
            e.duration = dto.duration
            e.lastPosition = dto.lastPosition
            e.isFinished = dto.isFinished
            e.lastPlayedAt = dto.lastPlayedAt
            e.seriesID = dto.seriesID
            e.seriesTitle = dto.seriesTitle
            e.seriesIndex = dto.seriesIndex
            e.conceptsData = dto.conceptsData
            e.visualsData = dto.visualsData
            e.rating = dto.rating
            e.ratingNote = dto.ratingNote
            e.sourceDocumentIDs = dto.sourceDocumentIDs
            e.slidesData = dto.slidesData
            e.verifyData = dto.verifyData
            e.deckData = dto.deckData
            e.deckModel = dto.deckModel
            e.courseID = dto.courseID
            e.parentEpisodeID = dto.parentEpisodeID
            e.derivedKind = dto.derivedKind
            e.sourceLessonID = dto.sourceLessonID
            e.sourceVideoTime = dto.sourceVideoTime
            e.generationStatsData = dto.generationStatsData
            e.audioIssuesData = dto.audioIssuesData
            e.topicsData = dto.topicsData
            e.audioRevision = dto.audioRevision ?? 0
            e.jobToken = nil
            e.scenesDone = e.scenesTotal
            let source = folder.appending(path: "Audio/\(dto.id.uuidString).m4a")
            let target = EpisodeFiles.directory(for: dto.id).appending(path: "podcast.m4a")
            try? FileManager.default.removeItem(at: target)
            do {
                try FileManager.default.copyItem(at: source, to: target)
            } catch {
                // Sesi olmayan bölümü "hazır" diye ekleme: oynatılamaz.
                EpisodeFiles.remove(episode: dto.id)
                skipped += 1
                continue
            }
            e.audioFileName = "podcast.m4a"
            // Şekiller, deste görselleri, eşlemeler (yeni yedeklerde).
            let extraDir = folder.appending(path: "EpisodeFiles/\(dto.id.uuidString)")
            for f in (try? FileManager.default.contentsOfDirectory(at: extraDir, includingPropertiesForKeys: nil)) ?? [] {
                let dest = EpisodeFiles.directory(for: dto.id).appending(path: f.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: f, to: dest)
            }
            context.insert(e)
            added += 1
        }
        let existingDocs = Set(try context.fetch(FetchDescriptor<SourceDocument>()).map(\.id))
        for d in manifest.documents where !existingDocs.contains(d.id) {
            // Dosyası gelmeyen belge kaydı eklenmez (Belgelerim'de açılamayan belge oluşmasın); kimlik cihazda olmadığı için
            // dosyayı içeren bir yedekten sonra yine geri yüklenebilir. Boş ad klasörün kendisini gösterir: dosya sayılmaz.
            guard !d.fileName.isEmpty else { continue }
            let source = folder.appending(path: "Documents/\(d.fileName)")
            let target = DocumentStore.directory.appending(path: d.fileName)
            try? FileManager.default.copyItem(at: source, to: target)
            guard FileManager.default.fileExists(atPath: target.path) else { continue }
            let doc = SourceDocument(name: d.name, kind: d.kindRaw, fileName: d.fileName, pageCount: d.pageCount)
            doc.id = d.id
            doc.addedAt = d.addedAt
            doc.lastUsedAt = d.lastUsedAt ?? d.addedAt
            context.insert(doc)
            summary.documents += 1
        }
        let existingMarks = Set(try context.fetch(FetchDescriptor<Bookmark>()).map(\.id))
        let episodesByID = Dictionary(try context.fetch(FetchDescriptor<Episode>()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for b in manifest.bookmarks where !existingMarks.contains(b.id) {
            guard let episode = episodesByID[b.episodeID] else { continue }
            let mark = Bookmark(episode: episode, time: b.time, text: b.text, note: b.note)
            mark.id = b.id
            mark.createdAt = b.createdAt
            mark.kind = b.kind ?? "note"
            mark.chapterIndex = b.chapterIndex
            if let name = b.audioFileName, !name.isEmpty {
                let target = VoiceNotes.url(name)
                try? FileManager.default.copyItem(at: folder.appending(path: "VoiceNotes/\(name)"), to: target)
                // Sesli not yalnız dosyası gerçekten geldiyse kayda geçer (çalmayan sesli not düğmesi oluşmasın).
                if FileManager.default.fileExists(atPath: target.path) { mark.audioFileName = name }
            }
            context.insert(mark)
            summary.bookmarks += 1
        }
        let existingCards = Dictionary(try context.fetch(FetchDescriptor<ReviewCard>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for c in manifest.cards {
            if let current = existingCards[c.id] {
                switch restoreCardSource(c, into: current) {
                case .updated: summary.cardSourceUpdates += 1
                case .conflict: summary.cardSourceConflicts += 1
                case .unchanged: break
                }
                continue
            }
            let card = ReviewCard(episodeID: c.episodeID, episodeTitle: c.episodeTitle, kind: ReviewCard.Kind(rawValue: c.kindRaw) ?? .flashcard,
                                  front: c.front, back: c.back, sourcePage: c.sourcePage)
            card.id = c.id
            card.ease = c.ease
            card.intervalDays = c.intervalDays
            card.repetitions = c.repetitions
            card.lapses = c.lapses
            card.due = c.due
            card.lastReviewed = c.lastReviewed
            if let v = c.createdAt { card.createdAt = v }
            card.clipLessonID = c.clipLessonID
            card.clipStart = c.clipStart ?? 0
            card.clipEnd = c.clipEnd ?? 0
            card.stability = c.stability ?? 0
            card.memoryDifficulty = c.memoryDifficulty ?? 0
            card.lastLapseAt = c.lastLapseAt
            card.episodeTime = c.episodeTime
            card.figureID = c.figureID
            card.origin = c.origin
            card.chapterIndex = c.chapterIndex
            card.sourceBookID = c.sourceBookID
            card.learningSourceJSON = c.learningSourceJSON
            context.insert(card)
            summary.cards += 1
        }
        // Koç ayarları: yalnızca cihazda henüz yoksa (mevcut ayarların üzerine yazılmaz).
        for (k, v) in manifest.preferences ?? [:] {
            if k == "coach.dailyGoalMinutes" {
                if UserDefaults.standard.object(forKey: k) == nil, let m = Int(String(decoding: v, as: UTF8.self)), m > 0 { UserDefaults.standard.set(m, forKey: k) }
            } else if UserDefaults.standard.data(forKey: k) == nil {
                UserDefaults.standard.set(v, forKey: k)
            }
        }
        BackupManifest.applyPreferenceValues(manifest.preferenceValues ?? [:])
        // Oku verileri (eski yedeklerde yok)
        let courseIDs = Set(try context.fetch(FetchDescriptor<Course>()).map(\.id))
        for c in manifest.courses ?? [] where !courseIDs.contains(c.id) { let m = Course(name: c.name, colorHex: c.colorHex); m.id = c.id; m.createdAt = c.createdAt; context.insert(m); summary.other += 1 }
        let lessonIDs = Set(try context.fetch(FetchDescriptor<Lesson>()).map(\.id))
        for l in manifest.lessons ?? [] where !lessonIDs.contains(l.id) { let m = Lesson(courseID: l.courseID, weekday: l.weekday, startMinute: l.startMinute, durationMinutes: l.durationMinutes, room: l.room); m.id = l.id; context.insert(m); summary.other += 1 }
        let assignmentIDs = Set(try context.fetch(FetchDescriptor<Assignment>()).map(\.id))
        for a in manifest.assignments ?? [] where !assignmentIDs.contains(a.id) {
            let m = Assignment(title: a.title, kind: Assignment.Kind(rawValue: a.kindRaw) ?? .homework, dueDate: a.dueDate, courseID: a.courseID, episodeID: a.episodeID, note: a.note)
            m.id = a.id; m.isDone = a.isDone; m.createdAt = a.createdAt; context.insert(m)
            summary.other += 1
        }
        let sessionIDs = Set(try context.fetch(FetchDescriptor<StudySession>()).map(\.id))
        for s in manifest.sessions ?? [] where !sessionIDs.contains(s.id) { let m = StudySession(startedAt: s.startedAt, seconds: s.seconds, courseID: s.courseID, episodeID: s.episodeID, kind: s.kind, completed: s.completed); m.id = s.id; context.insert(m); summary.other += 1 }
        let mistakeIDs = Set(try context.fetch(FetchDescriptor<MistakeEntry>()).map(\.id))
        for e in manifest.mistakes ?? [] where !mistakeIDs.contains(e.id) {
            let m = MistakeEntry(question: e.question, myAnswer: e.myAnswer, correctAnswer: e.correctAnswer, why: e.why, source: e.source, episodeID: e.episodeID, episodeTitle: e.episodeTitle, sourcePage: e.sourcePage, courseID: e.courseID)
            m.id = e.id; m.createdAt = e.createdAt; m.reviewedCount = e.reviewedCount; m.resolved = e.resolved
            m.correctStreak = e.correctStreak ?? 0; m.videoTime = e.videoTime; m.podcastTime = e.podcastTime; m.chapterIndex = e.chapterIndex
            context.insert(m)
            summary.other += 1
        }
        let noteIDs = Set(try context.fetch(FetchDescriptor<CornellNote>()).map(\.id))
        for n in manifest.cornellNotes ?? [] where !noteIDs.contains(n.id) {
            let m = CornellNote(title: n.title, episodeID: n.episodeID, courseID: n.courseID)
            m.id = n.id; m.cues = n.cues; m.notes = n.notes; m.summary = n.summary; m.createdAt = n.createdAt; m.updatedAt = n.updatedAt; context.insert(m)
            summary.notes += 1
        }
        let videoIDs = Set(try context.fetch(FetchDescriptor<VideoLesson>()).map(\.id))
        for v in manifest.videoLessons ?? [] where !videoIDs.contains(v.id) {
            let m = VideoLesson(url: v.url)
            m.id = v.id; m.videoID = v.videoID; m.title = v.title; m.channel = v.channel; m.duration = v.duration; m.thumbnailURL = v.thumbnailURL
            m.language = v.language; m.source = v.source; m.createdAt = v.createdAt; m.lastPosition = v.lastPosition
            m.transcriptData = v.transcriptData; m.episodeIDs = v.episodeIDs; m.favorite = v.favorite
            m.embeddable = v.embeddable ?? true
            m.courseID = v.courseID
            m.tags = v.tags ?? []
            m.rewindTimes = v.rewindTimes ?? []
            m.playbackRate = v.playbackRate ?? 0
            m.watchedSeconds = v.watchedSeconds ?? 0
            let sourceDir = folder.appending(path: "Videos/\(v.id.uuidString)")
            for f in (try? FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)) ?? [] {
                // Ses (m4a) iCloud yedeğinden yeniden hariç tutulur.
                VideoFiles.restoreFile(f, to: VideoFiles.directory(for: v.id).appending(path: f.lastPathComponent))
            }
            // Ses yalnızca dosyası gerçekten geldiyse kayda geçer.
            if let name = v.audioFileName, FileManager.default.fileExists(atPath: VideoFiles.audioURL(lesson: v.id, name: name).path) {
                m.audioFileName = name
            }
            context.insert(m)
            summary.lessons += 1
        }
        // v2: dinleme günleri, video notları, takip edilen kanallar, öğrenme kayıtları.
        let dayKeys = Set(try context.fetch(FetchDescriptor<ListeningDay>()).map(\.day))
        for d in manifest.listeningDays ?? [] where !dayKeys.contains(d.day) {
            let m = ListeningDay(day: d.day); m.seconds = d.seconds; m.episodesData = d.episodesData; context.insert(m)
            summary.other += 1
        }
        let timedIDs = Set(try context.fetch(FetchDescriptor<TimedNote>()).map(\.id))
        for n in manifest.timedNotes ?? [] where !timedIDs.contains(n.id) {
            let m = TimedNote(lessonID: n.lessonID, time: n.time, text: n.text)
            m.id = n.id; m.createdAt = n.createdAt
            if let name = n.photoFileName,
               FileManager.default.fileExists(atPath: VideoFiles.root.appending(path: n.lessonID.uuidString).appending(path: VideoFiles.safeAudioName(name)).path) {
                m.photoFileName = name
            }
            context.insert(m)
            summary.other += 1
        }
        let channelIDs = Set(try context.fetch(FetchDescriptor<FollowedChannel>()).map(\.id))
        for c in manifest.followedChannels ?? [] where !channelIDs.contains(c.id) {
            let m = FollowedChannel(url: c.url, title: c.title)
            m.id = c.id; m.lastChecked = c.lastChecked; m.knownVideoIDs = c.knownVideoIDs; m.autoProcess = c.autoProcess
            m.courseID = c.courseID; m.createdAt = c.createdAt
            context.insert(m)
            summary.other += 1
        }
        let attemptIDs = Set(try context.fetch(FetchDescriptor<RecallAttempt>()).map(\.id))
        for a in manifest.recallAttempts ?? [] where !attemptIDs.contains(a.id) {
            let m = RecallAttempt(source: a.source, question: a.question, episodeID: a.episodeID, episodeTitle: a.episodeTitle, chapterIndex: a.chapterIndex)
            m.id = a.id; m.createdAt = a.createdAt; m.choices = a.choices; m.chosenIndex = a.chosenIndex; m.correctIndex = a.correctIndex
            m.answerText = a.answerText; m.isCorrect = a.isCorrect; m.score = a.score; m.confidence = a.confidence
            m.responseSeconds = a.responseSeconds; m.daysSinceListen = a.daysSinceListen; m.conceptKey = a.conceptKey; m.cardID = a.cardID
            context.insert(m)
            summary.other += 1
        }
        let probeIDs = Set(try context.fetch(FetchDescriptor<EpisodeProbe>()).map(\.id))
        for p in manifest.episodeProbes ?? [] where !probeIDs.contains(p.id) {
            guard let episodeID = p.episodeID else { continue }
            let m = EpisodeProbe(episodeID: episodeID, episodeTitle: p.episodeTitle, dueDate: p.dueDate, stage: p.stage, kind: p.kindRaw)
            m.id = p.id; m.createdAt = p.createdAt; m.completedAt = p.completedAt; m.score = p.score
            context.insert(m)
            summary.other += 1
        }
        let exchangeIDs = Set(try context.fetch(FetchDescriptor<LiveExchange>()).map(\.id))
        for x in manifest.liveExchanges ?? [] where !exchangeIDs.contains(x.id) {
            let m = LiveExchange(episodeID: x.episodeID, episodeTitle: x.episodeTitle, question: x.question, answer: x.answer,
                                 chapterIndex: x.chapterIndex, time: x.time, mode: x.mode)
            m.id = x.id; m.createdAt = x.createdAt
            context.insert(m)
            summary.other += 1
        }
        // Yedekten dönen seri bölümü, sırası sonradan kapatılmış bir serideki numarayla çakışabilir; sıraları yeniden diz.
        if added > 0 { SeriesOps.closeGaps(context: context) }
        try context.save()
        completed.append("kitaplık")
        summary.episodes = added
        summary.skippedEpisodes = skipped
        stage = "araç kayıtları"
        summary.toolItems = restoreToolsAndNotify(from: folder.appending(path: "Tools"))
        completed.append("araç kayıtları")
        if let header = questionHeader, let store = questionTarget {
            stage = "soru arşivi"
            let count = store.entries.count
            try store.installArchive(sources: header.sources, entries: header.entries, stagedAssets: questionStage, assets: header.assets)
            summary.questions = store.entries.count - count
            completed.append("soru arşivi")
        }
        stage = "belge destek dosyaları"
        do {
            let support = try QSBackupSupport.apply(supportPlan, root: supportRoot)
            summary.supportFiles = support.added; summary.supportConflicts = support.conflicts; summary.supportNotes = support.notes
            if support.added > 0 { NotificationCenter.default.post(name: JSONStoreLocation.restored, object: nil) }
        } catch let partial as QSBackupSupport.PartialFailure {
            summary.supportFiles = partial.restored.added; summary.supportConflicts = partial.restored.conflicts; summary.supportNotes = partial.restored.notes
            if partial.restored.added > 0 { NotificationCenter.default.post(name: JSONStoreLocation.restored, object: nil) }
            throw partial
        }
        if supportRoot.standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL,
           supportPlan.additions.contains(where: { $0.destination.lastPathComponent == "library.json" && $0.destination.deletingLastPathComponent().lastPathComponent == "ReadyScenarioImports" }) {
            try QSReadyCenter.shared.reloadImportedLibraryAfterRestore()
        }
        return summary
        } catch {
            if completed.isEmpty { context.rollback(); summary = RestoreSummary() }
            throw PartialRestoreFailure(summary: summary, completed: completed, stage: stage, reason: error.localizedDescription)
        }
    }

    // MARK: Araç kutusu dosyaları

    enum CardSourceRestore { case unchanged, updated, conflict }
    /// Fill missing provenance only; never attach an old source to locally edited content or alter its review schedule.
    static func restoreCardSource(_ incoming: BackupManifest.CardDTO, into card: ReviewCard) -> CardSourceRestore {
        guard let raw = incoming.learningSourceJSON else { return .unchanged }
        guard raw.utf8.count <= 32_000, let data = raw.data(using: .utf8),
              let link = try? JSONDecoder().decode(LearningSourceLink.self, from: data),
              link.bookID.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil,
              ![".", ".."].contains(link.bookID), link.firstPage > 0, link.lastPage >= link.firstPage, link.lastPage <= 100_000,
              link.version.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
              link.noteID.map({ UUID(uuidString: $0) != nil }) != false,
              incoming.sourceBookID.map({ $0 == link.bookID }) != false,
              let page = incoming.sourcePage, (link.firstPage...link.lastPage).contains(page),
              card.id == incoming.id, card.front == incoming.front, card.back == incoming.back,
              card.kindRaw == incoming.kindRaw, card.episodeID == incoming.episodeID,
              card.episodeTitle == incoming.episodeTitle, card.sourcePage == incoming.sourcePage,
              card.sourceBookID.map({ $0 == link.bookID }) != false else { return .conflict }
        if card.learningSourceJSON != nil { return card.learningSource == link ? .unchanged : .conflict }
        card.learningSourceJSON = raw
        return .updated
    }

    /// Geri yükleme araç kutusu dosyalarına yazdıysa yayımlanır. Açık `JSONStore` listeyi bellekte tutar ve her değişiklikte
    /// dosyanın tamamını yazar: bu haberle dosyadan yeniden okumazsa ilk değişikliği yedekten eklenenleri silerdi.
    /// Ad `JSONStore` ile ortak sözleşmedir; değiştirilmez.
    nonisolated static let toolsRestored = Notification.Name("dersdas.tools.restored")

    /// `restoreTools` ve ardından haber. Ana aktörde, yazmayla aynı adımda (await'siz) yayımlanır: araya açık bir deponun
    /// kaydı giremez. Kayıt eklenmediyse (hiçbir depo değişmedi) yayımlanmaz.
    @discardableResult
    static func restoreToolsAndNotify(from source: URL, to target: URL = JSONStoreLocation.defaultDirectory,
                                      center: NotificationCenter = .default) -> Int {
        let added = restoreTools(from: source, to: target)
        if added > 0 { center.post(name: toolsRestored, object: nil) }
        return added
    }

    /// Araç kutusu dosyalarını geri yükler. Cihazda olmayan dosya kopyalanır; var olan bilinen `.json` deposuna yalnız yedekte
    /// olup cihazda olmayan kimlikler eklenir (cihazdaki kayıtlar değişmez). Birleşim, deponun kendi türüyle sınanmadan
    /// yazılmaz (`toolMergeIsSafe`); tanınmayan depo, tahta çizimi (`.drawing`) ve kenara alınmış bozuk dosyalar
    /// (`*.bozuk-*.json`) varsa atlanır. Dönen değer eklenen kayıt sayısıdır (kopyalanan dosyada öğe sayısı).
    /// Yalnız dosyaya yazar; açık depolara haberi `restoreToolsAndNotify` verir.
    @discardableResult
    nonisolated static func restoreTools(from source: URL, to target: URL = JSONStoreLocation.defaultDirectory) -> Int {
        let fm = FileManager.default
        var added = 0
        let files = ((try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ext == "json" || ext == "drawing" else { continue }
            let destination = target.appending(path: file.lastPathComponent)
            if !fm.fileExists(atPath: destination.path) {
                if file.lastPathComponent == "book-study.json" {
                    guard let data = try? Data(contentsOf: file), (try? BookStudyStore.decode(data)) != nil else { continue }
                }
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                guard (try? fm.copyItem(at: file, to: destination)) != nil else { continue }
                added += toolRecordCount(at: file)
            } else if file.lastPathComponent == "book-study.json" {
                guard let existing = try? Data(contentsOf: destination), let incoming = try? Data(contentsOf: file),
                      let merged = try? BookStudyStore.merge(existing: existing, incoming: incoming), merged.changed > 0,
                      toolMergeIsSafe(store: "book-study", existing: existing, merged: merged.data) == true,
                      (try? merged.data.write(to: destination, options: .atomic)) != nil else { continue }
                added += merged.changed
            } else if ext == "json", !file.lastPathComponent.contains(".bozuk-"),
                      let existing = try? Data(contentsOf: destination), let incoming = try? Data(contentsOf: file),
                      let merged = mergeToolArrays(existing: existing, incoming: incoming),
                      toolMergeIsSafe(store: file.deletingPathExtension().lastPathComponent, existing: existing, merged: merged.data) == true,
                      (try? merged.data.write(to: destination, options: .atomic)) != nil {
                added += merged.added
            }
        }
        return added
    }

    /// Birleşik veri güvenle yazılabilir mi? Bilinen depoda kendi türüyle çözülür: çözülmeli ve cihazdaki kayıtlar aynı
    /// değerlerle başta durmalı. Şeması uymayan tek bir yedek kaydı bütün dosyayı çözülemez kılardı; `JSONStore` okuyamadığı
    /// dosyayı kenara alıp depoyu boş açar. Tanınmayan depoda nil döner: birleştirilmez (eski "varsa atla" davranışı).
    /// Yeni bir araç deposu eklenince buraya da yazılmalı; yazılmazsa yalnız birleştirme yapılmaz, veri bozulmaz.
    nonisolated static func toolMergeIsSafe(store: String, existing: Data, merged: Data) -> Bool? {
        switch store {
        case "book-study": return BookStudyStore.mergeIsSafe(existing: existing, merged: merged)
        case "habits": return keepsRecords(Habit.self, existing, merged)
        case "goals": return keepsRecords(StudyGoal.self, existing, merged)
        case "todos": return keepsRecords(TodoItem.self, existing, merged)
        case "journal": return keepsRecords(JournalEntry.self, existing, merged)
        case "revisions": return keepsRecords(RevisionTopic.self, existing, merged)
        case "books": return keepsRecords(ReadingBook.self, existing, merged)
        case "quotes": return keepsRecords(OwnQuote.self, existing, merged)
        case "mock-exams": return keepsRecords(MockExam.self, existing, merged)
        case "grades": return keepsRecords(GradeCourse.self, existing, merged)
        case "absences": return keepsRecords(AbsenceCourse.self, existing, merged)
        case "countdowns": return keepsRecords(Countdown.self, existing, merged)
        case "questions": return keepsRecords(QuestionLog.self, existing, merged)
        default: return nil
        }
    }

    nonisolated private static func keepsRecords<T: Decodable & Equatable>(_ type: T.Type, _ existing: Data, _ merged: Data) -> Bool {
        let decoder = JSONDecoder()
        guard let before = try? decoder.decode([T].self, from: existing),
              let after = try? decoder.decode([T].self, from: merged) else { return false }
        return after.count > before.count && Array(after.prefix(before.count)) == before
    }

    /// İki araç deposunun (`[{ "id": …, … }]`) birleşimi: cihazdakiler olduğu gibi kalır, yedekte olup cihazda olmayan
    /// kimlikler sona eklenir. Eklenecek kayıt yoksa ya da biçim uymuyorsa (dizi değil, `id`siz öğe) nil: dosyaya dokunulmaz.
    /// Yalnız JSON düzeyinde birleştirir; kayıtların depo türüne uyduğunu `toolMergeIsSafe` sınar.
    nonisolated static func mergedToolArray(existing: Data, incoming: Data) -> Data? {
        mergeToolArrays(existing: existing, incoming: incoming)?.data
    }

    nonisolated private static func mergeToolArrays(existing: Data, incoming: Data) -> (data: Data, added: Int)? {
        guard let current = (try? JSONSerialization.jsonObject(with: existing)) as? [[String: Any]],
              let backup = (try? JSONSerialization.jsonObject(with: incoming)) as? [[String: Any]] else { return nil }
        var seen = Set<String>()
        for item in current {
            guard let key = toolRecordKey(item) else { return nil }
            seen.insert(key)
        }
        var merged = current
        for item in backup {
            guard let key = toolRecordKey(item) else { return nil }
            if seen.insert(key).inserted { merged.append(item) }
        }
        let added = merged.count - current.count
        guard added > 0, JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              // Yazmadan önce sağlama: birleşik veri geri okunduğunda cihazdaki kayıtlar aynı değerlerle başta duruyor mu?
              let check = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], check.count == merged.count,
              NSArray(array: Array(check.prefix(current.count))).isEqual(to: current) else { return nil }
        return (data, added)
    }

    /// Kayıt kimliği (metin ya da sayı); başka türde ya da yoksa nil.
    nonisolated private static func toolRecordKey(_ item: [String: Any]) -> String? {
        switch item["id"] {
        case let text as String: "s:" + text
        case let number as NSNumber: "n:" + number.stringValue
        default: nil
        }
    }

    /// Kopyalanan araç dosyasındaki kayıt sayısı; dizi değilse (çizim, tek nesne) 1.
    nonisolated private static func toolRecordCount(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url), let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return 1 }
        return array.count
    }

    struct RestoreWarning: LocalizedError {
        var added: Int, skipped: Int
        var errorDescription: String? { "\(added) bölüm geri yüklendi; \(skipped) bölümün ses dosyası yedekte bulunamadığı için atlandı." }
    }
}
