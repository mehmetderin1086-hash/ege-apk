import Foundation
import Testing
@testable import IETTAsistan

struct DetailTests {
    @Test func railStatusFiltersInactiveAndMalformedRows() throws {
        let data = Data(#"{"Success":true,"Data":[{"LineName":"M7","Description":"İşletme değişikliği","UpdateDate":"2026-10-15T19:45:11","IsActive":true},{"LineName":"M2","Description":"Eski","IsActive":false},{"LineName":17}]}"#.utf8)
        let result = try JSONDecoder().decode(RailStatusResponse.self, from: data)
        #expect(result.active.count == 1 && result.active.first?.LineName == "M7")
    }
    @MainActor @Test func railAssistantDoesNotInventTimes() async {
        let session = AssistantSession(model: AppModel())
        let reply = await session.reply(to: "M2 metro kaç dakika sonra gelecek?")
        #expect(reply.text.contains("doğrulayamıyorum"))
        #expect(reply.actions.contains(.open(.railStations, "İstasyonları aç", "tram.fill")))
    }
    @Test func metroStationsDecodeAndKeepMissingCoordinatesSafe() throws {
        let data = Data(#"{"Success":true,"Data":[{"Id":20,"Description":"Yenikapı","LineName":"M2","Order":1,"IsActive":null,"DetailInfo":{"Latitude":"41.0056","Longitude":"28.9513","Lift":4,"Escolator":14,"WC":true}},{"Id":21,"Description":"İsimsiz konum","LineName":"M2","Order":2,"IsActive":true,"DetailInfo":{"Latitude":null,"Longitude":null}},{"Id":22,"Description":"Kapalı","LineName":"M2","Order":3,"IsActive":false,"DetailInfo":null},{"Id":"bozuk"}]}"#.utf8)
        let response = try JSONDecoder().decode(RailResponse.self, from: data)
        #expect(response.stations.count == 2)
        #expect(response.stations[0].id == "M2:20")
        #expect(response.stations[0].coordinate?.latitude == 41.0056)
        #expect(response.stations[1].coordinate == nil)
        let snapshot = RailStationStore.Snapshot(stations: response.stations, fetchedAt: Date(timeIntervalSince1970: 100))
        let restored = try JSONDecoder().decode(RailStationStore.Snapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.stations == snapshot.stations && restored.fetchedAt == snapshot.fetchedAt)
    }
    @Test func stopMetadataDecodesAndSurvivesTheDiskCacheRoundTrip() throws {
        let json = Data(#"{"SDURAKKODU":100022,"SDURAKADI":"OKTAY","KOORDINAT":"POINT (28.695 41.0046)","ILCEADI":"Esenyurt","SYON":"BOGAZKÖY","AKILLI":"VAR","FIZIKI":"AÇIK","DURAK_TIPI":"İETTBAYRAK","ENGELLIKULLANIM":"Uygun Degil"}"#.utf8)
        let stop = try JSONDecoder().decode(Durak.self, from: json)
        #expect(stop.smart && stop.kind == "İETTBAYRAK" && stop.physical == "AÇIK" && stop.accessibility == "Uygun Degil")
        let again = try JSONDecoder().decode(Durak.self, from: JSONEncoder().encode(stop))
        #expect(again == stop)
        let plain = try JSONDecoder().decode(Durak.self, from: Data(#"{"SDURAKKODU":1,"SDURAKADI":"X","KOORDINAT":"POINT (29 41)","AKILLI":"YOK"}"#.utf8))
        #expect(!plain.smart && plain.kind.isEmpty)
    }
    @Test func lineInfoSummarisesDirectionsLengthAndSpeed() throws {
        let rows = [(41.010, 1), (41.008, 2), (41.006, 3)].map { "<Table><YON>G</YON><YON_ADI>SON</YON_ADI><SIRANO>\($0.1)</SIRANO><DURAKKODU>\(100 + $0.1)</DURAKKODU><DURAKADI>D\($0.1)</DURAKADI><XKOORDINATI>29.0</XKOORDINATI><YKOORDINATI>\($0.0)</YKOORDINATI></Table>" }.joined()
        let route = try LineRoute.parse(line: "X", soap: Data("<e><NewDataSet>\(rows)</NewDataSet></e>".utf8))
        let info = LineInfo.compute(hat: Hat(code: "X", name: "T", tariff: "2 BİLETLİ", lengthKm: 30, tripMinutes: 120), route: route)
        #expect(info.directions.count == 1 && info.directions[0].stopCount == 3 && info.directions[0].firstStop == "D1" && info.directions[0].lastStop == "D3")
        #expect(abs(info.directions[0].lengthKm - 0.444) < 0.02)
        #expect(info.averageSpeedKmh == 15 && info.tripText == "2 sa 0 dk")
        #expect(LineInfo.durationText(45.4) == "45 dk" && LineInfo.durationText(272.9) == "4 sa 33 dk")
        let bare = LineInfo.compute(hat: Hat(code: "Y", name: "T"), route: nil)
        #expect(bare.directions.isEmpty && bare.averageSpeedKmh == nil && bare.tripText == nil)
    }
    @Test func upcomingPassingTimesShiftByStopOffsetAndStopAtDayEnd() {
        let times = [350, 365, 380, 1430]
        #expect(Timetable.upcoming(times, offset: 10, nowMinutes: 370, count: 2) == [375, 390])
        #expect(Timetable.upcoming(times, offset: 0, nowMinutes: 1431, count: 3).isEmpty)
        #expect(Timetable.upcoming(times, offset: 0, nowMinutes: 0, count: 10) == times)
    }
    @Test func notesPersistAndEmptyNotesAreRemoved() {
        let defaults = UserDefaults(suiteName: "notes-\(UUID().uuidString)")!
        SharedStore.saveNotes(["line:500T": "Ön kapı", "stop:1": "Kalabalık"], to: defaults)
        #expect(SharedStore.loadNotes(from: defaults) == ["line:500T": "Ön kapı", "stop:1": "Kalabalık"])
        #expect(SharedStore.loadNotes(from: UserDefaults(suiteName: "notes-\(UUID().uuidString)")!).isEmpty)
    }
    @MainActor @Test func modelSetsAndClearsNotes() {
        let model = AppModel()
        let key = "line:TEST-\(UUID().uuidString)"
        model.setNote("  deneme  ", for: key)
        #expect(model.note(for: key) == "  deneme  ")
        model.setNote("   \n", for: key)
        #expect(model.note(for: key).isEmpty && model.notes[key] == nil)
    }
}
