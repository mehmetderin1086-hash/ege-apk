import Foundation

enum AlertSeverity: Int, Comparable, Codable {
    case info = 0, warning = 1, critical = 2
    static func < (a: AlertSeverity, b: AlertSeverity) -> Bool { a.rawValue < b.rawValue }
    var emoji: String { switch self { case .info: "🔵"; case .warning: "🟠"; case .critical: "🔴" } }
    var title: String { switch self { case .info: "Duyuru"; case .warning: "Uyarı"; case .critical: "İptal / ertelendi" } }
}

/// Duyuru metnini şiddetine göre sınıflandırır (harf büyüklüğü ve aksan duyarsız).
enum NoticeClassifier {
    private static let critical = ["iptal", "ertelen", "yapilamamakta", "yapilamayacak", "hizmet disi", "durdurul", "kaldirildi", "sefer yok"]
    private static let warning = ["gecik", "aksama", "degisiklik", "degistirildi", "farkli guzergah", "alternatif", "kapali", "yol calisma", "kaza", "ariza", "yogunluk", "trafik", "mac", "miting", "etkinlik", "kar yagis", "tadilat", "yerine"]

    static func severity(_ text: String) -> AlertSeverity {
        let t = fold(text)
        if critical.contains(where: t.contains) { return .critical }
        if warning.contains(where: t.contains) { return .warning }
        return .info
    }
    /// En yüksek şiddet (boşsa nil) ve şiddete göre sayım.
    static func summary(_ notices: [Duyuru]) -> (top: AlertSeverity?, counts: [AlertSeverity: Int]) {
        var counts: [AlertSeverity: Int] = [:]
        for notice in notices { counts[severity(notice.message), default: 0] += 1 }
        return (counts.keys.max(), counts)
    }
}

/// Favori (hat, durak) için bildirim kuralı: hangi gün/saatlerde, hangi türde, kaç dakika önce.
struct AlertRule: Codable, Hashable {
    var enabled = true
    var leadMinutes = 10
    /// Takvim hafta günleri (1 pazar … 7 cumartesi).
    var days: Set<Int> = [2, 3, 4, 5, 6]
    var startMinute = 6 * 60 + 30
    var endMinute = 9 * 60 + 30
    /// Planlı geçişten `leadMinutes` önce (uygulama kapalıyken de gelir).
    var passing = true
    /// Hat çıkış durağından kalkarken (planlı kalkış saatinden önce).
    var origin = false
    /// Canlı: yaklaşıyor / durakta (uygulama açıkken ya da arka planda kısa süre).
    var live = true
    /// Gecikme uyarısı (canlı konum planlı saatten çok geç gösterince).
    var delay = true
    /// Duyuru, iptal, ertelendi (arka plan yenileme ve uygulama açıkken).
    var notices = true

    static let morning = AlertRule(startMinute: 6 * 60 + 30, endMinute: 9 * 60 + 30)
    static let evening = AlertRule(startMinute: 16 * 60 + 30, endMinute: 19 * 60 + 30)
    static let allDay = AlertRule(startMinute: 0, endMinute: 24 * 60 - 1)

    func isActive(on date: Date) -> Bool {
        guard enabled else { return false }
        let c = IETTDates.calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return days.contains(c.weekday ?? 0) && minute >= startMinute && minute <= endMinute
    }
}

struct PlannedAlert: Identifiable, Hashable {
    enum Kind: String { case passing, origin }
    let id: String
    let fireDate: Date
    let title: String
    let body: String
    let kind: Kind
}

enum AlertPlanner {
    static let idPrefix = "plan|"

    /// Önümüzdeki `horizonDays` gün için, kuralın gün ve saat aralığına düşen planlı geçişlerden `lead` dakika öncesine bildirim kurar.
    /// `passingTimes(dayType)`: durağa tahmini geçiş dakikaları; `originTimes(dayType)`: hattın çıkış durağındaki kalkış dakikaları.
    static func plan(favorite: Favorite, rule: AlertRule, originName: String, passingTimes: (String) -> [Int], originTimes: (String) -> [Int],
                     now: Date = .now, horizonDays: Int = 2, limit: Int = 24) -> [PlannedAlert] {
        guard rule.enabled, rule.passing || rule.origin else { return [] }
        var result: [PlannedAlert] = []
        let calendar = IETTDates.calendar
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            guard rule.days.contains(calendar.component(.weekday, from: day)) else { continue }
            let type = IETTDates.dayType(day), start = calendar.startOfDay(for: day)
            let stamp = Int(start.timeIntervalSince1970 / 86400)
            func add(_ minutes: [Int], kind: PlannedAlert.Kind) {
                for m in minutes where m >= rule.startMinute && m <= rule.endMinute {
                    let fire = start.addingTimeInterval(Double(m - rule.leadMinutes) * 60)
                    guard fire > now.addingTimeInterval(20) else { continue }
                    let clock = Timetable.format(m)
                    let when = rule.leadMinutes == 0 ? "şimdi" : "\(rule.leadMinutes) dk sonra"
                    result.append(PlannedAlert(
                        id: "\(idPrefix)\(favorite.id)|\(stamp)|\(m)|\(kind.rawValue)", fireDate: fire,
                        title: kind == .passing ? "\(favorite.line) · \(favorite.stopName)" : "\(favorite.line) kalkıyor",
                        body: kind == .passing ? (rule.leadMinutes == 0 ? "Şimdi geçiyor (\(clock))" : "\(when) geçecek (\(clock))") : "\(originName) çıkışından \(clock) seferi \(when) kalkıyor",
                        kind: kind))
                }
            }
            if rule.passing { add(passingTimes(type), kind: .passing) }
            if rule.origin { add(originTimes(type), kind: .origin) }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// iOS en çok 64 bekleyen yerel bildirim tutar: tüm kuralların planı zamana göre sıralanıp sınırlanır.
    static func capped(_ alerts: [PlannedAlert], limit: Int = 56) -> [PlannedAlert] { Array(alerts.sorted { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }.prefix(limit)) }
}

/// Canlı konumdan hesaplanan varış, planlı geçişten çok sonraysa gecikme saniyesi (aksi halde nil).
enum DelayEstimator {
    /// `scheduled`: bugünün planlı geçiş anları. En yakın planlı geçişle karşılaştırılır; ardışık seferler arası `minHeadway` dk'dan azsa
    /// eşleşme belirsiz olduğundan uyarı verilmez.
    static func delay(scheduled: [Date], arrival: Date, threshold: TimeInterval = 6 * 60, minHeadway: TimeInterval = 12 * 60) -> TimeInterval? {
        let sorted = scheduled.sorted()
        guard let nearest = sorted.min(by: { abs($0.timeIntervalSince(arrival)) < abs($1.timeIntervalSince(arrival)) }) else { return nil }
        let gaps = zip(sorted, sorted.dropFirst()).map { $1.timeIntervalSince($0) }
        if let smallest = gaps.min(), smallest < minHeadway { return nil }
        let late = arrival.timeIntervalSince(nearest)
        return late >= threshold && late <= 45 * 60 ? late : nil
    }
}
