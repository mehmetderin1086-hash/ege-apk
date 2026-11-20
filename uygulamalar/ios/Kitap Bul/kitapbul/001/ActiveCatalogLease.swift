import Foundation
import SwiftData

/// An activation is a new UI lifetime even when it reopens the same container.
/// Advance only after the durable switch commit, before shared state/publishing.
@MainActor
enum ActiveCatalogGeneration {
    private(set) static var current = UUID()

    static func didActivate() {
        current = UUID()
    }
}

/// UI work captures this before starting a worker. It never follows a later
/// catalog automatically. Isolated/trial services intentionally do not use it.
@MainActor
struct ActiveCatalogLease {
    struct Expired: LocalizedError {
        var errorDescription: String? {
            "Katalog değişti; önceki ekrandaki işlem durduruldu. Yeni katalogda işlemi yeniden başlatın."
        }
    }

    private let containerID: ObjectIdentifier
    private let generation: UUID

    static func capture(context: ModelContext, activeContainer: ModelContainer?, generation: UUID) throws -> Self {
        try Task.checkCancellation()
        guard let activeContainer, activeContainer === context.container else { throw Expired() }
        return Self(containerID: ObjectIdentifier(activeContainer), generation: generation)
    }

    static func captureCurrent(context: ModelContext) throws -> Self {
        try capture(context: context, activeContainer: KitapVeritabani.shared, generation: ActiveCatalogGeneration.current)
    }

    func require(context: ModelContext, activeContainer: ModelContainer?, generation: UUID) throws {
        try Task.checkCancellation()
        guard let activeContainer, activeContainer === context.container,
              ObjectIdentifier(activeContainer) == containerID, generation == self.generation else {
            throw Expired()
        }
    }

    func requireCurrent(context: ModelContext) throws {
        try require(context: context, activeContainer: KitapVeritabani.shared, generation: ActiveCatalogGeneration.current)
    }

    /// No suspension is possible between this gate and database/session writes.
    func perform<Result>(context: ModelContext, activeContainer: ModelContainer?, generation: UUID,
                         _ body: @MainActor () throws -> Result) throws -> Result {
        try require(context: context, activeContainer: activeContainer, generation: generation)
        return try body()
    }

    func performCurrent<Result>(context: ModelContext, _ body: @MainActor () throws -> Result) throws -> Result {
        try perform(context: context, activeContainer: KitapVeritabani.shared,
                    generation: ActiveCatalogGeneration.current, body)
    }
}
