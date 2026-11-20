import Foundation

/// Kota kartı için anlık görünüm.
struct QuotaSnapshot: Equatable {
    var used: Int, limit: Int, remaining: Int
    /// Kota yeniden açılana kadar saniye (açıksa 0) ve servis kilidi bitişi.
    var waitSeconds: TimeInterval
    var blockedUntil: Date?
    /// Son bir saatin 10'ar dakikalık dilimleri (en eskiden en yeniye) ve her dilimdeki çağrı sayısı.
    var buckets: [Int]
    /// En eski çağrı pencereden düşünce kota bir hak kazanır (dolduysa).
    var nextFree: Date?
    var ratio: Double { limit == 0 ? 0 : Double(used) / Double(limit) }
}

/// İBB canlı konum servisi (FiloDurum) saatte en fazla 100 isteğe izin verir; aşılınca "Rate limit exceeded" ile saatlerce kapanabilir.
/// Bu sayaç, çağrı zamanlarını App Group'ta tutar (uygulama ve widget aynı kotayı paylaşır) ve sınırın altında kalır.
actor FleetBudget {
    static let shared = FleetBudget()
    static let hourlyLimit = 90                    // 100'ün altında pay bırakır
    private let defaults: UserDefaults
    private let key = "fleet.calls.v1", blockedKey = "fleet.blockedUntil.v1"
    private let now: () -> Date

    init(defaults: UserDefaults = SharedStore.defaults, now: @escaping () -> Date = { .now }) { self.defaults = defaults; self.now = now }

    private func calls() -> [TimeInterval] {
        let cutoff = now().timeIntervalSince1970 - 3600
        return (defaults.array(forKey: key) as? [TimeInterval] ?? []).filter { $0 > cutoff }
    }
    var used: Int { calls().count }
    var remaining: Int { max(0, Self.hourlyLimit - calls().count) }
    var blockedUntil: Date? {
        let value = defaults.double(forKey: blockedKey)
        return value > now().timeIntervalSince1970 ? Date(timeIntervalSince1970: value) : nil
    }

    /// Kota kartı için tüm göstergeler tek çağrıda.
    func snapshot() -> QuotaSnapshot {
        let current = now(), list = calls()
        var buckets = Array(repeating: 0, count: 6)
        for t in list {
            let age = current.timeIntervalSince1970 - t                      // 0…3600 sn
            buckets[max(0, min(5, 5 - Int(age / 600)))] += 1
        }
        let full = list.count >= Self.hourlyLimit
        return QuotaSnapshot(used: list.count, limit: Self.hourlyLimit, remaining: max(0, Self.hourlyLimit - list.count), waitSeconds: waitSeconds(), blockedUntil: blockedUntil,
                             buckets: buckets, nextFree: full ? list.min().map { Date(timeIntervalSince1970: $0 + 3600) } : nil)
    }

    /// Bir çağrı hakkı ister; kota doluysa ya da servis bizi sınırladıysa false.
    func acquire() -> Bool {
        guard blockedUntil == nil else { return false }
        var list = calls()
        guard list.count < Self.hourlyLimit else { return false }
        list.append(now().timeIntervalSince1970)
        defaults.set(list, forKey: key)
        return true
    }
    /// Sunucu "Rate limit exceeded" derse: pencere dolana kadar (en az 10 dk) hiç çağrı yapılmaz.
    func serverRefused(minutes: Double = 15) {
        defaults.set(now().timeIntervalSince1970 + minutes * 60, forKey: blockedKey)
    }
    /// Kota yeniden açılana kadar tahmini süre (saniye); açıksa 0.
    func waitSeconds() -> TimeInterval {
        if let blocked = blockedUntil { return blocked.timeIntervalSince(now()) }
        let list = calls()
        guard list.count >= Self.hourlyLimit, let oldest = list.min() else { return 0 }
        return max(0, oldest + 3600 - now().timeIntervalSince1970)
    }
    /// Etkin hat sayısına göre güvenli yenileme aralığı: saatte 90 çağrı bütün hatlara bölünür (en az 30 sn).
    static func refreshInterval(activeLines: Int) -> TimeInterval { max(30, 3600 / Double(hourlyLimit) * Double(max(1, activeLines))) }
}
