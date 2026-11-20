import Foundation

/// Source identity is separate from a decoded image: iCloud/Photos loading can
/// fail before pixels exist. Keep that identity/error so the user can reselect.
nonisolated struct ScanPhotoImportSource: Identifiable, Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable { case pending, failed, parsed }
    var id = UUID()
    var selectionIndex: Int
    var pickerIdentifier: String?
    var imageIndex: Int?
    var status: Status = .pending
    var errorMessage: String?
    var needsRead: Bool { status != .parsed }
}

nonisolated struct ScanPhotoImportOutcome: Sendable {
    var source: ScanPhotoImportSource
    var image: Data?
    var book: Book?

    /// Pixels live once in sourceImages; the source holds an index. Applying a
    /// retry does not duplicate successful draft identities or image payloads.
    func apply(to session: inout ScanSession) {
        var updated = source
        var images = session.sourceImages ?? []
        if let image, updated.imageIndex.flatMap({ images.indices.contains($0) ? $0 : nil }) == nil {
            updated.imageIndex = images.count; images.append(image)
        }
        session.sourceImages = images
        var sources = session.separatePhotoSources ?? []
        if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = updated }
        else { sources.append(updated) }
        session.separatePhotoSources = sources
        if let book {
            session.pendingBooks.removeAll { $0.id == source.id }
            session.pendingBooks.append(book)
        }
    }
}

@MainActor enum ScanPhotoImportWorker {
    enum Failure: LocalizedError {
        case reselect, noData, identityChanged
        var errorDescription: String? {
            switch self {
            case .reselect: "Bu fotoğrafın verisi yüklenemedi. Galeriden aynı kaynağı yeniden seçin; diğer kayıtlar korunuyor."
            case .noData: "Fotoğraf verisi alınamadı. Galeriden yeniden seçin veya indirmeyi tamamlayın."
            case .identityChanged: "Fotoğraf taslağının işlem kimliği değişti; kaynak korunuyor ve kayıt yapılmadı."
            }
        }
    }

    /// Does not write models/global metadata. Callers check their active-catalog
    /// lease before applying the result. Both Photos load and OCR failures carry
    /// a result with explicit source identity instead of disappearing as nil.
    static func read(_ original: ScanPhotoImportSource, cachedImage: Data?,
        load: @MainActor () async throws -> Data,
        parse: @MainActor (Data) async throws -> Book) async -> ScanPhotoImportOutcome {
        var source = original, image = cachedImage
        do {
            try Task.checkCancellation()
            if image == nil { image = try await load() }
            guard let image, !image.isEmpty else { throw Failure.noData }
            try Task.checkCancellation()
            let book = try await parse(image)
            guard book.id == source.id else { throw Failure.identityChanged }
            try Task.checkCancellation()
            source.status = .parsed; source.errorMessage = nil
            return .init(source: source, image: image, book: book)
        } catch is CancellationError {
            source.status = .pending; source.errorMessage = "Okuma iptal edildi; kaynak fotoğraf korunuyor."
        } catch {
            source.status = .failed; source.errorMessage = error.localizedDescription
        }
        return .init(source: source, image: image, book: nil)
    }
}
