import Foundation
import Testing
@testable import IETTAsistan

struct ShareTests {
    private let now = IETTDates.calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 6, minute: 45))!
    private let fav = Favorite(line: "500T", stopCode: 301341, stopName: "4.LEVENT METRO", lat: 41.0842, lon: 29.0073)
    private func eta(_ minutes: Double, _ state: BusETA.State = .approaching, left: Int? = 3) -> BusETA { BusETA(id: "C-1", minutes: minutes, distance: 900, state: state, speedKmh: 18, stopsLeft: left, asOf: now) }

    @Test func composedTextHonoursTheToggles() {
        let m = ShareBuilder.favorite(fav, etas: [eta(4)], now: now)
        let full = m.text(stamp: "28 Eki 06:45")
        #expect(full.hasPrefix("🚌 500T · 4.LEVENT METRO") && full.contains("📍 https://maps.apple.com/?ll=41.0842,29.0073") && full.contains("📲 Otobüs Asistanı: iettasistan://line/500T?stop=301341") && full.hasSuffix("⏱ 28 Eki 06:45"))
        let plain = m.text(includeMap: false, includeApp: false)
        #expect(!plain.contains("📍") && !plain.contains("📲") && !plain.contains("⏱"))
        #expect(m.body.contains("İlk araç: 4 dk sonra (3 durak kaldı)"))
    }
    @Test func etaTextCoversEveryState() {
        #expect(ShareBuilder.etaText(nil) == "yaklaşan araç görünmüyor")
        #expect(ShareBuilder.etaText(eta(0, .atStop), now: now) == "durakta")
        #expect(ShareBuilder.etaText(eta(7, .estimated, left: nil), now: now) == "yaklaşık 7 dk sonra")
        #expect(ShareBuilder.etaText(eta(0.2), now: now) == "yaklaşıyor (3 durak kaldı)")
        // Geçen süre düşülür: 4 dk'lık tahmin 2 dk sonra paylaşılırsa 2 dk.
        #expect(ShareBuilder.etaText(eta(4), now: now.addingTimeInterval(120)) == "2 dk sonra (3 durak kaldı)")
    }
    @Test func lineAndStopMessagesListTheKeyFacts() {
        let hat = Hat(code: "14M", name: "KADIKÖY - ÜMRANİYE")
        let line = ShareBuilder.line(hat, total: 7, byDirection: ["G": 4, "D": 3], nextDepartures: [("07:10", 25), ("07:30", 45)], nearestStop: "KADIKÖY ÇARŞI", eta: eta(3), now: now)
        #expect(line.body.contains("7 araç var (dönüş 3, gidiş 4)") && line.body.contains("En yakın durak: KADIKÖY ÇARŞI — 3 dk sonra") && line.body.contains("07:10 (25 dk sonra), 07:30 (45 dk sonra)"))
        #expect(ShareBuilder.line(hat, total: 0, byDirection: [:], nextDepartures: []).body.contains("canlı araç görünmüyor"))
        let stop = Durak(code: 7, name: "KADIKÖY ÇARŞI", lat: 41, lon: 29, district: "Kadıköy", direction: "ÜSKÜDAR")
        let arrivals = ShareBuilder.stopArrivals(stop, rows: [("14M", "ÜMRANİYE", "3 dk"), ("20D", "", "12:40")])
        #expect(arrivals.body.contains("(Kadıköy · ÜSKÜDAR, no 7)") && arrivals.body.contains("• 14M → ÜMRANİYE: 3 dk") && arrivals.body.contains("• 20D: 12:40"))
        #expect(ShareBuilder.stopArrivals(stop, rows: []).body.contains("yaklaşan araç bilgisi yok"))
        #expect(ShareBuilder.stop(stop).body == "KADIKÖY ÇARŞI durağı\nKadıköy · ÜSKÜDAR · durak no 7" && ShareBuilder.stop(stop).maps != nil)
    }
    @Test func tripAndTransferMessagesDescribeTheJourney() {
        let board = RouteStop(seq: 1, code: 1, name: "A DURAĞI", lat: 41, lon: 29), alight = RouteStop(seq: 5, code: 5, name: "B DURAĞI", lat: 41.01, lon: 29)
        let option = TripOption(line: "X", direction: "G", destination: "SON", board: board, alight: alight, stops: 4, rideMeters: 900, rideMinutes: 11.2, walkToBoard: 120, walkFromAlight: 80)
        let trip = ShareBuilder.trip(option, waitMinutes: 6)
        #expect(trip.title == "Yolculuk: A DURAĞI → B DURAĞI" && trip.body.contains("120 m yürü, A DURAĞI durağından bin") && trip.body.contains("4 durak (~11 dk)") && trip.body.contains("sıradaki planlı geçiş ~6 dk sonra"))
        #expect(ShareBuilder.trip(option, waitMinutes: 0).body.contains("şimdi bir sefer var") && !ShareBuilder.trip(option, waitMinutes: nil).body.contains("planlı geçiş"))
        let legA = TripLeg(line: "A", direction: "G", destination: "X", board: board, alight: alight, stops: 4, rideMeters: 900, rideMinutes: 10)
        let legB = TripLeg(line: "B", direction: "G", destination: "SON", board: alight, alight: RouteStop(seq: 9, code: 9, name: "C DURAĞI", lat: 41.02, lon: 29), stops: 3, rideMeters: 700, rideMinutes: 8)
        let transfer = ShareBuilder.transfer(TransferOption(first: legA, second: legB, walkToBoard: 100, walkFromAlight: 50))
        #expect(transfer.title == "Aktarmalı yolculuk: A → B" && transfer.body.contains("Aktarma: B DURAĞI") && transfer.body.contains("C DURAĞI durağında in"))
    }
    @Test func noticeBoardAndAnswerMessages() {
        let notice = Duyuru(line: "500T", lineName: "TUZLA", kind: "Günlük", updated: "Kayit Saati: 16:07", message: "Maç nedeniyle seferler ertelenmiştir.")
        let n = ShareBuilder.notice(notice)
        #expect(n.title == "500T · İptal / ertelendi" && n.body.hasPrefix("🔴 500T TUZLA") && n.body.contains("(Kayit Saati: 16:07)") && n.deep != nil)
        let stop = Durak(code: 1, name: "ÇOK PROGRAMLI LİSE", lat: 41, lon: 29)
        let rows = [BoardRow(line: "137", direction: "G", destination: "Sultaniye", arrival: now.addingTimeInterval(20), live: true, atStop: true, planned: now.addingTimeInterval(-300)),
                    BoardRow(line: "9H", direction: "D", destination: "Çekmeköy", arrival: now.addingTimeInterval(95 * 60), live: false, atStop: false)]
        let board = ShareBuilder.board(stop, rows: rows, now: now)
        #expect(board.body.contains("• 137 SULTANİYE: DURAKTA (canlı) ⚠ +5 dk GECİKME") && board.body.contains("• 9H ÇEKMEKÖY: 08:20 (tarife)"))
        #expect(ShareBuilder.answer("Merhaba").text(includeMap: false, includeApp: false) == "🚌 Otobüs Asistanı\n\nMerhaba")
        #expect(ShareBuilder.stamp(now).contains("28 Eki 06:45") && ShareBuilder.stamp(now).hasSuffix("tahmindir"))
    }
}
