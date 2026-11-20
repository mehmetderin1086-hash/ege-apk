import CryptoKit
import Foundation
import Observation

/// Kitap indirmesinden bağımsız saklanan sayfa notu veya yer imi.
nonisolated struct BookStudyNote: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var bookID: String
    var title: String
    var page: Int
    var quote: String
    var note: String
    var isBookmark: Bool
    var createdAt: Date
    var updatedAt: Date
    var subject: String? = nil
    var concept: String? = nil

    var learningTopic: String { concept.flatMap { $0.isEmpty ? nil : $0 } ?? title }
    var contentVersion: String {
        let value = [bookID, String(page), quote, note].map { String($0.utf8.count) + ":" + $0 }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init(id: UUID = UUID(), bookID: String, title: String, page: Int, quote: String = "", note: String = "",
         isBookmark: Bool = false, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.bookID = bookID; self.title = title; self.page = page
        self.quote = quote; self.note = note; self.isBookmark = isBookmark
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Uzun metin sessizce kesilmez: kullanıcı düzenleyebilsin diye kaydetme reddedilir.
    func validated() throws -> Self {
        var value = self
        value.bookID = bookID.trimmingCharacters(in: .whitespacesAndNewlines)
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.subject = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.concept = concept?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (value.subject?.count ?? 0) <= 120, (value.concept?.count ?? 0) <= 300 else { throw BookStudyError.invalid("Ders en fazla 120, konu en fazla 300 karakter olabilir.") }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !value.bookID.isEmpty, value.bookID.count <= 128,
              value.bookID.unicodeScalars.allSatisfy(allowed.contains),
              value.bookID != ".", value.bookID != ".." else { throw BookStudyError.invalid("Kitap kimliği geçerli değil.") }
        guard !value.title.isEmpty, value.title.count <= 300 else { throw BookStudyError.invalid("Kitap adı 1–300 karakter olmalı.") }
        guard (1...100_000).contains(page) else { throw BookStudyError.invalid("Geçerli bir sayfa numarası seç.") }
        guard value.quote.count <= 12_000, value.note.count <= 12_000 else { throw BookStudyError.invalid("Alıntı ve not ayrı ayrı en fazla 12.000 karakter olabilir.") }
        guard value.isBookmark || !value.quote.isEmpty || !value.note.isEmpty else { throw BookStudyError.invalid("Bir alıntı veya not yaz.") }
        guard createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite else {
            throw BookStudyError.invalid("Notun tarihi geçerli değil.")
        }
        return value
    }
}

nonisolated enum BookStudyError: LocalizedError {
    case invalid(String), unreadable, writeFailed(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .unreadable: "Kitap notları okunamadı. Mevcut dosya korundu; notlar yeniden okunana kadar değişiklik kaydedilemez."
        case .writeFailed(let detail): "Kitap notları kaydedilemedi. Önceki kayıtlar korundu. " + detail
        }
    }
}

/// Tek paylaşılan depo; değişiklik ancak diske başarıyla yazıldıktan sonra görünür olur.
@MainActor @Observable final class BookStudyStore {
    static let shared = BookStudyStore()
    private(set) var entries: [BookStudyNote] = []
    private(set) var loadError: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var restoreObserver: (any NSObjectProtocol)?

    nonisolated static let maximumBytes = 32 * 1024 * 1024
    nonisolated static let maximumEntries = 20_000

    init(url: URL = JSONStoreLocation.defaultDirectory.appending(path: "book-study.json")) {
        self.url = url
        do { try reload() } catch { /* reload exposes the error without replacing the file. */ }
        restoreObserver = NotificationCenter.default.addObserver(forName: JSONStoreLocation.restored, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.reload() }
        }
    }

    isolated deinit {
        if let restoreObserver { NotificationCenter.default.removeObserver(restoreObserver) }
    }

    func reload() throws {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maximumBytes else { throw BookStudyError.unreadable }
                let loaded = try Self.decode(Data(contentsOf: url))
                entries = loaded
            } else { entries = [] }
            loadError = nil
        } catch {
            loadError = BookStudyError.unreadable.localizedDescription
            throw BookStudyError.unreadable
        }
    }

    func notes(for bookID: String) -> [BookStudyNote] {
        entries.filter { $0.bookID == bookID }.sorted {
            $0.page != $1.page ? $0.page < $1.page : $0.createdAt < $1.createdAt
        }
    }

    func save(_ entry: BookStudyNote) throws {
        try requireReadable()
        var value = try entry.validated()
        var next = entries
        if let index = next.firstIndex(where: { $0.id == value.id }) {
            value.createdAt = next[index].createdAt
            value.updatedAt = max(.now, next[index].updatedAt.addingTimeInterval(0.001))
            next[index] = value
        } else {
            value.updatedAt = max(value.createdAt, .now)
            next.append(value)
        }
        try commit(next)
    }

    func delete(id: UUID) throws {
        try requireReadable()
        guard entries.contains(where: { $0.id == id }) else { return }
        try commit(entries.filter { $0.id != id })
    }

    func isBookmarked(bookID: String, page: Int) -> Bool {
        entries.contains { $0.bookID == bookID && $0.page == page && $0.isBookmark }
    }

    func toggleBookmark(bookID: String, title: String, page: Int) throws {
        try requireReadable()
        if isBookmarked(bookID: bookID, page: page) {
            // Yer imi kaldırılırken aynı kayıtta bulunan kullanıcının notunu koru.
            let next = entries.compactMap { entry -> BookStudyNote? in
                guard entry.bookID == bookID, entry.page == page, entry.isBookmark else { return entry }
                guard !entry.quote.isEmpty || !entry.note.isEmpty else { return nil }
                var value = entry; value.isBookmark = false
                value.updatedAt = max(.now, entry.updatedAt.addingTimeInterval(0.001))
                return value
            }
            try commit(next)
        } else { try save(BookStudyNote(bookID: bookID, title: title, page: page, isBookmark: true)) }
    }

    private func requireReadable() throws {
        if loadError != nil { throw BookStudyError.unreadable }
    }

    private func commit(_ values: [BookStudyNote]) throws {
        let data = try Self.encode(values)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch { throw BookStudyError.writeFailed(error.localizedDescription) }
        entries = values
    }

    /// MEB anahtarının model göçü gerektirmeyen, değişmeyen kart grubu kimliği (UUID v8).
    nonisolated static func sourceID(for bookID: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("com.mehmetderin.derspodcast.book-source:" + bookID).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    nonisolated static func decode(_ data: Data) throws -> [BookStudyNote] {
        guard data.count <= maximumBytes else { throw BookStudyError.unreadable }
        let records = try JSONDecoder().decode([BookStudyNote].self, from: data)
        guard records.count <= maximumEntries, Set(records.map(\.id)).count == records.count else { throw BookStudyError.unreadable }
        return try records.map { try $0.validated() }
    }

    nonisolated static func encode(_ records: [BookStudyNote]) throws -> Data {
        guard records.count <= maximumEntries, Set(records.map(\.id)).count == records.count else {
            throw BookStudyError.invalid("Kitap notu sınırına ulaşıldı veya aynı kayıt yinelendi.")
        }
        let clean = try records.map { try $0.validated() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(clean)
        guard data.count <= maximumBytes else { throw BookStudyError.invalid("Kitap notları 32 MB sınırını aşıyor.") }
        return data
    }

    nonisolated struct MergeResult: Sendable { var data: Data; var changed: Int }

    /// Kimlikler birleşir; aynı notun yalnız daha yeni düzenlemesi alınır. Eşit tarihte cihazdaki kalır.
    nonisolated static func merge(existing: Data, incoming: Data) throws -> MergeResult {
        var current = try decode(existing)
        let incoming = try decode(incoming)
        var indices = Dictionary(uniqueKeysWithValues: current.enumerated().map { ($1.id, $0) })
        var changed = 0
        for note in incoming {
            if let index = indices[note.id] {
                if note.updatedAt > current[index].updatedAt { current[index] = note; changed += 1 }
            } else {
                indices[note.id] = current.count; current.append(note); changed += 1
            }
        }
        return MergeResult(data: try encode(current), changed: changed)
    }

    /// Genel yedek birleştirmesinin eski notları düşürmediğini veya geriye almadığını doğrular.
    nonisolated static func mergeIsSafe(existing: Data, merged: Data) -> Bool {
        guard let before = try? decode(existing), let after = try? decode(merged) else { return false }
        let byID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        guard before.allSatisfy({ old in
            guard let new = byID[old.id] else { return false }
            return new == old || new.updatedAt > old.updatedAt
        }) else { return false }
        return after != before
    }
}
