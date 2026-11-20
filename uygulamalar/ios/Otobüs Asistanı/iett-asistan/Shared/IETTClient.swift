import Foundation

enum IETTError: LocalizedError {
    case fault(String), badResponse
    /// Canlı konum kotası (saatte 100) doldu; `seconds` sonra yeniden açılır.
    case rateLimited(seconds: TimeInterval)
    var errorDescription: String? {
        switch self {
        case .fault(let message): "İETT servisi hata verdi: \(message)"
        case .badResponse: "İETT servisinden okunamayan yanıt geldi."
        case .rateLimited(let seconds): "Canlı konum kotası doldu (İETT saatte 100 isteğe izin veriyor); yaklaşık \(max(1, Int((seconds / 60).rounded(.up)))) dk sonra açılır."
        }
    }
}

/// SOAP zarfındaki `<…Result>` metnini (JSON) ve varsa `faultstring` değerini çıkarır.
final class SoapResultParser: NSObject, XMLParserDelegate {
    private(set) var result = "", fault = ""
    private var inResult = false, inFault = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if name.hasSuffix("Result") { inResult = true }
        if name == "faultstring" { inFault = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inResult { result += string }
        if inFault { fault += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if inResult { result += String(decoding: CDATABlock, as: UTF8.self) } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name.hasSuffix("Result") { inResult = false }
        if name == "faultstring" { inFault = false }
    }
}

actor IETTClient {
    static let shared = IETTClient()
    enum Service: String {
        case routes = "UlasimAnaVeri/HatDurakGuzergah.asmx", schedule = "UlasimAnaVeri/PlanlananSeferSaati.asmx"
        case fleet = "FiloDurum/SeferGerceklesme.asmx", notices = "UlasimDinamikVeri/Duyurular.asmx", ibb = "ibb/ibb.asmx"
    }
    private let session: URLSession
    private let base = "https://api.ibb.gov.tr/iett/"
    init(session: URLSession? = nil) {
        if let session { self.session = session; return }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 45; configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    static func envelope(operation: String, parameters: [(String, String)]) -> Data {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let body = parameters.map { "<\($0.0)>\(escape($0.1))</\($0.0)>" }.joined()
        return Data("""
        <?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"><soap:Body><\(operation) xmlns="http://tempuri.org/">\(body)</\(operation)></soap:Body></soap:Envelope>
        """.utf8)
    }
    /// SOAP yanıtından JSON gövdesini çıkarır; hata zarfında `IETTError.fault` fırlatır.
    static func extractJSON(from data: Data) throws -> Data {
        let parser = SoapResultParser(), xml = XMLParser(data: data)
        xml.delegate = parser
        guard xml.parse() || !parser.fault.isEmpty else { throw IETTError.badResponse }
        if !parser.fault.isEmpty { throw IETTError.fault(parser.fault.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard !parser.result.isEmpty else { return Data("[]".utf8) }
        return Data(parser.result.utf8)
    }

    func call(_ service: Service, _ operation: String, _ parameters: [(String, String)] = []) async throws -> Data {
        try Self.extractJSON(from: try await post(service, operation, parameters))
    }
    /// Ham SOAP yanıtı (ibb.asmx durak servisleri JSON değil, gömülü XML tablo döndürür).
    func post(_ service: Service, _ operation: String, _ parameters: [(String, String)] = []) async throws -> Data {
        var request = URLRequest(url: URL(string: base + service.rawValue)!)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\"http://tempuri.org/\(operation)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = Self.envelope(operation: operation, parameters: parameters)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse).map({ $0.statusCode == 200 || $0.statusCode == 500 }) ?? false else { throw IETTError.badResponse }
        return data
    }
    /// Hattın yönlere göre SIRALI durakları (SIRANO), yön adlarıyla.
    func route(line: String) async throws -> LineRoute {
        let data = try await post(.ibb, "DurakDetay_GYY_wYonAdi", [("hat_kodu", line)])
        return try LineRoute.parse(line: line, soap: data)
    }

    func lines() async throws -> [Hat] {
        try JSONDecoder().decode([Hat].self, from: try await call(.routes, "GetHat_json", [("HatKodu", "")])).sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }
    private var busCache: [String: (date: Date, buses: [Bus])] = [:]
    /// Son başarılı canlı çekim zamanı (önbellek yaşı göstermek için).
    func lastFetch(line: String) -> Date? { busCache[line]?.date }
    /// Canlı konum, kota ve önbellek bilinciyle: `maxAge`'den yeni önbellek varsa ağa gidilmez; kota doluysa eski veri döner
    /// (hiç veri yoksa `rateLimited` fırlatılır). Servis "Rate limit" derse kota sayacı pencere dolana dek kilitlenir.
    func buses(line: String, maxAge: TimeInterval = 40, budget: FleetBudget = .shared) async throws -> [Bus] {
        if let cached = busCache[line], Date().timeIntervalSince(cached.date) < maxAge { return cached.buses }
        guard await budget.acquire() else {
            if let cached = busCache[line] { return cached.buses }
            throw IETTError.rateLimited(seconds: await budget.waitSeconds())
        }
        do {
            let buses = try JSONDecoder().decode([FailableDecodable<Bus>].self, from: try await call(.fleet, "GetHatOtoKonum_json", [("HatKodu", line)])).compactMap(\.value)
            busCache[line] = (Date(), buses)
            return buses
        } catch IETTError.fault(let message) where message.contains("Policy") {
            await budget.serverRefused()
            if let cached = busCache[line] { return cached.buses }
            throw IETTError.rateLimited(seconds: await budget.waitSeconds())
        }
    }
    /// Planlı sefer saatleri (kotasız servis). Diske 12 saat saklanır; ağ yoksa eski kopya kullanılır (çevrimdışı bakılabilir).
    func timetable(line: String, cacheFolder: URL = IETTClient.timetableFolder, maxAge: TimeInterval = 12 * 3600) async throws -> [PlannedTrip] {
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        let url = cacheFolder.appending(path: line.replacingOccurrences(of: "/", with: "_") + ".json")
        let cached = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([PlannedTrip].self, from: $0) }
        let age = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate].flatMap { $0 as? Date }.map { Date().timeIntervalSince($0) }
        if let cached, !cached.isEmpty, let age, age < maxAge { return cached }
        do {
            let trips = try JSONDecoder().decode([FailableDecodable<PlannedTrip>].self, from: try await call(.schedule, "GetPlanlananSeferSaati_json", [("HatKodu", line)])).compactMap(\.value)
            if !trips.isEmpty, let data = try? JSONEncoder().encode(trips) { try? data.write(to: url, options: .atomic) }
            return trips
        } catch { if let cached, !cached.isEmpty { return cached }; throw error }
    }
    static var timetableFolder: URL { SharedStore.routesFolder.deletingLastPathComponent().appending(path: "sefer-v2", directoryHint: .isDirectory) }
    func notices() async throws -> [Duyuru] {
        try JSONDecoder().decode([FailableDecodable<Duyuru>].self, from: try await call(.notices, "GetDuyurular_json")).compactMap(\.value)
    }
    /// ~3,7 MB; haftada bir indirilir, diskte saklanır.
    func stops(cache: URL = IETTClient.stopCacheURL, maxAge: TimeInterval = 7 * 86400) async throws -> [Durak] {
        let cached = (try? Data(contentsOf: cache)).flatMap { try? JSONDecoder().decode([Durak].self, from: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        if let cached, let attributes = try? FileManager.default.attributesOfItem(atPath: cache.path), let date = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(date) < maxAge { return cached }
        do {
            let data = try await call(.routes, "GetDurak_json", [("DurakKodu", "")])
            let stops = try JSONDecoder().decode([FailableDecodable<Durak>].self, from: data).compactMap(\.value)
            guard !stops.isEmpty else { throw IETTError.badResponse }
            if let encoded = try? JSONEncoder().encode(stops) { try? encoded.write(to: cache, options: .atomic) }
            return stops
        } catch {
            if let cached { return cached }
            throw error
        }
    }
    static var stopCacheURL: URL { URL.cachesDirectory.appending(path: "durak-v2.json") }
}

/// Tek bozuk kayıt tüm listeyi düşürmesin.
struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}
