import CoreLocation
import Foundation
import Testing
@testable import IETTAsistan

struct CoreTests {
    private func soap(_ json: String) -> Data {
        Data("<?xml version=\"1.0\"?><soap:Envelope xmlns:soap=\"x\"><soap:Body><R xmlns=\"t\"><GetHat_jsonResult>\(json)</GetHat_jsonResult></R></soap:Body></soap:Envelope>".utf8)
    }
    @Test func soapResultAndFault() throws {
        let json = try IETTClient.extractJSON(from: soap("[{&quot;SHATKODU&quot;:&quot;500T&quot;,&quot;SHATADI&quot;:&quot;A &amp;amp; B&quot;}]"))
        let hats = try JSONDecoder().decode([Hat].self, from: json)
        #expect(hats.first?.code == "500T" && hats.first?.name == "A &amp; B")
        let fault = Data("<soap:Envelope xmlns:soap=\"x\"><soap:Body><soap:Fault><faultstring>Hat Kodu Girmeden</faultstring></soap:Fault></soap:Body></soap:Envelope>".utf8)
        #expect(throws: IETTError.self) { try IETTClient.extractJSON(from: fault) }
    }
    @Test func requestEnvelopeEscapesParameters() {
        let body = String(decoding: IETTClient.envelope(operation: "Op", parameters: [("HatKodu", "A&<B>")]), as: UTF8.self)
        #expect(body.contains("<HatKodu>A&amp;&lt;B&gt;</HatKodu>") && body.contains("<Op xmlns=\"http://tempuri.org/\">"))
    }
    @Test func modelsDecodeMixedTypesAndSkipBadRecords() throws {
        let buses = Data(#"[{"kapino":"C-1","boylam":"29.1","enlem":41.0,"hatkodu":"500T","guzergahkodu":"500T_G_D0","yon":"X","son_konum_zamani":"2026-10-27 20:49:58","yakinDurakKodu":"401351"},{"kapino":"C-2","boylam":"bozuk"}]"#.utf8)
        let decoded = try JSONDecoder().decode([FailableDecodable<Bus>].self, from: buses).compactMap(\.value)
        #expect(decoded.count == 1 && decoded[0].direction == "G" && decoded[0].nearStop == 401351 && decoded[0].lastSeen != nil)
        let stop = try JSONDecoder().decode(Durak.self, from: Data(#"{"SDURAKKODU":100022,"SDURAKADI":"OKTAY","KOORDINAT":"POINT (28.695 41.0046)","ILCEADI":"Esenyurt","SYON":"X"}"#.utf8))
        #expect(stop.code == 100022 && abs(stop.lat - 41.0046) < 1e-6 && abs(stop.lon - 28.695) < 1e-6)
    }
    @Test func turkishFoldingIsDiacriticInsensitive() {
        #expect(fold("ŞİŞLİ Kadıköy İskele") == "sisli kadikoy iskele")
    }

    // Kuzeyden güneye giden bir araç: durak güneyde. 0,001° enlem ≈ 111 m.
    private func bus(_ id: String, lat: Double, at: Date) -> Bus {
        Bus(plate: id, lat: lat, lon: 29.0, line: "X", routeCode: "X_G_D0", lastSeen: at)
    }
    private let stop = CLLocationCoordinate2D(latitude: 41.000, longitude: 29.0)
    @Test func approachingBusGetsMeasuredETA() {
        let tracker = LiveTracker(), now = Date()
        tracker.ingest([bus("A", lat: 41.010, at: now.addingTimeInterval(-40))], now: now.addingTimeInterval(-40))
        tracker.ingest([bus("A", lat: 41.008, at: now)], now: now)   // 222 m / 40 s ≈ 5,5 m/s
        let eta = tracker.etas(buses: [bus("A", lat: 41.008, at: now)], stop: stop, now: now)
        #expect(eta.count == 1 && eta[0].state == .approaching)
        #expect(eta[0].minutes > 3 && eta[0].minutes < 6, "\(eta[0].minutes)")
    }
    @Test func recedingBusIsDroppedAndUnknownDirectionIsEstimated() {
        let tracker = LiveTracker(), now = Date()
        tracker.ingest([bus("B", lat: 40.995, at: now.addingTimeInterval(-40))], now: now.addingTimeInterval(-40))
        tracker.ingest([bus("B", lat: 40.993, at: now)], now: now)   // durağı geçmiş, uzaklaşıyor
        #expect(tracker.etas(buses: [bus("B", lat: 40.993, at: now)], stop: stop, now: now).isEmpty)
        let fresh = LiveTracker()
        let eta = fresh.etas(buses: [bus("C", lat: 41.005, at: now)], stop: stop, now: now)
        #expect(eta.count == 1 && eta[0].state == .estimated && eta[0].text.hasPrefix("~"))
        #expect(fresh.etas(buses: [bus("D", lat: 41.080, at: now)], stop: stop, now: now).isEmpty)   // 9 km, yönü bilinmeyen
    }
    @Test func atStopAndStaleBuses() {
        let tracker = LiveTracker(), now = Date()
        let eta = tracker.etas(buses: [bus("E", lat: 41.0003, at: now)], stop: stop, now: now)
        #expect(eta.first?.state == .atStop && eta.first?.text == "Durakta")
        #expect(tracker.etas(buses: [bus("F", lat: 41.001, at: now.addingTimeInterval(-900))], stop: stop, now: now).isEmpty)
    }
    @Test func headingFollowsMovement() {
        let tracker = LiveTracker(), now = Date()
        tracker.ingest([bus("H", lat: 41.010, at: now.addingTimeInterval(-30))], now: now.addingTimeInterval(-30))
        tracker.ingest([bus("H", lat: 41.009, at: now)], now: now)
        let heading = tracker.heading(of: "H")
        #expect(heading != nil && abs(heading! - 180) < 5)
    }
    @Test func timetableUsesDayTypeAndDirection() {
        let istanbul = IETTDates.calendar
        let monday = istanbul.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 10, minute: 0))!
        #expect(IETTDates.dayType(monday) == "I")
        #expect(IETTDates.dayType(istanbul.date(byAdding: .day, value: 5, to: monday)!) == "C")
        #expect(IETTDates.dayType(istanbul.date(byAdding: .day, value: 6, to: monday)!) == "P")
        let trips = [PlannedTrip(line: "X", direction: "G", dayType: "I", time: "10:15"), PlannedTrip(line: "X", direction: "G", dayType: "I", time: "09:00"),
                     PlannedTrip(line: "X", direction: "D", dayType: "I", time: "10:20"), PlannedTrip(line: "X", direction: "G", dayType: "C", time: "10:30")]
        let next = Timetable.next(trips, direction: "G", now: monday)
        #expect(next.map(\.time) == ["10:15"] && next[0].minutes == 15)
    }
    @MainActor @Test func assistantUnderstandsTurkishQuestions() {
        let lines = [Hat(code: "500T", name: "TUZLA"), Hat(code: "14M", name: "X"), Hat(code: "20D", name: "Y")]
        #expect(LocalAssistant.parse("500T nerede?", lines: lines) == .status("500T"))
        #expect(LocalAssistant.parse("Kadıköy iskele durağına 14m kaç dk?", lines: lines) == .eta("14M", "kadikoy iskele"))
        #expect(LocalAssistant.parse("yakınımdaki duraklar", lines: lines) == .nearby)
        #expect(LocalAssistant.parse("20D duyuru var mı", lines: lines) == .notices("20D"))
        #expect(LocalAssistant.parse("merhaba", lines: lines) == .help)
        #expect(LocalAssistant.parse("tuzla otobüsü", lines: lines) == .search("tuzla otobüsü"))
    }
}
