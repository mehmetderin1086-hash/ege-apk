import SwiftUI
import SwiftData

// MARK: - Soru üretici (kitap sınavı)

nonisolated struct QuizQuestion: Codable, Sendable, Equatable, Identifiable {
    var id: String { question }
    var question: String
    var options: [String]
    var answer: Int
    var explanation: String?
}

nonisolated struct QuizReply: Codable, Sendable {
    var questions: [QuizQuestion]
}

enum QuizEngine {
    static let systemPrompt = """
    Sen bir okul kütüphanecisi ve Türkçe öğretmenisin. Verilen kitap için okuduğunu anlama soruları \
    hazırla. Kitabı tanımıyorsan yalnız verilen özet/bilgiden soru üret; uydurma olay yazma. Her soru 4 \
    seçenekli, tek doğru cevaplı; "answer" doğru seçeneğin 0'dan başlayan sırası. Sorular öğrencinin \
    düzeyine uygun, kısa ve açık olsun. YALNIZCA JSON: {"questions": [{"question": "", "options": ["", "", "", ""], \
    "answer": 0, "explanation": "kısa açıklama"}]}
    """

    static func generate(title: String, author: String, summary: String, level: String, count: Int) async throws -> [QuizQuestion] {
        let prompt = """
        KİTAP: \(title) — \(author)
        ÖZET/NOT: \(summary.isEmpty ? "yok" : String(summary.prefix(1500)))
        DÜZEY: \(level.isEmpty ? "ortaokul" : level)
        SORU SAYISI: \(count)
        """
        let reply = try await GeminiClient.shared.generateJSON(QuizReply.self, prompt: prompt, system: systemPrompt,
                                                               temperature: 0.5, maxOutputTokens: 4096)
        return sanitized(reply.questions)
    }

    /// Bozuk soruları atar: 2–6 seçenek, geçerli cevap sırası, boş olmayan metin.
    nonisolated static func sanitized(_ questions: [QuizQuestion]) -> [QuizQuestion] {
        questions.compactMap { q in
            let options = q.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !q.question.trimmingCharacters(in: .whitespaces).isEmpty, (2...6).contains(options.count),
                  options.count == q.options.count, options.indices.contains(q.answer) else { return nil }
            return QuizQuestion(question: q.question, options: options, answer: q.answer, explanation: q.explanation)
        }
    }

    nonisolated static func printable(title: String, _ questions: [QuizQuestion], withAnswers: Bool) -> String {
        var lines = ["\(title) — Okuma Soruları", ""]
        for (i, q) in questions.enumerated() {
            lines.append("\(i + 1)) \(q.question)")
            for (j, option) in q.options.enumerated() {
                lines.append("   \(["A", "B", "C", "D", "E", "F"][j])) \(option)")
            }
            lines.append("")
        }
        if withAnswers {
            lines.append("CEVAP ANAHTARI: " + questions.enumerated().map { "\($0.offset + 1)-\(["A", "B", "C", "D", "E", "F"][$0.element.answer])" }.joined(separator: "  "))
        }
        return lines.joined(separator: "\n")
    }
}

struct QuizPage: View {
    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var book: CatalogBook?
    @State private var count = 5
    @State private var questions: [QuizQuestion] = []
    @State private var chosen: [Int: Int] = [:]
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Kitap") {
                if let book {
                    LabeledContent(book.title, value: book.author)
                    Button("Başka kitap seç") { self.book = nil; questions = [] }
                } else {
                    TextField("Kitap adı ara", text: $search)
                    switch Result(catching: { try IntentVeri.bul(search, context: modelContext, limit: 6) }) {
                    case .success(let matches):
                        ForEach(matches) { aday in
                            Button("\(aday.title) — \(aday.author)") { book = aday }
                        }
                    case .failure(let failure):
                        Text("Katalog araması yapılamadı: \(failure.localizedDescription)").foregroundStyle(.red)
                    }
                }
                Stepper("Soru sayısı: \(count)", value: $count, in: 3...15)
                Button {
                    Task { await generate() }
                } label: {
                    Label(isWorking ? "Sorular hazırlanıyor…" : "Soruları Üret", systemImage: "questionmark.bubble")
                }
                .buttonStyle(.kitapDolu(KitapTema.dosya))
                .disabled(book == nil || isWorking)
            }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            if !questions.isEmpty {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, q in
                    Section("\(index + 1). soru") {
                        Text(q.question).font(.subheadline.weight(.semibold))
                        ForEach(Array(q.options.enumerated()), id: \.offset) { j, option in
                            Button {
                                chosen[index] = j
                            } label: {
                                HStack {
                                    Text(option)
                                    Spacer()
                                    if let secim = chosen[index], secim == j || j == q.answer {
                                        Image(systemName: j == q.answer ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(j == q.answer ? .green : .red)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                        if chosen[index] != nil, let explanation = q.explanation, !explanation.isEmpty {
                            Text(explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    ShareLink(item: QuizEngine.printable(title: book?.title ?? "", questions, withAnswers: false)) {
                        Label("Öğrenci kâğıdını paylaş", systemImage: "doc.text")
                    }
                    ShareLink(item: QuizEngine.printable(title: book?.title ?? "", questions, withAnswers: true)) {
                        Label("Cevap anahtarlı paylaş", systemImage: "key")
                    }
                }
            }
        }
        .navigationTitle("Kitap Soruları")
    }

    private func generate() async {
        guard let book else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            questions = try await QuizEngine.generate(title: book.title, author: book.author, summary: book.notes,
                                                      level: book.readingLevel ?? "", count: count)
            chosen = [:]
            if questions.isEmpty { error = "Geçerli soru üretilemedi; yeniden deneyin." }
        } catch {
            self.error = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Koleksiyon boşluk analizi

nonisolated struct GapReply: Codable, Sendable {
    struct Gap: Codable, Sendable, Identifiable {
        var id: String { area }
        var area: String
        var reason: String
        var suggestions: [Suggestion]?
    }
    struct Suggestion: Codable, Sendable, Hashable {
        var title: String
        var author: String?
    }
    var gaps: [Gap]
    var note: String?
}

enum GapAnalysisEngine {
    struct Row: Equatable {
        let category: String
        let copies: Int
        let loans: Int
        /// 12 aylık ödünç / nüsha: 1'den büyükse talep arzı aşıyor
        var demandRatio: Double { copies == 0 ? Double(loans) : Double(loans) / Double(copies) }
    }

    /// Kategori başına nüsha ve son 12 ay ödünç sayısı (talep/arz oranı).
    static func rows(books: [CatalogBook], events: [LoanEvent], now: Date = .now) -> [Row] {
        let since = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        var categoryOf: [UUID: String] = [:]
        var copies: [String: Int] = [:]
        for book in books where !book.isWithdrawn {
            let category = (book.category ?? "").isEmpty ? "Kategorisiz" : (book.category ?? "")
            categoryOf[book.id] = category
            copies[category, default: 0] += max(1, book.quantity ?? 1)
        }
        var loans: [String: Int] = [:]
        for event in events where event.kind == .lent && event.date >= since {
            if let category = categoryOf[event.bookID] { loans[category, default: 0] += 1 }
        }
        return copies.map { Row(category: $0.key, copies: $0.value, loans: loans[$0.key] ?? 0) }
            .sorted { $0.demandRatio > $1.demandRatio }
    }

    static func analyze(rows: [Row], levels: [String: Int], classes: [String]) async throws -> GapReply {
        let table = rows.map { "\($0.category): \($0.copies) nüsha, 12 ayda \($0.loans) ödünç (oran \(String(format: "%.1f", $0.demandRatio)))" }
            .joined(separator: "\n")
        let levelText = levels.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        let prompt = """
        KOLEKSİYON (kategori başına):
        \(table)
        OKUMA DÜZEYİ DAĞILIMI: \(levelText.isEmpty ? "kayıtlı değil" : levelText)
        OKULDAKİ SINIFLAR: \(classes.isEmpty ? "belirtilmedi" : classes.joined(separator: ", "))
        """
        return try await GeminiClient.shared.generateJSON(
            GapReply.self, prompt: prompt,
            system: """
            Sen deneyimli bir okul kütüphanesi danışmanısın. Koleksiyon tablosuna bakıp EKSİK ya da talebi \
            karşılamayan en fazla 5 alanı belirle (talep/arz oranı yüksek kategoriler, hiç olmayan temel \
            türler, düzeyi eksik sınıflar). Her alan için kısa gerekçe ve Türkiye'de bulunabilen, yaşa uygun \
            2–4 kitap önerisi ver. YALNIZCA JSON: {"gaps": [{"area": "", "reason": "", "suggestions": \
            [{"title": "", "author": ""}]}], "note": ""}
            """,
            temperature: 0.5, maxOutputTokens: 4096, thinking: .auto)
    }
}

struct GapAnalysisPage: View {
    @Query private var books: [CatalogBook]
    @State private var reply: GapReply?
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        let rows = GapAnalysisEngine.rows(books: books, events: LoanHistoryStore.all)
        List {
            Section("Talep / arz (12 ay)") {
                ForEach(rows.prefix(12), id: \.category) { row in
                    HStack {
                        Text(row.category)
                        Spacer()
                        Text("\(row.copies) nüsha · \(row.loans) ödünç")
                            .font(.caption).foregroundStyle(.secondary)
                        Circle().fill(row.demandRatio >= 1 ? Color.red : (row.demandRatio >= 0.5 ? .orange : .green))
                            .frame(width: 10, height: 10)
                            .accessibilityLabel(row.demandRatio >= 1 ? "talep yüksek" : "yeterli")
                    }
                }
            }
            Section {
                Button {
                    Task { await run(rows) }
                } label: {
                    Label(isWorking ? "Gemini inceliyor…" : "Eksikleri ve Alım Önerilerini Bul", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.kitapDolu(KitapTema.toplu))
                .disabled(isWorking || rows.isEmpty)
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            if let reply {
                ForEach(reply.gaps) { gap in
                    Section(gap.area) {
                        Text(gap.reason).font(.subheadline)
                        ForEach(gap.suggestions ?? [], id: \.self) { s in
                            Label("\(s.title)\(s.author.map { " — \($0)" } ?? "")", systemImage: "cart.badge.plus")
                                .font(.callout)
                        }
                    }
                }
                if let note = reply.note, !note.isEmpty { Section("Not") { Text(note) } }
                Section {
                    ShareLink(item: shareText(reply)) { Label("Alım listesini paylaş", systemImage: "square.and.arrow.up") }
                }
            }
        }
        .navigationTitle("Koleksiyon Analizi")
    }

    private func run(_ rows: [GapAnalysisEngine.Row]) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        var levels: [String: Int] = [:]
        for book in books where !book.isWithdrawn { if let level = book.readingLevel, !level.isEmpty { levels[level, default: 0] += 1 } }
        do {
            reply = try await GapAnalysisEngine.analyze(rows: Array(rows.prefix(30)), levels: levels, classes: StudentStore.classNames())
        } catch {
            self.error = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func shareText(_ reply: GapReply) -> String {
        reply.gaps.map { gap in
            "■ \(gap.area): \(gap.reason)\n" + (gap.suggestions ?? []).map { "  - \($0.title)\($0.author.map { " (\($0))" } ?? "")" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

// MARK: - Bağış değerlendirme

nonisolated struct DonationItem: Codable, Sendable, Identifiable, Equatable {
    var id: String { title + "|" + (author ?? "") }
    var title: String
    var author: String?
    /// "al" | "alma" | "kontrol"
    var decision: String
    var reason: String
    var category: String?
    var readingLevel: String?
}

nonisolated struct DonationReply: Codable, Sendable {
    var items: [DonationItem]
}

enum DonationEngine {
    /// Bağış listesinden satırları ayıklar ("Ad - Yazar" ya da "Ad, Yazar").
    nonisolated static func parse(_ text: String) -> [(title: String, author: String?)] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-•*0123456789.) ").union(.whitespaces))
            guard line.count >= 2 else { return nil }
            for separator in [" — ", " - ", " – ", ","] where line.contains(separator) {
                let parts = line.components(separatedBy: separator)
                let title = parts[0].trimmingCharacters(in: .whitespaces)
                let author = parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
                return (title, author.isEmpty ? nil : author)
            }
            return (line, nil)
        }
    }

    static func evaluate(_ items: [(title: String, author: String?, duplicateCount: Int)]) async throws -> [DonationItem] {
        let list = items.enumerated().map { i, item in
            "\(i + 1). \(item.title)\(item.author.map { " — \($0)" } ?? "")" + (item.duplicateCount > 0 ? " [katalogda \(item.duplicateCount) nüsha var]" : "")
        }.joined(separator: "\n")
        let reply = try await GeminiClient.shared.generateJSON(
            DonationReply.self, prompt: "BAĞIŞ LİSTESİ:\n\(list)",
            system: """
            Sen bir okul kütüphanesi seçim komisyonu üyesisin. Bağış kitaplarını değerlendir: okul yaşına uygun \
            mu, eğitsel değeri var mı, katalogda zaten çok nüshası var mı (köşeli parantezde yazar), güncelliğini \
            yitirmiş mi (eski sınav kitabı, eski ansiklopedi). decision: "al", "alma" ya da "kontrol" (fiziksel \
            durum/içerik elle bakılmalı). Kısa Türkçe gerekçe; category şu listeden: \(KitapKategorileri.liste.joined(separator: ", ")); \
            readingLevel şu listeden ya da boş: \(OkumaDuzeyi.liste.joined(separator: ", ")). Listedeki her kitap için bir kayıt \
            döndür, adları aynen koru. YALNIZCA JSON: {"items": [{"title": "", "author": "", "decision": "al", "reason": "", \
            "category": "", "readingLevel": ""}]}
            """,
            temperature: 0.3, maxOutputTokens: 6144)
        return normalizedDecisions(reply.items)
    }

    /// Bilinmeyen karar güvenli tarafa ("kontrol") çekilir.
    nonisolated static func normalizedDecisions(_ items: [DonationItem]) -> [DonationItem] {
        items.map { item in
            var copy = item
            copy.decision = copy.decision.lowercased(with: Locale(identifier: "tr_TR")).trimmingCharacters(in: .whitespaces)
            if !["al", "alma", "kontrol"].contains(copy.decision) { copy.decision = "kontrol" }
            return copy
        }
    }
}

struct DonationPage: View {
    @Environment(\.modelContext) private var modelContext
    @State private var text = ""
    @State private var results: [DonationItem] = []
    @State private var isWorking = false
    @State private var error: String?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Her satıra bir kitap: Ad - Yazar", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                Button {
                    Task { await run() }
                } label: {
                    Label(isWorking ? "Değerlendiriliyor…" : "Bağışları Değerlendir", systemImage: "gift")
                }
                .buttonStyle(.kitapDolu(KitapTema.basari))
                .disabled(isWorking || DonationEngine.parse(text).isEmpty)
            } footer: {
                Text("Raf sırtları aracıyla bağış kolisinin fotoğrafından çıkan listeyi de buraya yapıştırabilirsiniz. Katalogdaki nüsha sayısı cihazda denetlenir.")
            }
            if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            if !results.isEmpty {
                ForEach(["al", "kontrol", "alma"], id: \.self) { decision in
                    let group = results.filter { $0.decision == decision }
                    if !group.isEmpty {
                        Section(decision == "al" ? "Alınsın (\(group.count))" : decision == "alma" ? "Alınmasın (\(group.count))" : "Elle kontrol (\(group.count))") {
                            ForEach(group) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.subheadline.weight(.semibold))
                                    Text(item.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button("“Alınsın” olanları kataloğa ekle", systemImage: "plus.circle.fill") { addAccepted() }
                        .buttonStyle(.kitapDolu(KitapTema.basari))
                    if let message { Text(message).font(.footnote) }
                    ShareLink(item: results.map { "\($0.decision.uppercased(with: Locale(identifier: "tr_TR"))): \($0.title) — \($0.reason)" }.joined(separator: "\n")) {
                        Label("Komisyon kararını paylaş", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .navigationTitle("Bağış Değerlendirme")
    }

    private func run() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        let parsed = DonationEngine.parse(text).prefix(60)
        let withDuplicates = parsed.map { item in
            (title: item.title, author: item.author,
             duplicateCount: MukerrerDenetimi.eslesmeler(title: item.title, isbn: "", haric: nil, context: modelContext).count)
        }
        do {
            results = try await DonationEngine.evaluate(Array(withDuplicates))
        } catch {
            self.error = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func addAccepted() {
        let accepted = results.filter { $0.decision == "al" }
        guard YetkiDurumu.shared.yonetici else { message = "Toplu bağış kaydı için yönetici kilidini açın."; return }
        do {
            let catalog = try modelContext.fetch(FetchDescriptor<CatalogBook>())
            let books = accepted.map { Book(title: $0.title, author: $0.author ?? "", notes: "Bağış", category: $0.category,
                                            readingStatus: "Okunacak", readingLevel: $0.readingLevel) }
            let outcomes = try CatalogSaveEngine.saveBatch(books, context: modelContext, catalog: catalog, mergeWithinBatch: true)
            for outcome in outcomes {
                switch outcome {
                case .inserted(let id), .merged(let id, _): EnrichmentQueue.enqueue(id)
                default: break
                }
            }
            message = "\(outcomes.count) kitap kaydedildi; eksik alanlar arka planda tamamlanacak."
            results.removeAll { $0.decision == "al" }
        } catch { message = "Kaydedilemedi: \(error.localizedDescription)" }

    }
}

// MARK: - Kategori tutarlılığı

nonisolated struct CategoryMappingReply: Codable, Sendable {
    var mappings: [String: String]
}

enum CategoryConsistencyEngine {
    /// Listede olmayan kategori yazımları ve kitap sayıları.
    static func strayCategories(_ books: [CatalogBook]) -> [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for book in books {
            guard let category = book.category?.trimmingCharacters(in: .whitespaces), !category.isEmpty,
                  !KitapKategorileri.liste.contains(category) else { continue }
            counts[category, default: 0] += 1
        }
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    /// Yapay zekâsız eşleme: aksan/büyük harf/çoğul farkı ("hikaye", "ROMANLAR") → liste ögesi.
    nonisolated static func localMatch(_ name: String) -> String? {
        let key = CatalogMatcher.normalize(name)
        for item in KitapKategorileri.liste {
            let target = CatalogMatcher.normalize(item)
            if key == target || key == target + "lar" || key == target + "ler" || key == target + "i" || key == target + "u" {
                return item
            }
        }
        return nil
    }

    static func aiMatch(_ names: [String]) async throws -> [String: String] {
        guard !names.isEmpty else { return [:] }
        let reply = try await GeminiClient.shared.generateJSON(
            CategoryMappingReply.self,
            prompt: "EŞLENECEK KATEGORİLER:\n" + names.map { "- \($0)" }.joined(separator: "\n"),
            system: """
            Kütüphane kategori adlarını standart listeye eşle. Standart liste: \(KitapKategorileri.liste.joined(separator: ", ")). \
            Her giriş için listeden EN UYGUN tek ögeyi seç; hiçbiri uymuyorsa "Diğer". YALNIZCA JSON: \
            {"mappings": {"giriş adı aynen": "liste ögesi"}}
            """,
            temperature: 0, maxOutputTokens: 2048)
        return reply.mappings.filter { KitapKategorileri.liste.contains($0.value) }
    }

    /// - Parameter aiMapped: Eşlemesi Gemini'den gelen kategori adları. Yalnız bunlar `gemini` kaynaklı
    ///   damgalanır ve geri alma günlüğüne `viaGemini` olarak yazılır; yerel eşlemeler günlükte yine görünür.
    @discardableResult
    static func apply(_ mapping: [String: String], to books: [CatalogBook], context: ModelContext,
                      aiMapped: Set<String> = []) throws -> Int {
        guard YetkiDurumu.shared.yonetici else { throw CatalogSaveEngine.SaveError(message: "Kategori düzenlemek için yönetici kilidini açın.") }
        let snapshots = books.map { ($0, $0.book) }
        let journal = AIDegisiklikToplayici(tool: "kategori")
        var changed = 0
        for book in books {
            guard let category = book.category?.trimmingCharacters(in: .whitespaces), let target = mapping[category], target != category, KitapKategorileri.liste.contains(target) else { continue }
            let previous = book.book
            let viaGemini = aiMapped.contains(category)
            book.category = target
            if viaGemini { book.update(from: BookFieldMetadata.stampChanges(before: previous, after: book.book, source: "gemini")) }
            book.refreshSearchKey()
            journal.note(book, before: previous, viaGemini: viaGemini)
            changed += 1
        }
        do { try context.save() }
        catch { journal.discard(); snapshots.forEach { $0.0.update(from: $0.1) }; throw error }
        journal.commit()
        return changed
    }
}

struct CategoryConsistencyPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]
    @State private var mapping: [String: String] = [:]
    @State private var aiMapped: Set<String> = []
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        let strays = CategoryConsistencyEngine.strayCategories(books)
        Form {
            Section {
                if strays.isEmpty {
                    Label("Tüm kategoriler standart listede", systemImage: "checkmark.seal.fill").foregroundStyle(KitapTema.basari)
                }
                ForEach(strays, id: \.name) { stray in
                    Picker("\(stray.name) (\(stray.count))", selection: Binding(
                        get: { mapping[stray.name] ?? "" },
                        set: { mapping[stray.name] = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Dokunma").tag("")
                        ForEach(KitapKategorileri.liste, id: \.self) { Text($0).tag($0) }
                    }
                }
            } header: {
                Text("Standart dışı kategoriler")
            } footer: {
                Text("Filtreler ve raporlar tutarlı olsun diye farklı yazımlar tek kategoride toplanır.")
            }
            if !strays.isEmpty {
                Section {
                    Button("Yerel eşle (yazım farkları)", systemImage: "textformat") {
                        for stray in strays { if let match = CategoryConsistencyEngine.localMatch(stray.name) { mapping[stray.name] = match } }
                    }
                    Button {
                        Task { await runAI(strays.map(\.name)) }
                    } label: {
                        Label(isWorking ? "Gemini eşliyor…" : "Kalanları Gemini eşlesin", systemImage: "sparkles")
                    }
                    .disabled(isWorking)
                    Button("\(mapping.count) eşlemeyi uygula", systemImage: "checkmark.circle.fill") {
                        do {
                            let count = try CategoryConsistencyEngine.apply(mapping, to: books, context: modelContext, aiMapped: aiMapped)
                            message = "\(count) kitabın kategorisi düzeltildi. Ayarlar › Yapay Zekâ bölümünden geri alınabilir."
                            mapping = [:]
                            aiMapped = []
                        } catch { message = "Kaydedilemedi: \(error.localizedDescription)" }
                    }
                    .buttonStyle(.kitapDolu(KitapTema.ana))
                    .disabled(mapping.isEmpty)
                }
            }
            if let message { Section { Text(message).font(.footnote) } }
        }
        .navigationTitle("Kategori Tutarlılığı")
    }

    private func runAI(_ names: [String]) async {
        isWorking = true
        defer { isWorking = false }
        let remaining = names.filter { mapping[$0] == nil }
        do {
            let result = try await CategoryConsistencyEngine.aiMatch(Array(remaining.prefix(80)))
            mapping.merge(result) { current, _ in current }
            aiMapped.formUnion(result.keys)
        } catch {
            message = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Sınıfa toplu kişisel okuma listesi (PDF)

struct ClassReadingListsPage: View {
    @Query private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]
    @State private var className = StudentStore.classNames().first ?? ""
    @State private var perStudent = 3
    @State private var progress = 0
    @State private var total = 0
    @State private var pdfURL: URL?
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        let students = StudentStore.students(in: className)
        Form {
            Section {
                Picker("Sınıf", selection: $className) {
                    ForEach(StudentStore.classNames(), id: \.self) { Text($0).tag($0) }
                }
                Stepper("Öğrenci başına \(perStudent) kitap", value: $perStudent, in: 1...6)
                LabeledContent("Öğrenci", value: "\(students.count)")
            } footer: {
                Text("Her öğrenci için ayrı istek gönderilir (\(students.count) istek). Öğrenci adları Google'a gönderilmez; yalnızca sınıf ve okuduğu kitap adları gider.")
            }
            Section {
                if total > 0 && pdfURL == nil {
                    ProgressView(value: Double(progress), total: Double(total)) { Text("\(progress)/\(total) öğrenci") }
                    Button("Durdur", role: .destructive) { task?.cancel() }
                } else {
                    Button("Kişisel Listeleri Hazırla", systemImage: "list.star") { start(students) }
                        .buttonStyle(.kitapDolu(KitapTema.toplu))
                        .disabled(students.isEmpty)
                }
                if let pdfURL { ShareLink(item: pdfURL) { Label("PDF'i Paylaş / Yazdır", systemImage: "printer") } }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Kişisel Okuma Listeleri")
        .onDisappear { task?.cancel() }
    }

    private func start(_ students: [Student]) {
        pdfURL = nil
        error = nil
        progress = 0
        total = students.count
        let candidates = AssistantContext.availableSample(from: books.filter { !$0.isWithdrawn }, loans: loans, limit: 120)
        task = Task { @MainActor in
            var sections: [PDFReportBuilder.Section] = []
            for student in students {
                if Task.isCancelled { break }
                let previous = LoanHistoryStore.events(for: student.id).filter { $0.kind == .returned && $0.readingCompleted == true && $0.loanKind != "textbook" && $0.memberID == nil }.map(\.bookTitle)
                let unread = candidates.filter { !previous.contains($0.title) }
                do {
                    let reply = try await AIRecommendEngine.recommend(className: className, studentName: "", interests: "",
                                                                      previous: Array(Set(previous)).prefix(20).map { $0 },
                                                                      candidates: unread, loans: loans, count: perStudent)
                    let rows = reply.recommendations.prefix(perStudent).map { rec -> (String, String) in
                        let book = unread.first { CatalogMatcher.isSimilar($0.title, rec.title) }
                        let place = book?.konumMetni ?? ""
                        return ("\(rec.title) — \(rec.reason)", place)
                    }
                    sections.append(PDFReportBuilder.Section(title: "\(student.name) (\(className))", rows: Array(rows)))
                } catch {
                    self.error = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
                    if case .limitReached = error as? GeminiError { break }
                }
                progress += 1
            }
            let data = PDFReportBuilder.build(title: "\(className) — KİŞİSEL OKUMA LİSTELERİ",
                                              subtitle: Date.now.formatted(date: .long, time: .omitted), sections: sections,
                                              signatures: ["Kütüphane Sorumlusu"])
            pdfURL = GeciciDosya.yaz(data, ad: "Okuma-Listeleri-\(className).pdf")
            total = 0
        }
    }
}

// MARK: - Yapay zekâ değişiklik günlüğü (P-04)

/// Yapay zekânın katalogda yaptığı tek bir alan değişikliği.
nonisolated struct AIDegisiklik: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    /// Aynı toplu işlemin değişiklikleri ortak kimlik taşır ("son toplu işlemi geri al").
    var batchID: UUID
    var bookID: UUID
    var field: String
    var oldValue: String
    var newValue: String
    var date: Date
    /// "tamamla", "kategori", "zenginlestirme"
    var tool: String
    /// Alan kaynağı `gemini` olarak damgalandı: geri alırken kaynak hâlâ `gemini` olmalı.
    var viaGemini: Bool = true
}

/// Geri alınan değişikliklerin kimlikleri (günlük dosyasına ayrı satır olarak eklenir).
nonisolated private struct AIGeriAlmaKaydi: Codable {
    var undoneIDs: [UUID]
}

/// Yapay zekâ kaynaklı yazımlar JSON satırlarıyla (`AIDegisiklikGunlugu.jsonl`) kaydedilir:
/// eski değer, yeni değer, zaman ve araç. Satır ekleme ucuzdur (arka plan zenginleştirmesi sık yazar);
/// geri alma ayrı bir işaret satırı ekler, dosya şişince sıkıştırılır.
nonisolated enum AIDegisiklikGunlugu {
    nonisolated(unsafe) static var directoryOverride: URL?
    private static let lock = NSLock()
    static let compactionThreshold = 4000
    static let keptAfterCompaction = 2500

    static var url: URL? {
        let base = directoryOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("AIDegisiklikGunlugu.jsonl")
    }

    // MARK: Okuma / yazma

    /// Geri alınmışlar `undone` işaretiyle değil, listeden çıkarılarak döner.
    static func all(includeUndone: Bool = false) -> [AIDegisiklik] {
        lock.lock(); defer { lock.unlock() }
        let (changes, undone) = readLocked()
        return includeUndone ? changes : changes.filter { !undone.contains($0.id) }
    }

    private static func readLocked() -> ([AIDegisiklik], Set<UUID>) {
        guard let url, let data = try? Data(contentsOf: url) else { return ([], []) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var changes: [AIDegisiklik] = []
        var undone = Set<UUID>()
        for line in data.split(separator: UInt8(ascii: "\n")) {
            if let change = try? decoder.decode(AIDegisiklik.self, from: Data(line)) {
                changes.append(change)
            } else if let marker = try? decoder.decode(AIGeriAlmaKaydi.self, from: Data(line)) {
                undone.formUnion(marker.undoneIDs)
            } // bozuk satır (yarım yazım) atlanır
        }
        return (changes, undone)
    }

    private static func encodeLine<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(value) else { return nil }
        line.append(UInt8(ascii: "\n"))
        return line
    }

    private static func appendLocked(_ lines: [Data]) throws {
        guard let url else { throw CocoaError(.fileNoSuchFile) }
        let payload = lines.reduce(into: Data()) { $0.append($1) }
        guard !payload.isEmpty else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: payload)
        } else {
            try payload.write(to: url, options: .atomic)
        }
    }

    static func append(_ entries: [AIDegisiklik]) throws {
        guard !entries.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        try appendLocked(entries.compactMap { encodeLine($0) })
        compactIfNeededLocked()
    }

    private static func compactIfNeededLocked() {
        guard let url, let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > compactionThreshold * 300 else { return }
        let (changes, undone) = readLocked()
        guard changes.count > compactionThreshold else { return }
        let kept = changes.suffix(keptAfterCompaction)
        let keptUndone = undone.intersection(kept.map(\.id))
        var data = Data()
        kept.compactMap { encodeLine($0) }.forEach { data.append($0) }
        if !keptUndone.isEmpty, let marker = encodeLine(AIGeriAlmaKaydi(undoneIDs: Array(keptUndone))) { data.append(marker) }
        try? data.write(to: url, options: .atomic)
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: Fark

    /// `before` → `after` arasında değişen metin alanlarını günlük kayıtlarına çevirir (kapak görseli hariç).
    static func entries(before: Book, after: Book, bookID: UUID, batchID: UUID, tool: String,
                        date: Date = .now, viaGemini: Bool = true) -> [AIDegisiklik] {
        BookFieldMetadata.fields.filter { $0 != "coverData" }.compactMap { field in
            let old = BookFieldMetadata.value(field, in: before)
            let new = BookFieldMetadata.value(field, in: after)
            guard old != new else { return nil }
            return AIDegisiklik(batchID: batchID, bookID: bookID, field: field, oldValue: old, newValue: new,
                                date: date, tool: tool, viaGemini: viaGemini)
        }
    }

    /// Alanı (kapak hariç) bir `Book` değerine yazar; boş değer isteğe bağlı alanlarda `nil` olur.
    static func setField(_ field: String, to value: String, on book: inout Book) {
        let optional: String? = value.isEmpty ? nil : value
        switch field {
        case "title": book.title = value
        case "author": book.author = value
        case "isbn": book.isbn = optional
        case "publisher": book.publisher = optional
        case "publicationYear": book.publicationYear = optional
        case "edition": book.edition = optional
        case "pageCount": book.pageCount = optional
        case "category": book.category = optional
        case "language": book.language = optional
        case "notes": book.notes = value
        case "cabinet": book.cabinet = optional
        case "shelf": book.shelf = optional
        case "series": book.series = optional
        case "volume": book.volume = optional.flatMap(Int.init)
        case "tags": book.tags = optional
        case "readingLevel": book.readingLevel = optional
        case "contentWarning": book.contentWarning = optional
        default: break
        }
    }

    // MARK: Son toplu işlem

    struct TopluIslem: Equatable {
        var batchID: UUID
        var tool: String
        var date: Date
        var entries: [AIDegisiklik]
        var bookCount: Int { Set(entries.map(\.bookID)).count }
    }

    /// Geri alınmamış en son toplu işlem.
    static func lastBatch() -> TopluIslem? {
        let live = all()
        guard let last = live.last else { return nil }
        let entries = live.filter { $0.batchID == last.batchID }
        return TopluIslem(batchID: last.batchID, tool: last.tool, date: entries.map(\.date).max() ?? last.date, entries: entries)
    }

    static func toolTitle(_ tool: String) -> String {
        switch tool {
        case "tamamla": "Eksikleri Tamamla"
        case "kategori": "Kategori Tutarlılığı"
        case "zenginlestirme": "Arka plan zenginleştirmesi"
        default: "Yapay zekâ"
        }
    }

    struct GeriAlmaSonucu: Equatable {
        var restored: Int
        var skipped: Int
    }

    /// Son toplu işlemi geri alır. Alan kullanıcı tarafından sonradan değiştirilmişse (değer ya da kaynak
    /// artık yapay zekâya ait değilse) atlanır; yönetici kilidi açık olmalıdır. Kayıt başarısızsa hiçbir şey değişmez.
    @MainActor
    static func undoLastBatch(books: [CatalogBook], context: ModelContext) throws -> GeriAlmaSonucu {
        guard YetkiDurumu.shared.yonetici else {
            throw CatalogSaveEngine.SaveError(message: "Geri almak için yönetici kilidini açın.")
        }
        guard let batch = lastBatch() else { return GeriAlmaSonucu(restored: 0, skipped: 0) }
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var snapshots: [UUID: (CatalogBook, Book)] = [:]
        var restoredIDs: [UUID] = []
        var skipped = 0
        // Yeni değerler eskiden yeniye uygulandığı için geri alma tersten yapılır
        for entry in batch.entries.reversed() {
            guard let book = byID[entry.bookID], !book.isDeleted, book.modelContext != nil else { skipped += 1; continue }
            var value = book.book
            var metadata = BookFieldMetadata.decode(value.fieldMetadata)
            let sourceOK = !entry.viaGemini || metadata[entry.field]?.source == "gemini"
            guard BookFieldMetadata.value(entry.field, in: value) == entry.newValue, sourceOK,
                  !(metadata[entry.field]?.isLocked ?? false) else { skipped += 1; continue }
            if snapshots[book.id] == nil { snapshots[book.id] = (book, book.book) }
            setField(entry.field, to: entry.oldValue, on: &value)
            if metadata[entry.field]?.source == "gemini" { metadata[entry.field] = nil }
            value.fieldMetadata = metadata.isEmpty ? nil : BookFieldMetadata.encode(metadata)
            book.update(from: value)
            book.refreshSearchKey()
            restoredIDs.append(entry.id)
        }
        do { try context.save() }
        catch {
            snapshots.values.forEach { model, previous in if !model.isDeleted { model.update(from: previous) } }
            throw error
        }
        if !restoredIDs.isEmpty {
            lock.lock(); defer { lock.unlock() }
            if let line = encodeLine(AIGeriAlmaKaydi(undoneIDs: restoredIDs)) { try? appendLocked([line]) }
        }
        return GeriAlmaSonucu(restored: restoredIDs.count, skipped: skipped)
    }
}

/// Toplu işlem sırasında değişiklikleri biriktirir; kayıt başarılı olunca `commit`, geri alınırsa `discard`.
@MainActor
final class AIDegisiklikToplayici {
    let batchID: UUID
    let tool: String
    private(set) var pending: [AIDegisiklik] = []

    init(tool: String, batchID: UUID = UUID()) {
        self.tool = tool
        self.batchID = batchID
    }

    /// `book` şu an `before` değerinden farklıysa farkı biriktirir.
    func note(_ book: CatalogBook, before: Book, viaGemini: Bool = true) {
        pending += AIDegisiklikGunlugu.entries(before: before, after: book.book, bookID: book.id,
                                               batchID: batchID, tool: tool, viaGemini: viaGemini)
    }

    func discard() { pending.removeAll() }

    @discardableResult
    func commit() -> Bool {
        defer { pending.removeAll() }
        guard !pending.isEmpty else { return true }
        return (try? AIDegisiklikGunlugu.append(pending)) != nil
    }
}

// MARK: - Büyük görselleri sıkıştır (AI-11)

/// Eski kayıtlarda arka kapak ve künye fotoğrafları ham (3-5 MB) saklanıyordu. Yalnız eşiği aşanlar
/// 1600 px / %80 JPEG'e küçültülür; küçülmeyen (zaten küçük ya da çözülemeyen) görsele dokunulmaz.
enum GorselSikistirmaMotoru {
    static let esikBayt = 1_500_000
    static let enBuyukKenar = 1600
    static let kalite = 0.8

    nonisolated struct Aday: Equatable, Sendable {
        var bookID: UUID
        var title: String
        var backBytes: Int
        var imprintBytes: Int
        var total: Int { backBytes + imprintBytes }
    }

    nonisolated struct Ozet: Equatable, Sendable {
        var images = 0
        var beforeBytes = 0
        var afterBytes = 0
        var savedBytes: Int { max(0, beforeBytes - afterBytes) }
    }

    /// Bayt sayısını okunur yazar ("4,2 MB").
    nonisolated static func megabayt(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Eşiği aşan arka kapak/künye görseli olan kitaplar.
    static func adaylar(in books: [CatalogBook], esik: Int = esikBayt) -> [Aday] {
        books.compactMap { book in
            guard !book.isDeleted else { return nil }
            let back = book.backCoverData?.count ?? 0
            let imprint = book.imprintData?.count ?? 0
            guard back > esik || imprint > esik else { return nil }
            return Aday(bookID: book.id, title: book.title, backBytes: back > esik ? back : 0, imprintBytes: imprint > esik ? imprint : 0)
        }
    }

    /// Tek görseli küçültür; sonuç orijinalden küçük değilse `nil` (dokunulmaz).
    nonisolated static func sikistir(_ data: Data) -> Data? {
        guard let output = GeminiImagePreparer.jpegData(from: data, maxPixel: enBuyukKenar, quality: kalite),
              output.count < data.count else { return nil }
        return output
    }

    /// Adayları sırayla sıkıştırır; her 10 kitapta bir kaydeder, kayıt başarısızsa o grubu geri alır.
    @MainActor
    static func calistir(books: [CatalogBook], context: ModelContext, esik: Int = esikBayt,
                         progress: ((Int, Int) -> Void)? = nil) async throws -> Ozet {
        guard YetkiDurumu.shared.yonetici else {
            throw CatalogSaveEngine.SaveError(message: "Görselleri sıkıştırmak için yönetici kilidini açın.")
        }
        let targets = books.filter { book in
            !book.isDeleted && ((book.backCoverData?.count ?? 0) > esik || (book.imprintData?.count ?? 0) > esik)
        }
        var summary = Ozet()
        var group: [(CatalogBook, Data?, Data?)] = []
        var groupSummary = Ozet()

        func flush() throws {
            guard !group.isEmpty else { return }
            do { try context.save() }
            catch {
                for (book, back, imprint) in group where !book.isDeleted { book.backCoverData = back; book.imprintData = imprint }
                group = []; groupSummary = Ozet()
                throw error
            }
            summary.images += groupSummary.images
            summary.beforeBytes += groupSummary.beforeBytes
            summary.afterBytes += groupSummary.afterBytes
            group = []; groupSummary = Ozet()
        }

        for (index, book) in targets.enumerated() {
            try Task.checkCancellation()
            let back = book.backCoverData, imprint = book.imprintData
            var changed = false
            if let back, back.count > esik {
                let small = await Task.detached(priority: .utility) { sikistir(back) }.value
                if let small { book.backCoverData = small; changed = true
                    groupSummary.images += 1; groupSummary.beforeBytes += back.count; groupSummary.afterBytes += small.count }
            }
            if let imprint, imprint.count > esik {
                let small = await Task.detached(priority: .utility) { sikistir(imprint) }.value
                if let small { book.imprintData = small; changed = true
                    groupSummary.images += 1; groupSummary.beforeBytes += imprint.count; groupSummary.afterBytes += small.count }
            }
            if changed { group.append((book, back, imprint)) }
            if group.count >= 10 { try flush() }
            progress?(index + 1, targets.count)
        }
        try flush()
        return summary
    }
}

struct GorselSikistirmaPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]
    @State private var candidates: [GorselSikistirmaMotoru.Aday]?
    @State private var summary: GorselSikistirmaMotoru.Ozet?
    @State private var isWorking = false
    @State private var progress = (done: 0, total: 0)
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text("Eski kayıtlarda arka kapak ve künye fotoğrafları 3-5 MB’lık ham dosya olarak duruyor. 1,5 MB’tan büyük olanlar okunabilirliği bozmadan küçültülür; ilk kapak fotoğraflarına dokunulmaz.")
                    .font(.footnote)
            }
            Section {
                if let candidates {
                    let total = candidates.reduce(0) { $0 + $1.total }
                    LabeledContent("Büyük görseli olan kitap", value: "\(candidates.count)")
                    LabeledContent("Toplam boyut", value: GorselSikistirmaMotoru.megabayt(total))
                }
                if isWorking, progress.total > 0 {
                    ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                        Text("Sıkıştırılıyor: \(progress.done)/\(progress.total)").font(.caption)
                    }
                    Button("Durdur", role: .destructive) { task?.cancel() }
                } else {
                    Button("Büyük görselleri tara", systemImage: "magnifyingglass") { scan() }
                        .disabled(isWorking)
                    if let candidates, !candidates.isEmpty {
                        Button("Sıkıştır", systemImage: "arrow.down.right.and.arrow.up.left") { run() }
                            .buttonStyle(.kitapDolu(KitapTema.ana))
                            .disabled(isWorking)
                    }
                }
            }
            if let summary {
                Section("Sonuç") {
                    LabeledContent("Küçültülen görsel", value: "\(summary.images)")
                    LabeledContent("Önce", value: GorselSikistirmaMotoru.megabayt(summary.beforeBytes))
                    LabeledContent("Sonra", value: GorselSikistirmaMotoru.megabayt(summary.afterBytes))
                    LabeledContent("Kazanılan", value: GorselSikistirmaMotoru.megabayt(summary.savedBytes))
                }
            }
            if let errorText { Section { Text(errorText).font(.footnote).foregroundStyle(.red) } }
        }
        .navigationTitle("Büyük Görselleri Sıkıştır")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
    }

    private func scan() {
        isWorking = true
        errorText = nil
        summary = nil
        // Dosya boyutlarını okumak diskten görsel yükler; kısa bir bekleme göstergesiyle yapılır
        task = Task { @MainActor in
            await Task.yield()
            candidates = GorselSikistirmaMotoru.adaylar(in: books)
            isWorking = false
        }
    }

    private func run() {
        isWorking = true
        errorText = nil
        progress = (0, candidates?.count ?? 0)
        task = Task { @MainActor in
            defer { isWorking = false }
            do {
                summary = try await GorselSikistirmaMotoru.calistir(books: books, context: modelContext) { done, total in
                    progress = (done, total)
                }
                candidates = GorselSikistirmaMotoru.adaylar(in: books)
            } catch is CancellationError {
                errorText = "Durduruldu; o ana kadar kaydedilenler kalıcıdır."
            } catch {
                errorText = "Sıkıştırılamadı: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Ayarlar › Yapay Zekâ

/// Kabuk Ayarlar sayfasında "Yapay Zekâ" bölümü olarak gösterilir: mevcut Gemini ayarlarına
/// bağlantı durumu, son toplu işlemi geri alma ve bakım araçları eklenir.
struct YapayZekaAyarlariBolumu: View {
    var body: some View {
        GeminiSettingsSection()
        GeminiBaglantiBolumu()
        AIGeriAlmaBolumu()
        Section {
            NavigationLink {
                GorselSikistirmaPage()
            } label: {
                Label("Büyük görselleri sıkıştır", systemImage: "photo.badge.arrow.down")
            }
        } header: {
            Text("Bakım")
        } footer: {
            Text("Arka kapak ve künye fotoğraflarının disk kullanımını azaltır.")
        }
    }
}

private struct GeminiBaglantiBolumu: View {
    private let durum = GeminiDurumu.shared
    @State private var reachability = GeminiReachability.shared
    @State private var checking = false

    var body: some View {
        Section {
            LabeledContent("Durum", value: durum.isActive ? "Hazır" : GeminiSettings.statusDescription)
            if durum.keyReadBlocked {
                Label("Anahtar cihaz ilk kez açılmadan okunamadı; kilidi açtıktan sonra yeniden denenir.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Bağlantı", value: reachability.durum.etiket)
            Button {
                checking = true
                Task {
                    await reachability.probe()
                    checking = false
                }
            } label: {
                if checking { ProgressView() } else { Label("Bağlantıyı denetle", systemImage: "network") }
            }
            .disabled(checking)
        } header: {
            Text("Bağlantı")
        } footer: {
            Text("Okul ağı Google’ı engellerse sesli yanıt cihaz sesiyle okunur ve asistan bilinen soruları cihazda yanıtlar.")
        }
    }
}

private struct AIGeriAlmaBolumu: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var books: [CatalogBook]
    @State private var batch = AIDegisiklikGunlugu.lastBatch()
    @State private var confirming = false
    @State private var result: String?
    @State private var errorText: String?

    var body: some View {
        Section {
            if let batch {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AIDegisiklikGunlugu.toolTitle(batch.tool)).font(.subheadline.weight(.semibold))
                    Text("\(batch.bookCount) kitap · \(batch.entries.count) alan · \(batch.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Son AI toplu işlemini geri al", systemImage: "arrow.uturn.backward", role: .destructive) { confirming = true }
                    .disabled(!YetkiDurumu.shared.yonetici)
            } else {
                Label("Geri alınacak yapay zekâ işlemi yok", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let result { Text(result).font(.footnote) }
            if let errorText { Text(errorText).font(.footnote).foregroundStyle(.red) }
        } header: {
            Text("Yapay zekâ değişiklikleri")
        } footer: {
            Text("Yapay zekânın doldurduğu alanlar kaydedilir. Geri alırken sonradan elle değiştirdiğiniz alanlara dokunulmaz.")
        }
        .onAppear { batch = AIDegisiklikGunlugu.lastBatch() }
        .confirmationDialog("Son toplu işlem geri alınsın mı?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Geri al", role: .destructive) { undo() }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Yapay zekânın doldurduğu alanlar önceki değerlerine döner.")
        }
    }

    private func undo() {
        do {
            let outcome = try AIDegisiklikGunlugu.undoLastBatch(books: books, context: modelContext)
            result = "\(outcome.restored) alan geri alındı" + (outcome.skipped > 0 ? "; \(outcome.skipped) alan sonradan değiştirildiği için bırakıldı." : ".")
            errorText = nil
        } catch {
            errorText = "Geri alınamadı: \(error.localizedDescription)"
        }
        batch = AIDegisiklikGunlugu.lastBatch()
    }
}
