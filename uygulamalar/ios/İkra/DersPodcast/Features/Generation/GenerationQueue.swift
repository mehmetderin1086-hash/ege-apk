import SwiftData
import SwiftUI

/// Açılışta yarım kalan üretimlerin sürdürülmesi (üretim eşgüdümcüsü ilk etkinleşmede, LibraryView `.task`'ında çağırır).
enum GenerationQueue {
    /// Açılış planı süreç başına bir kez uygulanır.
    private static var launched = false

    /// Uygulama kapanmadan önce yarım kalan bölümleri ve senaryo isteklerini sürdür. Yalnız ilk çağrı planı uygular;
    /// sonrakiler (Kütüphane sekmesine her dönüş) kullanıcının durdurduğu ya da takılan bölümü yeniden başlatmaz,
    /// yalnız kuyruğu dürter.
    static func resumeOnLaunch(episodes: [Episode], context: ModelContext, generator: GenerationCoordinator) {
        // Erişim anahtarı yokken istekler 401 alıp kalıcı "Başarısız"a düşerdi; plan anahtar girilince uygulanır.
        guard AppState.current?.needsToken != true else { return }
        let requests = (try? context.fetch(FetchDescriptor<QueuedRequest>())) ?? []
        if !launched {
            launched = true
            let plan = launchPlan(episodes: episodes.map { .init(id: $0.id, status: $0.status, canResume: $0.canResume, needsApproval: $0.needsApproval) },
                                  requests: requests.map { .init(id: $0.id, state: $0.stateRaw) },
                                  scripting: Set(requests.map(\.id).filter(generator.isScripting)),
                                  stopped: UserStoppedGenerations.all())
            GenerationActivity.endOrphans(keeping: plan.keepActivities)
            for episode in episodes where plan.resume.contains(episode.id) {
                generator.resume(episode, context: context)
            }
            for episode in episodes where plan.expire.contains(episode.id) {
                episode.status = .failed
                episode.errorMessage = "Üretim yarıda kaldı ve süresi doldu."
            }
            for request in requests where plan.requeue.contains(request.id) {
                request.stateRaw = QueueState.needsRetry
                request.nextRetryAt = .now
            }
            try? context.save()
        }
        if !requests.isEmpty {
            Task { await OfflineQueue.process(context: context, generator: generator) }
        }
    }

    nonisolated struct EpisodeState: Sendable { var id: UUID; var status: EpisodeStatus; var canResume: Bool; var needsApproval: Bool }
    nonisolated struct RequestState: Sendable { var id: UUID; var state: String }
    nonisolated struct LaunchPlan: Equatable, Sendable {
        var resume: Set<UUID> = []
        var expire: Set<UUID> = []
        var requeue: Set<UUID> = []
        var keepActivities: Set<UUID> = []
    }

    /// Saf karar (test edilir): onay bekleyen bölüm ve yeniden denenecek istek "süresi doldu" diye bozulmaz.
    /// `stopped`: kullanıcının durdurduğu bölümler; ne sürdürülür ne de süresi dolmuş sayılır.
    nonisolated static func launchPlan(episodes: [EpisodeState], requests: [RequestState], scripting: Set<UUID>,
                                       stopped: Set<UUID> = []) -> LaunchPlan {
        var plan = LaunchPlan()
        for e in episodes where e.status == .generating {
            if e.needsApproval || stopped.contains(e.id) { continue }
            if e.canResume { plan.resume.insert(e.id) } else { plan.expire.insert(e.id) }
        }
        for r in requests where !scripting.contains(r.id) {
            // Uygulama yüklemede ya da yazımda öldü: aynı kimlikle (iş varsa yoklamayla) sürer.
            if r.state == QueueState.uploading || r.state == QueueState.scripting { plan.requeue.insert(r.id) }
        }
        plan.keepActivities = plan.resume.union(scripting)
        return plan
    }
}

/// Kullanıcının "Durdur" dediği bölümler (durumları `.generating` kalır): açılışta ve ön plana dönüşte
/// kendiliğinden sürdürülmez; yeniden başlatılınca ya da bölüm bitince/silinince kayıt kalkar.
nonisolated enum UserStoppedGenerations {
    static let key = "generation.userStopped"

    static func all(in defaults: UserDefaults = .standard) -> Set<UUID> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap { UUID(uuidString: $0) })
    }

    static func contains(_ id: UUID, in defaults: UserDefaults = .standard) -> Bool { all(in: defaults).contains(id) }

    static func insert(_ id: UUID, in defaults: UserDefaults = .standard) {
        var ids = all(in: defaults)
        if ids.insert(id).inserted { save(ids, in: defaults) }
    }

    static func remove(_ id: UUID, in defaults: UserDefaults = .standard) {
        var ids = all(in: defaults)
        if ids.remove(id) != nil { save(ids, in: defaults) }
    }

    private static func save(_ ids: Set<UUID>, in defaults: UserDefaults) {
        if ids.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(ids.map(\.uuidString).sorted(), forKey: key) }
    }
}

// MARK: - Öneri 7 / #3 / #43: üretim kuyruğu

enum OfflineQueue {
    /// İsteği kuyruğa alır: kaynaklar belge kütüphanesine kaydedilir. Sunucu erişilebilirse hemen işlenir.
    /// Dönen kimlik `QueuedRequest.id`'dir (ileride oluşacak `Episode.id`).
    @discardableResult
    static func enqueue(sources: [ImportedSource], settings: PodcastSettings, context: ModelContext) -> UUID {
        let request = insert(sources: sources, settings: settings, context: context, state: QueueState.waiting)
        if let app = AppState.current, app.server != nil {
            app.generator.retryNow(request.id, context: context)
        }
        return request.id
    }

    /// Kalıcı istek kaydı (senaryo aşaması boyunca yaşar; bölüm oluşunca silinir).
    /// `onDocuments`: kaynak sırasıyla belge kimlikleri (kopyası başarısızsa nil). Çağıran bunları kaynaklarına
    /// (`ImportedSource.documentID`) geri yazarsa yeniden denemede belge ve dosya yeniden kopyalanmaz.
    static func insert(sources: [ImportedSource], settings: PodcastSettings, context: ModelContext, state: String, id: UUID? = nil,
                       onDocuments: ([UUID?]) -> Void = { _ in }) -> QueuedRequest {
        // Her yeni bölüm buradan geçer: kaldırılan bir ses motoru (eski ayar, kısayol, seri devamı) yeni seslendirmeye sızmaz.
        let settings = settings.forNewAudio
        // Kaynak başına kaydedilir: kopyası başarısız olan kaynak atlanınca sayfa aralıkları başka belgeye kaymasın.
        // Aynı PDF dosyasının parçaları (bölümlere ayrılmış kitap) bir kez kaydedilir: her parça için kitabın tamamı
        // ayrı belge olarak kopyalanmaz; sayfa aralıkları `QueuedPageRanges`'te sırayla durur.
        var byURL: [URL: UUID] = [:]
        for source in sources {
            if let id = source.documentID, case let .pdf(url, _) = source.kind { byURL[url] = id }
        }
        let perSource = sources.map { source -> UUID? in
            guard source.documentID == nil, case let .pdf(url, _) = source.kind else {
                return DocumentLibrary.persist([source], context: context).first
            }
            if let known = byURL[url] { return known }
            var copy = source
            if let libraryName = source.libraryName { copy.name = libraryName }
            let id = DocumentLibrary.persist([copy], context: context).first
            if let id { byURL[url] = id }
            return id
        }
        onDocuments(perSource)
        let request = QueuedRequest(documentIDs: perSource.compactMap { $0 }, settings: settings, title: title(for: sources, settings: settings))
        if let id { request.id = id }
        request.stateRaw = state
        request.sourceNames = sources.map(\.name)
        context.insert(request)
        QueuedPageRanges.save(sources, documentIDs: perSource, for: request.id)
        try? context.save()
        return request
    }

    static func title(for sources: [ImportedSource], settings: PodcastSettings) -> String {
        let names = sources.map(\.name).joined(separator: ", ")
        guard let series = settings.series else { return names }
        return "\(series.name) · \(series.index)/\(series.total) · \(names)"
    }

    private static var running = false
    /// İşlem sürerken gelen çağrı: döngü bitince bir tur daha (ör. seri bölümü bitti, sıradaki açıldı).
    private static var rerun = false

    nonisolated struct SeriesItem: Sendable {
        var id: UUID
        var seriesID: UUID?
        var index: Int
        var failed: Bool
    }

    /// Seri sırası (saf; test edilir): aynı seride daha önceki bölümü hâlâ kuyrukta bekleyen istek atlanır.
    /// Başarısız (kullanıcı kararı bekleyen) önceki bölüm seriyi kilitlemez.
    nonisolated static func blockedBySeries(_ items: [SeriesItem]) -> Set<UUID> {
        var blocked: Set<UUID> = []
        for item in items {
            guard let series = item.seriesID else { continue }
            if items.contains(where: { $0.seriesID == series && $0.index < item.index && !$0.failed && $0.id != item.id }) {
                blocked.insert(item.id)
            }
        }
        return blocked
    }

    static func seriesItems(_ requests: [QueuedRequest]) -> [SeriesItem] {
        requests.filter { $0.modelContext != nil && !$0.isDeleted }.map { r in
            let series = r.settings?.series
            return SeriesItem(id: r.id, seriesID: series?.id, index: series?.index ?? 0, failed: r.stateRaw == QueueState.failed)
        }
    }

    /// Zamanı gelen istekleri sırayla üretir; bağlantı hatasında durur (muhtemelen hâlâ çevrimdışı).
    static func process(context: ModelContext, generator: GenerationCoordinator) async {
        guard !running else {
            rerun = true
            return
        }
        running = true
        defer { running = false }
        repeat {
            rerun = false
            guard await processOnce(context: context, generator: generator) else { return }
        } while rerun
    }

    /// Bir tur; bağlantı hatasında false (durulur).
    private static func processOnce(context: ModelContext, generator: GenerationCoordinator) async -> Bool {
        let queue = (try? context.fetch(FetchDescriptor<QueuedRequest>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        for request in queue {
            guard request.modelContext != nil, !request.isDeleted else { continue }
            let id = request.id
            guard !generator.isScripting(id), request.stateRaw != QueueState.failed else { continue }
            // Seri sırası: önceki bölüm hâlâ kuyruktaysa bu bölüm bekler (o bitince yeniden işlenir).
            let live = (try? context.fetch(FetchDescriptor<QueuedRequest>())) ?? []
            if blockedBySeries(seriesItems(live)).contains(id) { continue }
            if let next = request.nextRetryAt, next > .now {
                generator.scheduleRetry(id, after: next.timeIntervalSinceNow, context: context)
                continue
            }
            do {
                try await generator.process(id, context: context)
            } catch let queued as GenerationQueuedError {
                if queued.isNetwork { return false }
            } catch {
                continue
            }
        }
        return true
    }

    /// Kullanıcı kuyruktan siler: sunucu işi de iptal edilir. Seri bölümüyse sıradaki bölüm açılır.
    static func remove(_ request: QueuedRequest, context: ModelContext) {
        let id = request.id
        let inSeries = request.settings?.series != nil
        AppState.current?.generator.cancelDraft(id)
        if let job = request.serverJobID { Task { try? await APIClient.shared.scriptCancel(jobId: job) } }
        QueuedPageRanges.clear(id)
        context.delete(request)
        try? context.save()
        if inSeries, let generator = AppState.current?.generator { generator.continueQueue(context: context) }
    }

    /// #31: seri bölümü başlarken önceki bölümlerin (kuyrukta beklerken oluşmuş olabilir) başlıkları ve son ana fikirleri.
    nonisolated static func refreshedSeries(_ series: SeriesContext,
                                            earlier: [(index: Int, title: String, keyPoints: [String])]) -> SeriesContext {
        let before = earlier.filter { $0.index >= 1 && $0.index < series.index }.sorted { $0.index < $1.index }
        guard !before.isEmpty else { return series }
        var s = series
        let byIndex = Dictionary(before.map { ($0.index, $0.title) }, uniquingKeysWith: { a, _ in a })
        // Sıra bölüm sırasıdır (1…index-1); bölümü olmayan (ör. silinmiş) önceki başlık eski listeden korunur.
        s.previousTitles = (1..<max(series.index, 1)).compactMap { byIndex[$0] ?? series.previousTitles[safe: $0 - 1] }
        if let last = before.last, !last.keyPoints.isEmpty { s.previousKeyPoints = Array(last.keyPoints.prefix(12)) }
        return s
    }

    /// Durum etiketi (saf).
    nonisolated static func stateTitle(_ state: String) -> String {
        switch state {
        case QueueState.uploading: "Yükleniyor"
        case QueueState.scripting: "Senaryo yazılıyor"
        case QueueState.needsRetry: "Yeniden denenecek"
        case QueueState.failed: "Başarısız"
        default: "Sırada"
        }
    }
}

/// Başka bir ekrandan (ör. YouTube dersi) başlatılan podcast üretimleri: senaryo yazılırken görünür kalsın.
struct DraftBanner: View {
    @Environment(GenerationCoordinator.self) private var generator
    /// Taslak kimliği = kuyruk isteği kimliği: başlık oradan gelir (iki eşzamanlı taslak ayırt edilsin).
    @Query private var requests: [QueuedRequest]

    var body: some View {
        let ids = generator.drafts.keys.sorted { $0.uuidString < $1.uuidString }
        if !ids.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ids, id: \.self) { id in
                    if let phase = generator.drafts[id] {
                        // Ayrıntı ekranında (PendingGenerationView) "Vazgeç" var: arka plana alınan yazım oradan durdurulur.
                        Button {
                            AppState.current?.open(id)
                        } label: {
                            HStack(spacing: 10) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Self.title(requests.first { $0.id == id }?.title))
                                        .font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(Self.subtitle(phase)).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                    ProgressView(value: phase.draftFraction).tint(.accentColor)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Üretim ayrıntısını aç")
                    }
                }
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

extension DraftBanner {
    /// Satır başlığı (saf; test edilir): isteğin adı; isteği olmayan ya da adı boş taslakta "Podcast".
    nonisolated static func title(_ requestTitle: String?) -> String {
        let name = requestTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Podcast" : name
    }

    /// Alt satır: yazım aşamasında ilerleme ("Plan çıkarıldı · Konu 6/14"), öncesinde aşamanın adı.
    static func subtitle(_ phase: GenerationCoordinator.Phase) -> String {
        phase.isWritingScript ? phase.progressText : phase.title
    }
}

struct QueueBanner: View {
    @Query(sort: \QueuedRequest.createdAt) private var queue: [QueuedRequest]
    @Environment(\.modelContext) private var context
    @Environment(GenerationCoordinator.self) private var generator

    var body: some View {
        // Şu an yazılanlar DraftBanner'da görünür.
        let waiting = queue.filter { !generator.isScripting($0.id) }
        if !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Kuyrukta \(waiting.count) podcast", systemImage: "tray.full.fill").font(.subheadline.bold())
                Text("Sunucuya bağlanınca sırayla üretilir; hata olursa kendiliğinden yeniden denenir.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(waiting) { item in
                    QueueRow(item: item)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct QueueRow: View {
    var item: QueuedRequest
    @Environment(\.modelContext) private var context
    @Environment(GenerationCoordinator.self) private var generator

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    AppState.current?.open(item.id)
                } label: {
                    HStack(spacing: 4) {
                        Text(DraftBanner.title(item.title)).font(.caption.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Üretim ayrıntısını aç")
                Spacer(minLength: 4)
                Button(role: .destructive) { OfflineQueue.remove(item, context: context) } label: {
                    Image(systemName: "xmark.circle").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Kuyruktan sil")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { status; Spacer(minLength: 4); retryButton }
                VStack(alignment: .leading, spacing: 4) { status; retryButton }
            }
            if let error = item.lastError { Text(error).font(.caption2).foregroundStyle(.orange).lineLimit(3) }
        }
    }

    private var status: some View {
        HStack(spacing: 4) {
            Text(item.progressText.map { "\(OfflineQueue.stateTitle(item.stateRaw)) · \($0)" } ?? OfflineQueue.stateTitle(item.stateRaw))
            if let next = item.nextRetryAt, next > .now, item.stateRaw == QueueState.needsRetry {
                Text(next, style: .timer).monospacedDigit()
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var retryButton: some View {
        Button("Şimdi dene", systemImage: "arrow.clockwise") { generator.retryNow(item.id, context: context) }
            .font(.caption.bold())
            .buttonStyle(.bordered)
            .frame(minHeight: 44)
    }
}

#if DEBUG
/// Yalnızca Debug: P3 ekranlarını sunucusuz göstermek için örnek veri.
/// `-p3Demo`: onay bekleyen bölüm + kuyrukta bekleyen istek + senaryo taslağı; `-p3Preview` önizlemeyi açar;
/// `-p3Customize` yeni podcast ayarlarını açar; `-p3Sources[=N]` yeni podcast ekranını kaynak adımında örnek
/// kaynaklarla (N fotoğraf, varsayılan 3) açar.
enum P3Demo {
    private static var done = false
    static let episodeID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A3")!

    static var sourcesRequested: Bool {
        ProcessInfo.processInfo.arguments.contains { $0 == "-p3Sources" || $0.hasPrefix("-p3Sources=") }
    }

    static func run(context: ModelContext, generator: GenerationCoordinator) {
        let args = ProcessInfo.processInfo.arguments
        guard !done else { return }
        done = true
        if args.contains("-p3Customize") || sourcesRequested { AppState.current?.pendingRoute = "new" }
        guard args.contains("-p3Demo") else { return }
        let id = episodeID
        if (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first) == nil {
            let scene = { (t: String) in ScriptScene(turns: [ScriptTurn(speaker: .a, text: t, style: ""), ScriptTurn(speaker: .b, text: "Harika soru! Peki neden?", style: "")]) }
            let script = PodcastScript(
                title: "Hücre bölünmesi: mitoz ve mayoz", summary: "Mitozun evreleri ve mayozla farkı.", keyPoints: ["Mitoz iki özdeş hücre verir."],
                chapters: [ScriptChapter(title: "Hücre döngüsü", scenes: [scene("Hücre döngüsü interfazla başlar."), scene("DNA eşlenir.")], style: "sohbet"),
                           ScriptChapter(title: "Mitozun evreleri", scenes: [scene("Profaz, metafaz, anafaz, telofaz.")], style: "anlatim"),
                           ScriptChapter(title: "Mayozla karşılaştırma", scenes: [scene("Mayoz dört hücre verir.")], style: "hizliSoru")],
                sourceNotes: "Mitoz ve mayoz notları.",
                quality: ScriptQualityReport(targetMinutes: 15, estimatedMinutes: 13.4, words: 2010,
                                             findings: [QualityFinding(id: "great", label: "“Harika soru”", count: 9, examples: nil),
                                                        QualityFinding(id: "echo", label: "Yalnız onaylayan B turu", count: 4, examples: nil)],
                                             weakScenes: [WeakScene(scene: 1, reasons: ["B yalnız onaylıyor", "Örnek yok"])],
                                             chapterErrors: [ChapterError(index: 3, title: "Mayoz II ve çaprazlama", message: "Model zamanında yanıt vermedi.")]))
            let episode = Episode(id: id, script: script, settings: PodcastSettings(speechProvider: "apple"), sourceNames: ["Biyoloji notu"], jobToken: "demo")
            episode.needsApproval = true
            context.insert(episode)
            let request = QueuedRequest(documentIDs: [], settings: PodcastSettings(), title: "Fizik · Hareket ve kuvvet")
            request.stateRaw = QueueState.needsRetry
            request.lastError = "Sunucuya ulaşılamadı."
            request.nextRetryAt = .now.addingTimeInterval(300)
            context.insert(request)
            try? context.save()
        }
        generator.setDraft(UUID(), .writingScript(ScriptProgress(stage: "chapters", chaptersDone: 4, chaptersTotal: 12)))
        if args.contains("-p3Preview") { AppState.current?.open(id) }
        else if args.contains("-p3Library") { AppState.current?.selectedTab = .library }
    }
}
#endif
