import Foundation

/// Paylaşılacak mesaj: gövde metni, isteğe bağlı konum (Apple Haritalar) ve uygulama bağlantısı.
struct ShareMessage: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var body: String
    var maps: URL? = nil
    var deep: URL? = nil

    /// Gönderilecek tam metin: başlık + gövde + (seçilirse) konum ve uygulama bağlantısı + zaman damgası.
    func text(includeMap: Bool = true, includeApp: Bool = true, stamp: String? = nil) -> String {
        var parts = ["🚌 \(title)", body]
        if includeMap, let maps { parts.append("📍 \(maps.absoluteString)") }
        if includeApp, let deep { parts.append("📲 Otobüs Asistanı: \(deep.absoluteString)") }
        if let stamp { parts.append("⏱ \(stamp)") }
        return parts.joined(separator: "\n\n")
    }
}

enum ShareBuilder {
    static func stamp(_ now: Date = .now) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.timeZone = IETTDates.istanbul; f.dateFormat = "d MMM HH:mm"
        return "\(f.string(from: now)) itibarıyla · süreler tahmindir"
    }
    static func mapsURL(name: String, lat: Double, lon: Double) -> URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [.init(name: "ll", value: "\(lat),\(lon)"), .init(name: "q", value: name)]
        return c.url!
    }
    /// "4 dk · 3 durak kaldı", "Durakta", "yaklaşan araç yok".
    static func etaText(_ eta: BusETA?, now: Date = .now) -> String {
        guard let eta else { return "yaklaşan araç görünmüyor" }
        let minutes = Int(eta.minutes(at: now).rounded())
        if eta.state == .atStop { return "durakta" }
        let base = minutes <= 0 ? "yaklaşıyor" : "\(eta.state == .estimated ? "yaklaşık " : "")\(minutes) dk sonra"
        return base + (eta.stopsLeft.flatMap { $0 > 0 ? " (\($0) durak kaldı)" : nil } ?? "")
    }

    static func favorite(_ f: Favorite, etas: [BusETA], now: Date = .now) -> ShareMessage {
        var body = "\(f.line) hattı → \(f.stopName) durağı\nİlk araç: \(etaText(etas.first, now: now))"
        if etas.count > 1 { body += "\nSonraki: " + etas.dropFirst().prefix(2).map { etaText($0, now: now) }.joined(separator: ", ") }
        return ShareMessage(title: "\(f.line) · \(f.stopName)", body: body, maps: mapsURL(name: f.stopName, lat: f.lat, lon: f.lon), deep: f.deepLink)
    }

    static func line(_ hat: Hat, total: Int, byDirection: [String: Int], nextDepartures: [(time: String, minutes: Int)], nearestStop: String? = nil, eta: BusETA? = nil, now: Date = .now) -> ShareMessage {
        var lines = ["\(hat.code) · \(hat.name)"]
        lines.append(total == 0 ? "Şu an yolda canlı araç görünmüyor." : "Şu an yolda \(total) araç var" + (byDirection.isEmpty ? "." : " (" + byDirection.sorted { $0.key < $1.key }.map { "\($0.key == "G" ? "gidiş" : "dönüş") \($0.value)" }.joined(separator: ", ") + ")."))
        if let nearestStop { lines.append("En yakın durak: \(nearestStop) — \(etaText(eta, now: now))") }
        if !nextDepartures.isEmpty { lines.append("Sıradaki planlı kalkışlar: " + nextDepartures.map { "\($0.time) (\($0.minutes) dk sonra)" }.joined(separator: ", ")) }
        return ShareMessage(title: "\(hat.code) hattı", body: lines.joined(separator: "\n"), deep: DeepLink.line(hat.code))
    }

    static func stopArrivals(_ stop: Durak, rows: [(line: String, destination: String, text: String)]) -> ShareMessage {
        var body = "\(stop.name) durağı (\([stop.district, stop.direction].filter { !$0.isEmpty }.joined(separator: " · ")), no \(stop.code))"
        if rows.isEmpty { body += "\nŞu an yaklaşan araç bilgisi yok." }
        else { body += "\n" + rows.prefix(8).map { "• \($0.line)" + ($0.destination.isEmpty ? "" : " → \($0.destination)") + ": \($0.text)" }.joined(separator: "\n") }
        return ShareMessage(title: stop.name, body: body, maps: mapsURL(name: stop.name, lat: stop.lat, lon: stop.lon), deep: DeepLink.stop(stop.code))
    }

    static func stop(_ stop: Durak) -> ShareMessage { stopArrivals(stop, rows: []).with(body: "\(stop.name) durağı\n\([stop.district, stop.direction].filter { !$0.isEmpty }.joined(separator: " · ")) · durak no \(stop.code)") }

    static func trip(_ o: TripOption, waitMinutes: Int?) -> ShareMessage {
        var body = "\(o.line) hattı → \(o.destination)\n🚶 \(Int(o.walkToBoard)) m yürü, \(o.board.name) durağından bin\n🚌 \(o.stops) durak (~\(Int(o.rideMinutes.rounded())) dk)\n🚏 \(o.alight.name) durağında in, \(Int(o.walkFromAlight)) m yürü\nToplam ~\(Int(o.totalMinutes.rounded())) dk"
        if let waitMinutes { body += waitMinutes <= 0 ? "\nBinişte şimdi bir sefer var." : "\nBinişe sıradaki planlı geçiş ~\(waitMinutes) dk sonra." }
        return ShareMessage(title: "Yolculuk: \(o.board.name) → \(o.alight.name)", body: body, maps: mapsURL(name: o.board.name, lat: o.board.lat, lon: o.board.lon), deep: DeepLink.line(o.line, stop: o.board.code))
    }

    static func transfer(_ o: TransferOption) -> ShareMessage {
        let transfer = o.transferWalkMeters > 0 ? "\(o.first.alight.name) → \(o.second.board.name), ~\(Int(o.transferWalkMeters.rounded())) m yürü" : o.first.alight.name
        let body = "1️⃣ \(o.first.line): \(o.first.board.name) → \(o.first.alight.name) (\(o.first.stops) durak)\n🔄 Aktarma: \(transfer) (~\(Int(TransferOption.assumedWait)) dk bekleme)\n2️⃣ \(o.second.line): → \(o.second.destination), \(o.second.alight.name) durağında in (\(o.second.stops) durak)\n🚶 \(Int(o.walkToBoard)) m + \(Int(o.walkFromAlight)) m yürüyüş · toplam ~\(Int(o.totalMinutes.rounded())) dk"
        return ShareMessage(title: "Aktarmalı yolculuk: \(o.first.line) → \(o.second.line)", body: body, maps: mapsURL(name: o.first.board.name, lat: o.first.board.lat, lon: o.first.board.lon), deep: DeepLink.line(o.first.line, stop: o.first.board.code))
    }

    static func itinerary(_ option: MultiTripOption, destination: Durak) -> ShareMessage {
        var rows: [String] = []
        for (index, leg) in option.legs.enumerated() {
            if option.walks.indices.contains(index), option.walks[index] > 1 {
                rows.append("🚶 \(leg.board.name) durağına ~\(Int(option.walks[index].rounded())) m yürü")
            }
            rows.append("\(index + 1). \(leg.line) · \(leg.destination) yönü\nBin: \(leg.board.name) (\(leg.board.code))\nİn: \(leg.alight.name) (\(leg.alight.code)) · \(leg.stops) durak")
        }
        if let walk = option.walks.last, walk > 1 { rows.append("🚶 \(destination.name) hedefine ~\(Int(walk.rounded())) m yürü") }
        rows.append("Toplam ~\(Int(option.totalMinutes.rounded())) dk · \(max(0, option.legs.count - 1)) aktarma")
        rows.append("Süreler tahminidir; ilk aracı bekleme dahil değildir. Aktarma başına ~\(Int(TransferOption.assumedWait)) dk bekleme varsayılır. Yürüyüş mesafeleri kuş uçuşudur. Sefer saatlerini ayrıca kontrol et.")
        return ShareMessage(title: "Yolculuk: \(destination.name)", body: rows.joined(separator: "\n\n"), maps: mapsURL(name: destination.name, lat: destination.lat, lon: destination.lon))
    }

    static func notice(_ n: Duyuru) -> ShareMessage {
        let severity = NoticeClassifier.severity(n.message)
        return ShareMessage(title: "\(n.line) · \(severity.title)", body: "\(severity.emoji) \(n.line) \(n.lineName)\n\(n.message)" + (n.updated.isEmpty ? "" : "\n(\(n.updated))"), deep: DeepLink.line(n.line))
    }

    static func board(_ stop: Durak, rows: [BoardRow], now: Date = .now) -> ShareMessage {
        var body = "\(stop.name) durağı — sıradakiler"
        if rows.isEmpty { body += "\nYakında sefer yok." }
        for row in rows.prefix(8) {
            body += "\n• \(row.line) \(BoardFormat.upper(row.destination)): \(BoardFormat.text(row, now: now))\(row.live ? " (canlı)" : " (tarife)")"
            if let p = BoardFormat.punctuality(row), p.tone == .late { body += " ⚠ \(p.text)" }
        }
        return ShareMessage(title: stop.name, body: body, maps: mapsURL(name: stop.name, lat: stop.lat, lon: stop.lon), deep: DeepLink.stop(stop.code))
    }

    static func timetable(_ hat: Hat, destination: String, day: String, entries: [Timetable.Entry], offset: Int = 0) -> ShareMessage {
        ShareMessage(title: "\(hat.code) sefer saatleri", body: Timetable.shareText(line: hat.code, name: hat.name, destination: destination, day: day, entries: entries, offset: offset), deep: DeepLink.timetable(hat.code))
    }

    static func answer(_ text: String) -> ShareMessage { ShareMessage(title: "Otobüs Asistanı", body: text) }
}

extension ShareMessage { func with(body: String) -> ShareMessage { var copy = self; copy.body = body; return copy } }
