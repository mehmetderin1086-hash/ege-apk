import ActivityKit
import Foundation

/// Podcast üretim ilerlemesi (Dynamic Island + kilit ekranı). Uygulama ve widget eklentisi ortak kullanır.
nonisolated struct GenerationActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var phase: String          // "Seslendiriliyor", "Birleştiriliyor", "Hazır", "Durdu"
        var done: Int
        var total: Int
        var finished: Bool
        /// #3: "Plan çıkarıldı · Konu 6/14 · Sahne 18/52" (eski sürüm durumlarında yok).
        var detail: String? = nil
        /// #3: bütün üretim boyunca gerçek oran (0…1; senaryo + seslendirme + birleştirme). Yoksa `done/total`.
        var fraction: Double? = nil
    }

    var title: String
    var episodeID: String
}
