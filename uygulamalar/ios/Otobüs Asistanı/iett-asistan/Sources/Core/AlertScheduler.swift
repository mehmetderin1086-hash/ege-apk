import BackgroundTasks
import Foundation
import UserNotifications

/// Yerel bildirim yardımcıları: izin, anında ve zamanlanmış bildirim, planlıları temizleme.
enum Notifier {
    static var paused: Bool { UserDefaults.standard.bool(forKey: "alerts.paused") }

    @discardableResult static func authorize() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    static func status() async -> UNAuthorizationStatus { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }

    static func content(title: String, body: String, important: Bool) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body; c.sound = .default
        c.interruptionLevel = important ? .timeSensitive : .active
        return c
    }
    /// Hemen (ya da `delay` sn sonra) gösterilen bildirim.
    static func post(id: String, title: String, body: String, important: Bool = false, delay: TimeInterval = 1) async {
        guard !paused else { return }
        let request = UNNotificationRequest(identifier: id, content: content(title: title, body: body, important: important), trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
    static func schedule(_ alert: PlannedAlert) async {
        let parts = IETTDates.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alert.fireDate)
        let request = UNNotificationRequest(identifier: alert.id, content: content(title: alert.title, body: alert.body, important: true), trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }
    static func clearPlanned() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(AlertPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    static func pendingPlannedCount() async -> Int {
        await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix(AlertPlanner.idPrefix) }.count
    }
}

/// Favori (hat, durak) kurallarını sefer saatlerinden zamanlanmış bildirimlere çevirir; uygulama kapalıyken de gelir.
enum AlertScheduler {
    /// Tek favori için planlanacak bildirimler (kotasız sefer saatleri ve güzergâh kayması; kural kapalıysa boş).
    static func alerts(for favorite: Favorite, rule: AlertRule, hat: (String) -> Hat?, client: IETTClient = .shared, store: RouteStore = .shared, now: Date = .now, limit: Int = 24) async -> [PlannedAlert] {
        guard rule.enabled, rule.passing || rule.origin else { return [] }
        let trips = (try? await client.timetable(line: favorite.line)) ?? []
        guard !trips.isEmpty else { return [] }
        let route = try? await store.route(favorite.line)
        let directions = route?.directions(serving: favorite.stopCode) ?? []
        let direction = directions.first ?? trips.first?.direction ?? "G"
        var offset = 0, originName = favorite.stopName
        if let route, let stops = route.stops[direction] {
            originName = stops.first?.name ?? originName
            if let index = route.stopIndex(code: favorite.stopCode, direction: direction), let hat = hat(favorite.line) {
                let geometry = RouteGeometry(stops: stops)
                offset = Timetable.offsetMinutes(tripMinutes: hat.tripMinutes, stopAlong: geometry.cumulative[index], routeLength: geometry.length) ?? 0
            }
        }
        let directionSet = directions.isEmpty ? [direction] : directions
        func times(_ type: String, shift: Int) -> [Int] { Array(Set(directionSet.flatMap { Timetable.times(trips, dayType: $0 == "" ? type : type, direction: $0) })).sorted().map { $0 + shift } }
        return AlertPlanner.plan(favorite: favorite, rule: rule, originName: originName, passingTimes: { times($0, shift: offset) }, originTimes: { Timetable.times(trips, dayType: $0, direction: direction) }, now: now, limit: limit)
    }

    /// Önceki planı siler, güncel favoriler ve kurallarla yeniden kurar. Zamanlanan bildirim sayısını döner.
    @discardableResult
    static func reschedule(favorites: [Favorite], rules: [String: AlertRule], hat: (String) -> Hat?, client: IETTClient = .shared, store: RouteStore = .shared, now: Date = .now) async -> Int {
        await Notifier.clearPlanned()
        guard !Notifier.paused else { return 0 }
        var all: [PlannedAlert] = []
        for favorite in favorites {
            guard let rule = rules[favorite.id] else { continue }
            all += await alerts(for: favorite, rule: rule, hat: hat, client: client, store: store, now: now)
        }
        let capped = AlertPlanner.capped(all)
        for alert in capped { await Notifier.schedule(alert) }
        return capped.count
    }
}

/// Duyuru uyarıları: favori hatlardaki yeni duyuruları şiddetine göre (🔴 iptal/ertelendi, 🟠 uyarı, 🔵 bilgi) bildirir; her duyuru bir kez.
enum NoticeAlerts {
    private static let seenKey = "notices.seen.v1"
    static var onlyImportant: Bool { UserDefaults.standard.object(forKey: "alerts.noticesImportantOnly") as? Bool ?? true }

    static func seen() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? []) }
    static func mark(_ ids: [String]) { UserDefaults.standard.set(Array(seen().union(ids).suffix(400)), forKey: seenKey) }

    /// `lines`: bildirimi açık favori hatlar. Yeni (daha önce bildirilmemiş) ve uygun şiddetteki duyurular bildirilir ve geri döner.
    @discardableResult
    static func process(_ notices: [Duyuru], lines: Set<String>) async -> [Duyuru] {
        guard !Notifier.paused, !lines.isEmpty else { return [] }
        let known = seen()
        var fresh: [Duyuru] = []
        for notice in notices where lines.contains(notice.line) && !known.contains(notice.id) {
            fresh.append(notice)
            let severity = NoticeClassifier.severity(notice.message)
            if onlyImportant && severity == .info { continue }
            await Notifier.post(id: "notice|\(notice.id)", title: "\(severity.emoji) \(notice.line) · \(severity.title)", body: notice.message, important: severity == .critical)
        }
        mark(fresh.map(\.id))
        return fresh
    }
}

/// Arka plan yenileme: duyuruları kontrol eder ve planlı bildirimleri tazeler (iOS zamanlamayı kendisi belirler, garanti yoktur).
enum BackgroundRefresh {
    static let identifier = "com.mehmetderin.iettasistan.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            schedule()   // bir sonrakini hemen iste
            let work = Task {
                await run()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 20 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    static func run() async {
        let favorites = SharedStore.loadFavorites(), rules = SharedStore.loadRules()
        guard !favorites.isEmpty else { return }
        let noticeLines = Set(favorites.filter { rules[$0.id]?.notices ?? true }.map(\.line))
        if let notices = try? await IETTClient.shared.notices() { await NoticeAlerts.process(notices, lines: noticeLines) }
        let stats = SharedStore.loadHatStats()
        await AlertScheduler.reschedule(favorites: favorites, rules: rules, hat: { code in stats[code].map { Hat(code: code, name: "", lengthKm: $0.first, tripMinutes: $0.last) } })
    }
}
