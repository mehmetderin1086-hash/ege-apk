import PhotosUI
import SwiftData
import SwiftUI
import UserNotifications
import VisionKit

struct NewPodcastView: View {
    var onCreated: (Episode) -> Void

    @Environment(GenerationCoordinator.self) private var generator
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @AppStorage("lastSettings") private var lastSettingsData = Data()
    @State private var sources: [ImportedSource] = []
    @State private var settings = PodcastSettings()
    @State private var step = Step.sources
    @State private var error: String?
    /// "Ders Podcast’te aç" ile gelen dosyalardan yüklenemeyenler (kaynak adımında gösterilir).
    @State private var importError: String?
    /// #4: geçici hatada istek kuyruğa düştü (otomatik yeniden denenecek).
    @State private var queuedMessage: String?
    @State private var compare = false
    @State private var makeSeries = false
    @State private var seriesName = ""
    @State private var seriesProgress: (current: Int, total: Int)?
    /// Yarıda kalan seri: "tekrar dene" aynı seriye kaldığı kaynaktan devam eder (önceki bölümler yeniden üretilmez).
    @State private var seriesRun: SeriesRun?
    /// İzlenen taslak (`generator.drafts`); eşzamanlı başka üretimler bu ekranı etkilemez (#50).
    @State private var draftID: UUID?
    /// "Arka planda sürsün": ekran kapandı; bölüm oluşunca açılmaz, kütüphanede görünür.
    /// Görev ekran kapandıktan sonra da okuduğu için başvuru kutusu (State değeri değil).
    @State private var detached = DetachFlag()

    final class DetachFlag { var value = false }

    struct SeriesRun {
        let id = UUID()
        var name: String
        var titles: [String] = []
        /// Bölüm sırasıyla kuyruk istekleri (= ileride oluşacak bölüm kimlikleri); seri başlarken hepsi kuyruğa yazılır.
        var requestIDs: [UUID] = []
        /// Serinin kurulduğu kaynaklar (sırayla); liste değiştiyse seri sürdürülmez (bkz. `resumesSeries`).
        var sourceIDs: [UUID] = []
        var firstEpisodeID: UUID?
    }
    @State private var task: Task<Void, Never>?

    enum Step { case sources, customize, generating }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .sources:
                    SourcesStep(sources: $sources, incomingError: importError, quick: {
                        // Tek dokunuş: kayıtlı ayarlar, belgeye göre süre; ayar adımı atlanır.
                        importError = nil
                        generate()
                    }) {
                        importError = nil
                        step = .customize
                    }
                case .customize:
                    CustomizeStep(settings: $settings, sourceCount: sources.count, autoMinutes: PodcastAuto.duration(sources),
                                  makeSeries: $makeSeries, seriesName: $seriesName, compare: $compare) { generate() }
                case .generating:
                    GeneratingStep(error: error, queued: queuedMessage, settings: settings, seriesProgress: seriesProgress, draftID: draftID,
                                   onBackground: {
                                       detached.value = true
                                       dismiss()
                                   },
                                   onClose: { dismiss() }) {
                        step = .customize
                        error = nil
                        queuedMessage = nil
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        task?.cancel()
                        cancelQueuedSeries()
                        dismiss()
                    }
                }
                if step == .customize {
                    ToolbarItem(placement: .navigation) {
                        Button("Geri", systemImage: "chevron.left") { step = .sources }
                    }
                }
            }
        }
        .interactiveDismissDisabled(step == .generating && error == nil && queuedMessage == nil)
        .onChange(of: settings.scriptAI) { _, _ in
            if let data = try? JSONEncoder().encode(settings.reusable) { lastSettingsData = data }
        }
        .onAppear {
            settings = Self.initialSettings(saved: lastSettingsData, maxQuality: QualityMode.isMax).withAppVoice
            importIncomingFiles()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-p3Customize"), sources.isEmpty {
                sources = [ImportedSource(name: "Biyoloji notu", kind: .text(String(repeating: "Hücre bölünmesi mitoz ve mayoz. ", count: 20)))]
                step = .customize
            }
            if P3Demo.sourcesRequested, sources.isEmpty { sources = Self.demoSources() }
            #endif
        }
        .onChange(of: app.incomingFiles) { _, _ in importIncomingFiles() }
    }

    private var title: String {
        switch step {
        case .sources: "Kaynak ekle"
        case .customize: "Podcast ayarları"
        case .generating: "Hazırlanıyor"
        }
    }

    private func generate() {
        // lastSettings yalnız yeniden kullanılabilir ayarlarla yazılır (seri, yönerge, türev bölüme özgüdür).
        // Süre belgeye göre seçilsin isteniyorsa kaynakların uzunluğundan hesaplanır.
        if PodcastAuto.autoDuration { settings.durationMin = PodcastAuto.duration(sources) }
        lastSettingsData = (try? JSONEncoder().encode(settings.reusable)) ?? Data()
        error = nil
        queuedMessage = nil
        seriesProgress = nil
        let series = makeSeries && sources.count > 1 && !compare
        // Kalıcı hatayla yarıda kalan seri bu kez sürdürülmüyorsa (kaynaklar değişti ya da seri kapatıldı) kuyrukta
        // kalan bölümleri yeni üretimin yanında ikinci kez üretilmesin; oluşmuş bölümlere dokunulmaz.
        if let run = seriesRun, !Self.resumesSeries(runSources: run.sourceIDs, current: sources.map(\.id), wantsSeries: series) {
            removeQueued(run)
        }
        step = .generating
        // #46: bitiş/takılma bildirimi için izin (ön planda, kullanıcı dokunuşuyla; yalnız ilk seferde sorulur).
        Task { _ = await NotificationGate.request(UNUserNotificationCenter.current(), options: [.alert, .sound]) }
        let flag = detached
        flag.value = false
        task = Task {
            do {
                let episode: Episode
                if series {
                    episode = try await generateSeries()
                } else {
                    let id = UUID()
                    draftID = id
                    let used = sources
                    episode = try await generator.start(sources: used, settings: effectiveSettings, context: context,
                                                        userInitiated: true, requestID: id,
                                                        onDocuments: { adopt($0, for: used) })
                }
                if !flag.value { onCreated(episode) }
            } catch is CancellationError {
            } catch let queued as GenerationQueuedError {
                queuedMessage = queued.localizedDescription
            } catch {
                self.error = error.localizedDescription + queuedSeriesNote
            }
        }
    }
}

extension NewPodcastView {
    /// Karşılaştırma modu (öneri 18): tartışma biçimi + kaynakları karşılaştırma talimatı.
    fileprivate var effectiveSettings: PodcastSettings { Self.effective(settings, compare: compare && sources.count > 1, sourceNames: sources.map(\.name)) }

    /// #50: maks kalite yalnız kayıtlı ayar yokken uygulanır (kullanıcının kayıtlı seçimini ezmez).
    static func initialSettings(saved: Data, maxQuality: Bool) -> PodcastSettings {
        if let decoded = try? JSONDecoder().decode(PodcastSettings.self, from: saved) {
            var s = decoded.reusable
            s.focus = nil
            return s
        }
        let fresh = PodcastSettings()
        return maxQuality ? QualityMode.apply(to: fresh) : fresh
    }

    /// #1: uygulamanın senaryo notları (kaynak karşılaştırma, şekil/tablo anlatımı, iki dilli) `directives`'e yazılır;
    /// kullanıcının `customInstructions`'ı ayrı ve dokunulmadan kalır (sunucu ≤500).
    static func effective(_ settings: PodcastSettings, compare: Bool, sourceNames: [String],
                          narrateFigures: Bool = UserDefaults.standard.object(forKey: "narrateFigures") as? Bool ?? true,
                          bilingual: Bool = UserDefaults.standard.bool(forKey: "bilingual"),
                          schoolExam: Bool = PodcastAuto.schoolExam) -> PodcastSettings {
        var s = settings
        var notes: [String] = []
        if schoolExam { notes.append(PodcastAuto.schoolDirective) }
        if compare {
            if s.format.usesTwoHosts { s.format = .tartisma }
            notes.append("KAYNAK KARŞILAŞTIRMASI: Kaynakları (\(sourceNames.joined(separator: ", "))) karşılaştır. Ortak noktaları, farklılıkları ve varsa çelişkileri açıkça tartış; her iddiada hangi kaynaktan geldiğini adıyla söyle. Bir kaynağı diğerine üstün tutma, belgede olanı aktar.")
        }
        if narrateFigures {
            notes.append("ŞEKİL VE TABLOLAR: Belgedeki grafik, şema, diyagram ve tabloları atlama; dinleyici göremediği için ne gösterdiklerini sözle anlat (eksenler, eğilim, en önemli değerler, satır-sütun karşılaştırması). Tablodaki tüm sayıları tek tek okuma, anlamlı olanları seç.")
        }
        if s.language == .en, bilingual {
            notes.append("İKİ DİLLİ ANLATIM: Senaryo İngilizce. Ancak \(s.hostB.name) (B) önemli terimlerden ve zor cümlelerden sonra kısa Türkçe açıklama yapar (\"Yani Türkçesiyle…\" gibi). Türkçe kısımlar konuşmanın en fazla beşte biri olsun; terimin İngilizcesini de tekrar et.")
        }
        s.directives = s.directives.filter { !notes.contains($0) } + notes
        return s
    }

    /// Kalıcılaştırılan belge kimlikleri kaynaklara geri yazılır: kalıcı hatadan sonra ("Ayarlara dön") yeniden
    /// denemede `DocumentLibrary.persist` yeni belge ve dosya kopyası oluşturmaz, yalnız `lastUsedAt` günceller.
    static func adoptingDocumentIDs(_ ids: [UUID?], for used: [ImportedSource], in sources: [ImportedSource]) -> [ImportedSource] {
        var result = sources
        for (source, documentID) in zip(used, ids) {
            guard let documentID, let i = result.firstIndex(where: { $0.id == source.id }) else { continue }
            result[i].documentID = documentID
            // Aynı PDF'in henüz kaydedilmemiş öbür parçaları (bölümlere ayrılmış kitap) da bu belgeyi kullanır: seri
            // akışında her parça için kitabın tamamı yeniden kopyalanmaz.
            guard case let .pdf(url, _) = result[i].kind else { continue }
            for j in result.indices where result[j].documentID == nil {
                if case let .pdf(other, _) = result[j].kind, other == url { result[j].documentID = documentID }
            }
        }
        return result
    }

    fileprivate func adopt(_ ids: [UUID?], for used: [ImportedSource]) {
        let updated = Self.adoptingDocumentIDs(ids, for: used, in: sources)
        if updated != sources { sources = updated }
    }

    /// #1/#31: seri bağlamı (`index` 1 tabanlı). Kullanıcı talimatı ayrı kalır.
    static func seriesSettings(_ base: PodcastSettings, seriesID: UUID, name: String, index: Int, total: Int,
                               previousTitles: [String], previousKeyPoints: [String]) -> PodcastSettings {
        var s = base
        s.series = SeriesContext(id: seriesID, name: name, index: index, total: total,
                                 previousTitles: previousTitles, previousKeyPoints: Array(previousKeyPoints.prefix(12)))
        return s
    }

    /// Serinin bölüm ayarları (saf; test edilir): bölüm j → `index` j+1, `total` = bölüm sayısı. Önceki başlıklar ve
    /// ana fikirler boş bırakılır; her bölüm yazılmaya başlarken tazelenir (`OfflineQueue.refreshedSeries`).
    static func seriesPlan(_ base: PodcastSettings, count: Int, seriesID: UUID, name: String) -> [PodcastSettings] {
        (0..<max(count, 0)).map {
            seriesSettings(base, seriesID: seriesID, name: name, index: $0 + 1, total: count, previousTitles: [], previousKeyPoints: [])
        }
    }

    /// Serinin bütün bölümlerini baştan kuyruğa yazar (test edilir): kaynak j, `plan[j]` ayarlarıyla bekleyen ayrı bir
    /// istek olur. İstek kimlikleri (bölüm sırasıyla) ve belge kimlikleri işlenmiş kaynaklar döner. Her parça listenin
    /// güncel kopyasından okunur: önceki parçanın kalıcılaşan belge kimliği aynı PDF'in sonraki parçalarına da
    /// yazılmıştır (bölümlere ayrılmış kitap bir kez kopyalanır).
    static func enqueueSeries(_ sources: [ImportedSource], plan: [PodcastSettings],
                              context: ModelContext) -> (requestIDs: [UUID], sources: [ImportedSource]) {
        var used = sources
        var requestIDs: [UUID] = []
        for (j, settings) in zip(sources.indices, plan) {
            let source = used[j]
            let request = OfflineQueue.insert(sources: [source], settings: settings, context: context, state: QueueState.waiting,
                                              onDocuments: { used = adoptingDocumentIDs($0, for: [source], in: used) })
            requestIDs.append(request.id)
        }
        return (requestIDs, used)
    }

    /// Her kaynak ayrı bölüm. Bütün bölümler baştan kuyruğa yazılır: uygulama kapanırsa kalanlar kaybolmaz, kuyruk
    /// seri sırasıyla sürdürür. Ekran açıkken bölümler buradan sırayla başlatılır ve izlenir. İlk bölüm döner.
    fileprivate func generateSeries() async throws -> Episode {
        // Ekran kapandıktan sonra ("Arka planda sürsün") ortam değerleri okunmasın.
        let context = self.context, generator = self.generator
        try GenerationCoordinator.validate(settings)
        let base = Self.effective(settings, compare: false, sourceNames: [])
        if let run = seriesRun {
            // Yeniden deneme ("Ayarlara dön" sonrası): henüz sunucuya gitmemiş isteklere güncel ayarlar yazılır.
            let plan = Self.seriesPlan(base, count: run.requestIDs.count, seriesID: run.id, name: run.name)
            for (j, id) in run.requestIDs.enumerated() where j >= run.titles.count && !generator.isScripting(id) {
                guard let request = Self.queuedRequest(id, context: context), request.serverJobID == nil, let fresh = plan[safe: j] else { continue }
                request.settingsData = (try? JSONEncoder().encode(fresh)) ?? request.settingsData
                // Kaynağın adı ya da sayfa aralığı da değişmiş olabilir (kimliği aynı kalır): istek eski aralıkla sürmesin.
                guard let source = sources[safe: j], source.id == run.sourceIDs[safe: j] else { continue }
                request.title = OfflineQueue.title(for: [source], settings: fresh)
                request.sourceNames = [source.name]
                QueuedPageRanges.save([source], documentIDs: [request.documentIDs.first], for: id)
            }
            try? context.save()
        } else {
            let used = sources
            let name = seriesName.trimmingCharacters(in: .whitespaces).isEmpty ? (used.first?.name ?? "Seri") : seriesName
            var run = SeriesRun(name: name)
            run.sourceIDs = used.map(\.id)
            let plan = Self.seriesPlan(base, count: used.count, seriesID: run.id, name: name)
            let queued = Self.enqueueSeries(used, plan: plan, context: context)
            run.requestIDs = queued.requestIDs
            // Kalıcılaşan belge kimlikleri kaynaklara geri yazılır (bkz. `adopt`).
            if queued.sources != sources { sources = queued.sources }
            seriesRun = run
        }
        guard var run = seriesRun else { throw CancellationError() }
        for (i, id) in run.requestIDs.enumerated() where i >= run.titles.count {
            try Task.checkCancellation()
            seriesProgress = (i + 1, run.requestIDs.count)
            draftID = id
            do {
                // Bölüm oluşunca `applyContext` seri kimliğini, adını ve sırasını atar. Kuyruk işleyicisi bölümü
                // çoktan başlattıysa aynı yazıma katılınır; bitirdiyse hazır bölüm döner.
                let episode = try await generator.startQueued(id, context: context)
                run.titles.append(episode.title)
                if run.firstEpisodeID == nil { run.firstEpisodeID = episode.id }
                seriesRun = run
            } catch let queued as GenerationQueuedError {
                // Bu bölüm ve kalanlar zaten kuyrukta: seri sırasıyla, kendiliğinden işlenir.
                seriesRun = nil
                seriesProgress = nil
                throw queued
            }
        }
        seriesProgress = nil
        seriesRun = nil
        let firstID = run.firstEpisodeID
        guard let firstID,
              let first = try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == firstID })).first
        else { throw CancellationError() }
        return first
    }

    fileprivate static func queuedRequest(_ id: UUID, context: ModelContext) -> QueuedRequest? {
        try? context.fetch(FetchDescriptor<QueuedRequest>(predicate: #Predicate { $0.id == id })).first
    }

    /// Seride kalıcı hata: o bölüm kuyrukta "Başarısız" kalır, sonraki bölümler kuyrukta sürer.
    fileprivate var queuedSeriesNote: String {
        guard seriesProgress != nil, let run = seriesRun, run.titles.count + 1 < run.requestIDs.count else { return "" }
        return " Kalan bölümler kuyrukta sürüyor; Kütüphane'deki kuyruktan izleyebilir ya da silebilirsin."
    }

    /// Seri yazılırken "Vazgeç": henüz bölüme dönüşmemiş istekler kuyruktan silinir; o an yazılan da iptal edilir
    /// (yazımı kuyruk işleyicisi başlatmış olabilir, bu ekranın görevinin iptali ona ulaşmaz).
    fileprivate func cancelQueuedSeries() {
        guard Self.cancelsQueuedSeries(generating: step == .generating, failed: error != nil, queued: queuedMessage != nil,
                                       inProgress: seriesProgress != nil), let run = seriesRun else { return }
        removeQueued(run)
    }

    /// "Vazgeç" serinin kuyruktaki bölümlerini de siler mi (saf; test edilir): yalnız seri yazılırken. Kalıcı hata ya da
    /// kuyruğa düşme ekranında kalan bölümler kuyrukta sürer (kullanıcıya öyle söylenmiştir); "Vazgeç" yalnız kapatır.
    static func cancelsQueuedSeries(generating: Bool, failed: Bool, queued: Bool, inProgress: Bool) -> Bool {
        generating && !failed && !queued && inProgress
    }

    /// Serinin kuyrukta kalan (henüz bölüme dönüşmemiş) istekleri silinir; o an yazılan da iptal edilir.
    fileprivate func removeQueued(_ run: SeriesRun) {
        let queued = (try? context.fetch(FetchDescriptor<QueuedRequest>())) ?? []
        for request in Self.queuedSeriesRequests(queued, requestIDs: run.requestIDs) { OfflineQueue.remove(request, context: context) }
        seriesRun = nil
    }

    /// Kuyruktan silinecekler (saf; test edilir): yalnız bu serinin istekleri. Bölüme dönüşen istek kuyrukta olmadığı
    /// için oluşmuş bölümlere, kimliği seride olmayan başka isteklere de dokunulmaz.
    static func queuedSeriesRequests(_ queued: [QueuedRequest], requestIDs: [UUID]) -> [QueuedRequest] {
        queued.filter { requestIDs.contains($0.id) }
    }

    /// Yarıda kalan seri sürdürülür mü (saf; test edilir): yalnız yine seri isteniyorsa ve kaynak listesi sırasıyla aynıysa.
    /// Aksi hâlde yeni üretim baştan kurulur ve eski serinin kuyrukta kalan bölümleri silinir.
    static func resumesSeries(runSources: [UUID], current: [UUID], wantsSeries: Bool) -> Bool {
        wantsSeries && runSources == current
    }

    fileprivate func importIncomingFiles() {
        guard !app.incomingFiles.isEmpty else { return }
        let loaded = DocumentLoader.loadAll(app.incomingFiles)
        sources += loaded.sources
        importError = loaded.errors.isEmpty ? nil : loaded.errors.joined(separator: "\n")
        app.incomingFiles = []
        // Üretim sürerken ilerleme ekranını bozma; dosyalar listede bekler.
        if step != .generating { step = .sources }
    }

    #if DEBUG
    /// Yalnızca Debug (`-p3Sources[=N]`): kaynak adımını seçicisiz denetlemek için uzun adlı iki metin, 120 sayfalık
    /// bir PDF ve N (varsayılan 3) fotoğraf. `-p3Sources=21` görsel sınırı uyarısını gösterir.
    static func demoSources() -> [ImportedSource] {
        var sources = [
            ImportedSource(name: "Biyoloji 11 Ders Kitabı · 3. Ünite: Hücre Bölünmeleri ve Kalıtımın Genel İlkeleri",
                           kind: .text(String(repeating: "Mitoz ve mayoz. ", count: 30))),
            ImportedSource(name: "Biyoloji 11 Ders Kitabı · 4. Ünite: Ekosistem Ekolojisi ve Güncel Çevre Sorunları",
                           kind: .text(String(repeating: "Ekosistem ve madde döngüleri. ", count: 30))),
        ]
        let pdf = URL.temporaryDirectory.appending(path: "p3-ornek-kitap.pdf")
        let pages = 120
        let wrote: Void? = try? UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 400)).writePDF(to: pdf) { context in
            for page in 1...pages {
                context.beginPage()
                ("Sayfa \(page)" as NSString).draw(at: CGPoint(x: 24, y: 24), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
            }
        }
        if wrote != nil { sources.append(ImportedSource(name: "Örnek kitap", kind: .pdf(pdf, pageCount: pages))) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        }.jpegData(compressionQuality: 0.7)
        guard let photo else { return sources }
        for _ in 0..<min(max(DebugArg.value("p3Sources").flatMap { Int($0) } ?? 3, 0), 40) {
            sources.append(ImportedSource(name: SourceNaming.next("Fotoğraf", existing: sources.map(\.name)), kind: .image(photo),
                                          thumbnailData: DocumentLoader.thumbnailJPEG(photo)))
        }
        return sources
    }
    #endif
}

// MARK: - 1. Kaynaklar

private struct SourcesStep: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var sources: [ImportedSource]
    /// Başka uygulamadan gelen dosyaların yükleme hatası (üst görünüm tutar; "Devam"da temizlenir).
    var incomingError: String? = nil
    /// Ayar adımını atlayıp hemen üretir.
    var quick: () -> Void = {}
    var next: () -> Void

    @State private var showFiles = false
    @State private var showScanner = false
    @State private var showLink = false
    @State private var showRecord = false
    @State private var showLibrary = false
    @State private var showHandwriting = false
    @State private var photoItems: [PhotosPickerItem] = []
    /// Süren içe aktarma sayısı (fotoğraf ve tarama üst üste binebilir; biri bitince "Devam" erken açılmasın).
    @State private var importsInFlight = 0
    private var loading: Bool { importsInFlight > 0 }
    @State private var error: String?
    /// PDF içindekiler tablosu, dosya başına bir kez okunur (gövdede her çizimde PDF açılmasın).
    @State private var outlines: [URL: [(title: String, range: ClosedRange<Int>)]] = [:]
    @State private var makeSeries = false
    @State private var seriesName = ""
    @State private var seriesProgress: (current: Int, total: Int)?
    /// Yarıda kalan seri: "tekrar dene" aynı seriye kaldığı kaynaktan devam eder (önceki bölümler yeniden üretilmez).
    @State private var seriesRun: SeriesRun?

    struct SeriesRun {
        let id = UUID()
        var name: String
        var titles: [String] = []
        var firstEpisodeID: UUID?
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OkuSectionHeading(title: "Neyi dinlemek istersin?", detail: "Önce kaynağını ekle, sonra anlatım biçimini seç.")
                    VStack(spacing: 0) {
                        Button { showFiles = true } label: {
                            OkuRouteLabel(title: "Dosya ekle", detail: "PDF, Word veya ders notu", symbol: "doc")
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 72)
                        PhotosPicker(selection: $photoItems, maxSelectionCount: remainingImages, matching: .images) {
                            OkuRouteLabel(title: "Fotoğraf seç", detail: "Kitap sayfası veya notların", symbol: "photo")
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 72)
                        Button { showLink = true } label: {
                            OkuRouteLabel(title: "Bağlantı ekle", detail: "Web sayfası veya YouTube", symbol: "link")
                        }.buttonStyle(.plain)
                    }.okuSurface()
                    DisclosureGroup("Tarama, ses kaydı ve kayıtlı belgeler") {
                        VStack(spacing: 0) {
                            Button { showScanner = true } label: {
                                OkuRouteLabel(title: "Belge tara", detail: "Kamerayla birden çok sayfa", symbol: "doc.viewfinder")
                            }.buttonStyle(.plain).disabled(!VNDocumentCameraViewController.isSupported)
                            Button { showRecord = true } label: {
                                OkuRouteLabel(title: "Ders kaydı", detail: "Ses kaydet veya ses dosyası seç", symbol: "mic")
                            }.buttonStyle(.plain)
                            Button { showLibrary = true } label: {
                                OkuRouteLabel(title: "Belgelerim", detail: "Önceden eklediğin bir kaynağı kullan", symbol: "tray.full")
                            }.buttonStyle(.plain)
                        }
                    }.font(.subheadline).padding(16).okuSurface()

                    if loading {
                        HStack { ProgressView(); Text("Ekleniyor…").foregroundStyle(.secondary) }
                    }
                    if let shown = Self.joined(incomingError, error) {
                        Label(shown, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    if sources.contains(where: \.isImage) {
                        Button {
                            showHandwriting = true
                        } label: {
                            Label("Fotoğrafları metne çevir ve doğrula (el yazısı için)", systemImage: "text.viewfinder")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.bordered)
                    }

                    if !sources.isEmpty {
                        Text("Eklenen kaynaklar")
                            .font(.headline)
                            .padding(.top, 4)
                        VStack(spacing: 10) {
                            ForEach($sources) { $source in
                                let id = source.id
                                SourceRow(source: $source, canMoveUp: id != sources.first?.id, canMoveDown: id != sources.last?.id,
                                          move: { sources = sources.moving(id: id, by: $0) },
                                          remove: { sources.removeAll { $0.id == id } })
                                if case let .pdf(url, _) = source.kind, source.pageRange == nil, let parts = outlines[url], parts.count >= 2 {
                                    Button {
                                        split(source, into: parts)
                                    } label: {
                                        Label("İçindekilere göre \(parts.count) bölüme ayır", systemImage: "rectangle.split.3x1")
                                            .font(.caption.bold())
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            if sources.count > 1 {
                                Text("Birden fazla kaynak var: sonraki adımda \"Her kaynağı ayrı bölüm yap (seri)\" ile her biri ayrı bölüm olur. Sıra bölüm sırasını belirler; satırdaki ⋯ menüsünden değiştirebilirsin.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(16)
            }

            let limit = SourceLimits.problem(for: sources)
            VStack(alignment: .leading, spacing: 10) {
                if let limit {
                    Label(limit, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Button(action: quick) {
                    Label(sources.isEmpty ? "Kaynak ekle" : "Hemen oluştur · ≈\(PodcastAuto.duration(sources)) dk", systemImage: "bolt.fill").lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(PrimaryButtonStyle(enabled: !sources.isEmpty && limit == nil))
                .disabled(sources.isEmpty || loading || limit != nil)
                .accessibilityHint("Kayıtlı ayarlarla ve belgeye göre seçilen süreyle üretir")
                // İkincil ve tek satır: dar ekranda kaynak ızgarasını örtmesin.
                Button(action: next) {
                    Label("Ayarları değiştir · \(sources.count) kaynak", systemImage: "slider.horizontal.3").font(.subheadline).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .disabled(sources.isEmpty || loading || limit != nil)
            }
            .padding(16)
        }
        .task(id: sources.map(\.id)) {
            for source in sources {
                guard case let .pdf(url, _) = source.kind, outlines[url] == nil else { continue }
                outlines[url] = BookSplitter.chapters(of: url)
                await Task.yield()
            }
        }
        .sheet(isPresented: $showLink) { LinkImportSheet { sources.append($0) } }
        .sheet(isPresented: $showRecord) { LectureRecordSheet { sources.append($0) } }
        .sheet(isPresented: $showLibrary) {
            DocumentLibraryView { docs in
                sources += docs.compactMap(DocumentLibrary.importedSource)
            }
        }
        .sheet(isPresented: $showHandwriting) {
            HandwritingReviewSheet(images: sources.filter(\.isImage)) { text in
                sources.removeAll(where: \.isImage)
                sources.append(text)
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: DocumentLoader.importTypes, allowsMultipleSelection: true) { result in
            error = nil
            switch result {
            case let .success(urls):
                // Çoklu seçimde her dosyanın hatası ayrı satırda kalır (sonuncusu öncekileri ezmez).
                let loaded = DocumentLoader.loadAll(urls)
                sources += loaded.sources
                if !loaded.errors.isEmpty { error = loaded.errors.joined(separator: "\n") }
            case let .failure(failure):
                error = failure.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner(limit: remainingImages) { images, total in
                addScanned(images, total: total)
            } onError: { failure in
                error = "Tarama yapılamadı: \(failure.localizedDescription)"
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            importsInFlight += 1
            error = nil
            Task {
                var failed = 0
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = await DocumentLoader.jpeg(fromImageData: data) else {
                        failed += 1
                        continue
                    }
                    let source = await DocumentLoader.imageSource(jpeg: jpeg, name: SourceNaming.next("Fotoğraf", existing: sources.map(\.name)))
                    sources.append(source)
                }
                photoItems = []
                importsInFlight -= 1
                if failed > 0 { error = "\(failed) fotoğraf yüklenemedi." }
            }
        }
    }
}

extension SourcesStep {
    /// Seçiciye/tarayıcıya verilecek üst sınır: listedeki görseller düşülür; sınır dolmuşken de en az 1
    /// (fazlası eklenirse "Devam" üstündeki uyarı açıklar).
    fileprivate var remainingImages: Int { max(1, Config.maxImages - sources.count(where: \.isImage)) }

    /// Gelen dosya hatası ile bu adımın kendi hatası tek uyarıda, satır satır.
    fileprivate static func joined(_ messages: String?...) -> String? {
        let lines = messages.compactMap { $0 }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// Taranan sayfalar ana iş parçacığı dışında küçültülür; sınır yüzünden alınmayan ve işlenemeyen sayfalar bildirilir.
    fileprivate func addScanned(_ images: [UIImage], total: Int) {
        importsInFlight += 1
        error = nil
        Task {
            var failed = 0
            for image in images {
                guard let jpeg = await DocumentLoader.jpeg(from: image) else {
                    failed += 1
                    continue
                }
                let source = await DocumentLoader.imageSource(jpeg: jpeg, name: SourceNaming.next("Taranan sayfa", existing: sources.map(\.name)))
                sources.append(source)
            }
            importsInFlight -= 1
            if let note = SourceLimits.scanNote(total: total, taken: images.count, failed: failed) { error = note }
        }
    }

    /// Öneri 17: kitabı içindekiler tablosuna göre ayrı kaynaklara böler (her biri kendi sayfa aralığıyla).
    fileprivate func split(_ source: ImportedSource, into parts: [(title: String, range: ClosedRange<Int>)]) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        let pieces = parts.map { part -> ImportedSource in
            var piece = ImportedSource(name: "\(source.name) · \(part.title)", kind: source.kind)
            piece.pageRange = part.range
            // Parçalar aynı dosyadır: kütüphanede kitabın adıyla tek belge olur (her parça için tam kopya oluşmaz).
            piece.documentID = source.documentID
            piece.libraryName = source.libraryName ?? source.name
            return piece
        }
        sources.replaceSubrange(index...index, with: pieces)
    }
}

private struct SourceButton: View {
    var symbol: String, title: String, subtitle: String
    var action: () -> Void

    var body: some View {
        Button(action: action) { SourceTile(symbol: symbol, title: title, subtitle: subtitle) }
            .buttonStyle(.plain)
    }
}

private struct SourceTile: View {
    var symbol: String, title: String, subtitle: String
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.gradient)
            Text(title).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct SourceRow: View {
    @Binding var source: ImportedSource
    var canMoveUp = false
    var canMoveDown = false
    /// −1 yukarı, +1 aşağı.
    var move: (Int) -> Void = { _ in }
    var remove: () -> Void
    @State private var editingRange = false
    @State private var renaming = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = source.thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFill()
                } else {
                    Image(systemName: source.symbol).font(.title3).foregroundStyle(.tint)
                }
            }
            .frame(width: 44, height: 44)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                // Bölünmüş kitap parçalarında ("Kitap · Bölüm") ayırt edici kısım sondadır: ortadan kırpılır.
                Text(source.name).font(.subheadline.weight(.semibold)).lineLimit(2).truncationMode(.middle)
                Text(source.detail).font(.caption).foregroundStyle(.secondary)
                if source.pageCount.map({ $0 > 1 }) == true {
                    Button(source.pageRange == nil ? "Sayfa aralığı seç" : "Aralığı değiştir") { editingRange = true }
                        .font(.caption.bold())
                }
            }
            // Ayrı Spacer yerine: 320 nokta genişlikte ada bir boşluk payı (12 nokta) daha kalır.
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Yukarı taşı", systemImage: "arrow.up") { move(-1) }.disabled(!canMoveUp)
                Button("Aşağı taşı", systemImage: "arrow.down") { move(1) }.disabled(!canMoveDown)
                Button("Yeniden adlandır", systemImage: "pencil") {
                    renameText = source.name
                    renaming = true
                }
                Divider()
                Button("Kaldır", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Kaynak seçenekleri")
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $editingRange) {
            if let count = source.pageCount {
                PageRangeSheet(pageCount: count, range: $source.pageRange)
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Kaynağı yeniden adlandır", isPresented: $renaming) {
            TextField("Kaynak adı", text: $renameText)
                .onChange(of: renameText) { _, text in
                    if text.count > SourceNaming.maxLength { renameText = String(text.prefix(SourceNaming.maxLength)) }
                }
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") {
                if let name = SourceNaming.cleaned(renameText) { source.name = name }
            }
        }
    }
}

private struct PageRangeSheet: View {
    var pageCount: Int
    @Binding var range: ClosedRange<Int>?
    @Environment(\.dismiss) private var dismiss
    /// Metin olarak tutulur: sayı biçimli alan değeri ancak odak değişince işlerdi, klavye açıkken "Tamam" eski sayıyı alırdı.
    @State private var startText = "1"
    @State private var endText = "1"
    @FocusState private var focused: Field?
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 76

    private enum Field { case start, end }

    private var resolved: ClosedRange<Int> {
        PageRangeInput.resolve(startText: startText, endText: endText, pageCount: pageCount) ?? 1...max(pageCount, 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("İlk sayfa", text: $startText, fallback: 1, field: .start)
                    row("Son sayfa", text: $endText, fallback: pageCount, field: .end)
                } footer: {
                    Text("Yalnızca \(resolved.lowerBound)–\(resolved.upperBound). sayfalar (\(resolved.count) sayfa) gönderilir. Sayfa numaraları transkriptte orijinal belgeye göre gösterilir.")
                }
                Section {
                    Button("Tüm sayfaları kullan (\(pageCount))") {
                        range = nil
                        dismiss()
                    }
                }
            }
            .navigationTitle("Sayfa aralığı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") {
                        range = PageRangeInput.resolve(startText: startText, endText: endText, pageCount: pageCount)
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Bitti") { focused = nil }
                }
            }
            .onAppear {
                startText = String(range?.lowerBound ?? 1)
                endText = String(range?.upperBound ?? pageCount)
            }
        }
    }

    /// Sayı klavyeden yazılır (600 sayfalık kitapta 250–300 için yüzlerce dokunuş gerekmesin); Stepper ince ayar içindir.
    private func row(_ title: String, text: Binding<String>, fallback: Int, field: Field) -> some View {
        let last = max(pageCount, 1)
        let number = Binding<Int>(get: { min(max(Int(text.wrappedValue) ?? fallback, 1), last) }, set: { text.wrappedValue = String($0) })
        let input = TextField(title, text: text)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused($focused, equals: field)
            .frame(width: fieldWidth)
            .frame(minHeight: 44)
        let stepper = Stepper(title, value: number, in: 1...last).labelsHidden()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title)
                Spacer(minLength: 8)
                input
                stepper
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                HStack(spacing: 12) {
                    input
                    Spacer(minLength: 8)
                    stepper
                }
            }
        }
    }
}

// MARK: - 2. Ayarlar

private struct CustomizeStep: View {
    @AppStorage(AppVoice.primaryKey) private var appVoiceRaw = ""
    @AppStorage(AppVoice.secondaryKey) private var appVoiceRaw2 = ""
    @AppStorage(AppVoice.claudeReadingsKey) private var claudeReadings = false
    @Binding var settings: PodcastSettings
    var sourceCount: Int
    /// Belgeye göre önerilen süre.
    var autoMinutes = 10
    @AppStorage(PodcastAuto.autoDurationKey) private var autoDuration = true
    @AppStorage(PodcastAuto.schoolExamKey) private var schoolExam = true
    @Binding var makeSeries: Bool
    @Binding var seriesName: String
    @Binding var compare: Bool
    var generate: () -> Void
    @AppStorage("narrateFigures") private var narrateFigures = true
    @AppStorage("bilingual") private var bilingual = false
    @AppStorage(GenerationCoordinator.previewKey) private var previewBeforeVoicing = false
    @Environment(AppState.self) private var app
    @Query private var ratedEpisodes: [Episode]
    @State private var profiles = PodcastProfiles.all
    @State private var showSaveProfile = false
    @State private var profileName = ""

    /// 👍 verilen bölümlerde en sık kullanılan biçim, derinlik ve süre (öneri 27).
    private var likedSettings: PodcastSettings? {
        let liked = ratedEpisodes.filter { $0.rating == 2 }.compactMap(\.settings)
        guard liked.count >= 2 else { return nil }
        func mode<T: Hashable>(_ values: [T]) -> T? { Dictionary(grouping: values, by: { $0 }).max { $0.value.count < $1.value.count }?.key }
        var s = settings
        s.format = mode(liked.map(\.format)) ?? s.format
        s.depth = mode(liked.map(\.depth)) ?? s.depth
        s.durationMin = mode(liked.map(\.durationMin)) ?? s.durationMin
        s.tone = mode(liked.map(\.tone)) ?? s.tone
        return s.format == settings.format && s.depth == settings.depth && s.durationMin == settings.durationMin && s.tone == settings.tone ? nil : s
    }

    /// Katalog gelene dek geçerli sayılır (`ScriptModelValidity`); yalnız katalogca reddedilen seçim "Oluştur"u kilitler.
    @State private var modelReady = true
    @State private var offlineModels = OfflineSpeechModels.shared

    private var speechReady: Bool {
        (!settings.engine.isNeuralOnDevice || offlineModels.state(settings.engine).ready)
            && (try? LocalSpeech.validate(settings, requireModel: false)) != nil
    }

    private let durationColumns = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                profileSection

                ScriptModelSection(selection: $settings.scriptAI, isValid: $modelReady)

                Section {
                    Toggle("Okul yazılısına hazırlık", isOn: $schoolExam)
                } footer: {
                    Text(schoolExam ? "Anlatım kaynağa sadık kalır, sohbeti kısa tutar; her başlığın sonunda yazılıda çıkabilecek soruyu ve cevabını söyler." : "Kapalıyken anlatım aşağıdaki ton ve biçim ayarlarına göre serbesttir.")
                }

                Section {
                    Toggle("Süreyi belgeye göre seç · yaklaşık \(autoMinutes) dk", isOn: $autoDuration)
                        .onChange(of: autoDuration) { _, on in if on { settings.durationMin = autoMinutes } }
                        .onAppear { if autoDuration { settings.durationMin = autoMinutes } }
                    LazyVGrid(columns: durationColumns, spacing: 8) {
                        ForEach(PodcastSettings.durations, id: \.self) { minutes in
                            let selected = settings.durationMin == minutes
                            Button {
                                autoDuration = false
                                settings.durationMin = minutes
                            } label: {
                                VStack(spacing: 0) {
                                    Text(minutes == 60 ? "1" : "\(minutes)").font(.headline)
                                    Text(minutes == 60 ? "saat" : "dk").font(.caption2)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text("Süre")
                } footer: {
                    if settings.durationMin > 20 {
                        Text("Uzun bölümler önce planlanır, sonra bölüm bölüm yazılır. Hazırlanması yaklaşık \(settings.estimatedGenerationMinutes) dakika sürer; seslendirme arka planda devam eder.")
                    }
                }

                if sourceCount > 1 {
                    Section {
                        Toggle("Her kaynağı ayrı bölüm yap (seri)", isOn: $makeSeries)
                            .onChange(of: makeSeries) { _, on in if on { compare = false } }
                        Toggle("Kaynakları karşılaştır", isOn: $compare)
                            .onChange(of: compare) { _, on in if on { makeSeries = false } }
                        if makeSeries {
                            TextField("Seri adı (ör. Biyoloji 101)", text: $seriesName)
                        }
                    } header: {
                        Text("Seri")
                    } footer: {
                        Text(makeSeries
                             ? "\(sourceCount) bölüm sırayla yazılır; her bölüm öncekilere atıf yapar ve tekrar etmez. Bir bölüm bitince sıradaki otomatik çalar."
                             : "Kapalıyken tüm kaynaklar tek bir bölümde birleştirilir.")
                    }
                }

                if let liked = likedSettings {
                    Section {
                        Button {
                            settings = liked
                        } label: {
                            Label("Beğendiğin ayarlar: \(liked.format.title) · \(liked.depth.title) · \(liked.durationMin) dk", systemImage: "hand.thumbsup.fill")
                        }
                    } footer: {
                        Text("👍 verdiğin bölümlerde en sık kullandığın ayarlar.")
                    }
                }

                Section("Biçim") {
                    ForEach(PodcastFormat.allCases.filter { settings.engine.supportsTwoHosts || !$0.usesTwoHosts }) { format in
                        Button {
                            settings.format = format
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: format.symbol)
                                    .font(.title3)
                                    .frame(width: 32)
                                    .foregroundStyle(Theme.gradient)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(format.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    Text(format.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: settings.format == format ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(settings.format == format ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            }
                        }
                        .accessibilityAddTraits(settings.format == format ? .isSelected : [])
                    }
                }

                Section("Anlatım") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Derinlik").font(.subheadline)
                        Picker("Derinlik", selection: $settings.depth) {
                            // 320 nokta genişlikte "Derinlemesine" üç parçalı denetimde kırpılır; yalnız burada kısaltılır.
                            ForEach(PodcastDepth.allCases) { Text($0 == .derin ? "Derin" : $0.title).tag($0) }
                        }
                        .modifier(AccessiblePickerStyle())
                        .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Konuşma temposu").font(.subheadline)
                        Picker("Tempo", selection: $settings.pace) {
                            ForEach(PodcastPace.allCases) { Text($0.title).tag($0) }
                        }
                        .modifier(AccessiblePickerStyle())
                        .labelsHidden()
                    }
                    Picker("Seviye", selection: $settings.level) {
                        ForEach(PodcastLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Ton", selection: $settings.tone) {
                        ForEach(PodcastTone.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    Picker("Dil", selection: $settings.language) {
                        ForEach(PodcastLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(settings.engine.turkishOnly)
                }

                Section {
                    Toggle("Gerçek hayattan örnekler", isOn: $settings.extras.examples)
                    Toggle("Benzetmeler", isOn: $settings.extras.analogies)
                    Toggle("Sınav ipuçları", isOn: $settings.extras.examTips)
                    Toggle("Sık yapılan hatalar", isOn: $settings.extras.commonMistakes)
                    Toggle("Bölüm sonu tekrar soruları", isOn: $settings.extras.recapQuestions)
                    Toggle("Şekil ve tabloları sözle anlat", isOn: $narrateFigures)
                    if settings.language == .en {
                        Toggle("Türkçe açıklama araları (iki dilli)", isOn: $bilingual)
                    }
                } header: {
                    Text("İçerik")
                }

                Section {
                    TextField("Odaklanılacak konu (ör. Calvin döngüsü)", text: Binding(
                        get: { settings.focus ?? "" },
                        set: { settings.focus = $0.isEmpty ? nil : String($0.prefix(300)) }),
                        axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Özel talimat (ör. formülleri adım adım açıkla)", text: Binding(
                        get: { settings.customInstructions ?? "" },
                        set: { settings.customInstructions = $0.isEmpty ? nil : String($0.prefix(PodcastSettings.maxCustomInstructions)) }),
                        axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Odak ve özel istek")
                } footer: {
                    Text("Anlatım her zaman yalnızca belgendeki bilgilere dayanır.")
                }

                // Tek ses ayarı (Ayarlar › Ses ile aynı): motor sesten türer, ayar değişince podcast ayarları yeniden kurulur.
                Section("Ses") {
                    AppVoiceSettingRow(title: "Anlatıcı sesi", slot: .primary)
                    if settings.format.usesTwoHosts { AppVoiceSettingRow(title: "İkinci ses", slot: .secondary) }
                    if AppVoice.primaryChoice().engine == .chirp { Toggle("Okunuşları Claude hazırlasın", isOn: $claudeReadings) }
                    Text(settings.engine.detail)
                        .font(.footnote).foregroundStyle(.secondary)
                    if settings.engine.isNeuralOnDevice {
                        OfflineModelControls(engine: settings.engine)
                        NavigationLink("iPhone ses modellerini yönet") { OfflineSpeechModelsView() }
                    }
                }
                .onChange(of: appVoiceRaw) { _, _ in settings.applyAppVoice() }
                .onChange(of: appVoiceRaw2) { _, _ in settings.applyAppVoice() }
                .onChange(of: claudeReadings) { _, _ in settings.applyAppVoice() }
                Section {
                    HostEditor(title: settings.format == .tekAnlatici ? "Anlatıcı" : "Anlatıcı (uzman)",
                               host: $settings.hostA, color: Theme.hostColor(.a), speaker: .a, language: settings.language, engine: settings.engine,
                               excludedVoices: settings.format.usesTwoHosts ? [settings.hostB.voice] : [], pace: settings.pace,
                               tone: settings.tone, canRehearse: podcast2)
                    if settings.format.usesTwoHosts {
                        HostEditor(title: "Meraklı öğrenci", host: $settings.hostB, color: Theme.hostColor(.b), speaker: .b, language: settings.language,
                                   engine: settings.engine, excludedVoices: [settings.hostA.voice], pace: settings.pace, tone: settings.tone, canRehearse: podcast2)
                    }
                } header: {
                    Text(settings.format.usesTwoHosts ? "Sunucular" : "Anlatıcı")
                } footer: {
                    Text(!settings.engine.supportsTwoHosts ? "Bu motor tek anlatıcı kullanır." : "Sesler yukarıdaki Ses bölümünden (Ayarlar › Ses ile aynı) seçilir.")
                }

                guestSection

                Section {
                    SoundIdentityPicker(selection: $settings.soundIdentity)
                } header: {
                    Text("Ses kimliği")
                }

                Section {
                    Toggle("Seslendirmeden önce senaryoyu göster", isOn: $previewBeforeVoicing)
                } footer: {
                    Text(previewBeforeVoicing
                         ? "Senaryo hazır olunca konuları ve doğallık karnesini görür, onaylayınca seslendirilir."
                         : "Senaryo hazır olunca seslendirme hemen başlar.")
                }
            }

            VStack(spacing: 8) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if settings.engine.isNeuralOnDevice, !speechReady {
                    Text("Başlamak için yukarıdan ses modelini indir.").font(.caption).foregroundStyle(.secondary)
                }
                if !modelReady {
                    Label("Senaryo modeli seçimi geçersiz; yukarıdan yeniden seç.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                Button(action: generate) {
                    Label("Podcast'i oluştur", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!modelReady || !speechReady)
            }
            .padding(16)
            .background(.bar)
        }
        .animation(.smooth, value: settings.format)
    }

    private var podcast2: Bool { app.serverSupports("podcast2") }

    /// #9: karma biçim ve konuk uzman (yalnız podcast2; konuk yalnız Chirp).
    private var guestSection: some View {
        Section {
            Toggle("Karma biçim (konuya göre anlatım)", isOn: $settings.mixedFormat)
                .disabled(!podcast2)
            Toggle("Konuk uzman", isOn: Binding(
                get: { settings.guest != nil },
                set: { on in settings.guest = on ? Host(name: "Deniz", voice: Self.guestVoice(excluding: [settings.hostA.voice, settings.hostB.voice])) : nil }))
                .disabled(!podcast2 || !settings.engine.supportsGuest)
            if let guest = Binding($settings.guest) {
                HostEditor(title: "Konuk uzman", host: guest, color: Theme.hostColor(.c), speaker: .c, language: settings.language,
                           engine: settings.engine, excludedVoices: [settings.hostA.voice], pace: settings.pace, tone: settings.tone, canRehearse: podcast2)
            }
        } header: {
            Text("Biçim zenginliği")
        } footer: {
            Text(!podcast2 ? "Sunucu bu özellikleri henüz desteklemiyor."
                 : !settings.engine.supportsGuest ? "Konuk sesi yalnız Chirp motorunda kullanılabilir."
                 : "Karma biçimde her konu kendi anlatım biçimini alır. Konuk en fazla iki konuda anlatıcıyla birlikte konuşur.")
        }
    }

    static func guestVoice(excluding used: [String]) -> String {
        VoiceOption.all.first { !used.contains($0.id) && $0.id != "Kore" && $0.id != "Puck" }?.id ?? "Charon"
    }

    /// #43: profil uygula / kaydet.
    private var profileSection: some View {
        Section {
            if !profiles.isEmpty {
                Menu {
                    ForEach(profiles) { profile in
                        Button(profile.name) { settings = QuickSettingsSheet.applying(profile.settings, keepingContextOf: settings).withAppVoice }
                    }
                } label: {
                    Label("Profil uygula", systemImage: "person.crop.rectangle.stack")
                }
            }
            Button("Bu ayarları profil olarak kaydet", systemImage: "square.and.arrow.down") { showSaveProfile = true }
        } header: {
            Text("Profil")
        }
        .alert("Profil adı", isPresented: $showSaveProfile) {
            TextField("ör. Sınav haftası", text: $profileName)
            Button("Kaydet") {
                PodcastProfiles.save(profileName, settings: settings)
                profiles = PodcastProfiles.all
                profileName = ""
            }
            Button("Vazgeç", role: .cancel) { profileName = "" }
        } message: {
            Text("Kısayollar ve Siri bu adla tek dokunuşla podcast oluşturabilir.")
        }
    }

    private var summary: String {
        let duration = settings.durationMin == 60 ? "1 saat" : "\(settings.durationMin) dk"
        let series = makeSeries && sourceCount > 1 ? "\(sourceCount) bölümlük seri · " : ""
        return series + "\(duration) · \(settings.format.title) · \(settings.depth.title) · \(settings.language.title)"
    }
}

private struct ScriptModelSection: View {
    @Binding var selection: ScriptAISettings?
    @Binding var isValid: Bool
    @State private var catalog: ScriptModelCatalog?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        Section {
            if let catalog {
                Picker("Yapay zekâ", selection: Binding(
                    get: { selection?.provider ?? "" },
                    set: { selection = catalog.selection(provider: $0) }
                )) {
                    if let current = selection?.provider, !catalog.providers.contains(where: { $0.id == current }) {
                        Text("\(current) · kullanılamıyor").tag(current)
                    }
                    ForEach(catalog.providers) { Text($0.title).tag($0.id) }
                }
                .accessibilityIdentifier("scriptProvider")

                Picker("Model", selection: Binding(
                    get: { selection?.model ?? "" },
                    set: { selection = catalog.selection(provider: selection?.provider ?? "", modelID: $0) }
                )) {
                    if let current = selection?.model, catalog.model(for: selection) == nil {
                        Text("\(current) · kullanılamıyor").tag(current)
                    }
                    ForEach(catalog.models.filter { $0.provider == selection?.provider }) { Text($0.title).tag($0.id) }
                }
                .accessibilityIdentifier("scriptModel")

                if let model = catalog.model(for: selection) {
                    Picker("Düşünme düzeyi", selection: Binding(
                        get: { selection?.effort ?? "auto" },
                        set: { selection?.effort = $0 }
                    )) {
                        if let effort = selection?.effort, !model.efforts.contains(effort) {
                            Text("\(ScriptAISettings.effortTitle(effort)) · desteklenmiyor").tag(effort)
                        }
                        ForEach(model.efforts, id: \.self) { Text(ScriptAISettings.effortTitle($0)).tag($0) }
                    }
                    .disabled(model.efforts.count < 2)
                    .accessibilityIdentifier("scriptEffort")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.detail)
                        Text(model.id).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !catalog.accepts(selection) {
                    Label("Kayıtlı seçim kullanılamıyor. Yapay zekâ, model veya düşünme düzeyini yeniden seç.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    if catalog.accepts(catalog.defaultSelection) {
                        Button("Varsayılan modeli seç") { selection = catalog.defaultSelection }
                    }
                }
            }
            if loading {
                HStack { ProgressView(); Text("Modeller yükleniyor…").foregroundStyle(.secondary) }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Button(catalog == nil ? "Yeniden dene" : "Model listesini yenile", systemImage: "arrow.clockwise") {
                Task { await load() }
            }
            .disabled(loading)
        } header: {
            Text("Senaryo yapay zekâsı")
        } footer: {
            Text("Seçimin sonraki podcast için hatırlanır. Yüksek düşünme düzeyi daha uzun sürebilir ve daha fazla kota kullanabilir.")
        }
        .task { await load() }
        .onChange(of: selection) { _, _ in isValid = ScriptModelValidity.isValid(catalog: catalog, selection: selection, loading: loading) }
    }

    private func load() async {
        loading = true
        error = nil
        isValid = ScriptModelValidity.isValid(catalog: catalog, selection: selection, loading: true)
        // Her çıkışta, iptalde de (bölüm ekran dışına kaydırılınca `.task` iptal olur) geçerlilik yeniden hesaplanır:
        // "Oluştur" asılı kalan ya da yarıda kesilen istek yüzünden kilitli kalmaz.
        defer {
            loading = false
            isValid = ScriptModelValidity.isValid(catalog: catalog, selection: selection, loading: false)
        }
        do {
            let result = try await APIClient.shared.scriptModels()
            catalog = result
            if selection == nil { selection = result.defaultSelection }
            if result.models.isEmpty { error = "Kullanılabilir senaryo modeli bulunamadı. Sunucu bağlantısını kontrol et." }
        } catch is CancellationError {
            return
        } catch {
            // #4: katalog gelmezse "Oluştur" kilitlenmez; istek kuyruğa düşer ve sunucunun varsayılanı kullanılır.
            self.error = error.localizedDescription + " Kayıtlı ya da sunucunun varsayılan modeli kullanılır."
        }
    }
}

/// Senaryo modeli seçimi "Oluştur"u kilitler mi (saf; test edilir). Katalog yokken (yükleniyor, gelmedi ya da istek
/// iptal oldu) seçim geçerli sayılır: kayıtlı ya da sunucunun varsayılan modeli kullanılır (#4). Katalog varken seçim
/// katalogca kabul edilmeli; yenileme sürerken eldeki katalog esastır.
nonisolated enum ScriptModelValidity {
    static func isValid(catalog: ScriptModelCatalog?, selection: ScriptAISettings?, loading: Bool) -> Bool {
        guard let catalog else { return true }
        return catalog.accepts(selection)
    }
}

private struct HostEditor: View {
    var title: String
    @Binding var host: Host
    var color: Color
    var speaker: Speaker
    var language: PodcastLanguage
    var engine: SpeechEngine
    /// Diğer sunucunun sesi (aynı ses seçilemez).
    var excludedVoices: [String] = []
    var pace: PodcastPace = .normal
    /// #14: provada tempo ile birlikte ton stili de iletilir.
    var tone: PodcastTone = .samimi
    /// Sunucu `/v1/speak` destekliyor mu (podcast2).
    var canRehearse = false
    @State private var rehearsal = VoiceRehearsal.shared
    @State private var samples = VoicePreview.shared

    /// Chirp sesi: gömülü örnek dinlenebilir. Ses her motorda Ayarlar › Ses'ten seçilir (bu ekranın Ses bölümü aynı ayardır).
    private var choosesVoice: Bool { engine.voicedBy == .chirp }
    private var rehearsalKey: String { "\(engine.rawValue)-\(speaker.rawValue)-\(host.voice)-\(pace.rawValue)-\(tone.rawValue)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    TextField("Ad", text: Binding(get: { host.name }, set: { host.name = String($0.prefix(20)) }))
                        .font(.body.weight(.medium))
                }
            }
            Text(choosesVoice ? voiceTitle : voiceDescription).font(.caption).foregroundStyle(.secondary)
            if canRehearse, engine.usesServer {
                Button {
                    rehearsal.toggle(key: rehearsalKey, request: SpeakRequest(
                        engine: engine.voicedBy.rawValue, voice: engine == .edge ? (speaker == .a ? "Emel" : "Ahmet") : host.voice, pace: pace, style: VoiceRehearsal.style(tone: tone, speaker: speaker),
                        text: Self.sample(name: host.name, language: language), replacements: nil))
                } label: {
                    HStack(spacing: 6) {
                        if rehearsal.loading == rehearsalKey { ProgressView() }
                        else { Image(systemName: rehearsal.playing == rehearsalKey ? "stop.circle" : "play.circle") }
                        Text(rehearsal.playing == rehearsalKey ? "Provayı durdur" : "Provayı dinle")
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                if let error = rehearsal.errors[rehearsalKey] { Text(error).font(.caption).foregroundStyle(.red) }
            } else if choosesVoice {
                Button {
                    samples.play(host.voice)
                } label: {
                    Label(samples.playing == host.voice ? "Örneği durdur" : "Ses örneğini dinle",
                          systemImage: samples.playing == host.voice ? "stop.circle" : "play.circle")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// Seçili sesin menüdeki adı ("Kore — Kararlı"); listede yoksa kimliği.
    private var voiceTitle: String {
        VoiceOption.all.first { $0.id == host.voice }.map { "\($0.id) — \($0.trait)" } ?? host.voice
    }

    private var voiceDescription: String {
        // Tek ses ayarından gelen anahtar ("xtts:<kimlik>", "apple:F"): seçicideki adıyla.
        if QSVoiceKey.prefixed(host.voice) { return AppVoice.title(QSVoiceKey(host.voice)) }
        return switch engine {
        case .apple: DeviceSpeech.qualityDescription(speaker: speaker == .c ? .b : speaker, language: language)
        case .edge: speaker == .a ? "Emel (kadın sesi)" : "Ahmet (erkek sesi)"
        default: engine.supportsTwoHosts ? engine.voiceLabel(speaker == .c ? .b : speaker) : "Tek anlatıcı · \(engine.voiceLabel(.a))"
        }
    }

    static func sample(name: String, language: PodcastLanguage) -> String {
        language == .en
            ? "Hi, I'm \(name). Today we'll learn this topic step by step, with clear examples."
            : "Merhaba, ben \(name). Bugün bu konuyu adım adım, örneklerle birlikte öğreneceğiz."
    }
}

// MARK: - 3. Üretim

private struct GeneratingStep: View {
    var error: String?
    var queued: String?
    var settings: PodcastSettings
    var seriesProgress: (current: Int, total: Int)?
    var draftID: UUID?
    var onBackground: () -> Void
    var onClose: () -> Void
    var retry: () -> Void
    @Environment(GenerationCoordinator.self) private var generator

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let queued {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                    Text(queued)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Kütüphanedeki kuyruktan izleyebilir ya da “Şimdi dene” diyebilirsin.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Kapat", action: onClose)
                        .buttonStyle(.borderedProminent)
                } else if let error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Ayarlara dön", action: retry)
                        .buttonStyle(.bordered)
                } else {
                    let phase = draftID.flatMap { generator.drafts[$0] } ?? .preparing
                    PulsingWave()
                    VStack(spacing: 8) {
                        if let seriesProgress {
                            Text("Seri: \(seriesProgress.current). bölüm / \(seriesProgress.total)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.tint)
                        }
                        Text(phase.title).font(.title3.bold())
                        Text(detail(phase))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    ProgressView(value: phase.draftFraction)
                        .padding(.horizontal, 48)
                    Text("Senaryo hazır olunca bölüm açılır. İlk sahneler seslenir seslenmez dinlemeye başlayabilirsin; gerisi sen dinlerken hazırlanır.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Arka planda sürsün", systemImage: "arrow.down.right.and.arrow.up.left", action: onBackground)
                        .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .padding(.top, 32)
        }
    }

    private func detail(_ phase: GenerationCoordinator.Phase) -> String {
        if case let .writingScript(progress) = phase, progress.chaptersTotal == 0, settings.durationMin > 20 {
            return "Önce bölüm planı çıkarılıyor, sonra bölümler paralel yazılıyor. \(settings.durationMin) dakikalık bir bölüm için birkaç dakika sürebilir."
        }
        return phase.detail
    }
}

struct PulsingWave: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: 8, height: 20 + 40 * abs(sin(t * 2.4 + Double(i) * 0.6)))
                }
            }
            .frame(height: 64)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Belge tarayıcı

struct DocumentScanner: UIViewControllerRepresentable {
    /// En çok bu kadar sayfa alınır (gönderilebilecek görsel sınırı).
    var limit = Config.maxImages
    /// Alınan sayfalar ve taranan toplam sayfa sayısı (fazlası alınmadıysa çağıran bunu kullanıcıya söyler).
    var onScan: ([UIImage], Int) -> Void
    var onError: (Error) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<min(scan.pageCount, max(parent.limit, 0))).map { scan.imageOfPage(at: $0) }
            parent.onScan(images, scan.pageCount)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onError(error)
            parent.dismiss()
        }
    }
}
