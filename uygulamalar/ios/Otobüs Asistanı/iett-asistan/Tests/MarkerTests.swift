import Foundation
import Testing
@testable import IETTAsistan

struct MarkerTests {
    private func trip(_ time: String, marker: String = "", type: String = "Normal", route: String = "X_G_D0", day: String = "I", dir: String = "G") -> PlannedTrip {
        PlannedTrip(line: "X", routeCode: route, direction: dir, dayType: day, time: time, marker: marker, serviceType: type)
    }
    @Test func realApiRecordsDecodeWithTrimmedMarkerAndServiceType() throws {
        let json = Data(#"[{"SHATKODU":"137","HATADI":"X","SGUZERAH":"137_G_D2629","SYON":"G","SGUNTIPI":"I","GUZERGAH_ISARETI":"-1   ","SSERVISTIPI":"Gareli","DT":"19:30"},{"SHATKODU":"137","SGUZERAH":"137_G_D0","SYON":"G","SGUNTIPI":"I","GUZERGAH_ISARETI":null,"SSERVISTIPI":"ÖHO","DT":"05:20"}]"#.utf8)
        let trips = try JSONDecoder().decode([PlannedTrip].self, from: json)
        #expect(trips[0].marker == "-1" && trips[0].serviceType == "Gareli" && trips[0].routeCode == "137_G_D2629")
        #expect(trips[1].marker.isEmpty && trips[1].serviceType == "ÖHO")
        // Eski önbellek (alanlar yok) okunabilir.
        let old = try JSONDecoder().decode([PlannedTrip].self, from: Data(#"[{"SHATKODU":"X","SYON":"G","SGUNTIPI":"I","DT":"10:00"}]"#.utf8))
        #expect(old[0].marker.isEmpty && old[0].serviceType.isEmpty)
        // Disk önbelleği biçimi gidiş-dönüşte korunur.
        #expect(try JSONDecoder().decode([PlannedTrip].self, from: JSONEncoder().encode(trips)) == trips)
    }
    @Test func entriesDedupeMergeServiceTypesAndFlagOHOAndVariants() {
        let trips = [trip("10:00", type: "Normal"), trip("10:00", type: "Gareli"),                      // aynı saat/güzergâh: tek giriş, iki tür
                     trip("10:00", marker: "-1", route: "X_G_D2629"),                                   // aynı saat farklı güzergâh: ayrı giriş
                     trip("09:00", type: "ÖHO"), trip("11:00", day: "C"), trip("12:00", dir: "D")]
        let entries = Timetable.entries(trips, dayType: "I", direction: "G")
        #expect(entries.map(\.minutes) == [540, 600, 600])
        #expect(entries[0].isOHO && !entries[1].isOHO)
        let merged = entries.first { $0.minutes == 600 && !$0.isMarked }!
        #expect(merged.serviceTypes == ["Normal", "Gareli"] && !merged.isVariant)
        let marked = entries.first { $0.isMarked }!
        #expect(marked.isVariant && marked.markerText == "(-1)")
    }
    @Test func markerGroupsAndServiceTypeCountsSummariseTheTable() {
        let trips = [trip("10:00", marker: "-1", type: "Gareli", route: "X_G_D2629"), trip("11:00", marker: "-1", route: "X_G_D2629"), trip("12:00", marker: "S", route: "X_G_D6790"),
                     trip("13:00"), trip("14:00", type: "ÖHO")]
        let entries = Timetable.entries(trips, dayType: "I", direction: "G")
        let groups = Timetable.markerGroups(entries)
        #expect(groups.map(\.marker) == ["-1", "S"] && groups[0].count == 2 && groups[0].routeCodes == ["X_G_D2629"] && groups[0].sampleTimes == [600, 660])
        #expect(groups[0].serviceTypes == ["Gareli", "Normal"])
        let counts = Dictionary(uniqueKeysWithValues: Timetable.serviceTypeCounts(entries).map { ($0.type, $0.count) })
        #expect(counts == ["Normal": 3, "Gareli": 1, "ÖHO": 1])
    }
    @Test func shareTextShowsMarkersAndOHOLegend() {
        let entries = Timetable.entries([trip("05:30"), trip("06:00", marker: "-1", route: "X_G_D1"), trip("06:20", type: "ÖHO")], dayType: "I", direction: "G")
        let text = Timetable.shareText(line: "X", name: "TEST", destination: "SON", day: "Hafta içi", entries: entries)
        #expect(text.contains("05: 30") && text.contains("06: 00(-1) 20*") && text.hasSuffix("* ÖHO seferi") && text.hasPrefix("X · TEST\n→ SON · Hafta içi"))
        let shifted = Timetable.shareText(line: "X", name: "T", destination: "S", day: "G", entries: entries, offset: 10)
        #expect(shifted.contains("05: 40"))
        #expect(!Timetable.shareText(line: "X", name: "T", destination: "S", day: "G", entries: Timetable.entries([trip("05:30")], dayType: "I", direction: "G")).contains("ÖHO"))
    }
}
