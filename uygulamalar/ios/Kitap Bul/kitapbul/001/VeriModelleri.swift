import Foundation
import SwiftData

// MARK: - Nüsha (tek tek demirbaş takibi)

/// Bir kitabın tek bir fiziksel nüshası: kendi demirbaş kodu, durumu (yeni/yıpranmış…)
/// ve dolaşım durumu (rafta/onarımda/kayıp). Nüsha kaydı olmayan kitaplar eskisi gibi
/// yalnız `quantity` ile sayılır.
@Model
final class BookCopy {
    var id: UUID = UUID()
    var bookID: UUID = UUID()
    var accessionCode: String = ""
    /// "Yeni" | "İyi" | "Yıpranmış" | "Onarım gerekli"
    var condition: String = "İyi"
    /// "Rafta" | "Onarımda" | "Kayıp" | "Düşüldü"
    var status: String = "Rafta"
    var note: String = ""
    var addedAt: Date = Date.now
    var cabinet: String? = nil
    var shelf: String? = nil

    static let conditions = ["Yeni", "İyi", "Yıpranmış", "Onarım gerekli"]
    static let statuses = ["Rafta", "Onarımda", "Kayıp", "Düşüldü"]

    /// Ödünç verilebilir mi? (kayıp/onarımda/düşülmüş nüshalar sayılmaz)
    var isCirculating: Bool { status == "Rafta" }

    func effectiveCabinet(for book: CatalogBook) -> String? { cabinet ?? book.cabinet }
    func effectiveShelf(for book: CatalogBook) -> String? { shelf ?? book.shelf }
    func effectivePlace(for book: CatalogBook) -> String {
        if cabinet == nil && shelf == nil, let place = book.location, !place.isEmpty { return place }
        return Self.place(cabinet: effectiveCabinet(for: book), shelf: effectiveShelf(for: book))
    }
    /// "Dolap 3 · Raf 2"; biçim tek kaynaktan (`CatalogBook.konumMetni`) gelir, boşsa "".
    static func place(cabinet: String?, shelf: String?) -> String {
        CatalogBook.konumMetni(yer: nil, dolap: cabinet, raf: shelf) ?? ""
    }
    /// Ayraç " • " iken kaydedilmiş yer metni (sayım oturumu ve anlık görüntüsü) bugünkü " · " biçimine çevrilir.
    static func eskiAyraciCevir(_ yer: String) -> String {
        yer.replacingOccurrences(of: " • ", with: " · ")
    }

    init(bookID: UUID, accessionCode: String = "", condition: String = "İyi", status: String = "Rafta", note: String = "", cabinet: String? = nil, shelf: String? = nil) {
        self.id = UUID()
        self.bookID = bookID
        self.accessionCode = accessionCode
        self.condition = condition
        self.status = status
        self.note = note
        self.addedAt = .now
        self.cabinet = cabinet; self.shelf = shelf
    }
}

// MARK: - Rezervasyon / bekleme listesi

/// Ödünçteki bir kitap için sıra. Kitap iade edilince sıradaki kişiye bildirim gider.
@Model
final class Reservation {
    var id: UUID = UUID()
    var bookID: UUID = UUID()
    var bookTitleSnapshot: String = ""
    var studentName: String = ""
    var studentClass: String = ""
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    /// student / member / manual / legacy: kişi türü ad metninden tahmin edilmez.
    var identitySource: String? = nil
    var studentNumberSnapshot: String? = nil
    var copyID: UUID? = nil
    var expiresAt: Date? = nil
    var needsIdentityReview: Bool = false
    var createdAt: Date = Date.now
    /// Kitap iade edilip kişiye haber verildiyse
    var notifiedAt: Date?
    /// Kişi kitabı aldıysa/vazgeçtiyse sıradan düşer
    var isClosed: Bool = false
    var closureKind: String? = nil
    var closedAt: Date? = nil

    var stateLabel: String {
        if !isClosed { return notifiedAt == nil ? "Sırada" : "Teslim için ayrıldı" }
        switch closureKind {
        case "delivered": return "Teslim edildi"
        case "cancelled": return "İptal edildi"
        case "expired": return "Ayırma süresi doldu"
        default: return "Eski kapalı kayıt — nedeni bilinmiyor"
        }
    }

    init(bookID: UUID, bookTitleSnapshot: String, studentName: String, studentClass: String) {
        self.id = UUID()
        self.bookID = bookID
        self.bookTitleSnapshot = bookTitleSnapshot
        self.studentName = studentName
        self.studentClass = studentClass
        self.createdAt = .now
    }
}

// MARK: - Şema sürüm planı

/// Veritabanı şemasının sürümü. İleride bir alan yeniden adlandırılır ya da tip değişirse
/// yeni bir `KitapSemasiV2` ve özel geçiş adımı eklenir; böylece katalog açılamayıp boş
/// gelmez. Yalnız alan EKLEMEK (isteğe bağlı/varsayılanlı) hafif geçişle kendiliğinden olur.
enum KitapSemasiV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [CatalogBook.self, ActiveLoan.self, BookCopy.self, Reservation.self, ScanWriteReceipt.self, LibraryEventOutbox.self, CatalogMergeUndoRecord.self]
    }
}

enum KitapGocPlani: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [KitapSemasiV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Uygulamanın tüm modelleri (kap oluşturma, testler ve Siri kısayolları için tek kaynak).
enum KitapVeritabani {
    static var schema: Schema { Schema(versionedSchema: KitapSemasiV1.self) }

    /// Uygulama ve Siri kısayolları aynı kabı kullanır (MyApp açılışta atar). Yalnız ana aktörden
    /// okunur/yazılır; önceki `nonisolated(unsafe)` veri yarışına açık kapı bırakıyordu.
    @MainActor static var shared: ModelContainer?

    static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let url {
            configuration = ModelConfiguration(schema: schema, url: url)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        return try ModelContainer(for: schema, migrationPlan: KitapGocPlani.self, configurations: [configuration])
    }
}
