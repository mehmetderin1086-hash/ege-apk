import CoreLocation
import Foundation

/// Hem cihaz içi yapay zekânın araçları hem de kural tabanlı yedek asistan aynı canlı veri işlevlerini kullanır.
@MainActor final class TransitBrain {
    let model: AppModel
    init(model: AppModel) { self.model = model }

    func findLines(_ query: String) -> String {
        let needle = fold(query)
        let found = model.lines.filter { fold($0.code) == needle || fold($0.code + " " + $0.name).contains(needle) }.prefix(8)
        guard !found.isEmpty else { return "“\(query)” ile eşleşen hat bulunamadı." }
        return found.map { "\($0.code): \($0.name)" }.joined(separator: "\n")
    }

    func lineStatus(_ code: String) async -> String {
        guard let hat = model.line(code) else { return "“\(code)” adında bir İETT hattı bulunamadı." }
        async let buses = model.buses(line: hat.code), trips = model.timetable(line: hat.code), notices = model.notices(line: hat.code)
        let (live, plan, news) = await (buses, trips, notices)
        var lines = ["\(hat.code) · \(hat.name)"]
        let fresh = live.filter { $0.lastSeen.map { Date().timeIntervalSince($0) < 300 } ?? true }
        if let error = model.liveError { lines.append("Canlı veri uyarısı: \(error)") }
        if model.liveError == nil || !fresh.isEmpty { lines.append(fresh.isEmpty ? "Şu an yolda canlı araç görünmüyor." : "Şu an yolda \(fresh.count) araç var (G: \(fresh.filter { $0.direction == "G" }.count), D: \(fresh.filter { $0.direction == "D" }.count)).") }
        for (direction, label) in [("G", "Gidiş"), ("D", "Dönüş")] {
            let next = Timetable.next(plan, direction: direction)
            if !next.isEmpty { lines.append("\(label) sonraki kalkışlar: " + next.map { "\($0.time) (\($0.minutes) dk sonra)" }.joined(separator: ", ")) }
        }
        if let notice = news.first { lines.append("Duyuru: \(notice.message)") }
        return lines.joined(separator: "\n")
    }

    func stopETA(line code: String, stopQuery: String) async -> String {
        guard let hat = model.line(code) else { return "“\(code)” adında bir İETT hattı bulunamadı." }
        let near = model.location?.coordinate
        guard var stop = model.searchStops(stopQuery, near: near, limit: 1).first else { return "“\(stopQuery)” adında durak bulunamadı." }
        var buses = await model.buses(line: hat.code)
        let route = await model.route(hat.code)
        // Güzergâh biliniyorsa yön araç kodundan bellidir. Yoksa yön ancak iki örnekle anlaşılır: kısa bir ölçüm daha alınır.
        if route == nil, buses.contains(where: { (model.tracker.history[$0.id]?.count ?? 0) < 2 }) {
            try? await Task.sleep(for: .seconds(8)); buses = await model.buses(line: hat.code)
        }
        if let route, route.directions(serving: stop.code).isEmpty {
            // Aranan ad bu hattın durağı değil: hattın kendi duraklarında en iyi eşleşmeyi dene.
            let needle = fold(stopQuery)
            if let own = route.stops.values.joined().first(where: { fold($0.name).contains(needle) }), let matching = model.stop(code: own.code) { stop = matching }
            else { return "\(hat.code) hattı “\(stop.name)” durağından geçmiyor." }
        }
        let etas = await model.etas(line: hat.code, buses: buses, stop: stop.coordinate, stopCode: stop.code)
        let header = "\(hat.code) → \(stop.name) (\(stop.district)\(stop.direction.isEmpty ? "" : ", " + stop.direction + " yönü"))"
        guard !etas.isEmpty else { return header + "\n" + (model.liveError.map { "Canlı veri alınamadı: \($0)" } ?? "Duraktan geçecek, yaklaşmakta olan canlı araç görünmüyor.") }
        return header + "\n" + etas.prefix(3).map { "Araç \($0.id): \($0.text) (\([$0.stopsLeft.flatMap { $0 > 0 ? "\($0) durak kaldı" : nil }, $0.distanceText + " uzakta"].compactMap { $0 }.joined(separator: ", ")))" }.joined(separator: "\n")
            + "\nSüreler canlı konumdan hesaplanan tahmindir."
    }

    /// Bir durağa uğrayan hatlar ve her birinin ilk aracının varış süresi.
    func stopLines(_ stopQuery: String) async -> String {
        guard let stop = model.searchStops(stopQuery, near: model.location?.coordinate, limit: 1).first else { return "“\(stopQuery)” adında durak bulunamadı." }
        let entries = await model.linesAtStop(stop.code)
        guard !entries.isEmpty else { return "\(stop.name) için hat bilgisi henüz indirilmedi (arka planda sürüyor); biraz sonra tekrar sor." }
        var lines: [String] = ["\(stop.name) (\(stop.district)) durağına uğrayan hatlar:"]
        var seen = Set<String>()
        for entry in entries.prefix(12) where seen.insert(entry.line).inserted {
            let buses = await model.buses(line: entry.line)
            let etas = await model.etas(line: entry.line, buses: buses, stop: stop.coordinate, stopCode: stop.code)
            lines.append("\(entry.line): " + (etas.first?.text ?? "yaklaşan araç yok"))
        }
        return lines.joined(separator: "\n")
    }

    /// Planlı sefer saatleri özeti (kotasız servis): ilk/son sefer, aralık ve sıradaki kalkışlar, iki yön için.
    func schedule(_ code: String) async -> String {
        guard let hat = model.line(code) else { return "“\(code)” adında bir İETT hattı bulunamadı." }
        let trips = await model.timetable(line: hat.code), route = await model.route(hat.code)
        guard !trips.isEmpty else { return "\(hat.code) için planlı sefer verisi bulunamadı." }
        let type = IETTDates.dayType(), now = Timetable.nowMinutes()
        var lines = ["\(hat.code) · \(hat.name)", "Bugün (\(Timetable.dayTypes.first { $0.code == type }?.title ?? "")) planlı seferler:"]
        for direction in route?.directions ?? ["G", "D"] {
            let times = Timetable.times(trips, dayType: type, direction: direction)
            guard let summary = Timetable.summary(times) else { continue }
            let next = times.filter { $0 >= now }.prefix(3).map(Timetable.format).joined(separator: ", ")
            lines.append("→ \(route?.destination(direction) ?? direction): ilk \(Timetable.format(summary.first)), son \(Timetable.format(summary.last)), \(summary.count) sefer\(summary.averageGap.map { ", ~\(Int($0.rounded())) dk aralık" } ?? "")" + (next.isEmpty ? ". Bugün sefer kalmadı." : ". Sıradaki: \(next)"))
        }
        return lines.joined(separator: "\n")
    }

    func nearby() -> String {
        guard let here = model.location?.coordinate else { return "Konumun alınamadı; Ayarlar'dan konum iznini aç." }
        let list = model.nearestStops(to: here, limit: 5, within: 1500)
        guard !list.isEmpty else { return "1,5 km çevrende durak bulunamadı." }
        return list.map { "\($0.stop.name) (\($0.stop.direction)) · \(Int($0.meters)) m" }.joined(separator: "\n")
    }

    func notices(line: String?) async -> String {
        let list = await model.notices(line: line?.isEmpty == true ? nil : line)
        guard !list.isEmpty else { return line.map { "\($0) için güncel duyuru yok." } ?? "Güncel duyuru yok." }
        return list.prefix(5).map { "\($0.line): \($0.message)" }.joined(separator: "\n")
    }
}

/// Apple Intelligence kullanılamadığında (eski cihaz, kapalı, simülatör) çalışan Türkçe kural tabanlı asistan.
@MainActor struct LocalAssistant {
    let brain: TransitBrain
    enum Intent: Equatable { case status(String), schedule(String), eta(String, String), stopLines(String), nearby, notices(String?), search(String), help }

    /// `context`: sohbette en son konuşulan hat; "peki sefer saatleri?" gibi hat adı geçmeyen devam sorularında kullanılır.
    static func parse(_ text: String, lines: [Hat], context: String? = nil) -> Intent {
        let lower = fold(text)
        let codes = Set(lines.map { fold($0.code) })
        let tokens = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var line = tokens.first { codes.contains($0) }
        let followUp = ["peki", "onun", "bunun", "bu hat", "ayni hat", "o hat"].contains { lower.contains($0) }
        if line == nil, followUp || lower.contains("sefer saat") || lower.contains("tarife") || lower.contains("duyuru"), let context { line = fold(context) }
        if lower.contains("yakin") && (lower.contains("durak") || lower.contains("cevre")) { return .nearby }
        if lower.contains("duyuru") || lower.contains("aksama") || lower.contains("kapali") { return .notices(line.map { $0.uppercased() }) }
        if line == nil, lower.contains("hangi hat") || lower.contains("hatlar") || lower.contains("hat geciyor") || lower.contains("hat gecer") || lower.contains("hat ugrar") {
            let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !["hangi", "hat", "hatlar", "gecer", "geciyor", "ugrar", "durak", "durag", "duragindan", "duragina", "duraginda", "mi", "var", "bu", "olan", "kadar"].contains($0) }
            if !words.isEmpty { return .stopLines(words.joined(separator: " ")) }
        }
        guard let line else { return lower.count > 1 && !lower.contains("merhaba") ? .search(text) : .help }
        let code = lines.first { fold($0.code) == line }?.code ?? line.uppercased()
        if ["sefer saat", "tarife", "ilk sefer", "son sefer", "kacta kalk", "kacta", "saatleri"].contains(where: lower.contains), !["kac dk", "kac dakika"].contains(where: lower.contains) { return .schedule(code) }
        let etaWords = ["kac dk", "kac dakika", "ne zaman", "gelir", "gelecek", "ne kadar", "kalan", "durag", "duragina", "duraginda"]
        if etaWords.contains(where: lower.contains), let stop = stopPhrase(in: lower, line: line) { return .eta(code, stop) }
        return .status(code)
    }
    /// "…Kadıköy iskele durağına 14M kaç dk" → "kadikoy iskele"
    private static func stopPhrase(in lower: String, line: String) -> String? {
        let stopWords: Set<String> = ["kac", "dk", "dakika", "ne", "zaman", "gelir", "gelecek", "kadar", "kalan", "durag", "duragina", "duraginda", "duraga", "duragi", "hatti", "hat", "otobus", "otobusu", "icin", "bir", "mi", "bana", "soyle", "var", line]
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !stopWords.contains($0) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// Cevaptaki hatları/durakları açan dokunulabilir eylemler.
    func actions(for intent: Intent) -> [AssistantAction] {
        let model = brain.model
        func line(_ code: String) -> [AssistantAction] {
            [.open(.line(code: code, stop: nil), "\(code) canlı", "dot.radiowaves.left.and.right"), .open(.timetable(code: code, direction: nil, stop: nil), "Sefer saatleri", "clock"), .open(.lineInfo(code: code), "Hat bilgisi", "info.circle")]
        }
        switch intent {
        case .status(let code), .schedule(let code): return line(code)
        case .eta(let code, let stopQuery):
            guard let stop = model.searchStops(stopQuery, near: model.location?.coordinate, limit: 1).first else { return line(code) }
            return [.open(.line(code: code, stop: stop.code), "\(code) · haritada", "map"), .follow(line: code, stop: stop.code, title: "Takip et"), .starStop(code: stop.code), .open(.stop(code: stop.code), "Durak bilgisi", "mappin.and.ellipse")]
        case .stopLines(let query):
            return model.searchStops(query, near: model.location?.coordinate, limit: 1).first.map { [.open(.stop(code: $0.code), "\($0.name) durağını aç", "mappin.and.ellipse"), .starStop(code: $0.code)] } ?? []
        case .nearby:
            guard let here = model.location?.coordinate else { return [] }
            return model.nearestStops(to: here, limit: 3, within: 1500).map { .open(.stop(code: $0.stop.code), $0.stop.name, "signpost.right") }
        case .notices(let code): return code.map { [.open(.lineInfo(code: $0), "\($0) hat bilgisi", "info.circle")] } ?? []
        case .search(let query):
            let needle = fold(query)
            return model.lines.filter { fold($0.code + " " + $0.name).contains(needle) }.prefix(4).map { .open(.line(code: $0.code, stop: nil), $0.code, "bus") }
        case .help: return []
        }
    }

    func answer(_ text: String, context: String? = nil) async -> String {
        switch Self.parse(text, lines: brain.model.lines, context: context) {
        case .status(let code): return await brain.lineStatus(code)
        case .schedule(let code): return await brain.schedule(code)
        case .eta(let code, let stop): return await brain.stopETA(line: code, stopQuery: stop)
        case .stopLines(let stop): return await brain.stopLines(stop)
        case .nearby: return brain.nearby()
        case .notices(let line): return await brain.notices(line: line)
        case .search(let query): return brain.findLines(query)
        case .help: return "Şunları sorabilirsin:\n• “500T nerede?”\n• “Kadıköy iskele durağına 14M kaç dk?”\n• “Yakınımdaki duraklar”\n• “500T sefer saatleri”\n• “Kadıköy çarşı durağından hangi hatlar geçer?”\n• “15F duyuru var mı?”"
        }
    }
}

/// Asistan cevabının altındaki dokunulabilir eylemler.
enum AssistantAction: Hashable {
    case open(Route, String, String)
    case follow(line: String, stop: Int, title: String)
    case starStop(code: Int)
}
