import PDFKit
import SwiftUI
import UIKit

// Kitap okuyucu: indirilen MEB kitabını uygulama içinde okuma (kaldığı sayfa, içindekiler, sayfaya gitme)
// ve seçilen sayfa aralığını konu videosuna kaynak olarak aktarma.

/// PDF'ten sayfa aralığıyla metin alma (konu videosunun kaynağı).
nonisolated enum PDFPageText {
    /// Bir kerede en çok bu kadar sayfa alınır.
    static let maxPages = 40
    /// Kullanıcının yazdığı aralığı belgeye sığdırır: 1…`count`, ters girilmişse çevrilir, en çok `maxPages` sayfa.
    static func range(from: Int, to: Int, count: Int) -> ClosedRange<Int>? {
        guard count > 0 else { return nil }
        let low = min(max(1, min(from, to)), count), high = min(max(1, max(from, to)), count)
        return low...min(high, low + maxPages - 1)
    }
    /// Sayfaların yazı katmanı (PDF sayfa numarası, 1'den). Yazı yoksa (taranmış sayfalar) boş döner.
    /// `marked`: her sayfanın başına "[Sayfa N]" imi konur (kaynağa sadakat kapısı, madde 25: sunucu alıntının sayfasını bu imden bulur).
    static func read(url: URL, pages: ClosedRange<Int>, limit: Int = TopicSource.maximum, marked: Bool = false) -> String {
        guard let document = PDFDocument(url: url), let range = Self.range(from: pages.lowerBound, to: pages.upperBound, count: document.pageCount) else { return "" }
        var text = ""
        for page in range {
            if Task.isCancelled || text.utf16.count >= limit { break }
            autoreleasepool { text += (marked ? "[Sayfa \(page)]\n" : "") + (document.page(at: page - 1)?.string ?? "") + "\n\n" }
        }
        return text.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Sayfanın küçük görüntüsü (aralık seçerken doğru sayfayı görmek için).
    static func thumbnail(url: URL, page: Int, side: CGFloat = 360) -> UIImage? {
        guard let document = PDFDocument(url: url), let target = document.page(at: page - 1) else { return nil }
        return target.thumbnail(of: CGSize(width: side, height: side * 1.4), for: .mediaBox)
    }
}

extension MEBBookIndex {
    /// "1.4. CANLILARIN ORTAK ÖZELLİKLERİ" → "Canlıların Ortak Özellikleri".
    static func plainTitle(_ title: String) -> String {
        let locale = Locale(identifier: "tr_TR")
        var text = title.replacingOccurrences(of: #"^\d+(\.\d+)*\.?\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let letters = text.filter(\.isLetter)
        if !letters.isEmpty, letters == letters.uppercased(with: locale) {
            text = text.lowercased(with: locale).capitalized(with: locale)
            for word in [" Ve ", " İle ", " Veya "] { text = text.replacingOccurrences(of: word, with: word.lowercased(with: locale)) }
        }
        return text
    }
    /// PDF sayfasının (1'den) içinde olduğu konunun adı: o sayfadan önce başlayan son bölüm ya da numaralı konu başlığı.
    func heading(atPDFPage page: Int) -> String? {
        let printed = page - offset
        let entry = entries.last { $0.page <= printed && $0.level <= 1 } ?? entries.last { $0.page <= printed }
        return entry.map { Self.plainTitle($0.title) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Sayfaya gitme isteği, görünümün boyutu belli olana dek bekletilir (boyutsuz görünümde yapılan atlama ilk yerleşimde kaybolur).
final class MEBPDFPages: PDFView {
    var pending: PDFPage?
    func show(_ target: PDFPage) {
        if bounds.width > 0, bounds.height > 0 { pending = nil; top(of: target) } else { pending = target }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let target = pending else { return }
        pending = nil
        // Ölçek bu yerleşimde kurulur; atlama bir sonraki turda yapılır.
        DispatchQueue.main.async { [weak self] in self?.top(of: target) }
    }
    /// Sayfanın üst kenarına gider (başlık gezinme çubuğunun altında kalmasın).
    private func top(of target: PDFPage) {
        let box = target.bounds(for: displayBox), corner = CGPoint(x: box.minX, y: box.maxY)
        go(to: PDFDestination(page: target, at: corner))
        // PDFKit sayfanın başını çubukların altında bırakabiliyor: sayfanın üst kenarı ölçülür ve görünür alanın başına çekilir.
        guard let scroll = subviews.compactMap({ $0 as? UIScrollView }).first else { return }
        layoutIfNeeded()
        let shift = convert(corner, from: target).y - (safeAreaInsets.top + 6)
        let lowest = -scroll.adjustedContentInset.top, highest = max(lowest, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        scroll.contentOffset.y = min(max(scroll.contentOffset.y + shift, lowest), highest)
    }
}

nonisolated struct MEBTextSelection: Equatable, Sendable {
    let page: Int
    let text: String
}

/// PDFKit görünümü: sayfa ve seçim metnini değer olarak bildirir.
struct MEBPDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var page: Int
    @Binding var count: Int
    @Binding var selection: MEBTextSelection?
    var jump: MEBReader.Jump?

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> MEBPDFPages {
        let view = MEBPDFPages()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = document
        // Kaydırma alanı çubuklara göre kendiliğinden kaymasın (sayfaya gidince sayfanın başı çubuğun altında kalıyordu);
        // SwiftUI safeAreaInset alt araç çubuğuna yer ayırır.
        if let scroll = view.subviews.compactMap({ $0 as? UIScrollView }).first {
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.contentInset.bottom = 12; scroll.verticalScrollIndicatorInsets.bottom = 12
        }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.selectionChanged(_:)), name: .PDFViewSelectionChanged, object: view)
        let total = view.document?.pageCount ?? 0
        if let jump, let target = view.document?.page(at: jump.page - 1) { context.coordinator.applied = jump.id; view.show(target) }
        DispatchQueue.main.async { count = total }
        return view
    }
    func updateUIView(_ view: MEBPDFPages, context: Context) {
        context.coordinator.parent = self
        guard let jump, jump.id != context.coordinator.applied, let target = view.document?.page(at: jump.page - 1) else { return }
        context.coordinator.applied = jump.id
        view.show(target)
    }
    static func dismantleUIView(_ view: MEBPDFPages, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        view.document = nil
    }

    final class Coordinator: NSObject {
        var parent: MEBPDFView
        var applied: UUID?
        init(_ parent: MEBPDFView) { self.parent = parent }
        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let current = view.currentPage, let document = view.document else { return }
            let number = document.index(for: current) + 1
            if parent.page != number { parent.page = number }
        }
        @objc func selectionChanged(_ note: Notification) {
            guard let view = note.object as? PDFView, let document = view.document,
                  let selected = view.currentSelection, let first = selected.pages.first,
                  let text = selected.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                parent.selection = nil
                return
            }
            let number = document.index(for: first)
            guard number != NSNotFound, number >= 0, number < document.pageCount else { parent.selection = nil; return }
            parent.selection = MEBTextSelection(page: number + 1, text: text)
        }
    }
}

struct MEBReader: View {
    struct Jump: Equatable { var page: Int; var id = UUID() }
    struct Draft: Identifiable { let id = UUID(); var topic: String; var source: String; var learningSource: LearningSourceLink? = nil }
    struct NoteDraft: Identifiable { let id = UUID(); let page: Int; let quote: String }
    enum Panel: Identifiable {
        case contents, appearance, range, search, tools, notebook, note(NoteDraft), create(Draft)
        var id: String {
            switch self {
            case .contents: "contents"
            case .appearance: "appearance"
            case .range: "range"
            case .search: "search"
            case .tools: "tools"
            case .notebook: "notebook"
            case .note(let draft): draft.id.uuidString
            case .create(let draft): draft.id.uuidString
            }
        }
    }
    let title: String
    let url: URL
    /// Kaldığı sayfanın saklanacağı ad (belge kimliği); verilmezse sayfa hatırlanmaz.
    var key: String?
    /// Açılışta gidilecek sayfa (verilmezse kaldığı sayfa).
    var start: Int?
    @Environment(\.dismiss) private var dismiss
    @State private var page = 1
    @State private var count = 0
    @State private var jump: Jump?
    @State private var panel: Panel?
    @State private var asking = false
    @State private var typed = ""
    @State private var index: MEBBookIndex?
    @State private var document: PDFDocument?
    @State private var loadError: String?
    @State private var reloadID = UUID()
    @State private var textMode = false
    @State private var pageText = ""
    @State private var textLoading = false
    @State private var selection: MEBTextSelection?
    @State private var studyError: String?
    @State private var studyStatus: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var readerFontSize = 19.0
    @AppStorage("meb.reader.textScale") private var textScale = 1.0
    @AppStorage("meb.reader.lineSpacing") private var lineSpacing = 7.0
    @AppStorage("meb.reader.serif") private var serif = false

    private var bookID: String? {
        key.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    // PDFKit belge nesnesi işçi görevinde oluşturulur ve yalnız bir kez ana aktöre devredilir.
    nonisolated private struct LoadedDocument: @unchecked Sendable { let document: PDFDocument? }

    nonisolated static func openingPage(start: Int?, saved: Int?, count: Int) -> Int {
        min(max(1, start ?? saved ?? 1), max(1, count))
    }

    /// Belgenin en son okunan sayfası (1'den); hiç açılmadıysa `nil`.
    static func savedPage(_ key: String) -> Int? {
        let value = UserDefaults.standard.integer(forKey: "meb.page." + key)
        return value > 1 ? value : nil
    }

    var body: some View {
        // Paneller bu değerleri gövdeden alır: yalnız panelin içinde okunan durum değişince gövde yenilenmez ve panel eski değeri görür.
        let loaded = index, total = count
        return NavigationStack {
            VStack(spacing: 0) {
            Group {
                if let loadError {
                    ContentUnavailableView {
                        Label("Kitap açılamadı", systemImage: "doc.badge.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Yeniden dene") { reloadID = UUID() }.buttonStyle(.borderedProminent)
                    }
                } else if let document {
                    if textMode {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Sayfa \(page)").font(.headline).accessibilityAddTraits(.isHeader)
                                if textLoading { ProgressView("Sayfa metni okunuyor…") }
                                else if pageText.isEmpty {
                                    Text("Bu sayfada seçilebilir metin yok. Görselleri incelemek için PDF görünümüne geçebilirsin.")
                                } else {
                                    Text(pageText).font(.system(size: readerFontSize * textScale, design: serif ? .serif : .default))
                                        .lineSpacing(lineSpacing).textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                        }.background(Theme.canvas)
                    } else {
                        MEBPDFView(document: document, page: $page, count: $count, selection: $selection, jump: jump)
                    }
                } else {
                    ProgressView("Kitap açılıyor…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if document != nil { readerControls }
            }.background(Theme.canvas)
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Kitabı paylaş") }
                }
                .alert("Sayfaya git", isPresented: $asking) {
                    TextField("1–\(max(1, count))", text: $typed).keyboardType(.numberPad)
                    Button("Git") { if let wanted = Int(typed.trimmingCharacters(in: .whitespaces)), count > 0 { jump = Jump(page: min(max(1, wanted), count)) } }
                    Button("Vazgeç", role: .cancel) {}
                } message: { Text("PDF sayfa numarasını yaz.") }
        }
        .sheet(item: $panel) { item in
            switch item {
            case .contents: contents(loaded, total: total)
            case .appearance: appearance
            case .tools: readerTools
            case .search:
                BookSearchView(url: url, title: title) { target in
                    jump = Jump(page: min(max(1, target), max(1, total))); panel = nil
                }
            case .notebook:
                if let bookID {
                    BookNotebookView(bookID: bookID) { note in
                        jump = Jump(page: min(max(1, note.page), max(1, total))); panel = nil
                    }
                }
            case .note(let draft):
                if let bookID { BookNoteEditor(bookID: bookID, title: title, page: draft.page, quote: draft.quote) }
            case .range:
                PDFRangeSheet(url: url, title: title, from: page, to: min(max(1, total), page + 7)) { text, pages in
                    let topic = loaded?.heading(atPDFPage: pages.lowerBound) ?? ""
                    let link = bookID.map { LearningSourceLink(bookID: $0, title: title, pages: pages, text: text, topic: topic) }
                    panel = .create(Draft(topic: topic, source: text, learningSource: link))
                }
            case .create(let draft):
                TopicVideoCreateView(courseID: nil, topic: draft.topic, source: draft.source, learningSource: draft.learningSource)
            }
        }
        .onChange(of: page) { _, value in
            if let key, value > 0 { UserDefaults.standard.set(value, forKey: "meb.page." + key) }
            selection = nil; studyStatus = nil
        }
        .task(id: reloadID) {
            document = nil; loadError = nil; index = nil
            let file = url
            let result = await Task.detached(priority: .userInitiated) { LoadedDocument(document: PDFDocument(url: file)) }.value
            guard !Task.isCancelled else { return }
            guard let loaded = result.document, loaded.pageCount > 0, !loaded.isLocked else {
                loadError = "Dosya eksik, bozuk veya kilitli olabilir. Kitap seçeneklerinden indirilen kopyayı silip tekrar indirebilirsin."
                return
            }
            count = loaded.pageCount
            page = Self.openingPage(start: start, saved: key.flatMap(Self.savedPage), count: count)
            jump = Jump(page: page)
            document = loaded
            if let key { MEBLibrary.shared.recordOpened(key: key) }
            index = await Task.detached(priority: .utility) { PDFDocument(url: file).map { MEBBookIndex.read($0) } }.value
            guard !Task.isCancelled else { return }
            #if DEBUG
            if let wanted = DebugArg.value("mebReaderPanel") {
                switch wanted {
                case "range": panel = .range
                case "search": panel = .search
                case "notebook": if bookID != nil { panel = .notebook }
                case "note": if bookID != nil { panel = .note(NoteDraft(page: page, quote: "")) }
                default: panel = .contents
                }
            }
            #endif
        }
        .task(id: "\(textMode)-\(page)") {
            guard textMode else { return }
            textLoading = true; pageText = ""
            let file = url, current = page
            let text = await Task.detached(priority: .userInitiated) { PDFPageText.read(url: file, pages: current...current) }.value
            guard !Task.isCancelled else { return }
            pageText = text; textLoading = false
        }
        .onChange(of: jump) { _, value in
            if textMode, let value { page = min(max(1, value.page), max(1, count)) }
        }
        .onChange(of: textMode) { _, _ in selection = nil; jump = Jump(page: page) }
        .alert("Kitap kaydı tamamlanamadı", isPresented: Binding(get: { studyError != nil }, set: { if !$0 { studyError = nil } })) {
            Button("Tamam", role: .cancel) { studyError = nil }
        } message: { Text(studyError ?? "") }
        .task(id: studyStatus) {
            guard studyStatus != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            studyStatus = nil
        }
    }

    private var readerControls: some View {
        VStack(spacing: 8) {
            if let studyStatus { Text(studyStatus).font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }
                    .disabled(page <= 1).accessibilityLabel("Önceki sayfa")
                Button { typed = ""; asking = true } label: {
                    Text("\(page) / \(count)").font(.subheadline.monospacedDigit()).frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityLabel("Sayfaya git").accessibilityValue("\(count) sayfadan \(page). sayfa")
                Button { navigate(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                    .disabled(page >= count).accessibilityLabel("Sonraki sayfa")
            }
            if typeSize.isAccessibilitySize {
                Button { panel = .tools } label: {
                    Label("Okuma araçları", systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityHint("Arama, içindekiler, görünüm ve kitap çalışma seçeneklerini açar")
            } else {
                HStack(spacing: 12) {
                    Button("Ara", systemImage: "magnifyingglass") { panel = .search }.frame(minHeight: 44).accessibilityLabel("Kitap içinde ara")
                    Button("İçindekiler", systemImage: "list.bullet") { panel = .contents }.frame(minHeight: 44)
                    Menu {
                        studyActions
                    } label: { Label("Araçlar", systemImage: "ellipsis.circle").frame(minHeight: 44) }
                }.font(.subheadline.weight(.semibold)).labelStyle(.titleOnly)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6).background(.bar)
    }

    private var readerTools: some View {
        NavigationStack {
            List {
                Button("Kitap içinde ara", systemImage: "magnifyingglass") { panel = .search }.frame(minHeight: 44)
                Button("İçindekiler", systemImage: "list.bullet") { panel = .contents }.frame(minHeight: 44)
                studyActions
            }
            .environment(\.defaultMinListRowHeight, 52)
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle("Okuma araçları").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { panel = nil } } }
        }
    }

    @ViewBuilder private var studyActions: some View {
        Button("Görünüm", systemImage: "textformat.size") { panel = .appearance }
        if let bookID {
            Divider()
            let marked = BookStudyStore.shared.isBookmarked(bookID: bookID, page: page)
            Button(marked ? "Yer imini kaldır" : "Bu sayfaya yer imi ekle", systemImage: marked ? "bookmark.fill" : "bookmark") {
                do {
                    try BookStudyStore.shared.toggleBookmark(bookID: bookID, title: title, page: page)
                    let message = marked ? "Yer imi kaldırıldı" : "Yer imi eklendi"
                    studyStatus = message
                    UIAccessibility.post(notification: .announcement, argument: message)
                } catch { studyError = error.localizedDescription }
            }
            Button(selection == nil ? "Bu sayfaya not ekle" : "Seçili alıntıya not ekle", systemImage: "square.and.pencil") {
                panel = .note(NoteDraft(page: selection?.page ?? page, quote: selection?.text ?? ""))
            }
            Button("Kitap defteri", systemImage: "text.book.closed") { panel = .notebook }
        }
        Divider()
        Button("Bu sayfalardan konu videosu hazırla", systemImage: "play.rectangle.on.rectangle") { panel = .range }
    }

    private func navigate(_ delta: Int) {
        jump = Jump(page: min(max(1, page + delta), count))
    }

    private var appearance: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Okuma görünümü", selection: $textMode) {
                        Text("Özgün PDF").tag(false)
                        Text("Büyüyen metin").tag(true)
                    }.pickerStyle(.inline)
                } footer: {
                    Text("Özgün PDF şekilleri ve sayfa düzenini korur. Metin görünümü seçilebilir yazıyı kullanır; bazı PDF’lerde metnin sırası farklı olabilir.")
                }
                if textMode {
                    Section("Metin görünümü") {
                        Stepper("Yazı boyutu · %\(Int(textScale * 100))", value: $textScale, in: 1...1.8, step: 0.2)
                        Stepper("Satır aralığı · \(Int(lineSpacing))", value: $lineSpacing, in: 3...15, step: 2)
                        Toggle("Kitap yazı tipi", isOn: $serif)
                        Text("Yazı, iPhone’un metin boyutu ayarını da izler.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("Okuma görünümü").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { panel = nil } } }
        }
    }

    private func contents(_ index: MEBBookIndex?, total count: Int) -> some View {
        NavigationStack {
            List {
                if let index, !index.entries.isEmpty {
                    ForEach(Array(index.entries.enumerated()), id: \.offset) { _, entry in
                        Button { jump = Jump(page: min(max(1, entry.page + index.offset), max(1, count))); panel = nil } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.title)
                                    .font(entry.level == 0 ? .subheadline.weight(.bold) : (entry.level == 1 ? .subheadline.weight(.semibold) : .footnote))
                                    .foregroundStyle(Color.primary).padding(.leading, CGFloat(entry.level) * 10)
                                Spacer(minLength: 8)
                                Text("\(entry.page)").font(.footnote.monospacedDigit()).foregroundStyle(Color.secondary)
                            }
                        }
                    }
                } else if index == nil {
                    ProgressView("İçindekiler okunuyor…")
                } else {
                    ContentUnavailableView("İçindekiler okunamadı", systemImage: "list.bullet", description: Text("Bu kitabın içindekiler sayfası yazı olarak okunamıyor. Alttaki sayfa düğmesinden sayfa numarasıyla gidebilirsin."))
                }
            }
            .navigationTitle("İçindekiler").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { panel = nil } } }
        }
    }
}

/// PDF'ten sayfa aralığı seçip metnini alma: ilk ve son sayfa yazılır, iki sayfanın küçük görüntüsü gösterilir.
struct PDFRangeSheet: View {
    let url: URL
    let title: String
    let onDone: (String, ClosedRange<Int>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var from: Int
    @State private var to: Int
    @State private var count = 0
    @State private var working = false
    @State private var note: String?
    @State private var first: UIImage?
    @State private var last: UIImage?

    init(url: URL, title: String, from: Int = 1, to: Int? = nil, onDone: @escaping (String, ClosedRange<Int>) -> Void) {
        self.url = url; self.title = title; self.onDone = onDone
        _from = State(initialValue: max(1, from)); _to = State(initialValue: max(max(1, from), to ?? from + 7))
    }
    private var chosen: ClosedRange<Int>? { PDFPageText.range(from: from, to: to, count: count) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("İlk sayfa", $from)
                    field("Son sayfa", $to)
                } header: { Text(title) } footer: {
                    Text(note ?? summary)
                }
                Section("Önizleme") {
                    HStack(alignment: .top, spacing: 12) { preview(first, chosen?.lowerBound); preview(last, chosen?.upperBound) }
                        .frame(maxWidth: .infinity)
                }
                Section {
                    Button {
                        guard let pages = chosen else { return }
                        working = true; note = nil
                        let file = url
                        Task {
                            let text = await Task.detached(priority: .userInitiated) { PDFPageText.read(url: file, pages: pages, marked: true) }.value
                            working = false
                            if text.count < TopicSource.minimum { note = "Bu sayfalarda seçilebilir yazı yok ya da çok az. Başka sayfa seç ya da sayfaların fotoğrafını ekle." }
                            else { onDone(text, pages) }
                        }
                    } label: { if working { ProgressView() } else { Label("Bu sayfaları kaynak al", systemImage: "text.page") } }
                        .buttonStyle(PrimaryButtonStyle(enabled: chosen != nil && !working)).disabled(chosen == nil || working)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
            }
            .navigationTitle("Sayfa aralığı").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } } }
            .task {
                let file = url
                count = await Task.detached { PDFDocument(url: file)?.pageCount ?? 0 }.value
                if count == 0 { note = "Belge açılamadı." }
            }
            // Yazarken her tuşta görüntü üretilmesin: kısa bir bekleme.
            .task(id: "\(chosen?.lowerBound ?? 0)-\(chosen?.upperBound ?? 0)") {
                guard let pages = chosen else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let file = url
                let images = await Task.detached(priority: .utility) { (PDFPageText.thumbnail(url: file, page: pages.lowerBound), PDFPageText.thumbnail(url: file, page: pages.upperBound)) }.value
                guard !Task.isCancelled else { return }
                first = images.0; last = images.1
            }
        }
    }

    private var summary: String {
        guard let pages = chosen else { return count == 0 ? "Belge açılıyor…" : "Sayfa numaralarını yaz." }
        let asked = abs(to - from) + 1
        return "\(pages.lowerBound)–\(pages.upperBound). sayfalar · \(pages.count) sayfa" + (asked > pages.count && max(from, to) <= count ? " (bir kerede en çok \(PDFPageText.maxPages))" : "") + ". Belge \(count) sayfa. Kısa konu videosu yaklaşık \(TopicSource.quick / 1000) bin, ders saati videosu \(TopicSource.maximum / 1000) bin karakter kullanır; fazlası kesilir."
    }
    private func field(_ label: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...max(1, count)) {
            HStack {
                Text(label)
                Spacer(minLength: 4)
                TextField("", value: value, format: .number.grouping(.never)).keyboardType(.numberPad).multilineTextAlignment(.trailing).monospacedDigit().frame(width: 56)
            }
        }
    }
    private func preview(_ image: UIImage?, _ number: Int?) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit() } else { Rectangle().fill(.quaternary).aspectRatio(0.72, contentMode: .fit) }
            }
            .frame(maxHeight: 190).clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text(number.map { "s. \($0)" } ?? "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
