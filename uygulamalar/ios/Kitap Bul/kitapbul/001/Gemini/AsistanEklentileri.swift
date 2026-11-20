import Foundation
import SwiftUI
import SwiftData
import Charts

// MARK: - Kitap düzenleme niyeti (düş, taşı, durum, kategori, adet)

nonisolated struct BookEditIntent: Codable, Sendable, Equatable {
    var bookTitle: String?
    var withdraw: Bool?
    var withdrawReason: String?
    var cabinet: String?
    var shelf: String?
    var readingStatus: String?
    var category: String?
    var quantity: Int?

    /// Uygulanacak en az bir değişiklik var mı?
    var hasChange: Bool {
        withdraw == true || [cabinet, shelf, readingStatus, category].contains { !($0 ?? "").isEmpty } || quantity != nil
    }

    /// Kartta ve onayda gösterilecek değişiklik satırları.
    var changeLines: [String] {
        var lines: [String] = []
        if withdraw == true { lines.append("Koleksiyondan düş" + ((withdrawReason ?? "").isEmpty ? "" : " (\(withdrawReason ?? ""))")) }
        if let cabinet, !cabinet.isEmpty { lines.append("Dolap → \(cabinet)") }
        if let shelf, !shelf.isEmpty { lines.append("Raf → \(shelf)") }
        if let readingStatus, !readingStatus.isEmpty { lines.append("Durum → \(readingStatus)") }
        if let category, !category.isEmpty { lines.append("Kategori → \(category)") }
        if let quantity { lines.append("Adet → \(quantity)") }
        return lines
    }
}

nonisolated struct EditProposal: Codable, Sendable, Equatable {
    var bookID: UUID
    var bookTitle: String
    var intent: BookEditIntent
}

enum BookEditEngine {
    static let readingStatuses = ["Okunacak", "Okunuyor", "Okundu"]

    /// Onaylanan düzenlemeyi uygular ve sesli okunacak özet döndürür.
    static func apply(_ intent: BookEditIntent, to book: CatalogBook, context: ModelContext) throws -> String {
        guard YetkiDurumu.shared.yonetici else { throw CatalogSaveEngine.SaveError(message: "Kitap düzenlemek için yönetici kilidini açın.") }
        let previous = book.book
        if let quantity = intent.quantity,
           max(1, min(9999, quantity)) < SchoolLibraryService.minimumQuantity(for: book, context: context) {
            throw CatalogSaveEngine.SaveError(message: "Adet, ödünç veya demirbaş sayısının altına düşürülemez.")
        }
        if intent.withdraw == true {
            let state = SchoolLibraryService.stock(for: book, context: context)
            guard state.loaned == 0, state.reserved == 0 else {
                throw CatalogSaveEngine.SaveError(message: "Ödünç/rezervasyon kapanmadan eser koleksiyondan düşülemez.")
            }
        }
        if intent.withdraw == true {
            book.isWithdrawn = true
            book.withdrawnReason = (intent.withdrawReason ?? "").isEmpty ? "Asistanla düşüldü" : intent.withdrawReason
            book.withdrawnDate = .now
        }
        if let cabinet = intent.cabinet, !cabinet.isEmpty { book.cabinet = cabinet }
        if let shelf = intent.shelf, !shelf.isEmpty { book.shelf = shelf }
        if let status = intent.readingStatus, readingStatuses.contains(status) { book.readingStatus = status }
        if let category = intent.category, !category.isEmpty {
            book.category = category
            book.refreshSearchKey()
        }
        if let quantity = intent.quantity { book.quantity = max(1, min(9999, quantity)) }
        book.update(from: BookFieldMetadata.stampChanges(before: previous, after: book.book, source: "manual"))
        do { try context.save() }
        catch { book.update(from: previous); throw error }
        AppLog.write("Asistan düzenlemesi uygulandı")
        return "“\(book.title)” güncellendi: " + intent.changeLines.joined(separator: ", ") + "."
    }
}

// MARK: - Yanıtta grafik

nonisolated struct AssistantChart: Codable, Sendable, Equatable {
    struct Bar: Codable, Sendable, Equatable {
        var label: String
        var value: Double
    }

    var title: String?
    var bars: [Bar]

    /// Anlamsız grafikler gösterilmez: 2–12 çubuk, negatif/boş değer yok.
    var sanitized: AssistantChart? {
        let clean = bars
            .filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty && $0.value.isFinite && $0.value >= 0 }
            .prefix(12)
        guard clean.count >= 2 else { return nil }
        return AssistantChart(title: title, bars: Array(clean))
    }
}

struct CevapGrafigi: View {
    let chart: AssistantChart

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title = chart.title, !title.isEmpty {
                Text(title).font(.caption.weight(.semibold))
            }
            Chart(Array(chart.bars.enumerated()), id: \.offset) { _, bar in
                BarMark(x: .value("Değer", bar.value), y: .value("Ad", bar.label))
                    .foregroundStyle(KitapTema.ana.gradient)
                    .annotation(position: .trailing) {
                        Text(bar.value.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(chart.bars.count) * 28 + 10)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((chart.title ?? "Grafik") + ": " + chart.bars.map { "\($0.label) \(Int($0.value))" }.joined(separator: ", "))
    }
}

// MARK: - Sohbet geçmişi ve favoriler

nonisolated struct StoredChatMessage: Codable, Equatable {
    var isUser: Bool
    var text: String
    var date: Date
    // Optional alanlar eski metin-only geçmiş dosyalarıyla uyumludur.
    var id: UUID? = nil
    var bookIDs: [UUID]? = nil
    var proposedBook: SesliKitapKaydi? = nil
    var proposedBooks: [SesliKitapKaydi]? = nil
    var proposedOperationIDs: [UUID]? = nil
    var proposedLoan: LoanProposal? = nil
    var proposedEdit: EditProposal? = nil
    var proposedTargetChoice: AssistantTargetChoice? = nil
    var proposalResolved: Bool? = nil
}

@MainActor
extension StoredChatMessage {
    init(_ message: ChatMessage) {
        isUser = message.role == .user; text = message.text; date = message.date
        id = message.id; bookIDs = message.bookIDs
        proposalResolved = message.proposalResolved
        if !message.proposalResolved {
            proposedBook = message.proposedBook; proposedBooks = message.proposedBooks
            proposedOperationIDs = message.proposedOperationIDs
            proposedLoan = message.proposedLoan; proposedEdit = message.proposedEdit
            proposedTargetChoice = message.proposedTargetChoice
        }
    }
    var message: ChatMessage {
        var result = ChatMessage(role: isUser ? .user : .assistant, text: text)
        result.id = id ?? UUID(); result.date = date; result.bookIDs = bookIDs ?? []
        result.proposedBook = proposedBook; result.proposedBooks = proposedBooks ?? []
        result.proposedOperationIDs = proposedOperationIDs ?? []
        result.proposedLoan = proposedLoan; result.proposedEdit = proposedEdit
        result.proposedTargetChoice = proposedTargetChoice
        result.proposalResolved = proposalResolved ?? false
        result.proposalNeedsReview = result.hasPendingProposal
        return result
    }
}

enum ChatHistoryStore {
    static let maxMessages = 100
    static var fileOverride: URL?
    private static var file: URL? {
        if let fileOverride { return fileOverride }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AsistanGecmisi.json")
    }
    static func save(_ messages: [ChatMessage]) {
        do { try saveVerified(messages) } catch { AppLog.write("Asistan taslakları diske yazılamadı") }
    }
    /// Başarısız veya onay bekleyen kayıtlar geçmiş sınırı yüzünden atılmaz.
    static func saveVerified(_ messages: [ChatMessage]) throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        let recentIDs = Set(messages.filter { !$0.isError && !$0.hasPendingProposal }.suffix(maxMessages).map(\.id))
        let stored = messages.filter { $0.hasPendingProposal || recentIDs.contains($0.id) }.map(StoredChatMessage.init)
        let ids = stored.compactMap(\.id)
        guard Set(ids).count == ids.count else { throw CocoaError(.fileWriteInvalidFileName) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(stored).write(to: file, options: .atomic)
    }
    static func load() -> [StoredChatMessage] { (try? loadVerified()) ?? [] }
    static func loadVerified() throws -> [StoredChatMessage] {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let stored = try decoder.decode([StoredChatMessage].self, from: Data(contentsOf: file))
        let ids = stored.compactMap(\.id)
        guard Set(ids).count == ids.count else { throw CocoaError(.fileReadCorruptFile) }
        return stored
    }
    static func clear() { do { try clearVerified() } catch { AppLog.write("Asistan geçmişi silinemedi") } }
    static func clearVerified() throws {
        guard let file else { throw CocoaError(.fileNoSuchFile) }
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

enum FavoritePromptStore {
    private static let key = "assistantFavoritePrompts"
    static let limit = 12

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func contains(_ prompt: String) -> Bool {
        all().contains(prompt)
    }

    static func toggle(_ prompt: String) {
        var list = all()
        if let index = list.firstIndex(of: prompt) {
            list.remove(at: index)
        } else {
            list.insert(prompt, at: 0)
        }
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }
}

// MARK: - Asistan dili (çok dilli kiosk)

enum AsistanDili: String, CaseIterable, Identifiable {
    case turkce = "tr-TR"
    case ingilizce = "en-US"
    case almanca = "de-DE"
    case arapca = "ar-SA"
    case rusca = "ru-RU"
    case fransizca = "fr-FR"

    static let key = "assistantLanguage"

    var id: String { rawValue }

    var ad: String {
        switch self {
        case .turkce: "Türkçe"
        case .ingilizce: "English"
        case .almanca: "Deutsch"
        case .arapca: "العربية"
        case .rusca: "Русский"
        case .fransizca: "Français"
        }
    }

    /// Gemini'ye yanıt dili talimatı
    var promptAdi: String {
        switch self {
        case .turkce: "Türkçe"
        case .ingilizce: "İngilizce"
        case .almanca: "Almanca"
        case .arapca: "Arapça"
        case .rusca: "Rusça"
        case .fransizca: "Fransızca"
        }
    }

    static var current: AsistanDili {
        AsistanDili(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .turkce
    }
}

// MARK: - Onay kartları

struct DuzenlemeOnerisiKarti: View {
    let proposal: EditProposal
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(proposal.intent.withdraw == true ? "Koleksiyondan düşülsün mü?" : "Kitap güncellensin mi?",
                  systemImage: proposal.intent.withdraw == true ? "archivebox.fill" : "pencil.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(proposal.intent.withdraw == true ? KitapTema.vurgu : KitapTema.dosya)
            Text(proposal.bookTitle).font(.headline)
            ForEach(proposal.intent.changeLines, id: \.self) { line in
                Label(line, systemImage: "arrow.right.circle").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button("Vazgeç", action: onDismiss).buttonStyle(.kitapTonlu(.red))
                Button(action: onConfirm) { Label("Uygula", systemImage: "checkmark") }
                    .buttonStyle(.kitapDolu(KitapTema.dosya))
            }
            Text("Sesle de onaylayabilirsiniz: “tamam” ya da “iptal”.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KitapTema.dosya.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// Tek seferde dikte edilen birden çok kitap: liste + "Hepsini Kaydet".
struct CokluKayitKarti: View {
    let kayitlar: [SesliKitapKaydi]
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(kayitlar.count) kitap eklensin mi?", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KitapTema.basari)
            ForEach(Array(kayitlar.enumerated()), id: \.offset) { index, kaydi in
                HStack(alignment: .top) {
                    Text("\(index + 1).").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(kaydi.title ?? "").font(.subheadline.weight(.semibold))
                        Text([kaydi.author, (kaydi.quantity ?? 1) > 1 ? "\(kaydi.quantity ?? 1) adet" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !(kaydi.uncertain ?? []).isEmpty {
                        Image(systemName: "questionmark.circle").foregroundStyle(KitapTema.vurgu)
                            .accessibilityLabel("Kontrol edilecek alan var")
                    }
                }
            }
            HStack(spacing: 8) {
                Button("Vazgeç", action: onDismiss).buttonStyle(.kitapTonlu(.red))
                Button(action: onSave) { Label("Hepsini Kaydet", systemImage: "checkmark") }
                    .buttonStyle(.kitapDolu(KitapTema.basari))
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(KitapTema.basari.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
