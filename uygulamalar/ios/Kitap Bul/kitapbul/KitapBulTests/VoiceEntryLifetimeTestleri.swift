import Foundation
import Testing
@testable import _01

@MainActor @Suite(.serialized)
struct VoiceEntryLifetimeTestleri {
    @MainActor private final class Scheduler {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var waiting = false
        func wait() async {
            await withCheckedContinuation { continuation in self.continuation = continuation; waiting = true }
        }
        func release() { let saved = continuation; continuation = nil; saved?.resume() }
    }
    private func waitForSuspension(_ scheduler: Scheduler) async throws {
        for _ in 0..<100 {
            if scheduler.waiting { return }
            await Task.yield()
        }
        Issue.record("Fake scheduler bekleme noktasına ulaşmadı")
    }

    @Test func leavingPageCancelsQueuedContinuousResumeWithoutStartingMicrophone() async throws {
        let gate = VoiceEntryTaskGate(), scheduler = Scheduler()
        var microphoneStarts = 0
        gate.activate()
        gate.scheduleResume(wait: { await scheduler.wait() }, shouldStart: { true }, start: { microphoneStarts += 1 })
        try await waitForSuspension(scheduler)
        gate.deactivate(); scheduler.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(microphoneStarts == 0 && !gate.isActive)
    }

    @Test func latePermissionSuccessCannotStartMicrophoneAfterPageReentry() async throws {
        let gate = VoiceEntryTaskGate(), scheduler = Scheduler()
        var microphoneStarts = 0
        gate.activate()
        let token = try #require(gate.currentToken)
        let request = Task { @MainActor in
            await gate.authorizeAndStart(authorization: { await scheduler.wait(); return true }, start: { microphoneStarts += 1 })
        }
        try await waitForSuspension(scheduler)
        gate.deactivate(); gate.activate(); scheduler.release()
        #expect(await request.value == false)
        #expect(microphoneStarts == 0 && !gate.accepts(token))
        #expect(await gate.authorizeAndStart(authorization: { true }, start: { microphoneStarts += 1 }))
        #expect(microphoneStarts == 1)
    }

    @Test func cancelledExplicitResumeDoesNotRaceNewResumeOrPermissionDenial() async throws {
        let gate = VoiceEntryTaskGate(), old = Scheduler(), new = Scheduler()
        var starts: [String] = []
        gate.activate()
        gate.scheduleResume(wait: { await old.wait() }, shouldStart: { true }, start: { starts.append("old") })
        try await waitForSuspension(old)
        gate.scheduleResume(wait: { await new.wait() }, shouldStart: { true }, start: { starts.append("new") })
        try await waitForSuspension(new)
        old.release(); new.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(starts == ["new"])
        #expect(await gate.authorizeAndStart(authorization: { false }, start: { starts.append("denied") }) == false)
        #expect(starts == ["new"])
    }
}
