import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// #21: bölüm işlemleri yarım sayfası (eski ••• menünün yerine): Dinle / Düzelt / Çalış / Paylaş / Yönet.
/// Satırlarda durum yazar ("2 uyarı", "Akışta", "Ses metinle uyuşmuyor"). Sayfa yalnız hazır bölümde açılır;
/// "Onay bekliyor" üretimdeki bölümün ••• menüsündedir (`EpisodeDetailView`).
struct EpisodeActionsSheet: View {
    @Bindable var episode: Episode
    /// Yolda modu ve silme onayı bu sayfa kapandıktan SONRA sunulur (bkz. `EpisodeActionsFollowUp`):
    /// kapanma animasyonu sürerken istenen yeni sunumu UIKit reddedebilir.
    var onTheRoad: () -> Void
    var onDelete: () -> Void
    /// #20: elle hazırlanan kelime senkronu hazır; açık bölüm sayfası kelime zamanlarını yeniden yükler.
    var onWordSyncReady: () -> Void = {}
    @Environment(PlayerController.self) private var player
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showSlides") private var showSlides = true

    @State private var sheet: ActionSheet?
    @State private var weakClips: [PodcastClip] = []
    @State private var weakSession: WeakSpotsTarget?
    @State private var exporting = false
    @State private var exportDocument: AudioFileDocument?
    @State private var shareURL: URL?
    @State private var busy: String?
    @State private var message: String?
    @State private var ratingPrompt = false
    @State private var ratingNote = ""
    @State private var wordSyncState: String?
    @State private var queued = false

    enum ActionSheet: String, Identifiable {
        case regenerate, deck, figures, video, linkSources, verifyFix, studio, pronunciation, cards, share, organize, clip
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                listenSection
                fixSection
                studySection
                shareSection
                manageSection
            }
            .navigationTitle("Bölüm işlemleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
            .sheet(item: $sheet) { which in sheetContent(which) }
            .fullScreenCover(item: $weakSession) { WeakSpotsSession(clips: $0.clips) }
            .sheet(item: $shareURL) { url in ShareSheet(items: [url]) }
            .fileExporter(isPresented: $exporting, document: exportDocument,
                          contentType: .mpeg4Audio, defaultFilename: episode.title) { result in
                exportDocument = nil
                if case let .failure(error) = result, let text = EpisodeActionStatus.exportFailure(error) { message = text }
            }
            .alert("Neyi beğenmedin?", isPresented: $ratingPrompt) {
                TextField("Ör. çok yüzeysel, sesler yorucu", text: $ratingNote)
                Button("Kaydet") {
                    episode.ratingNote = ratingNote.isEmpty ? nil : ratingNote
                    try? context.save()
                }
            }
            .alert("Bilgi", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: { Text(message ?? "") }
            .task { weakClips = WeakSpots.clips(context: context, limit: 8) }
        }
    }

    // MARK: - Bölümler

    private var listenSection: some View {
        Section {
            ListeningModePicker(compact: false)
            row("Yolda modu", "car.fill", status: nil) {
                onTheRoad()
                dismiss()
            }
            row(queued || player.upNext.contains(.episode(episode.id)) ? "Sırada" : "Sıraya ekle", "text.badge.plus",
                status: player.upNext.isEmpty ? nil : "\(player.upNext.count) öğe") {
                player.enqueue(.episode(episode.id))
                queued = true
            }
            .disabled(player.episode?.id == episode.id || player.upNext.contains(.episode(episode.id)))
            Toggle(isOn: $showSlides) { Label("Senkron slaytlar", systemImage: "rectangle.on.rectangle") }
            Toggle(isOn: Binding(get: { player.skipSilence }, set: { player.skipSilence = $0 })) {
                Label("Sessizliği atla", systemImage: "waveform.path")
            }
            row("Kelime senkronunu hazırla", "text.word.spacing", status: wordSyncState) {
                Task { await prepareWordSync() }
            }
            .disabled(busy != nil)
        } header: {
            Text("Dinle")
        } footer: {
            Text("Kilit ekranında ±15 düğmeleri görünür; konu geçişi kulaklıktaki ileri/geri ve Siri (\"Ders Podcast sonraki konu\") ile yapılır.")
        }
    }

    private var fixSection: some View {
        Section("Düzelt") {
            row(generator.isVerifying(episode) ? "Doğrulanıyor…" : "Senaryoyu belgeyle doğrula", "checkmark.shield",
                status: EpisodeActionStatus.verification(episode.verification, error: generator.verifyError[episode.id]),
                detail: generator.verifyError[episode.id]) {
                generator.verify(episode, context: context)
            }
            .disabled(generator.isVerifying(episode))
            if !(episode.verification ?? []).filter({ $0.fixedAt == nil }).isEmpty {
                row("Düzeltme önerileri", "wand.and.stars", status: nil) { sheet = .verifyFix }
            }
            row("Sahne stüdyosu", "slider.horizontal.3", status: EpisodeActionStatus.audio(episode.audioIssues)) { sheet = .studio }
            row("Telaffuz önerileri", "character.bubble", status: nil) { sheet = .pronunciation }
            // Hazır ses seçimi yalnızca sesi Chirp'in ürettiği motorlarda etkili (diğerlerinde ses sabit ya da kendi seçicisindedir).
            if episode.settings?.engine.voicedBy == .chirp {
                row("Sesi yeniden üret", "waveform.badge.plus", status: nil) { sheet = .regenerate }
            }
            row("Kaynak belge bağla", "link.badge.plus", status: nil) { sheet = .linkSources }
        }
    }

    private var studySection: some View {
        Section("Çalış") {
            row(weakTitle, "scope", status: weakClips.isEmpty ? "Henüz yok" : nil) {
                weakSession = WeakSpotsTarget(clips: weakClips)
            }
            .disabled(weakClips.isEmpty)
            row("Kart önerileri", "rectangle.stack.badge.plus", status: nil) { sheet = .cards }
            row(busy == "recap" ? "Hızlı tekrar hazırlanıyor…" : "Hızlı tekrar sesi (5 dk)", "bolt.badge.clock", status: nil) {
                // Meşgul imi dokunuşla aynı anda kurulur: art arda iki dokunuş iki üretim başlatmasın.
                guard busy == nil else { return }
                busy = "recap"
                Task { await startRecap() }
            }
            .disabled(episode.script == nil || busy != nil)
            row("Sunum stüdyosu", "rectangle.stack.badge.play", status: nil) { sheet = .deck }
            row("Kaynak şekilleri", "photo.on.rectangle.angled", status: nil) { sheet = .figures }
            row("Ders videosu (MP4)", "film", status: nil) { sheet = .video }
                .disabled(episode.deck == nil)
        }
    }

    private var shareSection: some View {
        Section("Paylaş") {
            row("Paylaş…", "square.and.arrow.up", status: nil) { sheet = .share }
            row("Klip paylaş (60 sn)", "scissors", status: nil) { sheet = .clip }
            if let url = episode.audioURL {
                row("Dosyalar'a kaydet", "folder", status: nil) {
                    exportDocument = AudioFileDocument(url: url)
                    exporting = true
                }
                ShareLink(item: url, preview: SharePreview(episode.title)) {
                    Label("Ses dosyasını paylaş", systemImage: "waveform")
                }
                row(busy == "chapters" ? "Hazırlanıyor…" : "Konu işaretli ses", "list.bullet.rectangle", status: nil) {
                    Task { await exportChapters() }
                }
                .disabled(busy != nil)
            }
            ShareLink(item: transcriptText, preview: SharePreview("\(episode.title) — transkript")) {
                Label("Transkripti paylaş", systemImage: "doc.plaintext")
            }
            row("Markdown olarak paylaş", "doc.richtext", status: nil) { export(pdf: false) }
            row("PDF olarak paylaş", "doc.text", status: nil) { export(pdf: true) }
            row(busy == "feed" ? "Akış güncelleniyor…" : (PodcastFeed.published.contains(episode.id) ? "Podcast akışından çıkar" : "Podcast akışına ekle"),
                "dot.radiowaves.left.and.right", status: EpisodeActionStatus.feed(PodcastFeed.published.contains(episode.id))) {
                Task { await toggleFeed() }
            }
            .disabled(busy != nil)
        }
    }

    private var manageSection: some View {
        Section("Yönet") {
            GenerationStatsCard(episode: episode)
            row("Düzenle (ad, seri, ders)", "square.and.pencil", status: nil) { sheet = .organize }
            HStack {
                Text("Bu bölüm nasıldı?").font(.subheadline)
                Spacer()
                Button { episode.rating = 2; try? context.save() } label: {
                    Image(systemName: episode.rating == 2 ? "hand.thumbsup.fill" : "hand.thumbsup").frame(width: 44, height: 44)
                }
                .accessibilityLabel(episode.rating == 2 ? "Beğendim, seçili" : "Beğendim")
                Button { episode.rating = 1; ratingPrompt = true } label: {
                    Image(systemName: episode.rating == 1 ? "hand.thumbsdown.fill" : "hand.thumbsdown").frame(width: 44, height: 44)
                }
                .accessibilityLabel(episode.rating == 1 ? "Beğenmedim, seçili" : "Beğenmedim")
            }
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                onDelete()
                dismiss()
            } label: { Label("Bölümü sil", systemImage: "trash") }
        }
    }

    // MARK: - Yardımcılar

    /// Kısa durum başlığın sağında tek satırda durur; sığmayan (uzun neden, 320 pt) kırpılmadan başlığın altına iner.
    /// `detail`: hatanın nedeni (kırmızı, tam metin).
    private func row(_ title: String, _ symbol: String, status: String?, detail: String? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Label(title, systemImage: symbol).foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        if let status { statusText(status).lineLimit(1) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Label(title, systemImage: symbol).foregroundStyle(.primary)
                        if let status { statusText(status).fixedSize(horizontal: false, vertical: true) }
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    private func statusText(_ status: String) -> some View {
        Text(status)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder private func sheetContent(_ which: ActionSheet) -> some View {
        switch which {
        case .regenerate: RegenerateAudioSheet(episode: episode)
        case .deck: DeckView(episode: episode)
        case .figures: FigureGalleryView(episode: episode)
        case .video: DeckVideoSheet(episode: episode)
        case .linkSources:
            DocumentLibraryView { docs in
                // Var olan belgeleri bu bölüme bağla; şekiller bir sonraki deste/şekil çıkarımında yeniden kesilir.
                let new = docs.map(\.id).filter { !(episode.sourceDocumentIDs ?? []).contains($0) }
                guard !new.isEmpty else { return }
                episode.sourceDocumentIDs = (episode.sourceDocumentIDs ?? []) + new
                episode.sourceFigures = []
                episode.figureMap = nil
                try? context.save()
            }
        case .verifyFix: VerifyFixSheet(episode: episode, focusTurn: nil)
        case .studio: SceneStudioView(episode: episode, sceneIndex: currentScene)
        case .pronunciation: PronunciationSuggestionsSheet(episode: episode)
        case .cards: CardSuggestionsView(episode: episode)
        case .share: ShareEpisodeSheet(episode: episode)
        case .organize: EpisodeOrganizeSheet(episode: episode)
        case .clip: ClipShareSheet(episode: episode, start: player.episode?.id == episode.id ? player.currentTime : 0)
        }
    }

    /// Sahne stüdyosu: önce sorunlu sahne, yoksa çalan sahne.
    private var currentScene: Int {
        if let bad = episode.audioIssues.first?.scene { return bad }
        guard player.episode?.id == episode.id, let turn = player.currentTurnIndex, let script = episode.script else { return 0 }
        return AudioEditor.sceneIndex(forTurn: turn, script: script) ?? 0
    }

    private var weakTitle: String {
        let seconds = weakClips.reduce(0) { $0 + max(0, $1.end - $1.start) }
        return weakClips.isEmpty ? "Zayıf kesitleri dinle" : "Zayıf kesitleri dinle (\(max(1, Int((seconds / 60).rounded(.up)))) dk)"
    }

    private var transcriptText: String {
        guard let timeline = episode.timeline, let settings = episode.settings else { return episode.title }
        var lines = [episode.title, ""]
        var chapter = -1
        for turn in timeline.turns {
            if turn.chapterIndex != chapter {
                chapter = turn.chapterIndex
                lines += ["", ChapterTitleCase.upper(timeline.chapters[safe: chapter]?.title ?? "", language: settings.language)]
            }
            lines.append("\(settings.displayName(for: turn.speaker)) [\(turn.start.clockText)]: \(turn.text)")
        }
        return lines.joined(separator: "\n")
    }

    private func toggleFeed() async {
        busy = "feed"
        defer { busy = nil }
        do {
            if PodcastFeed.published.contains(episode.id) { try await PodcastFeed.remove(episode) } else { try await PodcastFeed.publish(episode) }
        } catch { message = error.localizedDescription }
    }

    private func export(pdf: Bool) {
        do { shareURL = try pdf ? EpisodeExporter.writePDF(episode) : EpisodeExporter.writeMarkdown(episode) }
        catch { message = error.localizedDescription }
    }

    private func startRecap() async {
        defer { busy = nil }
        do {
            let recap = try await RecapGenerator.start(for: episode, generator: generator, context: context)
            dismiss()
            AppState.current?.pendingOpenEpisode = recap.id
        } catch { message = "Hızlı tekrar başlatılamadı: \(error.localizedDescription)" }
    }

    private func exportChapters() async {
        busy = "chapters"
        defer { busy = nil }
        do { shareURL = try await ChapterAudioExport.export(episode) }
        catch { message = "Konu işaretli ses hazırlanamadı: \(error.localizedDescription)" }
    }

    private func prepareWordSync() async {
        busy = "wordSync"
        wordSyncState = "Hazırlanıyor…"
        defer { busy = nil }
        let outcome = await WordSyncRunner.prepare(episode)
        wordSyncState = EpisodeActionStatus.wordSync(outcome)
        if EpisodeActionStatus.reloadsWordTimes(outcome) { onWordSyncReady() }
    }
}

/// Satır durum metinleri (saf; test edilir).
enum EpisodeActionStatus {
    static func verification(_ issues: [ScriptIssue]?, error: String?) -> String? {
        if error != nil { return "Doğrulanamadı" }
        guard let issues else { return nil }
        let open = issues.filter { $0.fixedAt == nil }.count
        return open == 0 ? "Sorun yok" : "\(open) uyarı"
    }

    static func feed(_ published: Bool) -> String? { published ? "Akışta" : nil }
    /// "Dosyalar'a kaydet" hatası; kullanıcı vazgeçtiyse nil (uyarı gösterilmez).
    static func exportFailure(_ error: any Error) -> String? {
        (error as? CocoaError)?.code == .userCancelled ? nil : "Kaydedilemedi: \(error.localizedDescription)"
    }
    /// #7: onay yalnız üretimdeki bölümde anlamlı (işlemler sayfası yalnız hazır bölümde açılır); durum üretimdeki
    /// bölümün ••• menüsünde ve düğme etiketinde gösterilir.
    static func approval(_ needsApproval: Bool, status: EpisodeStatus) -> String? {
        status == .generating && needsApproval ? "Onay bekliyor" : nil
    }

    /// #20: yalnız `.ready` sonucunda açık sayfa kelime zamanlarını yeniden yükler.
    static func reloadsWordTimes(_ outcome: WordSyncOutcome?) -> Bool { outcome == .ready }
    static func audio(_ issues: [AudioIssue]) -> String? { issues.isEmpty ? nil : "Ses metinle uyuşmuyor" }

    static func wordSync(_ outcome: WordSyncOutcome?) -> String {
        switch outcome {
        case .ready: "Hazır"
        case let .unsupported(reason): reason
        case .denied: "Konuşma tanıma izni yok"
        case let .failed(reason): reason
        case nil: "Zaten hazırlanıyor"
        }
    }
}

private struct WeakSpotsTarget: Identifiable {
    var clips: [PodcastClip]
    var id: UUID { clips.first?.id ?? UUID() }
}

/// #22: zayıf kesitler oturumu: her kesitten sonra soru sorulur, cevaplanınca sonraki kesit çalar.
struct WeakSpotsSession: View {
    var clips: [PodcastClip]
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var question: QuizItem?
    @State private var waiter: CheckedContinuation<Void, Never>?
    @State private var started = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let question {
                    InlineQuizSheet(item: question) { _ in resumeNext() }
                } else if let progress = player.clipProgress {
                    Spacer()
                    Text("Kesit \(progress.index)/\(progress.count)").font(.title2.bold())
                    Text(player.episode?.title ?? "").font(.headline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.largeTitle)
                            .frame(width: 88, height: 88)
                            .background(Theme.gradient, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")
                    Spacer()
                } else if started {
                    ContentUnavailableView("Kesitler bitti", systemImage: "checkmark.circle",
                                           description: Text("Zorlandığın yerleri yeniden dinledin."))
                }
            }
            .padding()
            .navigationTitle("Zayıf kesitler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") {
                        player.endClipSession()
                        resumeNext()
                        dismiss()
                    }
                }
            }
            .task {
                guard !started else { return }
                started = true
                player.playClips(clips, context: context) { clip in
                    // Arka plandaysa (kilitli) soru beklenmez; kesitler sürer. Durum canlı okunur: görünüm
                    // kopyasındaki scenePhase bu kapanış kurulduğu andaki değerde kalır.
                    guard UIApplication.shared.applicationState == .active,
                          let item = WeakSpots.question(for: clip, context: context) else { return }
                    await withCheckedContinuation { continuation in
                        waiter = continuation
                        question = item
                    }
                }
            }
            // Soru ekrandayken kesit başka yoldan geçildi (kilit ekranından "oynat"): eski soru kapanır.
            .onChange(of: player.clipProgress?.index) { _, _ in
                if question != nil { resumeNext() }
            }
        }
        // "Kapat" dışında kalkarsa da (bildirim, Spotlight, sayfa değişimi) oturum kapanır, bekleyen soru bırakılır.
        .onDisappear {
            player.endClipSession()
            resumeNext()
        }
    }

    private func resumeNext() {
        question = nil
        waiter?.resume()
        waiter = nil
    }
}
