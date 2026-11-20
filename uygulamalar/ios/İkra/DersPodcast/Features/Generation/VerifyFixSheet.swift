import SwiftData
import SwiftUI

/// #5: doğrulamanın işaretlediği cümleler için düzeltme önerisi; hazır bölümde "Düzeltmeyi uygula ve seslendir"
/// yalnız etkilenen sahneleri yeniden seslendirir (`SceneEditor.replace`).
struct VerifyFixSheet: View {
    let episode: Episode
    let focusTurn: Int?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(GenerationCoordinator.self) private var generator
    @Environment(AppState.self) private var app
    @State private var proposals: [Int: String] = [:]
    @State private var working = false
    @State private var error: String?

    init(episode: Episode, focusTurn: Int?) {
        self.episode = episode
        self.focusTurn = focusTurn
    }

    private var issues: [ScriptIssue] {
        let open = (episode.verification ?? []).filter { $0.fixedAt == nil }
        guard let focusTurn else { return open }
        let focused = open.filter { $0.index == focusTurn }
        return focused.isEmpty ? open : focused
    }

    private var turns: [ScriptTurn] { episode.script.map(ScriptEditing.allTurns) ?? [] }

    var body: some View {
        NavigationStack {
            List {
                if issues.isEmpty {
                    Text("Düzeltme önerisi yok").foregroundStyle(.secondary)
                }
                ForEach(issues, id: \.index) { issue in
                    Section {
                        if let turn = turns[safe: issue.index] {
                            Text(turn.text).font(.callout)
                        }
                        Label(issue.reason, systemImage: "exclamationmark.bubble").font(.caption).foregroundStyle(.orange)
                        if let quote = issue.quote {
                            Text("Belgede: “\(quote)”" + (issue.page.map { " (s. \($0))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                        }
                        if let proposal = proposals[issue.index] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Önerilen").font(.caption.bold()).foregroundStyle(.green)
                                Text(proposal).font(.callout)
                            }
                        } else if let correction = issue.correction {
                            Text("Doğrusu: \(correction)").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(Self.severityTitle(issue.severity))
                    }
                }
                if let error {
                    Label(error, systemImage: "xmark.octagon").foregroundStyle(.red).font(.callout)
                }
            }
            .navigationTitle("Düzeltme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() }.disabled(working) }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .interactiveDismissDisabled(working)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if !issues.isEmpty {
            VStack(spacing: 8) {
                if !app.serverSupports("podcast2") {
                    Text("Bu sunucu otomatik düzeltme önermiyor.").font(.caption).foregroundStyle(.secondary)
                } else if proposals.isEmpty {
                    Button { Task { await propose() } } label: {
                        HStack { if working { ProgressView() }; Text("Düzeltme öner") }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                } else if episode.status == .ready {
                    Button { Task { await apply() } } label: {
                        HStack { if working { ProgressView() }; Text("Düzeltmeyi uygula ve seslendir") }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working)
                    Text("Yalnızca etkilenen sahneler yeniden seslendirilir.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.bar)
        }
    }

    private func propose() async {
        guard let script = episode.script, let settings = episode.settings else { return }
        working = true
        error = nil
        defer { working = false }
        let wanted = issues.compactMap(\.page) + ScriptEditing.referencedPages(script)
        let pages = await SourcePages.texts(for: episode, pages: Array(Set(wanted)).sorted(), maxChars: 60_000, context: context)
        do {
            let candidates = issues.compactMap { issue in
                turns[safe: issue.index].flatMap { FixTurnsTurn.make(index: issue.index, turn: $0, issue: issue) }
            }
            guard !candidates.isEmpty else {
                error = "Bu cümleler otomatik düzeltilemeyecek kadar uzun."
                return
            }
            let fixed = try await APIClient.shared.fixTurns(FixTurnsRequest(
                title: ServerText.prefix(script.title, 300), sourceNotes: ServerText.prefix(script.sourceNotes, 15_000),
                pages: pages.isEmpty ? nil : Array(pages.prefix(40)), settings: FixTurnsSettings(settings),
                turns: Array(candidates.prefix(40))))
            proposals = Dictionary(fixed.map { ($0.index, $0.text) }, uniquingKeysWith: { a, _ in a })
            if proposals.isEmpty { error = "Düzeltme önerisi alınamadı." }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Etkilenen her sahne yeni turlarla değiştirilir ve yeniden seslendirilir.
    private func apply() async {
        guard let script = episode.script else { return }
        working = true
        error = nil
        defer { working = false }
        let fixes = proposals.map { FixedTurn(index: $0.key, text: $0.value, style: nil) }
        let fixedScript = ScriptEditing.applyFixes(fixes, to: script)
        let scenes = Set(fixes.compactMap { ScriptEditing.locate($0.index, in: script)?.scene }).sorted()
        // `SceneEditor.replace` her sahnede doğrulamayı sıfırlar; düzeltmeler tur sayısını değiştirmediği için
        // kalan bulguların indeksleri geçerlidir: önceki liste saklanır, yalnız uygulananlar işaretlenir.
        let before = episode.verification
        var applied: Set<Int> = []
        defer {
            if !applied.isEmpty || episode.verification == nil, !episode.isDeleted, episode.modelContext != nil {
                episode.verification = ScriptEditing.markingFixed(before, turns: applied)
                try? context.save()
            }
        }
        do {
            for scene in scenes {
                guard let turns = fixedScript.flatScenes[safe: scene]?.scene.turns else { continue }
                try await SceneEditor.replace(episode, sceneIndex: scene, turns: turns, context: context, generator: generator)
                applied.formUnion(fixes.map(\.index).filter { ScriptEditing.locate($0, in: script)?.scene == scene })
            }
            dismiss()
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    nonisolated static func severityTitle(_ severity: String) -> String {
        switch severity {
        case "uydurma": "Belgede yok"
        case "hatali": "Hatalı"
        case "belirsiz": "Belirsiz"
        default: severity
        }
    }
}
