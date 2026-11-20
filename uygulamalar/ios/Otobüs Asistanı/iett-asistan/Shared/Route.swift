import CoreLocation
import Foundation

struct RouteStop: Codable, Hashable, Identifiable {
    var seq: Int, code: Int, name: String, lat: Double, lon: Double
    var id: String { "\(code)-\(seq)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Bir hattın yönlere (G gidiş / D dönüş) göre sıralı durakları.
struct LineRoute: Codable, Hashable {
    var line: String
    var stops: [String: [RouteStop]]
    var destinations: [String: String]
    /// Gidiş (G) önce, sonra dönüş (D); ekranlarda yön sırası hep böyle.
    var directions: [String] { stops.keys.sorted { ($0 == "G" ? 0 : 1, $0) < ($1 == "G" ? 0 : 1, $1) } }

    func destination(_ direction: String) -> String { destinations[direction] ?? (direction == "G" ? "Gidiş" : "Dönüş") }
    func stopIndex(code: Int, direction: String) -> Int? { stops[direction]?.firstIndex { $0.code == code } }
    /// Durağın bu hattın hangi yönlerinde geçtiği.
    func directions(serving code: Int) -> [String] { directions.filter { stopIndex(code: code, direction: $0) != nil } }

    static func parse(line: String, soap: Data) throws -> LineRoute {
        let parser = TableParser(), xml = XMLParser(data: soap)
        xml.delegate = parser
        _ = xml.parse()
        if !parser.fault.isEmpty { throw IETTError.fault(parser.fault.trimmingCharacters(in: .whitespacesAndNewlines)) }
        var stops: [String: [RouteStop]] = [:], names: [String: String] = [:]
        for row in parser.rows {
            guard let direction = row["YON"], let seq = row["SIRANO"].flatMap(Int.init), let code = row["DURAKKODU"].flatMap(Int.init),
                  let lon = row["XKOORDINATI"].flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }),
                  let lat = row["YKOORDINATI"].flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) else { continue }
            stops[direction, default: []].append(.init(seq: seq, code: code, name: row["DURAKADI"] ?? "", lat: lat, lon: lon))
            if let name = row["YON_ADI"], !name.isEmpty { names[direction] = name }
        }
        for key in stops.keys { stops[key] = stops[key]!.sorted { $0.seq < $1.seq } }
        guard !stops.isEmpty else { throw IETTError.badResponse }
        return LineRoute(line: line, stops: stops, destinations: names)
    }
}

/// `<Table><ALAN>değer</ALAN>…</Table>` satırlarını sözlüklere çevirir.
final class TableParser: NSObject, XMLParserDelegate {
    private(set) var rows: [[String: String]] = [], fault = ""
    private var row: [String: String]?, field = "", text = "", inFault = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "Table" { row = [:] } else if name == "faultstring" { inFault = true } else if row != nil { field = name; text = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inFault { fault += string } else if row != nil, !field.isEmpty { text += string }
    }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "Table" { if let row { rows.append(row) }; row = nil }
        else if name == "faultstring" { inFault = false }
        else if row != nil, name == field { row?[name] = text.trimmingCharacters(in: .whitespacesAndNewlines); field = "" }
    }
}

/// Güzergâh çizgisi üzerinde konum ölçümü: duraklar arası doğru parçaları, metre cinsinden birikimli mesafe.
struct RouteGeometry {
    let stops: [RouteStop], cumulative: [Double]
    private let originLat: Double
    init(stops: [RouteStop]) {
        self.stops = stops; originLat = stops.first?.lat ?? 41
        var total = 0.0, list: [Double] = []
        for (i, stop) in stops.enumerated() { if i > 0 { total += stops[i - 1].coordinate.distance(to: stop.coordinate) }; list.append(total) }
        cumulative = list
    }
    var length: Double { cumulative.last ?? 0 }
    var coordinates: [CLLocationCoordinate2D] { stops.map(\.coordinate) }

    private func xy(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        (c.longitude * 111_320 * cos(originLat * .pi / 180), c.latitude * 110_540)
    }
    /// Noktanın çizgiye izdüşümü: başlangıçtan metre (`along`) ve çizgiye uzaklık (`off`).
    func project(_ point: CLLocationCoordinate2D) -> (along: Double, off: Double)? {
        guard stops.count >= 2 else { return nil }
        let p = xy(point)
        var best: (along: Double, off: Double)?
        for i in 0..<(stops.count - 1) {
            let a = xy(stops[i].coordinate), b = xy(stops[i + 1].coordinate)
            let dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
            let off = hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
            if best == nil || off < best!.off { best = (cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), off) }
        }
        return best
    }
}

enum RouteETAEngine {
    static let maxOffRoute = 500.0, passedTolerance = 80.0, atStopRadius = 60.0, dwellPerStop = 6.0

    /// Hat güzergâhına oturtulmuş varış süresi: araç çizgide nerede, durak çizgide nerede; aradaki yol ÷ hız.
    /// Yön, aracın güzergâh kodundan (G/D) bellidir; bu yüzden durağı geçmiş ya da ters yöndeki araçlar kesin elenir.
    static func etas(buses: [Bus], route: LineRoute, stopCode: Int, hat: Hat? = nil, tracker: LiveTracker, now: Date = .now) -> [BusETA] {
        var result: [BusETA] = []
        let average = hat.flatMap { h -> Double? in
            guard let km = h.lengthKm, let minutes = h.tripMinutes, minutes > 0, km > 0 else { return nil }
            return min(9, max(2.5, km * 1000 / (minutes * 60)))
        } ?? LiveTracker.defaultSpeed
        for direction in route.directions(serving: stopCode) {
            guard let stops = route.stops[direction], let stopIndex = route.stopIndex(code: stopCode, direction: direction) else { continue }
            let geometry = RouteGeometry(stops: stops), stopAlong = geometry.cumulative[stopIndex]
            for bus in buses where bus.direction == direction {
                if let seen = bus.lastSeen, now.timeIntervalSince(seen) > LiveTracker.staleAfter { continue }
                guard let here = geometry.project(bus.coordinate), here.off <= maxOffRoute else { continue }
                let remaining = stopAlong - here.along
                if remaining < -passedTolerance { continue }
                // Ölçülen hız: son örneklerin güzergâh üzerindeki ilerlemesi.
                var speed = average
                let recent = (tracker.history[bus.id] ?? []).filter { now.timeIntervalSince($0.date) <= LiveTracker.window }
                if let first = recent.first, let last = recent.last, last.date.timeIntervalSince(first.date) >= 15,
                   let a = geometry.project(first.coordinate), let b = geometry.project(last.coordinate) {
                    let measured = (b.along - a.along) / last.date.timeIntervalSince(first.date)
                    if measured > 1 { speed = min(14, max(2.5, 0.5 * measured + 0.5 * average)) }
                }
                let passedStops = geometry.cumulative.lastIndex { $0 <= here.along + 1 } ?? 0
                let left = max(0, stopIndex - passedStops)
                if remaining < atStopRadius {
                    result.append(.init(id: bus.id, minutes: 0, distance: max(0, remaining), state: .atStop, speedKmh: speed * 3.6, stopsLeft: 0)); continue
                }
                let seconds = remaining / speed + Double(left) * dwellPerStop * (speed == average ? 0 : 1)
                result.append(.init(id: bus.id, minutes: seconds / 60, distance: remaining, state: .approaching, speedKmh: speed * 3.6, stopsLeft: left))
            }
        }
        return result.sorted { $0.minutes < $1.minutes }
    }

    /// Aracın hat üzerindeki konumuna en yakın durağın sırası (zaman çizelgesinde göstermek için).
    static func stopIndex(of bus: Bus, in route: LineRoute) -> Int? {
        guard let stops = route.stops[bus.direction] else { return nil }
        let geometry = RouteGeometry(stops: stops)
        guard let here = geometry.project(bus.coordinate), here.off <= maxOffRoute else { return nil }
        return geometry.cumulative.lastIndex { $0 <= here.along + 1 }
    }
}

/// Hat güzergâhları diskte (hat başına bir dosya) saklanır; tüm hatlar bir kez arka planda indirilince
/// "bu durağa uğrayan hatlar" dizini kurulur.
actor RouteStore {
    static let shared = RouteStore()
    struct Entry: Codable, Hashable { var line: String; var direction: String }
    private var memory: [String: LineRoute] = [:]
    private var stopLines: [Int: [Entry]] = [:]
    private let folder: URL
    private let client: IETTClient
    private let maxAge: TimeInterval
    init(folder: URL = SharedStore.routesFolder, client: IETTClient = .shared, maxAge: TimeInterval = 30 * 86400) {
        self.folder = folder; self.client = client; self.maxAge = maxAge
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: folder.appending(path: "_index.json")), let index = try? JSONDecoder().decode([Int: [Entry]].self, from: data) { stopLines = index }
    }
    private func file(_ line: String) -> URL { folder.appending(path: line.replacingOccurrences(of: "/", with: "_") + ".json") }
    private func fresh(_ url: URL) -> Bool {
        guard let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(date) < maxAge
    }

    func route(_ line: String) async throws -> LineRoute {
        if let cached = memory[line] { return cached }
        let url = file(line)
        if fresh(url), let data = try? Data(contentsOf: url), let route = try? JSONDecoder().decode(LineRoute.self, from: data) { memory[line] = route; return route }
        let route = try await client.route(line: line)
        if let data = try? JSONEncoder().encode(route) { try? data.write(to: url, options: .atomic) }
        memory[line] = route; return route
    }
    func hasIndex() -> Bool { !stopLines.isEmpty }
    func lines(atStop code: Int) -> [Entry] { stopLines[code] ?? [] }

    /// Çok aktarmalı arama için diskte hazır güzergâhların anlık kopyası; ağa istek göndermez.
    func cachedRoutes() -> [LineRoute] {
        var result = memory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasSuffix(".json") && !name.hasPrefix("_") {
            guard let data = try? Data(contentsOf: folder.appending(path: name)), let route = try? JSONDecoder().decode(LineRoute.self, from: data), result[route.line] == nil else { continue }
            result[route.line] = route
        }
        return result.values.sorted { $0.line < $1.line }
    }

    /// Uygulamayla gelen güzergâh tohumunu (hat başına JSON) henüz olmayan dosyalar için kopyalar; var olana dokunmaz.
    /// Kullanıcı cihazı servisi hiç yormadan "durağa uğrayan hatlar" bilgisine ilk açılışta kavuşur.
    @discardableResult func seed(from seedFolder: URL?) -> Int {
        guard let seedFolder, let names = try? FileManager.default.contentsOfDirectory(atPath: seedFolder.path) else { return 0 }
        var copied = 0
        for name in names where name.hasSuffix(".json") && !name.hasPrefix("_") {
            let target = folder.appending(path: name)
            if FileManager.default.fileExists(atPath: target.path) { continue }
            if (try? FileManager.default.copyItem(at: seedFolder.appending(path: name), to: target)) != nil { copied += 1 }
        }
        return copied
    }
    /// Servis bizi sınırlarsa ("Policy Falsified") eşitleme bırakılır; bir sonraki açılışta eksik kalanlardan sürer.
    private var blocked = false
    /// Eksik/eski hatları ağır ağır (2 eşzamanlı istek, aralarda bekleme) indirir, sonra dizini kurar. `progress(tamamlanan, toplam)`.
    func sync(lines: [String], concurrency: Int = 2, pause: Duration = .milliseconds(400), progress: @Sendable @escaping (Int, Int) -> Void) async {
        let needed = lines.filter { !fresh(file($0)) }
        var done = lines.count - needed.count
        progress(done, lines.count)
        blocked = false
        var iterator = needed.makeIterator()
        await withTaskGroup(of: Void.self) { group in
            func next() {
                guard !blocked, let line = iterator.next() else { return }
                group.addTask {
                    try? await Task.sleep(for: pause)
                    do { _ = try await self.route(line) }
                    catch IETTError.fault(let message) where message.contains("Policy") { await self.markBlocked() }
                    catch {}
                }
            }
            for _ in 0..<concurrency { next() }
            while await group.next() != nil { done += 1; progress(done, lines.count); next() }
        }
        buildIndex(lines: lines)
    }
    private func markBlocked() { blocked = true }
    func buildIndex(lines: [String]) {
        var index: [Int: Set<Entry>] = [:]
        for line in lines {
            guard let data = try? Data(contentsOf: file(line)), let route = try? JSONDecoder().decode(LineRoute.self, from: data) else { continue }
            for (direction, stops) in route.stops { for stop in stops { index[stop.code, default: []].insert(.init(line: line, direction: direction)) } }
        }
        stopLines = index.mapValues { $0.sorted { ($0.line, $0.direction) < ($1.line, $1.direction) } }
        if let data = try? JSONEncoder().encode(stopLines) { try? data.write(to: folder.appending(path: "_index.json"), options: .atomic) }
    }
}
