import Combine
import Foundation

/// A local calendar day's measured listening. No duration is inferred from play counts.
struct ListeningDay: Codable, Identifiable, Equatable {
    var dayStart: Date
    var seconds: Double
    var trackSeconds: [String: Double]
    var id: Date { dayStart }

    init(dayStart: Date, seconds: Double = 0, trackSeconds: [String: Double] = [:]) {
        self.dayStart = dayStart
        self.seconds = seconds
        self.trackSeconds = trackSeconds
    }
}

@MainActor
final class ListeningStore: ObservableObject {
    @Published private(set) var days: [ListeningDay] = []
    @Published private(set) var errorMessage: String?

    private struct State: Codable { var version = 1; var days: [ListeningDay] }
    private struct Sample { var date: Date; var uptime: TimeInterval }
    private let stateURL: URL
    private let calendar: Calendar
    private let now: () -> Date
    private let uptime: () -> TimeInterval
    private var activeTrackID: UUID?
    private var previousSample: Sample?
    private var lastPersistedUptime: TimeInterval
    private var dirty = false
    private var canWrite = true
    private let retentionDays = 366

    /// Use the parent of LibraryStore.directory so tests and separate libraries remain isolated.
    init(directory: URL, calendar: Calendar = .autoupdatingCurrent,
         now: @escaping () -> Date = Date.init,
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.stateURL = directory.appendingPathComponent("listening.json")
        self.calendar = calendar
        self.now = now
        self.uptime = uptime
        self.lastPersistedUptime = uptime()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL))
                guard state.version == 1,
                      state.days.allSatisfy({ day in
                          day.dayStart.timeIntervalSince1970.isFinite && day.seconds.isFinite && day.seconds >= 0
                          && day.trackSeconds.allSatisfy { UUID(uuidString: $0.key) != nil && $0.value.isFinite && $0.value >= 0 }
                      }) else { throw CocoaError(.fileReadCorruptFile) }
                // Normalize and merge calendar buckets if the device time zone has changed.
                var merged: [Date: ListeningDay] = [:]
                for day in state.days {
                    let key = calendar.startOfDay(for: day.dayStart)
                    var value = merged[key] ?? ListeningDay(dayStart: key)
                    value.seconds += day.seconds
                    for (track, seconds) in day.trackSeconds { value.trackSeconds[track, default: 0] += seconds }
                    merged[key] = value
                }
                days = merged.values.sorted { $0.dayStart < $1.dayStart }
                prune(at: now())
            }
        } catch {
            // Preserve unreadable data before starting fresh; never replace the only copy.
            if FileManager.default.fileExists(atPath: stateURL.path) {
                let backup = directory.appendingPathComponent("listening-corrupt-\(UUID().uuidString).json")
                do { try FileManager.default.copyItem(at: stateURL, to: backup) }
                catch { canWrite = false }
            } else { canWrite = false }
            days = []
            errorMessage = canWrite
                ? "Dinleme geçmişi okunamadı. Önceki dosya korundu; yeni dinlemeler kaydedilecek."
                : "Dinleme geçmişi kaydedilemiyor. Önceki dosya korunuyor."
        }
    }

    /// Drive with AVPlayer's actual timeControlStatus, never the requested play state.
    /// Seek position and playback rate deliberately have no role in the measured duration.
    func updatePlayback(trackID: UUID?, isPlaying: Bool, isSeeking: Bool = false) {
        let sample = Sample(date: now(), uptime: uptime())
        checkpoint(at: sample)
        let next = isPlaying && !isSeeking ? trackID : nil
        let changed = next != activeTrackID
        activeTrackID = next
        previousSample = next == nil ? nil : sample
        if changed { persist(at: sample.uptime) }
    }

    /// A periodic player heartbeat updates visible totals and checkpoints at most every 15 seconds.
    func tick() {
        let sample = Sample(date: now(), uptime: uptime())
        checkpoint(at: sample)
        if sample.uptime - lastPersistedUptime >= 15 { persist(at: sample.uptime) }
    }

    /// Flush on pause, item changes, backgrounding, and termination. Background audio may continue.
    func flush() {
        let sample = Sample(date: now(), uptime: uptime())
        checkpoint(at: sample)
        persist(at: sample.uptime)
    }

    func recentDays(count: Int, now: Date = Date()) -> [ListeningDay] {
        let count = min(retentionDays, max(0, count))
        guard count > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.dayStart, $0) })
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDate[date] ?? ListeningDay(dayStart: date)
        }
    }

    func totalSeconds(days: Int, now: Date = Date()) -> Double {
        recentDays(count: days, now: now).reduce(0) { $0 + $1.seconds }
    }

    private func checkpoint(at sample: Sample) {
        guard let trackID = activeTrackID, let previousSample else { return }
        self.previousSample = sample
        let duration = sample.uptime - previousSample.uptime
        // A playing AVPlayer supplies a heartbeat at least once per second. After a long
        // suspension/stall, a delayed pause callback cannot prove that playback continued.
        // Discard that unobserved gap instead of manufacturing listening time.
        guard duration.isFinite, duration > 0, duration <= 10 else { return }
        // The monotonic clock determines duration. A manual wall-clock change cannot add hours.
        let wallDuration = sample.date.timeIntervalSince(previousSample.date)
        let start = abs(wallDuration - duration) <= 5 ? previousSample.date : sample.date.addingTimeInterval(-duration)
        var cursor = start
        var remaining = duration
        var updated = Dictionary(uniqueKeysWithValues: days.map { ($0.dayStart, $0) })
        let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: calendar.startOfDay(for: sample.date))!
        // Even a resumed process after a very long sleep cannot grow unbounded history.
        if cursor < cutoff {
            let skip = min(remaining, cutoff.timeIntervalSince(cursor))
            cursor = cursor.addingTimeInterval(skip)
            remaining -= skip
        }
        while remaining > 0.000_001 {
            let day = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let portion = min(remaining, nextDay.timeIntervalSince(cursor))
            guard portion > 0 else { break }
            var value = updated[day] ?? ListeningDay(dayStart: day)
            value.seconds += portion
            value.trackSeconds[trackID.uuidString, default: 0] += portion
            updated[day] = value
            remaining -= portion
            cursor = cursor.addingTimeInterval(portion)
        }
        days = updated.values.sorted { $0.dayStart < $1.dayStart }
        dirty = true
        prune(at: sample.date)
    }

    private func prune(at date: Date) {
        let today = calendar.startOfDay(for: date)
        guard let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: today) else { return }
        let kept = days.filter { $0.dayStart >= cutoff && $0.dayStart <= today }
        if kept != days { days = kept; dirty = true }
    }

    private func persist(at currentUptime: TimeInterval) {
        guard dirty, canWrite else { return }
        do {
            let data = try JSONEncoder().encode(State(days: days))
            try data.write(to: stateURL, options: .atomic)
            dirty = false
            lastPersistedUptime = currentUptime
        } catch {
            errorMessage = "Dinleme geçmişi kaydedilemedi: \(error.localizedDescription)"
            // Retry on the next checkpoint, keeping the in-memory measurements.
            lastPersistedUptime = currentUptime
        }
    }
}
