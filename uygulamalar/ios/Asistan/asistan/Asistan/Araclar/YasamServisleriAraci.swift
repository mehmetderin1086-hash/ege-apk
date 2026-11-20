import EventKit
import Foundation
import FoundationModels
import UserNotifications
import CryptoKit

/// Anahtarsız kamusal hizmetlerin ortak ağ katmanı. Başarılı yanıtı diskte tutar; ağ kesilirse
/// kaynağın zamanı açıkça belirtilerek son doğrulanmış yanıtı döndürür.
actor YasamServisiOnbellegi {
    static let ortak = YasamServisiOnbellegi()

    nonisolated struct Sonuc: Sendable { let veri: Data; let zaman: Date; let bayat: Bool }
    private struct Kayit: Codable, Sendable { let zaman: Date; let veri: Data }
    nonisolated struct Durum: Codable, Sendable, Equatable {
        let hizmet: String
        var sonBasari: Date?
        var sonHata: Date?
        var hata: String?
    }

    private var bellek: [String: Kayit] = [:]
    private var durumlar: [String: Durum] = [:]
    private let dizin = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "YasamServisleri")
    private let durumAnahtari = "yasam.servis.durum.v1"

    init() {
        if let d = UserDefaults.standard.data(forKey: durumAnahtari), let l = try? JSONDecoder().decode([Durum].self, from: d) {
            durumlar = Dictionary(uniqueKeysWithValues: l.map { ($0.hizmet, $0) })
        }
    }

    func getir(hizmet: String, istek: URLRequest, tazelik: TimeInterval, bayatSiniri: TimeInterval = 7 * 86_400) async throws -> Sonuc {
        let anahtar = Self.anahtar(istek), simdi = Date()
        let eski = kayit(anahtar)
        if let eski, simdi.timeIntervalSince(eski.zaman) < tazelik { return Sonuc(veri: eski.veri, zaman: eski.zaman, bayat: false) }
        do {
            var i = istek
            i.setValue("Asistan/0.21 (com.mehmetderin.asistan)", forHTTPHeaderField: "User-Agent")
            let (veri, yanit) = try await URLSession.shared.data(for: i)
            guard let http = yanit as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            guard veri.count <= 5 * 1024 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
            _ = try JSONSerialization.jsonObject(with: veri)
            try Task.checkCancellation()
            let yeni = Kayit(zaman: simdi, veri: veri)
            bellek[anahtar] = yeni
            try? FileManager.default.createDirectory(at: dizin, withIntermediateDirectories: true)
            try? JSONEncoder().encode(yeni).write(to: dizin.appending(path: anahtar + ".json"), options: .atomic)
            temizle()
            durumlar[hizmet] = Durum(hizmet: hizmet, sonBasari: simdi, sonHata: durumlar[hizmet]?.sonHata, hata: nil)
            durumlariYaz()
            return Sonuc(veri: veri, zaman: simdi, bayat: false)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            durumlar[hizmet] = Durum(hizmet: hizmet, sonBasari: durumlar[hizmet]?.sonBasari, sonHata: simdi, hata: String(error.localizedDescription.prefix(160)))
            durumlariYaz()
            if let eski, simdi.timeIntervalSince(eski.zaman) <= bayatSiniri { return Sonuc(veri: eski.veri, zaman: eski.zaman, bayat: true) }
            throw error
        }
    }

    func durumListesi() -> [Durum] { durumlar.values.sorted { $0.hizmet < $1.hizmet } }
    private func kayit(_ anahtar: String) -> Kayit? {
        if let k = bellek[anahtar] { return k }
        guard let d = try? Data(contentsOf: dizin.appending(path: anahtar + ".json")), let k = try? JSONDecoder().decode(Kayit.self, from: d) else { return nil }
        bellek[anahtar] = k; return k
    }
    private func durumlariYaz() { UserDefaults.standard.set(try? JSONEncoder().encode(Array(durumlar.values)), forKey: durumAnahtari) }
    private func temizle() {
        if bellek.count > 50 { bellek.removeAll(keepingCapacity: true) }
        let dosyalar = ((try? FileManager.default.contentsOfDirectory(at: dizin, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? [])
            .compactMap { u -> (URL, Int, Date)? in
                guard let v = try? u.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (u, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
        var toplam = dosyalar.reduce(0) { $0 + $1.1 }
        for (u, boyut, tarih) in dosyalar {
            if toplam > 20 * 1024 * 1024 || Date().timeIntervalSince(tarih) > 30 * 86400 {
                try? FileManager.default.removeItem(at: u); toplam -= boyut
            }
        }
    }
    nonisolated static func anahtar(_ istek: URLRequest) -> String {
        let ham = (istek.httpMethod ?? "GET") + "|" + (istek.url?.absoluteString ?? "") + "|" + String(decoding: istek.httpBody ?? Data(), as: UTF8.self)
        return SHA256.hash(data: Data(ham.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Günlük yaşam, sağlık, bilim ve araştırma için anahtarsız kamusal veri hizmetleri.
nonisolated struct YasamServisleriAraci: Tool {
    let name = "yasamServisleri"
    let description = "Ücretsiz kamusal veri hizmetleri. İşlemler: saglikHavasi (hava kalitesi/polen/UV; yer), deprem (son depremler; yer veya koordinat), urun (barkod), bilgi (Wikipedia özeti; sorgu), doga (GBIF tür ve Türkiye gözlemleri; sorgu), makale (OpenAlex akademik yayın; sorgu), sabahOzeti (takvim+hava+sağlık), hizmetDurumu. Sonuçlar kaynak ve veri zamanını içerir; ağ yoksa son doğrulanmış önbellek açıkça işaretlenir."
    @Generable struct Arguments {
        @Guide(description: "saglikHavasi, deprem, urun, bilgi, doga, makale, sabahOzeti veya hizmetDurumu") var islem: String
        @Guide(description: "Arama metni, tür adı veya bilgi başlığı") var sorgu: String?
        @Guide(description: "Şehir/ilçe; boşsa cihaz konumu") var yer: String?
        @Guide(description: "Ürün barkodu (EAN/UPC)") var barkod: String?
        @Guide(description: "İsteğe bağlı enlem") var enlem: Double?
        @Guide(description: "İsteğe bağlı boylam") var boylam: Double?
        @Guide(description: "Deprem araması yarıçapı km; varsayılan 300") var yaricapKm: Double?
    }

    func call(arguments a: Arguments) async throws -> String {
        switch AtolyeYonlendirme.normalize(a.islem).replacingOccurrences(of: " ", with: "") {
        case "saglikhavasi": return try await saglikHavasi(a)
        case "deprem": return try await deprem(a)
        case "urun": return try await urun(a)
        case "bilgi": return try await bilgi(a)
        case "doga": return try await doga(a)
        case "makale": return try await makale(a)
        case "sabahozeti": return try await sabahOzeti(a)
        case "hizmetdurumu": return await hizmetDurumu()
        default: return "İşlem anlaşılmadı. Sağlık havası, deprem, ürün, bilgi, doğa, makale, sabah özeti veya hizmet durumu kullanılabilir."
        }
    }

    struct HavaSagligi: Decodable, Sendable {
        struct Simdi: Decodable, Sendable {
            let time: String; let european_aqi: Double?; let pm10: Double?; let pm2_5: Double?; let ozone: Double?; let uv_index: Double?
            let alder_pollen: Double?; let birch_pollen: Double?; let grass_pollen: Double?; let mugwort_pollen: Double?; let olive_pollen: Double?; let ragweed_pollen: Double?
        }
        let current: Simdi
    }
    private func koordinat(_ a: Arguments) async throws -> (Double, Double, String) {
        if a.enlem != nil || a.boylam != nil {
            guard let e = a.enlem, let b = a.boylam, e.isFinite, b.isFinite, (-90...90).contains(e), (-180...180).contains(b) else { throw IndirmeHatasi.metin("Geçerli enlem ve boylam birlikte gerekli.") }
            return (e, b, a.yer ?? "seçilen konum")
        }
        if let yer = a.yer?.trimmingCharacters(in: .whitespacesAndNewlines), !yer.isEmpty {
            guard let g = try await HavaAraci.konumBul(yer) else { throw IndirmeHatasi.metin("İstenen yer bulunamadı; konum değiştirilmedi.") }; return g
        }
        let k = try await Konum.paylasilan.al(); return (k.coordinate.latitude, k.coordinate.longitude, "bulunduğun yer")
    }
    private func saglikHavasi(_ a: Arguments) async throws -> String {
        let (enlem, boylam, ad) = try await koordinat(a)
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [.init(name: "latitude", value: String(enlem)), .init(name: "longitude", value: String(boylam)), .init(name: "current", value: "european_aqi,pm10,pm2_5,ozone,uv_index,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"), .init(name: "timezone", value: "auto")]
        let r = try await YasamServisiOnbellegi.ortak.getir(hizmet: "Open-Meteo Hava Kalitesi", istek: URLRequest(url: c.url!), tazelik: 30 * 60)
        return Self.saglikMetni(try JSONDecoder().decode(HavaSagligi.self, from: r.veri), ad: ad) + Self.kaynakNotu(r, kaynak: "Open-Meteo Hava Kalitesi · https://open-meteo.com/en/docs/air-quality-api")
    }
    static func saglikMetni(_ y: HavaSagligi, ad: String) -> String {
        let s = y.current
        var satir = "\(ad): Avrupa Hava Kalitesi İndeksi \(s.european_aqi.map { String(Int($0.rounded())) } ?? "—") (\(aqiSozu(s.european_aqi))). PM2.5 \(olcu(s.pm2_5)), PM10 \(olcu(s.pm10)), ozon \(olcu(s.ozone)); UV \(s.uv_index.map { String(format: "%.1f", $0) } ?? "—")."
        let polenler = [("kızılağaç", s.alder_pollen), ("huş", s.birch_pollen), ("çimen", s.grass_pollen), ("pelin", s.mugwort_pollen), ("zeytin", s.olive_pollen), ("ambrosia", s.ragweed_pollen)].compactMap { ad, deger in deger.map { (ad, $0) } }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        let polenVerisi = [s.alder_pollen, s.birch_pollen, s.grass_pollen, s.mugwort_pollen, s.olive_pollen, s.ragweed_pollen].contains { $0 != nil }
        satir += !polenVerisi ? " Polen verisi yok." : polenler.isEmpty ? " Bildirilen polen değerleri sıfır." : " Polen (tanecik/m³): " + polenler.map { "\($0.0) \(String(format: "%.1f", $0.1))" }.joined(separator: ", ") + "."
        return satir + " Veri saati: \(s.time)."
    }
    static func aqiSozu(_ a: Double?) -> String { guard let a else { return "veri yok" }; return switch a { case ..<20: "iyi"; case ..<40: "makul"; case ..<60: "orta"; case ..<80: "kötü"; case ..<100: "çok kötü"; default: "son derece kötü" } }
    static func olcu(_ d: Double?) -> String { d.map { String(format: "%.1f µg/m³", $0) } ?? "—" }

    struct DepremYaniti: Decodable, Sendable {
        struct Oge: Decodable, Sendable { struct Ozellik: Decodable, Sendable { let mag: Double?; let place: String?; let time: Double; let url: String? }; let properties: Ozellik; let geometry: Geometri }
        struct Geometri: Decodable, Sendable { let coordinates: [Double] }
        let features: [Oge]
    }
    private func deprem(_ a: Arguments) async throws -> String {
        let (e, b, ad) = try await koordinat(a), yaricap = min(max(a.yaricapKm ?? 300, 10), 2_000)
        var c = URLComponents(string: "https://earthquake.usgs.gov/fdsnws/event/1/query")!
        c.queryItems = [.init(name: "format", value: "geojson"), .init(name: "latitude", value: String(e)), .init(name: "longitude", value: String(b)), .init(name: "maxradiuskm", value: String(yaricap)), .init(name: "starttime", value: Self.gunOnce(7)), .init(name: "orderby", value: "time"), .init(name: "limit", value: "20")]
        let r = try await YasamServisiOnbellegi.ortak.getir(hizmet: "USGS Deprem", istek: URLRequest(url: c.url!), tazelik: 5 * 60)
        let y = try JSONDecoder().decode(DepremYaniti.self, from: r.veri)
        guard !y.features.isEmpty else { return "\(ad) çevresinde son 7 günde, \(Int(yaricap)) km içinde USGS kaydı bulunamadı." + Self.kaynakNotu(r, kaynak: "USGS") }
        let satirlar = y.features.prefix(12).map { d in [d.properties.mag.map { String(format: "%.1f", $0) } ?? "—", d.properties.place ?? "Konum bilinmiyor", Self.tarih(d.properties.time / 1000), d.geometry.coordinates.count > 2 ? String(format: "%.0f km", d.geometry.coordinates[2]) : "—"] }
        await MainActor.run { EkDefteri.ortak.ekle(MesajEki(tur: .tablo(baslik: "\(ad) · Son depremler", sutunlar: ["Büyüklük", "Yer", "Zaman", "Derinlik"], satirlar: satirlar, kaynak: "https://earthquake.usgs.gov/earthquakes/map/", dosya: nil))) }
        return "\(ad) çevresinde son 7 günde \(y.features.count) USGS deprem kaydı bulundu; en yenileri tabloda." + Self.kaynakNotu(r, kaynak: "USGS · https://earthquake.usgs.gov/fdsnws/event/1/")
    }

    struct UrunYaniti: Decodable, Sendable {
        struct Urun: Decodable, Sendable {
            struct Besin: Decodable, Sendable { let energyKcal: Double?; let fat: Double?; let sugars: Double?; let proteins: Double?; let salt: Double?; enum CodingKeys: String, CodingKey { case energyKcal = "energy-kcal_100g", fat = "fat_100g", sugars = "sugars_100g", proteins = "proteins_100g", salt = "salt_100g" } }
            let product_name: String?; let brands: String?; let nutriscore_grade: String?; let ingredients_text: String?; let allergens: String?; let nutriments: Besin?
        }
        let status: Int?; let product: Urun?
    }
    private func urun(_ a: Arguments) async throws -> String {
        let kod = (a.barkod ?? a.sorgu ?? "").filter(\.isNumber); guard (8...14).contains(kod.count) else { return "8–14 haneli EAN/UPC barkodu gerekli. Kamera ile barkodu okutabilir veya numarayı yazabilirsin." }
        var c = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(kod).json")!; c.queryItems = [.init(name: "fields", value: "code,product_name,brands,nutriscore_grade,ingredients_text,allergens,nutriments")]
        let r = try await YasamServisiOnbellegi.ortak.getir(hizmet: "Open Food Facts", istek: URLRequest(url: c.url!), tazelik: 7 * 86_400, bayatSiniri: 30 * 86_400)
        let y = try JSONDecoder().decode(UrunYaniti.self, from: r.veri); guard y.status == 1, let u = y.product else { return "\(kod) barkodlu ürün Open Food Facts'ta bulunamadı. Veritabanı topluluk katkılı olduğu için ürün eksik olabilir." }
        let b = u.nutriments; var s = "\(u.product_name ?? "Ürün")" + (u.brands.map { " · \($0)" } ?? "") + ". Nutri-Score: \(u.nutriscore_grade?.uppercased() ?? "yok")."
        s += " 100 g için: \(b?.energyKcal.map { "\(Int($0.rounded())) kcal" } ?? "enerji —"), yağ \(Self.gram(b?.fat)), şeker \(Self.gram(b?.sugars)), protein \(Self.gram(b?.proteins)), tuz \(Self.gram(b?.salt))."
        if let al = u.allergens, !al.isEmpty { s += " Bildirilen alerjenler: \(al)." }; if let ic = u.ingredients_text, !ic.isEmpty { s += " İçindekiler: \(String(ic.prefix(700)))." }
        return s + " Bu veri üretici etiketi yerine geçmez; paket üzerindeki alerjen bilgisini doğrula." + Self.kaynakNotu(r, kaynak: "Open Food Facts · https://world.openfoodfacts.org/product/\(kod)")
    }
    static func gram(_ d: Double?) -> String { d.map { String(format: "%.1f g", $0) } ?? "—" }

    struct WikiYaniti: Decodable, Sendable { struct Sorgu: Decodable, Sendable { let pages: [String: Sayfa]? }; struct Sayfa: Decodable, Sendable { let title: String; let extract: String?; let fullurl: String? }; let query: Sorgu? }
    private func bilgi(_ a: Arguments) async throws -> String {
        guard let q = a.sorgu?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return "Aranacak kişi, yer, eser veya kavram gerekli." }
        var c = URLComponents(string: "https://tr.wikipedia.org/w/api.php")!; c.queryItems = [.init(name: "action", value: "query"), .init(name: "generator", value: "search"), .init(name: "gsrsearch", value: q), .init(name: "gsrlimit", value: "3"), .init(name: "prop", value: "extracts|info"), .init(name: "exintro", value: "1"), .init(name: "explaintext", value: "1"), .init(name: "inprop", value: "url"), .init(name: "format", value: "json")]
        let r = try await YasamServisiOnbellegi.ortak.getir(hizmet: "Wikimedia", istek: URLRequest(url: c.url!), tazelik: 24 * 3600)
        let sayfalar = try JSONDecoder().decode(WikiYaniti.self, from: r.veri).query?.pages?.values.sorted { $0.title < $1.title } ?? []; guard let ilk = sayfalar.first else { return "Wikipedia'da '\(q)' için sonuç bulunamadı." }
        var s = "\(ilk.title): \(String((ilk.extract ?? "Özet bulunamadı.").prefix(1800)))\nKaynak: \(ilk.fullurl ?? "https://tr.wikipedia.org")"; let ek = sayfalar.dropFirst().map(\.title); if !ek.isEmpty { s += "\nDiğer olası başlıklar: " + ek.joined(separator: ", ") }; return s + Self.kaynakNotu(r, kaynak: "Wikimedia")
    }

    struct TurYaniti: Decodable, Sendable { let usageKey: Int?; let scientificName: String?; let canonicalName: String?; let rank: String?; let status: String?; let kingdom: String?; let phylum: String?; let `class`: String?; let order: String?; let family: String?; let genus: String? }
    struct GozlemYaniti: Decodable, Sendable { struct Gozlem: Decodable, Sendable { let scientificName: String?; let locality: String?; let eventDate: String?; let decimalLatitude: Double?; let decimalLongitude: Double? }; let count: Int?; let results: [Gozlem] }
    private func doga(_ a: Arguments) async throws -> String {
        guard let q = a.sorgu?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return "Türün Türkçe veya bilimsel adı gerekli." }
        var m = URLComponents(string: "https://api.gbif.org/v1/species/match")!; m.queryItems = [.init(name: "name", value: q), .init(name: "verbose", value: "true")]
        let mr = try await YasamServisiOnbellegi.ortak.getir(hizmet: "GBIF Tür", istek: URLRequest(url: m.url!), tazelik: 30 * 86_400); let tur = try JSONDecoder().decode(TurYaniti.self, from: mr.veri)
        guard let key = tur.usageKey, let bilimsel = tur.scientificName else { return "GBIF'te '\(q)' için güvenilir bir tür eşleşmesi bulunamadı." }
        var o = URLComponents(string: "https://api.gbif.org/v1/occurrence/search")!; o.queryItems = [.init(name: "taxon_key", value: String(key)), .init(name: "country", value: "TR"), .init(name: "limit", value: "8")]
        let or = try await YasamServisiOnbellegi.ortak.getir(hizmet: "GBIF Gözlem", istek: URLRequest(url: o.url!), tazelik: 24 * 3600); let goz = try JSONDecoder().decode(GozlemYaniti.self, from: or.veri)
        let sinif = [tur.kingdom, tur.phylum, tur.class, tur.order, tur.family, tur.genus].compactMap { $0 }.joined(separator: " › "); var s = "\(bilimsel)" + (tur.rank.map { " · \($0)" } ?? "") + (tur.status.map { " · \($0)" } ?? "") + ".\nSınıflandırma: \(sinif.isEmpty ? "—" : sinif). Türkiye'deki kayıt sayısı: \(goz.count ?? 0)."
        if !goz.results.isEmpty { s += "\nSon örnek kayıtlar:\n" + goz.results.prefix(5).map { "• \($0.locality ?? "Yer belirtilmemiş") · \(($0.eventDate ?? "tarih yok").prefix(10))" }.joined(separator: "\n") }; return s + "\nTür sayfası: https://www.gbif.org/species/\(key)" + Self.kaynakNotu(or.bayat ? or : mr, kaynak: "GBIF")
    }

    struct MakaleYaniti: Decodable, Sendable { struct Makale: Decodable, Sendable { struct Yazarlik: Decodable, Sendable { struct Yazar: Decodable, Sendable { let display_name: String? }; let author: Yazar }; let id: String; let doi: String?; let display_name: String; let publication_year: Int?; let cited_by_count: Int?; let authorships: [Yazarlik] }; let results: [Makale] }
    private func makale(_ a: Arguments) async throws -> String {
        guard let q = a.sorgu?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return "Makale konusu gerekli." }
        var c = URLComponents(string: "https://api.openalex.org/works")!; c.queryItems = [.init(name: "search", value: q), .init(name: "per-page", value: "8"), .init(name: "sort", value: "relevance_score:desc")]
        let r = try await YasamServisiOnbellegi.ortak.getir(hizmet: "OpenAlex", istek: URLRequest(url: c.url!), tazelik: 24 * 3600); let l = try JSONDecoder().decode(MakaleYaniti.self, from: r.veri).results; guard !l.isEmpty else { return "OpenAlex'te '\(q)' için yayın bulunamadı." }
        let satirlar = l.prefix(8).map { m in [m.display_name, m.authorships.prefix(3).compactMap { $0.author.display_name }.joined(separator: ", "), m.publication_year.map(String.init) ?? "—", String(m.cited_by_count ?? 0), m.doi ?? m.id] }
        await MainActor.run { EkDefteri.ortak.ekle(MesajEki(tur: .tablo(baslik: "Akademik yayınlar · \(q)", sutunlar: ["Başlık", "Yazar", "Yıl", "Atıf", "Bağlantı"], satirlar: satirlar, kaynak: "https://openalex.org", dosya: nil))) }
        return "OpenAlex'te '\(q)' için \(l.count) ilgili yayın bulundu; ilk 8 yayın tabloda. Atıf sayısı kalite hükmü değildir; yöntem ve örneklem ayrıca incelenmelidir." + Self.kaynakNotu(r, kaynak: "OpenAlex · https://docs.openalex.org")
    }

    private func sabahOzeti(_ a: Arguments) async throws -> String {
        async let hava = HavaAraci().call(arguments: .init(yer: a.yer)); async let saglik = saglikHavasi(a); let etkinlikler = Self.bugununTakvimi()
        var s = "Günaydın.\nTakvim: " + (etkinlikler.isEmpty ? "Bugün etkinlik görünmüyor veya takvim izni kapalı." : etkinlikler.joined(separator: "; "))
        s += "\nHava: \((try? await hava) ?? "alınamadı")\nSağlık havası: \((try? await saglik) ?? "alınamadı")"
        return s
    }
    static func bugununTakvimi(simdi: Date = .now) -> [String] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }; let d = EKEventStore(), bas = Calendar.current.startOfDay(for: simdi), bit = Calendar.current.date(byAdding: .day, value: 1, to: bas)!; let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"
        return d.events(matching: d.predicateForEvents(withStart: bas, end: bit, calendars: nil)).sorted { $0.startDate < $1.startDate }.prefix(8).map { "\($0.isAllDay ? "tüm gün" : f.string(from: $0.startDate)) \($0.title ?? "Etkinlik")" }
    }
    private func hizmetDurumu() async -> String { let l = await YasamServisiOnbellegi.ortak.durumListesi(); guard !l.isEmpty else { return "Henüz yaşam servisi çağrılmadı; durum kaydı yok." }; return "Hizmet durumu:\n" + l.map { d in "• \(d.hizmet): " + (d.hata == nil ? "çalışıyor" : "son çağrı hatalı") + (d.sonBasari.map { "; son başarı \(Self.tarih($0.timeIntervalSince1970))" } ?? "; henüz başarı yok") + (d.hata.map { "; \($0)" } ?? "") }.joined(separator: "\n") }
    static func kaynakNotu(_ r: YasamServisiOnbellegi.Sonuc, kaynak: String) -> String { "\nKaynak: \(kaynak). " + (r.bayat ? "Ağ yanıt vermedi; son doğrulanmış önbellek: " : "Alınma zamanı: ") + tarih(r.zaman.timeIntervalSince1970) + "." }
    static func tarih(_ saniye: Double) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM yyyy HH:mm"; return f.string(from: Date(timeIntervalSince1970: saniye)) }
    static func gunOnce(_ gun: Int) -> String { let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f.string(from: Date().addingTimeInterval(-Double(gun) * 86_400)) }
}
