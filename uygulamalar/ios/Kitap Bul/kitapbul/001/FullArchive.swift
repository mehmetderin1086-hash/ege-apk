import Foundation
import SwiftUI
import UniformTypeIdentifiers
import SwiftData
import CryptoKit

/// Arşivdeki etkin ödünç kaydı (SwiftData nesnesinden bağımsız, Codable kopya).
nonisolated struct ArchivedLoan: Codable, Equatable {
    var id: UUID
    var bookID: UUID
    var bookTitleSnapshot: String
    var studentName: String
    var studentClass: String
    var loanedAt: Date
    var dueDate: Date
    var extensionCount: Int = 0
    var studentID: UUID? = nil
    var memberID: UUID? = nil
    var identitySource: String? = nil
    var studentNumberSnapshot: String? = nil
    var copyID: UUID? = nil
    var needsIdentityReview: Bool? = nil
    var kind: String? = nil
    var periodSnapshot: String? = nil
}

@MainActor
extension ArchivedLoan {
    init(_ loan: ActiveLoan) {
        self.init(
            id: loan.id,
            bookID: loan.bookID,
            bookTitleSnapshot: loan.bookTitleSnapshot,
            studentName: loan.studentName,
            studentClass: loan.studentClass,
            loanedAt: loan.loanedAt,
            dueDate: loan.dueDate,
            extensionCount: loan.extensionCount, studentID: loan.studentID, memberID: loan.memberID, identitySource: loan.identitySource, studentNumberSnapshot: loan.studentNumberSnapshot, copyID: loan.copyID,
            needsIdentityReview: loan.needsIdentityReview, kind: loan.kind, periodSnapshot: loan.periodSnapshot
        )
    }

    func makeActiveLoan() -> ActiveLoan {
        let loan = ActiveLoan(
            bookID: bookID,
            bookTitleSnapshot: bookTitleSnapshot,
            studentName: studentName,
            studentClass: studentClass,
            dueDate: dueDate
        )
        loan.id = id
        loan.loanedAt = loanedAt
        loan.extensionCount = extensionCount
        loan.studentID = studentID
        loan.memberID = memberID
        loan.identitySource = identitySource
        loan.studentNumberSnapshot = studentNumberSnapshot
        loan.copyID = copyID
        loan.needsIdentityReview = needsIdentityReview ?? false
        loan.kind = kind ?? "library"
        loan.periodSnapshot = periodSnapshot
        return loan
    }
}

/// Arşivden okunan her şey: kitaplar (kapaklarıyla), ödünç geçmişi ve etkin ödünçler.
nonisolated struct ArchiveContents: Sendable {
    var books: [Book] = []
    var loanEvents: [LoanEvent] = []
    var activeLoans: [ArchivedLoan] = []
    var copies: [ArchivedCopy] = []
    var reservations: [ArchivedReservation] = []
    var students: [Student] = []
    var members: [Member] = []
    var settings: [String: Data] = [:]
    var supportingFiles: [String: Data] = [:]
    var scanReceipts: [ArchivedScanReceipt] = []
    var scanSessions: [ScanSession] = []
    var graduatedStudents: [GraduatedStudent] = []
    var mergeUndoRecords: [ArchivedCatalogMergeUndo] = []
}

/// Kapak görselleri dahil tam arşiv: tek ZIP dosyasında katalog JSON'u + kapaklar.
/// Cihaz değişiminde ya da yedek saklamada kullanılır; geri yükleme de aynı dosyadan yapılır.
nonisolated enum FullArchive {
    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    /// `buildVerified` için bellekte tutulabilecek görsel toplamı (geliştirme uyarı eşiği).
    static let inMemoryImageBudget = 256 * 1_048_576
    /// ZIP içeriği: katalog.json + kapaklar/<id>.png (+ odunc-gecmisi.json, etkin-oduncler.json)
    static func build(books: [Book], loanEvents: [LoanEvent] = [], activeLoans: [ArchivedLoan] = []) -> Data {
        build(ArchiveContents(books: books, loanEvents: loanEvents, activeLoans: activeLoans))
    }

    static func build(_ contents: ArchiveContents) -> Data { (try? buildVerified(contents)) ?? Data() }

    /// Tam arşiv hiçbir girişi sessizce dışarıda bırakamaz.
    static func buildVerified(_ contents: ArchiveContents) throws -> Data {
        // Bu yol bütün arşivi (kapaklar dahil) belleğe alır. Büyük kataloglar için akışlı yazıcı
        // (`AutoArchive.writeStreaming`) kullanılmalı; geliştirme derlemesinde yanlış kullanım yakalanır.
        assert(contents.books.reduce(0) { $0 + ($1.coverData?.count ?? 0) + ($1.backCoverData?.count ?? 0) + ($1.imprintData?.count ?? 0) }
               < Self.inMemoryImageBudget, "Büyük arşiv bellekte kuruluyor; AutoArchive.writeStreaming kullanın.")
        var entries: [(String, Data)] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var books = contents.books
        for index in books.indices {
            let id = books[index].id.uuidString
            if let cover = books[index].coverData { entries.append(("kapaklar/\(id).png", cover)) }
            if let back = books[index].backCoverData { entries.append(("arka/\(id).jpg", back)) }
            if let imprint = books[index].imprintData { entries.append(("kunye/\(id).jpg", imprint)) }
            books[index].coverData = nil; books[index].backCoverData = nil; books[index].imprintData = nil
        }
        func add<T: Encodable>(_ name: String, _ value: T) throws {
            entries.append((name, try encoder.encode(value)))
        }
        try add("katalog.json", books)
        try add("odunc-gecmisi.json", contents.loanEvents)
        try add("etkin-oduncler.json", contents.activeLoans)
        try add("nushalar.json", contents.copies)
        try add("rezervasyonlar.json", contents.reservations)
        try add("ogrenciler.json", contents.students)
        try add("uyeler.json", contents.members)
        try add("ayarlar.json", contents.settings.filter { ArchiveSettings.allowedKeys.contains($0.key) })
        try add("destek-dosyalari.json", contents.supportingFiles.filter { ArchiveSettings.supportingFileNames.contains($0.key) })
        try add("tarama-makbuzlari.json", contents.scanReceipts)
        try add("tarama-oturumlari.json", contents.scanSessions)
        try add("mezunlar.json", contents.graduatedStudents)
        try add("katalog-birlestirme-geri-al.json", contents.mergeUndoRecords)
        guard Set(entries.map(\.0)).count == entries.count else {
            throw ValidationError(message: "Arşivde aynı kimlikle birden çok kapak/kayıt var; eksik veya çakışan yedek oluşturulmadı.")
        }
        let hashes = Dictionary(uniqueKeysWithValues: entries.map { ($0.0, SHA256.hash(data: $0.1).map { String(format: "%02x", $0) }.joined()) })
        try add("manifest.json", ArchiveManifest(version: 2, hashes: hashes))
        var archive = ZIPWriter()
        for (name, data) in entries {
            guard archive.add(name: name, data: data) else {
                throw ValidationError(message: "Arşiv ZIP boyut veya dosya sayısı sınırını aşıyor; eksik yedek oluşturulmadı.")
            }
        }
        return archive.finalize()
    }

    /// ZIP arşivinden kitapları (kapaklarıyla) okur.
    static func restore(from url: URL) -> [Book] {
        restoreContents(from: url).books
    }

    static func restoreContents(from url: URL) -> ArchiveContents {
        guard let data = try? Data(contentsOf: url) else { return ArchiveContents() }
        return restoreContents(data: data)
    }

    static func restoreContents(data: Data) -> ArchiveContents {
        restoreContents(entries: ZIPReader.entries(in: data))
    }

    /// ZIP bir kez çözülür; `readValidated` aynı girişleri yeniden çözmeden buraya verir.
    static func restoreContents(entries: [ZIPReader.Entry]) -> ArchiveContents {
        guard let jsonEntry = entries.first(where: { $0.name == "katalog.json" }) else {
            return ArchiveContents()
        }
        var books = CatalogBackup.decode(jsonEntry.data)

        // Kapakları eşleştir. Ad → veri sözlüğü BİR KEZ kurulur: 2.575 kitap × 2.575
        // giriş için her kitapta listeyi baştan taramak milyonlarca karşılaştırma
        // demekti ve ilk açılışı ana iş parçacığında saniyelerce kilitliyordu.
        var coversByName: [String: Data] = [:]
        coversByName.reserveCapacity(entries.count)
        for entry in entries where entry.name.hasPrefix("kapaklar/") {
            coversByName[entry.name] = entry.data
        }
        for entry in entries where entry.name.hasPrefix("arka/") || entry.name.hasPrefix("kunye/") {
            coversByName[entry.name] = entry.data
        }
        for index in books.indices {
            let id = books[index].id.uuidString
            if let cover = coversByName["kapaklar/\(id).png"] {
                books[index].coverData = cover
            }
            // Akışlı (günlük) arşivde arka kapak ve künye ayrı dosyadır
            if books[index].backCoverData == nil, let back = coversByName["arka/\(id).jpg"] {
                books[index].backCoverData = back
            }
            if books[index].imprintData == nil, let imprint = coversByName["kunye/\(id).jpg"] {
                books[index].imprintData = imprint
            }
        }

        let decoder = JSONDecoder()
        let entriesByName = Dictionary(entries.map { ($0.name, $0.data) }, uniquingKeysWith: { first, _ in first })
        decoder.dateDecodingStrategy = .iso8601
        let events = entries.first(where: { $0.name == "odunc-gecmisi.json" })
            .flatMap { try? decoder.decode([LoanEvent].self, from: $0.data) } ?? []
        let loans = entries.first(where: { $0.name == "etkin-oduncler.json" })
            .flatMap { try? decoder.decode([ArchivedLoan].self, from: $0.data) } ?? []
        return ArchiveContents(books: books, loanEvents: events, activeLoans: loans,
                               copies: decode("nushalar.json", entries: entriesByName, decoder: decoder) ?? [],
                               reservations: decode("rezervasyonlar.json", entries: entriesByName, decoder: decoder) ?? [],
                               students: decode("ogrenciler.json", entries: entriesByName, decoder: decoder) ?? [],
                               members: decode("uyeler.json", entries: entriesByName, decoder: decoder) ?? [],
                               settings: decode("ayarlar.json", entries: entriesByName, decoder: decoder) ?? [:],
                               supportingFiles: decode("destek-dosyalari.json", entries: entriesByName, decoder: decoder) ?? [:],
                               scanReceipts: decode("tarama-makbuzlari.json", entries: entriesByName, decoder: decoder) ?? [],
                               scanSessions: decode("tarama-oturumlari.json", entries: entriesByName, decoder: decoder) ?? [],
                               graduatedStudents: decode("mezunlar.json", entries: entriesByName, decoder: decoder) ?? [],
                               mergeUndoRecords: decode("katalog-birlestirme-geri-al.json", entries: entriesByName, decoder: decoder) ?? [])
    }
    private static func decode<T: Decodable>(_ name: String, entries: [String: Data], decoder: JSONDecoder) -> T? {
        entries[name].flatMap { try? decoder.decode(T.self, from: $0) }
    }

    static func readValidated(from url: URL) throws -> ArchiveContents {
        // Bellek eşlemeli okuma: büyük arşivin ikinci bir tam kopyası oluşmaz.
        try readValidated(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func readValidated(data: Data) throws -> ArchiveContents {
        let entries = ZIPReader.entries(in: data)
        // Ad → giriş sözlüğü bir kez kurulur: manifest doğrulaması giriş sayısı kadar aramadır ve
        // doğrusal tarama 2.700 girişte milyonlarca dizge karşılaştırmasına çıkıyordu.
        var byName: [String: ZIPReader.Entry] = [:]
        byName.reserveCapacity(entries.count)
        for entry in entries { byName[entry.name] = entry }
        guard byName.count == entries.count, let catalog = byName["katalog.json"] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let catalogRows = (try? JSONSerialization.jsonObject(with: catalog.data)) as? [Any] else { throw ValidationError(message: "Arşiv katalog listesi okunamadı.") }
        if let manifestData = byName["manifest.json"]?.data {
            let manifest = try decoder.decode(ArchiveManifest.self, from: manifestData)
            guard manifest.version == 2 else { throw CocoaError(.fileReadCorruptFile) }
            guard Set(manifest.hashes.keys) == Set(byName.keys.filter { $0 != "manifest.json" }) else {
                throw ValidationError(message: "Manifest arşivdeki bütün dosyaları kapsamıyor; doğrulanmamış ek içerik geri yüklenmedi.")
            }
            for (name, expected) in manifest.hashes {
                guard let entry = byName[name] else { throw CocoaError(.fileReadCorruptFile) }
                let actual = SHA256.hash(data: entry.data).map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw CocoaError(.fileReadCorruptFile) }
            }
            let required = ["katalog.json", "odunc-gecmisi.json", "etkin-oduncler.json", "nushalar.json", "rezervasyonlar.json", "ogrenciler.json", "uyeler.json", "ayarlar.json"]
            guard required.allSatisfy({ manifest.hashes[$0] != nil }) else { throw CocoaError(.fileReadCorruptFile) }
        }
        func validate<T: Decodable>(_ name: String, _ type: T.Type) throws {
            if let entry = byName[name] {
                do { _ = try decoder.decode(type, from: entry.data) }
                catch { throw ValidationError(message: "Arşivde \(name) okunamadı. Dosya değiştirilmedi.") }
            }
        }
        try validate("etkin-oduncler.json", [ArchivedLoan].self)
        try validate("odunc-gecmisi.json", [LoanEvent].self)
        try validate("nushalar.json", [ArchivedCopy].self)
        try validate("rezervasyonlar.json", [ArchivedReservation].self)
        try validate("ogrenciler.json", [Student].self)
        try validate("uyeler.json", [Member].self)
        try validate("ayarlar.json", [String: Data].self)
        try validate("destek-dosyalari.json", [String: Data].self)
        try validate("tarama-makbuzlari.json", [ArchivedScanReceipt].self)
        try validate("tarama-oturumlari.json", [ScanSession].self)
        try validate("mezunlar.json", [GraduatedStudent].self)
        try validate("katalog-birlestirme-geri-al.json", [ArchivedCatalogMergeUndo].self)
        let contents = restoreContents(entries: entries)
        try ArchiveSettings.validate(contents.settings)
        if let journal = contents.supportingFiles["OgrenciAktarimGunlugu.json"] { _ = try StudentImportStore.validate(journal) }
        if let journal = contents.supportingFiles[FieldMaintenanceStore.fileName] { _ = try FieldMaintenanceStore.validate(journal) }
        if let journal = contents.supportingFiles[InventoryActionStore.fileName] { _ = try InventoryActionStore.validate(journal) }
        guard contents.books.count == catalogRows.count else { throw ValidationError(message: "Katalogdaki bazı satırlar çözülemedi; kısmi geri yükleme yapılmadı.") }
        let ids = Set(contents.books.map(\.id))
        guard ids.count == contents.books.count else { throw ValidationError(message: "Arşivde aynı kimlikle birden çok eser var.") }
        guard Set(contents.copies.map(\.id)).count == contents.copies.count,
              Set(contents.reservations.map(\.id)).count == contents.reservations.count,
              Set(contents.activeLoans.map(\.id)).count == contents.activeLoans.count,
              Set(contents.students.map(\.id)).count == contents.students.count,
              Set(contents.members.map(\.id)).count == contents.members.count,
              Set(contents.scanReceipts.map(\.operationID)).count == contents.scanReceipts.count,
              Set(contents.graduatedStudents.map(\.id)).count == contents.graduatedStudents.count,
              Set(contents.mergeUndoRecords.map(\.id)).count == contents.mergeUndoRecords.count else {
            throw ValidationError(message: "Arşivde tekrarlanan nüsha, ödünç, rezervasyon veya kişi kimliği var.")
        }
        guard contents.activeLoans.allSatisfy({ $0.studentID == nil || $0.memberID == nil }),
              contents.loanEvents.allSatisfy({ $0.studentID == nil || $0.memberID == nil }),
              contents.reservations.allSatisfy({ $0.studentID == nil || $0.memberID == nil }) else {
            throw ValidationError(message: "Bir ödünç hareketinde hem öğrenci hem üye kimliği var; belirsiz kişi ilişkisi geri yüklenmedi.")
        }
        let orphanLoans = contents.activeLoans.filter { !ids.contains($0.bookID) }.count
        let orphanCopies = contents.copies.filter { !ids.contains($0.bookID) }.count
        let orphanReservations = contents.reservations.filter { !ids.contains($0.bookID) }.count
        guard orphanLoans + orphanCopies + orphanReservations == 0 else {
            throw ValidationError(message: "Arşivde kataloğu bulunamayan \(orphanLoans) ödünç, \(orphanCopies) nüsha, \(orphanReservations) rezervasyon var. Dosya değiştirilmedi; ilişkileri düzeltip yeniden deneyin.")
        }
        guard contents.activeLoans.allSatisfy({ loan in loan.copyID == nil || contents.copies.contains { $0.id == loan.copyID && $0.bookID == loan.bookID } }) else {
            throw ValidationError(message: "Bir ödüncün fiziksel nüsha bağlantısı arşivde bulunamadı. Dosya değiştirilmedi.")
        }
        guard contents.reservations.allSatisfy({ reservation in reservation.copyID == nil || contents.copies.contains { $0.id == reservation.copyID && $0.bookID == reservation.bookID } }) else {
            throw ValidationError(message: "Bir rezervasyonun fiziksel nüsha bağlantısı eksik veya başka esere ait. Dosya değiştirilmedi.")
        }
        let loanedCopyIDs = contents.activeLoans.compactMap(\.copyID)
        guard Set(loanedCopyIDs).count == loanedCopyIDs.count else {
            throw ValidationError(message: "Aynı fiziksel nüsha arşivde birden çok etkin ödünce bağlı. Dosya değiştirilmedi; ilişkileri düzeltip yeniden deneyin.")
        }

        return contents
    }

}

/// Dışa aktarma için ZIP belgesi.
struct ArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Sıkıştırmasız ZIP yazıcı/okuyucu

/// Basit "store" (sıkıştırmasız) ZIP yazıcı — Excel çıktısı da aynı yazıcıyı kullanır.
///
/// Klasik (Zip64 olmayan) biçimin sınırları vardır: en fazla 65.535 giriş, toplam
/// 4 GB. `UInt16(x)` / `UInt32(x)` dönüşümleri bu sınırlar aşıldığında sessizce
/// kırpmaz, uygulamayı ÇÖKERTİR. Bu yüzden sınırı aşacak girişler eklenmez;
/// `skippedCount` ile kaç girişin dışarıda kaldığı öğrenilebilir.
nonisolated struct ZIPWriter {
    private struct Entry {
        let name: Data
        let size: UInt32
        let checksum: UInt32
        let offset: UInt32
    }

    /// Klasik ZIP'in giriş sayısı sınırı (merkezi dizin 16 bit sayar). 0xFFFF değeri
    /// bazı okuyucularda "Zip64'e bak" işareti sayıldığı için bir eksiği kullanılır.
    static let maxEntryCount = Int(UInt16.max) - 1
    /// Klasik ZIP'in toplam boyut sınırı (ofsetler 32 bit; 0xFFFFFFFF yine Zip64 işareti).
    static let maxArchiveSize = Int(UInt32.max) - 1
    /// Yerel başlık (30 bayt) + merkezi dizin kaydı (46 bayt) + iki kez ad + son kayıt (22 bayt).
    private static let perEntryOverhead = 30 + 46
    private static let endRecordSize = 22

    private var output = Data()
    private var entries: [Entry] = []
    /// Dosyaya akıtma: büyük arşivler (binlerce kapak) belleğe sığdırılmadan yazılır.
    private let sink: FileHandle?
    private var written = 0
    private(set) var writeError: Error?

    init(fileHandle: FileHandle? = nil) {
        self.sink = fileHandle
    }

    /// Sınırlar yüzünden arşive alınamayan giriş sayısı.
    private(set) var skippedCount = 0

    /// Girişin eklenmesi arşivi klasik ZIP sınırlarının dışına taşırır mı?
    func canAdd(name: String, dataCount: Int) -> Bool {
        guard writeError == nil, entries.count < Self.maxEntryCount else { return false }
        let nameCount = name.utf8.count
        guard nameCount <= Int(UInt16.max), dataCount <= Self.maxArchiveSize else { return false }
        let projected = written + Self.perEntryOverhead + nameCount * 2 + dataCount
            + Self.endRecordSize + directorySizeSoFar
        return projected <= Self.maxArchiveSize
    }

    /// Şimdiye dek eklenen girişlerin merkezi dizinde kaplayacağı yer
    /// (her ekleme sırasında artırılır; 65 bin girişte yeniden toplamak gerekmez).
    private var directorySizeSoFar = 0

    private mutating func emit(_ data: Data) {
        guard writeError == nil else { return }
        if let sink {
            do { try sink.write(contentsOf: data) }
            catch { writeError = error; return }
        } else { output.append(data) }
        written += data.count
    }

    mutating func add(name: String, text: String) {
        add(name: name, data: Data(text.utf8))
    }

    /// Girişi ekler; sınır aşılacaksa eklemez ve `false` döner (çökme yerine).
    @discardableResult
    mutating func add(name: String, data: Data) -> Bool {
        guard canAdd(name: name, dataCount: data.count) else {
            skippedCount += 1
            return false
        }

        let nameData = Data(name.utf8)
        let offset = UInt32(written)
        let size = UInt32(data.count)
        let checksum = ZIPCRC32.checksum(data)

        var header = Data()
        header.appendLE(UInt32(0x04034B50))
        header.appendLE(UInt16(20))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(UInt16(0))
        header.appendLE(checksum)
        header.appendLE(size)
        header.appendLE(size)
        header.appendLE(UInt16(nameData.count))
        header.appendLE(UInt16(0))
        header.append(nameData)
        emit(header)
        emit(data)
        guard writeError == nil else { skippedCount += 1; return false }

        entries.append(Entry(name: nameData, size: size, checksum: checksum, offset: offset))
        directorySizeSoFar += 46 + nameData.count
        return true
    }

    /// Merkezi dizini yazar. Bellek kipinde arşivin tamamını, dosya kipinde boş veri döndürür.
    mutating func finalize() -> Data {
        let directoryOffset = UInt32(written)
        var directory = Data()
        for entry in entries {
            directory.appendLE(UInt32(0x02014B50))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(20))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(entry.checksum)
            directory.appendLE(entry.size)
            directory.appendLE(entry.size)
            directory.appendLE(UInt16(entry.name.count))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt16(0))
            directory.appendLE(UInt32(0))
            directory.appendLE(entry.offset)
            directory.append(entry.name)
        }
        let directorySize = UInt32(directory.count)
        directory.appendLE(UInt32(0x06054B50))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(0))
        directory.appendLE(UInt16(entries.count))
        directory.appendLE(UInt16(entries.count))
        directory.appendLE(directorySize)
        directory.appendLE(directoryOffset)
        directory.appendLE(UInt16(0))
        emit(directory)
        return output
    }
}

/// Sıkıştırmasız ZIP okuyucu (kendi yazdığımız arşivleri geri okumak için).
nonisolated enum ZIPReader {
    struct Entry {
        let name: String
        let data: Data
    }

    static func entries(in archive: Data) -> [Entry] {
        var result: [Entry] = []
        // Arşivin tamamını [UInt8]'e kopyalamadan doğrudan bayt tamponu üzerinden okunur.
        archive.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var index = 0
            while index + 30 <= bytes.count {
                // Yerel dosya başlığı imzası
                guard bytes[index] == 0x50, bytes[index + 1] == 0x4B,
                      bytes[index + 2] == 0x03, bytes[index + 3] == 0x04 else { break }

                let method = readUInt16(bytes, index + 8)
                let size = Int(readUInt32(bytes, index + 18))
                let nameLength = Int(readUInt16(bytes, index + 26))
                let extraLength = Int(readUInt16(bytes, index + 28))

                let nameStart = index + 30
                let dataStart = nameStart + nameLength + extraLength
                guard dataStart + size <= bytes.count else { break }

                let name = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[nameStart..<(nameStart + nameLength)]), as: UTF8.self)
                if method == 0 {
                    result.append(Entry(name: name, data: Data(UnsafeRawBufferPointer(rebasing: bytes[dataStart..<(dataStart + size)]))))
                }
                index = dataStart + size
            }
        }
        return result
    }

    private static func readUInt16(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

/// Tablo tabanlı CRC-32 (IEEE 802.3, ZIP'in kullandığı). Bayt başına 8 döngülük
/// bit-bit hesap, kapaklı 2.500 kitaplık arşivde dakikalarca %100 CPU tüketip
/// telefonu ısıtıyordu; tablo ile ~10 kat hızlıdır ve sonuç aynıdır.
nonisolated enum ZIPCRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            for byte in buffer {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ UInt32.max
    }
}

private nonisolated extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
