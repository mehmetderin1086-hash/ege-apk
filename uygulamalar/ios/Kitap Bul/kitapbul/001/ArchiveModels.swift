import Foundation
import SwiftData

nonisolated struct ArchiveManifest: Codable {
    var version: Int
    var hashes: [String: String]
}

nonisolated struct ArchivedCopy: Codable, Equatable {
    var id: UUID
    var bookID: UUID
    var accessionCode: String
    var condition: String
    var status: String
    var note: String
    var addedAt: Date
    var cabinet: String? = nil
    var shelf: String? = nil
}

nonisolated struct ArchivedReservation: Codable, Equatable {
    var id: UUID
    var bookID: UUID
    var bookTitleSnapshot: String
    var studentName: String
    var studentClass: String
    var createdAt: Date
    var notifiedAt: Date?
    var isClosed: Bool
    var studentID: UUID?
    var memberID: UUID? = nil
    var identitySource: String? = nil
    var studentNumberSnapshot: String? = nil
    var copyID: UUID?
    var expiresAt: Date?
    var needsIdentityReview: Bool?
    var closureKind: String? = nil
    var closedAt: Date? = nil
}

@MainActor
extension ArchivedCopy {
    init(_ copy: BookCopy) {
        self.init(id: copy.id, bookID: copy.bookID, accessionCode: copy.accessionCode, condition: copy.condition,
                  status: copy.status, note: copy.note, addedAt: copy.addedAt, cabinet: copy.cabinet, shelf: copy.shelf)
    }
    func makeModel() -> BookCopy {
        let copy = BookCopy(bookID: bookID, accessionCode: accessionCode, condition: condition, status: status, note: note, cabinet: cabinet, shelf: shelf)
        copy.id = id; copy.addedAt = addedAt
        return copy
    }
}

@MainActor
extension ArchivedReservation {
    init(_ reservation: Reservation) {
        self.init(id: reservation.id, bookID: reservation.bookID, bookTitleSnapshot: reservation.bookTitleSnapshot,
                  studentName: reservation.studentName, studentClass: reservation.studentClass,
                  createdAt: reservation.createdAt, notifiedAt: reservation.notifiedAt, isClosed: reservation.isClosed,
                  studentID: reservation.studentID, memberID: reservation.memberID, identitySource: reservation.identitySource, studentNumberSnapshot: reservation.studentNumberSnapshot, copyID: reservation.copyID, expiresAt: reservation.expiresAt,
                  needsIdentityReview: reservation.needsIdentityReview, closureKind: reservation.closureKind, closedAt: reservation.closedAt)
    }
    func makeModel() -> Reservation {
        let reservation = Reservation(bookID: bookID, bookTitleSnapshot: bookTitleSnapshot, studentName: studentName, studentClass: studentClass)
        reservation.id = id; reservation.createdAt = createdAt; reservation.notifiedAt = notifiedAt
        reservation.isClosed = isClosed; reservation.studentID = studentID; reservation.copyID = copyID
        reservation.memberID = memberID; reservation.identitySource = identitySource
        reservation.studentNumberSnapshot = studentNumberSnapshot
        reservation.expiresAt = expiresAt; reservation.needsIdentityReview = needsIdentityReview ?? false
        reservation.closureKind = closureKind; reservation.closedAt = closedAt
        return reservation
    }
}

nonisolated enum ArchiveSettings {
    /// Bilerek dar liste: sağlayıcı anahtarları, PIN, token veya kimlik doğrulama bilgileri alınmaz.
    /// Son konum (`SonKonum`) da kataloğa özgü olduğundan arşivle birlikte taşınır.
    static let allowedKeys: Set<String> = Set([
        "schoolName", "loanDurationDays", "textbookDueDateTimestamp", "textbookPeriod", "maxLoansPerPerson", "blockOverdueBorrowers", "inventoryCommission",
        "kitaplarSiralama", "kitaplarKapakGorunumu2", "catalogLayout", "catalogSort", "catalogFilter",
        "kitaplarKayitliFiltreler", "kitaplarAramaGecmisi", "spineLabelTemplate",
        "libraryLabelPrintProfile", "libraryStudentPrintProfile", "appearanceMode", "themeAccent",
        "memberLoanRules", "autoArchiveRetentionPolicy", "homeQuickActionsV1"
    ]).union(SonKonum.anahtarlar)
    static let supportingFileNames: Set<String> = ["KademeKurallari.json", "KayitliGorunumler.json", "SayimOturumu.json", "OCRDuzeltmeleri.json", "BekleyenKuyruk.json", "Mezunlar.json", "OgrenciAktarimGunlugu.json", "field_maintenance_journal.json", "SayimBeklenti.json", "SayimOkutmalar.jsonl", "sayim_islem_fisleri.json", "AyriTutCiftleri.json", "AIDegisiklikGunlugu.jsonl"]
    @MainActor static var directoryOverride: URL?
    /// Kişisel veri dosyalarının güncel klasörü (taşıma bitene dek Belgeler, sonra Application Support/Metadata).
    @MainActor static var supportingDirectory: URL? { directoryOverride ?? MetadataRelocation.metadataDirectory }
    /// Destek dosyasının güncel adresi. Taşınmayan dosyalar (örn. OCR düzeltmeleri) Belgeler'de kalır,
    /// bu yüzden klasör değil dosya adına bakılır.
    @MainActor static func supportingURL(for name: String) -> URL? {
        if let directoryOverride { return directoryOverride.appendingPathComponent(name) }
        return MetadataRelocation.url(forFile: name)
    }
    @MainActor static func supportingFiles() -> [String: Data] { (try? supportingFilesVerified()) ?? [:] }
    @MainActor static func supportingFilesVerified() throws -> [String: Data] {
        guard supportingDirectory != nil else { throw CocoaError(.fileNoSuchFile) }
        var result: [String: Data] = [:]
        for name in supportingFileNames {
            guard let url = supportingURL(for: name) else { throw CocoaError(.fileNoSuchFile) }
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                if name == "OgrenciAktarimGunlugu.json" { _ = try StudentImportStore.validate(data) }
                if name == FieldMaintenanceStore.fileName { _ = try FieldMaintenanceStore.validate(data) }
                if name == InventoryActionStore.fileName { _ = try InventoryActionStore.validate(data) }
                result[name] = data
            }
        }
        return result
    }

    @MainActor static func snapshot() -> [String: Data] {
        var result: [String: Data] = [:]
        for key in allowedKeys {
            if let data = UserDefaults.standard.data(forKey: key) {
                result[key] = try? JSONSerialization.data(withJSONObject: ["archiveData": data.base64EncodedString()])
                continue
            }
            guard let value = UserDefaults.standard.object(forKey: key),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else { continue }
            result[key] = data
        }
        return result
    }
    static func validate(_ settings: [String: Data]) throws {
        for (key, data) in settings where allowedKeys.contains(key) {
            let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            if key == "memberLoanRules" {
                guard let wrapper = value as? [String: String], let encoded = wrapper["archiveData"],
                      let decoded = Data(base64Encoded: encoded) else {
                    throw FullArchive.ValidationError(message: "Üye süre/kota ayarı okunamadı; geri yükleme uygulanmadı.")
                }
                try MemberLoanRuleStore.validate(JSONDecoder().decode([MemberLoanRule].self, from: decoded))
            }
            if key == "autoArchiveRetentionPolicy" {
                guard let raw = value as? String, ArchiveRetentionPolicy(rawValue: raw) != nil else {
                    throw FullArchive.ValidationError(message: "Arşiv saklama tercihi geçersiz.")
                }
            }
        }
    }

    @MainActor static func restore(_ settings: [String: Data]) throws {
        try validate(settings)
        for (key, data) in settings where allowedKeys.contains(key) {
            let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
            if let object = value as? [String: String], let encoded = object["archiveData"], let decoded = Data(base64Encoded: encoded) {
                UserDefaults.standard.set(decoded, forKey: key)
            } else { UserDefaults.standard.set(value, forKey: key) }
        }
    }
}

@MainActor
extension FullArchive {
    static func snapshot(context: ModelContext) throws -> ArchiveContents {
        ArchiveContents(books: try context.fetch(FetchDescriptor<CatalogBook>()).map(\.book),
                        loanEvents: try SchoolLibraryService.historySnapshot(context: context),
                        activeLoans: try context.fetch(FetchDescriptor<ActiveLoan>()).map(ArchivedLoan.init),
                        copies: try context.fetch(FetchDescriptor<BookCopy>()).map(ArchivedCopy.init),
                        reservations: try context.fetch(FetchDescriptor<Reservation>()).map(ArchivedReservation.init),
                        students: try StudentStore.allVerified(), members: try MemberStore.allVerified(), settings: ArchiveSettings.snapshot(),
                        supportingFiles: try ArchiveSettings.supportingFilesVerified(),
                        scanReceipts: try context.fetch(FetchDescriptor<ScanWriteReceipt>()).map(ArchivedScanReceipt.init),
                        scanSessions: try ScanSessionStore.allVerified(),
                        graduatedStudents: try GraduatedStudentStore.allVerified(),
                        mergeUndoRecords: try context.fetch(FetchDescriptor<CatalogMergeUndoRecord>()).map(ArchivedCatalogMergeUndo.init))
    }
}

nonisolated struct ArchivedCatalogMergeUndo: Codable, Equatable {
    var id: UUID
    var payload: Data
    var createdAt: Date
    var undoneAt: Date?
}

@MainActor
extension ArchivedCatalogMergeUndo {
    init(_ record: CatalogMergeUndoRecord) {
        id = record.id; payload = record.payload; createdAt = record.createdAt; undoneAt = record.undoneAt
    }
    func makeModel() -> CatalogMergeUndoRecord {
        let record = CatalogMergeUndoRecord(payload: payload)
        record.id = id; record.createdAt = createdAt; record.undoneAt = undoneAt
        return record
    }
}

nonisolated struct ArchivedScanReceipt: Codable, Equatable {
    var id: UUID
    var operationID: UUID
    var bookID: UUID
    var addedCopies: Int
    var inserted: Bool
    var createdAt: Date
    var beforeBookData: Data? = nil
    var afterBookData: Data? = nil
}

@MainActor
extension ArchivedScanReceipt {
    init(_ receipt: ScanWriteReceipt) {
        self.init(id: receipt.id, operationID: receipt.operationID, bookID: receipt.bookID,
                  addedCopies: receipt.addedCopies, inserted: receipt.inserted, createdAt: receipt.createdAt,
                  beforeBookData: receipt.beforeBookData, afterBookData: receipt.afterBookData)
    }
    func makeModel() -> ScanWriteReceipt {
        let receipt = ScanWriteReceipt(operationID: operationID, bookID: bookID, addedCopies: addedCopies, inserted: inserted)
        receipt.id = id; receipt.createdAt = createdAt
        receipt.beforeBookData = beforeBookData; receipt.afterBookData = afterBookData
        return receipt
    }
}
