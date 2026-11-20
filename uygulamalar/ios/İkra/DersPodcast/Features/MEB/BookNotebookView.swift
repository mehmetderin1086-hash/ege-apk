import Foundation
import SwiftData
import SwiftUI

/// Metin seçimine bağımlı olmayan, Türkçe ve Unicode güvenli kart taslağı.
/// Aynı ifade birden çok kez geçiyorsa yalnız seçilen eşleşme gizlenir.
nonisolated enum BookCardDraft {
    struct Value: Equatable, Sendable {
        var front: String
        var back: String
    }

    enum Problem: Error, LocalizedError, Equatable {
        case emptyQuestion, emptyAnswer, emptyPassage, emptyPhrase, phraseNotFound, invalidOccurrence, entirePassage
        var errorDescription: String? {
            switch self {
            case .emptyQuestion: "Önce kartın sorusunu yaz."
            case .emptyAnswer: "Kartın cevabı boş olamaz."
            case .emptyPassage: "Boşluk doldurmak için önce bir kaynak cümle ekle."
            case .emptyPhrase: "Gizlemek istediğin sözcüğü veya ifadeyi yaz."
            case .phraseNotFound: "Bu ifade kaynak metinde aynen bulunamadı. Büyük/küçük harf ve noktalama işaretlerini kontrol et."
            case .invalidOccurrence: "Gizlenecek eşleşmeyi yeniden seç."
            case .entirePassage: "Cümlenin tamamı yerine içindeki bir sözcüğü veya ifadeyi gizle."
            }
        }
    }

    static func manual(question: String, answer: String) throws -> Value {
        let front = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let back = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else { throw Problem.emptyQuestion }
        guard !back.isEmpty else { throw Problem.emptyAnswer }
        return Value(front: front, back: back)
    }

    static func occurrenceCount(in quote: String, phrase: String) -> Int {
        ranges(in: quote, phrase: phrase.trimmingCharacters(in: .whitespacesAndNewlines)).count
    }

    static func cloze(quote: String, phrase: String, occurrence: Int = 0) throws -> Value {
        let text = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw Problem.emptyPassage }
        guard !answer.isEmpty else { throw Problem.emptyPhrase }
        let matches = ranges(in: text, phrase: answer)
        guard !matches.isEmpty else { throw Problem.phraseNotFound }
        guard matches.indices.contains(occurrence) else { throw Problem.invalidOccurrence }
        let selected = matches[occurrence]
        guard selected != (text.startIndex..<text.endIndex) else { throw Problem.entirePassage }
        var front = text
        front.replaceSubrange(selected, with: "[Boşluk]")
        return Value(front: front, back: String(text[selected]))
    }

    private static func ranges(in text: String, phrase: String) -> [Range<String.Index>] {
        guard !phrase.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
              let match = text.range(of: phrase, options: .literal, range: cursor..<text.endIndex) {
            result.append(match)
            cursor = match.upperBound
        }
        return result
    }
}

/// Yeni kart ayrı bir bağlamda kaydedilir: başarısızlık başka ekranların bekleyen değişikliklerini geri almaz.
@MainActor enum BookCardWriter {
    struct Outcome: Equatable {
        var id: UUID
        var created: Bool
    }

    static func save(_ draft: BookCardDraft.Value, source: BookStudyNote, context: ModelContext) throws -> Outcome {
        let valid = try BookCardDraft.manual(question: draft.front, answer: draft.back)
        let writer = ModelContext(context.container)
        writer.autosaveEnabled = false
        let bookID: String? = source.bookID
        let descriptor = FetchDescriptor<ReviewCard>(predicate: #Predicate { $0.sourceBookID == bookID })
        let key = CardImport.key(front: valid.front, back: valid.back)
        if let existing = try writer.fetch(descriptor).first(where: { $0.sourcePage == source.page && CardImport.key(front: $0.front, back: $0.back) == key }) {
            if existing.learningSource == nil {
                existing.learningSource = .init(note: source)
                do { try writer.save() } catch { writer.rollback(); throw error }
            }
            LearningContinuity.bookCard(existing, source: source)
            return Outcome(id: existing.id, created: false)
        }
        let card = ReviewCard(episodeID: BookStudyStore.sourceID(for: source.bookID), episodeTitle: source.title,
                              kind: .flashcard, front: valid.front, back: valid.back, sourcePage: source.page)
        card.sourceBookID = source.bookID
        card.learningSource = .init(note: source)
        card.origin = "book"
        do {
            try writer.transaction {
                writer.insert(card)
                try writer.save()
            }
        } catch {
            writer.rollback()
            throw error
        }
        LearningContinuity.bookCard(card, source: source)
        return Outcome(id: card.id, created: true)
    }
}

struct BookNoteEditor: View {
    let bookID: String
    let title: String
    let page: Int
    var existing: BookStudyNote?
    @Environment(\.dismiss) private var dismiss
    @State private var quoteText: String
    @State private var noteText: String
    @State private var bookmarked: Bool
    @State private var subject: String
    @State private var concept: String
    @State private var problem: String?
    @State private var discard = false
    private let initialQuote: String
    private let initialNote: String
    private let initialBookmark: Bool
    private var store: BookStudyStore { .shared }

    init(bookID: String, title: String, page: Int, quote: String, existing: BookStudyNote? = nil) {
        self.bookID = bookID
        self.title = title
        self.page = page
        self.existing = existing
        let savedQuote = existing?.quote ?? quote
        let savedNote = existing?.note ?? ""
        let savedBookmark = existing?.isBookmark ?? false
        initialQuote = savedQuote; initialNote = savedNote; initialBookmark = savedBookmark
        _quoteText = State(initialValue: savedQuote)
        _noteText = State(initialValue: savedNote)
        _bookmarked = State(initialValue: savedBookmark)
        _subject = State(initialValue: existing?.subject ?? "")
        _concept = State(initialValue: existing?.concept ?? "")
    }

    private var dirty: Bool { quoteText != initialQuote || noteText != initialNote || bookmarked != initialBookmark || subject != (existing?.subject ?? "") || concept != (existing?.concept ?? "") }
    private var canSave: Bool {
        bookmarked || !quoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kaynak") {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("PDF sayfası \(page)").font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $quoteText).font(.body).frame(minHeight: 120)
                        .accessibilityLabel("Kitaptan alıntı")
                        .accessibilityIdentifier("book.note.quote")
                } header: { Text("Kitaptan alıntı") } footer: {
                    Text("İstersen kitaptan bir alıntı yapıştır. Metni düzenleyebilirsin; notun bu kitap ve sayfayla bağlantılı kalır.")
                }
                Section("Öğrenme bağlantısı") {
                    TextField("Ders (ör. Biyoloji)", text: $subject)
                    TextField("Konu / kazanım (ör. Mitoz)", text: $concept)
                    Text("Bu nottan oluşturduğun kartlar aynı konu altında soru, yazılı ve deney geçmişine bağlanır.").font(.caption)
                }
                Section("Kendi notun") {
                    TextEditor(text: $noteText).font(.body).frame(minHeight: 110)
                        .accessibilityLabel("Kendi notun")
                        .accessibilityIdentifier("book.note.text")
                }
                Section { Toggle("Bu sayfayı işaretle", isOn: $bookmarked).frame(minHeight: 44) }
                if let message = problem ?? store.loadError {
                    Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.primary) }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle(existing == nil ? "Kitap notu ekle" : "Kitap notunu düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { if dirty { discard = true } else { dismiss() } }.frame(minHeight: 44)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).frame(minHeight: 44).disabled(!canSave)
                        .accessibilityIdentifier("book.note.save")
                }
            }
            .interactiveDismissDisabled(dirty)
            .confirmationDialog("Değişikliklerden vazgeçilsin mi?", isPresented: $discard, titleVisibility: .visible) {
                Button("Değişiklikleri bırak", role: .destructive) { dismiss() }
                Button("Düzenlemeye devam et", role: .cancel) {}
            }
        }
    }

    private func save() {
        var entry = existing ?? BookStudyNote(bookID: bookID, title: title, page: page)
        entry.quote = quoteText
        entry.note = noteText
        entry.isBookmark = bookmarked
        entry.subject = subject; entry.concept = concept
        entry.updatedAt = .now
        do {
            try store.save(entry)
            if let saved = store.entries.first(where: { $0.id == entry.id }) { LearningEvidenceStore.shared.upsert([LearningContinuity.noteEvidence(saved)]) }
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct BookNotebookView: View {
    var bookID: String? = nil
    var onOpen: ((BookStudyNote) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var search = ""
    @State private var filter = Filter.all
    @State private var editing: BookStudyNote?
    @State private var makingCard: BookStudyNote?
    @State private var makingVideo: BookStudyNote?
    @State private var opening: BookStudyNote?
    @State private var deleting: BookStudyNote?
    @State private var problem: String?
    @State private var showCards = false
    private var store: BookStudyStore { .shared }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "Tümü", notes = "Notlar", bookmarks = "İşaretler"
        var id: String { rawValue }
    }
    private var entries: [BookStudyNote] {
        store.entries.filter { bookID == nil || $0.bookID == bookID }
            .filter { filter == .all || (filter == .bookmarks ? $0.isBookmark : !$0.quote.isEmpty || !$0.note.isEmpty) }
            .filter { StudySearch.matches([$0.title, $0.quote, $0.note, "Sayfa \($0.page)"], query: search) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Menu {
                        Picker("Göster", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        HStack {
                            Text(filter.rawValue).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "line.3.horizontal.decrease").accessibilityHidden(true)
                        }.frame(minHeight: 44)
                    }
                    .accessibilityLabel("Gösterilen kayıtlar, \(filter.rawValue)")
                    Button { showCards = true } label: { Label("Kitap kartlarım", systemImage: "rectangle.stack").frame(minHeight: 44) }
                        .accessibilityHint("Kitaplardan oluşturduğun kartları gösterir")
                }
                if let message = problem ?? store.loadError {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.primary)
                        Button("Yeniden yükle") {
                            do { try store.reload(); problem = nil } catch { problem = error.localizedDescription }
                        }.frame(minHeight: 44)
                    }
                }
                if entries.isEmpty && store.loadError == nil {
                    Section {
                        if !search.isEmpty {
                            ContentUnavailableView.search(text: search)
                        } else {
                            ContentUnavailableView(filter == .bookmarks ? "İşaretli sayfa yok" : "Kitap notun yok", systemImage: "note.text",
                                                   description: Text("Kitabı açıp bir pasaj seç veya Okuma araçlarından not ekle. Kayıtların bu cihazda saklanır."))
                        }
                    }.listRowBackground(Color.clear)
                } else if !entries.isEmpty {
                    Section("\(entries.count) kayıt") {
                        ForEach(entries) { entry in noteRow(entry) }
                    }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle(bookID == nil ? "Kitap notlarım" : "Bu kitaptaki notlar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kitap, alıntı veya not ara")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.frame(minHeight: 44) } }
            .sheet(item: $editing) { entry in
                BookNoteEditor(bookID: entry.bookID, title: entry.title, page: entry.page, quote: entry.quote, existing: entry)
            }
            .sheet(item: $makingCard) { BookCardComposer(source: $0) }
            .sheet(item: $makingVideo) { note in
                TopicVideoCreateView(topic: note.learningTopic, source: "\(note.title) · PDF sayfası \(note.page)\n" + note.quote + "\n" + note.note, learningSource: .init(note: note))
            }
            .sheet(isPresented: $showCards) { CardBrowserView(filter: .books) }
            .fullScreenCover(item: $opening) { BookSourceView(bookID: $0.bookID, title: $0.title, page: $0.page) }
            .confirmationDialog("Bu kayıt silinsin mi?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { entry in
                Button("Kaydı sil", role: .destructive) {
                    do { try store.delete(id: entry.id); deleting = nil } catch { problem = error.localizedDescription }
                }
                Button("Vazgeç", role: .cancel) { deleting = nil }
            } message: { _ in Text("Oluşturduğun kartlar ve kitabın dosyası korunur.") }
        }
    }

    private func noteRow(_ entry: BookStudyNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Label("Sayfa \(entry.page)" + (entry.isBookmark ? " · İşaretli" : ""), systemImage: entry.isBookmark ? "bookmark.fill" : "doc.text")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Notu düzenle", systemImage: "pencil") { editing = entry }
                    Button("Kaydı sil", systemImage: "trash", role: .destructive) { deleting = entry }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }.accessibilityLabel("\(entry.title), sayfa \(entry.page), not seçenekleri")
            }
            if let concept = entry.concept, !concept.isEmpty { Text((entry.subject ?? "") + " · " + concept).font(.subheadline.bold()) }
            if !entry.quote.isEmpty { Text(entry.quote).font(.body).lineLimit(typeSize.isAccessibilitySize ? nil : 5) }
            if !entry.note.isEmpty { Text(entry.note).font(.body).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 4) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 8) {
                Button("Kaynağa git", systemImage: "book") {
                    if let onOpen { onOpen(entry) } else { opening = entry }
                }.frame(minHeight: 44)
                    .accessibilityIdentifier("book.note.source." + entry.id.uuidString)
                Button("Video oluştur") { makingVideo = entry }.disabled(entry.quote.isEmpty && entry.note.isEmpty)
                NavigationLink("Planla") { TutorPlanView(initialSubject: entry.subject, initialTopic: entry.learningTopic) }
                Button("Kart oluştur", systemImage: "rectangle.stack.badge.plus") { makingCard = entry }
                    .frame(minHeight: 44).disabled(entry.quote.isEmpty && entry.note.isEmpty)
                    .accessibilityHint("Bu pasajdan soru-cevap veya boşluk doldurma kartı hazırlar")
            }
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleOnly)
        }
        .padding(.vertical, 8)
        .buttonStyle(.borderless)
    }
}

private struct BookCardComposer: View {
    let source: BookStudyNote
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var mode = Mode.manual
    @State private var question = ""
    @State private var answer: String
    @State private var passage: String
    @State private var phrase = ""
    @State private var occurrence = 0
    @State private var problem: String?
    @State private var saved = false
    @State private var resultMessage: String?
    @State private var showCards = false
    @State private var discard = false

    private enum Mode: String, CaseIterable, Identifiable {
        case manual = "Soru-cevap", cloze = "Boşluk doldur"
        var id: String { rawValue }
    }
    init(source: BookStudyNote) {
        self.source = source
        let text = source.quote.isEmpty ? source.note : source.quote
        _answer = State(initialValue: text)
        _passage = State(initialValue: text)
    }
    private var draft: Result<BookCardDraft.Value, Error> {
        Result {
            if mode == .manual { return try BookCardDraft.manual(question: question, answer: answer) }
            return try BookCardDraft.cloze(quote: passage, phrase: phrase, occurrence: occurrence)
        }
    }
    private var valid: BookCardDraft.Value? { try? draft.get() }
    private var count: Int { BookCardDraft.occurrenceCount(in: passage, phrase: phrase) }
    private var dirty: Bool {
        let original = source.quote.isEmpty ? source.note : source.quote
        return !question.isEmpty || !phrase.isEmpty || answer != original || passage != original
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Kaynak") {
                    Text(source.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text("PDF sayfası \(source.page)").font(.subheadline).foregroundStyle(.secondary)
                }
                if saved {
                    Section {
                        Label(resultMessage ?? "Kart kaydedildi.", systemImage: "checkmark.circle.fill")
                        Text("Kartın normal tekrar listesinde hazır. Kaynak kitabına ve sayfasına geri dönebilirsin.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Kitap kartlarımı aç") { showCards = true }.frame(minHeight: 44)
                    }
                } else {
                    Section {
                        Picker("Kart biçimi", selection: $mode) {
                            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                        }.modifier(AccessiblePickerStyle())
                    }
                    if mode == .manual {
                        Section("Ön yüz · soru") {
                            TextField("Bu pasajla ilgili kendi sorunu yaz", text: $question, axis: .vertical).frame(minHeight: 44)
                                .accessibilityIdentifier("book.card.question")
                        }
                        Section("Arka yüz · cevap") {
                            TextEditor(text: $answer).font(.body).frame(minHeight: 120).accessibilityLabel("Kartın cevabı")
                        }
                    } else {
                        Section("Kaynak cümle") {
                            TextEditor(text: $passage).font(.body).frame(minHeight: 120).accessibilityLabel("Boşluk doldurulacak cümle")
                        }
                        Section {
                            TextField("Gizlenecek sözcük veya ifade", text: $phrase, axis: .vertical)
                                .autocorrectionDisabled().textInputAutocapitalization(.never).frame(minHeight: 44)
                                .accessibilityIdentifier("book.card.phrase")
                            if count > 1 {
                                Stepper("\(count) eşleşmeden \(occurrence + 1). eşleşmeyi gizle", value: $occurrence, in: 0...(count - 1))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } header: { Text("Gizlenecek ifade") } footer: {
                            Text("İfade metindeki büyük/küçük harf ve noktalama ile aynen eşleşir. Birden fazla eşleşmede yalnız seçtiğin gizlenir.")
                        }
                    }
                    Section("Kart önizlemesi") {
                        if let preview = valid {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Ön yüz").font(.caption).foregroundStyle(.secondary)
                                Text(preview.front).font(.body)
                                Divider()
                                Text("Arka yüz").font(.caption).foregroundStyle(.secondary)
                                Text(preview.back).font(.body)
                            }.fixedSize(horizontal: false, vertical: true)
                        } else if case .failure(let issue) = draft {
                            Text(issue.localizedDescription).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if let problem { Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(.primary) } }
                }
            }
            .scrollContentBackground(.hidden).background(Theme.canvas)
            .navigationTitle("Kitaptan kart").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Bitti" : "Vazgeç") {
                        if !saved && dirty { discard = true } else { dismiss() }
                    }.frame(minHeight: 44)
                }
                if !saved {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kaydet", action: save).frame(minHeight: 44).disabled(valid == nil)
                            .accessibilityLabel("Kartı kaydet")
                            .accessibilityIdentifier("book.card.save")
                    }
                }
            }
            .onChange(of: phrase) { occurrence = 0 }
            .onChange(of: passage) { occurrence = min(occurrence, max(0, count - 1)) }
            .interactiveDismissDisabled(!saved && dirty)
            .confirmationDialog("Kart taslağından vazgeçilsin mi?", isPresented: $discard, titleVisibility: .visible) {
                Button("Değişiklikleri bırak", role: .destructive) { dismiss() }
                Button("Düzenlemeye devam et", role: .cancel) {}
            }
            .sheet(isPresented: $showCards) { CardBrowserView(filter: .books) }
        }
    }

    private func save() {
        guard let valid else { return }
        do {
            let result = try BookCardWriter.save(valid, source: source, context: context)
            resultMessage = result.created ? "Kart kaydedildi." : "Bu kart zaten kayıtlı; ikinci kopya oluşturulmadı."
            saved = true
            problem = nil
        } catch { problem = "Kart kaydedilemedi. " + error.localizedDescription }
    }
}

/// Bir kart veya notun kaynak kitabı. Yalnız katalogdaki kararlı kimlikler dosyaya çevrilir.
struct BookSourceView: View {
    let bookID: String
    let title: String
    let page: Int
    @Environment(\.dismiss) private var dismiss
    private var library: MEBLibrary { .shared }
    private var file: MEBFile? {
        if let downloaded = library.downloaded.first(where: { $0.id == bookID }) { return downloaded }
        let catalog = MEBCatalog.shared
        return catalog.books.compactMap { MEBFile(book: $0, catalog: catalog) }.first { $0.id == bookID }
            ?? catalog.courses.compactMap { MEBFile(program: $0, catalog: catalog) }.first { $0.id == bookID }
    }

    var body: some View {
        Group {
            if let file, library.has(file) {
                MEBReader(title: file.title, url: library.location(file), key: file.id, start: max(1, page))
            } else {
                NavigationStack {
                    List {
                        Section("Kaynak") {
                            Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                            Text("PDF sayfası \(max(1, page))").font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let file {
                            Section {
                                if let progress = library.progress[file.id] {
                                    ProgressView(value: progress).accessibilityLabel("Kaynak kitap indiriliyor")
                                    Button("İndirmeyi durdur · %\(Int(progress * 100))", systemImage: "stop.circle") { library.cancel(file) }.frame(minHeight: 44)
                                } else {
                                    Text("Bu kitabın indirilen kopyası cihazda yok. Notun ve kartın saklanıyor; kitabı indirince kaynak sayfası açılır.")
                                    Button(library.errors[file.id] == nil ? "Kitabı indir" : "İndirmeyi yeniden dene", systemImage: "arrow.down.circle") { library.download(file) }
                                        .frame(minHeight: 44)
                                    if file.bytes > 0 { Text(MEBFile.size(file.bytes)).font(.caption).foregroundStyle(.secondary) }
                                }
                                if let error = library.errors[file.id] { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.primary) }
                            }
                        } else {
                            Section {
                                ContentUnavailableView("Kaynak kitap bulunamadı", systemImage: "book.closed",
                                                       description: Text("Bu kitabın kimliği mevcut katalogda yok. Not ve kart içeriği korunuyor; kitap adını kullanarak Kitaplık'ta arayabilirsin."))
                            }
                        }
                    }
                    .navigationTitle("Kaynak kitap").navigationBarTitleDisplayMode(.inline)
                    .scrollContentBackground(.hidden).background(Theme.canvas)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() }.frame(minHeight: 44) } }
                }
            }
        }
        .onAppear { library.reload() }
    }
}
