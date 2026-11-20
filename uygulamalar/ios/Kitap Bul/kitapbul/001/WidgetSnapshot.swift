import Foundation
import WidgetKit

/// Widget'ın gösterdiği küçük özet. Depo paylaşılmaz; uygulama her ödünç/iade/arşiv sonrası bunu yazar.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var geciken: Int
    var bugunIade: Int
    var sonArsiv: Date?
    var guncelleme: Date

    static let bayatlikSuresi: TimeInterval = 86_400

    func bayatMi(now: Date = .now) -> Bool { now.timeIntervalSince(guncelleme) > Self.bayatlikSuresi }

    /// "Bugün iade" sayısı yalnız yazıldığı gün geçerlidir.
    func bugunGecerli(now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(guncelleme, inSameDayAs: now)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> WidgetSnapshot {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(WidgetSnapshot.self, from: data)
    }
}

nonisolated enum WidgetSnapshotStore {
    static let appGroup = "group.com.mehmetderin.kitapkatalogu"
    static let fileName = "WidgetSnapshot.json"
    static let widgetKind = "KitapBulHizliIslem"

    /// App Group yetkisi yoksa nil döner; özellik sessizce pasif kalır.
    static func defaultURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appendingPathComponent(fileName)
    }

    static func read(from url: URL? = nil) -> WidgetSnapshot? {
        guard let url = url ?? defaultURL(), let data = try? Data(contentsOf: url) else { return nil }
        return try? WidgetSnapshot.decode(data)
    }

    @discardableResult
    static func publish(geciken: Int, bugunIade: Int, sonArsiv: Date?, now: Date = .now,
                        to url: URL? = nil, reload: Bool = true) -> Bool {
        guard let url = url ?? defaultURL() else { return false }
        let snapshot = WidgetSnapshot(geciken: max(0, geciken), bugunIade: max(0, bugunIade), sonArsiv: sonArsiv, guncelleme: now)
        guard let data = try? snapshot.encoded(), (try? data.write(to: url, options: .atomic)) != nil else { return false }
        if reload { WidgetCenter.shared.reloadTimelines(ofKind: widgetKind) }
        return true
    }
}
