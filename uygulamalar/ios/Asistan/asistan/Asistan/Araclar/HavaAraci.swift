import Foundation
import FoundationModels
import CoreLocation

/// Open-Meteo (ücretsiz, anahtarsız). WeatherKit yerine; şehir adı verilmezse cihaz konumu.
nonisolated struct HavaAraci: Tool {
    let name = "havaDurumu"
    let description = "Şu anki hava ve 3 günlük tahmin. Şehir verilmezse cihazın konumu kullanılır."

    @Generable
    struct Arguments {
        @Guide(description: "Şehir/ilçe adı (isteğe bağlı; boşsa mevcut konum)") var yer: String?
    }

    func call(arguments a: Arguments) async throws -> String {
        var enlem: Double, boylam: Double, ad: String
        if let yer = a.yer, !yer.isEmpty {
            guard let g = try await Self.konumBul(yer) else { return "'\(yer)' bulunamadı." }
            (enlem, boylam, ad) = g
        } else {
            let k = try await Konum.paylasilan.al()
            enlem = k.coordinate.latitude; boylam = k.coordinate.longitude; ad = "bulunduğun yer"
        }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(enlem)), .init(name: "longitude", value: String(boylam)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code,wind_speed_10m"),
            .init(name: "forecast_hours", value: "12"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "3"),
        ]
        let (veri, yanit) = try await URLSession.shared.data(for: URLRequest(url: c.url!, timeoutInterval: 20))
        guard (yanit as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let y = try JSONDecoder().decode(Yanit.self, from: veri)
        try Task.checkCancellation()
        // İptal denetiminden SONRA: iptal edilen istekte kart sızmaz. Kart yanıt balonuna bağlanır ve sohbetle saklanır.
        let ozet = HavaOzeti(y, ad: ad)
        await MainActor.run { EkDefteri.ortak.ekle(MesajEki(tur: .hava(ozet))) }
        return Self.metin(y, ad: ad)
    }

    static func metin(_ y: Yanit, ad: String) -> String {
        var s = "\(ad.prefix(1).uppercased() + ad.dropFirst()): şu an \(Int(y.current.temperature_2m.rounded()))°C (hissedilen \(Int(y.current.apparent_temperature.rounded()))°), \(kod(y.current.weather_code)), nem %\(y.current.relative_humidity_2m), rüzgâr \(Int(y.current.wind_speed_10m.rounded())) km/sa."
        let gunler = ["bugün", "yarın", "öbür gün"]
        for i in 0..<([3, y.daily.time.count, y.daily.temperature_2m_min.count, y.daily.temperature_2m_max.count, y.daily.weather_code.count, y.daily.precipitation_probability_max.count].min() ?? 0) {
            s += " \(gunler[i].prefix(1).uppercased() + gunler[i].dropFirst()): \(Int(y.daily.temperature_2m_min[i].rounded()))–\(Int(y.daily.temperature_2m_max[i].rounded()))°C, \(kod(y.daily.weather_code[i])), yağış olasılığı %\(y.daily.precipitation_probability_max[i] ?? 0)."
        }
        return s
    }

    static func kod(_ k: Int) -> String {
        switch k {
        case 0: "açık"
        case 1, 2: "az bulutlu"
        case 3: "kapalı"
        case 45, 48: "sisli"
        case 51, 53, 55, 56, 57: "çisenti"
        case 61, 63, 65, 66, 67: "yağmurlu"
        case 71, 73, 75, 77: "kar yağışlı"
        case 80, 81, 82: "sağanak"
        case 85, 86: "kar sağanağı"
        case 95, 96, 99: "gök gürültülü fırtına"
        default: "değişken"
        }
    }

    /// API çoğu yerleşim için nüfus vermez; o durumda büyükşehir illeri öne alınır.
    nonisolated static func konumPuani(_ nufus: Int?, _ il: String?) -> Double {
        let buyuk = ["İstanbul", "Ankara", "İzmir", "Bursa", "Antalya", "Adana", "Konya", "Gaziantep", "Kocaeli", "Mersin"]
        let sira = il.flatMap { buyuk.firstIndex(of: $0) }
        return Double(nufus ?? 0) + (sira.map { Double(buyuk.count - $0) } ?? 0)
    }

    static func konumBul(_ yer: String) async throws -> (Double, Double, String)? {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: yer), .init(name: "count", value: "10"), .init(name: "language", value: "tr")]
        let (veri, _) = try await URLSession.shared.data(from: c.url!)
        struct G: Decodable { struct S: Decodable { let latitude: Double; let longitude: Double; let name: String; let admin1: String?; let population: Int? }; let results: [S]? }
        // Aynı adlı küçük yerleşimler (ör. Kastamonu Beykoz) yerine en kalabalık eşleşme seçilir.
        guard let s = try JSONDecoder().decode(G.self, from: veri).results?.max(by: { Self.konumPuani($0.population, $0.admin1) < Self.konumPuani($1.population, $1.admin1) }) else { return nil }
        return (s.latitude, s.longitude, s.admin1.map { "\(s.name), \($0)" } ?? s.name)
    }

    struct Yanit: Decodable {
        struct Simdi: Decodable { let temperature_2m: Double; let apparent_temperature: Double; let relative_humidity_2m: Int; let weather_code: Int; let wind_speed_10m: Double }
        struct Gunluk: Decodable { let time: [String]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double]; let weather_code: [Int]; let precipitation_probability_max: [Int?] }
        let current: Simdi
        let daily: Gunluk
        var hourly: Saatlik? = nil
        struct Saatlik: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let precipitation_probability: [Int?]
            let weather_code: [Int?]
            let wind_speed_10m: [Double?]
        }
    }
}

/// Hava kartının kalıcı, eşitlenebilir özeti (`MesajEki.Tur.hava`). `HavaAraci.Yanit` yalnız Decodable olduğu için
/// kart ve sohbet kaydı bu türü taşır (`EkKalici` `t: "hava"`).
nonisolated struct HavaOzeti: Codable, Equatable, Sendable {
    nonisolated struct Saat: Codable, Equatable, Sendable {
        /// "14:00" (tahmin konumunun yerel saati).
        var saat: String
        var sicaklik: Double?
        var yagis: Int?
        var kod: Int?
        var ruzgar: Double?

        /// Kart sekmesine göre değer metni ("Sıcaklık", "Yağış", "Rüzgâr"); değer yoksa "—".
        func deger(_ sekme: String) -> String {
            switch sekme {
            case "Yağış": yagis.map { "%\($0)" } ?? "—"
            case "Rüzgâr": ruzgar.map { "\(Int($0.rounded())) km/sa" } ?? "—"
            default: sicaklik.map { "\(Int($0.rounded()))°" } ?? "—"
            }
        }
    }
    var ad: String
    var sicaklik: Double
    var hissedilen: Double
    var kod: Int
    var yuksek: Double?
    var dusuk: Double?
    var saatler: [Saat]
    var zaman: Date

    static let enFazlaSaat = 12

    /// Kartta gösterilen yuvarlanmış sıcaklık ("18°").
    var sicaklikMetni: String { "\(Int(sicaklik.rounded()))°" }
}

nonisolated extension HavaOzeti {
    /// Open-Meteo yanıtından özet: saatlik dizi yoksa `saatler` boş; dizi uzunlukları uyuşmazsa eksik alan nil; en çok 12 saat.
    init(_ y: HavaAraci.Yanit, ad: String, zaman: Date = .now) {
        var saatler: [Saat] = []
        if let h = y.hourly {
            for i in 0..<min(Self.enFazlaSaat, h.time.count) {
                saatler.append(Saat(saat: String(h.time[i].suffix(5)),
                                    sicaklik: h.temperature_2m[safe: i] ?? nil,
                                    yagis: h.precipitation_probability[safe: i] ?? nil,
                                    kod: h.weather_code[safe: i] ?? nil,
                                    ruzgar: h.wind_speed_10m[safe: i] ?? nil))
            }
        }
        self.init(ad: ad, sicaklik: y.current.temperature_2m, hissedilen: y.current.apparent_temperature, kod: y.current.weather_code,
                  yuksek: y.daily.temperature_2m_max.first, dusuk: y.daily.temperature_2m_min.first, saatler: saatler, zaman: zaman)
    }
}
