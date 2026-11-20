import CoreLocation
import Foundation

struct BusSample { let date: Date; let coordinate: CLLocationCoordinate2D }

struct BusETA: Identifiable, Hashable {
    enum State { case atStop, approaching, estimated }
    let id: String, minutes: Double, distance: Double, state: State, speedKmh: Double
    var stopsLeft: Int? = nil
    /// Bu sürenin hesaplandığı an; canlı veri seyrek geldiğinden ekranda aradaki geçen süre düşülür.
    var asOf: Date = .now
    func minutes(at date: Date) -> Double { state == .atStop ? 0 : max(0, minutes - date.timeIntervalSince(asOf) / 60) }
    var wholeMinutes: Int { max(0, Int(minutes.rounded())) }
    /// "Durakta", "3 dk", "~7 dk" (yön henüz doğrulanmadıysa tahmini işareti)
    var text: String {
        switch state {
        case .atStop: "Durakta"
        case .approaching: wholeMinutes <= 0 ? "Yaklaşıyor" : "\(wholeMinutes) dk"
        case .estimated: wholeMinutes <= 0 ? "Yaklaşıyor" : "~\(wholeMinutes) dk"
        }
    }
    var distanceText: String { distance < 1000 ? "\(Int(distance.rounded() / 10) * 10) m" : String(format: "%.1f km", distance / 1000).replacingOccurrences(of: ".", with: ",") }
}

/// Araç konumlarını geçmişiyle tutar: yönü (durağa yaklaşıyor mu), hızı ve varış süresini canlı örneklerden çıkarır.
/// İETT güzergâh-durak sırası vermediği için süre kuş uçuşu mesafe × yol katsayısı ÷ ölçülen hız ile bulunur.
final class LiveTracker {
    static let roadFactor = 1.3, defaultSpeed = 5.0 /* m/s ≈ 18 km/h */, window: TimeInterval = 150, staleAfter: TimeInterval = 300
    private(set) var history: [String: [BusSample]] = [:]

    func ingest(_ buses: [Bus], now: Date = .now) {
        for bus in buses {
            var samples = history[bus.id, default: []]
            // Aynı konum tekrar gelirse (sunucu önbelleği) yeni örnek sayılmaz.
            if let last = samples.last, last.coordinate.distance(to: bus.coordinate) < 1 { continue }
            samples.append(.init(date: bus.lastSeen ?? now, coordinate: bus.coordinate))
            history[bus.id] = samples.filter { now.timeIntervalSince($0.date) <= Self.window * 2 }.suffix(12).map { $0 }
        }
        let live = Set(buses.map(\.id)); history = history.filter { live.contains($0.key) }
    }

    /// Son hareketten yön (derece, kuzey=0); duran araçta nil.
    func heading(of id: String) -> Double? {
        guard let samples = history[id], samples.count >= 2, let last = samples.last,
              let earlier = samples.dropLast().last(where: { $0.coordinate.distance(to: last.coordinate) >= 15 }) else { return nil }
        return earlier.coordinate.bearing(to: last.coordinate)
    }

    func etas(buses: [Bus], stop: CLLocationCoordinate2D, stopCode: Int? = nil, now: Date = .now) -> [BusETA] {
        var result: [BusETA] = []
        for bus in buses {
            if let seen = bus.lastSeen, now.timeIntervalSince(seen) > Self.staleAfter { continue }
            let current = bus.coordinate.distance(to: stop)
            let recent = (history[bus.id] ?? []).filter { now.timeIntervalSince($0.date) <= Self.window }
            var state = BusETA.State.estimated, speed = Self.defaultSpeed
            if let first = recent.first, let last = recent.last, recent.count >= 2, last.date.timeIntervalSince(first.date) >= 15 {
                let before = first.coordinate.distance(to: stop), moved = first.coordinate.distance(to: last.coordinate)
                let dt = last.date.timeIntervalSince(first.date)
                if before - current < -20, moved >= 40 { continue }            // uzaklaşıyor: durağı geçmiş
                if before - current > 20 { state = .approaching }
                let measured = moved / dt
                if measured > 1.5 { speed = min(12, max(2.5, 0.5 * measured + 0.5 * Self.defaultSpeed)) }
            } else if current > 5000 { continue }                               // yönü bilinmeyen uzak araç güven vermez
            if current < 60 || (current < 150 && bus.nearStop == stopCode && stopCode != nil) {
                result.append(.init(id: bus.id, minutes: 0, distance: current, state: .atStop, speedKmh: speed * 3.6)); continue
            }
            result.append(.init(id: bus.id, minutes: current * Self.roadFactor / speed / 60, distance: current, state: state, speedKmh: speed * 3.6))
        }
        return result.sorted { $0.minutes < $1.minutes }
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        let a = latitude * .pi / 180, b = other.latitude * .pi / 180, d = (other.longitude - longitude) * .pi / 180
        let y = sin(d) * cos(b), x = cos(a) * sin(b) - sin(a) * cos(b) * cos(d)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

enum Timetable {
    /// Bugünün (gün tipine göre) kalkış saatleri, seçilen yön için tekilleştirilmiş ve sıralı.
    static func departures(_ trips: [PlannedTrip], direction: String, now: Date = .now) -> [(time: String, date: Date)] {
        let type = IETTDates.dayType(now)
        let times = Set(trips.filter { $0.dayType == type && (direction.isEmpty || $0.direction == direction) }.map(\.time))
        return times.compactMap { t in IETTDates.departure(t, on: now).map { (t, $0) } }.sorted { $0.date < $1.date }
    }
    static func next(_ trips: [PlannedTrip], direction: String, now: Date = .now, count: Int = 3) -> [(time: String, minutes: Int)] {
        departures(trips, direction: direction, now: now).filter { $0.date >= now }.prefix(count).map { ($0.time, Int($0.date.timeIntervalSince(now) / 60)) }
    }
}

extension Timetable {
    static let dayTypes: [(code: String, title: String)] = [("I", "Hafta içi"), ("C", "Cumartesi"), ("P", "Pazar")]

    /// "14:35" → gün başından dakika (24:10 gibi gece yarısını aşan saatler 1450 olur).
    static func minutes(of time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        return parts.count >= 2 ? parts[0] * 60 + parts[1] : nil
    }
    static func format(_ minutes: Int) -> String { String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60) }

    /// Seçilen gün tipi ve yön için tekilleştirilmiş, sıralı kalkış dakikaları.
    static func times(_ trips: [PlannedTrip], dayType: String, direction: String) -> [Int] {
        Array(Set(trips.filter { $0.dayType == dayType && (direction.isEmpty || $0.direction == direction) }.compactMap { minutes(of: $0.time) })).sorted()
    }
    /// Saat satırlarına böler: [(saat, [dakikalar])]; 24+ saatler 24, 25 olarak ayrı satırda kalır.
    static func byHour(_ times: [Int]) -> [(hour: Int, minutes: [Int])] {
        Dictionary(grouping: times, by: { $0 / 60 }).map { ($0.key, $0.value.map { $0 % 60 }.sorted()) }.sorted { $0.hour < $1.hour }
    }
    struct Summary: Equatable { var first: Int, last: Int, count: Int, averageGap: Double?, shortestGap: Int?, longestGap: Int? }
    static func summary(_ times: [Int]) -> Summary? {
        guard let first = times.first, let last = times.last else { return nil }
        let gaps = zip(times, times.dropFirst()).map { $1 - $0 }
        return Summary(first: first, last: last, count: times.count, averageGap: gaps.isEmpty ? nil : Double(gaps.reduce(0, +)) / Double(gaps.count), shortestGap: gaps.min(), longestGap: gaps.max())
    }
    /// Şu an (dakika, Türkiye saati) için sıradaki sefer ve kaç dakika sonra.
    static func nextIndex(_ times: [Int], nowMinutes: Int) -> Int? { times.firstIndex { $0 >= nowMinutes } }
    static func nowMinutes(_ date: Date = .now) -> Int {
        let c = IETTDates.calendar.dateComponents([.hour, .minute], from: date); return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    /// Kalkış saatine, durağın hat üzerindeki konumuna oranla tahmini yolculuk süresi eklenir (hat sefer süresi × durak konumu / hat uzunluğu).
    static func offsetMinutes(tripMinutes: Double?, stopAlong: Double, routeLength: Double) -> Int? {
        guard let tripMinutes, routeLength > 0 else { return nil }
        return Int((tripMinutes * min(1, max(0, stopAlong / routeLength))).rounded())
    }
}

extension Timetable {
    /// Durakta bundan sonraki tahmini geçişler (kalkış + durak kayması); günün sonundaysa boş döner.
    static func upcoming(_ times: [Int], offset: Int, nowMinutes: Int, count: Int) -> [Int] {
        times.map { $0 + offset }.filter { $0 >= nowMinutes }.prefix(count).map { $0 }
    }
}

/// Hat künyesi: uzunluk, süre, ortalama hız, yön ve durak sayıları, yön başına sefer özeti.
struct LineInfo: Equatable {
    struct Direction: Equatable { var code: String, destination: String, firstStop: String, lastStop: String, stopCount: Int, lengthKm: Double }
    var directions: [Direction]
    var averageSpeedKmh: Double?
    var tripText: String?
    static func compute(hat: Hat, route: LineRoute?) -> LineInfo {
        let dirs: [Direction] = (route?.directions ?? []).compactMap { code in
            guard let route, let stops = route.stops[code], let first = stops.first, let last = stops.last else { return nil }
            return Direction(code: code, destination: route.destination(code), firstStop: first.name, lastStop: last.name, stopCount: stops.count, lengthKm: RouteGeometry(stops: stops).length / 1000)
        }
        let speed = hat.lengthKm.flatMap { km in hat.tripMinutes.map { $0 > 0 ? km / ($0 / 60) : nil } } ?? nil
        return LineInfo(directions: dirs, averageSpeedKmh: speed, tripText: hat.tripMinutes.map(durationText))
    }
    static func durationText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); return m >= 60 ? "\(m / 60) sa \(m % 60) dk" : "\(m) dk"
    }
}

extension Timetable {
    /// Tablodaki tek bir saat: işareti, sefer türü ve güzergâh kodu ile (resmî sitedeki kırmızı/siyah ve "(-1)" gösterimi).
    struct Entry: Hashable, Identifiable {
        var minutes: Int, marker: String, routeCode: String, serviceTypes: [String]
        var id: String { "\(minutes)|\(marker)|\(routeCode)" }
        /// Kırmızı gösterilen: özel halk otobüsü (ÖHO) seferi.
        var isOHO: Bool { serviceTypes.contains { fold($0).contains("oho") } }
        /// Asıl güzergâhtan (…_D0) farklı bir güzergâh koduyla çıkıyorsa işaretlidir.
        var isVariant: Bool { !routeCode.isEmpty && !routeCode.hasSuffix("_D0") }
        var isMarked: Bool { !marker.isEmpty }
        var markerText: String? { marker.isEmpty ? nil : "(\(marker))" }
    }
    /// Gün tipi ve yön için işaret/tür bilgili, (saat, işaret, güzergâh) başına tekilleştirilmiş sıralı kayıtlar.
    static func entries(_ trips: [PlannedTrip], dayType: String, direction: String) -> [Entry] {
        var map: [String: Entry] = [:]
        for trip in trips where trip.dayType == dayType && (direction.isEmpty || trip.direction == direction) {
            guard let minutes = minutes(of: trip.time) else { continue }
            let key = "\(minutes)|\(trip.marker)|\(trip.routeCode)"
            if var existing = map[key] { if !trip.serviceType.isEmpty, !existing.serviceTypes.contains(trip.serviceType) { existing.serviceTypes.append(trip.serviceType); map[key] = existing } }
            else { map[key] = Entry(minutes: minutes, marker: trip.marker, routeCode: trip.routeCode, serviceTypes: trip.serviceType.isEmpty ? [] : [trip.serviceType]) }
        }
        return map.values.sorted { ($0.minutes, $0.marker, $0.routeCode) < ($1.minutes, $1.marker, $1.routeCode) }
    }
    struct MarkerGroup: Equatable { var marker: String, count: Int, routeCodes: [String], sampleTimes: [Int], serviceTypes: [String] }
    /// İşaret başına özet: kaç sefer, hangi güzergâh kodları, örnek saatler, hangi sefer türleri.
    static func markerGroups(_ entries: [Entry]) -> [MarkerGroup] {
        Dictionary(grouping: entries.filter(\.isMarked), by: \.marker).map { marker, list in
            MarkerGroup(marker: marker, count: list.count, routeCodes: Array(Set(list.map(\.routeCode))).sorted(), sampleTimes: list.map(\.minutes).prefix(6).map { $0 },
                        serviceTypes: Array(Set(list.flatMap(\.serviceTypes))).sorted())
        }.sorted { $0.marker < $1.marker }
    }
    /// Sefer türü etiketi → sefer sayısı (tabloda hangi türler var).
    static func serviceTypeCounts(_ entries: [Entry]) -> [(type: String, count: Int)] {
        Dictionary(grouping: entries.flatMap { $0.serviceTypes }, by: { $0 }).map { ($0.key, $0.value.count) }.sorted { ($1.count, $0.type) < ($0.count, $1.type) }
    }
    /// Paylaşılabilir düz metin tablo: saat ve işaret, ÖHO seferleri * ile.
    static func shareText(line: String, name: String, destination: String, day: String, entries: [Entry], offset: Int = 0) -> String {
        let rows = byHourEntries(entries, offset: offset).map { hour, list in
            String(format: "%02d: ", hour % 24) + list.map { String(format: "%02d", ($0.minutes + offset) % 60) + ($0.markerText ?? "") + ($0.isOHO ? "*" : "") }.joined(separator: " ")
        }
        let legend = entries.contains(where: \.isOHO) ? "\n* ÖHO seferi" : ""
        return "\(line) · \(name)\n→ \(destination) · \(day)\n" + rows.joined(separator: "\n") + legend
    }
    static func byHourEntries(_ entries: [Entry], offset: Int = 0) -> [(hour: Int, entries: [Entry])] {
        Dictionary(grouping: entries, by: { ($0.minutes + offset) / 60 }).map { ($0.key, $0.value.sorted { $0.minutes < $1.minutes }) }.sorted { $0.hour < $1.hour }
    }
}

/// Hat düzeyinde takip özeti: yoldaki araç sayısı (yönlere göre) ve konuma en yakın durağa en yakın aracın varışı.
struct LineSummary: Equatable {
    var line: String
    var total: Int
    var byDirection: [String: Int]
    var stopName: String?
    var stopCode: Int?
    var stopMeters: Double?
    var eta: BusETA?
    /// Yön başına hat şeridi: araçların hat üzerindeki konumu (0…1) ve sana en yakın durağın konumu.
    var tracks: [Track] = []
    struct Track: Equatable {
        var direction: String
        var destination: String
        var buses: [Double]
        var user: Double?
    }

    /// `buses`: hattın canlı araçları; `user`: kullanıcı konumu (yoksa yalnız sayılar). Durak, hattın bütün yönlerindeki duraklardan konuma en yakın olandır (en çok 2 km).
    static func make(line: String, buses: [Bus], route: LineRoute?, user: CLLocationCoordinate2D?, hat: Hat? = nil, tracker: LiveTracker = LiveTracker(), now: Date = .now) -> LineSummary {
        let fresh = buses.filter { $0.lastSeen.map { now.timeIntervalSince($0) < LiveTracker.staleAfter } ?? true }
        var summary = LineSummary(line: line, total: fresh.count, byDirection: Dictionary(grouping: fresh, by: \.direction).mapValues(\.count))
        guard let route else { return summary }
        var best: (stop: RouteStop, meters: Double)?
        if let user {
            for stops in route.stops.values { for stop in stops {
                let meters = user.distance(to: stop.coordinate)
                if meters <= 2000, best == nil || meters < best!.meters { best = (stop, meters) }
            } }
        }
        // Hat şeritleri: araçlar ve (varsa) en yakın durak, güzergâh boyunca 0…1 oranı.
        for direction in route.directions {
            guard let stops = route.stops[direction], stops.count >= 2 else { continue }
            let geometry = RouteGeometry(stops: stops)
            guard geometry.length > 0 else { continue }
            let fractions = fresh.filter { $0.direction == direction }.compactMap { bus -> Double? in
                guard let p = geometry.project(bus.coordinate), p.off <= RouteETAEngine.maxOffRoute else { return nil }
                return min(1, max(0, p.along / geometry.length))
            }.sorted()
            let userFraction = best.flatMap { b in stops.firstIndex { $0.code == b.stop.code }.map { geometry.cumulative[$0] / geometry.length } }
            summary.tracks.append(Track(direction: direction, destination: route.destination(direction), buses: fractions, user: userFraction))
        }
        guard let best else { return summary }
        summary.stopName = best.stop.name; summary.stopCode = best.stop.code; summary.stopMeters = best.meters
        summary.eta = RouteETAEngine.etas(buses: fresh, route: route, stopCode: best.stop.code, hat: hat, tracker: tracker, now: now).first
        return summary
    }
}
