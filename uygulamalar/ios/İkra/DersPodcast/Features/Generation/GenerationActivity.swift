import ActivityKit
import Foundation

/// Bölüm üretimi sürerken Dynamic Island / kilit ekranı etkinliği.
@MainActor
enum GenerationActivity {
    /// Bölüm kimliği → Activity kimliği. Nesneyi değil kimliği saklıyoruz; görev içinde yeniden bulunur (Sendable değil).
    private static var activityIDs: [UUID: String] = [:]

    /// Her güncellemede: uygulama güncellemeyi bırakırsa kart 3 dk sonra "eskimiş" görünür.
    nonisolated static let staleInterval: TimeInterval = 180

    /// Etkinlik nesnesi Sendable olmadığı için bulma ve güncelleme aynı (ana aktör dışı) bağlamda yapılır.
    @concurrent
    nonisolated private static func push(_ activityID: String, _ state: GenerationActivityAttributes.ContentState,
                                         end dismissal: ActivityUIDismissalPolicy? = nil) async {
        guard let activity = Activity<GenerationActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        let content = ActivityContent(state: state, staleDate: dismissal == nil ? Date.now.addingTimeInterval(staleInterval) : nil)
        if let dismissal {
            await activity.end(content, dismissalPolicy: dismissal)
        } else {
            await activity.update(content)
        }
    }

    static func update(_ id: UUID, title: String, phase: String, done: Int, total: Int, detail: String? = nil, fraction: Double? = nil) {
        // #3: BGContinuedProcessingTask sistem arayüzü gösterirken ikinci ilerleme arayüzü açılmaz.
        if GenerationBackground.isActive(id) {
            if let activityID = activityIDs.removeValue(forKey: id) {
                let state = GenerationActivityAttributes.ContentState(phase: phase, done: done, total: total, finished: false, detail: detail,
                                                              fraction: fraction)
                Task { await push(activityID, state, end: .immediate) }
            }
            return
        }
        let state = GenerationActivityAttributes.ContentState(phase: phase, done: done, total: total, finished: false, detail: detail,
                                                              fraction: fraction)
        if let activityID = activityIDs[id] {
            Task { await push(activityID, state) }
            return
        }
        // Uygulama yeniden açıldıysa aynı bölümün önceki etkinliğini kullan (kopya oluşturma).
        if let existing = Activity<GenerationActivityAttributes>.activities.first(where: { $0.attributes.episodeID == id.uuidString }) {
            activityIDs[id] = existing.id
            let activityID = existing.id
            Task { await push(activityID, state) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityIDs[id] = (try? Activity.request(attributes: GenerationActivityAttributes(title: title, episodeID: id.uuidString),
                                                 content: ActivityContent(state: state, staleDate: .now.addingTimeInterval(staleInterval))))?.id
    }

    /// Açılışta: üretimi sürmeyen bölümlere ait asılı etkinlikleri kapat.
    static func endOrphans(keeping generating: Set<UUID>) {
        for activity in Activity<GenerationActivityAttributes>.activities {
            guard let id = UUID(uuidString: activity.attributes.episodeID), !generating.contains(id) else { continue }
            let activityID = activity.id
            activityIDs[id] = nil
            let state = GenerationActivityAttributes.ContentState(phase: "Durdu", done: 0, total: 0, finished: false)
            Task { await push(activityID, state, end: .immediate) }
        }
    }

    static func end(_ id: UUID, success: Bool, total: Int) {
        guard let activityID = activityIDs.removeValue(forKey: id)
                ?? Activity<GenerationActivityAttributes>.activities.first(where: { $0.attributes.episodeID == id.uuidString })?.id
        else { return }
        let state = GenerationActivityAttributes.ContentState(phase: success ? "Hazır" : "Durdu", done: total, total: total, finished: success)
        let dismissal: ActivityUIDismissalPolicy = success ? .after(.now.addingTimeInterval(15 * 60)) : .immediate
        Task { await push(activityID, state, end: dismissal) }
    }
}
