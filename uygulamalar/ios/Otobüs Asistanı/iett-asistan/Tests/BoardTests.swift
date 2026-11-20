import Foundation
import Testing
@testable import IETTAsistan

struct BoardTests {
    private let now = IETTDates.calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12, minute: 0))!
    private func row(_ line: String, _ dir: String = "G", in seconds: TimeInterval, live: Bool = false, atStop: Bool = false) -> BoardRow {
        BoardRow(line: line, direction: dir, destination: "SON-\(line)", arrival: now.addingTimeInterval(seconds), live: live, atStop: atStop)
    }
    @Test func formatsRemainingTimeLikeAStopBoard() {
        #expect(BoardFormat.text(row("A", in: 30, live: true), now: now) == "YAKLAŞIYOR")
        #expect(BoardFormat.text(row("A", in: 30), now: now) == "ŞİMDİ")
        #expect(BoardFormat.text(row("A", in: 20, live: true, atStop: true), now: now) == "DURAKTA")
        #expect(BoardFormat.text(row("A", in: 61), now: now) == "2 dk")           // 61 sn → yukarı yuvarlanır
        #expect(BoardFormat.text(row("A", in: 7 * 60), now: now) == "7 dk")
        #expect(BoardFormat.text(row("A", in: 59 * 60), now: now) == "59 dk")
        #expect(BoardFormat.text(row("A", in: 75 * 60), now: now) == "13:15")      // 60 dk ve üzeri saat gösterir
    }
    @Test func liveRowsReplaceScheduledOnesDropPastAndSortByArrival() {
        let scheduled = [row("A", in: 600), row("B", in: 300), row("C", in: -120), row("A", "D", in: 900)]
        let live = [row("A", in: 240, live: true)]
        let merged = BoardFormat.merge(scheduled: scheduled, live: live, now: now)
        #expect(merged.map(\.id) == ["A|G", "B|G", "A|D"])
        #expect(merged[0].live && merged[0].arrival == now.addingTimeInterval(240))      // 600 sn'lik tarife yerine 240 sn'lik canlı
        #expect(!merged.contains { $0.line == "C" })                                    // 2 dk önce geçmiş
    }
    @Test func pagesSplitRowsAndLiveCandidatesRespectBudget() {
        let rows = (0..<10).map { row("L\($0)", in: Double($0) * 60 + 60) }
        let pages = BoardFormat.pages(rows, size: 4)
        #expect(pages.map(\.count) == [4, 4, 2] && BoardFormat.pages([], size: 4).isEmpty && BoardFormat.pages(rows, size: 0).isEmpty)
        let far = [row("X", in: 40 * 60), row("Y", in: 5 * 60), row("Z", in: 2 * 60), row("W", in: 10 * 60), row("V", in: 20 * 60)]
        #expect(BoardFormat.liveCandidates(far, now: now).map(\.line) == ["Z", "Y", "W", "V"])     // en yakın 4, 90 dk içi (X 40 dk, V 20 dk: ilk 4 = Z,Y,W,V)
        #expect(BoardFormat.liveCandidates([row("X", in: 100 * 60)], now: now).isEmpty)
    }
    @Test func scheduleMinutesBecomeAbsoluteTimes() {
        let date = BoardFormat.date(minutes: 14 * 60 + 35, on: now)
        let c = IETTDates.calendar.dateComponents([.hour, .minute, .day], from: date)
        #expect(c.hour == 14 && c.minute == 35 && c.day == 28)
        #expect(IETTDates.calendar.component(.day, from: BoardFormat.date(minutes: 24 * 60 + 10, on: now)) == 29)     // gece yarısını aşan sefer
    }
}

struct BoardDetailTests {
    private let now = IETTDates.calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12, minute: 0))!
    private func row(_ line: String = "A", in seconds: TimeInterval, live: Bool = false, atStop: Bool = false, planned: TimeInterval? = nil, origin: TimeInterval? = nil) -> BoardRow {
        BoardRow(line: line, direction: "G", destination: "Sultaniye", arrival: now.addingTimeInterval(seconds), live: live, atStop: atStop,
                 planned: planned.map { now.addingTimeInterval($0) }, origin: origin.map { now.addingTimeInterval($0) })
    }
    @Test func longTextAndClockFormatting() {
        #expect(BoardFormat.longText(30) == "30 sn" && BoardFormat.longText(7 * 60) == "7 dk" && BoardFormat.longText(61) == "2 dk")
        #expect(BoardFormat.longText(104 * 60) == "1 sa 44 dk" && BoardFormat.longText(120 * 60) == "2 sa" && BoardFormat.longText(-5) == "0 sn")
        #expect(BoardFormat.clock(now.addingTimeInterval(95 * 60)) == "13:35")
    }
    @Test func punctualityComparesLiveArrivalWithThePlan() {
        let late = BoardFormat.punctuality(row(in: 600, live: true, planned: 360))
        #expect(late?.text == "+4 dk GECİKME" && late?.tone == .late)
        let early = BoardFormat.punctuality(row(in: 300, live: true, planned: 540))
        #expect(early?.text == "4 dk ERKEN" && early?.tone == .early)
        #expect(BoardFormat.punctuality(row(in: 300, live: true, planned: 330))?.text == "ZAMANINDA")
        #expect(BoardFormat.punctuality(row(in: 300)) == nil && BoardFormat.punctuality(row(in: 300, live: true)) == nil)
    }
    @Test func detailLineShowsPlanArrivalClockAndOriginDeparture() {
        #expect(BoardFormat.detail(row(in: 600, live: true, planned: 360), now: now) == "PLAN 12:06 · +4 dk GECİKME")
        #expect(BoardFormat.detail(row(in: 12 * 60, origin: -60 + 5 * 60), now: now) == "VARIŞ 12:12 · ÇIKIŞ 12:04 · 4 dk")
        #expect(BoardFormat.detail(row(in: 104 * 60), now: now) == "1 sa 44 dk SONRA")
        // Çıkışı çoktan geçmiş sefer çıkış bilgisi göstermez.
        #expect(BoardFormat.detail(row(in: 12 * 60, origin: -10 * 60), now: now) == "VARIŞ 12:12")
        #expect(BoardFormat.detailLines(row(in: 104 * 60, origin: 80 * 60), now: now) == ["1 sa 44 dk SONRA", "ÇIKIŞ 13:20 · 1 sa 20 dk"])
        #expect(BoardFormat.detailLines(row(in: 600, live: true, planned: 360), now: now) == ["PLAN 12:06 · +4 dk GECİKME"])
    }
    @Test func mergeInheritsPlanAndOriginFromTheScheduledRow() {
        let scheduled = [row("A", in: 600, planned: 600, origin: -300)]
        let live = [row("A", in: 840, live: true)]
        let merged = BoardFormat.merge(scheduled: scheduled, live: live, now: now)
        #expect(merged.count == 1 && merged[0].live && merged[0].planned == now.addingTimeInterval(600) && merged[0].origin == now.addingTimeInterval(-300))
        #expect(BoardFormat.punctuality(merged[0])?.text == "+4 dk GECİKME")
    }
    @Test func tickerListsUpcomingArrivalsWithMinutesAndClock() {
        let rows = [row("137", in: 20, live: true, atStop: true), row("9H", in: 12 * 60), row("20D", in: 150 * 60), row("14M", in: 5 * 60, live: true, planned: 5 * 60 - 480)]
        let text = BoardFormat.ticker(rows, now: now)
        #expect(text.contains("137 SULTANİYE ▸ DURAKTA") && BoardFormat.upper("Sultaniye çarşı ığdır") == "SULTANİYE ÇARŞI IĞDIR")
        #expect(text.contains("9H SULTANİYE ▸ 12 dk (12:12)") && text.contains("20D SULTANİYE ▸ 14:30") && !text.contains("20D SULTANİYE ▸ 14:30 ("))
        #expect(text.contains("14M SULTANİYE ▸ 5 dk (12:05) ⚠ +8 dk GECİKME") && text.contains("     ●     "))
        #expect(BoardFormat.ticker([], now: now).isEmpty && BoardFormat.ticker(rows, now: now, limit: 1) == "137 SULTANİYE ▸ DURAKTA")
    }
}
