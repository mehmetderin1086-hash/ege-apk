import Foundation
import Observation
import SwiftData
import UIKit

/// `QueuedRequest.stateRaw` değerleri.
nonisolated enum QueueState {
    static let waiting = "waiting"
    static let uploading = "uploading"
    static let scripting = "scripting"
    static let needsRetry = "needsRetry"
    static let failed = "failed"
}

/// Kuyruğa alınan (sonra otomatik yeniden denenecek) üretim. Mesaj kullanıcıya gösterilir.
nonisolated struct GenerationQueuedError: LocalizedError, Sendable {
    var requestID: UUID
    var retryAt: Date?
    var underlying: String
    /// Bağlantı hatası (kuyruk işleyicisi durur; muhtemelen hâlâ çevrimdışı).
    var isNetwork = false

    var errorDescription: String? {
        guard let retryAt else { return "\(underlying) İstek kuyruğa alındı; bağlantı gelince sürecek." }
        return "\(underlying) İstek kuyruğa alındı; \(retryAt.formatted(date: .omitted, time: .shortened)) civarında otomatik yeniden denenecek."
    }
}

@Observable
final class GenerationCoordinator {
    enum Phase: Equatable {
        case preparing
        case uploading
        case writingScript(ScriptProgress = ScriptProgress())
        case voicing(done: Int, total: Int)
        case mixing

        var title: String {
            switch self {
            case .preparing: "Belgeler hazırlanıyor"
            case .uploading: "Belgeler gönderiliyor"
            case .writingScript: "Senaryo yazılıyor"
            case .voicing: "Seslendiriliyor"
            case .mixing: "Bölüm birleştiriliyor"
            }
        }

        var detail: String {
            switch self {
            case .preparing: "Sayfalar okunuyor ve sıkıştırılıyor."
            case .uploading: "Belgeler sunucuya yükleniyor."
            case let .writingScript(p) where p.chaptersTotal > 0: p.text
            case .writingScript: "Yapay zekâ belgeni okuyup iki sunuculu bir ders sohbeti kurguluyor. Bu adım 1–2 dakika sürebilir."
            case let .voicing(done, total): "\(done) / \(total) sahne hazır"
            case .mixing: "Sahneler tek bir ses dosyasında birleştiriliyor."
            }
        }

        /// Bütün üretim boyunca oran.
        var fraction: Double {
            switch self {
            case .preparing: GenerationPhaseMath.overall(script: nil)
            case .uploading: GenerationPhaseMath.overall(script: nil, uploading: true)
            case let .writingScript(p): GenerationPhaseMath.overall(script: p)
            case let .voicing(done, total): GenerationPhaseMath.overall(script: nil, voicedDone: done, voicedTotal: max(total, 1))
            case .mixing: GenerationPhaseMath.overall(script: nil, mixing: true)
            }
        }

        /// Yalnız senaryo aşaması (yeni podcast ekranındaki çubuk).
        var draftFraction: Double {
            switch self {
            case .preparing: 0.03
            case .uploading: 0.08
            case let .writingScript(p): 0.1 + 0.9 * p.fraction
            default: 1
            }
        }

        var isWritingScript: Bool { if case .writingScript = self { true } else { false } }

        /// "Plan çıkarıldı · Konu 6/14 · Sahne 18/52"
        var progressText: String {
            switch self {
            case .preparing, .uploading: title
            case let .writingScript(p): GenerationProgress.text(script: p, scenesDone: p.scenesDone, scenesTotal: p.scenesTotal)
            case let .voicing(done, total): GenerationProgress.text(script: nil, scenesDone: done, scenesTotal: total)
            case .mixing: "Sahneler birleştiriliyor"
            }
        }
    }

    /// #50: eşzamanlı senaryo taslakları (anahtar = QueuedRequest.id = ileride Episode.id).
    private(set) var drafts: [UUID: Phase] = [:]
    private var draftOrder: [UUID] = []
    /// Uyumluluk: en son başlayan taslağın aşaması.
    var draftPhase: Phase? { draftOrder.last.flatMap { drafts[$0] } }
    private(set) var phases: [UUID: Phase] = [:]
    private(set) var retryUntil: [UUID: Date] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    /// Senaryo görevleri (sonuç bölüm kimliğidir; model nesnesi görevler arasında taşınmaz).
    private var scriptTasks: [UUID: Task<UUID, Error>] = [:]
    private var retryTimers: [UUID: Task<Void, Never>] = [:]
    /// Sistem (BG görevi süresi) tarafından durdurulanlar: başarısız değil, "duraklatıldı".
    private var pausing: Set<UUID> = []
    private var paused: Set<UUID> = []
    /// Bu oturumda seslendirme öncesi doğrulaması denenen bölümler.
    private var preVerified: Set<UUID> = []
    @ObservationIgnored private var activeObserver: NSObjectProtocol?
    /// Açılış sürdürmesi süreç başına bir kez, ilk etkinleşmede yapılır.
    @ObservationIgnored private var didLaunchResume = false
    @ObservationIgnored private var watchingToken = false
    /// Sistem görevi istenip açılamayan işler (uygulama etkin değildi ya da gönderim reddedildi): ön plana dönünce yeniden denenir.
    @ObservationIgnored private var backgroundWanted: [UUID: (title: String, subtitle: String)] = [:]

    private let api = APIClient.shared

    init() {
        GenerationBackground.onExpire = { [weak self] id in self?.pause(id) }
        activeObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.becameActive() }
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-p3Demo") || args.contains("-p3Customize") || P3Demo.sourcesRequested {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self else { return }
                P3Demo.run(context: AppDataStore.container.mainContext, generator: self)
            }
        }
        #endif
    }

    /// Her etkinleşmede: (ilk seferde) yarım kalanlar sürdürülür, duraklatılanlar sürer, açılamamış sistem görevleri
    /// yeniden istenir ve kuyruk dürtülür. Böylece üretim Kütüphane sekmesinin açılmasına bağlı kalmaz.
    private func becameActive() {
        let launching = !didLaunchResume
        launchResumeIfNeeded()
        resumePaused()
        adoptBackground()
        // İlk etkinleşmede kuyruğu açılış sürdürmesi başlatır.
        if !launching, Self.canDriveQueue { continueQueue(context: AppDataStore.container.mainContext) }
    }

    private func launchResumeIfNeeded() {
        guard !didLaunchResume, !Self.isUnitTesting else { return }
        guard Self.canDriveQueue else {
            watchToken()
            return
        }
        didLaunchResume = true
        Task {
            await Self.waitForServerStatus()
            // Durum yoklaması anahtarı reddettiyse anahtar girilince ya da sonraki etkinleşmede yeniden denenir.
            guard Self.canDriveQueue else {
                didLaunchResume = false
                watchToken()
                return
            }
            let context = AppDataStore.container.mainContext
            let generating = EpisodeStatus.generating.rawValue
            let episodes = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.statusRaw == generating }))) ?? []
            GenerationQueue.resumeOnLaunch(episodes: episodes, context: context, generator: self)
        }
    }

    /// Erişim anahtarı aynı ön plan oturumunda girilirse yeni etkinleşme bildirimi gelmez: `needsToken` değişince
    /// açılış sürdürmesi yeniden denenir (Kütüphane sekmesinin açılması beklenmez).
    private func watchToken() {
        guard !watchingToken, let app = AppState.current else { return }
        watchingToken = true
        withObservationTracking {
            _ = app.needsToken
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.watchingToken = false
                self?.launchResumeIfNeeded()
            }
        }
    }

    /// Kendiliğinden sürdürme koşulu: birim testinde değil ve sunucu erişim anahtarı var. Anahtar yokken (kurulum ekranı)
    /// kuyruktaki istekler 401 alıp kalıcı "Başarısız"a düşerdi.
    private static var canDriveQueue: Bool { !isUnitTesting && AppState.current?.needsToken != true }

    private static var isUnitTesting: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }

    /// Sunucu yetenekleri açılıştan kısa süre sonra bilinir (RootView yeniler); bilinmeden başlayan seslendirme
    /// senaryo denetimini (#5) atlardı. En çok 3 sn beklenir: çevrimdışıyken cihaz motoru gecikmesin.
    private static func waitForServerStatus() async {
        for _ in 0..<15 {
            guard let app = AppState.current, app.server == nil, app.serverError == nil else { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    func isRunning(_ episode: Episode) -> Bool { tasks[episode.id] != nil }
    func isScripting(_ id: UUID) -> Bool { scriptTasks[id] != nil }
    private(set) var verifying: Set<UUID> = []
    private var verifyTasks: [UUID: Task<Void, Never>] = [:]
    /// Sahne düzenlemesi süren bölümler (eşzamanlı iki düzenleme aynı dosyayı bozmasın).
    private(set) var editing: Set<UUID> = []
    func isVerifying(_ episode: Episode) -> Bool { verifying.contains(episode.id) }
    private(set) var verifyError: [UUID: String] = [:]
    /// Üretim, düzenleme ya da senaryo taslağı sürüyor mu (yedek bekler).
    var hasActiveWork: Bool { !tasks.isEmpty || !editing.isEmpty || !drafts.isEmpty || !scriptTasks.isEmpty }

    /// "Plan çıkarıldı · Konu 6/14 · Sahne 18/52"; iş yoksa nil.
    func progressText(for episodeID: UUID) -> String? {
        if let draft = drafts[episodeID] { return draft.progressText }
        if let until = retryUntil[episodeID] {
            return "Bekleniyor · \(until.formatted(date: .omitted, time: .shortened)) civarında yeniden denenecek"
        }
        return phases[episodeID]?.progressText
    }

    /// Kuyruğa alır; dönen kimlik ileride oluşacak `Episode.id`'dir. Sunucu erişilebilirse hemen işlenir.
    @discardableResult
    func enqueue(sources: [ImportedSource], settings: PodcastSettings, context: ModelContext) -> UUID {
        OfflineQueue.enqueue(sources: sources, settings: settings, context: context)
    }
    // MARK: - Senaryo (#3: her üretim senaryo aşaması boyunca bir QueuedRequest kaydıdır)

    /// Belgelerden senaryo üretir, bölümü kaydeder ve seslendirmeyi arka planda başlatır.
    func start(sources: [ImportedSource], settings: PodcastSettings, context: ModelContext) async throws -> Episode {
        try await start(sources: sources, settings: settings, context: context,
                        userInitiated: UIApplication.shared.applicationState == .active)
    }

    /// `requestID`: çağıran taslağın ilerlemesini (`drafts[requestID]`) izlemek için kimliği önceden verebilir.
    /// `onDocuments`: kalıcılaştırılan belge kimlikleri (kaynak sırasıyla); bkz. `OfflineQueue.insert`.
    func start(sources: [ImportedSource], settings: PodcastSettings, context: ModelContext, userInitiated: Bool,
               requestID: UUID? = nil, onDocuments: ([UUID?]) -> Void = { _ in }) async throws -> Episode {
        // Doğrulama, bölümün gerçekten seslendirileceği motorla yapılır (bkz. `OfflineQueue.insert`).
        let settings = settings.forNewAudio
        try Self.validate(settings)
        let request = OfflineQueue.insert(sources: sources, settings: settings, context: context, state: QueueState.uploading, id: requestID,
                                          onDocuments: onDocuments)
        return try await runScript(request.id, sources: sources, context: context, userInitiated: userInitiated, interactive: true)
    }

    static func validate(_ settings: PodcastSettings) throws {
        try LocalSpeech.validate(settings)
        if settings.engine == .apple {
            let swapped = DeviceSpeech.swapsGenders(settings)
            _ = try DeviceSpeech.selectedVoice(speaker: .a, language: settings.language, swapped: swapped)
            if settings.format.usesTwoHosts { _ = try DeviceSpeech.selectedVoice(speaker: .b, language: settings.language, swapped: swapped) }
        }
    }

    /// Kuyruktaki isteği hemen dener ("Şimdi dene", bildirim eylemi, otomatik zamanlayıcı).
    func retryNow(_ id: UUID, context: ModelContext) {
        guard scriptTasks[id] == nil else { return }
        retryTimers[id]?.cancel()
        retryTimers[id] = nil
        Task { _ = try? await runScript(id, sources: nil, context: context, userInitiated: true, interactive: false) }
    }

    /// Kuyruk işleyicisi için: istek bitene (ya da yeniden kuyruğa düşene) dek bekler.
    func process(_ id: UUID, context: ModelContext) async throws {
        _ = try await runScript(id, sources: nil, context: context, userInitiated: false, interactive: false)
    }

    /// Kuyruğa önceden yazılmış isteği (serinin sıradaki bölümü) başlatır ya da süren yazımına katılır; bölümü döndürür.
    /// Kalıcı hatada istek silinmez, kuyrukta "Başarısız" kalır.
    func startQueued(_ id: UUID, context: ModelContext) async throws -> Episode {
        try await runScript(id, sources: nil, context: context, userInitiated: true, interactive: false)
    }

    /// İstek kuyruktan silinirken: süren yazım iptal edilir (sunucu işi de). Yazım sürmüyorsa otomatik deneme
    /// zamanlayıcısı ve o beklerken açık tutulan sistem görevi kapanır.
    func cancelDraft(_ id: UUID) {
        if let task = scriptTasks[id] {
            task.cancel()
            return
        }
        retryTimers[id]?.cancel()
        retryTimers[id] = nil
        backgroundWanted[id] = nil
        if tasks[id] == nil { GenerationBackground.finish(id, success: false) }
    }

    private func runScript(_ id: UUID, sources: [ImportedSource]?, context: ModelContext, userInitiated: Bool, interactive: Bool) async throws -> Episode {
        let episodeID: UUID
        if let running = scriptTasks[id] {
            episodeID = try await running.value
        } else {
            // Kayıt görevin kendi içinde silinir: bekleyenler (ör. duraklatmadan dönüş) uyandığında yer zaten boştur
            // ve dışarıdaki bir `defer` sonradan açılan yeni görevin kaydını silemez.
            let task = Task<UUID, Error> {
                defer { self.scriptTasks[id] = nil }
                return try await self.scriptBody(id, sources: sources, context: context, userInitiated: userInitiated, interactive: interactive).id
            }
            scriptTasks[id] = task
            episodeID = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        }
        guard let episode = fetchEpisode(episodeID, context: context) else { throw CancellationError() }
        return episode
    }

    func setDraft(_ id: UUID, _ phase: Phase) {
        if drafts[id] == nil { draftOrder.append(id) }
        drafts[id] = phase
    }

    func endDraft(_ id: UUID) {
        drafts[id] = nil
        draftOrder.removeAll { $0 == id }
    }

    private func fetchRequest(_ id: UUID, context: ModelContext) -> QueuedRequest? {
        try? context.fetch(FetchDescriptor<QueuedRequest>(predicate: #Predicate { $0.id == id })).first
    }

    private func fetchEpisode(_ id: UUID, context: ModelContext) -> Episode? {
        try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first
    }

    private func scriptBody(_ id: UUID, sources given: [ImportedSource]?, context: ModelContext,
                            userInitiated: Bool, interactive: Bool) async throws -> Episode {
        guard let request = fetchRequest(id, context: context) else {
            if let existing = fetchEpisode(id, context: context) { return existing }
            throw CancellationError()
        }
        // Aynı kimlikli bölüm zaten oluştuysa (ör. önceki deneme yanıtı yazdıktan sonra öldü) isteği kapat.
        if let existing = fetchEpisode(id, context: context) {
            context.delete(request)
            try? context.save()
            return existing
        }
        // Kuyruğa eski bir sürümde yazılmış istek kaldırılan bir ses motorunu taşıyabilir (seri devamı, çevrimdışı kuyruk):
        // yeni bölüm yalnız sunulan motorlarla seslendirilir.
        guard var settings = request.settings?.forNewAudio else {
            context.delete(request)
            try? context.save()
            throw APIError(status: 0, code: "settings", message: "İstek ayarları okunamadı.")
        }
        // #31: kuyrukta beklerken önceki seri bölümleri oluşmuş olabilir; başlıkları ve ana fikirleri eklenir.
        if request.serverJobID == nil, let series = settings.series {
            let refreshed = refreshedSeries(series, context: context)
            if refreshed != series {
                settings.series = refreshed
                request.settingsData = (try? JSONEncoder().encode(settings)) ?? request.settingsData
            }
        }
        let title = request.title
        setDraft(id, .preparing)
        defer { endDraft(id) }
        paused.remove(id)
        retryTimers[id]?.cancel()
        retryTimers[id] = nil
        wantBackground(id, title: "Podcast hazırlanıyor", subtitle: title)
        // Ölçülemeyen adımlarda (OCR, yükleme, plan) sistem görevi ilerleme görsün.
        GenerationBackground.pulse(id, toward: Phase.writingScript(ScriptProgress(stage: "plan", chaptersTotal: 1)).fraction)
        // Otomatik deneme zamanlandıysa görev "Bekleniyor" diye açık tutuluyor olabilir: kalp atışı sürer.
        defer { if retryTimers[id] == nil { GenerationBackground.stopPulse(id) } }
        let startedAt = Date.now
        request.stateRaw = QueueState.uploading
        request.lastError = nil
        request.nextRetryAt = nil
        try? context.save()

        do {
            if AppState.current?.server == nil { await AppState.current?.refreshStatus() }
            let app = AppState.current
            let useJobs = request.serverJobID != nil || app?.serverSupports("scriptJobs") == true
            let serverSettings = ServerSettings.prepare(settings, podcast2: app?.serverSupports("podcast2") == true)
            var loaded = given
            func loadSources() throws -> [ImportedSource] {
                if let loaded { return loaded }
                // Aralık belge kimliğiyle değil sırayla okunur: aynı belge iki aralıkla kullanıldıysa (kitabın iki bölümü)
                // iki kaynak da kendi sayfalarını gönderir.
                let docs = request.documentIDs.enumerated().compactMap { index, documentID -> ImportedSource? in
                    guard let document = DocumentLibrary.fetch(documentID, context: context),
                          var source = DocumentLibrary.importedSource(document) else { return nil }
                    if let range = QueuedPageRanges.range(at: index, document: documentID, for: id) { source.pageRange = range }
                    return source
                }
                let sources = QueuedSourceNames.apply(request.sourceNames, to: docs)
                guard !sources.isEmpty else { throw APIError(status: 0, code: "sources", message: "Kaynak belgeler bulunamadı.") }
                loaded = sources
                return sources
            }

            let response: ScriptResponse
            if useJobs {
                var jobID = request.serverJobID
                let result = try await withBackgroundTime("script") {
                    try await ScriptJobClient.run(existingJobID: jobID, makeStart: {
                        self.setDraft(id, .preparing)
                        let payload = try await DocumentLoader.payload(for: try loadSources())
                        self.setDraft(id, .uploading)
                        GenerationBackground.update(id, fraction: Phase.uploading.fraction, title: "Belgeler gönderiliyor", subtitle: title)
                        return ScriptStartRequest(clientRequestId: id.uuidString.lowercased(), settings: serverSettings,
                                                  sources: payload, prerender: Self.prerender(for: settings))
                    }, onJob: { job in
                        jobID = job
                        guard request.modelContext != nil, !request.isDeleted else { return }
                        request.serverJobID = job
                        request.stateRaw = job == nil ? QueueState.uploading : QueueState.scripting
                        try? context.save()
                    }, onProgress: { status in
                        let progress = ScriptProgress(status: status)
                        let phase = Phase.writingScript(progress)
                        // Sıradaki konu bitene dek sistem ilerlemesi azar azar artar.
                        var next = progress
                        if next.stage == "chapters" { next.chaptersDone = min(next.chaptersDone + 1, next.chaptersTotal) }
                        GenerationBackground.pulse(id, toward: max(Phase.writingScript(next).fraction, phase.fraction))
                        self.setDraft(id, phase)
                        if request.modelContext != nil, !request.isDeleted, request.progressText != phase.progressText {
                            request.progressText = phase.progressText
                            try? context.save()
                        }
                        GenerationBackground.update(id, fraction: phase.fraction, title: "Senaryo yazılıyor", subtitle: phase.progressText)
                        GenerationActivity.update(id, title: title, phase: "Senaryo yazılıyor", done: progress.chaptersDone,
                                                  total: progress.chaptersTotal, detail: phase.progressText, fraction: phase.fraction)
                    })
                }
                if !(result.script.quality?.chapterErrors.isEmpty ?? true) { ScriptJobMemory.save(jobID, for: id) }
                response = ScriptResponse(jobToken: result.jobToken, script: result.script, model: result.model)
            } else {
                let payload = try await DocumentLoader.payload(for: try loadSources())
                setDraft(id, .writingScript())
                request.stateRaw = QueueState.scripting
                GenerationBackground.update(id, fraction: Phase.writingScript().fraction, title: "Senaryo yazılıyor", subtitle: title)
                response = try await withBackgroundTime("script") {
                    try await api.script(ScriptRequest(settings: serverSettings, sources: payload))
                }
            }
            try Task.checkCancellation()
            if let existing = fetchEpisode(id, context: context) {
                context.delete(request)
                try? context.save()
                if tasks[id] == nil { GenerationBackground.finish(id, success: true) }
                return existing
            }
            let episode = makeEpisode(id: id, request: request, settings: settings, response: response, startedAt: startedAt)
            context.insert(episode)
            context.delete(request)
            QueuedPageRanges.clear(id)
            try? context.save()
            // Seri: kuyrukta bu bölümü bekleyen sonraki bölüm açılır.
            if settings.series != nil { continueQueue(context: context) }
            if episode.needsApproval {
                GenerationBackground.finish(id, success: true)
                GenerationActivity.end(id, success: false, total: 0)
                NotificationActions.post(.approval, episodeID: id, title: episode.title)
            } else {
                resume(episode, context: context)
            }
            return episode
        } catch {
            throw scriptFailed(id, error: error, context: context, interactive: interactive)
        }
    }

    /// Kuyruğu bir tur daha işletir (süren işlem varsa o bitince yeniden döner).
    func continueQueue(context: ModelContext) {
        Task { await OfflineQueue.process(context: context, generator: self) }
    }

    private func refreshedSeries(_ series: SeriesContext, context: ModelContext) -> SeriesContext {
        let seriesID: UUID? = series.id
        let episodes = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.seriesID == seriesID }))) ?? []
        return OfflineQueue.refreshedSeries(series, earlier: episodes.filter { $0.seriesIndex < series.index }.map {
            (index: $0.seriesIndex, title: $0.title, keyPoints: $0.script?.keyPoints ?? [])
        })
    }

    /// Senaryodan bölüm oluşturur (kimlik = istek kimliği; bağlam ve istatistik işlenir).
    private func makeEpisode(id: UUID, request: QueuedRequest, settings: PodcastSettings, response: ScriptResponse, startedAt: Date) -> Episode {
        let names = request.sourceNames.isEmpty ? [request.title] : request.sourceNames
        let episode = Episode(id: id, script: response.script, settings: settings, sourceNames: names, jobToken: response.jobToken)
        // Senaryoyu uygulama içi motor yazdıysa belirteci de onundur; sunucu bu belirteçle gelen seslendirme isteğini reddeder
        // ve bölüm düşerdi. Belirteç atılır: seslendirme başlarken sunucudan ses işi istenir (bkz. `render`).
        if response.serverJobToken == nil {
            episode.jobToken = nil
            episode.jobTokenExpiresAt = .distantPast
        }
        // İstekte aynı belge birden çok aralıkla yer alabilir; bölümün kaynak listesinde bir kez durur.
        var seen: Set<UUID> = []
        episode.sourceDocumentIDs = request.documentIDs.filter { seen.insert($0).inserted }
        episode.applyContext(from: settings)
        // #7: önizleme açıksa ya da bazı konular yazılamadıysa seslendirme onay bekler.
        let partial = !(response.script.quality?.chapterErrors.isEmpty ?? true)
        episode.needsApproval = Self.previewBeforeVoicing || partial
        let minutes = response.script.quality?.estimatedMinutes ?? Double(settings.durationMin)
        episode.generationStats = GenerationStats(
            engine: settings.speechProvider, scriptModel: response.model ?? settings.scriptAI?.model, startedAt: startedAt,
            scriptSeconds: Date.now.timeIntervalSince(startedAt), voiceSeconds: nil, mixSeconds: nil,
            characters: response.script.totalCharacters, scenes: response.script.flatScenes.count, retakes: 0,
            estimatedCostUSD: GenerationCost.estimate(engine: settings.engine, characters: response.script.totalCharacters))
        return episode
    }

    /// Senaryo hatası: kullanıcı iptali → istek silinir; sistem duraklatması ve geçici hata → kuyrukta bekler.
    private func scriptFailed(_ id: UUID, error: Error, context: ModelContext, interactive: Bool) -> Error {
        GenerationActivity.end(id, success: false, total: 0)
        let request = fetchRequest(id, context: context)
        // Otomatik deneme dalı sistem görevini kısa beklemede açık tutar; öbür bütün çıkışlarda görev kapanır.
        var keepsBackground = false
        defer { if !keepsBackground { GenerationBackground.finish(id, success: false) } }
        if error is CancellationError || Task.isCancelled {
            if pausing.remove(id) != nil, let request {
                request.stateRaw = QueueState.needsRetry
                request.lastError = "Duraklatıldı. Uygulama açılınca sürecek."
                request.nextRetryAt = .now
                try? context.save()
                // `paused` kaydı `pause()`'ta; ön plana dönüş bu görevin bitmesini bekleyip sürdürür.
                if UIApplication.shared.applicationState != .active {
                    NotificationActions.post(.stalled("Duraklatıldı; uygulamayı açınca sürecek."), episodeID: id, title: request.title)
                }
                return GenerationQueuedError(requestID: id, retryAt: nil, underlying: "Duraklatıldı.")
            }
            if let request {
                if let job = request.serverJobID { Task { try? await APIClient.shared.scriptCancel(jobId: job) } }
                context.delete(request)
                QueuedPageRanges.clear(id)
                try? context.save()
            }
            return CancellationError()
        }
        pausing.remove(id)
        guard let request else { return error }
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let inSeries = request.settings?.series != nil
        if RetryPolicy.shouldAutoRetry(error, attempts: request.attempts) {
            let delay = RetryPolicy.delay(attempt: request.attempts, retryAfter: (error as? APIError)?.retryAfter)
            request.attempts += 1
            request.stateRaw = QueueState.needsRetry
            request.lastError = message
            request.nextRetryAt = .now.addingTimeInterval(delay)
            try? context.save()
            keepsBackground = holdBackground(id, title: request.title, delay: delay)
            scheduleRetry(id, after: delay, context: context)
            return GenerationQueuedError(requestID: id, retryAt: request.nextRetryAt, underlying: message,
                                         isNetwork: (error as? APIError)?.code == "network")
        }
        if interactive {
            // Sonucu alınmamış sunucu işi iptal edilir (§5.1: hak iade edilir).
            if let job = request.serverJobID { Task { try? await APIClient.shared.scriptCancel(jobId: job) } }
            context.delete(request)
            QueuedPageRanges.clear(id)
        } else {
            request.attempts += 1
            request.stateRaw = QueueState.failed
            request.lastError = message
            request.nextRetryAt = nil
            // #46: kuyruk/Siri işi kalıcı olarak düştü; kullanıcı haberdar edilir (`post` ön planda göndermez).
            NotificationActions.post(.failed(message), episodeID: id, title: request.title)
        }
        try? context.save()
        // Seri: başarısız bölüm sonrakileri kilitlemez.
        if inSeries { continueQueue(context: context) }
        return error
    }

    /// #4: yalnız uygulama koşarken; askıdayken zamanlayıcı da durur, ön plana gelince sürer.
    func scheduleRetry(_ id: UUID, after delay: TimeInterval, context: ModelContext) {
        retryTimers[id]?.cancel()
        retryTimers[id] = Task {
            do { try await Task.sleep(for: .seconds(max(delay, 1))) } catch { return }
            retryTimers[id] = nil
            guard scriptTasks[id] == nil, fetchRequest(id, context: context) != nil else {
                // İstek beklerken silindiyse açık tutulan sistem görevi sahipsiz kalmasın.
                if scriptTasks[id] == nil, tasks[id] == nil { GenerationBackground.finish(id, success: false) }
                return
            }
            _ = try? await runScript(id, sources: nil, context: context, userInitiated: false, interactive: false)
        }
    }

    /// Sunucu motorlarında senaryo biter bitmez sahneler önceden üretilir (yalnız önizleme kapalıyken).
    static func prerender(for settings: PodcastSettings) -> ScriptPrerender? {
        // "Claude + Chirp"te sahne, Claude'un hazırladığı okunuşlarla istenir: önceden üretilen düz Chirp sesi kullanılmazdı.
        guard settings.usesServerSpeech, settings.engine != .claude, !previewBeforeVoicing else { return nil }
        let list = Pronunciations.all
        return ScriptPrerender(engine: settings.speechProvider, replacements: list.isEmpty ? nil : Array(list.prefix(40)))
    }

    static let previewKey = "podcast.previewBeforeVoicing"
    static var previewBeforeVoicing: Bool { UserDefaults.standard.bool(forKey: previewKey) }

    // MARK: - Sistem arka plan görevi (iOS 26+)

    /// Görevi açar; açılamazsa (uygulama etkin değil, gönderim reddedildi) ön plana dönünce yeniden denenmek üzere kaydeder.
    private func wantBackground(_ id: UUID, title: String, subtitle: String) {
        if GenerationBackground.isActive(id) || GenerationBackground.begin(id, title: title, subtitle: subtitle) {
            backgroundWanted[id] = nil
        } else {
            backgroundWanted[id] = (title: title, subtitle: subtitle)
        }
    }

    /// Ön plana dönünce: görevi istenip açılamamış ve hâlâ süren işler için sistem görevi açılır.
    private func adoptBackground() {
        guard !backgroundWanted.isEmpty else { return }
        for id in Array(backgroundWanted.keys) where tasks[id] == nil && scriptTasks[id] == nil { backgroundWanted[id] = nil }
        // Otomatik deneme bekleyen bölüm ilerleme bildiremez; görevi bekleme bitince ister (bkz. `resume`).
        let running = Set(tasks.keys).subtracting(retryUntil.keys).union(scriptTasks.keys)
        let candidates = BackgroundAdoption.candidates(wanted: Set(backgroundWanted.keys), running: running, active: GenerationBackground.active)
        for id in candidates {
            guard let wanted = backgroundWanted[id] else { continue }
            wantBackground(id, title: wanted.title, subtitle: wanted.subtitle)
            guard GenerationBackground.isActive(id) else { continue }
            let fraction = (phases[id] ?? drafts[id])?.fraction ?? 0
            GenerationBackground.update(id, fraction: fraction)
            // Sıradaki gerçek ilerleme bildirimine dek görev ilerlemesiz kalmasın.
            GenerationBackground.pulse(id, toward: fraction + 0.02)
        }
    }

    /// Otomatik yeniden deneme beklenirken: kısa beklemede sistem görevi "Bekleniyor" diye açık kalır (deneme
    /// kilitliyken de çalışsın). true = açık tutuldu; false ise çağıran görevi kapatır.
    private func holdBackground(_ id: UUID, title: String, delay: TimeInterval) -> Bool {
        guard RetryPolicy.keepsBackgroundTask(delay: delay), GenerationBackground.isActive(id) else { return false }
        GenerationBackground.hold(id, title: "Bekleniyor", subtitle: "\(title) · otomatik sürecek")
        return true
    }

    // MARK: - Duraklatma (BG görevi süresi doldu)

    private func pause(_ id: UUID) {
        // Süre dolma bildirimi uygulama ön plana döndükten SONRA da gelebilir: o zaman iş ön planda sürer, durdurulmaz.
        guard UIApplication.shared.applicationState != .active else { return }
        // Senaryo iki deneme arasında bekliyorsa (görev "Bekleniyor" diye açıktı) durdurulacak iş yoktur: işaretleri
        // tüketecek görev olmadığından eklenmez; sıradaki denemeyi zamanlayıcı başlatır.
        guard tasks[id] != nil || scriptTasks[id] != nil else { return }
        pausing.insert(id)
        paused.insert(id)
        tasks[id]?.cancel()
        scriptTasks[id]?.cancel()
    }

    /// Ön plana dönünce sistemce duraklatılan işleri sürdür. İptali henüz işlenmemiş görev varsa
    /// (askıya alınma iptalden hemen sonra geldi) o bitince sürdürülür; kimlik kaybolmaz.
    private func resumePaused() {
        guard !paused.isEmpty else { return }
        let ids = paused
        paused.removeAll()
        let context = AppDataStore.container.mainContext
        for id in ids {
            let running: Task<Void, Never>? = if let task = tasks[id] {
                Task { await task.value }
            } else if let task = scriptTasks[id] {
                Task { _ = await task.result }
            } else {
                nil
            }
            guard let running else {
                resumeStopped(id, context: context)
                continue
            }
            Task {
                await running.value
                resumeStopped(id, context: context)
            }
        }
    }

    private func resumeStopped(_ id: UUID, context: ModelContext) {
        // Bu arada yeniden arka plana düşüldüyse sonraki ön plana dönüşe kalır.
        guard UIApplication.shared.applicationState == .active else {
            paused.insert(id)
            return
        }
        if let episode = fetchEpisode(id, context: context) {
            if episode.canResume, !episode.needsApproval, !UserStoppedGenerations.contains(id) { resume(episode, context: context) }
        } else if fetchRequest(id, context: context) != nil {
            retryNow(id, context: context)
        }
    }

    // MARK: - #7 Önizleme ve onay

    /// "Seslendir": sunucu motorunda (podcast2) senaryo düzenlenmiş olabileceği için yeni iş belirteci alınır (hak düşmez).
    func approve(_ episode: Episode, context: ModelContext) async throws {
        guard episode.needsApproval, episode.script != nil, let settings = episode.settings else { return }
        if settings.usesServerSpeech, AppState.current?.serverSupports("podcast2") == true {
            // Belirteç gönderilen senaryoya bağlıdır: istek sürerken senaryo değiştiyse yenisi için yeniden istenir
            // (eski belirteçle render `job_token_invalid` alıp bölümü düşürürdü).
            var attempts = 0
            while true {
                let sent = episode.scriptData
                guard let script = episode.script else { return }
                let job = try await api.audioJob(.init(script: script, settings: settings, previousJobToken: episode.jobToken, purpose: "full"))
                guard episode.needsApproval, !episode.isDeleted, episode.modelContext != nil else { return }
                // Yeni belirteç zinciri sürdürür (sonraki istek hak düşürmez).
                episode.jobToken = job.jobToken
                episode.jobTokenExpiresAt = .now.addingTimeInterval(115 * 60)
                if episode.scriptData == sent { break }
                attempts += 1
                guard attempts < 3 else {
                    throw APIError(status: 0, code: "script_changed", message: "Senaryo onay sırasında değişti. Yeniden “Seslendir”e dokun.")
                }
            }
        }
        guard let script = episode.script else { return }
        episode.needsApproval = false
        episode.scenesTotal = script.flatScenes.count
        episode.scenesDone = 0
        try? context.save()
        resume(episode, context: context, userInitiated: true)
    }

    /// Önizlemede senaryoyu değiştirir (konu silme/sıralama, cilalama, konu yeniden deneme).
    func updateDraftScript(_ episode: Episode, _ edited: PodcastScript, context: ModelContext) {
        guard episode.needsApproval else { return }
        // Silinen/eklenen konular kelime ve süre tahminine yansır.
        let script = ScriptEditing.rescaled(edited)
        episode.scriptData = (try? JSONEncoder().encode(script)) ?? episode.scriptData
        episode.title = script.title
        episode.scenesTotal = script.flatScenes.count
        if var stats = episode.generationStats {
            stats.characters = script.totalCharacters
            stats.scenes = script.flatScenes.count
            episode.generationStats = stats
        }
        try? context.save()
    }

    /// #2: yazılamayan konuyu sunucuda yeniden yazdırır (hak düşmez) ve senaryoya yerleştirir.
    func retryChapter(_ episode: Episode, error chapterError: ChapterError, context: ModelContext) async throws {
        guard let jobID = ScriptJobMemory.jobID(for: episode.id) else {
            throw APIError(status: 0, code: "not_found", message: "Bu senaryonun sunucu işi artık yok; konu yeniden denenemez.")
        }
        try await api.scriptRetryChapter(jobId: jobID, index: chapterError.index)
        let episodeID = episode.id
        let result = try await ScriptJobClient.run(existingJobID: jobID, makeStart: {
            throw APIError(status: 404, code: "not_found", message: "Senaryo işi sunucuda bulunamadı.")
        }, onJob: { job in
            // İş bitti ya da kayboldu: kimlik bir daha kullanılmaz.
            if job == nil { ScriptJobMemory.save(nil, for: episodeID) }
        }, onProgress: { _ in })
        guard episode.needsApproval, !episode.isDeleted, episode.modelContext != nil, var script = episode.script else { return }
        let fresh = result.script
        // Sunucu konuyu yine yazamadıysa senaryo değişmez (iş `partial`a döner); indeksle başka konu seçilmez.
        if fresh.quality?.chapterErrors.contains(where: { $0.index == chapterError.index }) ?? false {
            let reason = fresh.quality?.chapterErrors.first { $0.index == chapterError.index }?.message
            throw APIError(status: 0, code: "chapter_failed",
                           message: "Konu yine yazılamadı." + (reason.map { " \($0)" } ?? "") + " Bu konu olmadan seslendirebilir ya da daha sonra yeniden deneyebilirsin.")
        }
        guard let chapter = ScriptEditing.retriedChapter(for: chapterError, in: fresh, local: script) else {
            // Yazılan konu güvenle eşlenemedi: yerel senaryo (düzenlemeler) korunur.
            throw APIError(status: 0, code: "chapter_unmatched", message: "Konu yeniden yazıldı ama senaryoya yerleştirilemedi.")
        }
        script = ScriptEditing.mergeRetriedChapter(chapter, serverIndex: chapterError.index, into: script, fresh: fresh)
        episode.jobToken = result.jobToken
        episode.jobTokenExpiresAt = .now.addingTimeInterval(115 * 60)
        updateDraftScript(episode, script, context: context)
        if fresh.quality?.chapterErrors.isEmpty ?? true { ScriptJobMemory.save(nil, for: episode.id) }
    }

    // MARK: - Seslendirme

    /// Kilitliyken de sürmesi için sistem görevi (iOS 26+) her başlatmada istenir; `userInitiated` geriye uyum için
    /// duruyor. Buraya ulaşan her başlatma kullanıcının "Durdur" işaretini kaldırır: otomatik çağıranlar (açılış
    /// planı, duraklatmadan dönüş) durdurulan bölümü kendileri eler.
    func resume(_ episode: Episode, context: ModelContext, userInitiated: Bool = false) {
        guard tasks[episode.id] == nil, episode.status == .generating else { return }
        // #7: onay bekleyen bölüm seslendirilmez.
        guard !episode.needsApproval else { return }
        UserStoppedGenerations.remove(episode.id)
        wantBackground(episode.id, title: "Podcast seslendiriliyor", subtitle: episode.title)
        episode.errorMessage = nil
        let id = episode.id
        tasks[id] = Task {
            var attempt = 0
            while !Task.isCancelled {
                let outcome = await render(episode, context: context, attempt: attempt)
                guard case let .retry(delay) = outcome else { break }
                // #4: kota/ağ hatası: bekle ve kendiliğinden sürdür (yalnız uygulama koşarken).
                retryUntil[id] = .now.addingTimeInterval(delay)
                do {
                    // Dilimli bekleme: `retryVoicingNow` bitiş anını öne çekince döngü en geç 1 sn içinde çıkar.
                    while let until = retryUntil[id], let wait = RetryWait.next(until: until, now: .now) {
                        try await Task.sleep(for: .seconds(wait))
                    }
                } catch {
                    // Bekleme sırasında iptal: duraklatma işareti burada tüketilir (sonraki "Durdur" yanlış dala girmesin).
                    _ = stoppedByCancel(episode, total: episode.scenesTotal, context: context)
                    break
                }
                retryUntil[id] = nil
                attempt += 1
                guard !episode.isDeleted, episode.modelContext != nil, episode.status == .generating else { break }
                // Uzun beklemede kapanan sistem görevi yeniden istenir (uygulama etkin değilse ön plana dönünce açılır).
                wantBackground(id, title: "Podcast seslendiriliyor", subtitle: episode.title)
            }
            tasks[id] = nil
            phases[id] = nil
            retryUntil[id] = nil
            backgroundWanted[id] = nil
            // Hangi yoldan çıkılırsa çıkılsın sistem görevi açık kalmaz (çoktan kapandıysa etkisiz).
            GenerationBackground.finish(id, success: false)
        }
    }

    /// "Şimdi dene": otomatik yeniden deneme beklemesi (kota/ağ) beklenmeden biter; bekleme yoksa etkisiz.
    func retryVoicingNow(_ episode: Episode) {
        if retryUntil[episode.id] != nil { retryUntil[episode.id] = .now }
    }

    /// Senaryoyu yeniden üretmeden, cihazda hazır olan WAV dosyalarını koruyarak devam eder.
    func recoverAudio(_ episode: Episode, context: ModelContext) {
        guard tasks[episode.id] == nil, episode.script != nil, episode.settings != nil else { return }
        episode.status = .generating
        // Eski belirteç `previousJobToken` olarak kullanılır (hak düşmez); yenisi istenir.
        if episode.settings?.usesServerSpeech == true { episode.jobTokenExpiresAt = .distantPast }
        episode.errorMessage = nil
        try? context.save()
        resume(episode, context: context, userInitiated: UIApplication.shared.applicationState == .active)
    }

    /// Sahne WAV dosyasının yolu (motor başına ayrı; üretim sürerken önizleme oynatıcısı da kullanır).
    static func sceneURL(_ episode: Episode, settings: PodcastSettings, index: Int) -> URL {
        if settings.engine.isNeuralOnDevice {
            return episode.directory.appending(path: LocalSpeech.cacheKey(settings) + String(format: "_scene_%04d.wav", index))
        }
        return settings.usesServerSpeech
            ? episode.directory.appending(path: settings.engine.rawValue + String(format: "_scene_%04d.wav", index))
            : EpisodeFiles.deviceSceneURL(episode: episode.id, index: index)
    }

    /// Baştan itibaren kesintisiz hazır sahneler (önizleme oynatıcısı için).
    static func readyScenes(_ episode: Episode) -> [(index: Int, url: URL)] {
        guard let script = episode.script, let settings = episode.settings else { return [] }
        var result: [(Int, URL)] = []
        for index in script.flatScenes.indices {
            let url = sceneURL(episode, settings: settings, index: index)
            guard FileManager.default.fileExists(atPath: url.path) else { break }
            result.append((index, url))
        }
        return result.map { (index: $0.0, url: $0.1) }
    }

    /// Öneri 2: senaryoyu koruyup sesi (yeni seslerle) baştan üretir. Mevcut ses yedeklenir:
    /// üretim başarısız olursa bölüm eski sesine döner; başarılı olursa yer imleri cümlelerine göre taşınır.
    func regenerateAudio(_ episode: Episode, settings: PodcastSettings, context: ModelContext) {
        guard tasks[episode.id] == nil, !editing.contains(episode.id), let script = episode.script,
              let audio = episode.audioURL, let timeline = episode.timeline else { return }
        if AppState.current?.player.episode?.id == episode.id { AppState.current?.player.close() }
        let id = episode.id
        // Yer imlerini cümle (tur) + cümle içi orana çevir.
        let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        var anchors: [UUID: RegenerationBackup.Anchor] = [:]
        for mark in marks {
            guard let i = timeline.turnIndex(at: mark.time), let turn = timeline.turns[safe: i] else { continue }
            anchors[mark.id] = .init(turn: i, ratio: (mark.time - turn.start) / max(turn.end - turn.start, 0.01))
        }
        let prev = episode.directory.appending(path: "podcast-prev.m4a")
        try? FileManager.default.removeItem(at: prev)
        guard (try? FileManager.default.moveItem(at: audio, to: prev)) != nil else { return }
        RegenerationBackup.save(.init(settingsData: episode.settingsData, timelineData: episode.timelineData,
                                      duration: episode.duration, audioFileName: episode.audioFileName ?? "podcast.m4a",
                                      anchors: anchors), for: id)
        for index in script.flatScenes.indices {
            try? FileManager.default.removeItem(at: Self.sceneURL(episode, settings: settings, index: index))
        }
        SceneMasters.invalidate(id)
        WordSync.invalidate(id)
        episode.settingsData = (try? JSONEncoder().encode(settings)) ?? episode.settingsData
        episode.status = .generating
        episode.scenesDone = 0
        episode.scenesTotal = script.flatScenes.count
        // Sesler değiştiği için yeni belirteç gerekir; eskisi `previousJobToken` olarak gider.
        episode.jobTokenExpiresAt = .distantPast
        episode.errorMessage = nil
        episode.audioIssues = []
        try? context.save()
        resume(episode, context: context)
    }

    func hasPreviousAudio(_ episode: Episode) -> Bool { RegenerationBackup.load(episode.id) != nil }

    /// Yeniden üretimi bırak ve önceki sese dön.
    func restorePreviousAudio(_ episode: Episode, context: ModelContext, message: String? = nil) {
        tasks[episode.id]?.cancel()
        guard let backup = RegenerationBackup.load(episode.id) else { return }
        let prev = episode.directory.appending(path: "podcast-prev.m4a")
        let target = episode.directory.appending(path: backup.audioFileName)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: prev, to: target)
        episode.settingsData = backup.settingsData
        episode.timelineData = backup.timelineData
        episode.duration = backup.duration
        episode.audioFileName = backup.audioFileName
        episode.status = .ready
        episode.jobToken = nil
        episode.errorMessage = message
        RegenerationBackup.clear(episode.id)
        UserStoppedGenerations.remove(episode.id)
        audioDidChange(episode)
        try? context.save()
        PodcastEvent.post(PodcastEvent.audioChanged, episodeID: episode.id)
    }

    /// Ses değişti: sürüm artar, sahne masterları ve kelime senkronu geçersizleşir.
    private func audioDidChange(_ episode: Episode) {
        episode.audioRevision += 1
        SceneMasters.invalidate(episode.id)
        WordSync.invalidate(episode.id)
    }

    /// Başarılı yeniden üretim sonrası: yer imlerini yeni zaman çizelgesine taşı, yedeği sil.
    private func finishRegeneration(_ episode: Episode, timeline: Timeline, context: ModelContext) {
        guard let backup = RegenerationBackup.load(episode.id) else { return }
        let id = episode.id
        let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
        for mark in marks {
            guard let anchor = backup.anchors[mark.id], let turn = timeline.turns[safe: anchor.turn] else { continue }
            mark.time = turn.start + anchor.ratio * (turn.end - turn.start)
        }
        try? FileManager.default.removeItem(at: episode.directory.appending(path: "podcast-prev.m4a"))
        RegenerationBackup.clear(id)
    }

    /// Öneri 3: tek sahneyi yeni turlarla değiştirir (gövde `SceneEditor.replace`'te).
    func replaceScene(_ episode: Episode, sceneIndex: Int, turns: [ScriptTurn], context: ModelContext) async throws {
        try await SceneEditor.replace(episode, sceneIndex: sceneIndex, turns: turns, context: context, generator: self)
    }

    /// Bölümde üretim ya da başka düzenleme yoksa işi kilit altında çalıştırır; meşgulse `busy` hatası.
    func withEditLock(_ episode: Episode, _ work: () async throws -> Void) async throws {
        guard tasks[episode.id] == nil, !editing.contains(episode.id) else {
            throw APIError(status: 0, code: "busy", message: "Bu bölümde başka bir işlem sürüyor. Bitince tekrar dene.")
        }
        editing.insert(episode.id)
        defer { editing.remove(episode.id) }
        try await work()
    }

    /// Öneri 10: bir konuyu bölümden çıkarır (ses, transkript, senaryo, notlar).
    func removeChapter(_ episode: Episode, chapterIndex: Int, context: ModelContext) async throws {
        guard var script = episode.script, let timeline = episode.timeline, let audio = episode.audioURL else { return }
        try await withEditLock(episode) {
            if AppState.current?.player.episode?.id == episode.id { AppState.current?.player.close() }
            let result = try await AudioEditor.removeChapter(audio: audio, timeline: timeline, chapterIndex: chapterIndex)
            if script.chapters.indices.contains(chapterIndex) { script.chapters.remove(at: chapterIndex) }
            let id = episode.id
            let delta = result.removed.upperBound - result.removed.lowerBound
            let marks = (try? context.fetch(FetchDescriptor<Bookmark>(predicate: #Predicate { $0.episodeID == id }))) ?? []
            for mark in marks {
                if result.removed.contains(mark.time) { context.delete(mark) }
                else if mark.time > result.removed.upperBound { mark.time -= delta }
            }
            episode.scriptData = (try? JSONEncoder().encode(script)) ?? episode.scriptData
            episode.timeline = result.timeline
            episode.duration = result.timeline.duration
            episode.scenesTotal = script.flatScenes.count
            episode.verification = nil
            episode.slides = nil
            audioDidChange(episode)
            try? context.save()
        }
        PodcastEvent.post(PodcastEvent.audioChanged, episodeID: episode.id)
    }

    /// Öneri 28 / #6: senaryoyu belgeyle (ilgili sayfalarla) karşılaştırıp şüpheli cümleleri işaretler (arka planda).
    func verify(_ episode: Episode, context: ModelContext) {
        guard let turns = episode.timeline?.turns, let script = episode.script, !script.sourceNotes.isEmpty else { return }
        let id = episode.id
        let notes = script.sourceNotes
        let pagesWanted = ScriptEditing.referencedPages(script)
        verifying.insert(id)
        verifyError[id] = nil
        verifyTasks[id]?.cancel()
        verifyTasks[id] = Task {
            defer {
                verifying.remove(id)
                verifyTasks[id] = nil
            }
            let pages = pagesWanted.isEmpty ? [] : await SourcePages.texts(for: episode, pages: pagesWanted, maxChars: 120_000, context: context)
            let request = VerifyRequest(sourceNotes: ServerText.prefix(notes, 15_000),
                                        turns: turns.prefix(400).map { VerifyTurn.make(index: $0.id, text: $0.text, page: $0.sourcePage) },
                                        pages: pages.isEmpty ? nil : Array(pages.prefix(40)))
            do {
                let issues = try await api.verifyScript(request)
                guard !Task.isCancelled, episode.modelContext != nil, !episode.isDeleted else { return }
                episode.verification = issues
                try? context.save()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                verifyError[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Kullanıcı "Durdur" dedi: bölüm `.generating` kalır ama açılışta/sekme dönüşünde kendiliğinden sürmez.
    func cancel(_ episode: Episode) {
        if tasks[episode.id] != nil { UserStoppedGenerations.insert(episode.id) }
        tasks[episode.id]?.cancel()
    }

    /// Bölümü siler. Üretim sürüyorsa önce görevin tamamen bitmesini bekler; böylece silinmiş modele
    /// yazılmaz ve uçuştaki sahne istekleri silinen klasörü yeniden oluşturmaz.
    func delete(_ episode: Episode, context: ModelContext) async {
        let id = episode.id
        for task in [tasks[id], verifyTasks[id]].compactMap({ $0 }) {
            task.cancel()
            await task.value
        }
        EpisodeFiles.remove(episode: id)
        SceneMasters.invalidate(id)
        WordSync.invalidate(id)
        RegenerationBackup.clear(id)
        ScriptJobMemory.save(nil, for: id)
        UserStoppedGenerations.remove(id)
        backgroundWanted[id] = nil
        // #48: bağlı kayıtlar. Not ve tekrar kartları gider; yoklama gider; çalışma kayıtları bölümsüz kalır.
        try? context.delete(model: Bookmark.self, where: #Predicate { $0.episodeID == id })
        try? context.delete(model: ReviewCard.self, where: #Predicate { $0.episodeID == id })
        try? context.delete(model: EpisodeProbe.self, where: #Predicate { $0.episodeID == id })
        for note in (try? context.fetch(FetchDescriptor<CornellNote>(predicate: #Predicate { $0.episodeID == id }))) ?? [] { note.episodeID = nil }
        for entry in (try? context.fetch(FetchDescriptor<MistakeEntry>(predicate: #Predicate { $0.episodeID == id }))) ?? [] { entry.episodeID = nil }
        for item in (try? context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate { $0.episodeID == id }))) ?? [] { item.episodeID = nil }
        for session in (try? context.fetch(FetchDescriptor<StudySession>(predicate: #Predicate { $0.episodeID == id }))) ?? [] { session.episodeID = nil }
        verifyError[id] = nil
        context.delete(episode)
        try? context.save()
        GenerationActivity.end(id, success: false, total: 0)
        GenerationBackground.finish(id, success: false)
        PodcastEvent.post(PodcastEvent.episodeDeleted, episodeID: id)
    }

    // MARK: - Seslendirme ve birleştirme

    private enum RenderOutcome { case finished, stopped, retry(TimeInterval) }

    /// Sahne üretiminin sonucu (görev grubundan ana aktöre).
    nonisolated private struct SceneOutcome: Sendable {
        var index: Int
        var issue: AudioIssue?
        var retook: Bool
        var wordTimes: [[Double]]?
    }

    private func render(_ episode: Episode, context: ModelContext, attempt: Int) async -> RenderOutcome {
        guard var script = episode.script, let settings = episode.settings else {
            fail(episode, "Bölüm verisi bozuk.", context: context)
            return .stopped
        }
        let id = episode.id
        let title = episode.title
        func sceneURL(_ index: Int) -> URL { Self.sceneURL(episode, settings: settings, index: index) }

        // #5: ses harcanmadan önce doğrula ve düzelt (yalnız hiç sahne yokken, oturumda bir kez).
        if !preVerified.contains(id), episode.verification == nil,
           !script.flatScenes.indices.contains(where: { FileManager.default.fileExists(atPath: sceneURL($0).path) }),
           UserDefaults.standard.object(forKey: "autoVerify") as? Bool ?? true,
           AppState.current?.serverSupports("podcast2") == true {
            preVerified.insert(id)
            phases[id] = .writingScript(ScriptProgress(stage: "check"))
            // Doğrulama + düzeltme 1–2 dk sürebilir: sistem görevi ilerleme görsün.
            let check = Phase.writingScript(ScriptProgress(stage: "check"))
            GenerationBackground.update(id, fraction: check.fraction, title: "Senaryo denetleniyor", subtitle: title)
            GenerationBackground.pulse(id, toward: Phase.voicing(done: 0, total: 1).fraction)
            script = await preVoiceVerify(episode, script: script, settings: settings, context: context)
            GenerationBackground.stopPulse(id)
            if Task.isCancelled { return stoppedByCancel(episode, total: script.flatScenes.count, context: context) }
        }

        let scenes = script.flatScenes
        let done = scenes.indices.filter { FileManager.default.fileExists(atPath: sceneURL($0).path) }
        episode.scenesDone = done.count
        episode.scenesTotal = scenes.count
        phases[id] = .voicing(done: done.count, total: scenes.count)
        reportVoicing(id, title: title, done: done.count, total: scenes.count)
        let pending = scenes.indices.filter { !done.contains($0) }
        let voiceStart = Date.now
        var issues = episode.audioIssues.filter { !pending.contains($0.scene) }
        var retakes = 0
        var wordTimes: [Int: [[Double]]] = [:]
        // #13: tanıma yalnız ön planda ve ayarı açıkken (varsayılan kapalı).
        let recognize = UserDefaults.standard.bool(forKey: "quality.asrCheck") && UIApplication.shared.applicationState == .active
        let engine = settings.engine
        let language = settings.language
        do {
            try await withBackgroundTime("device-speech") {
                if settings.usesServerSpeech {
                    // Öneri 9: sunucu motorlarında sahneler en fazla 3 paralel istekle üretilir.
                    if episode.jobToken == nil || (episode.jobTokenExpiresAt ?? .distantPast) < .now {
                        let job = try await api.audioJob(.init(script: script, settings: settings, previousJobToken: episode.jobToken, purpose: "full"))
                        episode.jobToken = job.jobToken
                        episode.jobTokenExpiresAt = .now.addingTimeInterval(115 * 60)
                        try context.save()
                    }
                    let token = episode.jobToken!
                    let api = self.api
                    let work = pending.map { index in (index, scenes[index].scene.turns, sceneURL(index)) }
                    try await withThrowingTaskGroup(of: SceneOutcome.self) { group in
                        var iterator = work.makeIterator()
                        func addNext() {
                            guard let (index, turns, url) = iterator.next() else { return }
                            group.addTask {
                                try await Self.voiceScene(api: api, token: token, index: index, turns: turns, url: url,
                                                          engine: engine, recognize: recognize, language: language)
                            }
                        }
                        for _ in 0..<3 { addNext() }
                        while let outcome = try await group.next() {
                            if let issue = outcome.issue { issues.append(issue) }
                            if outcome.retook { retakes += 1 }
                            if let times = outcome.wordTimes { wordTimes[outcome.index] = times }
                            episode.scenesDone += 1
                            phases[id] = .voicing(done: episode.scenesDone, total: scenes.count)
                            reportVoicing(id, title: title, done: episode.scenesDone, total: scenes.count)
                            try? context.save()
                            addNext()
                        }
                    }
                } else {
                    let dictionary = Pronunciations.all
                    for index in pending {
                        try Task.checkCancellation()
                        let turns = scenes[index].scene.turns
                        // #11/#12: sözlük ve Türkçe okunuş metin motora verilmeden önce (LocalSpeech değişmez).
                        let spoken = SpeakableText.prepare(turns, language: settings.language, dictionary: dictionary).turns
                        let data = WAV.encode(try await LocalSpeech.scene(turns: spoken, settings: settings))
                        try Task.checkCancellation()
                        let url = sceneURL(index)
                        try data.write(to: url, options: .atomic)
                        let check = await SceneQualityGate.evaluate(wav: url, turns: turns, engine: engine, recognize: recognize, language: language)
                        if !check.ok { issues.append(AudioIssue(scene: index, reasons: check.reasons)) }
                        if let times = check.wordTimes { wordTimes[index] = times }
                        episode.scenesDone += 1
                        phases[id] = .voicing(done: episode.scenesDone, total: scenes.count)
                        reportVoicing(id, title: title, done: episode.scenesDone, total: scenes.count)
                        try context.save()
                    }
                }
            }

            let mixStart = Date.now
            phases[id] = .mixing
            GenerationActivity.update(id, title: title, phase: "Birleştiriliyor", done: scenes.count, total: scenes.count, detail: "Sahneler birleştiriliyor",
                                      fraction: Phase.mixing.fraction)
            GenerationBackground.update(id, fraction: Phase.mixing.fraction, title: "Bölüm birleştiriliyor", subtitle: title)
            let inputs = scenes.enumerated().map { index, item in
                AudioStitcher.SceneInput(url: sceneURL(index), chapterIndex: item.chapterIndex, turns: item.scene.turns,
                                         wordTimes: wordTimes[index])
            }
            let output = episode.directory.appending(path: "podcast.m4a")
            GenerationBackground.pulse(id, toward: 0.99)
            // Sahne masterı birleştirmede kullanılan değerlerle işaretlenir (P4: sonraki sahne düzenlemesi aynı sesi verir).
            let design = SoundDesign.isEnabled
            let identity = SoundIdentity.resolve(settings.soundIdentity)
            let timeline = try await AudioStitcher.stitch(scenes: inputs, chapterTitles: script.chapters.map(\.title), output: output,
                                                          design: design, identity: identity)
            GenerationBackground.stopPulse(id)

            let regenerated = hasPreviousAudio(episode)
            episode.audioFileName = "podcast.m4a"
            episode.timeline = timeline
            episode.duration = timeline.duration
            episode.status = .ready
            episode.jobToken = nil
            episode.errorMessage = nil
            episode.audioIssues = issues.sorted { $0.scene < $1.scene }
            if regenerated { audioDidChange(episode) }
            if var stats = episode.generationStats {
                stats.voiceSeconds = (stats.voiceSeconds ?? 0) + mixStart.timeIntervalSince(voiceStart)
                stats.mixSeconds = Date.now.timeIntervalSince(mixStart)
                stats.retakes += retakes
                stats.scenes = scenes.count
                stats.characters = script.totalCharacters
                stats.estimatedCostUSD = GenerationCost.estimate(engine: settings.engine, characters: script.totalCharacters)
                episode.generationStats = stats
            }
            try? context.save()
            // "Durdur" son iptal denetiminden sonra geldiyse bölüm yine de biter; işaret kalmasın.
            UserStoppedGenerations.remove(id)
            GenerationActivity.end(id, success: true, total: scenes.count)
            GenerationBackground.finish(id, success: true)
            finishRegeneration(episode, timeline: timeline, context: context)
            // #10/#20: sahne WAV'ları silinmeden önce sahne masterı olarak saklanır.
            try? await SceneMasters.store(episodeID: id, scenes: scenes.indices.map(sceneURL), design: design, identity: identity)
            for index in scenes.indices {
                try? FileManager.default.removeItem(at: sceneURL(index))
            }
            PodcastEvent.post(regenerated ? PodcastEvent.audioChanged : PodcastEvent.episodeReady, episodeID: id)
            NotificationActions.post(.ready, episodeID: id, title: title)
            if episode.verification == nil, UserDefaults.standard.object(forKey: "autoVerify") as? Bool ?? true { verify(episode, context: context) }
            if UserDefaults.standard.bool(forKey: PodcastFeed.autoKey) { Task { try? await PodcastFeed.publish(episode) } }
            StudyMaterials.prepare(episode, context: context)
            startWordSyncIfForeground(episode, timeline: timeline, script: script)
            return .finished
        } catch is CancellationError {
            return stoppedByCancel(episode, total: scenes.count, context: context)
        } catch {
            // Yalnızca bütçe veya token gerçekten bittiyse kalıcı hata; geçici hatalar (ağ, kota) kendiliğinden sürer.
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if episode.canResume, !RetryPolicy.isFatalForAudio(error) {
                if RetryPolicy.shouldAutoRetry(error, attempts: attempt) {
                    let delay = RetryPolicy.delay(attempt: attempt, retryAfter: (error as? APIError)?.retryAfter)
                    episode.errorMessage = message + " Otomatik olarak yeniden denenecek."
                    try? context.save()
                    // Kısa beklemede sistem görevi açık kalır: kilitliyken tek bir geçici hata uygulamayı askıya aldırmasın.
                    if !holdBackground(id, title: title, delay: delay) { GenerationBackground.finish(id, success: false) }
                    GenerationActivity.update(id, title: title, phase: "Bekleniyor", done: episode.scenesDone, total: scenes.count,
                                              detail: "Ses hizmeti beklemede · otomatik sürecek",
                                              fraction: Phase.voicing(done: episode.scenesDone, total: scenes.count).fraction)
                    return .retry(delay)
                }
                GenerationBackground.finish(id, success: false)
                GenerationActivity.end(id, success: false, total: scenes.count)
                episode.errorMessage = message + " Kaldığı yerden devam edebilirsin."
                try? context.save()
                NotificationActions.post(.stalled(message), episodeID: id, title: title)
            } else {
                GenerationBackground.finish(id, success: false)
                GenerationActivity.end(id, success: false, total: scenes.count)
                fail(episode, message, context: context)
                NotificationActions.post(.failed(message), episodeID: id, title: title)
            }
            return .stopped
        }
    }

    private func stoppedByCancel(_ episode: Episode, total: Int, context: ModelContext) -> RenderOutcome {
        let id = episode.id
        GenerationActivity.end(id, success: false, total: total)
        GenerationBackground.finish(id, success: false)
        // İşaret her durumda tüketilir (bölüm silinmiş olsa da kümede kalmasın).
        let wasPausing = pausing.remove(id) != nil
        guard !episode.isDeleted, episode.modelContext != nil else { return .stopped }
        if wasPausing {
            episode.errorMessage = "Duraklatıldı. Uygulamayı açınca kaldığı yerden sürecek."
            // Uygulama zaten açıksa `resumePaused` bu görevin bitmesini bekleyip sürdürür; bildirim gereksiz.
            if UIApplication.shared.applicationState != .active {
                NotificationActions.post(.stalled("Duraklatıldı; uygulamayı açınca sürecek."), episodeID: id, title: episode.title)
            }
        } else {
            episode.errorMessage = "Seslendirme durduruldu. Kaldığı yerden devam edebilirsin."
        }
        try? context.save()
        return .stopped
    }

    private func reportVoicing(_ id: UUID, title: String, done: Int, total: Int) {
        let phase = Phase.voicing(done: done, total: total)
        GenerationActivity.update(id, title: title, phase: "Seslendiriliyor", done: done, total: total, detail: phase.progressText,
                                  fraction: phase.fraction)
        GenerationBackground.update(id, fraction: phase.fraction, title: "Seslendiriliyor", subtitle: "\(title) · \(phase.progressText)")
        // Uzun sahnede (cihaz içi motor) bir sonraki sahneye dek ilerleme azar azar artar.
        GenerationBackground.pulse(id, toward: Phase.voicing(done: min(done + 1, total), total: total).fraction)
    }

    /// "Claude + Chirp" sahnesinde okunuş hazırlığı yapılamadıysa sahnenin uyarısına eklenen neden (ses yine üretilir).
    nonisolated static let unpreparedReason = "Claude okunuş hazırlığı yapılamadı; sahne düz Chirp ile seslendirildi"

    /// Bir sahneyi sunucuda seslendirir; #13 kalite kapısından geçmezse bir kez `take: 1` ile yeniden ister.
    /// "Claude + Chirp"te önce sahnedeki formül ve kısaltmaların okunuşu Claude'a hazırlatılır; hazırlık yapılamazsa sahne
    /// düz Chirp ile seslendirilir ve bu, sahnenin uyarılarına yazılır (sessizce düşük kaliteye inilmesin).
    nonisolated private static func voiceScene(api: APIClient, token: String, index: Int, turns: [ScriptTurn], url: URL,
                                               engine: SpeechEngine, recognize: Bool, language: PodcastLanguage) async throws -> SceneOutcome {
        var request = TTSRequest(jobToken: token, sceneIndex: index,
                                 turns: turns.map { TTSTurn(speaker: $0.speaker, text: $0.text, style: $0.style) })
        var readings: [Pronunciation] = []
        var unprepared = false
        if engine == .claude {
            do { readings = try await api.speechReadings(request.turns, language: language) }
            catch is CancellationError { throw CancellationError() }
            catch { unprepared = true }
        }
        try await fetchScene(api: api, request: request, engine: engine, readings: readings, url: url)
        var check = await SceneQualityGate.evaluate(wav: url, turns: turns, engine: engine, recognize: recognize, language: language)
        var retook = false
        if !check.ok {
            request.take = 1
            try await fetchScene(api: api, request: request, engine: engine, readings: readings, url: url)
            check = await SceneQualityGate.evaluate(wav: url, turns: turns, engine: engine, recognize: recognize, language: language)
            retook = true
        }
        let reasons = (check.ok ? [] : check.reasons) + (unprepared ? [unpreparedReason] : [])
        return SceneOutcome(index: index, issue: reasons.isEmpty ? nil : AudioIssue(scene: index, reasons: reasons),
                            retook: retook, wordTimes: check.wordTimes)
    }

    nonisolated private static func fetchScene(api: APIClient, request: TTSRequest, engine: SpeechEngine, readings: [Pronunciation] = [], url: URL) async throws {
        let response = try await api.remoteTTS(request, engine: engine, readings: readings)
        guard let decoded = Data(base64Encoded: response.audio) else {
            throw APIError(status: 0, code: "audio", message: "Ses yanıtı okunamadı.")
        }
        _ = try WAV.parse(decoded)
        try Task.checkCancellation()
        try decoded.write(to: url, options: .atomic)
    }

    /// #20: bölüm hazır olunca (ön plandaysa) kelime senkronu.
    private func startWordSyncIfForeground(_ episode: Episode, timeline: Timeline, script: PodcastScript) {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: "wordSync.auto") as? Bool ?? true,
              timeline.duration <= 30 * 60, let audio = episode.audioURL else { return }
        let id = episode.id
        let language = episode.settings?.language
        Task { _ = await WordSync.prepare(episodeID: id, audioURL: audio, timeline: timeline, script: script, language: language) }
    }

    /// #5: doğrulama (ilgili sayfalarla) + yalnız sorunlu turların düzeltilmesi; düzeltme varsa yeni iş belirteci (hak düşmez).
    private func preVoiceVerify(_ episode: Episode, script: PodcastScript, settings: PodcastSettings, context: ModelContext) async -> PodcastScript {
        let id = episode.id
        guard !script.sourceNotes.isEmpty else { return script }
        let turns = ScriptEditing.allTurns(script)
        let wanted = ScriptEditing.referencedPages(script)
        let pages = wanted.isEmpty ? [] : await SourcePages.texts(for: episode, pages: wanted, maxChars: 120_000, context: context)
        let pageList: [PageText]? = pages.isEmpty ? nil : Array(pages.prefix(40))
        do {
            var issues = try await api.verifyScript(VerifyRequest(
                sourceNotes: ServerText.prefix(script.sourceNotes, 15_000),
                turns: turns.prefix(400).enumerated().map { VerifyTurn.make(index: $0.offset, text: $0.element.text, page: $0.element.sourcePage) },
                pages: pageList))
            try Task.checkCancellation()
            let fixable = issues.filter { $0.severity != "belirsiz" }
                .compactMap { issue in turns[safe: issue.index].flatMap { FixTurnsTurn.make(index: issue.index, turn: $0, issue: issue) } }
                .prefix(40).map { $0 }
            var result = script
            if !fixable.isEmpty {
                let fixed = try await api.fixTurns(FixTurnsRequest(
                    title: ServerText.prefix(script.title, 300), sourceNotes: ServerText.prefix(script.sourceNotes, 15_000), pages: pageList,
                    settings: FixTurnsSettings(settings),
                    turns: fixable))
                try Task.checkCancellation()
                result = ScriptEditing.applyFixes(fixed, to: script)
                issues = ScriptEditing.markingFixed(issues, turns: Set(fixed.map(\.index))) ?? issues
                if result != script {
                    episode.scriptData = (try? JSONEncoder().encode(result)) ?? episode.scriptData
                    if settings.usesServerSpeech {
                        let job = try await api.audioJob(.init(script: result, settings: settings, previousJobToken: episode.jobToken, purpose: "full"))
                        episode.jobToken = job.jobToken
                        episode.jobTokenExpiresAt = .now.addingTimeInterval(115 * 60)
                    }
                }
            }
            episode.verification = issues
            verifyError[id] = nil
            try? context.save()
            return result
        } catch is CancellationError {
            return script
        } catch {
            verifyError[id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Düzeltilmiş senaryo kaydedildi ama belirteç alınamadıysa, render eski belirteçle uyuşmaz: yenisi istenir.
            if episode.script != script { episode.jobTokenExpiresAt = .distantPast }
            try? context.save()
            return episode.script ?? script
        }
    }

    private func fail(_ episode: Episode, _ message: String, context: ModelContext) {
        if hasPreviousAudio(episode) {
            restorePreviousAudio(episode, context: context, message: "Yeni ses üretilemedi (\(message)); önceki ses geri yüklendi.")
            return
        }
        episode.status = .failed
        episode.errorMessage = message
        episode.jobToken = nil
        try? context.save()
    }

    /// Uygulama arka plana düşse bile işin kısa süre daha devam etmesini ister.
    /// Süre dolarsa görev hemen kapatılır (aksi halde sistem uygulamayı sonlandırır); iş, uygulama
    /// askıya alınınca kesilen istekler üzerinden hata verir ve kaldığı yerden sürdürülebilir.
    private func withBackgroundTime<T>(_ name: String, _ work: () async throws -> T) async rethrows -> T {
        let token = BackgroundTaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: name) { token.end() }
        defer { token.end() }
        return try await work()
    }
}

/// "Sesi yeniden üret" öncesi durum (UserDefaults'ta, bölüm başına).
nonisolated struct RegenerationBackup: Codable {
    struct Anchor: Codable { var turn: Int; var ratio: Double }
    var settingsData: Data
    var timelineData: Data?
    var duration: Double
    var audioFileName: String
    var anchors: [UUID: Anchor]

    private static func key(_ id: UUID) -> String { "regen.\(id.uuidString)" }
    static func save(_ backup: RegenerationBackup, for id: UUID) { UserDefaults.standard.set(try? JSONEncoder().encode(backup), forKey: key(id)) }
    static func load(_ id: UUID) -> RegenerationBackup? { UserDefaults.standard.data(forKey: key(id)).flatMap { try? JSONDecoder().decode(RegenerationBackup.self, from: $0) } }
    static func clear(_ id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }
}
