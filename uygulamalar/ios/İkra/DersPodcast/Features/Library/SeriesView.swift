import SwiftData
import SwiftUI

/// #39: seri işlemleri (saf mantık; test edilir).
nonisolated enum SeriesOps {
    /// "3/7 dinlendi".
    static func progress(_ items: [EpisodeListItem]) -> (listened: Int, total: Int) {
        (items.filter(\.isFinished).count, items.count)
    }

    static func progressText(_ items: [EpisodeListItem]) -> String {
        let p = progress(items)
        return "\(p.listened)/\(p.total) dinlendi"
    }

    /// Sürükle-bırak sonrası yeni sıra: kimlik → 1 tabanlı `seriesIndex`.
    static func reorder(_ ids: [UUID], from source: IndexSet, to destination: Int) -> [UUID: Int] {
        var list = ids
        list.move(fromOffsets: source, toOffset: destination)
        return Dictionary(uniqueKeysWithValues: list.enumerated().map { ($1, $0 + 1) })
    }

    /// Kaldığın yerden: sırada ilk bitmemiş hazır bölüm (yarım kalan öncelikli değil, sıra korunur).
    static func resumeTarget(_ items: [EpisodeListItem]) -> UUID? {
        items.filter { $0.statusRaw == "ready" }.sorted { $0.seriesIndex < $1.seriesIndex }.first { !$0.isFinished }?.id
    }

    /// Sıra numaralarındaki boşluğu kapatır: `index`, eşitse `createdAt` sırasıyla 1…n. Yalnız numarası değişenler döner.
    /// Seri sayfası ve satırlar bu numarayı gösterir ("1., 3., 4." kalmasın); "N. bölüm" etiketi gerçek sırayla uyuşsun.
    static func compacted(_ members: [(id: UUID, index: Int, createdAt: Date)]) -> [UUID: Int] {
        let ordered = members.sorted { ($0.index, $0.createdAt, $0.id.uuidString) < ($1.index, $1.createdAt, $1.id.uuidString) }
        var changes: [UUID: Int] = [:]
        for (offset, member) in ordered.enumerated() where member.index != offset + 1 { changes[member.id] = offset + 1 }
        return changes
    }
}

@MainActor
extension SeriesOps {
    /// Serilerdeki sıra boşluklarını kapatır (`only` verilirse yalnız o seride); numarası değişen oldu mu döner. Kaydetmez.
    /// `excluding`: seriden az önce çıkan/silinen bölüm (kayıtlarda hâlâ görünse de sayılmaz).
    /// Kuyrukta bölümü bekleyen seriye dokunulmaz: o bölüm kendi numarasıyla gelir, kapatılan sıra onunla çakışırdı.
    @discardableResult
    static func closeGaps(context: ModelContext, only: UUID? = nil, excluding: UUID? = nil) -> Bool {
        let members = ((try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.seriesID != nil }))) ?? [])
            .filter { $0.id != excluding }
        guard !members.isEmpty else { return false }
        let pending = Set(((try? context.fetch(FetchDescriptor<QueuedRequest>())) ?? []).compactMap { $0.settings?.series?.id })
        var changed = false
        for (series, group) in Dictionary(grouping: members, by: \.seriesID) {
            guard let series, only == nil || only == series, !pending.contains(series) else { continue }
            let changes = compacted(group.map { (id: $0.id, index: $0.seriesIndex, createdAt: $0.createdAt) })
            for episode in group { if let index = changes[episode.id] { episode.seriesIndex = index } }
            if !changes.isEmpty { changed = true }
        }
        return changed
    }
}

/// Kütüphanede serinin tek kartı.
struct SeriesCard: View {
    var title: String
    var items: [EpisodeListItem]
    var cover: VisualCover?

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                EpisodeArtwork(title: title, cover: cover)
                Image(systemName: "square.stack.fill")
                    .font(.caption2)
                    .padding(4)
                    .background(.thinMaterial, in: Circle())
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Seri · \(items.count) bölüm").font(.caption2.bold()).foregroundStyle(.tint)
                Text(title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                let p = SeriesOps.progress(items)
                ProgressView(value: Double(p.listened), total: Double(max(1, p.total)))
                Text(SeriesOps.progressText(items)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Seri sayfası: kaldığın yerden çal, adlandır, sürükleyerek sırala, var olan bölümü ekle, kitapçık.
struct SeriesView: View {
    let seriesID: UUID
    @Environment(AppState.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.seriesIndex) private var all: [Episode]
    @State private var renaming = false
    @State private var newName = ""
    @State private var adding = false
    @State private var shareURL: URL?
    @State private var error: String?
    @State private var exporting = false

    private var episodes: [Episode] { all.filter { $0.seriesID == seriesID }.sorted { $0.seriesIndex < $1.seriesIndex } }
    private var title: String { episodes.first?.seriesTitle ?? "Seri" }

    var body: some View {
        let items = episodes.map { EpisodeListItem($0) }
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(SeriesOps.progressText(items)).font(.subheadline.bold())
                    let p = SeriesOps.progress(items)
                    ProgressView(value: Double(p.listened), total: Double(max(1, p.total)))
                    if let id = SeriesOps.resumeTarget(items), let target = episodes.first(where: { $0.id == id }) {
                        Button {
                            player.load(target, context: context, autoplay: true)
                            app.open(target.id)
                        } label: {
                            Label(target.lastPosition > 5 ? "Kaldığın yerden: \(target.title)" : "Sıradaki: \(target.title)", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Bölümler") {
                ForEach(episodes) { e in
                    NavigationLink(value: e.id) {
                        HStack(spacing: 10) {
                            Text("\(e.seriesIndex).").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.title).foregroundStyle(.primary).lineLimit(2)
                                Text(e.isFinished ? "Dinlendi" : e.lastPosition > 5 ? "Yarım" : e.duration.minutesText)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if e.isFinished { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true) }
                        }
                        .frame(minHeight: 44)
                    }
                    .swipeActions {
                        Button("Seriden çıkar", role: .destructive) { remove(e) }
                    }
                }
                .onMove { source, destination in
                    let order = SeriesOps.reorder(episodes.map(\.id), from: source, to: destination)
                    for e in episodes { if let i = order[e.id] { e.seriesIndex = i } }
                    try? context.save()
                }
            }
            Section {
                Button("Var olan bölümü ekle", systemImage: "plus") { adding = true }
                Button("Seriyi yeniden adlandır", systemImage: "pencil") { newName = title; renaming = true }
                Button {
                    Task { await exportBooklet() }
                } label: {
                    HStack {
                        Label(exporting ? "Kitapçık hazırlanıyor…" : "Kitapçık olarak al (PDF)", systemImage: "book")
                        if exporting { Spacer(minLength: 0); ProgressView() }
                    }
                }
                .disabled(exporting)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .alert("Seri adı", isPresented: $renaming) {
            TextField("Seri adı", text: $newName)
                .onChange(of: newName) { _, text in if text.count > 120 { newName = String(text.prefix(120)) } }
            Button("Vazgeç", role: .cancel) {}
            Button("Kaydet") { rename() }
        }
        .sheet(isPresented: $adding) { SeriesAddSheet(seriesID: seriesID, title: title) }
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for e in episodes { e.seriesTitle = String(name.prefix(120)) }
        try? context.save()
    }

    private func remove(_ episode: Episode) {
        episode.seriesID = nil
        episode.seriesTitle = nil
        episode.seriesIndex = 0
        for (i, e) in episodes.filter({ $0.id != episode.id }).enumerated() { e.seriesIndex = i + 1 }
        try? context.save()
    }

    private func exportBooklet() async {
        exporting = true
        error = nil
        defer { exporting = false }
        // Üretimi süren ya da başarısız bölüm kitapçığa girmez (paylaşım sayfasındaki kitapçıkla aynı kural).
        let members = episodes.filter { $0.status == .ready }
        guard !members.isEmpty else { error = "Seride hazır bölüm yok."; return }
        do { shareURL = try await StudySheetExport.writeSeriesPDF(members) } catch { self.error = error.localizedDescription }
    }
}

/// Seriye var olan (seride olmayan, hazır) bölümleri ekler; sona eklenir.
struct SeriesAddSheet: View {
    let seriesID: UUID
    let title: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List(episodes.filter { $0.seriesID == nil && $0.status == .ready }) { e in
                Button {
                    if selection.contains(e.id) { selection.remove(e.id) } else { selection.insert(e.id) }
                } label: {
                    HStack {
                        Image(systemName: selection.contains(e.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.tint)
                        Text(e.title).foregroundStyle(.primary).lineLimit(2)
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Seriye ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle (\(selection.count))") { add() }.disabled(selection.isEmpty)
                }
            }
        }
    }

    private func add() {
        var next = (episodes.filter { $0.seriesID == seriesID }.map(\.seriesIndex).max() ?? 0) + 1
        for e in episodes.filter({ selection.contains($0.id) }).sorted(by: { $0.createdAt < $1.createdAt }) {
            e.seriesID = seriesID
            e.seriesTitle = title
            e.seriesIndex = next
            next += 1
        }
        try? context.save()
        dismiss()
    }
}

#if DEBUG
/// Yalnız Debug: `-p7Demo` ile seri (3 bölüm) ve türev bölüm tohumlanır; `-p7Sheet=topics|backup|organize|documents|share|series` ekranı açar.
enum P7Demo {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-p7Demo") }

    static func seed(context: ModelContext) {
        guard isRequested, ((try? context.fetchCount(FetchDescriptor<Episode>(predicate: #Predicate { $0.title.contains("P7 Demo") }))) ?? 0) == 0 else { return }
        let series = UUID()
        var parent: Episode?
        for (i, title) in ["P7 Demo · Hücre zarı ve taşıma", "P7 Demo · Mitoz bölünme", "P7 Demo · Mayoz ve çeşitlilik"].enumerated() {
            let script = PodcastScript(title: title, summary: "Özet", keyPoints: ["Nokta"], chapters: [], sourceNotes: "", quality: nil)
            let e = Episode(script: script, settings: PodcastSettings(), sourceNames: ["Biyoloji notu.pdf"], jobToken: "")
            e.statusRaw = EpisodeStatus.ready.rawValue
            e.duration = 1200
            e.lastPosition = i == 0 ? 1200 : i == 1 ? 400 : 0
            e.isFinished = i == 0
            e.seriesID = series
            e.seriesTitle = "Biyoloji: Hücre"
            e.seriesIndex = i + 1
            context.insert(e)
            if i == 1 { parent = e }
        }
        let standalone = Episode(script: PodcastScript(title: "P7 Demo · Fotosentez", summary: "", keyPoints: [], chapters: [], sourceNotes: "", quality: nil),
                                 settings: PodcastSettings(), sourceNames: ["Not.pdf"], jobToken: "")
        standalone.statusRaw = EpisodeStatus.ready.rawValue
        standalone.duration = 900
        context.insert(standalone)
        let recap = Episode(script: PodcastScript(title: "P7 Demo · Fotosentez tekrar", summary: "", keyPoints: [], chapters: [], sourceNotes: "", quality: nil),
                            settings: PodcastSettings(), sourceNames: [], jobToken: "")
        recap.statusRaw = EpisodeStatus.ready.rawValue
        recap.duration = 300
        recap.derivedKind = "recap"
        recap.parentEpisodeID = standalone.id
        context.insert(recap)
        _ = parent
        try? context.save()
    }

    /// `-p7Sheet=documents` denetimi için uzun adlı örnek belge; iki demo bölüme kaynak olarak bağlanır (kullanım sayısı görünsün).
    static func seedDocument(context: ModelContext) {
        guard isRequested, ((try? context.fetchCount(FetchDescriptor<SourceDocument>(predicate: #Predicate { $0.name.contains("P7 Demo") }))) ?? 0) == 0 else { return }
        let id = UUID()
        let fileName = "\(id.uuidString).txt"
        let text = "Hücre zarı seçici geçirgendir. Küçük ve yüksüz moleküller difüzyonla, büyük moleküller taşıyıcı proteinlerle geçer."
        guard (try? text.write(to: DocumentStore.directory.appending(path: fileName), atomically: true, encoding: .utf8)) != nil else { return }
        let document = SourceDocument(name: "P7 Demo · Biyoloji 9. sınıf hücre zarı ve madde taşınması ders notu.txt", kind: "text", fileName: fileName, pageCount: 0)
        document.id = id
        context.insert(document)
        let demo = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.title.contains("P7 Demo") }))) ?? []
        for episode in demo.prefix(2) { episode.sourceDocumentIDs = (episode.sourceDocumentIDs ?? []) + [id] }
        try? context.save()
    }
}
#endif
