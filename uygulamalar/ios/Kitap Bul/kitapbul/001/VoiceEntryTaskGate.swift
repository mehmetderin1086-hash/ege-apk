import Foundation
import Observation

/// A delayed resume/provider result belongs to one visible page generation.
/// Deactivation cancels scheduled work; a reentered page cannot accept old work.
@MainActor @Observable
final class VoiceEntryTaskGate {
    private var generation = UUID()
    private(set) var isActive = false
    private var resumeTask: Task<Void, Never>?
    var currentToken: UUID? { isActive ? generation : nil }

    func activate() { cancelResume(); generation = UUID(); isActive = true }
    func deactivate() { isActive = false; generation = UUID(); cancelResume() }
    func accepts(_ token: UUID) -> Bool { isActive && generation == token }
    func cancelResume() { resumeTask?.cancel(); resumeTask = nil }

    /// Permissions may finish after navigation. A success is never allowed to
    /// start a microphone on a page that left/reentered during the request.
    func authorizeAndStart(authorization: @MainActor () async -> Bool,
                           start: @MainActor () -> Void) async -> Bool {
        cancelResume()
        guard let token = currentToken else { return false }
        let authorized = await authorization()
        guard authorized, accepts(token), !Task.isCancelled else { return false }
        start(); return true
    }

    /// The caller supplies the real wait; tests supply a controlled scheduler.
    /// No microphone/speech engine is constructed by this state machine.
    func scheduleResume(wait: @escaping @MainActor () async throws -> Void,
        shouldStart: @escaping @MainActor () -> Bool, start: @escaping @MainActor () -> Void) {
        cancelResume()
        guard let token = currentToken else { return }
        resumeTask = Task { @MainActor [weak self] in
            do { try await wait() }
            catch { return }
            guard let self, self.accepts(token), !Task.isCancelled, shouldStart() else { return }
            start()
        }
    }
}
