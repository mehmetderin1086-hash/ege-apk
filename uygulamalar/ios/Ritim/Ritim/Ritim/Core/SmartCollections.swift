import Foundation

/// Live views over the local library; no network requests or background tasks.
enum SmartCollection: String, CaseIterable, Identifiable {
    case unheard, recent, rediscover, history
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unheard: return "Henüz dinlemediklerin"
        case .recent: return "Yeni eklenenler"
        case .rediscover: return "Yeniden keşfet"
        case .history: return "Son dinlenenler"
        }
    }
    var icon: String {
        switch self {
        case .unheard: return "sparkles"
        case .recent: return "plus.circle"
        case .rediscover: return "heart.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }
    var detail: String {
        switch self {
        case .unheard: return "Kütüphanende olup henüz çalmadığın müzikler."
        case .recent: return "Son 30 günde eklediğin müzikler."
        case .rediscover: return "En az 14 gündür dinlemediğin veya henüz çalmadığın beğeniler."
        case .history: return "Her parçanın son çalınma zamanına göre müziklerin."
        }
    }

    func tracks(in library: [MediaTrack], now: Date = Date()) -> [MediaTrack] {
        let audio = library.filter { $0.kind == .audio }
        let result: [MediaTrack]
        switch self {
        case .unheard:
            result = audio.filter { $0.playCount == 0 }
        case .recent:
            result = audio.filter { $0.addedAt >= now.addingTimeInterval(-30 * 86_400) && $0.addedAt <= now }
        case .rediscover:
            result = audio.filter { $0.isFavorite && ($0.lastPlayedAt == nil || $0.lastPlayedAt! <= now.addingTimeInterval(-14 * 86_400)) }
        case .history:
            result = audio.filter { $0.lastPlayedAt != nil }
        }
        return result.sorted {
            let left = self == .history ? $0.lastPlayedAt! : (self == .rediscover ? $0.lastPlayedAt ?? .distantPast : $0.addedAt)
            let right = self == .history ? $1.lastPlayedAt! : (self == .rediscover ? $1.lastPlayedAt ?? .distantPast : $1.addedAt)
            if left != right { return self == .rediscover ? left < right : left > right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
