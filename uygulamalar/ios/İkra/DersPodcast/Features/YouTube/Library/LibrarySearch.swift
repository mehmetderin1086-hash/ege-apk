import SwiftData
import SwiftUI

// #38: Kütüphanede küresel arama — tüm derslerin transkripti + kare yazıları (OCR) yerelde aranır; sonuç ders + dakika.
// "Yapay zekâyla ara" (/v1/youtube/search) soruyu bölüm başlıkları ve ana noktalar üzerinden sunucuya sorar.

nonisolated enum LibrarySearch {
    struct Para: Sendable, Hashable {
        var start: Double
        var text: String
        /// Büyük/küçük harf ve aksan farkı yok sayılmış hâl (indeks kurulurken bir kez hesaplanır).
        var folded: String
    }

    struct Doc: Sendable, Identifiable {
        var id: UUID
        var title: String
        var channel: String
        var foldedTitle: String
        var paragraphs: [Para]
        var frames: [Para]
        var chapters: [VideoChapter]
        var keyPoints: [NoteKeyPoint]
    }

    enum Source: String, Sendable { case title, transcript, frame }

    struct Hit: Identifiable, Hashable, Sendable {
        var lessonID: UUID
        var time: Double
        var snippet: String
        var source: Source
        var id: String { "\(lessonID)-\(source.rawValue)-\(Int(time * 10))" }
    }

    struct LessonHits: Identifiable, Sendable {
        var lesson: UUID
        var title: String
        var hits: [Hit]
        /// Gösterilmeyenler dahil toplam eşleşme.
        var total: Int
        var id: UUID { lesson }
    }

    static let maxPerLesson = 6
    /// "Tümünü göster" ile açılan derste gösterilecek en çok eşleşme.
    static let maxExpanded = 60
    static let maxLessons = 40

    /// Büyük/küçük harf, aksan ve noktasız ı farkı yok sayılır (ı ≈ i: yabancı klavyede yazılan sorgu da bulur).
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }

    static func tokens(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
    }

    /// Tüm sözcük parçaları metinde geçiyor mu (büyük/küçük harf ve aksan farkı yok sayılır).
    static func matches(text: String, tokens: [String]) -> Bool {
        guard !tokens.isEmpty else { return false }
        let folded = fold(text)
        return tokens.allSatisfy { folded.contains($0) }
    }

    /// İlk eşleşmenin çevresinden kısa alıntı.
    static func snippet(text: String, folded: String, tokens: [String], radius: Int = 70) -> String {
        let characters = Array(text)
        guard let token = tokens.first(where: { folded.contains($0) }), let range = folded.range(of: token) else {
            return String(characters.prefix(radius * 2))
        }
        // Katlama harf sayısını değiştirmezse aynı konum; değiştiyse sınırlara kırpılır.
        let offset = min(characters.count, folded.distance(from: folded.startIndex, to: range.lowerBound))
        let lower = max(0, offset - radius)
        let upper = min(characters.count, offset + token.count + radius)
        var out = String(characters[lower..<upper]).replacingOccurrences(of: "\n", with: " ")
        if lower > 0 { out = "…" + out }
        if upper < characters.count { out += "…" }
        return out
    }

    /// Alıntıda vurgulanacak yerler (karakter sırası aralıkları; sıralı, örtüşenler birleştirilmiş).
    /// Katlama harf sayısını değiştirdiyse konumlar güvenilmez: boş döner.
    static func highlightOffsets(snippet: String, tokens: [String]) -> [Range<Int>] {
        let folded = Array(fold(snippet))
        guard !folded.isEmpty, folded.count == snippet.count else { return [] }
        var found: [Range<Int>] = []
        for token in Set(tokens) {
            let needle = Array(token)
            guard !needle.isEmpty, needle.count <= folded.count else { continue }
            var index = 0
            while index + needle.count <= folded.count {
                if folded[index..<(index + needle.count)].elementsEqual(needle) {
                    found.append(index..<(index + needle.count))
                    index += needle.count
                } else {
                    index += 1
                }
            }
        }
        var merged: [Range<Int>] = []
        for range in found.sorted(by: { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound < $1.upperBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Ders başına gruplanmış sonuçlar: önce çok eşleşmesi olan dersler; ders içinde zamana göre.
    /// `expanded` içindeki derslerde sınır `maxPerLesson` yerine `maxExpanded` olur.
    static func search(_ query: String, in docs: [Doc], expanded: Set<UUID> = []) -> [LessonHits] {
        let tokens = tokens(query)
        guard !tokens.isEmpty else { return [] }
        var results: [LessonHits] = []
        for doc in docs {
            var hits: [Hit] = []
            if tokens.allSatisfy({ doc.foldedTitle.contains($0) }) {
                hits.append(Hit(lessonID: doc.id, time: 0, snippet: doc.title, source: .title))
            }
            for p in doc.paragraphs where tokens.allSatisfy({ p.folded.contains($0) }) {
                hits.append(Hit(lessonID: doc.id, time: p.start, snippet: snippet(text: p.text, folded: p.folded, tokens: tokens), source: .transcript))
            }
            for f in doc.frames where tokens.allSatisfy({ f.folded.contains($0) }) {
                hits.append(Hit(lessonID: doc.id, time: f.start, snippet: snippet(text: f.text, folded: f.folded, tokens: tokens), source: .frame))
            }
            guard !hits.isEmpty else { continue }
            hits.sort { $0.time != $1.time ? $0.time < $1.time : $0.source.rawValue < $1.source.rawValue }
            let limit = expanded.contains(doc.id) ? maxExpanded : maxPerLesson
            results.append(LessonHits(lesson: doc.id, title: doc.title, hits: Array(hits.prefix(limit)), total: hits.count))
        }
        results.sort { $0.total != $1.total ? $0.total > $1.total : $0.title.localizedCompare($1.title) == .orderedAscending }
        return Array(results.prefix(maxLessons))
    }

    /// Yapay zekâ aramasına gidecek özet (sunucu sınırlarını aşmamak için kırpılmış).
    static func aiEntries(from docs: [Doc], maxLessons: Int = 40, maxChapters: Int = 40, maxKeyPoints: Int = 30) -> [LessonSearchEntry] {
        docs.filter { !$0.chapters.isEmpty || !$0.keyPoints.isEmpty }.prefix(maxLessons).map {
            LessonSearchEntry(id: $0.id.uuidString.lowercased(), title: $0.title,
                              chapters: Array($0.chapters.prefix(maxChapters)), keyPoints: Array($0.keyPoints.prefix(maxKeyPoints)))
        }
    }
}

/// Arama indeksi için ders anlık görüntüsü (SwiftData nesnesi iş parçacığı dışına taşınmaz).
nonisolated struct LessonSnapshot: Sendable {
    var id: UUID
    var title: String
    var channel: String
    var transcriptData: Data?
}

// Dizin ve arama ekranı yalnız Oku'dadır; Ders Video bu dosyadan yalnız katlama/eşleme kurallarını kullanır.
nonisolated enum LibraryIndex {
    /// Transkript ve kare yazılarını çözüp indeks kurar; ana iş parçacığı dışında.
    @concurrent
    static func build(_ snapshots: [LessonSnapshot]) async -> [LibrarySearch.Doc] {
        snapshots.map { snap in
            let transcript = snap.transcriptData.flatMap { try? JSONDecoder().decode(VideoTranscript.self, from: $0) }
            let paragraphs = (transcript?.paragraphs ?? []).map { LibrarySearch.Para(start: $0.start, text: $0.text, folded: LibrarySearch.fold($0.text)) }
            let frames = FrameTextStore.nonEmpty(FrameTextStore.load(lesson: snap.id)).map {
                LibrarySearch.Para(start: $0.time, text: $0.text, folded: LibrarySearch.fold($0.text))
            }
            return LibrarySearch.Doc(id: snap.id, title: snap.title, channel: snap.channel, foldedTitle: LibrarySearch.fold(snap.title),
                                     paragraphs: paragraphs, frames: frames,
                                     chapters: transcript?.chapters ?? [], keyPoints: transcript?.notes?.keyPoints ?? [])
        }
    }
}

struct LibrarySearchView: View {
    var lessons: [VideoLesson]
    /// Dersi verilen saniyede aç.
    var open: (UUID, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var docs: [LibrarySearch.Doc] = []
    @State private var indexing = true
    @State private var results: [LibrarySearch.LessonHits] = []
    /// "Tümünü göster" denmiş dersler (sorgu değişince sıfırlanır).
    @State private var expanded: Set<UUID> = []
    @State private var aiHits: [AISearchHit] = []
    @State private var aiLoading = false
    @State private var aiError: String?

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let tokens = LibrarySearch.tokens(trimmed)
        return NavigationStack {
            List {
                if indexing {
                    HStack(spacing: 8) { ProgressView(); Text("Dersler taranıyor…").foregroundStyle(.secondary) }
                }
                if trimmed.count >= 2 {
                    Section {
                        Button {
                            Task { await askAI() }
                        } label: {
                            HStack {
                                Label("Yapay zekâyla ara", systemImage: "sparkles")
                                if aiLoading { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(aiLoading || indexing)
                        if let aiError { Text(aiError).font(.footnote).foregroundStyle(.red) }
                    } footer: {
                        Text("Soruyu bölüm başlıkları ve ana noktalar üzerinden anlam olarak arar (günlük araç hakkından düşer).")
                    }
                }
                if !aiHits.isEmpty {
                    Section("Yapay zekâ önerileri") {
                        ForEach(aiHits, id: \.self) { hit in
                            if let lesson = lessons.first(where: { $0.id.uuidString.lowercased() == hit.lessonId.lowercased() }) {
                                Button {
                                    open(lesson.id, hit.time)
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(lesson.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                                            Spacer(minLength: 6)
                                            Text(VideoTime.string(hit.time)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        }
                                        Text(hit.reason).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                                    }
                                }
                            }
                        }
                    }
                }
                ForEach(results) { group in
                    Section {
                        ForEach(group.hits) { hit in
                            Button {
                                open(group.lesson, hit.time)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: icon(hit.source)).foregroundStyle(.secondary).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if hit.source != .title {
                                            Text(VideoTime.string(hit.time)).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Color.accentColor)
                                        }
                                        Text(highlighted(hit.snippet, tokens: tokens)).font(.callout).foregroundStyle(.primary).lineLimit(4)
                                    }
                                }
                            }
                        }
                        if group.total > group.hits.count, !expanded.contains(group.lesson) {
                            Button("Tümünü göster (+\(group.total - group.hits.count))", systemImage: "chevron.down") {
                                expanded.insert(group.lesson)
                                results = LibrarySearch.search(trimmed, in: docs, expanded: expanded)
                            }
                            .font(.callout.weight(.semibold))
                        }
                    } header: {
                        Text(group.title).lineLimit(2).textCase(nil)
                    } footer: {
                        if group.total > group.hits.count, expanded.contains(group.lesson) {
                            Text("İlk \(group.hits.count) eşleşme gösteriliyor; +\(group.total - group.hits.count) eşleşme daha var.")
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tüm derslerde ara")
            .overlay {
                if !indexing && trimmed.count >= 2 && results.isEmpty && aiHits.isEmpty && !aiLoading {
                    ContentUnavailableView.search(text: trimmed)
                } else if trimmed.isEmpty && !indexing {
                    ContentUnavailableView("Derslerde ara", systemImage: "magnifyingglass",
                                           description: Text("Transkriptlerde ve karelerdeki yazılarda geçen kelimeyi yaz; sonuçta ders ve dakika görürsün."))
                }
            }
            .navigationTitle("Kütüphanede ara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task {
                #if DEBUG
                if let demo = LibraryDemo.query { query = demo }
                #endif
                let snapshots = lessons.map { LessonSnapshot(id: $0.id, title: $0.title, channel: $0.channel, transcriptData: $0.transcriptData) }
                docs = await LibraryIndex.build(snapshots)
                indexing = false
            }
            .task(id: trimmed) {
                aiHits = []
                aiError = nil
                expanded = []
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                results = LibrarySearch.search(trimmed, in: docs)
            }
            .onChange(of: docs.count) { _, _ in results = LibrarySearch.search(trimmed, in: docs, expanded: expanded) }
        }
        .debugNarrowScreen()
    }

    /// Alıntıda eşleşen sözcükler kalın + altı çizili + vurgu rengi (yalnız renge dayanmaz).
    private func highlighted(_ snippet: String, tokens: [String]) -> AttributedString {
        let offsets = LibrarySearch.highlightOffsets(snippet: snippet, tokens: tokens)
        guard !offsets.isEmpty else { return AttributedString(snippet) }
        let characters = Array(snippet)
        var out = AttributedString()
        var cursor = 0
        for range in offsets {
            if cursor < range.lowerBound { out.append(AttributedString(String(characters[cursor..<range.lowerBound]))) }
            var piece = AttributedString(String(characters[range]))
            piece.font = .callout.bold()
            piece.foregroundColor = Color.accentColor
            piece.underlineStyle = Text.LineStyle.single
            out.append(piece)
            cursor = range.upperBound
        }
        if cursor < characters.count { out.append(AttributedString(String(characters[cursor...]))) }
        return out
    }

    private func icon(_ source: LibrarySearch.Source) -> String {
        switch source {
        case .title: "text.alignleft"
        case .transcript: "text.quote"
        case .frame: "text.viewfinder"
        }
    }

    private func askAI() async {
        aiLoading = true
        aiError = nil
        defer { aiLoading = false }
        let entries = LibrarySearch.aiEntries(from: docs)
        guard !entries.isEmpty else {
            aiError = "Derslerde bölüm başlığı ya da ana nokta yok; yalnız yerel arama kullanılabilir."
            return
        }
        do {
            let hits = try await APIClient.shared.youtubeSearch(YouTubeSearchRequest(question: String(trimmed.prefix(500)), lessons: entries))
            aiHits = hits
            if hits.isEmpty { aiError = "Yapay zekâ ilgili bir yer bulamadı." }
        } catch {
            aiError = error.localizedDescription
        }
    }
}
