import SwiftData
import SwiftUI

/// Kavram haritası: düğümler kavramlar, kenarlar `related` ilişkileri.
struct ConceptMapView: View {
    var concepts: [Concept]
    /// Ustalık renkleri için: bu bölümün tekrar kartları.
    var episodeID: UUID?
    @Query private var cards: [ReviewCard]
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var modelContext
    @State private var selected: Concept?
    @State private var layout: [String: CGPoint] = [:]
    @State private var width: CGFloat = 0

    /// Tuval ekran genişliğinde; yalnızca dikey kayar. Eskiden 760×760 tuval iki eksende kaydığı için
    /// aşağı kaydırırken ekran sağa sola oynuyordu.
    static func canvasSize(width: CGFloat, count: Int) -> CGSize {
        let w = max(280, width)
        // Düğüm başına yaklaşık 24 000 nokta² alan; en az ekran genişliğinin 1,1 katı, en fazla 3 ekran boyu.
        let h = min(max(w * 1.1, CGFloat(count) * 24_000 / w), w * 3)
        return CGSize(width: w, height: h)
    }

    private var canvas: CGSize { Self.canvasSize(width: width, count: ConceptLayout.unique(concepts).count) }

    var body: some View {
        // Ustalık tek geçişte hesaplanır (düğüm başına bütün kartlar yeniden taranmaz).
        let nodes = ConceptLayout.unique(concepts)
        let scores = Mastery.scores(names: nodes.map(\.name), cards: episodeCards)
        VStack(spacing: 6) {
            if episodeID != nil { legend }
            map(nodes, scores: scores)
        }
        .sheet(item: $selected) { concept in
            // #16: zaman bu bölümün kendi zaman çizelgesinden; oynatıcıda başka bölüm çalıyor olabilir.
            ConceptDetail(concept: concept, mention: ConceptLayout.firstMention(of: concept.name, in: mapEpisode?.timeline),
                          episodeID: episodeID, mastery: scores[concept.name]) { time in
                selected = nil
                if let episode = mapEpisode, player.episode?.id != episode.id {
                    player.play(episode, at: time, context: modelContext)
                    if player.episode?.id == episode.id { player.seek(to: time) }
                } else {
                    player.seek(to: time)
                    player.play()
                }
            } selectRelated: { name in
                selected = concepts.first { $0.name == name }
            }
            .presentationDetents([.medium])
        }
    }

    /// Dolgu renklerinin anlamı (renk tek başına bilgi taşımasın: düğümün erişilebilirlik değeri de aynısını söyler).
    private var legend: some View {
        FlowLayout(spacing: 10) {
            legendItem("Zayıf", .red)
            legendItem("Öğreniliyor", .orange)
            legendItem("Öğrenildi", .green)
            legendItem("Çalışılmadı", .gray)
        }
        .font(.caption2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Renkler: kırmızı zayıf, turuncu öğreniliyor, yeşil öğrenildi, gri henüz çalışılmadı")
    }

    private func legendItem(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color.opacity(0.35)).overlay(Circle().strokeBorder(color.opacity(0.8))).frame(width: 10, height: 10)
            Text(title).foregroundStyle(.secondary)
        }
    }

    private func map(_ nodes: [Concept], scores: [String: Double]) -> some View {
        ScrollView(.vertical) {
            ZStack {
                Canvas { context, _ in
                    for (a, b) in ConceptLayout.edges(concepts) {
                        guard let p = layout[a], let q = layout[b] else { continue }
                        var path = Path()
                        path.move(to: p)
                        path.addLine(to: q)
                        let highlighted = selected.map { $0.name == a || $0.name == b } ?? false
                        context.stroke(path, with: .color(highlighted ? .accentColor : .secondary.opacity(0.35)),
                                       lineWidth: highlighted ? 2.5 : 1.2)
                    }
                }
                ForEach(nodes, id: \.name) { concept in
                    if let point = layout[concept.name] {
                        Button { selected = concept } label: {
                            Text(concept.name)
                                .font(.footnote.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .allowsTightening(true)
                                // Uzun kavram adları (Kemoheterotrof) kelime ortasından bölünmesin.
                                .dynamicTypeSize(...DynamicTypeSize.large)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: min(150, canvas.width * 0.42))
                                .background(selected?.name == concept.name ? AnyShapeStyle(Theme.gradient) : masteryFill(scores[concept.name]),
                                            in: Capsule())
                                .overlay(Capsule().strokeBorder(.tint.opacity(0.35)))
                                .foregroundStyle(selected?.name == concept.name ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(scores[concept.name].map(Mastery.label) ?? "Henüz çalışılmadı")
                        .position(point)
                    }
                }
            }
            .frame(width: canvas.width, height: canvas.height)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            guard abs(new - width) > 1 else { return }
            width = new
            layout = ConceptLayout.compute(ConceptLayout.unique(concepts), in: canvas)
        }
        .onChange(of: concepts) { _, new in layout = ConceptLayout.compute(ConceptLayout.unique(new), in: canvas) }
    }
}

extension Concept: Identifiable {
    var id: String { name }
}

extension ConceptMapView {
    /// Haritanın ait olduğu bölüm.
    fileprivate var mapEpisode: Episode? {
        guard let id = episodeID else { return nil }
        return try? modelContext.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })).first
    }

    fileprivate var episodeCards: [ReviewCard] {
        guard let episodeID else { return [] }
        return cards.filter { $0.episodeID == episodeID }
    }

    /// Kırmızı = zayıf, turuncu = öğreniliyor, yeşil = öğrenildi; kartı olmayan ya da hiç çalışılmamış kavram nötr.
    fileprivate func masteryFill(_ score: Double?) -> AnyShapeStyle {
        guard let score else { return AnyShapeStyle(.background.secondary) }
        return AnyShapeStyle(Mastery.color(score).opacity(0.25))
    }
}

/// Kavram ustalığı: kavramı içeren tekrar kartlarındaki performans (0…1); kart yoksa nil.
nonisolated enum Mastery {
    /// Bir kartın ustalık örneği. `reviewed`: kart en az bir kez tekrar edildi ya da yanlış yapılan sorudan açıldı.
    typealias Sample = (repetitions: Int, lapses: Int, reviewed: Bool)

    /// Örneklerin ortalaması. Hiç çalışılmamış kart (tekrar edilmemiş, yanlışı yok) ortalamaya girmez; hepsi öyleyse nil:
    /// yeni üretilmiş pakette bütün harita "Zayıf" görünmesin.
    static func score(samples: [Sample]) -> Double? {
        let values = samples.compactMap { sample -> Double? in
            if sample.lapses > 0 && sample.repetitions < 2 { return 0 }
            if sample.repetitions >= 2 && sample.lapses == 0 { return 1 }
            if sample.repetitions >= 1 { return 0.6 }
            return sample.reviewed ? 0.3 : nil
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Adı verilen kavramların ustalığı tek geçişte: kart metni bir kez küçük harfe çevrilir. Puanı olmayan kavram sözlükte yoktur.
    static func scores(names: [String], cards: [(text: String, sample: Sample)]) -> [String: Double] {
        let tr = Locale(identifier: "tr")
        let lowered = cards.map { (text: $0.text.lowercased(with: tr), sample: $0.sample) }
        var out: [String: Double] = [:]
        for name in names where out[name] == nil {
            let needle = name.lowercased(with: tr)
            if let value = score(samples: lowered.filter { $0.text.contains(needle) }.map(\.sample)) { out[name] = value }
        }
        return out
    }

    /// Yanlış yapılan sorunun kartı (`.quiz`) henüz tekrar edilmemiş olsa da çalışılmış sayılır: kavram "Zayıf" görünür
    /// (Tekrar ekranındaki `ReviewCard.isWeak` ile aynı kural). Hiç açılmamış flashcard nötr kalır.
    static func scores(names: [String], cards: [ReviewCard]) -> [String: Double] {
        scores(names: names, cards: cards.map {
            (text: $0.front + " " + $0.back,
             sample: (repetitions: $0.repetitions, lapses: $0.lapses, reviewed: $0.lastReviewed != nil || $0.kind == .quiz))
        })
    }

    static func score(for concept: String, cards: [ReviewCard]) -> Double? {
        let tr = Locale(identifier: "tr")
        let needle = concept.lowercased(with: tr)
        let related = cards.filter { ($0.front + " " + $0.back).lowercased(with: tr).contains(needle) }
        guard !related.isEmpty else { return nil }
        let values = related.map { card -> Double in
            if card.lapses > 0 && card.repetitions < 2 { return 0 }
            if card.repetitions >= 2 && card.lapses == 0 { return 1 }
            return card.repetitions >= 1 ? 0.6 : 0.3
        }
        return values.reduce(0, +) / Double(values.count)
    }

    static func color(_ score: Double) -> Color {
        score >= 0.75 ? .green : score >= 0.4 ? .orange : .red
    }

    static func label(_ score: Double) -> String {
        score >= 0.75 ? "Öğrenildi" : score >= 0.4 ? "Öğreniliyor" : "Zayıf"
    }
}

/// Kavramın geçtiği başka bir bölüm; `time`: transkriptte ilk geçtiği an (yalnız kavram listesinde varsa nil).
nonisolated struct OtherMention: Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var time: Double?
}

private struct ConceptDetail: View {
    var concept: Concept
    /// Kavramın bu bölümde ilk geçtiği an.
    var mention: Double?
    var episodeID: UUID?
    var mastery: Double?
    var play: (Double) -> Void
    var selectRelated: (String) -> Void
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @Environment(PlayerController.self) private var player
    @Environment(\.modelContext) private var context
    /// Aynı kavramın geçtiği diğer bölümler (öneri 12). Bütün bölümlerin transkripti arka planda bir kez taranır;
    /// `othersFor`: sonucun ait olduğu kavram (ilişkili kavrama geçilince eski sonuç gösterilmez).
    @State private var others: [OtherMention] = []
    @State private var othersFor: String?

    @State private var figureThumbs: [(SourceFigure, UIImage)] = []
    @State private var zoom: SourceFigure?

    /// Kavramla ilgili kaynak şekilleri: başlığında kavram geçen ya da aynı sayfadaki şekiller.
    static func relatedFigures(_ concept: Concept, in figures: [SourceFigure]) -> [SourceFigure] {
        let fold = { (t: String) in t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr")) }
        let needle = fold(concept.name)
        return figures.filter { fold($0.caption).contains(needle) || (concept.sourcePage != nil && $0.page == concept.sourcePage) }
    }

    var body: some View {
        NavigationStack {
            let otherEpisodes = othersFor == concept.name ? others : []
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(concept.definition).font(.body)
                        .task {
                            guard let id = episodeID, let episode = episodes.first(where: { $0.id == id }) else { return }
                            var out: [(SourceFigure, UIImage)] = []
                            for f in Self.relatedFigures(concept, in: episode.sourceFigures).prefix(4) {
                                if let img = await DeckAssets.thumbnail(episode.figureURL(f.id)) { out.append((f, img)) }
                            }
                            figureThumbs = out
                        }
                        .fullScreenCover(item: $zoom) { f in
                            if let id = episodeID, let episode = episodes.first(where: { $0.id == id }) { FigureZoomView(episode: episode, figure: f) }
                        }
                    if !figureThumbs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(figureThumbs, id: \.0.id) { figure, image in
                                    Button { zoom = figure } label: {
                                        Image(uiImage: image).resizable().scaledToFit().frame(height: 90)
                                            .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if let page = concept.sourcePage {
                        Text("Kaynak: sayfa \(page)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let time = mention {
                        Button {
                            play(time)
                        } label: {
                            Label("Podcast'te dinle (\(time.clockText))", systemImage: "play.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let mastery {
                        Label("\(Mastery.label(mastery)) · %\(Int(mastery * 100))", systemImage: "chart.bar.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Mastery.color(mastery))
                    }
                    if !otherEpisodes.isEmpty {
                        Text("Diğer bölümlerde").font(.headline).padding(.top, 4)
                        ForEach(otherEpisodes) { entry in
                            Button {
                                guard let episode = episodes.first(where: { $0.id == entry.id }) else { return }
                                player.load(episode, context: context, autoplay: false)
                                if let time = entry.time { player.seek(to: time) }
                                player.play()
                                AppState.current?.pendingOpenEpisode = episode.id
                            } label: {
                                HStack {
                                    Image(systemName: "link")
                                    Text(entry.title).lineLimit(2).multilineTextAlignment(.leading)
                                    Spacer()
                                    if let time = entry.time { Text(time.clockText).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                    if !concept.related.isEmpty {
                        Text("İlişkili kavramlar").font(.headline).padding(.top, 4)
                        FlowLayout(spacing: 8) {
                            ForEach(concept.related, id: \.self) { name in
                                Button(name) { selectRelated(name) }
                                    .font(.subheadline)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle(concept.name)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: concept.name) {
                // Ana aktörde yalnız ham JSON toplanır; çözme ve tarama arka planda.
                let name = concept.name
                let blobs = episodes.filter { $0.id != episodeID && $0.status == .ready }.map {
                    ConceptLayout.EpisodeBlob(id: $0.id, title: $0.title, concepts: $0.conceptsData, study: $0.studyData, timeline: $0.timelineData)
                }
                let found = await ConceptLayout.mentions(of: name, in: blobs)
                guard !Task.isCancelled else { return }
                others = found
                othersFor = name
            }
        }
    }
}

/// Satır sonuna gelince alt satıra geçen basit yerleşim.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

nonisolated enum ConceptLayout {
    /// Aynı adlı kavramlar (model bazen tekrarlar) tek düğüm olsun; ilk geçen kalır.
    static func unique(_ concepts: [Concept]) -> [Concept] {
        var seen = Set<String>()
        return concepts.filter { !$0.name.isEmpty && seen.insert($0.name).inserted }
    }

    /// Yalnızca listede bulunan kavramlar arasındaki tekil kenarlar.
    static func edges(_ concepts: [Concept]) -> [(String, String)] {
        let names = Set(concepts.map(\.name))
        var seen = Set<String>()
        var result: [(String, String)] = []
        for c in concepts {
            for r in c.related where names.contains(r) && r != c.name {
                let key = [c.name, r].sorted().joined(separator: "\u{1}")
                if seen.insert(key).inserted { result.append((c.name, r)) }
            }
        }
        return result
    }

    /// Kuvvet yönelimli yerleşim (deterministik: başlangıç çember üzerinde).
    static func compute(_ concepts: [Concept], in size: CGSize, iterations: Int = 300) -> [String: CGPoint] {
        let n = concepts.count
        guard n > 0 else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.38
        var pos = (0..<n).map { i -> CGPoint in
            let angle = Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        let index = Dictionary(concepts.enumerated().map { ($1.name, $0) }, uniquingKeysWith: { first, _ in first })
        let links = edges(concepts).compactMap { a, b in index[a].flatMap { i in index[b].map { (i, $0) } } }
        let ideal = sqrt(size.width * size.height / Double(max(n, 1))) * 0.8

        for step in 0..<iterations {
            var force = Array(repeating: CGPoint.zero, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                    let d = max(sqrt(dx * dx + dy * dy), 1)
                    let f = ideal * ideal / d
                    force[i].x += dx / d * f; force[i].y += dy / d * f
                    force[j].x -= dx / d * f; force[j].y -= dy / d * f
                }
            }
            for (i, j) in links {
                let dx = pos[i].x - pos[j].x, dy = pos[i].y - pos[j].y
                let d = max(sqrt(dx * dx + dy * dy), 1)
                let f = d * d / ideal
                force[i].x -= dx / d * f; force[i].y -= dy / d * f
                force[j].x += dx / d * f; force[j].y += dy / d * f
            }
            let temperature = Double(size.width) * 0.1 * (1 - Double(step) / Double(iterations)) + 1
            for i in 0..<n {
                let fx = force[i].x, fy = force[i].y
                let len = max(sqrt(fx * fx + fy * fy), 0.001)
                pos[i].x += fx / len * min(len, temperature)
                pos[i].y += fy / len * min(len, temperature)
                // Kenar payı ekran genişliğine oranlı: dar ekranda düğümler ortada iki sütuna sıkışmasın.
                let margin = min(80, size.width * 0.22)
                pos[i].x = min(max(pos[i].x, margin), size.width - margin)
                pos[i].y = min(max(pos[i].y, 30), size.height - 30)
            }
        }
        return Dictionary(concepts.enumerated().map { ($1.name, pos[$0]) }, uniquingKeysWith: { first, _ in first })
    }

    /// Kavramın transkriptte ilk geçtiği tur (Türkçe büyük/küçük harf duyarsız).
    static func firstMention(of name: String, in timeline: Timeline?) -> Double? {
        let tr = Locale(identifier: "tr")
        let needle = name.lowercased(with: tr)
        return timeline?.turns.first { $0.text.lowercased(with: tr).contains(needle) }?.start
    }

    // MARK: - Kavramın geçtiği diğer bölümler

    /// Bir bölümün ham JSON alanları (ana aktörde toplanır, arka planda çözülür).
    struct EpisodeBlob: Sendable {
        var id: UUID
        var title: String
        var concepts: Data?
        var study: Data?
        var timeline: Data?
    }

    /// Yalnız gereken alanlar çözülür (paketin soruları, zaman çizelgesinin konuları atlanır).
    private struct StudyConcepts: Decodable { var concepts: [Concept]? }
    private struct Transcript: Decodable {
        struct Turn: Decodable { var text: String; var start: Double }
        var turns: [Turn]
    }

    /// Kavramın kavram listesinde ya da transkriptinde geçtiği bölümler, verilen sırayla.
    /// `Episode.concepts` ile aynı kural: kavram alanı yoksa çalışma paketindeki kavramlara bakılır.
    static func mentionsNow(of name: String, in blobs: [EpisodeBlob]) -> [OtherMention] {
        let tr = Locale(identifier: "tr")
        let needle = name.lowercased(with: tr)
        guard !needle.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var out: [OtherMention] = []
        for blob in blobs {
            if Task.isCancelled { return [] }
            let transcript = blob.timeline.flatMap { try? decoder.decode(Transcript.self, from: $0) }
            let time = transcript?.turns.first { $0.text.lowercased(with: tr).contains(needle) }?.start
            if time == nil {
                var concepts = blob.concepts.flatMap { try? decoder.decode([Concept].self, from: $0) }
                if concepts == nil { concepts = blob.study.flatMap { try? decoder.decode(StudyConcepts.self, from: $0) }?.concepts }
                guard let concepts, concepts.contains(where: { $0.name.lowercased(with: tr) == needle }) else { continue }
            }
            out.append(OtherMention(id: blob.id, title: blob.title, time: time))
        }
        return out
    }

    @concurrent
    static func mentions(of name: String, in blobs: [EpisodeBlob]) async -> [OtherMention] { mentionsNow(of: name, in: blobs) }
}
