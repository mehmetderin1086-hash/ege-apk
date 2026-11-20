import Foundation
import SwiftData
import Observation

/// Ödünç hareketi katalogla aynı transaction içinde dayanıklı tutulur; JSON yalnız dışarı aktarımıdır.
@Model
final class LibraryEventOutbox {
    var id: UUID = UUID()
    var eventData: Data = Data()
    var createdAt: Date = Date()
    var replacesExisting: Bool = false

    init(event: LoanEvent, replacesExisting: Bool = false) throws {
        id = event.id
        self.replacesExisting = replacesExisting
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        eventData = try encoder.encode(event)
        createdAt = event.date
    }

    func decodedEvent() throws -> LoanEvent {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoanEvent.self, from: eventData)
    }
}

@MainActor
@Observable
final class LibrarySyncStatus {
    static let shared = LibrarySyncStatus()
    var warning: String?
}
