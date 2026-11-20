import Foundation
import Testing
@testable import IETTAsistan

struct FleetBudgetTests {
    private final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_800_000_000) }
    private func budget(_ clock: Clock) -> FleetBudget {
        FleetBudget(defaults: UserDefaults(suiteName: "fleet-\(UUID().uuidString)")!, now: { clock.date })
    }
    @Test func neverExceedsTheHourlyLimitAndReopensAfterTheWindow() async {
        let clock = Clock(), budget = budget(clock)
        var granted = 0
        for _ in 0..<(FleetBudget.hourlyLimit + 25) { if await budget.acquire() { granted += 1 } }
        #expect(granted == FleetBudget.hourlyLimit)
        let left = await budget.remaining
        #expect(left == 0)
        let wait = await budget.waitSeconds()
        #expect(wait > 3500 && wait <= 3600)
        clock.date.addTimeInterval(3601)
        let reopened = await budget.acquire(), afterReopen = await budget.remaining
        #expect(reopened && afterReopen == FleetBudget.hourlyLimit - 1)
    }
    @Test func serverRefusalLocksUntilTheWindowPasses() async {
        let clock = Clock(), budget = budget(clock)
        let first = await budget.acquire()
        await budget.serverRefused(minutes: 10)
        let refused = await budget.acquire(), wait = await budget.waitSeconds()
        #expect(first && refused == false && abs(wait - 600) < 1)
        clock.date.addTimeInterval(601)
        let again = await budget.acquire()
        #expect(again)
    }
    @Test func refreshIntervalSplitsTheBudgetAcrossLines() {
        #expect(FleetBudget.refreshInterval(activeLines: 1) == 40)
        #expect(FleetBudget.refreshInterval(activeLines: 3) == 120)
        #expect(FleetBudget.refreshInterval(activeLines: 0) == 40)
        // Her hat bu aralıkla yenilenirse toplam çağrı sınırı aşmaz.
        for lines in 1...6 { #expect(Double(lines) * 3600 / FleetBudget.refreshInterval(activeLines: lines) <= Double(FleetBudget.hourlyLimit) + 0.001) }
    }
    @Test func etaCountsDownBetweenRefreshes() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let eta = BusETA(id: "A", minutes: 5, distance: 1000, state: .approaching, speedKmh: 18, asOf: t0)
        #expect(abs(eta.minutes(at: t0.addingTimeInterval(120)) - 3) < 0.001)
        #expect(eta.minutes(at: t0.addingTimeInterval(900)) == 0)
        #expect(BusETA(id: "B", minutes: 0, distance: 10, state: .atStop, speedKmh: 0, asOf: t0).minutes(at: t0.addingTimeInterval(60)) == 0)
    }
}

struct QuotaSnapshotTests {
    private final class Clock: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_800_000_000) }
    @Test func snapshotBucketsCallsByTenMinutesAndReportsWhenQuotaReopens() async {
        let clock = Clock()
        let budget = FleetBudget(defaults: UserDefaults(suiteName: "q-\(UUID().uuidString)")!, now: { clock.date })
        // t0'da 3 çağrı, 25 dk sonra 2, 55 dk sonra 1 çağrı.
        for _ in 0..<3 { _ = await budget.acquire() }
        clock.date.addTimeInterval(25 * 60); for _ in 0..<2 { _ = await budget.acquire() }
        clock.date.addTimeInterval(30 * 60); _ = await budget.acquire()
        let s = await budget.snapshot()                                   // şimdi t0+55 dk
        #expect(s.used == 6 && s.limit == FleetBudget.hourlyLimit && s.remaining == FleetBudget.hourlyLimit - 6 && s.buckets.count == 6)
        #expect(s.buckets == [3, 0, 2, 0, 0, 1], "\(s.buckets)")          // 55, 30 ve 0 dk önce
        #expect(s.nextFree == nil && s.blockedUntil == nil && s.waitSeconds == 0 && abs(s.ratio - 6.0 / 90) < 1e-9)
    }
    @Test func snapshotShowsBlockAndNextFreeTime() async {
        let clock = Clock()
        let budget = FleetBudget(defaults: UserDefaults(suiteName: "q-\(UUID().uuidString)")!, now: { clock.date })
        for _ in 0..<FleetBudget.hourlyLimit { _ = await budget.acquire() }
        var s = await budget.snapshot()
        #expect(s.remaining == 0 && s.ratio == 1 && s.nextFree == clock.date.addingTimeInterval(3600) && s.waitSeconds > 3500)
        await budget.serverRefused(minutes: 15)
        s = await budget.snapshot()
        #expect(s.blockedUntil == clock.date.addingTimeInterval(900) && s.waitSeconds >= 900)
    }
}
