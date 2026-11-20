import Accessibility
import SwiftData
import SwiftUI

/// #7: seslendirmeden önce senaryo önizleme ve onay (GeneratingEpisodeView içinde; EpisodeDetailView değişmez).
struct ScriptPreviewView: View {
    var episode: Episode
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var busy: String?
    @State private var error: String?
    @State private var editing = false
    @State private var reading: ChapterReading?

    /// Açık metin sayfası: konu ve (zayıf sahneden açıldıysa) gösterilecek konu içi sahne.
    struct ChapterReading: Identifiable {
        var chapter: Int
        var scene: Int?
        var id: String { "\(chapter)-\(scene ?? -1)" }
    }

    /// Sunucu motorunda düzenleme yeni iş belirteci ister (hak düşmemesi podcast2 ile).
    private var canEdit: Bool {
        guard let settings = episode.settings else { return false }
        return !settings.usesServerSpeech || app.serverSupports("podcast2")
    }

    var body: some View {
        let script = episode.script
        List {
            if let script {
                header(script)
                if let quality = script.quality, !quality.findings.isEmpty {
                    Section("Doğallık karnesi") {
                        ForEach(quality.findings, id: \.id) { finding in
                            HStack(alignment: .firstTextBaseline) {
                                Text(finding.label)
                                Spacer(minLength: 8)
                                Text("×\(finding.count)").monospacedDigit().foregroundStyle(finding.count > 3 ? .orange : .secondary)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if let errors = script.quality?.chapterErrors, !errors.isEmpty {
                    Section {
                        ForEach(errors, id: \.index) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.message).font(.caption).foregroundStyle(.secondary)
                                Button {
                                    run("retry-\(item.index)") { try await generator.retryChapter(episode, error: item, context: context) }
                                } label: {
                                    busyLabel("Konuyu yeniden dene", systemImage: "arrow.clockwise", key: "retry-\(item.index)")
                                }
                                .buttonStyle(.bordered)
                                .disabled(busy != nil || ScriptJobMemory.jobID(for: episode.id) == nil)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text("Yazılamayan konular")
                    } footer: {
                        Text("Bu konular olmadan da seslendirebilirsin; yeniden deneme günlük hakkı düşürmez.")
                    }
                }
                chapters(script)
                if let weak = script.quality?.weakScenes, !weak.isEmpty {
                    Section {
                        ForEach(weak, id: \.scene) { item in
                            weakRow(item, script: script)
                        }
                    } header: {
                        Text("Zayıf sahneler")
                    } footer: {
                        Text("“Cilala” sahneyi aynı içerikle daha doğal yeniden yazar.")
                    }
                }
            } else {
                Text("Senaryo okunamadı.").foregroundStyle(.secondary)
            }
        }
        .environment(\.editMode, .constant(editing ? .active : .inactive))
        .safeAreaInset(edge: .bottom) { approveBar }
        .sheet(item: $reading) { ChapterTextSheet(episode: episode, target: $0) }
    }

    private func header(_ script: PodcastScript) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(script.title).font(.headline)
                let target = script.quality?.targetMinutes ?? Double(episode.settings?.durationMin ?? 0)
                if let estimated = script.quality?.estimatedMinutes {
                    Text("Tahmini süre \(Int(estimated.rounded())) dk · hedef \(Int(target.rounded())) dk")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text("\(script.chapters.count) konu · \(script.flatScenes.count) sahne" + (script.quality.map { " · \($0.words.formatted()) kelime" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Senaryo hazır, onay bekliyor")
        }
    }

    private func chapters(_ script: PodcastScript) -> some View {
        Section {
            ForEach(Array(script.chapters.enumerated()), id: \.offset) { index, chapter in
                // Düzenleme kipinde satır yalnız silinir/taşınır; metin sayfası açılmaz.
                Button {
                    if !editing { reading = ChapterReading(chapter: index, scene: nil) }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). \(chapter.title)").font(.subheadline.weight(.medium))
                            Text("\(chapter.scenes.count) sahne" + (chapter.style.map { " · \(Self.styleTitle($0))" } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if !editing {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(editing ? Text("") : Text("Konunun metnini açar"))
            }
            // Bir istek sürerken (Cilala, Seslendir, konu yeniden deneme) senaryo değişmez: istek eski indekslerle yanıtlanır.
            .onDelete(perform: canEdit && busy == nil && script.chapters.count > 1 ? { offsets in edit { $0.chapters.remove(atOffsets: offsets) } } : nil)
            .onMove(perform: canEdit && busy == nil ? { from, to in edit { $0.chapters.move(fromOffsets: from, toOffset: to) } } : nil)
        } header: {
            HStack {
                Text("Konular")
                Spacer()
                if canEdit {
                    Button(editing ? "Bitti" : "Düzenle") { editing.toggle() }
                        .font(.caption.bold())
                        .frame(minHeight: 44)
                        .disabled(busy != nil)
                }
            }
        } footer: {
            Text("Metnini okumak için konuya dokun. "
                 + (canEdit ? "Konuları silebilir ya da sıralayabilirsin; seslendirme onaydan sonra başlar." : "Bu sunucuda konular düzenlenemez."))
        }
    }

    private func weakRow(_ item: WeakScene, script: PodcastScript) -> some View {
        let location = ScriptEditing.chapterAndScene(item.scene, in: script)
        let chapterTitle = location.flatMap { script.chapters[safe: $0.chapter]?.title } ?? "Sahne \(item.scene + 1)"
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(chapterTitle) · sahne \(item.scene + 1)").font(.subheadline.weight(.medium))
            Text(item.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            let polishButton = Button {
                run("polish-\(item.scene)") { try await polish(item) }
            } label: {
                busyLabel("Cilala", systemImage: "sparkles", key: "polish-\(item.scene)")
            }
            .buttonStyle(.bordered)
            .disabled(busy != nil || !canEdit)
            let readButton = Button {
                if let location { reading = ChapterReading(chapter: location.chapter, scene: location.scene) }
            } label: {
                Label("Metni gör", systemImage: "text.alignleft").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(location == nil)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { polishButton; readButton }
                VStack(alignment: .leading, spacing: 6) { polishButton; readButton }
            }
        }
        .padding(.vertical, 4)
    }

    private var approveBar: some View {
        VStack(spacing: 6) {
            // Hata burada: liste sonundaki bölüm uzun senaryoda ekran dışında kalıyor, yalnız çarkın durduğu görülüyordu.
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                run("approve") { try await generator.approve(episode, context: context) }
            } label: {
                busyLabel("Seslendir", systemImage: "waveform", key: "approve")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy != nil || episode.script == nil)
            Text("Onaylayınca seslendirme arka planda başlar.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.bar)
    }

    @ViewBuilder
    private func busyLabel(_ title: String, systemImage: String, key: String) -> some View {
        HStack(spacing: 6) {
            if busy == key { ProgressView() } else { Image(systemName: systemImage) }
            Text(title)
        }
        .frame(minHeight: 44)
    }

    private func run(_ key: String, _ work: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = key
        editing = false
        error = nil
        Task {
            defer { busy = nil }
            do { try await work() } catch is CancellationError {} catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.error = message
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }

    private func edit(_ change: (inout PodcastScript) -> Void) {
        guard busy == nil, var script = episode.script else { return }
        change(&script)
        // Konu silinince/taşınınca küresel sahne indeksleri kayar; zayıf sahne listesi geçersizleşir.
        script.quality?.weakScenes = []
        generator.updateDraftScript(episode, script, context: context)
    }

    /// "Cilala": zayıf sahneyi aynı içerikle yeniden yazdırır (tempo, derinlik, konuk ve sayfalarla).
    private func polish(_ item: WeakScene) async throws {
        guard let script = episode.script, let settings = episode.settings,
              let flat = script.flatScenes[safe: item.scene],
              let key = ScriptEditing.sceneKey(item.scene, in: script) else { return }
        let chapter = script.chapters[safe: flat.chapterIndex]
        let all = script.flatScenes
        let before = all[safe: item.scene - 1]?.scene.turns.map(\.text).joined(separator: " ")
        let after = all[safe: item.scene + 1]?.scene.turns.map(\.text).joined(separator: " ")
        let wanted = (chapter?.sourcePages ?? []) + flat.scene.turns.compactMap(\.sourcePage)
        let pages = wanted.isEmpty ? [] : await SourcePages.texts(for: episode, pages: Array(Set(wanted)).sorted(), maxChars: 30_000, context: context)
        let reasons = item.reasons.joined(separator: ", ")
        let turns = try await APIClient.shared.rewriteScene(RewriteSceneRequest(
            title: ServerText.prefix(script.title, 300), sourceNotes: ServerText.prefix(script.sourceNotes, 15_000),
            chapterTitle: ServerText.prefix(chapter?.title ?? "", 300),
            before: before.map { ServerText.prefix($0, 2000) }, after: after.map { ServerText.prefix($0, 2000) },
            scene: flat.scene,
            instruction: ServerText.prefix("Bu sahneyi aynı bilgilerle daha doğal ve öğretici yeniden yaz; boş onaylardan ve tekrarlardan kaçın. Sorunlar: \(reasons)", 300),
            settings: RewriteSettings(level: settings.level, tone: settings.tone, format: settings.format, language: settings.language,
                                      hostA: settings.hostA, hostB: settings.hostB, pace: settings.pace, depth: settings.depth, guest: settings.guest),
            pages: pages.isEmpty ? nil : pages))
        guard let current = episode.script, !turns.isEmpty, episode.needsApproval else { return }
        // Sahne küresel indeksle değil (konu başlığı, konu içi sıra) ile yeniden bulunur; konu silindiyse ya da sahne
        // bu arada değiştiyse sonuç atılır (başka sahnenin turları ezilmez).
        guard let polished = ScriptEditing.applyingPolish(turns, key: key, original: flat.scene, in: current) else {
            throw APIError(status: 0, code: "scene_changed", message: "Sahne bu arada değişti; Cilala sonucu uygulanmadı.")
        }
        generator.updateDraftScript(episode, polished.script, context: context)
    }

    static func styleTitle(_ style: String) -> String {
        switch style {
        case "sohbet": "Sohbet"
        case "anlatim": "Anlatım"
        case "hizliSoru": "Hızlı soru"
        case "vaka": "Vaka"
        default: style
        }
    }
}

/// Önizlemede konu metni (saf; test edilir): sahne sırasıyla turlar ve konuşmacı adları.
nonisolated enum ScriptPreviewText {
    struct Line: Equatable, Identifiable, Sendable {
        /// Konu içindeki tur sırası.
        var id: Int
        /// Konu içindeki sahne sırası (0 tabanlı).
        var sceneIndex: Int
        var speaker: String
        var text: String
        var page: Int?
    }

    static func lines(for chapter: ScriptChapter, settings: PodcastSettings) -> [Line] {
        var result: [Line] = []
        for (sceneIndex, scene) in chapter.scenes.enumerated() {
            for turn in scene.turns {
                result.append(Line(id: result.count, sceneIndex: sceneIndex, speaker: settings.displayName(for: turn.speaker),
                                   text: turn.text, page: turn.sourcePage))
            }
        }
        return result
    }
}

/// Onaylanacak ya da cilalanacak konunun metni (salt okunur). Sahne numaraları ana ekrandaki gibi bölüm geneline göredir.
private struct ChapterTextSheet: View {
    var episode: Episode
    var target: ScriptPreviewView.ChapterReading
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let script = episode.script
        let chapter = script?.chapters[safe: target.chapter]
        let lines = chapter.map { ScriptPreviewText.lines(for: $0, settings: episode.settings ?? PodcastSettings()) } ?? []
        let firstScene = script?.chapters.prefix(target.chapter).reduce(0) { $0 + $1.scenes.count } ?? 0
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // Bir konu birkaç sahnedir: tembel yığın gerekmez, hedef sahneye kaydırma da güvenilir olur.
                    VStack(alignment: .leading, spacing: 20) {
                        if lines.isEmpty {
                            Text("Bu konunun metni okunamadı.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(Set(lines.map(\.sceneIndex))).sorted(), id: \.self) { sceneIndex in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("Sahne \(firstScene + sceneIndex + 1)").font(.footnote.weight(.semibold))
                                    if target.scene == sceneIndex {
                                        Label("Zayıf sahne", systemImage: "exclamationmark.bubble").font(.caption)
                                    }
                                }
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                                ForEach(lines.filter { $0.sceneIndex == sceneIndex }) { line in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(line.speaker).font(.caption.bold()).foregroundStyle(.tint)
                                            if let page = line.page {
                                                Text("s. \(page)").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        Text(line.text).font(.body).fixedSize(horizontal: false, vertical: true)
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .id(sceneIndex)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .onAppear {
                    if let scene = target.scene { proxy.scrollTo(scene, anchor: .top) }
                }
            }
            .navigationTitle(chapter?.title ?? "Konu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}
