import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Katalogdaki kitapları telefonun Spotlight aramasına (ekranı sağa kaydırıp arama)
/// kaydeder. `CatalogBackup.saveLight` her çağrıldığında (ki bu, uygulamadaki tüm
/// kayıt/silme/toplu işlem noktalarında zaten yapılıyor) tetiklenir — tek merkezden
/// tüm akışları kapsar, ayrıca her fonksiyona tek tek dokunmaya gerek kalmaz.
enum SpotlightIndexer {
    private static let domainIdentifier = "com.mehmetderin.kitapbul.books"

    struct Entry: Sendable, Equatable {
        let id: String
        let title: String
        let author: String
        let isbn: String
        let isWithdrawn: Bool
    }

    /// Süreç ömründe ilk çağrı tam indeks, sonrakiler yalnız değişenleri günceller.
    private static var tamIndeksYapildi = false

    struct Fark: Equatable {
        var eklenecek: [Entry]
        var silinecek: [String]
    }

    /// Kararlı (süreçler arası değişmeyen) özet: FNV-1a.
    nonisolated static func ozet(_ entry: Entry) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(entry.title)\u{1F}\(entry.author)\u{1F}\(entry.isbn)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return hash
    }

    nonisolated static func gorunur(_ entries: [Entry]) -> [Entry] {
        entries.filter { !$0.isWithdrawn && !$0.title.isEmpty }
    }

    /// Son indekslenen (id → özet) durumuna göre eklenecek/değişen ve silinecek kimlikleri bulur.
    nonisolated static func fark(eski: [String: UInt64], yeni entries: [Entry]) -> Fark {
        let visible = gorunur(entries)
        let ids = Set(visible.map(\.id))
        let eklenecek = visible.filter { eski[$0.id] != ozet($0) }
        let silinecek = eski.keys.filter { !ids.contains($0) }.sorted()
        return Fark(eklenecek: eklenecek, silinecek: silinecek)
    }

    private static var durumURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SpotlightDurumu.json")
    }

    private static func durumOku() -> [String: UInt64]? {
        guard let durumURL, let data = try? Data(contentsOf: durumURL) else { return nil }
        return try? JSONDecoder().decode([String: UInt64].self, from: data)
    }

    private static func durumYaz(_ durum: [String: UInt64]) {
        guard let durumURL else { return }
        try? FileManager.default.createDirectory(at: durumURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(durum) { try? data.write(to: durumURL, options: .atomic) }
    }

    private static func ogeler(_ entries: [Entry]) -> [CSSearchableItem] {
        entries.map { entry -> CSSearchableItem in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            attributes.title = entry.title
            attributes.contentDescription = [entry.author, entry.isbn]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            attributes.keywords = [entry.title, entry.author, entry.isbn].filter { !$0.isEmpty }
            return CSSearchableItem(
                uniqueIdentifier: entry.id,
                domainIdentifier: domainIdentifier,
                attributeSet: attributes
            )
        }
    }

    static func reindex(_ entries: [Entry]) {
        let index = CSSearchableIndex.default()
        let visible = gorunur(entries)
        let yeniDurum = Dictionary(visible.map { ($0.id, ozet($0)) }, uniquingKeysWith: { _, son in son })
        let bozulmaYolu = durumURL

        // Bozuk/eksik durum dosyası ya da ilk çağrı: tam yeniden indeks.
        guard tamIndeksYapildi, let eski = durumOku() else {
            tamIndeksYapildi = true
            durumYaz(yeniDurum)
            let items = ogeler(visible)
            index.deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in
                index.indexSearchableItems(items) { hata in
                    if hata != nil, let bozulmaYolu { try? FileManager.default.removeItem(at: bozulmaYolu) }
                }
            }
            return
        }

        let degisim = fark(eski: eski, yeni: entries)
        guard !degisim.eklenecek.isEmpty || !degisim.silinecek.isEmpty else { return }
        durumYaz(yeniDurum)
        let items = ogeler(degisim.eklenecek)
        let tamamla: @Sendable (Error?) -> Void = { hata in
            if hata != nil, let bozulmaYolu { try? FileManager.default.removeItem(at: bozulmaYolu) }
        }
        if degisim.silinecek.isEmpty {
            index.indexSearchableItems(items, completionHandler: tamamla)
        } else {
            index.deleteSearchableItems(withIdentifiers: degisim.silinecek) { hata in
                tamamla(hata)
                if !items.isEmpty { index.indexSearchableItems(items, completionHandler: tamamla) }
            }
        }
    }
}
