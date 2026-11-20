import Foundation
import OSLog

// Adaptation of the upstream resource interface: synthesis never makes a
// network request. Installation is explicitly managed by the host application.
enum Supertonic3ResourceDownloader {
    static func ensureModels(directory: URL?, veVariant: String?) async throws -> URL {
        guard let directory else { throw Supertonic3Error.modelFileNotFound("model directory") }
        let repo = directory.appendingPathComponent("supertonic-3-coreml")
        for file in ModelNames.Supertonic3.requiredFiles(veVariant: veVariant) {
            guard FileManager.default.fileExists(atPath: repo.appendingPathComponent(file).path) else {
                throw Supertonic3Error.modelFileNotFound(file)
            }
        }
        return repo
    }
}

struct AppLogger: Sendable {
    private let logger: Logger
    init(category: String) { logger = Logger(subsystem: "com.mehmetderin.derspodcast.supertonic", category: category) }
    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func warning(_ message: String) { logger.warning("\(message, privacy: .public)") }
    func debug(_ message: String) { logger.debug("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
}
