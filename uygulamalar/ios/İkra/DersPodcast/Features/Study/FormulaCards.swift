import SwiftData
import SwiftUI

/// Kavram ve formül listesinin saf mantığı (testlenir): bölüm JSON'larının çözümü, arama ve tür süzgeci.
nonisolated enum FormulaCards {
    enum Kind: String, CaseIterable, Sendable {
        case concept = "kavram", formula = "formül"
    }

    struct Item: Identifiable, Sendable {
        let id = UUID()
        var episode: String
        var name: String
        var body: String
        var kind: Kind
        /// Ad ve gövdenin katlanmış hâli: arama her tuş vuruşunda yeniden katlamaz.
        var key: String
    }

    /// Bir bölümün ham JSON alanları: ana aktörde yalnız bunlar toplanır, çözüm arka planda yapılır.
    struct Blob: Sendable {
        var title: String
        var concepts: Data?
        var study: Data?
    }

    /// `Episode.concepts` ile aynı kural: kavram alanı yoksa ya da çözülemiyorsa çalışma paketindeki kavramlar.
    static func items(_ blobs: [Blob]) -> [Item] {
        let decoder = JSONDecoder()
        var out: [Item] = []
        for blob in blobs {
            let study = blob.study.flatMap { try? decoder.decode(StudyPack.self, from: $0) }
            let concepts = blob.concepts.flatMap { try? decoder.decode([Concept].self, from: $0) } ?? study?.concepts ?? []
            for c in concepts {
                out.append(Item(episode: blob.title, name: c.name, body: c.definition, kind: .concept,
                                key: StudySearch.key([c.name, c.definition])))
            }
            for f in study?.formulas ?? [] {
                let body = "\(f.expression)\n\(f.meaning)\(f.when.isEmpty ? "" : "\nNe zaman: \(f.when)")"
                out.append(Item(episode: blob.title, name: f.name, body: body, kind: .formula, key: StudySearch.key([f.name, body])))
            }
        }
        return out
    }

    @concurrent
    static func decode(_ blobs: [Blob]) async -> [Item] { items(blobs) }

    /// `kind` nil: tümü. Boş sorgu yalnız türe bakar.
    static func filter(_ items: [Item], query: String, kind: Kind?) -> [Item] {
        items.filter { (kind == nil || $0.kind == kind) && StudySearch.matches(key: $0.key, query: query) }
    }
}

/// Tüm bölümlerin kavram ve formül kartları; sınav öncesi "tek sayfa özet" PDF.
struct FormulaCardsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Episode.createdAt, order: .reverse) private var episodes: [Episode]
    @State private var query = ""
    @State private var kind: FormulaCards.Kind?
    @State private var shareURL: URL?
    @State private var all: [FormulaCards.Item] = []
    @State private var loaded = false

    private var items: [FormulaCards.Item] { FormulaCards.filter(all, query: query, kind: kind) }

    var body: some View {
        NavigationStack {
            let shown = items
            List {
                Picker("Tür", selection: $kind) {
                    Text("Tümü").tag(FormulaCards.Kind?.none)
                    Text("Kavram").tag(FormulaCards.Kind?.some(.concept))
                    Text("Formül").tag(FormulaCards.Kind?.some(.formula))
                }
                .modifier(AccessiblePickerStyle())
                .listRowSeparator(.hidden)
                if !loaded {
                    ProgressView("Kavramlar okunuyor…").frame(maxWidth: .infinity)
                } else if all.isEmpty {
                    Text("Henüz kavram yok. Bölümler hazır olunca kavramlar otomatik çıkarılır.").foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text(emptyNote).foregroundStyle(.secondary)
                }
                ForEach(shown) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.name).font(.headline)
                            Spacer()
                            Text(item.kind.rawValue).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(item.kind == .formula ? Theme.goldInk.opacity(0.2) : Color.gray.opacity(0.15)))
                        }
                        Text(item.body).font(.subheadline)
                        Text(item.episode).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kavram veya formül ara")
            .navigationTitle("Kavram ve formüller")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tek sayfa özet", systemImage: "doc.text") { shareURL = CheatSheet.render(shown.map { ($0.name, $0.body, $0.episode) }) }
                        .disabled(shown.isEmpty)
                }
            }
            .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
            .task {
                // Ana aktörde yalnız ham veri toplanır; JSON arka planda bir kez çözülür.
                let blobs = episodes.filter { $0.status == .ready }
                    .map { FormulaCards.Blob(title: $0.title, concepts: $0.conceptsData, study: $0.studyData) }
                all = await FormulaCards.decode(blobs)
                loaded = true
            }
            .debugNarrowScreen()
        }
    }

    private var emptyNote: String {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch kind {
        case .formula: return searching ? "Aramayla eşleşen formül yok." : "Bu bölümlerde formül yok."
        case .concept: return searching ? "Aramayla eşleşen kavram yok." : "Bu bölümlerde kavram yok."
        case nil: return "Aramayla eşleşen kavram ya da formül yok."
        }
    }
}

/// Sınav öncesi tek sayfalık (gerekirse çok sayfalı) özet PDF'i.
enum CheatSheet {
    /// Gövdenin sayfada kaplayacağı tahmini satır sayısı (9 punto, satır başına yaklaşık 100 karakter; en çok 5 satır basılır).
    nonisolated static let bodyLineLimit = 5

    nonisolated static func bodyLines(_ body: String) -> Int {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, ($1.count + 99) / 100) }
        return min(bodyLineLimit, max(1, lines))
    }

    /// Satırın maliyeti gövde satırı biriminde: ad ve bölüm adı için 2, gövde için satır sayısı.
    nonisolated static func cost(_ row: (String, String, String)) -> Int { 2 + bodyLines(row.1) }

    /// Satırları, maliyet toplamı `capacity`yi aşmayacak sayfalara böler (sıra korunur, satır atlanmaz).
    /// 58: birim başına en çok yer tutan durumda bile (tek satırlık gövdeler, birim başına yaklaşık 13 nokta) A4'te
    /// başlık ve kenar boşluğundan kalan 760 noktaya sığar.
    nonisolated static func pages(_ rows: [(String, String, String)], capacity: Int = 58) -> [[(String, String, String)]] {
        var out: [[(String, String, String)]] = []
        var page: [(String, String, String)] = []
        var used = 0
        for row in rows {
            let weight = cost(row)
            if !page.isEmpty, used + weight > capacity {
                out.append(page)
                page = []
                used = 0
            }
            page.append(row)
            used += weight
        }
        if !page.isEmpty { out.append(page) }
        return out
    }

    static func render(_ rows: [(String, String, String)]) -> URL? {
        let url = URL.temporaryDirectory.appending(path: "Ozet-\(Int(Date.now.timeIntervalSince1970)).pdf")
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }
        for chunk in pages(rows) {
            let page = VStack(alignment: .leading, spacing: 6) {
                Text("Tek sayfa özet · Ders Podcast").font(.system(size: 14, weight: .bold))
                ForEach(Array(chunk.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.0).font(.system(size: 10, weight: .bold))
                        Text(row.1).font(.system(size: 9)).lineLimit(bodyLineLimit)
                        Text(row.2).font(.system(size: 7)).foregroundStyle(.gray)
                    }
                }
            }
            .padding(28)
            .frame(width: 595, height: 842, alignment: .topLeading)
            .background(Color.white)
            .foregroundStyle(.black)
            .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: page)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
        return url
    }
}
