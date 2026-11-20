import Foundation
import Testing
@testable import IETTAsistan

struct AlertTests {
    private let cal = IETTDates.calendar
    private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }   // 26 Ekim 2026 = Pazartesi
    private let fav = Favorite(line: "500T", stopCode: 1, stopName: "4.LEVENT METRO", lat: 41, lon: 29)

    @Test func classifiesNoticesBySeverity() {
        #expect(NoticeClassifier.severity("SEFERLERİMİZ GEÇİCİ OLARAK İPTAL EDİLMİŞTİR") == .critical)
        #expect(NoticeClassifier.severity("Maç nedeniyle sefer saati ertelenmiştir") == .critical)
        #expect(NoticeClassifier.severity("RECEP PEKER CADDESİ KAPALIDIR, güzergâh değişikliği") == .warning)
        #expect(NoticeClassifier.severity("Araçlarımız trafik yoğunluğu nedeniyle gecikmeli") == .warning)
        #expect(NoticeClassifier.severity("Yeni hat bilgisi yayında") == .info)
        let notices = [Duyuru(line: "A", message: "iptal"), Duyuru(line: "B", message: "kapalıdır"), Duyuru(line: "C", message: "kapalıdır"), Duyuru(line: "D", message: "merhaba")]
        let summary = NoticeClassifier.summary(notices)
        #expect(summary.top == .critical && summary.counts == [.critical: 1, .warning: 2, .info: 1])
        #expect(NoticeClassifier.summary([]).top == nil && AlertSeverity.critical > .warning)
    }
    @Test func ruleActivityFollowsDaysAndWindow() {
        let rule = AlertRule.morning                                // hafta içi 06:30-09:30
        #expect(rule.isActive(on: date(26, 7, 0)) && !rule.isActive(on: date(26, 10, 0)) && !rule.isActive(on: date(31, 7, 0)))   // 31 Ekim cumartesi
        var off = rule; off.enabled = false
        #expect(!off.isActive(on: date(26, 7, 0)))
        #expect(AlertRule.allDay.isActive(on: date(31, 3, 0)) == false)   // varsayılan günler hafta içi
    }
    @Test func plansAlertsOnlyInsideWindowAndDaysAndInTheFuture() {
        var rule = AlertRule.morning; rule.leadMinutes = 10
        let times: (String) -> [Int] = { type in type == "I" ? [6 * 60, 7 * 60 + 15, 8 * 60 + 40, 9 * 60 + 45, 17 * 60] : [8 * 60] }
        // Pazartesi 07:00: bugün 07:15 (fire 07:05) ve 08:40 geçerli; 06:00 pencere dışı ve geçmiş; 09:45/17:00 pencere dışı; yarın (salı) 07:15 ve 08:40.
        let alerts = AlertPlanner.plan(favorite: fav, rule: rule, originName: "ŞİFA", passingTimes: times, originTimes: { _ in [] }, now: date(26, 7, 0))
        #expect(alerts.count == 4)
        #expect(alerts.map(\.fireDate) == [date(26, 7, 5), date(26, 8, 30), date(27, 7, 5), date(27, 8, 30)])
        #expect(alerts[0].title == "500T · 4.LEVENT METRO" && alerts[0].body == "10 dk sonra geçecek (07:15)")
        #expect(Set(alerts.map(\.id)).count == 4 && alerts.allSatisfy { $0.id.hasPrefix(AlertPlanner.idPrefix) })
        // Cuma akşamı: hafta sonu günleri kapsam dışı; salı-cuma kuralıyla cumartesi/pazar hiç üretilmez.
        let weekend = AlertPlanner.plan(favorite: fav, rule: rule, originName: "", passingTimes: times, originTimes: { _ in [] }, now: date(30, 12, 0), horizonDays: 3)
        #expect(weekend.isEmpty)
    }
    @Test func supportsOriginDeparturesLeadZeroAndLimits() {
        var rule = AlertRule.allDay; rule.days = Set(1...7); rule.passing = false; rule.origin = true; rule.leadMinutes = 0
        let alerts = AlertPlanner.plan(favorite: fav, rule: rule, originName: "ŞİFA SONDURAK", passingTimes: { _ in [] }, originTimes: { _ in [9 * 60, 12 * 60] }, now: date(26, 8, 0), horizonDays: 1)
        #expect(alerts.count == 2 && alerts[0].kind == .origin && alerts[0].title == "500T kalkıyor")
        #expect(alerts[0].body == "ŞİFA SONDURAK çıkışından 09:00 seferi şimdi kalkıyor")
        var many = AlertRule.allDay; many.days = Set(1...7)
        let flood = AlertPlanner.plan(favorite: fav, rule: many, originName: "", passingTimes: { _ in Array(stride(from: 0, to: 1400, by: 5)) }, originTimes: { _ in [] }, now: date(26, 0, 0), horizonDays: 2, limit: 24)
        #expect(flood.count == 24 && flood == flood.sorted { $0.fireDate < $1.fireDate })
        #expect(AlertPlanner.capped(flood + flood.map { PlannedAlert(id: $0.id + "x", fireDate: $0.fireDate, title: "", body: "", kind: .passing) }, limit: 30).count == 30)
        var disabled = rule; disabled.enabled = false
        #expect(AlertPlanner.plan(favorite: fav, rule: disabled, originName: "", passingTimes: { _ in [600] }, originTimes: { _ in [600] }, now: date(26, 8, 0)).isEmpty)
    }
    @Test func delayIsReportedOnlyForClearLateArrivals() {
        let base = date(26, 8, 0)
        let schedule = [base, base.addingTimeInterval(20 * 60), base.addingTimeInterval(40 * 60)]
        let late = DelayEstimator.delay(scheduled: schedule, arrival: base.addingTimeInterval(9 * 60))
        #expect(late != nil && abs(late! - 540) < 0.01)       // 20 dk aralıkta 9 dk geç
        #expect(DelayEstimator.delay(scheduled: schedule, arrival: base.addingTimeInterval(3 * 60)) == nil)         // eşik altı
        #expect(DelayEstimator.delay(scheduled: schedule, arrival: base.addingTimeInterval(-2 * 60)) == nil)        // erken
        #expect(DelayEstimator.delay(scheduled: [base, base.addingTimeInterval(8 * 60)], arrival: base.addingTimeInterval(7 * 60)) == nil)   // sık seferde belirsiz
        #expect(DelayEstimator.delay(scheduled: [], arrival: base) == nil)
    }
    @Test func rulesPersistThroughSharedStore() {
        let defaults = UserDefaults(suiteName: "rules-\(UUID().uuidString)")!
        var rule = AlertRule.evening; rule.leadMinutes = 15; rule.origin = true
        SharedStore.saveRules(["500T-1": rule], to: defaults)
        #expect(SharedStore.loadRules(from: defaults) == ["500T-1": rule])
        #expect(SharedStore.loadRules(from: UserDefaults(suiteName: "rules-\(UUID().uuidString)")!).isEmpty)
    }
}
