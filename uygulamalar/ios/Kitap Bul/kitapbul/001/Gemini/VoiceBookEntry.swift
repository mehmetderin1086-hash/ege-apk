import SwiftUI
import SwiftData

// MARK: - Model

/// Konuşarak söylenen kitap bilgisinin Gemini tarafından yapılandırılmış hâli.
/// ("Kürk Mantolu Madonna, Sabahattin Ali, YKY, iki adet, B dolabı üçüncü raf")
nonisolated struct SesliKitapKaydi: Codable, Sendable, Equatable {
    var isBook: Bool?
    var title: String?
    var author: String?
    var publisher: String?
    var isbn: String?
    var publicationYear: String?
    var edition: String?
    var volume: String?
    var pageCount: String?
    var category: String?
    var language: String?
    var summary: String?
    var quantity: Int?
    var cabinet: String?
    var shelf: String?
    var notes: String?
    /// Kullanıcının söylediği komut: "save", "cancel", "next", "undo" ya da nil.
    var command: String?
    /// Emin olunmayan alan adları.
    var uncertain: [String]?

    init() { }

    var hasBookContent: Bool {
        !(title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// JSON alan adını kullanıcıya gösterilen Türkçe etikete çevirir.
    static func alanAdi(_ key: String) -> String {
        switch key {
        case "title": "kitap adı"
        case "author": "yazar"
        case "publisher": "yayınevi"
        case "isbn": "ISBN"
        case "publicationYear": "yıl"
        case "category": "kategori"
        case "language": "dil"
        case "quantity": "adet"
        case "cabinet": "dolap"
        case "shelf": "raf"
        case "pageCount": "sayfa"
        case "summary": "özet"
        default: key
        }
    }
}

// MARK: - Bekleyen kayıt kuyruğu

/// Sesli kayıtta kaydedilmemiş önizlemeler. Baştaki öğe ekrandaki (düzenlenen) karttır;
/// yeni kitap söylenince eskisi silinmez, kuyruğun altına iner.
nonisolated struct BekleyenKayitKuyrugu: Equatable, Sendable {
    struct Oge: Equatable, Sendable, Identifiable {
        var kaydi: SesliKitapKaydi
        let operationID: UUID
        var id: UUID { operationID }
    }

    private(set) var ogeler: [Oge] = []

    var current: SesliKitapKaydi? { ogeler.first?.kaydi }
    var currentOperationID: UUID? { ogeler.first?.operationID }
    var isEmpty: Bool { ogeler.isEmpty }
    var count: Int { ogeler.count }
    /// Ekrandaki karttan başka bekleyen kayıt sayısı.
    var waitingCount: Int { max(0, ogeler.count - 1) }

    @discardableResult
    mutating func push(_ kaydi: SesliKitapKaydi, operationID: UUID = UUID()) -> UUID {
        ogeler.insert(Oge(kaydi: kaydi, operationID: operationID), at: 0)
        return operationID
    }

    mutating func replaceCurrent(_ kaydi: SesliKitapKaydi) {
        guard !ogeler.isEmpty else { return }
        ogeler[0].kaydi = kaydi
    }

    mutating func removeCurrent() {
        guard !ogeler.isEmpty else { return }
        ogeler.removeFirst()
    }

    mutating func removeAll() { ogeler.removeAll() }
}

// MARK: - Motor

/// Konuşma metnini kitap kaydına çevirir. Basit komutlar ("kaydet", "iptal") Gemini'ye
/// gitmeden yerelde tanınır; kitap tanımları Gemini ile yapılandırılır ve model kitabı
/// tanıyorsa yayınevi/yıl/kategori gibi eksikleri kendi bilgisinden tamamlar.
enum VoiceBookEngine {
    enum LocalCommand { case save, saveAll, cancel, undo, next }

    /// Modelin "save" komutuna verilecek karar: emin olunmayan alan varsa ya da ISBN/yazar
    /// gibi doğrulayıcı bilgi yoksa sessizce kaydetmek yerine önizleme gösterilir.
    enum SaveRoute: Equatable { case saveNow, preview }

    static func saveRoute(for kaydi: SesliKitapKaydi) -> SaveRoute {
        guard kaydi.hasBookContent else { return .preview }
        guard (kaydi.uncertain ?? []).isEmpty else { return .preview }
        let hasISBN = !(kaydi.isbn ?? "").isEmpty
        let hasAuthor = !(kaydi.author ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        return hasISBN || hasAuthor ? .saveNow : .preview
    }

    /// Komutların geçtiği yer. Sesli kayıtta "sil" iptaldir; sohbette silme isteği olabileceğinden
    /// ("Nutuk'u sil") iptal sayılmaz ve normal soru olarak asistana gider.
    enum CommandScope { case voice, chat }

    /// Ağa gitmeden tanınan tek kelimelik komutlar.
    static func localCommand(in transcript: String, scope: CommandScope = .voice) -> LocalCommand? {
        let words = CatalogMatcher.normalize(transcript)
            .split { !$0.isLetter }
            .map(String.init)
        guard !words.isEmpty, words.count <= 3 else { return nil }
        let joined = words.joined(separator: " ")
        let saveAllWords = ["hepsini kaydet", "tümünü kaydet", "hepsini ekle", "tümünü ekle", "hepsi tamam"]
        let saveWords = ["kaydet", "tamam", "evet", "onayla", "onaylıyorum", "ekle", "kaydet lütfen", "tamamdır"]
        let cancelWords = scope == .voice
            ? ["iptal", "vazgeç", "hayır", "sil", "yanlış", "iptal et"]
            : ["iptal", "vazgeç", "hayır", "yanlış", "iptal et"]
        let undoWords = scope == .voice ? ["geri al", "sonuncuyu sil", "son kaydı sil", "geri"] : ["geri al", "geri"]
        let nextWords = ["sıradaki", "sonraki", "devam", "yeni kitap"]
        if saveAllWords.contains(where: { CatalogMatcher.normalize($0) == joined }) { return .saveAll }
        if saveWords.contains(where: { CatalogMatcher.normalize($0) == joined }) { return .save }
        if cancelWords.contains(where: { CatalogMatcher.normalize($0) == joined }) { return .cancel }
        if undoWords.contains(where: { CatalogMatcher.normalize($0) == joined }) { return .undo }
        if nextWords.contains(where: { CatalogMatcher.normalize($0) == joined }) { return .next }
        return nil
    }

    static let systemPrompt = """
    Sen bir okul kütüphanecisinin sesli kayıt asistanısın. Kütüphaneci kitap bilgilerini KONUŞARAK \
    söyler; sana konuşma tanımadan çıkan metin gelir (harf hataları olabilir). Görevin metni tek bir \
    kitap kaydına dönüştürmek. YALNIZCA şu JSON'u döndür:
    {"isBook": true, "title": "", "author": "", "publisher": "", "isbn": "", "publicationYear": "", \
    "category": "", "language": "", "summary": "", "quantity": 1, "cabinet": "", "shelf": "", "notes": "", \
    "command": null, "uncertain": []}
    Kurallar:
    - Konuşma tanıma hatalarını düzelt ("kürk mantolu madona" → "Kürk Mantolu Madonna", "sabahatin ali" → "Sabahattin Ali").
    - Kitabı tanıyorsan söylenmemiş publisher / publicationYear / category / language / summary alanlarını \
    kendi bilginle doldur; emin olmadıklarını "uncertain" listesine yaz. Tanımıyorsan boş bırak, uydurma.
    - Sayıları çevir: "iki adet", "2 tane" → quantity 2 (söylenmediyse 1). "B dolabı" → cabinet "B"; \
    "üçüncü raf", "raf 3" → shelf "3". ISBN söylendiyse yalnızca rakam.
    - category şu listeden: \(KitapKategorileri.liste.joined(separator: ", ")).
    - Kullanıcı "kaydet/tamam/onayla" derse command "save", "iptal/vazgeç" derse "cancel", \
    "sıradaki/sonraki" derse "next", "geri al" derse "undo"; bu durumda diğer alanlar boş olabilir.
    - Metin bir kitap tanımı değilse (sohbet, alakasız) {"isBook": false} döndür.
    - Katalogda benzer bir kitap adı verilmişse (İPUCU) ve söylenenle aynı kitapsa adı katalogdaki gibi yaz.
    """

    static func parse(_ transcript: String, catalogHints: [String] = []) async throws -> SesliKitapKaydi {
        var prompt = "KONUŞMA METNİ: \(transcript)"
        if !catalogHints.isEmpty {
            prompt += "\nİPUCU — katalogdaki benzer adlar: " + catalogHints.prefix(8).joined(separator: " | ")
        }
        var kaydi = try await GeminiClient.shared.generateJSON(
            SesliKitapKaydi.self,
            prompt: prompt,
            system: systemPrompt,
            temperature: 0.2,
            maxOutputTokens: 1024,
            timeout: 30
        )
        kaydi = normalized(kaydi)
        return kaydi
    }

    static func normalized(_ kaydi: SesliKitapKaydi) -> SesliKitapKaydi {
        var result = kaydi
        func clean(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        result.title = clean(kaydi.title)
        result.author = clean(kaydi.author)
        result.publisher = clean(kaydi.publisher)
        result.category = clean(kaydi.category)
        result.language = clean(kaydi.language)
        result.summary = clean(kaydi.summary)
        result.cabinet = clean(kaydi.cabinet)?.uppercased()
        result.shelf = clean(kaydi.shelf)
        result.notes = clean(kaydi.notes)
        result.command = clean(kaydi.command)?.lowercased()
        if let year = clean(kaydi.publicationYear) {
            let digits = year.filter(\.isNumber)
            result.publicationYear = digits.count == 4 ? digits : nil
        } else {
            result.publicationYear = nil
        }
        if let isbn = clean(kaydi.isbn) {
            let normalizedISBN = ISBNFormatter.normalize(isbn)
            result.isbn = normalizedISBN.isEmpty ? nil : normalizedISBN
        } else {
            result.isbn = nil
        }
        if let quantity = kaydi.quantity { result.quantity = min(max(quantity, 1), 500) } else { result.quantity = 1 }
        if let category = result.category {
            result.category = KitapKategorileri.enYakin(category)
        }
        return result
    }

    /// Kayıttan `Book` değeri üretir.
    static func book(from kaydi: SesliKitapKaydi, id: UUID = UUID()) -> Book {
        Book(
            id: id,
            title: kaydi.title ?? "",
            author: kaydi.author ?? "",
            publisher: kaydi.publisher,
            isbn: kaydi.isbn,
            publicationYear: kaydi.publicationYear,
            edition: kaydi.edition,
            pageCount: kaydi.pageCount,
            notes: [kaydi.summary, kaydi.notes].compactMap { $0 }.joined(separator: "\n"),
            category: kaydi.category,
            language: kaydi.language,
            readingStatus: "Okunacak",
            quantity: kaydi.quantity ?? 1,
            shelf: kaydi.shelf,
            cabinet: kaydi.cabinet,
            isTextbook: kaydi.category == "Ders Kitabı" || kaydi.category == "Yardımcı Kaynak",
            volume: kaydi.volume.flatMap(Int.init)
        )
    }
}

// MARK: - Kaydedici

/// Sesli/asistan kaynaklı kayıtları kataloğa yazar: ISBN ya da ad+yazar benzerliğiyle
/// mükerrer kontrolü yapar (aynı kitapsa adet artırır), kaydettikten sonra arka planda
/// resmî kapak ve eksik ISBN'i ağdan tamamlar.
enum VoiceBookSaver {
    enum Outcome {
        case inserted(CatalogBook)
        case merged(CatalogBook, added: Int)

        var book: CatalogBook {
            switch self {
            case .inserted(let book), .merged(let book, _): book
            }
        }

        var message: String {
            switch self {
            case .inserted(let book):
                "“\(book.title)” kaydedildi" + ((book.quantity ?? 1) > 1 ? " (\(book.quantity ?? 1) adet)." : ".")
            case .merged(let book, let added):
                added == 0 ? "“\(book.title)” daha önce kaydedildi; tekrar eklenmedi."
                    : "“\(book.title)” zaten katalogdaydı; \(added) adet eklendi, toplam \(book.quantity ?? 1)."
            }
        }
    }

    @discardableResult
    static func save(_ kaydi: SesliKitapKaydi, in context: ModelContext, catalog: [CatalogBook],
                     operationID: UUID? = nil,
                     source: String = "voice",
                     fieldMetadata: String? = nil,
                     coverData: Data? = nil,
                     confidence: Double? = nil,
                     decision: CatalogSaveDecision = .automatic,
                     persist: (() throws -> Void)? = nil) throws -> Outcome {
        var book = VoiceBookEngine.book(from: kaydi, id: operationID ?? UUID())
        book.fieldMetadata = fieldMetadata
        book.coverData = coverData
        if let confidence, confidence.isFinite {
            var metadata = BookFieldMetadata.decode(fieldMetadata)
            for field in BookFieldMetadata.fields where metadata[field] == nil && !BookFieldMetadata.value(field, in: book).isEmpty {
                metadata[field] = BookFieldEvidence(source: source, confidence: min(1, max(0, confidence)))
            }
            book.fieldMetadata = BookFieldMetadata.encode(metadata)
        }
        let saved = try CatalogSaveEngine.save(book, context: context, catalog: catalog, operationID: operationID, source: source, decision: decision, persist: persist)
        let id: UUID
        let added: Int?
        switch saved {
        case .inserted(let newID): id = newID; added = nil
        case .merged(let existingID, let delta): id = existingID; added = delta
        case .updated: id = book.id; added = nil
        case .failed(let error): throw CatalogSaveEngine.SaveError(message: error)
        }
        guard let model = try context.fetch(FetchDescriptor<CatalogBook>(predicate: #Predicate { $0.id == id })).first else {
            throw CatalogSaveEngine.SaveError(message: "Kaydedilen kitap tekrar okunamadı.")
        }
        if let added { return .merged(model, added: added) }
        EnrichmentQueue.enqueue(id)
        return .inserted(model)
    }

    /// Kayıttan sonra arka planda: ISBN varsa resmî kapak, yoksa ad+yazarla arama (kapak + ISBN + eksikler).
    static func enrichInBackground(_ book: CatalogBook, context: ModelContext) {
        let title = book.title
        let author = book.author
        let publisher = book.publisher ?? ""
        let isbn = ISBNFormatter.normalize(book.isbn ?? "")
        Task { @MainActor in
            guard !book.isDeleted, book.modelContext != nil, YetkiDurumu.shared.yonetici else { return }
            if !isbn.isEmpty {
                if book.coverData == nil, !BookFieldMetadata.isLocked("coverData", on: book),
                   let cover = await BookMetadataService.officialCover(isbn: isbn, title: title, author: author, publisher: publisher) {
                    guard !book.isDeleted, book.modelContext != nil, YetkiDurumu.shared.yonetici else { return }
                    var updated = book.book
                    updated.coverData = cover
                    _ = try? CatalogSaveEngine.save(updated, context: context, catalog: [book], source: "api")
                }
                return
            }
            guard let meta = await BookMetadataService.search(title: title, author: author, publisher: publisher) else { return }
            guard !book.isDeleted, book.modelContext != nil, YetkiDurumu.shared.yonetici else { return }
            var updated = book.book
            if (book.isbn ?? "").isEmpty, !meta.isbn.isEmpty, !BookFieldMetadata.isLocked("isbn", on: book) { updated.isbn = meta.isbn }
            if book.coverData == nil, let cover = meta.coverData, !BookFieldMetadata.isLocked("coverData", on: book) { updated.coverData = cover }
            if (book.publisher ?? "").isEmpty, !meta.publisher.isEmpty, !BookFieldMetadata.isLocked("publisher", on: book) { updated.publisher = meta.publisher }
            if (book.publicationYear ?? "").isEmpty, !meta.publicationYear.isEmpty, !BookFieldMetadata.isLocked("publicationYear", on: book) { updated.publicationYear = meta.publicationYear }
            if (book.pageCount ?? "").isEmpty, !meta.pageCount.isEmpty, !BookFieldMetadata.isLocked("pageCount", on: book) { updated.pageCount = meta.pageCount }
            _ = try? CatalogSaveEngine.save(updated, context: context, catalog: [book], source: "api")
        }
    }

}

// MARK: - Sayfa

/// Sesle kitap kaydetme: mikrofona konuş → Gemini alanlara ayırır → kart hâlinde göster →
/// "Kaydet" de ya da düğmeye bas → kaydedilir, sesli onay gelir, sıradaki kitap için
/// otomatik dinlemeye geçilir. Raf başında elleri meşgul kütüphaneci için tasarlandı.
struct VoiceBookEntryPage: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.addedAt, order: .reverse) private var books: [CatalogBook]

    @AppStorage("voiceEntryContinuous") private var continuous = true
    @AppStorage(GeminiSettings.voiceRepliesKey) private var voiceReplies = true
    @AppStorage(GeminiSettings.briefConfirmKey) private var briefConfirm = false

    @State private var speech = SpeechInput()
    @State private var voice = SpeechOutput()
    @State private var isParsing = false
    @State private var kuyruk = BekleyenKayitKuyrugu()
    @State private var review: CatalogSavePreview?
    @State private var persistTask: Task<Void, Never>?
    @State private var lastTranscript = ""
    @State private var message: (text: String, isError: Bool)?
    private struct OturumKaydi: Identifiable {
        let id = UUID()
        let bookID: UUID
        let text: String
        let merged: Bool
        let addedCopies: Int
        let operationID: UUID
    }
    @State private var sessionLog: [OturumKaydi] = []
    /// Son giriş mikrofondan mı geldi? Yazılı girişten sonra otomatik dinleme başlatılmaz.
    @State private var lastInputWasVoice = false
    @FocusState private var manualFocused: Bool
    @State private var sessionCount = 0
    @State private var manualText = ""
    @State private var persistentSession = ScanSession(kind: .voice, title: "Sesle kitap kaydı")
    @State private var taskGate = VoiceEntryTaskGate()
    @State private var catalogLease: ActiveCatalogLease?
    /// Art arda kaç kez sessizlikle bittiği; sınırda sürekli mod duraklar.
    @State private var idleRestarts = 0
    private let reachability = GeminiReachability.shared

    @ScaledMetric(relativeTo: .largeTitle) private var micSize: CGFloat = 72

    /// Ekrandaki (kuyruğun başındaki) önizleme.
    private var pending: SesliKitapKaydi? {
        get { kuyruk.current }
        nonmutating set {
            if let newValue { kuyruk.replaceCurrent(newValue) } else { kuyruk.removeCurrent() }
        }
    }

    private var pendingOperationID: UUID { kuyruk.currentOperationID ?? UUID() }

    private struct ReviewAnahtari: Equatable {
        var operationID: UUID?
        var title: String?
        var isbn: String?
        var author: String?
    }

    private var reviewKey: ReviewAnahtari {
        ReviewAnahtari(operationID: kuyruk.currentOperationID, title: kuyruk.current?.title,
                       isbn: kuyruk.current?.isbn, author: kuyruk.current?.author)
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 18) {
                micArea
                if let message {
                    Label(message.text, systemImage: message.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(message.isError ? KitapTema.vurgu : KitapTema.basari)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                }
                if let pending {
                    pendingCard(pending)
                        .id("onizleme")
                    if kuyruk.waitingCount > 0 {
                        waitingBar
                    }
                }
                manualEntry
                if !sessionLog.isEmpty {
                    sessionList
                }
            }
            .padding(.vertical)
        }
        // Alt sekme çubuğu son düğmeyi örtmesin; önizleme gelince ona kaydırılır
        .contentMargins(.bottom, 32, for: .scrollContent)
        .onChange(of: pending == nil) { _, isNil in
            if !isNil { withAnimation { proxy.scrollTo("onizleme", anchor: .top) } }
        }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sesle Kaydet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $continuous) {
                    Label("Sürekli mod", systemImage: continuous ? "repeat.circle.fill" : "repeat.circle")
                }
                .toggleStyle(.button)
                .tint(KitapTema.amazon)
                .accessibilityLabel(continuous ? "Sürekli dinleme açık" : "Sürekli dinleme kapalı")
                .accessibilityHint("Her kayıttan sonra sıradaki kitap için kendiliğinden dinler")
            }
        }
        .onAppear {
            taskGate.activate()
            reachability.startMonitoring()
            Task { await reachability.probeIfStale() }
            guard acceptsActiveCatalogResult() else { return }
            speech.onIdleTimeout = { handleIdleTimeout() }
            // Çağrı/Siri kesintisinde dinleme durur; kesinti bitince sürekli modda kaldığı yerden devam eder
            SesOturumu.shared.onInterruptionBegan = {
                message = ("Dinleme bir kesinti nedeniyle durdu.", false)
            }
            SesOturumu.shared.onInterruptionResume = {
                guard taskGate.isActive, continuous else { return }
                listenAgainIfContinuous(delay: 1.0)
            }
            speech.onFinalTranscript = { text in
                guard taskGate.isActive, acceptsActiveCatalogResult() else { return }
                lastInputWasVoice = true
                Task { await handle(transcript: text) }
            }
        }
        .onDisappear {
            taskGate.deactivate()
            speech.onFinalTranscript = nil
            speech.onIdleTimeout = nil
            SesOturumu.shared.onInterruptionBegan = nil
            SesOturumu.shared.onInterruptionResume = nil
            speech.stop()
            voice.stop()
            isParsing = false
            persistTask?.cancel()
            persistVoiceSession()
        }
        .onChange(of: kuyruk) { _, _ in schedulePersist() }
        .onChange(of: reviewKey) { _, _ in refreshReview() }
    }

    // MARK: Mikrofon alanı

    private var micArea: some View {
        VStack(spacing: 12) {
            Button {
                Task { await toggleListening() }
            } label: {
                ZStack {
                    Circle()
                        .fill(speech.isListening ? Color.red.gradient : KitapTema.amazon.gradient)
                        .frame(width: micSize * 1.6, height: micSize * 1.6)
                        .shadow(color: (speech.isListening ? Color.red : KitapTema.amazon).opacity(0.35), radius: 14, y: 6)
                    Image(systemName: speech.isListening ? "waveform" : (speech.isStarting ? "ellipsis" : "mic.fill"))
                        .font(.system(size: micSize * 0.6, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.variableColor.iterative, isActive: speech.isListening || speech.isStarting)
                }
            }
            .buttonStyle(.kitapSade)
            .disabled(isParsing || speech.isStarting)
            .accessibilityLabel(speech.isListening ? "Dinlemeyi bitir" : (speech.isStarting ? "Mikrofon hazırlanıyor" : "Kitap söylemek için dokun"))
            .accessibilityHint("Kitap adı, yazar, yayınevi, adet ve raf söyleyin")

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if reachability.isBlockedOrOffline {
                Label(reachability.durum.etiket + ": kitap ayrıştırma çalışmayabilir", systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(KitapTema.vurgu)
                    .padding(.horizontal)
            }

            if speech.isListening, !speech.transcript.isEmpty {
                CanliAlanlar(kaydi: VoiceBookEngine.quickParse(speech.transcript))
            }
            if !lastTranscript.isEmpty {
                Text("“\(lastTranscript)”")
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                    .padding(.horizontal)
                    .accessibilityLabel("Anlaşılan: \(lastTranscript)")
            }
            if let error = speech.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            if isParsing {
                ProgressView("Gemini kaydı düzenliyor…")
            }
        }
    }

    private var statusText: String {
        if speech.isListening {
            return speech.transcript.isEmpty ? "Dinliyorum… Örn: “Kürk Mantolu Madonna, Sabahattin Ali, YKY, iki adet, B dolabı raf 3”" : speech.transcript
        }
        if pending != nil {
            return "Kontrol edin; “Kaydet” deyin ya da düğmeye basın. Düzeltmek için söyleyin: “yazarı … yap”, “adet üç”, “rafı dört”."
        }
        return sessionCount == 0
            ? "Dokunun ve kitabı söyleyin. Ad ve yazar yeterli; yayınevi, adet ve rafı da söyleyebilirsiniz."
            : "Bu oturumda \(sessionCount) kitap kaydedildi. Sıradaki kitap için dokunun."
    }

    // MARK: Bekleyen kart

    private func pendingCard(_ kaydi: SesliKitapKaydi) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Kayıt önizleme", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(KitapTema.amazon)
                Spacer()
                if let uncertain = kaydi.uncertain, !uncertain.isEmpty {
                    Label("Kontrol: \(uncertain.map(SesliKitapKaydi.alanAdi).joined(separator: ", "))", systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(KitapTema.vurgu)
                }
            }
            field("Kitap Adı", \.title, key: "title", kaydi: kaydi)
            field("Yazar", \.author, key: "author", kaydi: kaydi)
            field("Yayınevi", \.publisher, key: "publisher", kaydi: kaydi)
            HStack(spacing: 10) {
                field("Yıl", \.publicationYear, key: "publicationYear", kaydi: kaydi)
                field("ISBN", \.isbn, key: "isbn", kaydi: kaydi)
            }
            HStack(spacing: 10) {
                field("Dolap", \.cabinet, key: "cabinet", kaydi: kaydi)
                field("Raf", \.shelf, key: "shelf", kaydi: kaydi)
                Stepper("Adet: \(pending?.quantity ?? 1)", value: Binding(
                    get: { pending?.quantity ?? 1 },
                    set: { pending?.quantity = $0 }
                ), in: 1...500)
                .font(.subheadline)
            }
            Picker("Kategori", selection: Binding(
                get: { pending?.category ?? "Diğer" },
                set: { pending?.category = $0 }
            )) {
                ForEach(KitapKategorileri.liste, id: \.self) { Text($0).tag($0) }
            }
            if let summary = kaydi.summary, !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if let review, !review.candidates.isEmpty {
                DisclosureGroup("Baskıyı ve eklenecek nüshayı karşılaştır") {
                    CatalogEditionReviewPanel(preview: review, decision: Binding(
                        get: { persistentSession.saveDecisions?[pendingOperationID] ?? .automatic },
                        set: { decision in
                            persistentSession.saveDecisions = persistentSession.saveDecisions ?? [:]
                            persistentSession.saveDecisions?[pendingOperationID] = decision
                            persistVoiceSession()
                        }))
                }
            }
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    discardPending(spoken: true)
                } label: {
                    Label("İptal", systemImage: "xmark")
                }
                .buttonStyle(.kitapTonlu(.red))
                Button {
                    savePending()
                } label: {
                    Label("Kaydet", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.kitapDolu(KitapTema.basari))
                .disabled(!(pending?.hasBookContent ?? false))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var waitingBar: some View {
        HStack(spacing: 10) {
            Label("Sırada \(kuyruk.waitingCount) kitap daha var", systemImage: "tray.full")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                saveAllPending()
            } label: {
                Label("Hepsini kaydet (\(kuyruk.count))", systemImage: "checkmark.circle")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.kitapTonlu(KitapTema.basari))
            .disabled(isParsing)
        }
        .padding(.horizontal)
    }

    private func field(_ title: String, _ keyPath: WritableKeyPath<SesliKitapKaydi, String?>, key: String, kaydi: SesliKitapKaydi) -> some View {
        HStack(spacing: 4) {
            TextField(title, text: Binding(
                get: { pending?[keyPath: keyPath] ?? "" },
                set: { pending?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(title)
            if (kaydi.uncertain ?? []).contains(key) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(KitapTema.vurgu)
                    .accessibilityLabel("Gemini bu alandan emin değil")
            }
        }
    }

    // MARK: Elle giriş (mikrofon kullanılamıyorsa)

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ya da yazın")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                TextField("Kitap adı, yazar, yayınevi, adet, raf…", text: $manualText, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .focused($manualFocused)
                    .submitLabel(.go)
                    .onSubmit { submitManual() }
                Button {
                    submitManual()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.kitapSade)
                .disabled(manualText.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
                .accessibilityLabel("Metni kayda çevir")
            }
        }
        .padding(.horizontal)
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Bu oturumda kaydedilenler (\(sessionLog.count))", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Spacer()
                Button {
                    undoLast()
                } label: {
                    Label("Sonuncuyu Geri Al", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.kitapTonlu(.red))
            }
            ForEach(sessionLog) { entry in
                Label(entry.text, systemImage: "checkmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: Akış

    /// Yazılı giriş: klavye kapanır, otomatik dinleme tetiklenmez.
    private func submitManual() {
        let text = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        manualText = ""
        manualFocused = false
        lastInputWasVoice = false
        Task { await handle(transcript: text) }
    }

    private func toggleListening() async {
        taskGate.cancelResume()
        guard taskGate.isActive, acceptsActiveCatalogResult() else { return }
        if speech.isListening {
            let text = speech.transcript
            speech.stop()
            if !text.isEmpty { await handle(transcript: text) }
            return
        }
        voice.stop()
        let started = await taskGate.authorizeAndStart(authorization: { await speech.requestAuthorization() }, start: {
            guard acceptsActiveCatalogResult() else { return }
            lastInputWasVoice = true
            speech.start()
        })
        if !started, taskGate.isActive, acceptsActiveCatalogResult() {
            message = (speech.errorMessage ?? "Mikrofon izni gerekli.", true)
        }
    }

    private func handle(transcript: String) async {
        guard let lifetime = taskGate.currentToken, acceptsActiveCatalogResult() else { return }
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lastTranscript = text
        message = nil
        idleRestarts = 0

        // Kısa komutlar ağa gitmez
        if let command = VoiceBookEngine.localCommand(in: text) {
            switch command {
            case .save:
                if pending != nil { savePending() } else { speak("Kaydedilecek bir kitap yok. Önce kitabı söyleyin.") }
            case .saveAll:
                if pending != nil { saveAllPending() } else { speak("Kaydedilecek bir kitap yok. Önce kitabı söyleyin.") }
            case .cancel: discardPending(spoken: true)
            case .undo: undoLast()
            case .next: listenAgainIfContinuous()
            }
            return
        }

        isParsing = true
        defer { if taskGate.accepts(lifetime) { isParsing = false } }

        // Önizleme açıkken kısa cümle = düzeltme ("yazarı Orhan Pamuk yap", "adet üç", "rafı 4")
        if let current = pending, VoiceBookEngine.looksLikeEdit(text) {
            do {
                let updated = try await VoiceBookEngine.applyEdit(current, instruction: text)
                guard taskGate.accepts(lifetime), acceptsActiveCatalogResult() else { return }
                if updated.command != "new" {
                    pending = updated
                    speak("Düzeltildi.")
                    AccessibilityNotification.Announcement("Kayıt düzeltildi").post()
                    listenAgainIfContinuous()
                    return
                }
            } catch {
                guard taskGate.accepts(lifetime), acceptsActiveCatalogResult() else { return }
                message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
                return
            }
        }

        do {
            let hints = AssistantContext.matchingBooks(for: text, in: books, limit: 8).map(\.title)
            let kaydi = try await VoiceBookEngine.parse(text, catalogHints: hints)
            guard taskGate.accepts(lifetime), acceptsActiveCatalogResult() else { return }
            switch kaydi.command {
            case "save":
                if kaydi.hasBookContent {
                    // Şüpheli alan varsa ya da ISBN/yazar yoksa körü körüne kaydetme: önizlemeye düş
                    kuyruk.push(kaydi)
                    if VoiceBookEngine.saveRoute(for: kaydi) == .preview {
                        announcePreview(kaydi)
                        return
                    }
                }
                if pending != nil { savePending() }
                return
            case "cancel":
                discardPending(spoken: true)
                return
            case "undo":
                undoLast()
                return
            default:
                break
            }
            guard kaydi.isBook != false, kaydi.hasBookContent else {
                message = ("Bunu bir kitap tanımı olarak anlayamadım. Kitap adı ve yazarı söyleyin.", true)
                speak("Anlayamadım. Kitap adı ve yazarı söyleyin.")
                listenAgainIfContinuous()
                return
            }
            kuyruk.push(kaydi)
            announcePreview(kaydi)
        } catch {
            guard taskGate.accepts(lifetime), acceptsActiveCatalogResult() else { return }
            message = ((error as? GeminiError)?.errorDescription ?? error.localizedDescription, true)
        }
    }

    private func announcePreview(_ kaydi: SesliKitapKaydi) {
        let summary = [kaydi.title, kaydi.author].compactMap { $0 }.joined(separator: ", ")
        let qty = (kaydi.quantity ?? 1) > 1 ? ", \(kaydi.quantity ?? 1) adet" : ""
        let waiting = kuyruk.waitingCount > 0 ? " Sırada \(kuyruk.waitingCount) kitap daha var." : ""
        if briefConfirm && (kaydi.uncertain ?? []).isEmpty {
            speak("\(summary). Kaydedeyim mi?\(waiting)")
        } else {
            speak("\(summary)\(qty). Kaydedeyim mi?\(waiting)")
        }
        AccessibilityNotification.Announcement("Kayıt önizleme hazır: \(summary)").post()
        listenAgainIfContinuous()
    }

    /// Kuyruktaki bütün önizlemeleri sırayla kaydeder; hata ya da içeriksiz kayıtta durur.
    private func saveAllPending() {
        guard taskGate.isActive, acceptsActiveCatalogResult() else { return }
        var saved = 0
        while let kaydi = pending {
            guard kaydi.hasBookContent else { kuyruk.removeCurrent(); continue }
            guard savePending(announce: false) else { break }
            saved += 1
        }
        guard saved > 0 else { return }
        let text = "\(saved) kitap kaydedildi."
        message = (text, false)
        speak(text)
        AccessibilityNotification.Announcement(text).post()
        listenAgainIfContinuous()
    }

    @discardableResult
    private func savePending(announce: Bool = true) -> Bool {
        guard taskGate.isActive, acceptsActiveCatalogResult() else { return false }
        guard let kaydi = pending, kaydi.hasBookContent else { return false }
        persistTask?.cancel()
        do {
            try writeVoiceSession()
            let outcome = try VoiceBookSaver.save(kaydi, in: modelContext, catalog: books, operationID: pendingOperationID,
                decision: persistentSession.saveDecisions?[pendingOperationID] ?? .automatic)
            VoiceBookSaver.enrichInBackground(outcome.book, context: modelContext)
            sessionCount += 1
            let merged = if case .merged = outcome { true } else { false }
            let added: Int
            if case .merged(_, let delta) = outcome { added = delta } else { added = 0 }
            sessionLog.insert(OturumKaydi(bookID: outcome.book.id, text: outcome.message, merged: merged, addedCopies: added, operationID: pendingOperationID), at: 0)
            if merged { persistentSession.mergedCopies[outcome.book.id, default: 0] += added }
            else { persistentSession.insertedIDs.append(outcome.book.id) }
            persistentSession.savedOperationIDs = (persistentSession.savedOperationIDs ?? []) + [pendingOperationID]
            message = (outcome.message, false)
            let hadUncertain = !(kaydi.uncertain ?? []).isEmpty
            pending = nil
            persistVoiceSession()
            lastTranscript = ""
            guard announce else { return true }
            // Kısa onay modu: şüpheli alan yoksa uzun cümle yerine titreşim + "Kaydedildi"
            if briefConfirm && !hadUncertain && max(1, kaydi.quantity ?? 1) <= 1 && added <= 1 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                speak("Kaydedildi.")
            } else {
                speak(outcome.message + (continuous ? " Sıradaki kitap." : ""))
            }
            AccessibilityNotification.Announcement(outcome.message).post()
            listenAgainIfContinuous()
            return true
        } catch {
            message = ("Kaydedilemedi: \(error.localizedDescription)", true)
            return false
        }
    }

    private func discardPending(spoken: Bool) {
        pending = nil
        lastTranscript = ""
        if spoken { speak("İptal edildi.") }
        listenAgainIfContinuous()
    }

    private func undoLast() {
        guard taskGate.isActive, acceptsActiveCatalogResult() else { return }
        guard let last = sessionLog.first,
              let book = books.first(where: { $0.id == last.bookID }) else {
            speak("Geri alınacak kayıt yok.")
            return
        }
        do {
            try CatalogSaveEngine.undo(insertedIDs: last.merged ? [] : [book.id],
                mergedCopies: last.merged ? [book.id: last.addedCopies] : [:], catalog: books, context: modelContext, operationIDs: [last.operationID])
        } catch {
            message = ("Geri alınamadı: \(error.localizedDescription)", true)
            return
        }
        sessionLog.removeFirst()
        if last.merged {
            persistentSession.mergedCopies[last.bookID] = max(0, (persistentSession.mergedCopies[last.bookID] ?? 0) - last.addedCopies)
        } else { persistentSession.insertedIDs.removeAll { $0 == last.bookID } }
        persistentSession.savedOperationIDs?.removeAll { $0 == last.operationID }
        persistVoiceSession()
        sessionCount = max(0, sessionCount - 1)
        message = ("Son kayıt geri alındı.", false)
        speak("Geri alındı.")
    }

    private func writeVoiceSession() throws {
        if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
        try catalogLease?.requireCurrent(context: modelContext)
        persistentSession.pendingBooks = kuyruk.ogeler.map { VoiceBookEngine.book(from: $0.kaydi, id: $0.operationID) }
        try ScanSessionStore.save(persistentSession)
    }

    /// Tuş başına disk yazımını önler: son değişiklikten 0,5 sn sonra bir kez yazar.
    private func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistVoiceSession()
        }
    }

    private func refreshReview() {
        guard let kaydi = pending else { review = nil; return }
        review = CatalogSaveEngine.preview(VoiceBookEngine.book(from: kaydi, id: pendingOperationID), catalog: books)
    }

    private func persistVoiceSession() {
        do { try writeVoiceSession() }
        catch { message = ("Sesli oturum saklanamadı: \(error.localizedDescription)", true) }
    }

    private func speak(_ text: String) {
        guard taskGate.isActive, acceptsActiveCatalogResult(), voiceReplies, !UIAccessibility.isVoiceOverRunning else { return }
        voice.speak(text)
    }

    /// Sürekli modda, sesli onay BİTTİKTEN sonra yeniden dinler. Hoparlör çalarken mikrofonu
    /// açmak hem yanıtı keser hem kendi sesimizi metne çevirirdi; bu yüzden okuma bitişi beklenir.
    private func listenAgainIfContinuous(delay: Double = 0.6) {
        // Yalnız izin reddi engeller; sessizlik/tanıma kesintisi gibi geçici hatalar engellemez
        guard taskGate.isActive, acceptsActiveCatalogResult(), continuous, lastInputWasVoice, !speech.permissionBlocked else { return }
        taskGate.scheduleResume(wait: {
            var waited = 0.0
            while (voice.isSpeaking || voice.isPreparing) && waited < 12 {
                try await Task.sleep(for: .milliseconds(250))
                waited += 0.25
            }
            try await Task.sleep(for: .seconds(delay))
        }, shouldStart: {
            // Ses hazırlanırken ya da çalarken mikrofon açılmaz (kendi sesimizi dinlemeyelim)
            continuous && !speech.isListening && !speech.isStarting && !isParsing
                && !voice.isPreparing && !voice.isSpeaking
                && !speech.permissionBlocked && acceptsActiveCatalogResult()
        }, start: {
            voice.stop()
            speech.start()
        })
    }

    /// Sessizlikle biten dinleme: sürekli modda "Dinlemeye devam ediyorum" duyurusuyla yeniden başlar,
    /// üst üste 5 sessizlikten sonra duraklar. Sürekli mod kapalıysa kısa bir uyarı gösterilir.
    private func handleIdleTimeout() {
        guard taskGate.isActive, acceptsActiveCatalogResult() else { return }
        guard continuous, lastInputWasVoice else {
            message = ("Ses algılanmadı; mikrofona biraz daha yakın konuşup yeniden deneyin.", true)
            return
        }
        idleRestarts += 1
        if idleRestarts > 5 {
            idleRestarts = 0
            message = ("Ses algılanmadığı için dinleme durakladı. Devam etmek için mikrofona dokunun.", false)
            return
        }
        if idleRestarts == 1 {
            AccessibilityNotification.Announcement("Dinlemeye devam ediyorum").post()
        }
        listenAgainIfContinuous(delay: 0.3)
    }

    private func acceptsActiveCatalogResult() -> Bool {
        do {
            if catalogLease == nil { catalogLease = try ActiveCatalogLease.captureCurrent(context: modelContext) }
            try catalogLease?.requireCurrent(context: modelContext)
            return true
        } catch {
            taskGate.cancelResume()
            message = ("Etkin katalog değişti veya işlem iptal edildi. Sesli kayıt korunuyor; yeni katalogda yeniden başlayın. \(error.localizedDescription)", true)
            return false
        }
    }
}

/// Konuşma sürerken yerel ön ayrıştırıcının anlık çıkardığı alanlar (Gemini sonra kesinleştirir).
private struct CanliAlanlar: View {
    let kaydi: SesliKitapKaydi

    var body: some View {
        let items: [(String, String?)] = [
            ("Ad", kaydi.title), ("Yazar", kaydi.author), ("Yayınevi", kaydi.publisher),
            ("Adet", kaydi.quantity.map(String.init)), ("Dolap", kaydi.cabinet), ("Raf", kaydi.shelf)
        ]
        let filled = items.compactMap { label, value in value.map { (label, $0) } }
        if !filled.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filled, id: \.0) { label, value in
                        Text("\(label): \(value)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(KitapTema.amazon.opacity(0.14), in: .capsule)
                            .foregroundStyle(KitapTema.amazon)
                    }
                }
                .padding(.horizontal)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Anlık alanlar: " + filled.map { "\($0.0) \($0.1)" }.joined(separator: ", "))
        }
    }
}
