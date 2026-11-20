import CoreLocation
import Foundation

extension KeyedDecodingContainer {
    /// İETT bazı sayıları metin, bazılarını sayı olarak döndürür; ondalık virgül de görülür.
    func lossyDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let text = try? decode(String.self, forKey: key) { return Double(text.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
    func lossyString(_ key: Key) -> String? {
        if let text = try? decode(String.self, forKey: key) { return text }
        if let number = try? decode(Int.self, forKey: key) { return String(number) }
        return nil
    }
}

struct Hat: Codable, Identifiable, Hashable {
    var code: String, name: String, tariff: String?, lengthKm: Double?, tripMinutes: Double?
    var id: String { code }
    enum CodingKeys: String, CodingKey { case code = "SHATKODU", name = "SHATADI", tariff = "TARIFE", lengthKm = "HAT_UZUNLUGU", tripMinutes = "SEFER_SURESI" }
    init(code: String, name: String, tariff: String? = nil, lengthKm: Double? = nil, tripMinutes: Double? = nil) {
        self.code = code; self.name = name; self.tariff = tariff; self.lengthKm = lengthKm; self.tripMinutes = tripMinutes
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code); name = (try? c.decode(String.self, forKey: .name)) ?? ""
        tariff = try? c.decode(String.self, forKey: .tariff); lengthKm = c.lossyDouble(.lengthKm); tripMinutes = c.lossyDouble(.tripMinutes)
    }
}

struct Durak: Codable, Identifiable, Hashable {
    var code: Int, name: String, lat: Double, lon: Double, district: String, direction: String
    /// Künye: durak tipi (ör. İETTBAYRAK), akıllı durak mı, fiziki durum (AÇIK/KAPALI…), engelli kullanımı.
    var kind: String = "", smart: Bool = false, physical: String = "", accessibility: String = ""
    var id: Int { code }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    enum CodingKeys: String, CodingKey { case code = "SDURAKKODU", name = "SDURAKADI", point = "KOORDINAT", district = "ILCEADI", direction = "SYON", kind = "DURAK_TIPI", smart = "AKILLI", physical = "FIZIKI", access = "ENGELLIKULLANIM" }
    init(code: Int, name: String, lat: Double, lon: Double, district: String = "", direction: String = "", kind: String = "", smart: Bool = false, physical: String = "", accessibility: String = "") {
        self.code = code; self.name = name; self.lat = lat; self.lon = lon; self.district = district; self.direction = direction
        self.kind = kind; self.smart = smart; self.physical = physical; self.accessibility = accessibility
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let code = c.lossyString(.code).flatMap(Int.init) else { throw DecodingError.dataCorruptedError(forKey: .code, in: c, debugDescription: "durak kodu") }
        guard let point = try? c.decode(String.self, forKey: .point), let parsed = Durak.parse(point: point) else {
            throw DecodingError.dataCorruptedError(forKey: .point, in: c, debugDescription: "koordinat")
        }
        self.code = code; name = (try? c.decode(String.self, forKey: .name)) ?? ""
        lon = parsed.lon; lat = parsed.lat
        district = (try? c.decode(String.self, forKey: .district)) ?? ""; direction = (try? c.decode(String.self, forKey: .direction)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""; physical = (try? c.decode(String.self, forKey: .physical)) ?? ""
        accessibility = (try? c.decode(String.self, forKey: .access)) ?? ""
        smart = ((try? c.decode(String.self, forKey: .smart)) ?? "YOK").uppercased() != "YOK"
    }
    /// Disk önbelleği, API ile aynı biçimde (POINT) yazılır; okuma tek kod yolundan geçer.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code); try c.encode(name, forKey: .name)
        try c.encode("POINT (\(lon) \(lat))", forKey: .point)
        try c.encode(district, forKey: .district); try c.encode(direction, forKey: .direction)
        try c.encode(kind, forKey: .kind); try c.encode(physical, forKey: .physical); try c.encode(accessibility, forKey: .access)
        try c.encode(smart ? "VAR" : "YOK", forKey: .smart)
    }
    /// "POINT (28.69 41.00)" → (lon, lat)
    static func parse(point: String) -> (lon: Double, lat: Double)? {
        let numbers = point.split(whereSeparator: { !"0123456789.-".contains($0) }).compactMap { Double($0) }
        guard numbers.count == 2, abs(numbers[1]) <= 90, abs(numbers[0]) <= 180 else { return nil }
        return (numbers[0], numbers[1])
    }
}

struct Bus: Decodable, Identifiable, Hashable {
    var plate: String, lat: Double, lon: Double, line: String, routeCode: String, lineName: String, destination: String
    var lastSeen: Date?, nearStop: Int?
    var id: String { plate }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    /// "500T_G_D0" → "G" (gidiş) / "D" (dönüş)
    var direction: String { Bus.direction(ofRoute: routeCode) }
    static func direction(ofRoute code: String) -> String {
        let parts = code.split(separator: "_"); return parts.count >= 2 ? String(parts[1]) : ""
    }
    enum CodingKeys: String, CodingKey { case plate = "kapino", lon = "boylam", lat = "enlem", line = "hatkodu", routeCode = "guzergahkodu", lineName = "hatad", destination = "yon", seen = "son_konum_zamani", near = "yakinDurakKodu" }
    init(plate: String, lat: Double, lon: Double, line: String, routeCode: String, lineName: String = "", destination: String = "", lastSeen: Date? = nil, nearStop: Int? = nil) {
        self.plate = plate; self.lat = lat; self.lon = lon; self.line = line; self.routeCode = routeCode; self.lineName = lineName
        self.destination = destination; self.lastSeen = lastSeen; self.nearStop = nearStop
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plate = try c.decode(String.self, forKey: .plate)
        guard let lat = c.lossyDouble(.lat), let lon = c.lossyDouble(.lon) else { throw DecodingError.dataCorruptedError(forKey: .lat, in: c, debugDescription: "konum") }
        self.lat = lat; self.lon = lon
        line = (try? c.decode(String.self, forKey: .line)) ?? ""; routeCode = (try? c.decode(String.self, forKey: .routeCode)) ?? ""
        lineName = (try? c.decode(String.self, forKey: .lineName)) ?? ""; destination = (try? c.decode(String.self, forKey: .destination)) ?? ""
        lastSeen = (try? c.decode(String.self, forKey: .seen)).flatMap(IETTDates.parse)
        nearStop = c.lossyString(.near).flatMap(Int.init)
    }
}

struct PlannedTrip: Codable, Hashable {
    var line: String, routeCode: String, direction: String, dayType: String, time: String, lineName: String
    /// Resmî tablodaki "(-1)" gibi güzergâh işareti ("-1", "-2", "S", "I", "K", "C"…); işaretsiz seferde boş.
    var marker: String = ""
    /// Sefer türü etiketi: "ÖHO", "Normal", "Gareli", "Tek Sof S.", "Ara Dinlen" gibi.
    var serviceType: String = ""
    enum CodingKeys: String, CodingKey { case line = "SHATKODU", routeCode = "SGUZERAH", direction = "SYON", dayType = "SGUNTIPI", time = "DT", lineName = "HATADI", marker = "GUZERGAH_ISARETI", serviceType = "SSERVISTIPI" }
    init(line: String, routeCode: String = "", direction: String, dayType: String, time: String, lineName: String = "", marker: String = "", serviceType: String = "") {
        self.line = line; self.routeCode = routeCode; self.direction = direction; self.dayType = dayType; self.time = time; self.lineName = lineName
        self.marker = marker; self.serviceType = serviceType
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = try c.decode(String.self, forKey: .line); routeCode = (try? c.decode(String.self, forKey: .routeCode)) ?? ""
        direction = (try? c.decode(String.self, forKey: .direction)) ?? ""; dayType = (try? c.decode(String.self, forKey: .dayType)) ?? "I"
        time = try c.decode(String.self, forKey: .time); lineName = (try? c.decode(String.self, forKey: .lineName)) ?? ""
        marker = ((try? c.decode(String.self, forKey: .marker)) ?? "").trimmingCharacters(in: .whitespaces)
        serviceType = ((try? c.decode(String.self, forKey: .serviceType)) ?? "").trimmingCharacters(in: .whitespaces)
    }
}

struct Duyuru: Decodable, Identifiable, Hashable {
    var line: String, lineName: String, kind: String, updated: String, message: String
    var id: String { line + "|" + message.prefix(60) }
    enum CodingKeys: String, CodingKey { case line = "HATKODU", lineName = "HAT", kind = "TIP", updated = "GUNCELLEME_SAATI", message = "MESAJ" }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = (try? c.decode(String.self, forKey: .line)) ?? ""; lineName = (try? c.decode(String.self, forKey: .lineName)) ?? ""
        kind = (try? c.decode(String.self, forKey: .kind)) ?? ""; updated = (try? c.decode(String.self, forKey: .updated)) ?? ""
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
    }
    init(line: String, lineName: String = "", kind: String = "", updated: String = "", message: String) {
        self.line = line; self.lineName = lineName; self.kind = kind; self.updated = updated; self.message = message
    }
}

struct Favorite: Codable, Identifiable, Hashable {
    var line: String, stopCode: Int, stopName: String, lat: Double, lon: Double
    /// Otobüs bu kadar dakika (ya da daha az) uzaklaşınca bildirim gönder; nil = kapalı.
    var alertMinutes: Int? = nil
    var id: String { "\(line)-\(stopCode)" }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

enum IETTDates {
    static let istanbul = TimeZone(identifier: "Europe/Istanbul")!
    private static let formatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = istanbul; f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
    static func parse(_ text: String) -> Date? { formatter.date(from: text) }
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = istanbul; return c }
    /// İETT gün tipi: I hafta içi, C cumartesi, P pazar.
    static func dayType(_ date: Date = .now) -> String {
        switch calendar.component(.weekday, from: date) { case 1: "P"; case 7: "C"; default: "I" }
    }
    /// "14:35" → bugünün o saati (gece yarısını aşan seferler için 24+ saat de kabul edilir).
    static func departure(_ time: String, on day: Date = .now) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: parts[0] * 60 + parts[1], to: start)
    }
}

/// Türkçe büyük/küçük harf ve aksan duyarsız karşılaştırma ("ŞİŞLİ" = "sisli").
func fold(_ text: String) -> String {
    text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        .replacingOccurrences(of: "ı", with: "i").lowercased()
}
