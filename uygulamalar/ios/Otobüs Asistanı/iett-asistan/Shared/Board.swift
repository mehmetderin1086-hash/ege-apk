import Foundation

/// Akıllı durak panosundaki bir satır: hat, yön, varış anı; canlı konumdan mı yoksa tarifeden mi hesaplandığı.
struct BoardRow: Identifiable, Hashable {
    let line: String, direction: String, destination: String
    let arrival: Date
    let live: Bool, atStop: Bool
    /// Planlı (tarifeden) durağa geçiş anı ve hattın çıkış durağından planlı kalkış anı; canlı satır bunları tarife satırından devralır.
    var planned: Date? = nil
    var origin: Date? = nil
    var id: String { line + "|" + direction }
}

enum BoardFormat {
    /// Panodaki süre metni: "DURAKTA", "YAKLAŞIYOR", "ŞİMDİ", "7 dk", 60 dk ve üzeri için saat ("14:35").
    static func text(_ row: BoardRow, now: Date) -> String {
        let remaining = row.arrival.timeIntervalSince(now)
        if row.atStop && row.live && remaining < 90 { return "DURAKTA" }
        if remaining <= 45 { return row.live ? "YAKLAŞIYOR" : "ŞİMDİ" }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 { return "\(minutes) dk" }
        let c = IETTDates.calendar.dateComponents([.hour, .minute], from: row.arrival)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Canlı satır aynı hat+yöndeki tarife satırının yerine geçer; geçmiş (>60 sn) satırlar atılır; varışa göre sıralanır.
    static func merge(scheduled: [BoardRow], live: [BoardRow], now: Date) -> [BoardRow] {
        var byID: [String: BoardRow] = [:]
        for row in scheduled { byID[row.id] = row }
        for row in live {
            let plan = byID[row.id]
            byID[row.id] = BoardRow(line: row.line, direction: row.direction, destination: row.destination, arrival: row.arrival, live: true, atStop: row.atStop,
                                    planned: row.planned ?? plan?.planned ?? plan?.arrival, origin: row.origin ?? plan?.origin)
        }
        return byID.values.filter { $0.arrival.timeIntervalSince(now) > -60 }.sorted { ($0.arrival, $0.line) < ($1.arrival, $1.line) }
    }

    /// Ekrana sığmayan satırlar sayfalara bölünür (otomatik sayfa dönüşü için).
    static func pages(_ rows: [BoardRow], size: Int) -> [[BoardRow]] {
        guard size > 0, !rows.isEmpty else { return [] }
        return stride(from: 0, to: rows.count, by: size).map { Array(rows[$0..<min($0 + size, rows.count)]) }
    }

    /// Tarife dakikasını (gün başından) bugünün mutlak anına çevirir.
    static func date(minutes: Int, on day: Date) -> Date { IETTDates.calendar.date(byAdding: .minute, value: minutes, to: IETTDates.calendar.startOfDay(for: day)) ?? day }

    /// Hangi satırların canlı sorgulanacağı: en yakın tarifeli `limit` hat (4 hat × ~4 dk önbellek ≈ 60 istek/saat, kota altında), yalnız `horizon` içindekiler.
    static func liveCandidates(_ scheduled: [BoardRow], now: Date, limit: Int = 4, horizon: TimeInterval = 90 * 60) -> [BoardRow] {
        Array(scheduled.filter { $0.arrival.timeIntervalSince(now) <= horizon }.sorted { $0.arrival < $1.arrival }.prefix(limit))
    }

    /// Türkçe büyük harf (i → İ, ı → I).
    static func upper(_ text: String) -> String { text.uppercased(with: Locale(identifier: "tr_TR")) }
    /// "45 sn", "7 dk", "1 sa 44 dk" (kalan süre, panoda alt satır ve şerit için).
    static func longText(_ remaining: TimeInterval) -> String {
        let seconds = Int(max(0, remaining))
        if seconds < 60 { return "\(seconds) sn" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        return minutes < 60 ? "\(minutes) dk" : (minutes % 60 == 0 ? "\(minutes / 60) sa" : "\(minutes / 60) sa \(minutes % 60) dk")
    }
    static func clock(_ date: Date) -> String {
        let c = IETTDates.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    enum Tone { case good, late, early, neutral }
    /// Canlı satırın planlıya göre durumu: "+4 dk GECİKME" / "3 dk ERKEN" / "ZAMANINDA" (3 dk eşiği); tarife satırında nil.
    static func punctuality(_ row: BoardRow) -> (text: String, tone: Tone)? {
        guard row.live, let planned = row.planned else { return nil }
        let minutes = Int((row.arrival.timeIntervalSince(planned) / 60).rounded())
        if minutes >= 3 { return ("+\(minutes) dk GECİKME", .late) }
        if minutes <= -3 { return ("\(-minutes) dk ERKEN", .early) }
        return ("ZAMANINDA", .good)
    }
    /// Satırın alt bilgisi satırları: canlıysa planlı saat + durum; tarifeyse varış saati/kalan süre ve ayrı satırda hat çıkış (kalkış) saati.
    static func detailLines(_ row: BoardRow, now: Date) -> [String] {
        if let punctuality = punctuality(row) {
            return [[row.planned.map { "PLAN \(clock($0))" }, punctuality.text].compactMap { $0 }.joined(separator: " · ")]
        }
        var lines = [row.arrival.timeIntervalSince(now) < 3600 ? "VARIŞ \(clock(row.arrival))" : "\(longText(row.arrival.timeIntervalSince(now))) SONRA"]
        if let origin = row.origin, origin > now.addingTimeInterval(-60) { lines.append("ÇIKIŞ \(clock(origin)) · \(longText(origin.timeIntervalSince(now)))") }
        return lines
    }
    static func detail(_ row: BoardRow, now: Date) -> String { detailLines(row, now: now).joined(separator: " · ") }
    /// Kayan şerit metni: "137 SULTANİYE ▸ DURAKTA ● 9H ÇEKMEKÖY ▸ 12 dk (08:15) ● …"
    static func ticker(_ rows: [BoardRow], now: Date, limit: Int = 8) -> String {
        rows.prefix(limit).map { row in
            let remaining = row.arrival.timeIntervalSince(now)
            let when = text(row, now: now)
            let extra = remaining > 45 && remaining < 7200 ? " (\(clock(row.arrival)))" : ""
            let late = punctuality(row).flatMap { $0.tone == .late ? " ⚠ \($0.text)" : nil } ?? ""
            return "\(row.line) \(upper(row.destination)) ▸ \(when)\(extra)\(late)"
        }.joined(separator: "     ●     ")
    }
}
