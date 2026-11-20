import CoreLocation
import Foundation

/// Doğrudan (aktarmasız) yolculuk seçeneği: aynı hat ve yönde, biniş durağı iniş durağından önce gelmeli.
struct TripOption: Identifiable, Hashable {
    let line: String, direction: String, destination: String
    let board: RouteStop, alight: RouteStop
    let stops: Int, rideMeters: Double, rideMinutes: Double
    let walkToBoard: Double, walkFromAlight: Double
    var id: String { "\(line)-\(direction)-\(board.code)-\(alight.code)" }
    /// Yürüyüş (80 m/dk) + yolculuk, dakika.
    var totalMinutes: Double { walkToBoard / 80 + rideMinutes + walkFromAlight / 80 }
}

enum TripPlanner {
    static let walkSpeed = 80.0 // m/dk

    /// `origins`/`destinations`: yakın duraklar ve yürüme mesafeleri. `lines(code)` durağa uğrayan hat+yönler, `route(line)` güzergâh,
    /// `hat(code)` süre/uzunluk için. Her (hat, yön) için en kısa toplam süreli biniş-iniş çifti seçilir.
    static func direct(origins: [(stop: Durak, meters: Double)], destinations: [(stop: Durak, meters: Double)],
                       lines: (Int) async -> [RouteStore.Entry], route: (String) async -> LineRoute?, hat: (String) -> Hat?) async -> [TripOption] {
        typealias Key = String
        var originEntries: [Key: [(Durak, Double, RouteStore.Entry)]] = [:], destinationEntries: [Key: [(Durak, Double, RouteStore.Entry)]] = [:]
        for (stop, meters) in origins { guard !Task.isCancelled else { return [] }; for e in await lines(stop.code) { originEntries[e.line + "|" + e.direction, default: []].append((stop, meters, e)) } }
        for (stop, meters) in destinations { guard !Task.isCancelled else { return [] }; for e in await lines(stop.code) { destinationEntries[e.line + "|" + e.direction, default: []].append((stop, meters, e)) } }
        var options: [TripOption] = []
        for (key, from) in originEntries {
            guard !Task.isCancelled else { return [] }
            guard let to = destinationEntries[key], let entry = from.first?.2, let route = await route(entry.line), let stops = route.stops[entry.direction], stops.count >= 2 else { continue }
            let geometry = RouteGeometry(stops: stops), info = hat(entry.line)
            var best: TripOption?
            for (originStop, walkIn, _) in from {
                guard let i = route.stopIndex(code: originStop.code, direction: entry.direction) else { continue }
                for (destinationStop, walkOut, _) in to {
                    guard let j = route.stopIndex(code: destinationStop.code, direction: entry.direction), j > i else { continue }
                    let meters = geometry.cumulative[j] - geometry.cumulative[i]
                    let minutes = Timetable.offsetMinutes(tripMinutes: info?.tripMinutes, stopAlong: meters, routeLength: geometry.length).map(Double.init) ?? meters / 4 / 60
                    let option = TripOption(line: entry.line, direction: entry.direction, destination: route.destination(entry.direction), board: stops[i], alight: stops[j],
                                            stops: j - i, rideMeters: meters, rideMinutes: max(1, minutes), walkToBoard: walkIn, walkFromAlight: walkOut)
                    if best == nil || option.totalMinutes < best!.totalMinutes { best = option }
                }
            }
            if let best { options.append(best) }
        }
        return options.sorted { ($0.totalMinutes, $0.line) < ($1.totalMinutes, $1.line) }
    }
}

/// Bir yolculuğun tek hat bacağı.
struct TripLeg: Hashable {
    let line: String, direction: String, destination: String
    let board: RouteStop, alight: RouteStop
    let stops: Int, rideMeters: Double, rideMinutes: Double

    /// Durak kodu tekrarlanan halka hatlarda sıra numarası doğru kesiti belirler.
    func routeStops(in route: LineRoute) -> [RouteStop] {
        guard route.line == line, let points = route.stops[direction],
              let start = points.firstIndex(where: { $0.code == board.code && $0.seq == board.seq }),
              let end = points.indices.first(where: { $0 > start && points[$0].code == alight.code && points[$0].seq == alight.seq }) else { return [] }
        return Array(points[start...end])
    }
}

extension TripOption {
    var itinerary: MultiTripOption {
        .init(legs: [.init(line: line, direction: direction, destination: destination, board: board, alight: alight, stops: stops, rideMeters: rideMeters, rideMinutes: rideMinutes)], walks: [walkToBoard, walkFromAlight])
    }
}

extension TransferOption {
    var itinerary: MultiTripOption { .init(legs: [first, second], walks: [walkToBoard, transferWalkMeters, walkFromAlight]) }
}

/// Tek aktarmalı yolculuk: A hattıyla aktarma durağına, orada B hattına geçiş.
struct TransferOption: Identifiable, Hashable {
    let first: TripLeg, second: TripLeg
    let walkToBoard: Double, walkFromAlight: Double
    var transferWalkMeters: Double = 0
    /// Aktarma bekleme süresi varsayımı (dk); sefer sıklığı bilinmediği için sabit.
    static let assumedWait = 6.0
    var id: String { "\(first.line)-\(first.direction)-\(first.board.code)-\(first.alight.code)>\(second.line)-\(second.direction)-\(second.board.code)-\(second.alight.code)" }
    var totalMinutes: Double { (walkToBoard + transferWalkMeters + walkFromAlight) / TripPlanner.walkSpeed + first.rideMinutes + Self.assumedWait + second.rideMinutes }
}

extension TripPlanner {
    private static func leg(_ route: LineRoute, direction: String, from i: Int, to j: Int, hat: Hat?) -> TripLeg? {
        guard let stops = route.stops[direction], i < j, j < stops.count else { return nil }
        let geometry = RouteGeometry(stops: stops), meters = geometry.cumulative[j] - geometry.cumulative[i]
        let minutes = Timetable.offsetMinutes(tripMinutes: hat?.tripMinutes, stopAlong: meters, routeLength: geometry.length).map(Double.init) ?? meters / 4 / 60
        return TripLeg(line: route.line, direction: direction, destination: route.destination(direction), board: stops[i], alight: stops[j], stops: j - i, rideMeters: meters, rideMinutes: max(1, minutes))
    }

    /// En çok bir aktarmalı seçenekler. Aktarma, A hattının ilerideki bir durağında (aynı durak kodu) B hattına binmektir;
    /// B hattı aynı yönde varış duraklarından birine, aktarma durağından sonra uğramalıdır. Aynı hat iki bacakta kullanılmaz.
    static func withTransfer(origins: [(stop: Durak, meters: Double)], destinations: [(stop: Durak, meters: Double)],
                             lines: (Int) async -> [RouteStore.Entry], route: (String) async -> LineRoute?, hat: (String) -> Hat?, limit: Int = 8,
                             transferStops: (RouteStop) -> [(code: Int, meters: Double)] = { [($0.code, 0)] }) async -> [TransferOption] {
        // Varış tarafı: (hat|yön) → [(durak, yürüme)]
        var lineIndex: [Int: [RouteStore.Entry]] = [:]
        func entries(_ code: Int) async -> [RouteStore.Entry] {
            if let cached = lineIndex[code] { return cached }
            let value = await lines(code); lineIndex[code] = value; return value
        }
        var arrival: [String: [(Durak, Double)]] = [:]
        for (stop, meters) in destinations { guard !Task.isCancelled else { return [] }; for e in await entries(stop.code) { arrival[e.line + "|" + e.direction, default: []].append((stop, meters)) } }
        guard !arrival.isEmpty else { return [] }
        var routes: [String: LineRoute] = [:]
        func load(_ line: String) async -> LineRoute? { if let r = routes[line] { return r }; let r = await route(line); routes[line] = r; return r }
        var best: [String: TransferOption] = [:]
        var originEntries: [String: [(Durak, Double, RouteStore.Entry)]] = [:]
        for (stop, meters) in origins { guard !Task.isCancelled else { return [] }; for e in await entries(stop.code) { originEntries[e.line + "|" + e.direction, default: []].append((stop, meters, e)) } }
        for (_, from) in originEntries {
            guard !Task.isCancelled else { return [] }
            guard let entryA = from.first?.2, let routeA = await load(entryA.line), let stopsA = routeA.stops[entryA.direction] else { continue }
            for (originStop, walkIn, _) in from {
                guard let i = routeA.stopIndex(code: originStop.code, direction: entryA.direction) else { continue }
                for t in (i + 1)..<max(i + 1, stopsA.count) {
                    guard !Task.isCancelled else { return [] }
                    for transfer in transferStops(stopsA[t]) where transfer.meters >= 0 && transfer.meters <= 250 {
                    for entryB in await entries(transfer.code) where entryB.line != entryA.line {
                        guard let targets = arrival[entryB.line + "|" + entryB.direction], let routeB = await load(entryB.line),
                              let tB = routeB.stopIndex(code: transfer.code, direction: entryB.direction) else { continue }
                        for (destinationStop, walkOut) in targets {
                            guard let j = routeB.stopIndex(code: destinationStop.code, direction: entryB.direction), j > tB,
                                  let first = leg(routeA, direction: entryA.direction, from: i, to: t, hat: hat(entryA.line)),
                                  let second = leg(routeB, direction: entryB.direction, from: tB, to: j, hat: hat(entryB.line)) else { continue }
                            let option = TransferOption(first: first, second: second, walkToBoard: walkIn, walkFromAlight: walkOut, transferWalkMeters: transfer.meters)
                            let key = "\(entryA.line)|\(entryA.direction)|\(entryB.line)|\(entryB.direction)"
                            if best[key] == nil || option.totalMinutes < best[key]!.totalMinutes { best[key] = option }
                        }
                    }
                    }
                }
            }
        }
        return Array(best.values.sorted { ($0.totalMinutes, $0.id) < ($1.totalMinutes, $1.id) }.prefix(limit))
    }
}

/// Kayıtlı yolculuk (Ev → İş): başlangıç bir durak ya da "konumum", varış bir durak.
struct SavedTrip: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var fromCode: Int?            // nil: konumum
    var fromName: String
    var toCode: Int
    var toName: String
}

/// Uygulama içi bağlantılar: widget ve bildirimler `iettasistan://…` ile ilgili ekranı açar.
enum DeepLink {
    static let scheme = "iettasistan"
    static func line(_ code: String, stop: Int? = nil) -> URL {
        var c = URLComponents(); c.scheme = scheme; c.host = "line"; c.path = "/" + code
        if let stop { c.queryItems = [.init(name: "stop", value: String(stop))] }
        return c.url!
    }
    static func stop(_ code: Int) -> URL { URL(string: "\(scheme)://stop/\(code)")! }
    static func timetable(_ code: String) -> URL {
        var c = URLComponents(); c.scheme = scheme; c.host = "timetable"; c.path = "/" + code; return c.url!
    }
    /// (tür, hat/durak, durak parametresi)
    static func parse(_ url: URL) -> (kind: String, id: String, stop: Int?)? {
        guard url.scheme == scheme, let kind = url.host else { return nil }
        let id = url.path.split(separator: "/").first.map(String.init) ?? ""
        guard !id.isEmpty else { return nil }
        let stop = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "stop" }?.value.flatMap(Int.init)
        return (kind, id, stop)
    }
}

extension Favorite { var deepLink: URL { DeepLink.line(line, stop: stopCode) } }

/// N araç ve N+1 yürüyüş: ilk durağa, aktarmalarda ve son duraktan hedefe.
struct MultiTripOption: Identifiable, Hashable {
    let legs: [TripLeg]
    let walks: [Double]
    var id: String { legs.map { "\($0.line)|\($0.direction)|\($0.board.code)|\($0.alight.code)" }.joined(separator: ">") }
    var totalMinutes: Double {
        walks.reduce(0, +) / TripPlanner.walkSpeed + legs.reduce(0) { $0 + $1.rideMinutes } + Double(max(0, legs.count - 1)) * TransferOption.assumedWait
    }
}

extension TripPlanner {
    /// Her tur bir araç daha ekler. Tam şehir verisini tur başına bir kez tarar.
    /// Saatli sefer uygunluğu değil, yönlü güzergâh bağlantısı ve tahmini yolculuk maliyeti hesaplanır.
    static func multiTransfer(origins: [(stop: Durak, meters: Double)], destinations: [(stop: Durak, meters: Double)],
                              routes: [LineRoute], hats: [Hat], maxRides: Int = 4, limit: Int = 4) -> [MultiTripOption] {
        guard !origins.isEmpty, !destinations.isEmpty, maxRides > 0 else { return [] }
        struct Label {
            var legs: [TripLeg]
            var walks: [Double]
            var minutes: Double
        }
        struct Pattern {
            let line: String, direction: String, destination: String
            let stops: [RouteStop], meters: [Double], minutes: [Double]
        }
        let stats = Dictionary(hats.map { ($0.code, $0) }, uniquingKeysWith: { first, _ in first })
        var patterns: [Pattern] = [], points: [Int: CLLocationCoordinate2D] = [:]
        for route in routes {
            for direction in route.directions {
                guard let stops = route.stops[direction], stops.count > 1 else { continue }
                let geometry = RouteGeometry(stops: stops)
                let duration = stats[route.line]?.tripMinutes.flatMap { $0 > 0 ? $0 : nil }
                let minutes = geometry.cumulative.map { meters in
                    duration.map { geometry.length > 0 ? meters / geometry.length * $0 : 0 } ?? meters / 240
                }
                patterns.append(Pattern(line: route.line, direction: direction, destination: route.destination(direction), stops: stops, meters: geometry.cumulative, minutes: minutes))
                for stop in stops { points[stop.code] = stop.coordinate }
            }
        }
        let cell = 0.003
        struct Cell: Hashable { let x: Int, y: Int }
        func bucket(_ point: CLLocationCoordinate2D) -> Cell { Cell(x: Int(floor(point.latitude / cell)), y: Int(floor(point.longitude / cell))) }
        var buckets: [Cell: [Int]] = [:]
        for (code, point) in points { buckets[bucket(point), default: []].append(code) }
        var nearbyCache: [Int: [(code: Int, meters: Double)]] = [:]
        func nearby(_ code: Int) -> [(code: Int, meters: Double)] {
            if let cached = nearbyCache[code] { return cached }
            guard let point = points[code] else { return [] }
            let origin = bucket(point)
            var result: [(code: Int, meters: Double)] = []
            for x in -1...1 { for y in -1...1 {
                for other in buckets[Cell(x: origin.x + x, y: origin.y + y)] ?? [] where other != code {
                    guard let coordinate = points[other] else { continue }
                    let meters = point.distance(to: coordinate)
                    if meters <= 250 { result.append((other, meters)) }
                }
            } }
            nearbyCache[code] = result
            return result
        }
        var labels: [Int: Label] = [:], found: [String: MultiTripOption] = [:]
        for origin in origins where origin.meters >= 0 {
            let label = Label(legs: [], walks: [origin.meters], minutes: origin.meters / walkSpeed)
            if labels[origin.stop.code].map({ $0.minutes > label.minutes }) ?? true { labels[origin.stop.code] = label }
        }
        for round in 1...min(maxRides, 4) {
            if Task.isCancelled { return [] }
            var reached: [Int: Label] = [:]
            for pattern in patterns {
                var boarding: (index: Int, label: Label, score: Double)?
                for (index, stop) in pattern.stops.enumerated() {
                    if let boarding {
                        let ride = max(1, pattern.minutes[index] - pattern.minutes[boarding.index])
                        let cost = boarding.label.minutes + ride + (round > 1 ? TransferOption.assumedWait : 0)
                        if reached[stop.code].map({ $0.minutes > cost }) ?? true {
                            let leg = TripLeg(line: pattern.line, direction: pattern.direction, destination: pattern.destination,
                                              board: pattern.stops[boarding.index], alight: stop, stops: index - boarding.index,
                                              rideMeters: pattern.meters[index] - pattern.meters[boarding.index], rideMinutes: ride)
                            reached[stop.code] = Label(legs: boarding.label.legs + [leg], walks: boarding.label.walks + [0], minutes: cost)
                        }
                    }
                    if let label = labels[stop.code] {
                        let score = label.minutes - pattern.minutes[index]
                        if boarding.map({ $0.score > score }) ?? true { boarding = (index, label, score) }
                    }
                }
            }
            for destination in destinations {
                guard let label = reached[destination.stop.code] else { continue }
                var walks = label.walks
                walks[walks.count - 1] += destination.meters
                let option = MultiTripOption(legs: label.legs, walks: walks)
                let signature = option.legs.map { $0.line + "|" + $0.direction }.joined(separator: ">")
                if found[signature].map({ $0.totalMinutes > option.totalMinutes }) ?? true { found[signature] = option }
            }
            labels = reached
            // Bir turda yalnız tek yürüme bağlantısı; zincirle sınırsız yürüyüş oluşmaz.
            for (code, label) in reached {
                for neighbor in nearby(code) {
                    let cost = label.minutes + neighbor.meters / walkSpeed
                    guard labels[neighbor.code].map({ $0.minutes > cost }) ?? true else { continue }
                    var walked = label; walked.minutes = cost
                    walked.walks[walked.walks.count - 1] += neighbor.meters
                    labels[neighbor.code] = walked
                }
            }
            if labels.isEmpty { break }
        }
        return Array(found.values.sorted { ($0.totalMinutes, $0.id) < ($1.totalMinutes, $1.id) }.prefix(limit))
    }
}
