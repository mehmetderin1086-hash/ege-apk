import SwiftUI

extension DeckPalette {
    var accent: Color { Self.color(accentHex) }
    var secondary: Color { Self.color(secondaryHex) }
    var surface: Color { Self.color(surfaceHex) }
    private static func color(_ hex: String) -> Color {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255)
    }
    var exportTheme: DeckTheme { DeckTheme(accent: accentHex, secondary: secondaryHex, background: surfaceHex) }
}

extension DeckSlide {
    var kindTitle: String {
        switch kind {
        case "title": "Kapak"
        case "agenda": "Ders planı"
        case "section": "Bölüm"
        case "table": "Tablo"
        case "chart": "Grafik"
        case "diagram": "Şema"
        case "image": "İllüstrasyon"
        case "figure": "Kaynak görseli"
        case "twoColumn": "Görsel anlatım"
        case "timeline": "Zaman çizgisi"
        case "stat": "Sayılarla"
        case "quote": "Alıntı"
        case "summary": "Özet"
        default: "Konu anlatımı"
        }
    }

    /// Tam metin görünümü ve VoiceOver, tuvalde sığdırılan metnin tamamına erişebilir.
    var readableText: String {
        var parts = [title]
        if let subtitle { parts.append(subtitle) }
        parts += bullets ?? []
        if let table {
            parts.append(table.headers.joined(separator: " · "))
            parts += table.rows.map { $0.joined(separator: " · ") }
        }
        if let diagram { parts += diagram.nodes.map { [$0.title, $0.detail].filter { !$0.isEmpty }.joined(separator: ": ") } }
        if let timeline { parts += timeline.map { "\($0.label) · \($0.title): \($0.detail)" } }
        if let stat { parts.append("\(stat.value) · \(stat.label)\n\(stat.context)") }
        if let chart {
            parts.append(chart.title + (chart.unit.map { " (\($0))" } ?? ""))
            for series in chart.series {
                parts.append(series.name)
                parts += zip(chart.labels, series.values).map { "\($0): \($1.formatted())" }
            }
        }
        if let quote { parts.append(quote) }
        if let caption { parts.append(caption) }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Yoğun tabloların satırlarını kaybetmeden okunabilir sayfalara ayırır.
nonisolated enum DeckReadability {
    static func prepare(_ deck: Deck) -> Deck {
        var result = deck
        result.slides = deck.slides.flatMap { slide -> [DeckSlide] in
            guard slide.kind == "table", let table = slide.table, table.rows.count > 4 else { return [slide] }
            let total = (table.rows.count + 3) / 4
            return stride(from: 0, to: table.rows.count, by: 4).map { start in
                var page = slide
                page.title = String(slide.title.prefix(135)) + " · \(start / 4 + 1)/\(total)"
                page.table = DeckTable(headers: table.headers, rows: Array(table.rows[start..<min(start + 4, table.rows.count)]))
                return page
            }
        }
        return result
    }
}

struct DeckOverview: View {
    let deck: Deck
    let images: [Int: UIImage]
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                // 130: 320 nokta genişlikte (284 kullanılabilir) iki sütun sığar (130×2 + 14).
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 18) {
                    ForEach(Array(deck.slides.enumerated()), id: \.offset) { index, slide in
                        Button {
                            page = index
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                SlideCanvas(slide: slide, deck: deck, index: index, image: images[index])
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == page ? deck.palette.accent : Color.secondary.opacity(0.2), lineWidth: index == page ? 3 : 1))
                                Text("\(index + 1) · \(slide.kindTitle)").font(.caption).foregroundStyle(.secondary)
                                Text(slide.title).font(.subheadline.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Slayt \(index + 1), \(slide.title)")
                    }
                }
                .padding(18)
            }
            .navigationTitle("Tüm slaytlar")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
        }
    }
}

struct DeckPresentationView: View {
    let deck: Deck
    let images: [Int: UIImage]
    let figures: [SourceFigure]
    @Binding var page: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                HStack {
                    Button("Kapat", systemImage: "xmark") { dismiss() }
                    Spacer()
                    Text("\(page + 1) / \(deck.slides.count)").monospacedDigit()
                }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 20)
                TabView(selection: $page) {
                    ForEach(Array(deck.slides.enumerated()), id: \.offset) { index, slide in
                        SlideCanvas(slide: slide, deck: deck, index: index, image: images[index], figure: figures.first { $0.id == slide.figureId })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, geo.size.width > geo.size.height ? 12 : 0)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                VStack(spacing: 10) {
                    if geo.size.height > geo.size.width {
                        Label("Yatay çevirerek büyüt", systemImage: "iphone.gen3.landscape")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    HStack {
                        Button("Önceki", systemImage: "chevron.left") { page = max(0, page - 1) }
                            .disabled(page == 0).keyboardShortcut(.leftArrow, modifiers: [])
                        Spacer(minLength: 16)
                        Button("Sonraki", systemImage: "chevron.right") { page = min(deck.slides.count - 1, page + 1) }
                            .disabled(page + 1 >= deck.slides.count).keyboardShortcut(.rightArrow, modifiers: [])
                    }
                    .lineLimit(1).minimumScaleFactor(0.8).frame(minHeight: 44)
                }
                .font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.bottom, 8)
            }
            .padding(.top, 8)
        }
        .background(Color(red: 0.055, green: 0.065, blue: 0.09).ignoresSafeArea())
        .foregroundStyle(.white).tint(.white)
        .statusBarHidden(true)
    }
}

struct DeckSlideEditor: View {
    @State var slide: DeckSlide
    var save: (DeckSlide) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var bullets = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Başlık") { TextField("Slayt başlığı", text: $slide.title, axis: .vertical).lineLimit(2...4) }
                if slide.bullets != nil {
                    Section {
                        TextEditor(text: $bullets).frame(minHeight: 180)
                    } header: { Text("Maddeler") } footer: { Text("Her maddeyi ayrı satıra yaz. En fazla 5 madde, madde başına 200 karakter.") }
                }
                Section("Konuşmacı notları") { TextEditor(text: $slide.notes).frame(minHeight: 160) }
            }
            .navigationTitle("Slaytı düzenle").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        slide.title = slide.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if slide.bullets != nil { slide.bullets = editedBullets }
                        save(slide)
                        dismiss()
                    }.disabled(!valid)
                }
            }
            .onAppear { bullets = (slide.bullets ?? []).joined(separator: "\n") }
        }
    }
    private var editedBullets: [String] { bullets.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var valid: Bool {
        !slide.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && slide.title.count <= 150 && slide.notes.count <= 1500
        && (slide.bullets == nil || (!editedBullets.isEmpty && editedBullets.count <= (slide.kind == "agenda" ? 12 : 5) && editedBullets.allSatisfy { $0.count <= 200 }))
    }
}

/// Aynı semantik bağlantıları döngü, hiyerarşi ve süreçlerde açık oklarla çizer.
nonisolated struct DeckDiagramGeometry {
    var boxes: [CGRect]
    var edges: [(Int, Int)]
    static func make(layout: String, count: Int, size: CGSize) -> Self {
        let n = min(max(count, 0), 8)
        guard n > 0, size.width > 0, size.height > 0 else { return Self(boxes: [], edges: []) }
        let w = size.width, h = size.height
        if layout == "cycle" {
            let bw = min(210.0, w * 0.22), bh = min(n > 4 ? 98.0 : 150.0, h * 0.3)
            let rx = max(0, (w - bw) / 2 - 10), ry = max(0, (h - bh) / 2 - 8)
            let boxes = (0..<n).map { i in
                let angle = Double(i) * 2 * .pi / Double(n) - .pi / 2
                return CGRect(x: w / 2 + rx * cos(angle) - bw / 2, y: h / 2 + ry * sin(angle) - bh / 2, width: bw, height: bh)
            }
            return Self(boxes: boxes, edges: n > 1 ? (0..<n).map { ($0, ($0 + 1) % n) } : [])
        }
        if layout == "hierarchy" {
            let rootW = min(380.0, w * 0.5), rootH = min(110.0, h * 0.25)
            var boxes = [CGRect(x: (w - rootW) / 2, y: 0, width: rootW, height: rootH)]
            let children = n - 1
            let columns = min(max(children, 1), 4), rows = max(1, (children + columns - 1) / columns)
            let gap = 20.0, top = rootH + 42
            let bw = (w - Double(columns - 1) * gap) / Double(columns)
            let bh = max(1, (h - top - Double(rows - 1) * 20) / Double(rows))
            for i in 0..<children { boxes.append(CGRect(x: Double(i % columns) * (bw + gap), y: top + Double(i / columns) * (bh + 20), width: bw, height: bh)) }
            return Self(boxes: boxes, edges: children > 0 ? (1..<n).map { (0, $0) } : [])
        }
        let columns = layout == "compare" ? (n > 4 ? 4 : min(2, n)) : min(n, n > 4 ? (n + 1) / 2 : 4)
        let rows = (n + columns - 1) / columns
        let gap = layout == "compare" ? 26.0 : 38.0
        let bw = (w - Double(columns - 1) * gap) / Double(columns)
        let bh = min(260.0, (h - Double(rows - 1) * 24) / Double(rows))
        let top = max(0, (h - (Double(rows) * bh + Double(rows - 1) * 24)) / 2)
        let boxes = (0..<n).map { i in CGRect(x: Double(i % columns) * (bw + gap), y: top + Double(i / columns) * (bh + 24), width: bw, height: bh) }
        return Self(boxes: boxes, edges: layout == "compare" || n < 2 ? [] : (0..<(n - 1)).map { ($0, $0 + 1) })
    }
}

#if DEBUG
import SwiftData

enum StudioPreview {
    static var deck: Deck {
        let intro = "Bu deste, sunum stüdyosunun yerleşimini sınayan yerel bir tasarım örneğidir. Canlı yapay zekâ üretimi değildir."
        func slide(_ kind: String, _ title: String) -> DeckSlide {
            DeckSlide(kind: kind, title: title, chapterIndex: 0, sourcePages: [1, 2], notes: intro)
        }
        var cover = slide("title", "Fotosentez: Işıktan Yaşama"); cover.chapterIndex = nil
        var agenda = slide("agenda", "Bu derste neler göreceğiz?"); agenda.bullets = ["Enerjinin dönüşümü", "Kloroplastın yapısı", "Evrelerin karşılaştırılması", "Döngü ve bağlantılar"]
        var bullets = slide("bullets", "Işık enerjisi kimyasal enerjiye dönüşür")
        bullets.bullets = ["Klorofil, ışığın soğurulmasında görev alır.", "Işığa bağlı tepkimeler tilakoit zarında gerçekleşir.", "Karbonun organik bileşiklere katılması stromada gerçekleşir."]
        var process = slide("diagram", "Enerjinin izlediği yol")
        process.diagram = DeckDiagram(layout: "steps", nodes: [.init(title: "Işık", detail: "Klorofil tarafından soğurulur"), .init(title: "Elektronlar", detail: "Taşıma zincirine aktarılır"), .init(title: "ATP ve NADPH", detail: "Karbon bağlanmasında kullanılır")])
        var cycle = slide("diagram", "Calvin döngüsünde karbonun dönüşümü")
        cycle.diagram = DeckDiagram(layout: "cycle", nodes: [.init(title: "Karbon bağlama", detail: "Karbondioksit organik yapıya katılır"), .init(title: "İndirgenme", detail: "ATP ve NADPH kullanılır"), .init(title: "Yenilenme", detail: "RuBP yeniden oluşturulur")])
        var compare = slide("diagram", "İki evre, birbirini tamamlayan görevler")
        compare.diagram = DeckDiagram(layout: "compare", nodes: [.init(title: "Işığa bağlı evre", detail: "Tilakoit zarı; ATP ve NADPH üretimi"), .init(title: "Calvin döngüsü", detail: "Stroma; karbonun organik yapıya katılması")])
        var table = slide("table", "Evreleri karşılaştıralım")
        table.table = DeckTable(headers: ["Özellik", "Işığa bağlı tepkimeler", "Calvin döngüsü"], rows: [
            ["Yer", "Tilakoit zarı", "Stroma"], ["ATP", "Üretilir", "Kullanılır"], ["NADPH", "Üretilir", "Kullanılır"], ["Karbondioksit", "Doğrudan bağlanmaz", "Organik bileşiklere katılır"], ["Oksijen", "Suyun parçalanmasıyla açığa çıkar", "Doğrudan üretilmez"], ["Bağlantı", "Kimyasal enerji sağlar", "Bu enerjiyi kullanır"]])
        var image = slide("image", "Kloroplastı yakından incele")
        image.imagePrompt = "İç içe tilakoit diskleri ve onları çevreleyen stromanın görüldüğü bir kloroplast kesiti, yapılar anatomik oranlarını koruyor, açık arka plan, tek odak nesnesi"
        var summary = slide("summary", "Üç temel bağlantıyı hatırla")
        summary.bullets = ["Işığın soğurulması enerji dönüşümünü başlatır.", "Tilakoit zarı ve stroma farklı işlevleri barındırır.", "Evreler madde ve enerji akışıyla birbirine bağlıdır."]
        return DeckReadability.prepare(Deck(title: cover.title, subtitle: "BİYOLOJİ · GÖRSEL DERS NOTLARI", slides: [cover, agenda, bullets, process, cycle, compare, table, image, summary], theme: "ocean", imageStyle: "cutaway", imageLevel: 1))
    }
    static func seed(context: ModelContext) -> Episode? {
        let title = "Sunum Stüdyosu · Tasarım Örneği"
        if let found = try? context.fetch(FetchDescriptor<Episode>()).first(where: { $0.title == title }) { return found }
        let script = PodcastScript(title: title, summary: "Yerel sunum tasarımı doğrulaması", keyPoints: [], chapters: [], sourceNotes: "Tasarım doğrulaması; canlı üretim değil.")
        let episode = Episode(script: script, settings: PodcastSettings(speechProvider: "apple"), sourceNames: ["Yerel tasarım örneği"], jobToken: "")
        episode.jobToken = nil
        episode.status = .ready
        episode.deck = deck
        context.insert(episode)
        try? context.save()
        return episode
    }
}
#endif
