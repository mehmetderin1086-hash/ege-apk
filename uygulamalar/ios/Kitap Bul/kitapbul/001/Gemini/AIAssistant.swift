import SwiftUI
import SwiftData
import Speech
import AVFoundation

// MARK: - Sohbet modeli

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    var id = UUID()
    var role: Role
    var text: String
    /// Yanıtta geçen ve katalogda bulunan kitaplar (dokunulabilir kartlar).
    var bookIDs: [UUID] = []
    var followUps: [String] = []
    var isError = false
    /// Asistanın "kitap ekle" niyetinden çıkardığı, onay bekleyen kayıt.
    var proposedBook: SesliKitapKaydi?
    /// Asistanın "ödünç ver / iade al" niyetinden çıkardığı, onay bekleyen işlem.
    var proposedLoan: LoanProposal?
    /// "Düş / taşı / durum değiştir" gibi onay bekleyen düzenleme.
    var proposedEdit: EditProposal?
    /// Henüz kitap/okur kimliği seçilmemiş işlem de açık bir taslak olarak saklanır.
    var proposedTargetChoice: AssistantTargetChoice?
    /// Tek seferde dikte edilen birden çok kitap.
    var proposedBooks: [SesliKitapKaydi] = []
    var proposedOperationIDs: [UUID] = []
    /// Sayısal yanıtlarda çubuk grafik.
    var chart: AssistantChart?
    /// Öneri kaydedildiyse/iptal edildiyse kart kapanır.
    var proposalResolved = false
    var date = Date()
    /// Eski kartlar sesli "kaydet" ile uygulanmaz; kullanıcı kartı yeniden incelemelidir.
    var proposalNeedsReview = false
    /// Cihazda üretilen (Gemini'siz) yanıt: "Çevrimdışı yanıt" rozeti gösterilir. Kalıcı sohbete yazılmaz.
    var isOffline = false
    var hasPendingProposal: Bool {
        !proposalResolved && (proposedBook != nil || proposedLoan != nil || proposedEdit != nil || proposedTargetChoice != nil || !proposedBooks.isEmpty)
    }
}

/// Onay bekleyen ödünç/iade işlemi (kişi adı cihazda gerçek adına çevrilmiş).
nonisolated struct LoanProposal: Codable, Sendable, Equatable {
    var kind: String          // "lend" | "return"
    var bookID: UUID
    var bookTitle: String
    var person: String
    var className: String?
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    var copyID: UUID? = nil
    var loanID: UUID? = nil
}

/// Gemini'den beklenen yapılandırılmış yanıt.
nonisolated struct AssistantReply: Codable, Sendable {
    struct Action: Codable, Sendable {
        var type: String
        var book: SesliKitapKaydi?
        /// "lend" / "return" için
        var loan: LoanIntent?
        /// "editBook" için
        var edit: BookEditIntent?
        /// "addBooks" için (birden çok kitap)
        var books: [SesliKitapKaydi]?
    }

    var answer: String
    var bookTitles: [String]?
    var followUps: [String]?
    var chart: AssistantChart?
    /// "addBook": kullanıcı kitap eklemek istedi; `book` alanları doldurulmuş kayıt taslağı.
    var action: Action?
}

// MARK: - Bağlam üretici

/// Soruyla ilgili katalog bilgisini Gemini'ye sığacak, kısa bir metne indirir.
/// Tüm kataloğu göndermek yerine: özet sayılar + geciken ödünçler + soruyla eşleşen
/// en fazla 40 kitap. Böylece 50 bin kitaplık katalogda da istek küçük kalır.
enum AssistantContext {
    private static let stopWords: Set<String> = [
        "kitap", "kitabı", "kitaplar", "var", "mi", "mı", "mu", "mü", "bir", "ve", "ile", "için",
        "bana", "öner", "önerir", "misin", "hangi", "kaç", "tane", "adet", "olan", "nedir", "ne",
        "kim", "kimin", "yazarı", "yazar", "the", "of", "and", "acaba", "lütfen", "şu", "bu", "o"
    ]

    /// Sorudaki anahtar sözcükler (3+ harf, durak sözcükler hariç).
    static func keywords(in question: String) -> [String] {
        CatalogMatcher.normalize(question)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    /// Soruyla en çok örtüşen kitaplar (ad, yazar, kategori, yayınevi üzerinde puanlama).
    static func matchingBooks(for question: String, in books: [CatalogBook], limit: Int = 40) -> [CatalogBook] {
        let terms = keywords(in: question)
        guard !terms.isEmpty else { return [] }

        var scored: [(CatalogBook, Int)] = []
        for book in books where !book.isWithdrawn {
            let haystack = CatalogMatcher.normalize(
                [book.title, book.author, book.category ?? "", book.publisher ?? "", book.notes]
                    .joined(separator: " ")
            )
            var score = 0
            for term in terms where haystack.contains(term) {
                score += CatalogMatcher.normalize(book.title).contains(term) ? 3 : 1
            }
            if score > 0 { scored.append((book, score)) }
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Öneri isteklerinde boşta olan kitaplardan çeşitli bir örneklem (kategori dengeli).
    static func availableSample(from books: [CatalogBook], loans: [ActiveLoan], limit: Int = 120) -> [CatalogBook] {
        let counts = loanCounts(loans)
        let available = books.filter {
            !$0.isWithdrawn && ($0.quantity ?? 1) - (counts[$0.id] ?? 0) > 0
        }
        var byCategory: [String: [CatalogBook]] = [:]
        for book in available {
            byCategory[book.category ?? "Diğer", default: []].append(book)
        }
        var result: [CatalogBook] = []
        var round = 0
        while result.count < limit {
            var addedThisRound = false
            for key in byCategory.keys.sorted() {
                guard let list = byCategory[key], round < list.count else { continue }
                result.append(list[round])
                addedThisRound = true
                if result.count >= limit { break }
            }
            if !addedThisRound { break }
            round += 1
        }
        return result
    }

    /// Ödünç sayımı için kitap kimliğine göre gruplanmış ödünçler (50 bin kitapta
    /// her kitap için tüm listeyi taramak yerine tek sözlük araması).
    static func loanCounts(_ loans: [ActiveLoan]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for loan in loans { counts[loan.bookID, default: 0] += 1 }
        return counts
    }

    static func line(
        for book: CatalogBook, loans: [ActiveLoan],
        loanCounts: [UUID: Int]? = nil, aliases: PersonAliases? = nil
    ) -> String {
        var parts = ["\(book.title) — \(book.author.isEmpty ? "yazar bilinmiyor" : book.author)"]
        if let category = book.category, !category.isEmpty { parts.append(category) }
        if let publisher = book.publisher, !publisher.isEmpty {
            parts.append([publisher, book.publicationYear ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
        }
        let total = book.quantity ?? 1
        let out = loanCounts?[book.id] ?? LoanAvailability.activeLoanCount(for: book.id, in: loans)
        let free = max(0, total - out)
        parts.append("adet \(total), boşta \(free)")
        let place = [book.cabinet, book.shelf].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        if !place.isEmpty { parts.append("yer: \(place)") }
        if let due = book.loanDueDate, let person = book.loanedTo, !person.isEmpty {
            let shown = aliases?.alias(for: person) ?? person
            parts.append("ödünçte: \(shown), son gün \(due.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " | ")
    }

    /// Gemini'ye gönderilecek bağlam metni + bağlamda geçen kitaplar + kişi takma adları.
    static func build(question: String, books: [CatalogBook], loans: [ActiveLoan],
                      searchPool: [CatalogBook]? = nil) -> AssistantContextResult {
        let aliases = PersonAliases()
        let counts = loanCounts(loans)
        var contextBooks: [CatalogBook] = []
        let active = books.filter { !$0.isWithdrawn }
        let overdueLoans = loans.filter(\.isOverdue)
        let legacyLoaned = active.filter { !($0.loanedTo ?? "").isEmpty }

        var categories: [String: Int] = [:]
        for book in active { categories[book.category ?? "Kategorisiz", default: 0] += 1 }
        let categorySummary = categories
            .sorted { $0.value > $1.value }
            .prefix(12)
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")

        var text = """
        BUGÜN: \(Date.now.formatted(date: .long, time: .omitted))
        KATALOG ÖZETİ: \(active.count) kitap (\(active.reduce(0) { $0 + ($1.quantity ?? 1) }) nüsha), \
        \(books.count - active.count) düşülmüş, \(loans.count + legacyLoaned.count) ödünçte, \
        \(overdueLoans.count) gecikmiş ödünç. Öğrenci sayısı: \(StudentStore.all().count), \
        sınıflar: \(StudentStore.classNames().prefix(15).joined(separator: ", ")).
        KATEGORİLER: \(categorySummary)
        """

        if !overdueLoans.isEmpty {
            text += "\nGECİKEN ÖDÜNÇLER:\n"
            for loan in overdueLoans.prefix(15) {
                let days = Calendar.current.dateComponents([.day], from: loan.dueDate, to: .now).day ?? 0
                text += "- \(loan.bookTitleSnapshot) — \(aliases.alias(for: loan.studentName)) (\(loan.studentClass)), \(days) gün gecikti\n"
            }
        }

        let matches = matchingBooks(for: question, in: searchPool ?? books)
        let wantsRecommendation = ["öner", "tavsiye", "okuyabilir", "okusun", "ne okuyayım", "uygun"]
            .contains { CatalogMatcher.normalize(question).contains(CatalogMatcher.normalize($0)) }

        if !matches.isEmpty {
            text += "\nSORUYLA İLGİLİ KİTAPLAR (\(matches.count)):\n"
            for book in matches {
                text += "- \(line(for: book, loans: loans, loanCounts: counts, aliases: aliases))\n"
            }
            contextBooks.append(contentsOf: matches)
        }
        if wantsRecommendation || matches.isEmpty {
            let sample = availableSample(from: books, loans: loans, limit: matches.isEmpty ? 120 : 60)
            if !sample.isEmpty {
                text += "\nBOŞTA OLAN KİTAPLARDAN ÖRNEKLEM (\(sample.count)):\n"
                let matchedIDs = Set(matches.map(\.id))
                for book in sample where !matchedIDs.contains(book.id) {
                    text += "- \(line(for: book, loans: loans, loanCounts: counts, aliases: aliases))\n"
                    contextBooks.append(book)
                }
            }
        }
        return AssistantContextResult(text: text, books: contextBooks, aliases: aliases)
    }

    /// Modelin döndürdüğü kitap adlarını YALNIZCA bağlamdaki kitaplarla eşler:
    /// tam eşleşme ya da uzunlukça %80+ örtüşen önek. Boş ad hiçbir şeyle eşleşmez.
    static func matchTitles(_ titles: [String], in books: [CatalogBook]) -> [CatalogBook] {
        var seen = Set<UUID>()
        var result: [CatalogBook] = []
        for title in titles {
            let wanted = CatalogMatcher.normalize(title)
            guard wanted.count >= 2 else { continue }
            let found = books.first { book in
                let candidate = CatalogMatcher.normalize(book.title)
                guard !candidate.isEmpty else { return false }
                if candidate == wanted { return true }
                let shorter = min(candidate.count, wanted.count)
                let longer = max(candidate.count, wanted.count)
                guard Double(shorter) / Double(longer) >= 0.8 else { return false }
                return candidate.hasPrefix(wanted) || wanted.hasPrefix(candidate)
            }
            if let found, seen.insert(found.id).inserted { result.append(found) }
        }
        return result
    }
}

/// Bağlam üretiminin çıktısı.
struct AssistantContextResult {
    var text: String
    /// Bağlama giren kitaplar (yanıttaki adlar bunlarla eşlenir).
    var books: [CatalogBook]
    var aliases: PersonAliases
}

/// Öğrenci adları Google'a gitmez: bağlamda "Öğrenci 1" gibi takma adlar kullanılır,
/// yanıt ekrana gelirken gerçek adlara geri çevrilir (eşleme yalnızca cihazda).
final class PersonAliases {
    private var byName: [String: String] = [:]
    private var byAlias: [String: String] = [:]

    func alias(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }
        if let existing = byName[trimmed] { return existing }
        let alias = "Öğrenci \(byName.count + 1)"
        byName[trimmed] = alias
        byAlias[alias] = trimmed
        return alias
    }

    var isEmpty: Bool { byAlias.isEmpty }

    /// Yanıttaki takma adları gerçek adlarla değiştirir ("Öğrenci 12" önce, sonra "Öğrenci 1").
    func restore(in text: String) -> String {
        var result = text
        for (alias, name) in byAlias.sorted(by: { $0.key.count > $1.key.count }) {
            result = result.replacingOccurrences(of: alias, with: name)
        }
        return result
    }
}

// MARK: - Motor

enum AssistantEngine {
    /// Hata kartındaki "Kitaplar’da ara" takip sorusu: sohbete gitmez, Kitaplar sekmesini açar.
    static let kitaplardaAraOnEki = "Kitaplar’da ara"

    /// Asistanın ödünç/düzenleme için aradığı kitap katalogda yoksa (tam ve gevşek aramadan sonra) gösterilen kart.
    static func notFoundCard(for title: String) -> ChatMessage {
        ChatMessage(role: .assistant,
                    text: "“\(title)” katalogda bulunamadı. Kitaplar sekmesinden arayıp adını kontrol edin.",
                    followUps: [kitaplardaAraOnEki + ": " + title], isError: true)
    }

    static let systemPrompt = """
    Sen "Kitap Bul" okul kütüphanesi uygulamasının sesli asistanısın. Kullanıcı kütüphaneci \
    ya da öğretmendir. Türkçe, samimi ve KISA konuş: yanıt sesli okunacak, 1–4 cümle yeter; \
    liste gerekiyorsa en fazla 5 madde. Yalnızca sana verilen BAĞLAM'daki bilgilere dayan; \
    bağlamda olmayan bir kitabı varmış gibi anlatma, "katalogda bulamadım" de. Öneri istenirse \
    bağlamdaki boşta olan kitaplardan seç ve neden uygun olduğunu bir cümleyle söyle. \
    Sayısal sorularda (kaç kitap, kaç gecikme) özetteki sayıları kullan.
    KİTAP EKLEME: Kullanıcı bir kitabı kataloğa eklemek/kaydetmek istiyorsa ("… ekle", "… kaydet", \
    "yeni kitap: …") action alanını doldur: {"type": "addBook", "book": {"title": "", "author": "", \
    "publisher": "", "isbn": "", "publicationYear": "", "category": "", "quantity": 1, "cabinet": "", \
    "shelf": "", "summary": "", "uncertain": []}}. Konuşma hatalarını düzelt, kitabı tanıyorsan \
    yayınevi/yıl/kategori gibi eksikleri bilginle doldur ve emin olmadıklarını uncertain'e yaz; \
    answer'da kısaca "Şunu kaydedeyim mi: …" de. Ekleme isteği yoksa action null olsun.
    ÖDÜNÇ / İADE: Kullanıcı bir kitabı birine vermek istiyorsa ("X'e Y'yi ver", "ödünç ver") \
    action {"type": "lend", "loan": {"kind": "lend", "bookTitle": "", "person": "", "className": ""}}; \
    iade ise ("X iade etti", "Y geri geldi") {"type": "return", "loan": {"kind": "return", "bookTitle": "", "person": ""}}. \
    Kişi adlarını sorudaki gibi AYNEN yaz ("Öğrenci 3" gibi takma adlar dahil). answer'da "… ödünç vereyim mi?" diye sor.
    ÇOKLU EKLEME: Kullanıcı tek cümlede BİRDEN ÇOK kitap sayarsa ("Şunları ekle: A, B ve C") \
    {"type": "addBooks", "books": [{...addBook alanları...}, …]} döndür (en fazla 20).
    DÜZENLEME: "X'i düş/koleksiyondan çıkar", "X'i B dolabı 3. rafa taşı", "X okundu", "X'in kategorisi Tarih olsun", \
    "X'ten 3 adet var" → {"type": "editBook", "edit": {"bookTitle": "", "withdraw": false, "withdrawReason": "", \
    "cabinet": "", "shelf": "", "readingStatus": "Okunacak|Okunuyor|Okundu", "category": "", "quantity": null}}; \
    yalnız istenen alanları doldur; answer'da "… yapayım mı?" diye sor.
    GRAFİK: Dağılım/karşılaştırma sorularında (kategorilere göre, sınıflara göre, aylara göre) chart alanını \
    doldur: {"title": "", "bars": [{"label": "", "value": 0}]} — yalnız BAĞLAM'daki sayılarla; aksi halde chart null.
    DİL: Kullanıcı hangi dilde sorarsa (ya da istenen yanıt dili neyse) answer ve followUps o dilde olsun; \
    kitap adlarını değiştirme.
    YALNIZCA şu JSON'u döndür: {"answer": "sesli okunacak yanıt", "bookTitles": ["bağlamdaki kitap adları AYNEN"], \
    "followUps": ["kullanıcının sorabileceği 2 kısa devam sorusu"], "action": null, "chart": null}
    """

    static func ask(question: String, history: [ChatMessage], context: String,
                    timeout: TimeInterval = 30, maxAttempts: Int = 2) async throws -> AssistantReply {
        let priorTurns: [GeminiContent] = history.suffix(8).map { message in
            GeminiContent(role: message.role == .user ? "user" : "model", parts: [GeminiPart(text: message.text)])
        }
        let prompt = """
        BAĞLAM:
        \(context)

        YANIT DİLİ: \(AsistanDili.current.promptAdi)
        SORU: \(question)
        """
        return try await GeminiClient.shared.generateJSON(
            AssistantReply.self,
            prompt: prompt,
            system: systemPrompt,
            history: priorTurns,
            temperature: 0.5,
            maxOutputTokens: 2048,
            timeout: timeout,
            maxAttempts: maxAttempts,
            thinking: .auto
        )
    }
}

// MARK: - Konuşma tanıma (mikrofon → metin) — ses oturumu arka planda açılır

@Observable
final class SpeechInput: SesKaydedici {
    var transcript = ""
    var isListening = false
    /// Mikrofon/konuşma izni reddedildi: sürekli mod yeniden dinlemeyi dener ama bu durumda denemez.
    /// Geçici hatalar (sessizlik, tanıma kesintisi) yeniden dinlemeyi ENGELLEMEZ.
    private(set) var permissionBlocked = false
    /// Sessizlik yüzünden tanıma boş bitti. Atanmışsa hata yazmak yerine bu çağrılır
    /// (sürekli modda "Dinlemeye devam ediyorum" duyurusu ve yeniden başlatma için).
    var onIdleTimeout: (() -> Void)?
    /// Ses oturumu/motor arka planda başlatılıyor (düğme "hazırlanıyor" gösterir).
    var isStarting = false
    var errorMessage: String?
    /// Sistem "cümle bitti" dediğinde çağrılır; otomatik gönderim için.
    var onFinalTranscript: ((String) -> Void)?

    /// Asistan dili (çok dilli kiosk) her başlatmada okunur
    private var recognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier: AsistanDili.current.rawValue))
    }
    /// Tanıma sürerken tanıyıcı nesnesi canlı tutulur
    private var activeRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Her başlatma yeni bir kimlik alır; geç gelen eski geri çağrılar yoksayılır.
    private var sessionID = UUID()
    /// `SesOturumu` sahiplik kimliği (yalnız kendi oturumumu bırakırım).
    private var audioToken: UUID?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    /// Mikrofon + konuşma tanıma izinlerini ister.
    func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            errorMessage = "Konuşma tanıma izni verilmedi. Ayarlar > Gizlilik'ten açabilirsiniz."
            permissionBlocked = true
            return false
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        if !mic { errorMessage = "Mikrofon izni verilmedi." }
        permissionBlocked = !mic
        return mic
    }

    private struct NoMicrophone: Error { }

    func start() {
        guard !isListening, !isStarting else { return }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Konuşma tanıma şu an kullanılamıyor (\(AsistanDili.current.ad) için internet gerekebilir)."
            return
        }
        activeRecognizer = recognizer
        errorMessage = nil
        transcript = ""
        isStarting = true
        let id = UUID()
        sessionID = id

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        // Cihaz üstü tanıma (internetsiz); desteklenmiyorsa sunucu kullanılır
        if GeminiSettings.prefersOnDeviceSpeech, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        let engine = audioEngine
        SesOturumu.shared.kaydedici = self

        // Oturum açılışı SesOturumu'nda sıralıdır (hoparlör çalıyorsa bekler). Motoru başlatmak
        // CoreAudio'yu bekletir; ana iş parçacığında yapıldığında (özellikle mikrofonsuz
        // simülatörde) arayüz kilitleniyordu, bu yüzden arka planda yapılır.
        Task { @MainActor [weak self] in
            let token: UUID
            do { token = try await SesOturumu.shared.beginRecording() }
            catch {
                self?.failStart(id: id, message: "Mikrofon başlatılamadı: \(error.localizedDescription)")
                return
            }
            guard let self, self.sessionID == id else { // oturum beklerken durduruldu
                await SesOturumu.shared.release(token)
                return
            }
            self.audioToken = token
            do {
                try await Task.detached(priority: .userInitiated) {
                    let input = engine.inputNode
                    let format = input.outputFormat(forBus: 0)
                    guard format.channelCount > 0, format.sampleRate > 0 else { throw NoMicrophone() }
                    input.removeTap(onBus: 0)
                    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                        request.append(buffer)
                    }
                    engine.prepare()
                    try engine.start()
                }.value
                self.didStart(id: id, recognizer: recognizer, request: request)
            } catch {
                let message = error is NoMicrophone
                    ? "Mikrofon bulunamadı (simülatörde mikrofon yoktur)."
                    : "Mikrofon başlatılamadı: \(error.localizedDescription)"
                self.failStart(id: id, message: message)
            }
        }
    }

    private func didStart(id: UUID, recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        guard sessionID == id else { // bu arada durduruldu
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            if let token = audioToken { audioToken = nil; Task { await SesOturumu.shared.release(token) } }
            return
        }
        isStarting = false
        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, self.sessionID == id else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        let final = self.transcript
                        self.stop()
                        if !final.isEmpty { self.onFinalTranscript?(final) }
                    }
                }
                if let error {
                    let nsError = error as NSError
                    let final = self.transcript
                    self.stop()
                    switch nsError.code {
                    case 216, 301, 1110:
                        break // kullanıcı durdurdu / oturum kapandı: normal
                    case 203, 1101:
                        // "Retry" / ses yok: bir şey söylenmişse gönder, yoksa kibar uyarı
                        if !final.isEmpty {
                            self.onFinalTranscript?(final)
                        } else if let idle = self.onIdleTimeout {
                            idle()
                        } else {
                            self.errorMessage = "Ses algılanmadı; mikrofona biraz daha yakın konuşup yeniden deneyin."
                        }
                    default:
                        self.errorMessage = "Dinleme kesildi (\(nsError.code)). Yeniden deneyin."
                    }
                }
            }
        }
    }

    private func failStart(id: UUID, message: String) {
        guard sessionID == id else { return }
        isStarting = false
        isListening = false
        request = nil
        audioEngine.inputNode.removeTap(onBus: 0)
        errorMessage = message
        if let token = audioToken { audioToken = nil; Task { await SesOturumu.shared.release(token) } }
    }

    /// Durumu hemen kapatır; motor ve oturum kapanışı `stopAndWait` ile beklenebilir.
    private func beginStop() -> Bool {
        sessionID = UUID() // bekleyen başlatma varsa geçersiz kılınır
        let wasActive = isListening || isStarting || audioEngine.isRunning
        isStarting = false
        isListening = false
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        return wasActive
    }

    func stop() {
        guard beginStop() else { return }
        let engine = audioEngine, token = audioToken
        audioToken = nil
        Task {
            await Task.detached { engine.stop(); engine.inputNode.removeTap(onBus: 0) }.value
            if let token { await SesOturumu.shared.release(token) }
        }
    }

    /// Motor durup oturum bırakılana kadar bekler: ardından hoparlörü açmak güvenlidir.
    func stopAndWait() async {
        guard beginStop() else { return }
        let engine = audioEngine, token = audioToken
        audioToken = nil
        await Task.detached { engine.stop(); engine.inputNode.removeTap(onBus: 0) }.value
        if let token { await SesOturumu.shared.release(token) }
    }
}

// MARK: - Sesli okuma (metin → ses) — Gemini HD + cihaz yedeği

/// Yanıtları seslendirir. Önce **Gemini TTS (HD ses)** denenir: metin Google'a gider,
/// WAV gelir, `AVAudioPlayer` çalar. Çevrimdışı/hata/kapalıysa cihazın kendi Türkçe
/// sesine (`AVSpeechSynthesizer`) düşer; kullanıcı asla sessiz kalmaz.
/// Aynı metin ikinci kez okunursa ses önbellekten gelir (jeton harcanmaz).
@Observable
final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var isSpeaking = false
    /// Gemini sesi indiriliyor (düğme "hazırlanıyor" gösterir).
    var isPreparing = false
    /// Son okumanın kaynağı: arayüzde "HD ses" rozeti için.
    private(set) var lastUsedGemini = false

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var fetchTask: Task<Void, Never>?
    /// Eski bir okumanın iptal geri çağrısı yeni okumanın durumunu bozmasın
    private var currentUtterance: AVSpeechUtterance?
    private let audioCache = NSCache<NSString, NSData>()
    /// `SesOturumu` çalma sahipliği; okuma bitince ya da durdurulunca bırakılır.
    private var playbackToken: UUID?
    private var speakGeneration = UUID()

    override init() {
        super.init()
        synthesizer.delegate = self
        audioCache.countLimit = 30
    }

    func speak(_ text: String) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSpeaking = true
        let generation = UUID()
        speakGeneration = generation
        let reachability = GeminiReachability.shared
        let useGemini = GeminiSettings.isTTSEnabled && !reachability.isBlockedOrOffline
        let cacheKey = "\(GeminiSettings.ttsVoice.rawValue)|\(trimmed)" as NSString
        let cached = useGemini ? audioCache.object(forKey: cacheKey) : nil
        if useGemini, cached == nil { isPreparing = true }

        fetchTask = Task { [weak self] in
            // Mikrofon kapanıp ses oturumu hoparlöre geçene kadar hiçbir şey çalmaz
            let token = try? await SesOturumu.shared.beginPlayback()
            guard let self, !Task.isCancelled, self.speakGeneration == generation else {
                if let token { await SesOturumu.shared.release(token) }
                return
            }
            self.playbackToken = token
            if let cached {
                self.play(cached as Data)
                return
            }
            guard useGemini else {
                self.speakWithDevice(trimmed)
                return
            }
            do {
                let audio = try await GeminiClient.shared.synthesizeSpeech(trimmed, timeout: GeminiReachability.ttsTimeout)
                guard !Task.isCancelled, self.speakGeneration == generation else { return }
                self.audioCache.setObject(audio as NSData, forKey: cacheKey)
                self.isPreparing = false
                self.play(audio)
            } catch {
                guard !Task.isCancelled, self.speakGeneration == generation else { return }
                self.isPreparing = false
#if DEBUG
                print("🔊 Gemini TTS düştü, cihaz sesi: \(error.localizedDescription)")
#endif
                self.speakWithDevice(trimmed)
            }
        }
    }

    private func releasePlayback() {
        guard let token = playbackToken else { return }
        playbackToken = nil
        Task { await SesOturumu.shared.release(token) }
    }

    func stop() {
        speakGeneration = UUID()
        fetchTask?.cancel()
        fetchTask = nil
        isPreparing = false
        currentUtterance = nil
        releasePlayback()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
        isSpeaking = false
    }

    // MARK: Gemini sesi

    private func play(_ audio: Data) {
        do {
            let player = try AVAudioPlayer(data: audio)
            player.delegate = self
            player.prepareToPlay()
            self.player = player
            lastUsedGemini = true
            isSpeaking = true
            player.play()
        } catch {
            speakWithDevice(nil)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.player = nil
            self.isSpeaking = false
            self.releasePlayback()
        }
    }

    // MARK: Cihaz sesi (yedek)

    private func speakWithDevice(_ text: String?) {
        guard let text, !text.isEmpty else {
            isSpeaking = false
            releasePlayback()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AsistanDili.current == .turkce
            ? Self.preferredTurkishVoice()
            : AVSpeechSynthesisVoice(language: AsistanDili.current.rawValue)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.prefersAssistiveTechnologySettings = true
        currentUtterance = utterance
        lastUsedGemini = false
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    /// Yüklüyse gelişmiş (enhanced/premium) Türkçe ses; yoksa varsayılan tr-TR.
    static func preferredTurkishVoice() -> AVSpeechSynthesisVoice? {
        let turkish = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("tr") }
        return turkish.first { $0.quality == .premium }
            ?? turkish.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "tr-TR")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(ObjectIdentifier(utterance))
    }

    /// Yalnızca GÜNCEL okumanın bitişi durumu değiştirir; eski okumanın iptal çağrısı yoksayılır.
    /// Oturum burada kapatılmaz: mikrofon o sırada açılmış olabilir.
    private nonisolated func finished(_ id: ObjectIdentifier) {
        Task { @MainActor in
            guard let current = self.currentUtterance, ObjectIdentifier(current) == id else { return }
            self.currentUtterance = nil
            self.isSpeaking = false
            self.releasePlayback()
        }
    }
}

// MARK: - Görünüm

struct AIAssistantView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogBook.addedAt, order: .reverse) private var books: [CatalogBook]
    @Query private var loans: [ActiveLoan]

    @AppStorage(GeminiSettings.voiceRepliesKey) private var voiceReplies = true
    @AppStorage(GeminiSettings.enabledKey) private var aiEnabled = true

    @State private var messages: [ChatMessage] = [
        ChatMessage(
            role: .assistant,
            text: "Merhaba! Ben kütüphane asistanınız. Katalogdaki kitapları, ödünçleri ve gecikmeleri sorabilir, öğrencilere kitap önerisi isteyebilirsiniz. Mikrofona dokunup konuşabilirsiniz.",
            followUps: ["Geciken ödünç var mı?", "5. sınıfa macera kitabı öner", "Kitap ekle: Şeker Portakalı, Vasconcelos, 2 adet", "Kuyucaklı Yusuf iade edildi"]
        )
    ]
    @State private var input = ""
    @State private var isThinking = false
    @State private var sendTask: Task<Void, Never>?
    @State private var sendGeneration = UUID()
    @State private var taskGate = VoiceEntryTaskGate()
    @State private var speech = SpeechInput()
    @State private var voice = SpeechOutput()
    @State private var selectedBook: CatalogBook?
    @State private var historySaveError: String?
    @State private var historyLoadedSafely = true
    @State private var clearChatConfirmation = false
    @State private var targetChoice: AssistantTargetChoice?
    @AppStorage(AsistanDili.key) private var languageRaw = AsistanDili.turkce.rawValue
    @AppStorage("assistantPushToTalk") private var pushToTalk = false
    @State private var favorites = FavoritePromptStore.all()
    @State private var didLoadHistory = false
    @State private var isPressingMic = false
    @GestureState private var micHeld = false
    @State private var isShowingAITools = false
    private let derinBaglanti = DerinBaglanti.shared
    @FocusState private var isInputFocused: Bool
    @ScaledMetric(relativeTo: .title) private var micSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var sendSize: CGFloat = 32

    private let quickPrompts = [
        "Geciken ödünç var mı?", "Kaç kitabımız var?", "Ödünçte hangi kitaplar var?",
        "5. sınıfa macera kitabı öner", "Bilim kitaplarından hangileri boşta?", "Sabahattin Ali kitabı var mı?"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !aiEnabled {
                    disabledBanner
                }
                conversation
                quickPromptBar
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .kenardanSekmeKaydir()
            .navigationTitle("Sesli Asistan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingAITools = true
                    } label: {
                        Label("Yapay zekâ araçları", systemImage: "sparkles")
                    }
                    .accessibilityHint("Gemini ile tarama, öneri, soru üretme ve analiz araçları")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $voiceReplies) {
                        Label("Sesli yanıt", systemImage: voiceReplies ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .toggleStyle(.button)
                    .tint(KitapTema.ana)
                    .accessibilityLabel(voiceReplies ? "Sesli yanıt açık" : "Sesli yanıt kapalı")
                    .accessibilityHint("Asistan yanıtlarının sesli okunmasını açar veya kapatır")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Asistan dili", selection: $languageRaw) {
                            ForEach(AsistanDili.allCases) { Text($0.ad).tag($0.rawValue) }
                        }
                        Toggle("Bas-konuş (basılı tut)", isOn: $pushToTalk)
                        Divider()
                        Button(role: .destructive) {
                            clearChatConfirmation = true
                        } label: {
                            Label("Sohbeti Temizle", systemImage: "trash")
                        }
                        .disabled(messages.count <= 1)
                    } label: {
                        Label("Asistan seçenekleri", systemImage: "ellipsis.circle")
                    }
                    .accessibilityHint("Dil, bas-konuş modu ve sohbet geçmişi")
                }
            }
            .sheet(isPresented: $isShowingAITools) { AIToolsView() }
            .sheet(item: $selectedBook) { book in
                AIBookInfoSheet(book: book, loans: loans)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $targetChoice) { choice in
                AssistantTargetPicker(choice: choice) { id, person, className, studentID, memberID, copyID, loanID in
                    guard let book = books.first(where: { $0.id == id }),
                          let choiceIndex = messages.firstIndex(where: { $0.proposedTargetChoice?.id == choice.id && !$0.proposalResolved }) else { return }
                    var message = ChatMessage(role: .assistant, text: "Seçtiğiniz işlem için son onay:", bookIDs: [id])
                    if let intent = choice.loan {
                        message.proposedLoan = LoanProposal(kind: intent.kind, bookID: id, bookTitle: book.title,
                            person: person, className: className, studentID: studentID, memberID: memberID, copyID: copyID, loanID: loanID)
                    } else if let intent = choice.edit {
                        message.proposedEdit = EditProposal(bookID: id, bookTitle: book.title, intent: intent)
                    }
                    messages[choiceIndex].proposalResolved = true
                    messages.append(message)
                    targetChoice = nil
                }
            }
            .onAppear {
                taskGate.activate()
                speech.onFinalTranscript = { text in
                    // Bas-konuş modunda gönderim parmak kalkınca yapılır
                    guard !pushToTalk else { return }
                    input = text
                    Task { await send() }
                }
                // Taslak kimlikleri aynen geri gelir; eski kartlar açık inceleme ister.
                if !didLoadHistory {
                    didLoadHistory = true
                    do {
                        messages += try ChatHistoryStore.loadVerified().map(\.message)
                    } catch {
                        historyLoadedSafely = false
                        historySaveError = "Sohbet dosyası okunamadı; mevcut dosya korunuyor. Taslak kaydetme kapalı: " + error.localizedDescription
                    }
                }
            }
            // Bir taslağın çözümlenmesi veya kısmi başarısızlığı da hemen kalıcılaşır.
            .onChange(of: messages) { _, _ in _ = persistHistory() }
            .confirmationDialog("Sohbet ve onay bekleyen \(messages.filter(\.hasPendingProposal).count) taslak silinsin mi?", isPresented: $clearChatConfirmation, titleVisibility: .visible) {
                Button("Temizle", role: .destructive) {
                    do {
                        try ChatHistoryStore.clearVerified()
                        voice.stop(); targetChoice = nil; messages = Array(messages.prefix(1))
                        historyLoadedSafely = true; historySaveError = nil
                    } catch { historySaveError = "Sohbet silinemedi: " + error.localizedDescription }
                }
                Button("Vazgeç", role: .cancel) { }
            }
            .safeAreaInset(edge: .top) {
                if let historySaveError { Text(historySaveError).font(.footnote).foregroundStyle(.red).padding().background(.regularMaterial).fixedSize(horizontal: false, vertical: true) }
            }
            .onDisappear {
                taskGate.deactivate()
                sendTask?.cancel()
                sendTask = nil
                sendGeneration = UUID()
                _ = persistHistory()
                speech.stop()
                voice.stop()
            }
            // Ana sayfa / alt çubuktaki "Asistana sesle sor" dinlemeyi hemen başlatır
            .onChange(of: derinBaglanti.asistanDinle, initial: true) { _, dinle in
                guard dinle else { return }
                derinBaglanti.asistanDinle = false
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if !speech.isListening { await toggleListening() }
                }
            }
            .sensoryFeedback(.success, trigger: messages.filter(\.proposalResolved).count)
        }
    }

    /// Yapay zekâ kapalıyken gösterilen uyarı şeridi.
    private var disabledBanner: some View {
        Label("Yapay zekâ ayarlardan kapatılmış. Ayarlar > Yapay Zekâ bölümünden açın.", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(KitapTema.vurgu.opacity(0.15))
            .foregroundStyle(KitapTema.vurgu)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubble(
                            message: message,
                            books: message.bookIDs.compactMap { id in books.first { $0.id == id } },
                            onBookTap: { selectedBook = $0 },
                            onFollowUp: { question in
                                if question.hasPrefix(AssistantEngine.kitaplardaAraOnEki) {
                                    DerinBaglanti.shared.hedefSekme = .kitaplar
                                    return
                                }
                                input = question
                                Task { await send() }
                            },
                            onSaveProposal: {
                                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                                    confirmProposal(at: index)
                                }
                            },
                            isFavorite: favorites.contains(message.text),
                            onToggleFavorite: {
                                FavoritePromptStore.toggle(message.text)
                                favorites = FavoritePromptStore.all()
                            },
                            onDismissProposal: {
                                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                                    messages[index].proposalResolved = true
                                }
                            }
                        )
                        .id(message.id)
                    }
                    if messages.count == 1 && !isThinking {
                        OneriKartlari { soru in
                            input = soru
                            Task { await send() }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    if isThinking {
                        ThinkingIndicator()
                            .id("thinking")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isThinking) {
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var quickPromptBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(favorites, id: \.self) { prompt in
                    Button {
                        input = prompt
                        Task { await send() }
                    } label: {
                        Label(prompt, systemImage: "star.fill")
                    }
                    .buttonStyle(.kitapTonlu(KitapTema.vurgu))
                    .font(.footnote)
                    .accessibilityHint("Favori soru; asistana gönderir")
                }
                ForEach(quickPrompts.filter { !favorites.contains($0) }, id: \.self) { prompt in
                    Button(prompt) {
                        input = prompt
                        Task { await send() }
                    }
                    .buttonStyle(.kitapTonlu(KitapTema.ana))
                    .font(.footnote)
                    .accessibilityHint("Bu soruyu asistana gönderir")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .disabled(isThinking || speech.isListening)
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            if speech.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .foregroundStyle(.red)
                    Text(speech.transcript.isEmpty ? "Dinliyorum… konuşun" : speech.transcript)
                        .font(.footnote)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Dinleniyor: \(speech.transcript)")
            }
            if let error = speech.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            HStack(spacing: 10) {
                if pushToTalk {
                    // Bas-konuş: basılı tutarken dinler, parmak kalkınca gönderir
                    Image(systemName: speech.isListening ? "mic.fill.badge.plus" : "mic.circle.fill")
                        .font(.system(size: micSize * (isPressingMic ? 1.25 : 1)))
                        .foregroundStyle(speech.isListening ? .red : KitapTema.ana)
                        .symbolEffect(.pulse, isActive: speech.isListening)
                        // GestureState, iptal edilen dokunuşta da (bildirim, çağrı) kendiliğinden sıfırlanır
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .updating($micHeld) { _, held, _ in held = true }
                        )
                        .onChange(of: micHeld) { _, held in
                            isPressingMic = held
                            Task { held ? await beginPushToTalk() : await endPushToTalk() }
                        }
                        .accessibilityLabel("Bas-konuş mikrofonu")
                        .accessibilityHint("Basılı tutup konuşun, bırakınca gönderilir. VoiceOver ile iki kez dokunarak başlatıp durdurun.")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { Task { await toggleListening() } }
                } else {
                    Button {
                        Task { await toggleListening() }
                    } label: {
                        Image(systemName: speech.isListening ? "stop.circle.fill" : (speech.isStarting ? "mic.badge.xmark" : "mic.circle.fill"))
                            .font(.system(size: micSize))
                            .foregroundStyle(speech.isListening ? .red : KitapTema.ana)
                            .symbolEffect(.pulse, isActive: speech.isListening || speech.isStarting)
                    }
                    .accessibilityLabel(speech.isListening ? "Dinlemeyi durdur ve gönder" : "Sesli soru sor")
                    .accessibilityHint("Mikrofonla konuşarak soru sorarsınız")
                }

                TextField("Sorunuzu yazın…", text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }
                    .accessibilityLabel("Asistana soru")

                if isThinking {
                    Button {
                        stopSending()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: sendSize))
                            .foregroundStyle(KitapTema.vurgu)
                    }
                    .accessibilityLabel("Yanıtı durdur")
                    .accessibilityHint("Bekleyen yanıtı iptal eder")
                } else if voice.isSpeaking {
                    Button {
                        voice.stop()
                    } label: {
                        Image(systemName: voice.isPreparing ? "waveform.badge.magnifyingglass" : "speaker.slash.circle.fill")
                            .font(.system(size: sendSize))
                            .foregroundStyle(KitapTema.vurgu)
                            .symbolEffect(.pulse, isActive: voice.isPreparing)
                    }
                    .accessibilityLabel(voice.isPreparing ? "HD ses hazırlanıyor, durdur" : "Okumayı durdur")
                } else {
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: sendSize))
                            .foregroundStyle(canSend ? KitapTema.ana : .gray)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Gönder")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking && aiEnabled
    }

    /// Karttaki "Kaydet/Uygula" ya da sesli "tamam": önerinin türüne göre işlem yapılır.
    private func confirmProposal(at index: Int) {
        guard messages.indices.contains(index) else { return }
        if let choice = messages[index].proposedTargetChoice {
            guard !messages[index].proposalResolved else { return }
            targetChoice = choice
        } else if messages[index].proposedLoan != nil {
            executeLoan(at: index)
        } else if messages[index].proposedEdit != nil {
            executeEdit(at: index)
        } else if !messages[index].proposedBooks.isEmpty {
            saveMultipleProposals(at: index)
        } else {
            saveProposal(at: index)
        }
    }

    @discardableResult
    private func persistHistory() -> Bool {
        guard historyLoadedSafely else { return false }
        do { try ChatHistoryStore.saveVerified(Array(messages.dropFirst())); historySaveError = nil; return true }
        catch { historySaveError = "Taslaklar cihazda kaydedilemedi. İşlemi yeniden deneyin: " + error.localizedDescription; return false }
    }

    private func announce(_ text: String) {
        if UIAccessibility.isVoiceOverRunning {
            AccessibilityNotification.Announcement(text).post()
        } else if voiceReplies {
            voice.speak(text)
        }
    }

    /// Onaylanan düzenlemeyi (düş/taşı/durum/kategori/adet) uygular.
    private func executeEdit(at index: Int) {
        guard messages.indices.contains(index), let proposal = messages[index].proposedEdit else { return }
        // Düşme ve adet değişikliği görevli modunda yönetici kimliği ister
        if !YetkiDurumu.shared.yonetici {
            let messageID = messages[index].id
            Task {
                if await YetkiDurumu.shared.yoneticiOl(), let current = messages.firstIndex(where: { $0.id == messageID }) {
                    executeEdit(at: current)
                }
            }
            return
        }
        guard !messages[index].proposalResolved else { return }
        guard let book = books.first(where: { $0.id == proposal.bookID }), !book.isDeleted else {
            messages.append(ChatMessage(role: .assistant, text: "Kitap katalogda bulunamadı.", isError: true))
            return
        }
        do {
            let text = try BookEditEngine.apply(proposal.intent, to: book, context: modelContext)
            messages[index].proposalResolved = true
            CatalogBackup.saveLight(books)
            messages.append(ChatMessage(role: .assistant, text: text, bookIDs: [book.id]))
            announce(text)
        } catch {
            messages.append(ChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
        }
    }

    /// Tek seferde dikte edilen kitapların hepsini kaydeder (her biri mükerrer denetiminden geçer).
    private func saveMultipleProposals(at index: Int) {
        guard messages.indices.contains(index), !messages[index].proposalResolved else { return }
        let list = messages[index].proposedBooks
        if messages[index].proposedOperationIDs.count != list.count {
            messages[index].proposedOperationIDs = list.map { _ in UUID() }
        }
        // Makbuz kimlikleri ilk veritabanı yazımından önce dosyada bulunmalıdır.
        guard persistHistory() else { return }
        let operationIDs = messages[index].proposedOperationIDs
        var saved: [UUID] = []
        var failed: [SesliKitapKaydi] = []
        var failedIDs: [UUID] = []
        var merged = 0
        var errors: [String] = []
        // Katalog tek kez okunur; her ekleme sonrası listeye eklenir (20 kitap × tam tablo okuması yok)
        var catalog: [CatalogBook]
        do { catalog = try modelContext.fetch(FetchDescriptor<CatalogBook>()) }
        catch {
            messages.append(ChatMessage(role: .assistant, text: "Katalog okunamadı: \(error.localizedDescription)", isError: true))
            return
        }
        for (itemIndex, kaydi) in list.enumerated() {
            do {
                let outcome = try VoiceBookSaver.save(kaydi, in: modelContext, catalog: catalog, operationID: operationIDs[itemIndex])
                VoiceBookSaver.enrichInBackground(outcome.book, context: modelContext)
                saved.append(outcome.book.id)
                if case .merged = outcome { merged += 1 } else { catalog.insert(outcome.book, at: 0) }
            } catch { failed.append(kaydi); failedIDs.append(operationIDs[itemIndex]); errors.append(error.localizedDescription) }
        }
        messages[index].proposedBooks = failed
        messages[index].proposedOperationIDs = failedIDs
        messages[index].proposalResolved = failed.isEmpty
        let text = "\(saved.count)/\(list.count) kitap kaydedildi" + (merged > 0 ? " (\(merged) mevcut kayda nüsha eklendi)." : ".")
            + (failed.isEmpty ? "" : " \(failed.count) kayıt yeniden denemek için korundu. " + (errors.first ?? ""))
        messages.append(ChatMessage(role: .assistant, text: text, bookIDs: Array(saved.prefix(8)), isError: !failed.isEmpty))
        announce(text)
    }

    private func beginPushToTalk() async {
        voice.stop()
        guard !speech.isListening, !speech.isStarting else { return }
        guard await speech.requestAuthorization() else {
            isPressingMic = false
            return
        }
        // İzin penceresi sırasında parmak kalktıysa mikrofon açılmaz
        guard isPressingMic else { return }
        speech.start()
    }

    private func endPushToTalk() async {
        // Son hecelerin de tanınması için kısa bekleme
        try? await Task.sleep(for: .milliseconds(350))
        let text = speech.transcript
        speech.stop()
        if !text.isEmpty {
            input = text
            await send()
        }
    }

    /// Onaylanan ödünç/iade işlemini uygular.
    private func executeLoan(at index: Int) {
        guard messages.indices.contains(index), let proposal = messages[index].proposedLoan else { return }
        guard !messages[index].proposalResolved else { return }
        guard let book = books.first(where: { $0.id == proposal.bookID }), !book.isDeleted else {
            messages.append(ChatMessage(role: .assistant, text: "Kitap katalogda bulunamadı.", isError: true))
            return
        }
        // Yeniden başlatıldığında aynı kart aynı ödünç makbuzunu kullanır.
        guard persistHistory() else { return }
        do {
            let text: String
            if proposal.kind == "return", let loanID = proposal.loanID {
                guard let loan = loans.first(where: { $0.id == loanID && $0.bookID == book.id }) else {
                    throw SchoolLibraryService.OperationError(message: "Seçilen ödünç kaydı artık açık değil; yeniden seçin.")
                }
                let sameIdentity: Bool
                if let expectedID = proposal.studentID { sameIdentity = loan.studentID == expectedID && loan.memberID == nil && proposal.memberID == nil }
                else if let expectedID = proposal.memberID { sameIdentity = loan.memberID == expectedID && loan.studentID == nil }
                else {
                    sameIdentity = loan.studentID == nil && loan.memberID == nil && CatalogMatcher.normalize(loan.studentName) == CatalogMatcher.normalize(proposal.person)
                        && loan.studentClass == (proposal.className ?? "")
                }
                guard sameIdentity, proposal.copyID == loan.copyID else {
                    throw SchoolLibraryService.OperationError(message: "Seçilen ödünç kaydı ile okur/nüsha kimliği değişti; iadeyi yeniden seçin.")
                }
                let notice = try SchoolLibraryService.returnLoan(loan, context: modelContext)
                text = "“\(book.title)” iade alındı." + (notice.map { " " + $0 } ?? "")
            } else if proposal.kind == "return" {
                text = try LoanActionEngine.giveBack(book: book, person: proposal.person.isEmpty ? nil : proposal.person,
                    loans: loans, context: modelContext, studentID: proposal.studentID, copyID: proposal.copyID, memberID: proposal.memberID)
            } else {
                text = try LoanActionEngine.lend(book: book, person: proposal.person, className: proposal.className,
                    loans: loans, context: modelContext, defaultDays: UserDefaults.standard.object(forKey: "loanDurationDays") as? Int ?? 15,
                    studentID: proposal.studentID, copyID: proposal.copyID, operationID: messages[index].id, memberID: proposal.memberID)
            }
            messages[index].proposalResolved = true
            messages.append(ChatMessage(role: .assistant, text: text, bookIDs: [book.id]))
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement(text).post()
            } else if voiceReplies {
                voice.speak(text)
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, text: error.localizedDescription, isError: true))
        }
    }

    /// Asistanın önerdiği kaydı kataloğa yazar (mükerrer kontrolü + arka planda kapak/ISBN tamamlama).
    private func saveProposal(at index: Int) {
        guard messages.indices.contains(index), !messages[index].proposalResolved,
              let kaydi = messages[index].proposedBook else { return }
        guard persistHistory() else { return }
        do {
            let outcome = try VoiceBookSaver.save(kaydi, in: modelContext, catalog: books, operationID: messages[index].id)
            VoiceBookSaver.enrichInBackground(outcome.book, context: modelContext)
            messages[index].proposalResolved = true
            messages.append(ChatMessage(role: .assistant, text: outcome.message, bookIDs: [outcome.book.id]))
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement(outcome.message).post()
            } else if voiceReplies {
                voice.speak(outcome.message)
            }
        } catch {
            messages.append(ChatMessage(role: .assistant, text: "Kaydedilemedi: \(error.localizedDescription)", isError: true))
        }
    }

    private func toggleListening() async {
        if speech.isListening {
            let text = speech.transcript
            speech.stop()
            if !text.isEmpty {
                input = text
                await send()
            }
            return
        }
        voice.stop()
        guard await speech.requestAuthorization() else { return }
        speech.start()
    }

    private func send() async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isThinking else { return }
        let generation = UUID()
        sendGeneration = generation
        let task = Task { await performSend(question: question, generation: generation) }
        sendTask = task
        await task.value
    }

    /// "Durdur": bekleyen yanıt iptal edilir; geç gelen yanıt hiçbir şeyi uygulamaz.
    private func stopSending() {
        sendTask?.cancel()
        sendTask = nil
        sendGeneration = UUID()
        isThinking = false
        messages.append(ChatMessage(role: .assistant, text: "Yanıt beklemesi durduruldu."))
    }

    private func performSend(question: String, generation: UUID) async {
        // Mikrofon açıksa kapat: sesli yanıt ile kayıt aynı ses oturumunu paylaşamaz
        speech.stop()
        voice.stop()

        // Bekleyen kayıt önerisi varsa "kaydet" / "iptal" ağa gitmeden yerelde işlenir.
        // Sohbet sözlüğünde "sil" iptal sayılmaz (silme isteği olabilir); normal soru olarak gider.
        if let pendingIndex = messages.lastIndex(where: {
               ($0.proposedBook != nil || $0.proposedLoan != nil || $0.proposedEdit != nil || !$0.proposedBooks.isEmpty)
                   && !$0.proposalResolved && !$0.proposalNeedsReview
           }),
           let command = VoiceBookEngine.localCommand(in: question, scope: .chat) {
            input = ""
            switch command {
            case .save, .saveAll:
                confirmProposal(at: pendingIndex)
            case .cancel:
                messages[pendingIndex].proposalResolved = true
                messages.append(ChatMessage(role: .assistant, text: "Tamam, kaydetmedim."))
            case .undo, .next:
                messages.append(ChatMessage(role: .assistant, text: "Bu komut burada geçerli değil. Kartı onaylayın ya da “iptal” deyin."))
            }
            return
        }
        input = ""
        isInputFocused = false
        messages.append(ChatMessage(role: .user, text: question))
        isThinking = true
        let lifetime = taskGate.currentToken
        defer { if sendGeneration == generation { isThinking = false } }
        /// İptal, "Durdur", başka bir soru ya da sayfadan çıkış sonrası eski yanıt uygulanmaz.
        func isCurrent() -> Bool {
            guard !Task.isCancelled, sendGeneration == generation else { return false }
            if let lifetime { return taskGate.accepts(lifetime) }
            return true
        }
        func speakOrAnnounce(_ text: String) {
            // VoiceOver açıkken iki ses üst üste binmesin: duyuru VoiceOver'a bırakılır
            if UIAccessibility.isVoiceOverRunning {
                AccessibilityNotification.Announcement(text).post()
            } else if voiceReplies {
                voice.speak(text)
            }
        }
        func answerLocally() -> Bool {
            guard let local = YerelAsistan.answer(question, books: books, loans: loans) else { return false }
            var message = ChatMessage(role: .assistant, text: local.text, bookIDs: local.bookIDs)
            message.isOffline = true
            messages.append(message)
            speakOrAnnounce(local.text)
            return true
        }

        // Google'a ulaşılamıyorsa (engelli ağ/çevrimdışı) bilinen sorular cihazda yanıtlanır
        let reachability = GeminiReachability.shared
        await reachability.probeIfStale()
        guard isCurrent() else { return }
        if reachability.isBlockedOrOffline, answerLocally() { return }

        // Büyük katalogda veritabanı ön süzmesi (searchKey); dizin boşsa tüm liste kullanılır
        let pool = CatalogSearchIndex.candidates(for: AssistantContext.keywords(in: question), context: modelContext)
        let context = AssistantContext.build(question: question, books: books, loans: loans,
                                             searchPool: pool.isEmpty ? nil : pool)
        // Soruda ve geçmişte geçen öğrenci/üye adları Google'a gitmeden takma adla değiştirilir.
        // Kayıtsız kişiler ("Ayşe'ye ver") yalnız ödünç fiilli cümlelerden bu istek için geçici eşlenir.
        let knownNames = StudentStore.all().map(\.name) + MemberStore.all().map(\.name) + loans.map(\.studentName)
        let names = knownNames + PersonAliases.kayitsizAdlar(in: question, known: knownNames, bookTitles: books.map(\.title))
        let authors = Array(Set(books.map(\.author).filter { !$0.isEmpty }))
        let safeQuestion = context.aliases.pseudonymize(question, names: names, protecting: authors)
        let safeHistory = messages.dropLast().filter { !$0.isError }.map { message -> ChatMessage in
            var copy = message
            copy.text = context.aliases.pseudonymize(message.text, names: names, protecting: authors)
            return copy
        }
        do {
            let reply = try await AssistantEngine.ask(
                question: safeQuestion,
                history: safeHistory,
                context: context.text
            )
            guard isCurrent() else { return }
            let answer = context.aliases.restore(in: reply.answer)
            let matched = AssistantContext.matchTitles(reply.bookTitles ?? [], in: context.books)
            var proposal: SesliKitapKaydi?
            if reply.action?.type == "addBook", let book = reply.action?.book {
                let normalized = VoiceBookEngine.normalized(book)
                if normalized.hasBookContent { proposal = normalized }
            }
            let loanProposal: LoanProposal? = nil
            var editProposal: EditProposal?
            var pendingChoice: AssistantTargetChoice?
            var missingTitle: String?
            var missingLoan: LoanIntent?
            var missingEdit: BookEditIntent?
            let uniqueBooks = Array(Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
            if let intent = reply.action?.loan ?? (["lend", "return"].contains(reply.action?.type ?? "")
                    ? LoanIntent(kind: reply.action?.type ?? "") : nil), let title = intent.bookTitle {
                var restoredIntent = intent
                restoredIntent.kind = intent.kind == "return" || reply.action?.type == "return" ? "return" : "lend"
                let candidates = AssistantTargetChoice.candidates(title, in: uniqueBooks)
                if !candidates.isEmpty {
                    pendingChoice = AssistantTargetChoice(bookIDs: candidates.map(\.id), loan: restoredIntent,
                        person: context.aliases.restore(in: intent.person ?? ""), className: intent.className ?? "")
                } else {
                    missingTitle = title
                    missingLoan = restoredIntent
                }
            }
            if reply.action?.type == "editBook", let intent = reply.action?.edit, intent.hasChange, let title = intent.bookTitle {
                let candidates = AssistantTargetChoice.candidates(title, in: uniqueBooks)
                if candidates.count == 1, let book = candidates.first {
                    editProposal = EditProposal(bookID: book.id, bookTitle: book.title, intent: intent)
                } else if !candidates.isEmpty {
                    pendingChoice = AssistantTargetChoice(bookIDs: candidates.map(\.id), edit: intent)
                } else {
                    missingTitle = title
                    missingEdit = intent
                }
            }
            // Tam eşleşme yoksa gevşek ikinci arama: aday varsa hedef seçimi, yoksa açık "bulunamadı" kartı
            if let title = missingTitle, pendingChoice == nil, editProposal == nil {
                let loosePool = CatalogSearchIndex.candidates(for: AssistantContext.keywords(in: title), context: modelContext)
                let loose = AssistantTargetChoice.looseCandidates(title, in: loosePool.isEmpty ? uniqueBooks : loosePool)
                if !loose.isEmpty {
                    if let intent = missingLoan {
                        pendingChoice = AssistantTargetChoice(bookIDs: loose.map(\.id), loan: intent,
                            person: context.aliases.restore(in: intent.person ?? ""), className: intent.className ?? "")
                    } else if let intent = missingEdit {
                        pendingChoice = AssistantTargetChoice(bookIDs: loose.map(\.id), edit: intent)
                    }
                    missingTitle = nil
                }
            }
            if let title = missingTitle {
                let card = AssistantEngine.notFoundCard(for: title)
                messages.append(card)
                speakOrAnnounce(card.text)
                return
            }
            var multiple: [SesliKitapKaydi] = []
            if reply.action?.type == "addBooks" {
                multiple = (reply.action?.books ?? []).prefix(20).map(VoiceBookEngine.normalized).filter(\.hasBookContent)
                // Tek kitap geldiyse normal kayıt kartı kullanılır
                if multiple.count == 1 {
                    proposal = multiple[0]
                    multiple = []
                }
            }
            let hasProposal = proposal != nil || loanProposal != nil || editProposal != nil || pendingChoice != nil || !multiple.isEmpty
            var message = ChatMessage(
                role: .assistant,
                text: answer,
                bookIDs: matched.map(\.id),
                followUps: hasProposal ? [] : (reply.followUps ?? []),
                proposedBook: proposal
            )
            message.proposedLoan = loanProposal
            message.proposedEdit = editProposal
            message.proposedTargetChoice = pendingChoice
            message.proposedBooks = multiple
            message.proposedOperationIDs = multiple.map { _ in UUID() }
            message.chart = reply.chart?.sanitized
            // Yeni soru eski/başarısız taslakları silemez. Sesli onay yalnız yeni kart içindir.
            for i in messages.indices where messages[i].hasPendingProposal { messages[i].proposalNeedsReview = true }
            messages.append(message)
            if let pendingChoice { targetChoice = pendingChoice }
            speakOrAnnounce(answer)
        } catch {
            guard isCurrent(), !(error is CancellationError) else { return }
            // Bağlantı sorunu ya da aylık sınır: bilinen sorular cihazda yanıtlanır
            if YerelAsistan.shouldAnswerLocally(after: error), answerLocally() { return }
            let message = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
            messages.append(ChatMessage(role: .assistant, text: "Üzgünüm, yanıt alamadım. \(message)", isError: true))
        }
    }
}

// MARK: - Sohbet baloncuğu

private struct ChatBubble: View {
    let message: ChatMessage
    let books: [CatalogBook]
    let onBookTap: (CatalogBook) -> Void
    let onFollowUp: (String) -> Void
    var onSaveProposal: () -> Void = { }
    var isFavorite = false
    var onToggleFavorite: () -> Void = { }
    var onDismissProposal: () -> Void = { }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(bubbleColor, in: .rect(cornerRadius: 16))
                    .foregroundStyle(isUser ? .white : .primary)
                    .overlay(alignment: .topLeading) {
                        if isUser && isFavorite {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow).offset(x: -6, y: -6)
                        }
                    }
                    .contextMenu {
                        if isUser {
                            Button(isFavorite ? "Favorilerden Çıkar" : "Favorilere Ekle",
                                   systemImage: isFavorite ? "star.slash" : "star") { onToggleFavorite() }
                        }
                        Button("Kopyala", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
                    }

                if message.isOffline {
                    Label("Çevrimdışı yanıt", systemImage: "wifi.slash")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Çevrimdışı yanıt: bu cevap cihazdaki kataloğa göre hazırlandı")
                }

                if let chart = message.chart {
                    CevapGrafigi(chart: chart)
                }

                if !books.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(books) { book in
                            Button {
                                onBookTap(book)
                            } label: {
                                HStack(spacing: 8) {
                                    CoverThumb(data: book.coverData)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(book.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                        Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(book.title), \(book.author)")
                            .accessibilityHint("Kitap bilgilerini gösterir")
                        }
                    }
                }

                if message.hasPendingProposal && message.proposalNeedsReview {
                    Label("Önceki oturumdan bekleyen taslak; uygulamadan önce kartı inceleyin.", systemImage: "clock.arrow.circlepath").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let choice = message.proposedTargetChoice, !message.proposalResolved {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("İşlem için hedef seçimi bekliyor", systemImage: "person.crop.circle.badge.questionmark").font(.subheadline.weight(.semibold))
                        Text(choice.loan?.kind == "return" ? "Kitabı ve iade edilecek açık ödünç satırını seçin." : choice.loan != nil ? "Kitap baskısını ve ödünç alacak okuru seçin." : "Düzenlenecek kitap baskısını seçin.").font(.footnote)
                        Button("Hedefleri seç", systemImage: "list.bullet.rectangle") { onSaveProposal() }.buttonStyle(.borderedProminent)
                        Button("Vazgeç", role: .cancel) { onDismissProposal() }.buttonStyle(.bordered)
                    }.padding(12).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
                }
                if let loan = message.proposedLoan, !message.proposalResolved {
                    OduncOnerisiKarti(proposal: loan, onConfirm: onSaveProposal, onDismiss: onDismissProposal)
                }
                if let proposal = message.proposedBook, !message.proposalResolved {
                    KayitOnerisiKarti(kaydi: proposal, onSave: onSaveProposal, onDismiss: onDismissProposal)
                }
                if let edit = message.proposedEdit, !message.proposalResolved {
                    DuzenlemeOnerisiKarti(proposal: edit, onConfirm: onSaveProposal, onDismiss: onDismissProposal)
                }
                if !message.proposedBooks.isEmpty, !message.proposalResolved {
                    CokluKayitKarti(kayitlar: message.proposedBooks, onSave: onSaveProposal, onDismiss: onDismissProposal)
                }

                if !message.followUps.isEmpty && !isUser {
                    HStack(spacing: 6) {
                        ForEach(message.followUps, id: \.self) { question in
                            Button(question) { onFollowUp(question) }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .tint(KitapTema.amazon)
                        }
                    }
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUser ? "Siz: \(message.text)" : "Asistan: \(message.text)")
    }

    private var bubbleColor: Color {
        if message.isError { return KitapTema.vurgu.opacity(0.2) }
        return isUser ? KitapTema.ana : Color(.secondarySystemGroupedBackground)
    }
}

/// Asistanın "kitap ekle" niyetinden çıkardığı kayıt: özet + Kaydet/Vazgeç.
private struct KayitOnerisiKarti: View {
    let kaydi: SesliKitapKaydi
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Kataloğa eklensin mi?", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KitapTema.basari)
            VStack(alignment: .leading, spacing: 2) {
                Text(kaydi.title ?? "").font(.headline)
                if let author = kaydi.author { Text(author).font(.subheadline).foregroundStyle(.secondary) }
                let details = [
                    kaydi.publisher, kaydi.publicationYear, kaydi.category,
                    kaydi.isbn.map { "ISBN \($0)" },
                    (kaydi.quantity ?? 1) > 1 ? "\(kaydi.quantity ?? 1) adet" : nil,
                    [kaydi.cabinet, kaydi.shelf].compactMap { $0 }.isEmpty ? nil
                        : "Yer: " + [kaydi.cabinet, kaydi.shelf].compactMap { $0 }.joined(separator: "/")
                ].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if let uncertain = kaydi.uncertain, !uncertain.isEmpty {
                    Label("Kontrol edin: \(uncertain.map(SesliKitapKaydi.alanAdi).joined(separator: ", "))", systemImage: "questionmark.circle")
                        .font(.caption2)
                        .foregroundStyle(KitapTema.vurgu)
                }
            }
            HStack(spacing: 8) {
                Button("Vazgeç", action: onDismiss)
                    .buttonStyle(.kitapTonlu(.red))
                Button {
                    onSave()
                } label: {
                    Label("Kaydet", systemImage: "checkmark")
                }
                .buttonStyle(.kitapDolu(KitapTema.basari))
            }
            Text("Sesle de onaylayabilirsiniz: “kaydet” ya da “iptal”.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KitapTema.basari.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kayıt önerisi: \(kaydi.title ?? ""), \(kaydi.author ?? "")")
    }
}

/// Ödünç/iade onay kartı.
private struct OduncOnerisiKarti: View {
    let proposal: LoanProposal
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private var isReturn: Bool { proposal.kind == "return" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(isReturn ? "İade alınsın mı?" : "Ödünç verilsin mi?",
                  systemImage: isReturn ? "arrow.uturn.left.circle.fill" : "person.badge.clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KitapTema.amazon)
            Text(proposal.bookTitle).font(.headline)
            if !proposal.person.isEmpty {
                Label(proposal.person + (proposal.className.map { " (\($0))" } ?? ""), systemImage: "person")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Vazgeç", action: onDismiss).buttonStyle(.kitapTonlu(.red))
                Button(action: onConfirm) {
                    Label(isReturn ? "İade Al" : "Ödünç Ver", systemImage: "checkmark")
                }
                .buttonStyle(.kitapDolu(KitapTema.amazon))
                .disabled(!isReturn && proposal.person.isEmpty)
            }
            Text("Sesle de onaylayabilirsiniz: “tamam” ya da “iptal”.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KitapTema.amazon.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

private struct ThinkingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Asistan düşünüyor…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .accessibilityLabel("Asistan yanıt hazırlıyor")
    }
}

/// Küçük kapak görseli (yoksa simge).
struct CoverThumb: View {
    let data: Data?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(KitapTema.ana.opacity(0.6))
            }
        }
        .frame(width: size, height: size * 1.4)
        .background(KitapTema.ana.opacity(0.1))
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

// MARK: - Kitap bilgi sayfası

struct AIBookInfoSheet: View {
    let book: CatalogBook
    let loans: [ActiveLoan]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        CoverThumb(data: book.coverData, size: 70)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.title3.weight(.semibold))
                            Text(book.author).foregroundStyle(.secondary)
                            if let category = book.category, !category.isEmpty {
                                Text(category)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(KitapTema.ana.opacity(0.12), in: .capsule)
                                    .foregroundStyle(KitapTema.ana)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Section("Durum") {
                    let free = LoanAvailability.availableCopies(for: book, activeLoans: loans)
                    LabeledContent("Nüsha", value: "\(book.quantity ?? 1)")
                    LabeledContent("Boşta", value: "\(free)")
                        .foregroundStyle(free > 0 ? KitapTema.basari : KitapTema.vurgu)
                    if let place = [book.cabinet, book.shelf].compactMap({ $0 }).filter({ !$0.isEmpty }).joined(separator: " / ").nilIfEmpty {
                        LabeledContent("Yer", value: place)
                    }
                    if let code = book.accessionCode, !code.isEmpty {
                        LabeledContent("Demirbaş", value: code)
                    }
                }
                Section("Künye") {
                    if let publisher = book.publisher, !publisher.isEmpty { LabeledContent("Yayınevi", value: publisher) }
                    if let year = book.publicationYear, !year.isEmpty { LabeledContent("Yıl", value: year) }
                    if let isbn = book.isbn, !isbn.isEmpty { LabeledContent("ISBN", value: isbn) }
                    if let pages = book.pageCount, !pages.isEmpty { LabeledContent("Sayfa", value: pages) }
                    if let language = book.language, !language.isEmpty { LabeledContent("Dil", value: language) }
                }
                if !book.notes.isEmpty {
                    Section("Notlar / Özet") {
                        Text(book.notes)
                    }
                }
            }
            .navigationTitle("Kitap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
    }
}

extension String {
    /// Boş dizeyi `nil` yapar; `if let` zincirlerini sadeleştirir.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Veri paylaşım onayı

/// İlk kullanımda bir kez sorulur: sorular, katalog özeti ve fotoğraflar Google Gemini'ye
/// gönderilir. Onay verilmeden hiçbir yapay zekâ isteği çıkmaz (App Store 5.1.2, KVKK).
/// Uygulamada TEK yerde (sekme kabuğu) uygulanır; birden çok görünüm aynı anda uyarı
/// açmaya kalkarsa iOS ikisini de düşürür ve kullanıcı hiçbirini göremez.
struct GeminiConsentGate: ViewModifier {
    /// Kullanıcı yapay zekâ sekmelerinden birine geçtiğinde `true` olur.
    var isRelevant: Bool

    @AppStorage(GeminiSettings.consentKey) private var consentGiven = false
    @AppStorage(GeminiSettings.enabledKey) private var aiEnabled = true
    @State private var isAsking = false
    @State private var askerID = UUID()
    /// Aynı anda yalnız bir kapı uyarı açar (kabuktaki ve AIToolsView içindeki kapı çakışmasın).
    private static var activeAsker: UUID?

    static let alertTitle = "Yapay zekâ veri paylaşımı"
    static let alertMessage =
        "Asistan soruları, katalog özeti (kitap adları, sayılar, sınıf bilgisi) ve taranan kitap "
        + "fotoğrafları işlenmek üzere Google Gemini servisine gönderilir. Öğrenci ve üye adları "
        + "gönderilmez; takma adla iletilir ve yalnızca bu cihazda gerçek ada çevrilir. "
        + "Onayı Ayarlar > Yapay Zekâ bölümünden istediğiniz zaman geri alabilirsiniz."

    func body(content: Content) -> some View {
        content
            .onAppear { askIfNeeded() }
            .onChange(of: isRelevant) { askIfNeeded() }
            .onChange(of: isAsking) { _, asking in
                if !asking, Self.activeAsker == askerID { Self.activeAsker = nil }
            }
            .alert(Self.alertTitle, isPresented: $isAsking) {
                Button("Kabul Ediyorum") { consentGiven = true }
                Button("Şimdi Değil", role: .cancel) { }
            } message: {
                Text(Self.alertMessage)
            }
    }

    private func askIfNeeded() {
        guard isRelevant, aiEnabled, !consentGiven else { return }
        guard Self.activeAsker == nil || Self.activeAsker == askerID else { return }
        Self.activeAsker = askerID
        isAsking = true
    }
}

extension View {
    func geminiConsentGate(isRelevant: Bool) -> some View { modifier(GeminiConsentGate(isRelevant: isRelevant)) }
}


/// Boş sohbette renkli öneri kartları: dokununca soru gönderilir.
private struct OneriKartlari: View {
    let gonder: (String) -> Void

    private let oneriler: [(String, String, Color)] = [
        ("Geciken ödünç var mı?", "exclamationmark.circle.fill", .red),
        ("5. sınıfa macera kitabı öner", "sparkles", KitapTema.foto),
        ("Kategorilere göre kitap sayısı", "chart.bar.fill", KitapTema.dosya),
        ("Şunları ekle: Simyacı, Küçük Prens", "plus.circle.fill", KitapTema.basari),
        ("Kuyucaklı Yusuf iade edildi", "arrow.uturn.left.circle.fill", KitapTema.amazon),
        ("Nutuk'u B dolabına taşı", "arrow.right.square.fill", KitapTema.vurgu)
    ]

    var body: some View {
        // Tembel olmayan ızgara: ilk çizimde kartların metni ölçülmeden kırpılmasın
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(0..<(oneriler.count + 1) / 2, id: \.self) { satir in
                GridRow {
                    ForEach(oneriler[(satir * 2)..<min(satir * 2 + 2, oneriler.count)], id: \.0) { oneri in
                        kart(oneri)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func kart(_ oneri: (String, String, Color)) -> some View {
        Group {
                Button { gonder(oneri.0) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: oneri.1)
                            .font(.title2)
                            .foregroundStyle(oneri.2)
                            .symbolEffect(.bounce, options: .nonRepeating, value: oneri.0)
                        Text(oneri.0)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .background(oneri.2.opacity(0.12), in: .rect(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(oneri.2.opacity(0.3)))
                }
                .buttonStyle(.kitapSade)
                .accessibilityHint("Bu soruyu asistana gönderir")
        }
    }
}
